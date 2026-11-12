#!/usr/bin/env python3
"""make_super.py -- 纯 Python 的 lpmake 替代品：把若干分区镜像重建成 Android 动态分区 super.img

完全可用的 v1 实现:
  - 每个分区 1 个 LINEAR extent，按命令行顺序连续分配
  - 分区起始按 --alignment（默认 1MiB / 2048 扇区）对齐
  - 支持多 group（default/main_a/main_b...），写入 group 的 maximum_size
  - block_devices 表项与 rothko 现网一致（64 字节: fls, align, size, name[36], flags）
  - metadata v10.2 / header_size 256 / geometry+header+tables 三个 SHA256 全部正确
  - 两种布局:
      standard : geometry@0        metadata@4096                        (AOSP 标准)
      mtk      : 4KB 0 + geometry@4096 + 副本@8192 + metadata@12288    (rothko 现网布局)
  - --metadata-only 只写元数据（快速验证/对比，可秒级完成）

用法示例:
  python make_super.py -o super_mini.img --device-size 64MiB --layout mtk \
    --group main_a:32MiB --group main_b:32MiB \
    --partition system_a:main_a:ro:system_a.img \
    --partition odm_b:main_b:ro:-

验证: python lp_tool.py dump super_mini.img -v
"""
import argparse
import hashlib
import os
import struct
import sys

SECTOR = 512
GEOMETRY_MAGIC = 0x616C4467
METADATA_MAGIC = 0x414C5030
GEOMETRY_SIZE = 4096
HEADER_SIZE_V2 = 256

ATTR_READONLY = 0x1
ATTR_SLOT_SUFFIXED = 0x2
ATTR_UPDATED = 0x4
ATTR_DISABLED = 0x8

HEADER_FLAG_VIRTUAL_AB = 0x1


def parse_size(s):
    s = str(s).strip().lower()
    mult = 1
    for suf, m in (("kib", 1 << 10), ("mib", 1 << 20), ("gib", 1 << 30),
                   ("kb", 1000), ("mb", 10 ** 6), ("gb", 10 ** 9),
                   ("k", 1 << 10), ("m", 1 << 20), ("g", 1 << 30), ("b", 1)):
        if s.endswith(suf):
            mult = m
            s = s[: -len(suf)]
            break
    return int(float(s) * mult)


def human(n):
    n = float(n)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(n) < 1024.0:
            return "%.2f %s" % (n, unit)
        n /= 1024.0
    return "%.2f PiB" % n


def sha256_zeroed(buf, csum_off, csum_len, total):
    b = bytearray(buf[:total])
    b[csum_off:csum_off + csum_len] = b"\x00" * csum_len
    return hashlib.sha256(bytes(b)).digest()


def build_geometry(metadata_max_size, slot_count, logical_block_size):
    g = bytearray(GEOMETRY_SIZE)
    struct.pack_into("<I", g, 0, GEOMETRY_MAGIC)
    struct.pack_into("<I", g, 4, 52)
    struct.pack_into("<III", g, 40, metadata_max_size, slot_count, logical_block_size)
    struct.pack_into("<32s", g, 8, sha256_zeroed(g, 8, 32, 52))
    return bytes(g)


def build_block_device(size_bytes, first_logical_sector, alignment, name):
    """64 字节 block device 表项（与 rothko 现网一致）:
       u64 first_logical_sector | u64 alignment | u64 size | char name[36] | u32 flags"""
    raw = bytearray(64)
    struct.pack_into("<QQQ", raw, 0, first_logical_sector, alignment, size_bytes)
    nb = name.encode()[:36]
    raw[24:24 + len(nb)] = nb
    struct.pack_into("<I", raw, 60, 0)
    return bytes(raw)


