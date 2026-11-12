#!/usr/bin/env python3
"""patch_vendor_boot.py -- 修改 Android vendor_boot (header v4) 镜像

做两件事（默认同时做，可用开关关闭）:
  1) --remove-avb: 删除 platform ramdisk 里 first_stage_ramdisk/fstab.mt6989 中
     所有 AVB 相关参数（token 等于 `avb`、或以 `avb=` / `avb_keys=` 开头），保留其余 flags。
  2) --selinux-permissive: 在 vendor_boot header 的 cmdline 末尾追加
     ` androidboot.selinux=permissive`（保留原有 bootopt=...）
  3) --force-gsi-avbkeys: 反向选项，仅删除 `avb`/`avb=`，保留 system/system_ext 行的
     GSI `avb_keys=`（默认按 Lead 要求一并删除）

重建规则:
  - platform ramdisk fragment 重新 cpio 打包 + gzip -9 -n（mtime=0, OS=3, XFL=2）
  - recovery fragment、dtb 段、bootconfig 段原样保留（逐字节）
  - 重建 vendor_ramdisk_table（更新 fragment0 size / fragment1 offset）
  - 更新 header.vendor_ramdisk_size；其余 header 字段不变
  - 分段顺序与原始镜像一致（本机 MTK 镜像为 header→ramdisk→dtb→table→bootconfig）
  - 保留尾部 AVB vbmeta blob 并更新 AVB footer 的 original_image_size/vbmeta_offset/vbmeta_size
    （注意：vbmeta 签名不会匹配新镜像，刷机需禁用 AVB 验证；可用 --strip-avb 输出无 AVB 版本）

用法:
  python patch_vendor_boot.py --in 02_base/images/rothko_current_vendor_boot_a.img \
      --out G:/OriginOS_Work/02_base/rothko_vendor_boot_patched.img
  python lp_tool-like 自检会打印 header/fragment/fstab/cmdline 摘要与 sha256。
"""
import argparse
import gzip
import hashlib
import json
import os
import struct
import sys

VENDOR_BOOT_MAGIC = b"VNDRBOOT"
AVB_MAGIC = b"AVBf"
CPIO_MAGIC = b"070701"
FDT_MAGIC = b"\xd0\x0d\xfe\xed"


# ---------------------------------------------------------------- gzip helpers
def gzip_compress_fixed(data, level=9):
    """生成 mtime=0、OS=3(Unix)、level=9 时 XFL=2 的 gzip 流（与 AOSP ramdisk 风格一致）。"""
    out = bytearray(gzip.compress(data, compresslevel=level, mtime=0))
    if len(out) >= 10:
        out[4:8] = b"\x00\x00\x00\x00"      # mtime = 0
        out[8] = 2 if level >= 9 else 4 if level >= 1 else 0  # XFL
        out[9] = 3                          # OS = Unix
    return bytes(out)


def gzip_decompress_fixed(data):
    return gzip.decompress(data)


# ----------------------------------------------------------------- cpio helpers
def cpio_parse(buf):
    """解析 newc cpio -> list[dict]，保留原始字段以便无损重建。"""
    entries = []
    pos = 0
    n = len(buf)
    while pos + 110 <= n:
        hdr = buf[pos:pos + 110]
        if hdr[:6] not in (b"070701", b"070702"):
            raise ValueError("bad cpio magic at %d: %r" % (pos, hdr[:8]))
        fields = [int(hdr[6 + i * 8:14 + i * 8], 16) for i in range(13)]
        (ino, mode, uid, gid, nlink, mtime, filesize, devmaj, devmin,
         rdevmaj, rdevmin, namesize, chksum) = fields
        name_raw = buf[pos + 110: pos + 110 + namesize]
        name = name_raw[:-1].decode("utf-8", "surrogateescape")
        hdrlen = 110 + namesize
        hdrlen = (hdrlen + 3) & ~3
        data = buf[pos + hdrlen: pos + hdrlen + filesize]
        entries.append({
            "name": name, "mode": mode, "uid": uid, "gid": gid, "nlink": nlink,
            "mtime": mtime, "filesize": filesize, "devmaj": devmaj, "devmin": devmin,
            "rdevmaj": rdevmaj, "rdevmin": rdevmin, "ino": ino, "data": data,
        })
        pos = pos + hdrlen + ((filesize + 3) & ~3)
        if name == "TRAILER!!!":
            break
    return entries


