#!/usr/bin/env python3
"""erofs_info.py -- 纯 Python 解析 EROFS superblock（无需 erofs-utils），用于统计压缩算法/压缩率。

用法:
  python erofs_info.py IMG [IMG...]                # 分析独立 erofs 镜像
  python erofs_info.py --super SUPER_IMG [--json out.json]   # 分析 super 内所有 erofs 分区

EROFS superblock 位于镜像 offset 1024，字段布局见 erofs_fs.h:
  magic(4) checksum(4) feature_compat(4) blkszbits(1) sb_extslots(1) root_nid(2)
  inos(8) build_time(8) build_time_nsec(4) blocks(4) meta_blkaddr(4) xattr_blkaddr(4)
  uuid(16) volume_name(16) feature_incompat(4) available_compr_algs(2) extra_devices(2)
  devt_slotoff(2) dirblkbits(1) xattr_prefix_count(1) xattr_prefix_start(4) packed_nid(8)
"""
import json
import os
import struct
import sys

EROFS_MAGIC = 0xE0F5E1E2
SB_OFFSET = 1024

COMPAT = {0x1: "sb_csum", 0x2: "mtime", 0x4: "big_pcluster?", 0x8: "0padding?"}
COMPR_ALGS = {1: "lz4", 2: "lzma", 4: "deflate", 8: "zstd"}
INCOMPAT = {
    0x1: "zero_padding", 0x2: "compr_cfgs", 0x4: "big_pcluster", 0x8: "meta_ctx",
    0x10: "xattr_filter", 0x20: "ztailpacking", 0x40: "fragments", 0x80: "dedupe",
    0x100: "device_table", 0x200: "48bit", 0x400: "idata",
}


def decode_bits(val, table):
    return [name for bit, name in table.items() if val & bit] + (["0x%x" % val] if val and not any(val & b for b in table) else [])


def read_sb_from_buffer(buf, base=0):
    off = base + SB_OFFSET
    if len(buf) < off + 128:
        return None
    b = buf[off:off + 128]
    magic, checksum, fcompat = struct.unpack("<III", b[:12])
    if magic != EROFS_MAGIC:
        return None
    blkszbits = b[12]
    sb_extslots = b[13]
    root_nid = struct.unpack("<H", b[14:16])[0]
    inos, build_time = struct.unpack("<QQ", b[16:32])
    build_nsec, blocks, meta_blkaddr, xattr_blkaddr = struct.unpack("<IIII", b[32:48])
    uuid = b[48:64].hex()
    volume_name = b[64:80].rstrip(b"\x00").decode("utf-8", "replace")
    fincompat = struct.unpack("<I", b[80:84])[0]
    # offset 84 是 union: 有 COMPR_CFGS 时 = available_compr_algs，否则是 legacy 的 lz4_max_distance
    union_val = struct.unpack("<H", b[84:86])[0]
    if fincompat & 0x2:  # EROFS_FEATURE_INCOMPAT_COMPR_CFGS
        avail = union_val
        legacy = False
        compr_desc = [n for bit, n in COMPR_ALGS.items() if avail & bit]
        compressed = bool(avail)
    else:
        avail = 0
        legacy = True
        lz4_max_distance = union_val
        # legacy 镜像: lz4_max_distance > 0 表示使用了 legacy LZ4 压缩
        compressed = union_val > 0
        compr_desc = (["lz4(legacy,max_distance=%d)" % union_val] if compressed else [])
    return {
        "magic": "0x%08x" % magic,
        "block_size": 1 << blkszbits,
        "blkszbits": blkszbits,
        "root_nid": root_nid,
        "inodes": inos,
        "build_time": build_time,
        "blocks": blocks,
        "meta_blkaddr": meta_blkaddr,
        "xattr_blkaddr": xattr_blkaddr,
        "uuid": uuid,
        "volume_name": volume_name,
        "feature_compat": fcompat,
        "feature_compat_decoded": decode_bits(fcompat, COMPAT),
        "feature_incompat": fincompat,
        "feature_incompat_decoded": decode_bits(fincompat, INCOMPAT),
        "compr_cfgs": bool(fincompat & 0x2),
        "legacy_lz4": legacy,
        "available_compr_algs": avail,
        "compr_desc": compr_desc,
        "compressed": compressed,
        "total_bytes_used": blocks * (1 << blkszbits),
    }