def build_metadata(groups, partitions, block_devices, header_flags):
    """groups: [(name, max_size, flags)]
       partitions: [(name, attrs, group_index, [(target_sector, num_sectors)])]
       block_devices: [raw bytes]"""
    parts_tbl = bytearray()
    for name, attrs, gidx, extents in partitions:
        raw = bytearray(52)
        nb = name.encode()[:36]
        raw[0:len(nb)] = nb
        struct.pack_into("<IIII", raw, 36, attrs, 0, len(extents), gidx)
        parts_tbl += raw
    ext_tbl = bytearray()
    for name, attrs, gidx, extents in partitions:
        for tgt, nsec in extents:
            ext_tbl += struct.pack("<QIQI", nsec, 0, tgt, 0)
    grp_tbl = bytearray()
    for name, max_size, gflags in groups:
        raw = bytearray(48)
        nb = name.encode()[:36]
        raw[0:len(nb)] = nb
        struct.pack_into("<IQ", raw, 36, gflags, max_size)
        grp_tbl += raw
    bdev_tbl = b"".join(block_devices)

    ext_idx = 0
    for i, (name, attrs, gidx, extents) in enumerate(partitions):
        struct.pack_into("<I", parts_tbl, i * 52 + 40, ext_idx)
        ext_idx += len(extents)

    tables = bytes(parts_tbl + ext_tbl + grp_tbl + bdev_tbl)
    part_off = 0
    ext_off = len(parts_tbl)
    grp_off = ext_off + len(ext_tbl)
    bdev_off = grp_off + len(grp_tbl)

    hdr = bytearray(HEADER_SIZE_V2)
    struct.pack_into("<IHHI", hdr, 0, METADATA_MAGIC, 10, 2, HEADER_SIZE_V2)
    struct.pack_into("<I", hdr, 44, len(tables))
    struct.pack_into("<III", hdr, 80, part_off, len(partitions), 52)
    struct.pack_into("<III", hdr, 92, ext_off, ext_idx, 24)
    struct.pack_into("<III", hdr, 104, grp_off, len(groups), 48)
    struct.pack_into("<III", hdr, 116, bdev_off, len(block_devices), 64)
    struct.pack_into("<I", hdr, 128, header_flags)
    struct.pack_into("<32s", hdr, 48, hashlib.sha256(tables).digest())
    struct.pack_into("<32s", hdr, 12, sha256_zeroed(hdr, 12, 32, HEADER_SIZE_V2))
    return bytes(hdr) + tables


