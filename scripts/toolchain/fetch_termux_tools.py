#!/usr/bin/env python3
"""fetch_termux_tools.py -- 从 Termux 官方仓库下载 aarch64 deb 并解包成设备端可用的 prefix 树。

产物:
  00_tools/termux/debs/*.deb          原始 deb
  00_tools/termux/root/data/data/com.termux/files/usr/...   Termux prefix 树（保持原始绝对路径布局）

用法:
  python fetch_termux_tools.py --root erofs-utils e2fsprogs
  python fetch_termux_tools.py --list-only
"""
import argparse
import gzip
import io
import json
import lzma
import os
import re
import shutil
import sys
import tarfile
import urllib.request
import urllib.error

BASE = "https://packages.termux.dev/apt/termux-main"
MIRRORS = [
    BASE,
    "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main",
    "https://mirrors.ustc.edu.cn/termux/apt/termux-main",
]
DIST = "dists/stable/main/binary-aarch64"
HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(os.path.dirname(HERE))          # OriginOS_Rothko_Port
OUT = os.path.join(PROJ, "00_tools", "termux")


def http_get(url, timeout=60):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (fetch_termux_tools)",
        "Accept": "*/*",
    })
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(), r.geturl(), r.status


def pick_mirror():
    for m in MIRRORS:
        try:
            data, url, code = http_get(m + "/dists/stable/Release", timeout=20)
            print(f"[mirror] OK {m} (HTTP {code}, {len(data)}B)")
            return m
        except Exception as e:
            print(f"[mirror] FAIL {m}: {e}")
    raise SystemExit("no reachable termux mirror")


def load_index(mirror):
    for name in ("Packages.xz", "Packages.gz", "Packages"):
        url = f"{mirror}/{DIST}/{name}"
        try:
            raw, _, code = http_get(url)
        except Exception as e:
            print(f"[index] {name} -> {e}")
            continue
        if name.endswith(".xz"):
            raw = lzma.decompress(raw)
        elif name.endswith(".gz"):
            raw = gzip.decompress(raw)
        print(f"[index] {name}: {len(raw)} bytes OK")
        return parse_packages(raw.decode("utf-8", "replace"))
    raise SystemExit("cannot fetch Packages index")


def parse_packages(text):
    pkgs = {}
    for stanza in text.split("\n\n"):
        if not stanza.strip():
            continue
        d = {}
        key = None
        for line in stanza.splitlines():
            if line[:1] in (" ", "\t") and key:
                d[key] += "\n" + line.strip()
            elif ":" in line:
                key, _, val = line.partition(":")
                d[key.strip()] = val.strip()
        if "Package" in d:
            pkgs[d["Package"]] = d
    return pkgs


def dep_names(depstr):
    """'liblz4 (>= 1.9), liblzma | xz' -> ['liblz4','liblzma']  (跳过 ${...} 变量)"""
    out = []
    if not depstr:
        return out
    for part in re.split(r",\s*", depstr):
        part = part.strip()
        if not part:
            continue
        alts = [a.strip() for a in part.split("|")]
        name = re.split(r"[\s(]", alts[0])[0].strip()
        if name and not name.startswith("${"):
            out.append(name)
    return out


def resolve(pkgs, roots):
    need, stack, missing = {}, list(roots), []
    while stack:
        n = stack.pop()
        if n in need:
            continue
        if n not in pkgs:
            missing.append(n)
            continue
        need[n] = pkgs[n]
        for d in dep_names(pkgs[n].get("Depends", "")):
            if d not in need:
                stack.append(d)
    return need, missing


def download(mirror, pkg, destdir):
    fn = pkg["Filename"]
    url = f"{mirror}/{fn}"
    out = os.path.join(destdir, os.path.basename(fn))
    if os.path.exists(out) and os.path.getsize(out) > 0:
        print(f"[deb] cached {os.path.basename(out)}")
        return out
    data, _, code = http_get(url)
    with open(out, "wb") as f:
        f.write(data)
    print(f"[deb] {os.path.basename(out)} <- HTTP {code} {len(data)} bytes")
    return out


