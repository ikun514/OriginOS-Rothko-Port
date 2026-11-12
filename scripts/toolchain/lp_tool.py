#!/usr/bin/env python3
"""lp_tool.py -- 纯 Python 实现的 Android 动态分区 (liblp) 解析/解包工具。

子命令:
  dump   <super.img> [--json out.json] [--slot 0] [-v]   解析并打印 LP 元数据
  unpack <super.img> -o outdir [--partitions system_a,vendor_a] [--base auto|N]
                                                         按 extent 提取 logical 分区为 raw 镜像
  make   (见 make_super.py)

支持的镜像:
  - raw super.img (liblp)
  - Android sparse (magic 0xED26FF3A)

布局自动探测（兼容本项目 Redmi K70 Ultra 的非标准布局）:
  标准:   geometry@0      metadata@4096                  data 绝对扇区从 0 起
  本机型: 4KB 0 + geometry@4096 + geometry 副本@8192 + metadata@12288, data 仍从 0 起
  通过"分区首 extent 处的文件系统 magic"对候选 base 打分，自动选中正确 base。

表偏移语义: table_descriptor.offset 相对 header 结束位置（即 header_size）计算。

只依赖 Python 3 标准库。
"""
import argparse
import hashlib
import json
import os
import struct
import sys

LP_PARTITION_RESERVED_BYTES = 4096
LP_METADATA_GEOMETRY_SIZE = 4096
GEOMETRY_MAGIC = 0x616C4467
METADATA_MAGIC = 0x414C5030
SECTOR = 512

SPARSE_MAGIC = 0xED26FF3A
CHUNK_RAW = 0xCAC1
CHUNK_FILL = 0xCAC2
CHUNK_DONT_CARE = 0xCAC3
CHUNK_CRC32 = 0xCAC4

ATTR_READONLY = 0x1
ATTR_SLOT_SUFFIXED = 0x2
ATTR_UPDATED = 0x4
ATTR_DISABLED = 0x8
GROUP_SLOT_SUFFIXED = 0x1

FS_MAGICS = {
    b"\xe2\xe1\xf5\xe0": ("erofs", 1024),
    b"\x10\x20\xf5\xf2": ("f2fs", 1024),
}


class SparseError(Exception):
    pass


class RawReader:
    def __init__(self, path):
        self.f = open(path, "rb")
        self.size = os.fstat(self.f.fileno()).st_size

    def read_at(self, offset, n):
        self.f.seek(offset)
        return self.f.read(n)

    def close(self):
        self.f.close()