def build_super(out_path, device_size, partition_specs, group_specs, layout="standard",
                metadata_slots=3, metadata_max_size=65536, logical_block_size=4096,
                alignment=1048576, first_logical_sector=2048,
                header_flags=HEADER_FLAG_VIRTUAL_AB, verbose=True, metadata_only=False):
    # 1) groups（default 组总是存在且排第一）
    groups = [("default", 0, 0)]
    for spec in group_specs:
        parts = spec.split(":")
        name = parts[0]
        max_size = parse_size(parts[1]) if len(parts) > 1 and parts[1] else 0
        flags = int(parts[2]) if len(parts) > 2 and parts[2] else 0
        if name == "default":
            groups[0] = ("default", max_size, flags)
            continue
        groups.append((name, max_size, flags))
    name_to_gidx = {g[0]: i for i, g in enumerate(groups)}

    # 2) 布局计算
    align_sectors = alignment // SECTOR
    cursor = first_logical_sector
    partitions = []
    plan = []
    for spec in partition_specs:
        name, gname, attr, img = spec.split(":", 3)
        if gname not in name_to_gidx:
            raise SystemExit("partition %s references unknown group %s (defined: %s)"
                             % (name, gname, list(name_to_gidx)))
        gidx = name_to_gidx[gname]
        attrs = 0
        for a in attr.split(","):
            a = a.strip().lower()
            if a in ("ro", "readonly"):
                attrs |= ATTR_READONLY
            elif a in ("rw", "readwrite", "", "-"):
                pass
            elif a == "slot":
                attrs |= ATTR_SLOT_SUFFIXED
            elif a == "disabled":
                attrs |= ATTR_DISABLED
            else:
                raise SystemExit("unknown attribute: %s" % a)
        if img in ("-", "", "none"):
            size = 0
            img = None
        else:
            if not os.path.exists(img):
                raise SystemExit("partition image not found: %s" % img)
            size = os.path.getsize(img)
        extents = []
        if size > 0:
            cursor = ((cursor + align_sectors - 1) // align_sectors) * align_sectors
            nsec = (size + SECTOR - 1) // SECTOR
            extents.append((cursor, nsec))
            cursor += nsec
        partitions.append((name, attrs, gidx, extents))
        plan.append({"name": name, "group": gname, "image": img, "size": size, "extents": extents})

    data_end = cursor * SECTOR
    if data_end > device_size:
        raise SystemExit("partitions exceed device-size: need %d (%s), given %d (%s)"
                         % (data_end, human(data_end), device_size, human(device_size)))

    bdev = build_block_device(device_size, first_logical_sector, alignment, "super")
    metadata = build_metadata(groups, partitions, [bdev], header_flags)
    if len(metadata) > metadata_max_size:
        raise SystemExit("metadata exceeds metadata_max_size: %d > %d" % (len(metadata), metadata_max_size))
    geometry = build_geometry(metadata_max_size, metadata_slots, logical_block_size)

    if layout == "standard":
        geo_off = 0
        meta_off = GEOMETRY_SIZE
    elif layout == "mtk":
        geo_off = GEOMETRY_SIZE
        meta_off = 3 * GEOMETRY_SIZE
    else:
        raise SystemExit("unknown layout: %s" % layout)

    if verbose:
        print("[make] layout=%s device_size=%d (%s) geo@%d meta@%d slots=%d metadata_only=%s"
              % (layout, device_size, human(device_size), geo_off, meta_off, metadata_slots, metadata_only))
        for p in plan:
            if p["size"]:
                print("  %-14s group=%-8s size=%-12d (%s) extent=%s"
                      % (p["name"], p["group"], p["size"], human(p["size"]),
                         ["%d+%d" % e for e in p["extents"]]))
            else:
                print("  %-14s group=%-8s EMPTY" % (p["name"], p["group"]))
        print("  data region: %d .. %d (first_logical_sector=%d, alignment=%d)"
              % (first_logical_sector * SECTOR, data_end, first_logical_sector, alignment))

    with open(out_path, "wb") as f:
        f.truncate(device_size)
        if layout == "mtk":
            f.seek(GEOMETRY_SIZE)
            f.write(geometry)          # 4096
            f.write(geometry)          # 8192 副本（rothko 现网如此）
        else:
            f.seek(0)
            f.write(geometry)
        for n in range(metadata_slots):
            f.seek(meta_off + n * metadata_max_size)
            f.write(metadata)
        total_written = 0
        if not metadata_only:
            for p in plan:
                if not p["image"]:
                    continue
                tgt = p["extents"][0][0] * SECTOR
                f.seek(tgt)
                with open(p["image"], "rb") as src:
                    while True:
                        b = src.read(8 << 20)
                        if not b:
                            break
                        f.write(b)
                        total_written += len(b)
    if verbose:
        print("[make] wrote %s: %d bytes, data %d bytes (%s)"
              % (out_path, os.path.getsize(out_path), total_written, human(total_written)))
    return {"path": out_path, "size": os.path.getsize(out_path), "layout": layout,
            "geo_offset": geo_off, "metadata_offset": meta_off,
            "partitions": plan, "data_end": data_end, "groups": groups}


def main():
    ap = argparse.ArgumentParser(description="Python lpmake: rebuild Android super.img")
    ap.add_argument("-o", "--output", required=True)
    ap.add_argument("--device-size", required=True, help="super partition size in bytes (e.g. 9GiB)")
    ap.add_argument("--partition", action="append", default=[],
                    help="name:group:attrs:image (attrs=ro/rw/slot/disabled/-; empty partition uses -)")
    ap.add_argument("--group", action="append", default=[], help="name:maximum_size[:flags]")
    ap.add_argument("--layout", choices=("standard", "mtk"), default="standard")
    ap.add_argument("--metadata-slots", type=int, default=3)
    ap.add_argument("--metadata-max-size", type=int, default=65536)
    ap.add_argument("--logical-block-size", type=int, default=4096)
    ap.add_argument("--alignment", default="1MiB")
    ap.add_argument("--first-logical-sector", type=int, default=2048)
    ap.add_argument("--header-flags", type=lambda s: int(s, 0), default=HEADER_FLAG_VIRTUAL_AB)
    ap.add_argument("--metadata-only", action="store_true",
                    help="only write geometry+metadata (skip partition data) for fast validation")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    build_super(args.output, parse_size(args.device_size), args.partition, args.group,
                layout=args.layout, metadata_slots=args.metadata_slots,
                metadata_max_size=args.metadata_max_size,
                logical_block_size=args.logical_block_size,
                alignment=parse_size(args.alignment),
                first_logical_sector=args.first_logical_sector,
                header_flags=args.header_flags, verbose=not args.quiet,
                metadata_only=args.metadata_only)


if __name__ == "__main__":
    main()