def extract_deb(debpath, destroot):
    """deb = ar archive: debian-binary, control.tar.*, data.tar.*"""
    with open(debpath, "rb") as f:
        blob = f.read()
    if not blob.startswith(b"!<arch>\n"):
        raise ValueError(f"{debpath} is not an ar archive")
    off = 8
    members = {}
    while off + 60 <= len(blob):
        hdr = blob[off:off + 60]
        name = hdr[0:16].decode("ascii", "replace").strip().rstrip("/")
        size = int(hdr[48:58].decode("ascii", "replace").strip() or 0)
        data = blob[off + 60:off + 60 + size]
        members[name] = data
        off += 60 + size + (size % 2)
    dataname = next((n for n in members if n.startswith("data.tar")), None)
    if not dataname:
        raise ValueError(f"no data.tar in {debpath}")
    raw = members[dataname]
    if dataname.endswith(".xz"):
        raw = lzma.decompress(raw)
    elif dataname.endswith(".gz"):
        raw = gzip.decompress(raw)
    elif dataname.endswith(".zst"):
        import subprocess
        p = subprocess.run(["zstd", "-d", "-c"], input=raw, capture_output=True)
        raw = p.stdout
    n = 0
    with tarfile.open(fileobj=io.BytesIO(raw)) as tf:
        for m in tf.getmembers():
            name = m.name
            while name.startswith("./"):
                name = name[2:]
            if not name or name in (".", "debian-binary"):
                continue
            target = os.path.join(destroot, name)
            base = os.path.dirname(target)
            if base:
                os.makedirs(base, exist_ok=True)
            if m.isdir():
                os.makedirs(target, exist_ok=True)
            elif m.issym():
                if os.path.lexists(target):
                    os.remove(target)
                os.symlink(m.linkname, target)
            elif m.islnk():
                src = os.path.join(destroot, m.linkname.lstrip("./"))
                if os.path.exists(target):
                    os.remove(target)
                try:
                    os.link(src, target)
                except OSError:
                    shutil.copy2(src, target)
            elif m.isfile():
                if os.path.lexists(target):
                    os.remove(target)
                with tf.extractfile(m) as srcf, open(target, "wb") as dstf:
                    shutil.copyfileobj(srcf, dstf)
                os.chmod(target, m.mode)
                n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", nargs="*", default=["erofs-utils", "e2fsprogs"])
    ap.add_argument("--list-only", action="store_true")
    ap.add_argument("--mirror", default=None)
    args = ap.parse_args()

    os.makedirs(os.path.join(OUT, "debs"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "root"), exist_ok=True)

    mirror = args.mirror or pick_mirror()
    pkgs = load_index(mirror)
    print(f"[index] {len(pkgs)} packages")

    need, missing = resolve(pkgs, args.root)
    if missing:
        print(f"[warn] dependencies not found in index: {missing}", file=sys.stderr)
    order = sorted(need)
    print(f"[resolve] {len(need)} debs: {order}")
    if args.list_only:
        for n in order:
            p = need[n]
            print(f"  {n:24s} {p.get('Version',''):20s} {p.get('Filename','')}")
        return

    manifest = {}
    for n in order:
        p = need[n]
        deb = download(mirror, p, os.path.join(OUT, "debs"))
        manifest[n] = {"version": p.get("Version"), "filename": os.path.basename(deb),
                       "depends": p.get("Depends", "")}

    root = os.path.join(OUT, "root")
    total = 0
    for n in order:
        deb = os.path.join(OUT, "debs", manifest[n]["filename"])
        cnt = extract_deb(deb, root)
        total += cnt
        print(f"[extract] {n}: {cnt} files")

    prefix = os.path.join(root, "data", "data", "com.termux", "files", "usr")
    print(f"[done] extracted files={total}")
    print(f"[done] prefix = {prefix}")
    for p in ("bin", "lib", "usr/bin"):
        d = os.path.join(prefix, p)
        if os.path.isdir(d):
            print(f"  {p}: {len(os.listdir(d))} entries")
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump({"mirror": mirror, "roots": args.root, "packages": manifest}, f, indent=2)


if __name__ == "__main__":
    main()