def cpio_build(entries):
    out = bytearray()
    for e in entries:
        name = e["name"] + "\x00"
        name_raw = name.encode("utf-8", "surrogateescape")
        data = e["data"]
        filesize = len(data)
        hdr = b"070701" + b"".join(
            b"%08X" % v for v in (
                e["ino"], e["mode"], e["uid"], e["gid"], e["nlink"], e["mtime"],
                filesize, e["devmaj"], e["devmin"], e["rdevmaj"], e["rdevmin"],
                len(name_raw), 0,
            ))
        out += hdr
        out += name_raw
        out += b"\x00" * ((4 - len(out) % 4) % 4)
        out += data
        out += b"\x00" * ((4 - len(out) % 4) % 4)
    # 尾部对齐到 512（cpio 惯例，不少内核/init 实现要求）
    out += b"\x00" * ((512 - len(out) % 512) % 512)
    return bytes(out)


# --------------------------------------------------------------- vendor_boot
class VendorBoot:
    def __init__(self, data):
        self.data = data
        if data[:8] != VENDOR_BOOT_MAGIC:
            raise SystemExit("not a vendor_boot image (magic=%r)" % data[:8])
        (self.magic, self.header_version, self.page_size, self.kernel_addr,
         self.ramdisk_addr, self.vendor_ramdisk_size) = struct.unpack("<8sIIIII", data[:28])
        self.cmdline_off = 28
        self.cmdline = data[28:28 + 2048]
        self.tags_addr, self.name, self.header_size, self.dtb_size, self.dtb_addr = \
            struct.unpack("<I16sIIQ", data[28 + 2048:28 + 2048 + 36])
        if self.header_version < 3:
            raise SystemExit("unsupported header_version=%d" % self.header_version)
        off = 2112
        if self.header_version >= 4:
            (self.table_size, self.table_num, self.table_esize, self.bootconfig_size) = \
                struct.unpack("<IIII", data[off:off + 16])
        else:
            self.table_size = self.table_num = self.table_esize = self.bootconfig_size = 0

        page = self.page_size
        self.hdr_padded = (self.header_size + page - 1) // page * page
        self.ramdisk_start = self.hdr_padded
        self.ramdisk_end = self.ramdisk_start + self.vendor_ramdisk_size
        self._locate_table()
        self._locate_dtb()
        self._locate_bootconfig()
        self._locate_avb()
        self.fragments = self._parse_fragments()

    # --- 定位 ---
    def _page_align(self, x):
        return (x + self.page_size - 1) // self.page_size * self.page_size

    def _locate_table(self):
        """在 ramdisk 之后、图像结束前扫描 vendor_ramdisk_table（校验 offsets/sizes 自洽）。"""
        cand = []
        start = self._page_align(self.ramdisk_end)
        end = len(self.data) - 64
        es = self.table_esize or 108
        num = self.table_num
        for t in range(start, end, self.page_size):
            if t + num * es > len(self.data):
                break
            ok = True
            acc = 0
            for i in range(num):
                o = t + i * es
                sz, roff, rtype = struct.unpack("<III", self.data[o:o + 12])
                if roff != acc or sz == 0 or roff + sz > self.vendor_ramdisk_size:
                    ok = False
                    break
                acc += sz
            if ok and acc <= self.vendor_ramdisk_size:
                cand.append(t)
        if not cand:
            raise SystemExit("cannot locate vendor_ramdisk_table")
        self.table_off = cand[0]

    def _locate_dtb(self):
        """dtb 段：优先用 FDT magic 定位（允许 64B 前缀），否则用 page 对齐推算。"""
        s = self._page_align(self.ramdisk_end)
        dtb_start = None
        # dtb 在 table 之前或之后，都可能
        for base in (s, self._page_align(self.table_off + self.table_size)):
            i = self.data.find(FDT_MAGIC, base, base + self.page_size)
            if i > 0:
                dtb_start = (i - base) and base or base
                # dtb 段起点是 page 对齐处；FDT 可能带前缀
                dtb_start = base
                self.dtb_fdt_off = i
                break
        if dtb_start is None:
            self.dtb_fdt_off = 0
            dtb_start = s
        self.dtb_start = dtb_start
        self.dtb_end = dtb_start + self.dtb_size

    def _locate_bootconfig(self):
        after = max(self.dtb_end, self.table_off + self.table_size)
        self.bootconfig_start = self._page_align(after)
        self.bootconfig_end = self.bootconfig_start + self.bootconfig_size

    def _locate_avb(self):
        self.avb_footer_off = self.data.rfind(AVB_MAGIC)
        self.avb = None
        if self.avb_footer_off > 0 and self.avb_footer_off + 64 <= len(self.data):
            f = self.data[self.avb_footer_off:self.avb_footer_off + 64]
            ver = struct.unpack(">I", f[4:8])[0]
            orig = struct.unpack(">Q", f[12:20])[0]
            vbo = struct.unpack(">Q", f[20:28])[0]
            vbs = struct.unpack(">Q", f[28:36])[0]
            self.avb = {"version": ver, "original_image_size": orig,
                        "vbmeta_offset": vbo, "vbmeta_size": vbs,
                        "footer_offset": self.avb_footer_off}
            self.vbmeta_blob = self.data[vbo:vbo + vbs]
        else:
            self.vbmeta_blob = b""

    def _parse_fragments(self):
        frags = []
        for i in range(self.table_num):
            o = self.table_off + i * self.table_esize
            sz, roff, rtype = struct.unpack("<III", self.data[o:o + 12])
            name = self.data[o + 12:o + 44].rstrip(b"\x00").decode("utf-8", "replace")
            board = struct.unpack("<16I", self.data[o + 44:o + 108])
            raw = self.data[self.ramdisk_start + roff: self.ramdisk_start + roff + sz]
            frags.append({"index": i, "size": sz, "offset": roff, "type": rtype,
                          "name": name, "board_id": list(board), "raw": raw,
                          "gzip": raw[:2] == b"\x1f\x8b"})
        return frags

    # --- 修改 ---
    def patch_cmdline(self, add="androidboot.selinux=permissive"):
        cur = self.cmdline.rstrip(b"\x00").decode("utf-8", "replace")
        if add in cur:
            print("[cmdline] already contains %r, skip" % add)
            return
        new = (cur + " " + add).strip()
        raw = new.encode()
        if len(raw) > 2048:
            raise SystemExit("cmdline too long: %d" % len(raw))
        buf = bytearray(self.cmdline)
        buf[:len(raw)] = raw
        for i in range(len(raw), 2048):
            buf[i] = 0
        self.cmdline = bytes(buf)
        print("[cmdline] %r -> %r" % (cur, new))

    def patch_fstab_avb(self, keep_gsi_avbkeys=False, fstab_name="first_stage_ramdisk/fstab.mt6989"):
        f0 = self.fragments[0]
        if not f0["gzip"]:
            raise SystemExit("fragment0 is not gzip; unsupported")
        dec = gzip_decompress_fixed(f0["raw"])
        entries = cpio_parse(dec)
        target = None
        for e in entries:
            if e["name"].lstrip("./") == fstab_name or e["name"].endswith("/" + fstab_name) \
                    or e["name"].lstrip("./").endswith(fstab_name):
                target = e
                break
        if target is None:
            raise SystemExit("fstab %r not found in platform ramdisk" % fstab_name)
        old_text = target["data"].decode("utf-8", "replace")
        new_lines = []
        removed = []
        for line in old_text.splitlines():
            words = line.split()
            if len(words) < 3:
                new_lines.append(line)
                continue
            mount = words[1]
            # fstab 行: <source> <mount> <type> [options] [fs_mgr_flags ...]
            # options/fs_mgr_flags 都是逗号分隔的 flag 列表；avb 相关 flag 在两者中都可能
            out_words = words[:3]
            for widx, w in enumerate(words[3:], start=3):
                flags = w.split(",")
                kept = []
                for tok in flags:
                    is_avb_plain = (tok == "avb")
                    is_avb_eq = tok.startswith("avb=") and not tok.startswith("avb_keys=")
                    is_avbkeys = tok.startswith("avb_keys=")
                    if is_avb_plain or is_avb_eq:
                        removed.append((mount, tok))
                        continue
                    if is_avbkeys:
                        if keep_gsi_avbkeys and mount in ("/system", "/system_ext"):
                            kept.append(tok)
                        else:
                            removed.append((mount, tok))
                        continue
                    kept.append(tok)
                if kept:
                    out_words.append(",".join(kept))
            new_lines.append(" ".join(out_words))
        new_text = "\n".join(new_lines)
        if old_text.endswith("\n"):
            new_text += "\n"
        target["data"] = new_text.encode()
        target["filesize"] = len(target["data"])
        new_cpio = cpio_build(entries)
        new_gz = gzip_compress_fixed(new_cpio, 9)
        print("[fstab] %s: %d -> %d bytes, removed %d avb tokens, cpio %d -> %d, gzip %d -> %d"
              % (fstab_name, len(old_text), len(new_text), len(removed),
                 len(dec), len(new_cpio), len(f0["raw"]), len(new_gz)))
        for mount, tok in removed[:12]:
            print("        removed %-14s %s" % (mount, tok))
        if len(removed) > 12:
            print("        ... (%d more)" % (len(removed) - 12))
        self.fragments[0]["raw"] = new_gz
        self.fragments[0]["size"] = len(new_gz)
        self.new_fstab_text = new_text
        return removed

    # --- 重建 ---
    def rebuild(self, strip_avb=False, keep_total_size=True):
        frags = self.fragments
        new_vrsize = sum(f["size"] for f in frags)
        # 新 ramdisk 区
        ramdisk = b"".join(f["raw"] for f in frags)
        # header
        hdr = bytearray(self.data[:self.header_size])
        struct.pack_into("<I", hdr, 24, new_vrsize)                      # vendor_ramdisk_size
        hdr[28:28 + 2048] = self.cmdline                                 # cmdline
        out = bytearray()
        out += bytes(hdr)
        out += b"\x00" * ((self.page_size - len(out) % self.page_size) % self.page_size)
        out += ramdisk
        out += b"\x00" * ((self.page_size - len(out) % self.page_size) % self.page_size)
        # 中间若有原始空隙（ramdisk 与下一段之间），保持为 0 填充即可

        # 按原始相对顺序输出其余段: dtb, table, bootconfig
        order = sorted([("dtb", self.dtb_start, self.dtb_end),
                        ("table", self.table_off, self.table_off + self.table_size),
                        ("bootconfig", self.bootconfig_start, self.bootconfig_end)],
                       key=lambda x: x[1])
        tbl = bytearray(self.data[self.table_off:self.table_off + self.table_size])
        acc = 0
        for i, f in enumerate(frags):
            o = i * self.table_esize
            struct.pack_into("<II", tbl, o, f["size"], acc)
            acc += f["size"]
        for name, s, e in order:
            if name == "dtb":
                seg = self.data[s:e]
            elif name == "table":
                seg = bytes(tbl)
            else:
                seg = self.data[s:e] if self.bootconfig_size else b""
            if not seg:
                continue
            out += b"\x00" * ((self.page_size - len(out) % self.page_size) % self.page_size)
            out += seg
        # 段间对齐到页，image 结束
        out += b"\x00" * ((self.page_size - len(out) % self.page_size) % self.page_size)
        image_end = len(out)
        # vbmeta blob（保留）+ 尾部
        if strip_avb:
            final = bytes(out)
        else:
            if self.vbmeta_blob:
                out += self.vbmeta_blob
            if keep_total_size:
                total = len(self.data)
                footer = bytearray(self.data[self.avb_footer_off:self.avb_footer_off + 64]) if self.avb else b""
                body = bytearray(out)
                # 更新 AVB footer 字段
                new_vb_off = image_end
                new_vb_size = len(self.vbmeta_blob)
                struct.pack_into(">Q", footer, 12, image_end)       # original_image_size
                struct.pack_into(">Q", footer, 20, new_vb_off)      # vbmeta_offset
                struct.pack_into(">Q", footer, 28, new_vb_size)     # vbmeta_size
                end_of_payload = len(body)
                body += b"\x00" * (total - 64 - len(body))
                body += bytes(footer)
                final = bytes(body)
            else:
                final = bytes(out)
        return final, {"image_end": image_end, "new_vrsize": new_vrsize,
                       "total_size": len(final)}

    # --- 自检 ---
    def report(self, out_path, out_data):
        print("--- vendor_boot 自检 ---")
        print("  header_version=%d page_size=%d header_size=%d" % (self.header_version, self.page_size, self.header_size))
        print("  kernel_addr=%#x ramdisk_addr=%#x tags_addr=%#x dtb_addr=%#x" %
              (self.kernel_addr, self.ramdisk_addr, self.tags_addr, self.dtb_addr))
        print("  cmdline=%r" % self.cmdline.rstrip(b"\x00"))
        print("  vendor_ramdisk_size: %d -> %d" % (self.vendor_ramdisk_size, sum(f["size"] for f in self.fragments)))
        print("  fragments:")
        acc = 0
        for f in self.fragments:
            print("    [%d] type=%d name=%r size=%d offset=%d gzip=%s" % (f["index"], f["type"], f["name"], f["size"], acc, f["gzip"]))
            acc += f["size"]
        print("  table: off=%d size=%d entries=%d esize=%d" % (self.table_off, self.table_size, self.table_num, self.table_esize))
        print("  dtb: off=%d size=%d (FDT magic at +%d)" % (self.dtb_start, self.dtb_size, self.dtb_fdt_off))
        print("  bootconfig: off=%d size=%d" % (self.bootconfig_start, self.bootconfig_size))
        if self.avb:
            print("  AVB(original): %s" % json.dumps(self.avb))
        print("  output: %s  size=%d  sha256=%s" % (out_path, len(out_data), hashlib.sha256(out_data).hexdigest()))
        # 重新解析输出镜像做结构自检
        chk = VendorBoot(out_data)
        ok = True
        msgs = []
        if chk.page_size != self.page_size:
            ok = False; msgs.append("page_size changed")
        if chk.vendor_ramdisk_size != sum(f["size"] for f in self.fragments):
            ok = False; msgs.append("vendor_ramdisk_size mismatch")
        if chk.table_num != self.table_num:
            ok = False; msgs.append("table entries changed")
        # fragment offsets 自洽
        acc = 0
        for i, f in enumerate(chk.fragments):
            if f["offset"] != acc:
                ok = False; msgs.append("fragment[%d] offset %d != %d" % (i, f["offset"], acc))
            acc += f["size"]
        # 新 ramdisk 里 fstab 内容检查
        try:
            dec = gzip_decompress_fixed(chk.fragments[0]["raw"])
            ents = cpio_parse(dec)
            fstab = [e for e in ents if e["name"].endswith("fstab.mt6989")]
            txt = fstab[0]["data"].decode("utf-8", "replace") if fstab else ""
            avb_lines = [l for l in txt.splitlines() if " avb" in l or "\tavb" in l]
            print("  fstab lines still containing avb*: %d" % len(avb_lines))
            for l in avb_lines[:5]:
                print("    %s" % l)
            msgs.append("fstab_avb_lines=%d" % len(avb_lines))
            cmd = chk.cmdline.rstrip(b"\x00").decode()
            print("  output cmdline=%r" % cmd)
            msgs.append("cmdline=%s" % cmd)
        except Exception as e:
            ok = False; msgs.append("reparse fstab failed: %s" % e)
        print("  自检: %s  %s" % ("PASS" if ok else "FAIL", "; ".join(msgs)))
        return ok