class SparseReader:
    """Android sparse image -> raw 视图"""

    def __init__(self, path):
        self.f = open(path, "rb")
        hdr = self.f.read(28)
        (self.magic, self.major, self.minor, self.file_hdr_sz, self.chunk_hdr_sz,
         self.blk_sz, self.total_blks, self.total_chunks, self.image_checksum) = struct.unpack("<IHHHHIIII", hdr)
        if self.magic != SPARSE_MAGIC:
            raise SparseError("bad sparse magic %#x" % self.magic)
        self.size = self.total_blks * self.blk_sz
        self.chunks = []
        off = self.file_hdr_sz
        cur = 0
        for _ in range(self.total_chunks):
            self.f.seek(off)
            chdr = self.f.read(self.chunk_hdr_sz)
            ctype, _res, csize, ctotal = struct.unpack("<HHII", chdr[:12])
            data_off = off + self.chunk_hdr_sz
            self.chunks.append((ctype, cur, ctotal * self.blk_sz, data_off))
            cur += ctotal * self.blk_sz
            if ctype == CHUNK_RAW:
                off = data_off + csize - self.chunk_hdr_sz
            elif ctype in (CHUNK_FILL, CHUNK_DONT_CARE):
                off = data_off
            else:
                raise SparseError("unsupported chunk type %#x" % ctype)

    def _find(self, pos):
        lo, hi = 0, len(self.chunks) - 1
        while lo <= hi:
            mid = (lo + hi) // 2
            ctype, start, length, data_off = self.chunks[mid]
            if start <= pos < start + length:
                return self.chunks[mid]
            if pos < start:
                hi = mid - 1
            else:
                lo = mid + 1
        return None

    def read_at(self, offset, n):
        out = bytearray()
        pos = offset
        while n > 0:
            ch = self._find(pos)
            if ch is None:
                nxt = min((c[1] for c in self.chunks if c[1] > pos), default=None)
                gap = n if nxt is None else min(n, nxt - pos)
                out += b"\x00" * gap
                pos += gap
                n -= gap
                continue
            ctype, start, length, data_off = ch
            avail = min(n, start + length - pos)
            if ctype == CHUNK_RAW:
                self.f.seek(data_off + (pos - start))
                out += self.f.read(avail)
            elif ctype == CHUNK_FILL:
                self.f.seek(data_off)
                fill = self.f.read(4)
                out += fill * (avail // 4) + fill[: avail % 4]
            else:
                out += b"\x00" * avail
            pos += avail
            n -= avail
        return bytes(out)

    def close(self):
        self.f.close()


def open_image(path):
    with open(path, "rb") as f:
        head = f.read(4)
    if len(head) == 4 and struct.unpack("<I", head)[0] == SPARSE_MAGIC:
        return SparseReader(path), "sparse"
    return RawReader(path), "raw"


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


def parse_geometry(blob):
    magic, struct_size = struct.unpack("<II", blob[:8])
    checksum = blob[8:40]
    metadata_max_size, metadata_slot_count, logical_block_size = struct.unpack("<III", blob[40:52])
    ok = False
    if magic == GEOMETRY_MAGIC and 52 <= struct_size <= LP_METADATA_GEOMETRY_SIZE:
        ok = sha256_zeroed(blob, 8, 32, struct_size) == checksum
    return {
        "offset": None,
        "magic": "0x%08x" % magic,
        "magic_ok": magic == GEOMETRY_MAGIC,
        "struct_size": struct_size,
        "checksum_ok": ok,
        "metadata_max_size": metadata_max_size,
        "metadata_slot_count": metadata_slot_count,
        "logical_block_size": logical_block_size,
    }


def parse_block_device(raw, entry_size):
    """返回 (first_logical_sector, alignment, size, name, flags, layout_name)
    兼容: 64B (本机型/AOSP 变体: fls,align,size,name36,flags)
          68B (packed: fls,align,align_off,size,name36,flags)
          72B (padded: fls,align,align_off,pad,size,name32,flags)"""
    if entry_size == 64:
        fls, al, size = struct.unpack("<QQQ", raw[:24])
        name = raw[24:60]
        flags = struct.unpack("<I", raw[60:64])[0]
        return fls, al, None, size, name, flags, "64"
    if entry_size == 68:
        fls, al, ao, size = struct.unpack("<QQIQ", raw[:28])
        name = raw[28:64]
        flags = struct.unpack("<I", raw[64:68])[0]
        return fls, al, ao, size, name, flags, "68"
    if entry_size == 72:
        fls, al, ao = struct.unpack("<QQI", raw[:20])
        size = struct.unpack("<Q", raw[24:32])[0]
        name = raw[32:68]
        flags = struct.unpack("<I", raw[68:72])[0]
        return fls, al, ao, size, name, flags, "72"
    fls, al, ao, size = struct.unpack("<QQIQ", raw[:28])
    name = raw[28:64]
    flags = 0
    return fls, al, ao, size, name, flags, "unk%02x" % entry_size


def parse_metadata(blob, meta_offset):
    magic, major, minor, header_size, header_checksum, tables_size, tables_checksum = \
        struct.unpack("<IHHI32sI32s", blob[:80])
    if magic != METADATA_MAGIC:
        return None
    calc_h = sha256_zeroed(blob, 12, 32, header_size)
    tables_off = header_size
    calc_t = hashlib.sha256(blob[tables_off:tables_off + tables_size]).digest()

    def desc(pos):
        return struct.unpack("<III", blob[pos:pos + 12])

    parts_t, ext_t, grp_t, bdev_t = desc(80), desc(92), desc(104), desc(116)
    flags = struct.unpack("<I", blob[128:132])[0] if header_size >= 132 else 0
    meta = {
        "metadata_offset": meta_offset,
        "magic": "0x%08x" % magic,
        "major_version": major,
        "minor_version": minor,
        "header_size": header_size,
        "header_checksum_ok": calc_h == header_checksum,
        "tables_size": tables_size,
        "tables_checksum_ok": calc_t == tables_checksum,
        "flags": flags,
        "table_descriptors": {
            "partitions": dict(zip(("offset", "num_entries", "entry_size"), parts_t)),
            "extents": dict(zip(("offset", "num_entries", "entry_size"), ext_t)),
            "groups": dict(zip(("offset", "num_entries", "entry_size"), grp_t)),
            "block_devices": dict(zip(("offset", "num_entries", "entry_size"), bdev_t)),
        },
    }

    def at(d, i):
        return tables_off + d["offset"] + i * d["entry_size"]

    extents = []
    for i in range(ext_t[1]):
        off = at(meta["table_descriptors"]["extents"], i)
        num_sectors, target_type, target_data, target_source = struct.unpack("<QIQI", blob[off:off + 24])
        extents.append({
            "index": i,
            "num_sectors": num_sectors,
            "size_bytes": num_sectors * SECTOR,
            "target_type": target_type,
            "target_type_name": {0: "LINEAR", 1: "ZERO"}.get(target_type, "UNKNOWN"),
            "target_data": target_data,
            "target_source": target_source,
        })

    groups = []
    for i in range(grp_t[1]):
        off = at(meta["table_descriptors"]["groups"], i)
        name, gflags, max_size = struct.unpack("<36sIQ", blob[off:off + 48])
        groups.append({
            "index": i, "name": name.rstrip(b"\x00").decode("utf-8", "replace"),
            "flags": gflags, "slot_suffixed": bool(gflags & GROUP_SLOT_SUFFIXED),
            "maximum_size": max_size, "maximum_size_human": human(max_size),
        })

    bdevs = []
    for i in range(bdev_t[1]):
        off = at(meta["table_descriptors"]["block_devices"], i)
        es = bdev_t[2]
        fls, al, ao, size, name, flags2, layout = parse_block_device(blob[off:off + es], es)
        bdevs.append({
            "index": i, "entry_size": es, "layout": layout,
            "first_logical_sector": fls, "alignment": al, "alignment_offset": ao,
            "size": size, "size_human": human(size),
            "partition_name": name.rstrip(b"\x00").decode("utf-8", "replace"), "flags": flags2,
        })

    partitions = []
    for i in range(parts_t[1]):
        off = at(meta["table_descriptors"]["partitions"], i)
        name = blob[off:off + 36]
        attributes, fei, num_ext, group_index = struct.unpack("<IIII", blob[off + 36:off + 52])
        plist = extents[fei:fei + num_ext]
        total = sum(e["num_sectors"] for e in plist)
        partitions.append({
            "index": i,
            "name": name.rstrip(b"\x00").decode("utf-8", "replace"),
            "attributes": attributes,
            "attributes_decoded": decode_attrs(attributes),
            "first_extent_index": fei, "num_extents": num_ext,
            "group_index": group_index,
            "group_name": groups[group_index]["name"] if group_index < len(groups) else "?",
            "total_sectors": total, "size": total * SECTOR, "size_human": human(total * SECTOR),
            "extents": plist,
        })
    meta["block_devices"] = bdevs
    meta["groups"] = groups
    meta["extents"] = extents
    meta["partitions"] = partitions
    return meta


def decode_attrs(a):
    out = []
    if a & ATTR_READONLY:
        out.append("READONLY")
    if a & ATTR_SLOT_SUFFIXED:
        out.append("SLOT_SUFFIXED")
    if a & ATTR_UPDATED:
        out.append("UPDATED")
    if a & ATTR_DISABLED:
        out.append("DISABLED")
    return out


def probe_fs_magic(reader, offset):
    """在 offset 处探测文件系统类型（erofs 在 +1024, ext4 在 +1080）"""
    try:
        head = reader.read_at(offset, 4096)
    except Exception:
        return None
    if len(head) < 2048:
        return None
    for magic, (name, off) in FS_MAGICS.items():
        if head[off:off + 4] == magic:
            return name
    if head[1080:1082] == b"\x53\xef":
        return "ext4"
    return None


def find_layout(path, slot=0, verbose=False):
    """自动探测 geometry 偏移、metadata 偏移、分区数据 base。"""
    reader, kind = open_image(path)
    probe = reader.read_at(0, 1 << 20)
    geo_hits = []
    i = probe.find(struct.pack("<I", GEOMETRY_MAGIC))
    while i != -1:
        geo_hits.append(i)
        i = probe.find(struct.pack("<I", GEOMETRY_MAGIC), i + 1)
    if not geo_hits:
        reader.close()
        raise SystemExit("不是 LP super 镜像（找不到 geometry magic）: %s" % path)

    candidates = []
    for g in geo_hits:
        geo = parse_geometry(probe[g:g + LP_METADATA_GEOMETRY_SIZE])
        if not geo["checksum_ok"]:
            continue
        geo = dict(geo, offset=g)
        # metadata 可能紧跟在 geometry 后（标准 4096），也可能是 8192（本机型 8KB geometry 区）
        for delta in (LP_METADATA_GEOMETRY_SIZE, 2 * LP_METADATA_GEOMETRY_SIZE):
            moff = g + delta + (slot * geo["metadata_max_size"])
            blob = reader.read_at(moff, geo["metadata_max_size"])
            if len(blob) < 256 or struct.unpack("<I", blob[:4])[0] != METADATA_MAGIC:
                continue
            meta = parse_metadata(blob, moff)
            if meta and meta["header_checksum_ok"] and meta["tables_checksum_ok"]:
                candidates.append({"geometry": geo, "metadata": meta, "geometry_offset": g})

    if not candidates:
        reader.close()
        raise SystemExit("找到 geometry 但无法解析出有效 metadata（校验失败）: %s" % path)

    best = None
    for cand in candidates:
        meta = cand["metadata"]
        # 数据 base 候选
        base_scores = {}
        for base in (0, cand["geometry_offset"], 4096, 8192):
            score = 0
            for p in meta["partitions"]:
                lin = [e for e in p["extents"] if e["target_type"] == 0]
                if not lin:
                    continue
                off = base + lin[0]["target_data"] * SECTOR
                if off + 4096 > reader.size:
                    continue
                if probe_fs_magic(reader, off):
                    score += 1
            base_scores[base] = score
        best_base = max(base_scores, key=lambda b: (base_scores[b], -b))
        cand["base_scores"] = base_scores
        cand["data_base"] = best_base
        cand["data_base_score"] = base_scores[best_base]
        if verbose:
            print("[layout] geometry@%d metadata@%d base_scores=%s -> base=%d (score=%d)"
                  % (cand["geometry_offset"], meta["metadata_offset"], base_scores, best_base, base_scores[best_base]))
        if best is None or cand["data_base_score"] > best["data_base_score"]:
            best = cand

    reader.close()
    meta = best["metadata"]
    # 一致性检查
    overflow = []
    for p in meta["partitions"]:
        for e in p["extents"]:
            if e["target_type"] == 0:
                end = best["data_base"] + (e["target_data"] + e["num_sectors"]) * SECTOR
                if end > reader.size:
                    overflow.append({"partition": p["name"], "end": end, "file_size": reader.size})
    res = {
        "file": os.path.abspath(path),
        "file_size": reader.size,
        "file_size_human": human(reader.size),
        "container": kind,
        "slot": slot,
        "layout": {
            "geometry_offset": best["geometry_offset"],
            "metadata_offset": meta["metadata_offset"],
            "data_base": best["data_base"],
            "data_base_scores": best["base_scores"],
            "note": "非标准布局" if best["geometry_offset"] != 0 or best["data_base"] != 0 else "标准 liblp 布局",
        },
        "geometry": best["geometry"],
        "metadata": meta,
        "checks": {
            "partition_data_within_file": not overflow,
            "overflow": overflow[:10],
            "sum_partition_sizes": sum(p["size"] for p in meta["partitions"]),
            "sum_partition_sizes_human": human(sum(p["size"] for p in meta["partitions"])),
            "fs_types": {},
        },
    }
    for p in meta["partitions"]:
        lin = [e for e in p["extents"] if e["target_type"] == 0]
        if not lin or p["size"] == 0:
            continue
        r2, _ = open_image(path)
        fs = probe_fs_magic(r2, best["data_base"] + lin[0]["target_data"] * SECTOR)
        r2.close()
        res["checks"]["fs_types"][p["name"]] = fs
    return res


def read_super(path, slot=0, verbose=False):
    return find_layout(path, slot=slot, verbose=verbose)


def extract_partition(img, out_path, part, data_base, verbose=False):
    reader, _ = open_image(img)
    written = 0
    with open(out_path, "wb") as out:
        for e in part["extents"]:
            if e["target_type"] == 1:
                chunk = b"\x00" * (1 << 20)
                left = e["size_bytes"]
                while left > 0:
                    n = min(left, len(chunk))
                    out.write(chunk[:n])
                    left -= n
                    written += n
                continue
            src = data_base + e["target_data"] * SECTOR
            left = e["size_bytes"]
            while left > 0:
                n = min(left, 8 << 20)
                data = reader.read_at(src, n)
                if len(data) != n:
                    raise SystemExit("short read: %s @%d want %d got %d" % (img, src, n, len(data)))
                out.write(data)
                src += n
                left -= n
                written += n
    reader.close()
    return written


def cmd_dump(args):
    res = read_super(args.image, slot=args.slot, verbose=args.verbose)
    geo, meta, lay = res["geometry"], res["metadata"], res["layout"]
    print("=" * 82)
    print("SUPER: %s" % res["file"])
    print("  container=%s  file_size=%d (%s)  slot=%d" % (res["container"], res["file_size"], res["file_size_human"], res["slot"]))
    print("  layout: geometry@%d metadata@%d data_base@%d  (%s)"
          % (lay["geometry_offset"], lay["metadata_offset"], lay["data_base"], lay["note"]))
    print("=" * 82)
    print("[geometry]")
    for k in ("offset", "magic", "magic_ok", "struct_size", "checksum_ok", "metadata_max_size",
              "metadata_slot_count", "logical_block_size"):
        print("  %-22s %s" % (k, geo[k]))
    print("[metadata header]")
    for k in ("major_version", "minor_version", "header_size", "header_checksum_ok", "tables_size",
              "tables_checksum_ok", "flags"):
        print("  %-22s %s" % (k, meta[k]))
    print("  table_descriptors:")
    for name, d in meta["table_descriptors"].items():
        print("    %-14s offset=%-6d num=%-4d entry_size=%d" % (name, d["offset"], d["num_entries"], d["entry_size"]))
    print("[block devices]")
    for b in meta["block_devices"]:
        print("  [%d] name=%-8s size=%d (%s) first_logical_sector=%d alignment=%d entry_size=%d"
              % (b["index"], b["partition_name"], b["size"], b["size_human"],
                 b["first_logical_sector"], b["alignment"], b["entry_size"]))
    print("[groups] (count=%d)" % len(meta["groups"]))
    for g in meta["groups"]:
        print("  [%d] %-12s max=%d (%s) flags=%d" % (g["index"], g["name"], g["maximum_size"],
                                                     g["maximum_size_human"], g["flags"]))
    print("[partitions] (count=%d)" % len(meta["partitions"]))
    for p in meta["partitions"]:
        fs = res["checks"]["fs_types"].get(p["name"])
        print("  [%2d] %-24s size=%-12d (%-9s) ext=%-2d grp=%-8s attrs=%-8s fs=%s"
              % (p["index"], p["name"], p["size"], p["size_human"], p["num_extents"], p["group_name"],
                 ",".join(p["attributes_decoded"]) or "-", fs or "-"))
        if args.verbose:
            for e in p["extents"]:
                print("        extent[%d] %-6s sectors=%-9d target_data=%-9d size=%-12d file_off=%d"
                      % (e["index"], e["target_type_name"], e["num_sectors"], e["target_data"],
                         e["size_bytes"], lay["data_base"] + e["target_data"] * SECTOR))
    print("[checks]")
    print("  sum_partition_sizes        = %d (%s)" % (res["checks"]["sum_partition_sizes"],
                                                     res["checks"]["sum_partition_sizes_human"]))
    print("  partition_data_within_file = %s" % res["checks"]["partition_data_within_file"])
    if res["checks"]["overflow"]:
        print("  OVERFLOW: %s" % res["checks"]["overflow"])
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(res, f, indent=2, ensure_ascii=False)
        print("\n[json] -> %s (%d bytes)" % (args.json, os.path.getsize(args.json)))
    return res


def cmd_unpack(args):
    res = read_super(args.image, slot=args.slot)
    meta, data_base = res["metadata"], res["layout"]["data_base"]
    os.makedirs(args.outdir, exist_ok=True)
    wanted = None
    if args.partitions:
        wanted = set(x.strip() for x in args.partitions.split(",") if x.strip())
    done = []
    for p in meta["partitions"]:
        if wanted and p["name"] not in wanted:
            continue
        if p["size"] == 0:
            print("[skip] %-24s size=0" % p["name"])
            continue
        out = os.path.join(args.outdir, p["name"] + ".img")
        n = extract_partition(args.image, out, p, data_base)
        h = hashlib.sha256()
        with open(out, "rb") as f:
            while True:
                b = f.read(8 << 20)
                if not b:
                    break
                h.update(b)
        fs = res["checks"]["fs_types"].get(p["name"])
        done.append({"name": p["name"], "path": out, "size": n, "sha256": h.hexdigest(), "fs": fs})
        print("[ok] %-24s %12d bytes (%-9s) fs=%-6s sha256=%s..." % (p["name"], n, human(n), fs or "?", h.hexdigest()[:16]))
    with open(os.path.join(args.outdir, "PARTITIONS.sha256"), "w", encoding="utf-8") as f:
        for d in done:
            f.write("%s  %s\n" % (d["sha256"], os.path.basename(d["path"])))
    with open(os.path.join(args.outdir, "unpack_manifest.json"), "w", encoding="utf-8") as f:
        json.dump({"source": os.path.abspath(args.image), "layout": res["layout"], "partitions": done}, f, indent=2)
    print("[done] extracted %d partitions -> %s" % (len(done), args.outdir))
    return done


def main():
    ap = argparse.ArgumentParser(description="Android liblp super 解析/解包 (纯 Python)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("dump")
    d.add_argument("image")
    d.add_argument("--json", default=None)
    d.add_argument("--slot", type=int, default=0)
    d.add_argument("-v", "--verbose", action="store_true")
    d.set_defaults(func=cmd_dump)

    u = sub.add_parser("unpack")
    u.add_argument("image")
    u.add_argument("-o", "--outdir", required=True)
    u.add_argument("--partitions", default=None)
    u.add_argument("--slot", type=int, default=0)
    u.set_defaults(func=cmd_unpack)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