def analyze_image(path):
    with open(path, "rb") as f:
        head = f.read(SB_OFFSET + 128)
    sb = read_sb_from_buffer(head)
    if not sb:
        return None
    sb["file"] = os.path.abspath(path)
    sb["file_size"] = os.path.getsize(path)
    # 注意: compressed 由 read_sb_from_buffer 已按 COMPR_CFGS/legacy 正确判定，不要用 available_compr_algs 覆盖
    return sb


def cmd_super(super_path, json_out):
    here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, here)
    import lp_tool
    res = lp_tool.read_super(super_path)
    meta, base = res["metadata"], res["layout"]["data_base"]
    reader, _ = lp_tool.open_image(super_path)
    rows = []
    total_alloc = 0
    total_used = 0
    for p in meta["partitions"]:
        lin = [e for e in p["extents"] if e["target_type"] == 0]
        if not lin or p["size"] == 0:
            continue
        off = base + lin[0]["target_data"] * lp_tool.SECTOR
        head = reader.read_at(off, sb_needed())
        sb = read_sb_from_buffer(head)
        row = {"name": p["name"], "partition_size": p["size"]}
        if sb:
            row.update(sb)
            total_alloc += p["size"]
            total_used += sb["total_bytes_used"]
        else:
            row["fs"] = "not-erofs"
        rows.append(row)
    reader.close()
    print("=" * 96)
    print("EROFS 分区压缩信息: %s" % os.path.abspath(super_path))
    print("=" * 96)
    print("%-18s %12s %12s %9s %-30s %-10s %s"
          % ("partition", "part_size", "used", "used%", "compr", "inodes", "features_incompat"))
    for r in rows:
        if r.get("fs") == "not-erofs":
            print("%-18s %12d %12s %9s %-30s %-10s %s" % (r["name"], r["partition_size"], "-", "-", "?non-erofs", "-", "-"))
            continue
        ratio = (r["total_bytes_used"] / r["partition_size"]) if r["partition_size"] else 0
        print("%-18s %12d %12d %8.1f%% %-30s %-10d %s"
              % (r["name"], r["partition_size"], r["total_bytes_used"], ratio * 100,
                 ",".join(r["compr_desc"]) or "none",
                 r["inodes"], ",".join(r["feature_incompat_decoded"])))
    print("-" * 96)
    print("total allocated=%d (%s)  erofs used=%d (%s)  overall_ratio=%.3f"
          % (total_alloc, human(total_alloc), total_used, human(total_used),
             (total_used / total_alloc) if total_alloc else 0))
    if json_out:
        with open(json_out, "w", encoding="utf-8") as f:
            json.dump({"super": os.path.abspath(super_path), "partitions": rows}, f, indent=2, ensure_ascii=False)
        print("[json] -> %s" % json_out)
    return rows


def sb_needed():
    return SB_OFFSET + 128


def human(n):
    n = float(n)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(n) < 1024.0:
            return "%.2f %s" % (n, unit)
        n /= 1024.0
    return "%.2f PiB" % n


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return
    if args[0] == "--super":
        super_path = args[1]
        json_out = None
        if "--json" in args:
            json_out = args[args.index("--json") + 1]
        cmd_super(super_path, json_out)
        return
    for p in args:
        sb = analyze_image(p)
        print("=" * 70)
        print(p)
        if not sb:
            print("  not an EROFS image")
            continue
        for k, v in sb.items():
            print("  %-26s %s" % (k, v))


if __name__ == "__main__":
    main()