def main():
    ap = argparse.ArgumentParser(description="patch Android vendor_boot v4 (fstab avb + cmdline selinux)")
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", dest="out", required=True)
    ap.add_argument("--remove-avb", action="store_true", default=True)
    ap.add_argument("--no-remove-avb", dest="remove_avb", action="store_false")
    ap.add_argument("--force-gsi-avbkeys", action="store_true",
                    help="保留 system/system_ext 行的 GSI avb_keys= (默认一并删除)")
    ap.add_argument("--selinux-permissive", action="store_true", default=True)
    ap.add_argument("--no-selinux-permissive", dest="selinux_permissive", action="store_false")
    ap.add_argument("--strip-avb", action="store_true", help="输出不含 AVB vbmeta/footer 的紧凑镜像")
    ap.add_argument("--compact", action="store_true", help="输出图像不补齐到原分区大小")
    ap.add_argument("--report", default=None, help="自检报告 JSON 输出路径")
    args = ap.parse_args()

    data = open(args.inp, "rb").read()
    vb = VendorBoot(data)
    print("输入: %s (%d B, header v%d, page=%d)" % (args.inp, len(data), vb.header_version, vb.page_size))
    print("原始 cmdline=%r" % vb.cmdline.rstrip(b"\x00"))
    removed = []
    if args.remove_avb:
        removed = vb.patch_fstab_avb(keep_gsi_avbkeys=args.force_gsi_avbkeys)
    if args.selinux_permissive:
        vb.patch_cmdline()
    out, info = vb.rebuild(strip_avb=args.strip_avb, keep_total_size=not (args.strip_avb or args.compact))
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "wb") as f:
        f.write(out)
    ok = vb.report(args.out, out)
    report = {
        "input": os.path.abspath(args.inp), "output": os.path.abspath(args.out),
        "output_size": len(out), "output_sha256": hashlib.sha256(out).hexdigest(),
        "self_check": "PASS" if ok else "FAIL", "info": info,
        "removed_avb_tokens": removed,
        "cmdline": vb.cmdline.rstrip(b"\x00").decode("utf-8", "replace"),
        "avb_signature_note": "vbmeta blob 保留但签名与新镜像不匹配：刷机必须禁用 AVB 验证，或使用 --strip-avb",
    }
    if args.report:
        with open(args.report, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        print("[report] -> %s" % args.report)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
