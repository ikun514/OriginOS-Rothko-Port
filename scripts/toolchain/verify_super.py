#!/usr/bin/env python3
"""verify_super.py -- super.img 自检（重建/修改后验证），纯 Python。

用法:
  python verify_super.py --built super.img [--reference original_super.img] [-v]
检查项:
  1. LP geometry/metadata 三个 checksum 是否有效（lp_tool 自动布局探测）
  2. block device size == 文件大小
  3. 每个非空分区的 extent 在文件内（不越界）
  4. 所有 LINEAR extent 按绝对偏移排序后互不重叠
  5. 每个分区首 extent 处的文件系统 magic（erofs/ext4/f2fs）可识别
  6. 有 --reference 时: 分区名/顺序/大小逐一比对，group max_size 比对
  7. device_size 与自定义期望值比对（--expect-size）
退出码 0=PASS，1=FAIL。
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lp_tool  # noqa: E402


def collect(meta, data_base):
    rows = []
    for p in meta["partitions"]:
        lin = [e for e in p["extents"] if e["target_type"] == 0]
        if not lin or p["size"] == 0:
            rows.append({"name": p["name"], "size": 0, "start": None, "end": None,
                         "extents": [], "group": p["group_name"],
                         "attrs": p["attributes_decoded"]})
            continue
        start = data_base + min(e["target_data"] for e in lin) * lp_tool.SECTOR
        end = data_base + max(e["target_data"] + e["num_sectors"] for e in lin) * lp_tool.SECTOR
        rows.append({"name": p["name"], "size": p["size"], "start": start, "end": end,
                     "extents": lin, "group": p["group_name"],
                     "attrs": p["attributes_decoded"]})
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--built", required=True)
    ap.add_argument("--reference", default=None)
    ap.add_argument("--expect-size", type=int, default=None)
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    errors, warns, info = [], [], []
    res = lp_tool.read_super(args.built, verbose=False)
    meta = res["metadata"]
    data_base = res["layout"]["data_base"]
    rows = collect(meta, data_base)
    fsize = res["file_size"]

    info.append("file=%s size=%d (%s) layout=%s container=%s"
                % (res["file"], fsize, res["file_size_human"], res["layout"], res["container"]))
    info.append("metadata v%d.%d header_checksum_ok=%s tables_checksum_ok=%s"
                % (meta["major_version"], meta["minor_version"],
                   meta["header_checksum_ok"], meta["tables_checksum_ok"]))
    if not (meta["header_checksum_ok"] and meta["tables_checksum_ok"] and res["geometry"]["checksum_ok"]):
        errors.append("LP checksum 无效")
    if args.expect_size and fsize != args.expect_size:
        errors.append("文件大小 %d != 期望 %d" % (fsize, args.expect_size))
    bdevs = meta["block_devices"]
    if bdevs and bdevs[0]["size"] != fsize:
        errors.append("block_device size %d != 文件大小 %d" % (bdevs[0]["size"], fsize))

    # 越界 & 重叠
    nonempty = [r for r in rows if r["size"] > 0]
    for r in nonempty:
        if r["end"] > fsize:
            errors.append("分区 %s 越界: end=%d > file=%d" % (r["name"], r["end"], fsize))
    ordered = sorted(nonempty, key=lambda r: r["start"])
    for a, b in zip(ordered, ordered[1:]):
        if a["end"] > b["start"]:
            errors.append("extent 重叠: %s [%d,%d) 与 %s [%d,%d)" % (a["name"], a["start"], a["end"], b["name"], b["start"], b["end"]))
    # 文件系统 magic
    reader, _ = lp_tool.open_image(args.built)
    for r in nonempty:
        fs = lp_tool.probe_fs_magic(reader, r["start"])
        r["fs"] = fs
        if fs is None:
            warns.append("分区 %s 首 extent 未识别到 erofs/ext4/f2fs magic" % r["name"])
    reader.close()
    # group max
    for g in meta["groups"]:
        used = sum(r["size"] for r in nonempty if r["group"] == g["name"])
        if g["maximum_size"] and used > g["maximum_size"]:
            errors.append("group %s 超限: used=%d > max=%d" % (g["name"], used, g["maximum_size"]))
        info.append("group %-8s max=%-12d used=%-12d (%s)" % (g["name"], g["maximum_size"], used,
                                                              lp_tool.human(used)))

    # 与参考 super 比对
    if args.reference:
        ref = lp_tool.read_super(args.reference, verbose=False)
        rmeta = ref["metadata"]
        rrows = {r["name"]: r for r in collect(rmeta, ref["layout"]["data_base"])}
        rnames = [p["name"] for p in rmeta["partitions"]]
        bnames = [p["name"] for p in meta["partitions"]]
        if rnames != bnames:
            errors.append("分区名/顺序不一致:\n  ref=%s\n  built=%s" % (rnames, bnames))
        for p in meta["partitions"]:
            r = rrows.get(p["name"])
            if r is None:
                errors.append("参考 super 缺少分区 %s" % p["name"])
            elif r["size"] != p["size"]:
                errors.append("分区 %s 大小不一致: ref=%d built=%d" % (p["name"], r["size"], p["size"]))
        for g in meta["groups"]:
            rg = [x for x in rmeta["groups"] if x["name"] == g["name"]]
            if not rg:
                errors.append("参考 super 缺少 group %s" % g["name"])
            elif rg[0]["maximum_size"] != g["maximum_size"]:
                errors.append("group %s max 不一致: ref=%d built=%d" % (g["name"], rg[0]["maximum_size"], g["maximum_size"]))
        if rmeta["major_version"] != meta["major_version"] or rmeta["minor_version"] != meta["minor_version"]:
            errors.append("metadata 版本不一致")
        info.append("与参考 super 比对: 分区数 %d/%d, group 数 %d/%d"
                    % (len(bnames), len(rnames), len(meta["groups"]), len(rmeta["groups"])))

    print("=" * 84)
    print("SUPER 自检: %s" % args.built)
    print("=" * 84)
    for i in info:
        print("  " + i)
    print("  分区（按文件偏移排序）:")
    print("  %-18s %12s %12s %12s  %-8s %s" % ("name", "size", "file_start", "file_end", "fs", "attrs"))
    for r in ordered:
        print("  %-18s %12d %12d %12d  %-8s %s"
              % (r["name"], r["size"], r["start"], r["end"], r.get("fs") or "-", ",".join(r["attrs"])))
    for w in warns:
        print("  WARN: " + w)
    print()
    if errors:
        print("结果: FAIL (%d errors)" % len(errors))
        for e in errors:
            print("  - " + e)
        sys.exit(1)
    print("结果: PASS  (0 errors, %d warnings)" % len(warns))


if __name__ == "__main__":
    main()
