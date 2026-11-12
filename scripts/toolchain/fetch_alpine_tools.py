#!/usr/bin/env python3
"""fetch_alpine_tools.py -- 下载 Alpine aarch64 apk（musl 动态链接）并解包成可 push 到 Android 的目录树。

用途: 手机自带 mkfs.erofs 不带 zstd 压缩器时，用 Alpine 的 erofs-utils（通常带 libzstd/liblzma）
      在设备上用 musl loader 直接运行:
        LD_LIBRARY_PATH=... /data/local/tmp/alpine/lib/ld-musl-aarch64.so.1 --library-path ... \
            /data/local/tmp/alpine/usr/bin/mkfs.erofs -zzstd,level=9 ...

产物:
  00_tools/alpine/apks/*.apk
  00_tools/alpine/root/{usr,lib,etc}/...   （apk 的 data.tar.gz 内容）
  00_tools/alpine/manifest.json

用法:
  python fetch_alpine_tools.py --root erofs-utils
  python fetch_alpine_tools.py --root erofs-utils --list-only
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

MIRRORS = [
    ("v3.21", "https://dl-cdn.alpinelinux.org/alpine/v3.21"),
    ("v3.20", "https://dl-cdn.alpinelinux.org/alpine/v3.20"),
    ("v3.19", "https://dl-cdn.alpinelinux.org/alpine/v3.19"),
    ("edge", "https://dl-cdn.alpinelinux.org/alpine/edge"),
]
ARCH = "aarch64"
HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(PROJ, "00_tools", "alpine")


def http_get(url, timeout=90):
    req = urllib.request.Request(url, headers={"User-Agent": "fetch_alpine_tools/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(), r.geturl(), r.status


def load_index(repo):
    """返回 {包名: 字段}；同时合并 main 与 community 组件（erofs-utils 在 community）。"""
    allpkgs = {}
    for component in ("main", "community"):
        url = f"{repo}/{component}/{ARCH}/APKINDEX.tar.gz"
        try:
            raw, _, code = http_get(url)
        except Exception as e:
            print(f"[index] {url} -> {e}")
            continue
        tf = tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz")
        text = None
        for m in tf.getmembers():
            if m.name in ("APKINDEX", "./APKINDEX"):
                text = tf.extractfile(m).read().decode("utf-8", "replace")
                break
        if not text:
            continue
        pkgs = parse_apkindex(text)
        for name, d in pkgs.items():
            d["__component"] = component
            allpkgs.setdefault(name, d)
        print(f"[index] {url}: {len(pkgs)} packages ({component})")
    if not allpkgs:
        raise SystemExit("cannot fetch APKINDEX")
    return allpkgs


def parse_apkindex(text):
    pkgs = {}
    for stanza in text.split("\n\n"):
        if not stanza.strip():
            continue
        d = {}
        for line in stanza.splitlines():
            if len(line) > 2 and line[1] == ":":
                k = line[0]
                v = line[2:]
                d.setdefault(k, v)
        if "P" in d:
            pkgs[d["P"]] = d
    return pkgs


def dep_names(depstr, pkgs):
    """Alpine D: 'so:libzstd.so.1=1.5.6 so:libc.musl-aarch64.so.1' 或 'musl'"""
    out = []
    for tok in depstr.split():
        tok = tok.split("=")[0].split(">")[0].split("<")[0]
        if not tok or tok.startswith("!"):
            continue
        if tok.startswith("so:"):
            # 通过 C: provides 反查包名
            for name, p in pkgs.items():
                if tok in p.get("C", "").split():
                    out.append(name)
                    break
            continue
        out.append(tok)
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
        for dep in dep_names(pkgs[n].get("D", ""), pkgs):
            if dep not in need:
                stack.append(dep)
    return need, missing


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", nargs="*", default=["erofs-utils"])
    ap.add_argument("--list-only", action="store_true")
    ap.add_argument("--repo-version", default=None)
    args = ap.parse_args()

    os.makedirs(os.path.join(OUT, "apks"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "root"), exist_ok=True)

    repo = None
    ver = args.repo_version
    for rv, rurl in MIRRORS:
        if ver and rv != ver:
            continue
        try:
            pkgs = load_index(rurl)
            print(f"[repo] using {rurl}: {len(pkgs)} packages")
            repo = (rv, rurl)
            break
        except SystemExit as e:
            print(f"[repo] {rv} failed: {e}")
    if not repo:
        raise SystemExit("no usable alpine repo")
    rv, rurl = repo

    need, missing = resolve(pkgs, args.root)
    if missing:
        print(f"[warn] missing deps: {missing}", file=sys.stderr)
    order = sorted(need)
    print(f"[resolve] {len(need)} apks: {order}")
    if args.list_only:
        for n in order:
            print(f"  {n:22s} {need[n].get('V',''):16s} {need[n].get('F','')}")
        return

    root = os.path.join(OUT, "root")
    manifest = {"repo": rurl, "arch": ARCH, "roots": args.root, "packages": {}}
    for n in order:
        p = need[n]
        fn = p.get("F", f"{n}-{p.get('V','')}.apk")
        comp = p.get("__component", "main")
        url = f"{rurl}/{comp}/{ARCH}/{fn}"
        out = os.path.join(OUT, "apks", fn)
        if not (os.path.exists(out) and os.path.getsize(out) > 0):
            data, _, code = http_get(url)
            with open(out, "wb") as f:
                f.write(data)
        manifest["packages"][n] = {"version": p.get("V"), "file": fn, "deps": p.get("D", "")}
        print(f"[apk] {fn} ({os.path.getsize(out)} bytes)")
        nfiles = extract_apk(out, root)
        print(f"[extract] {n} -> {nfiles} files")

    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    # 汇总
    print("[done] root =", root)
    for sub in ("usr/bin", "usr/sbin", "lib", "usr/lib"):
        d = os.path.join(root, sub)
        if os.path.isdir(d):
            entries = [x for x in os.listdir(d) if "erofs" in x or "ld-musl" in x or "mke2fs" in x]
            print(f"  {sub}: {len(os.listdir(d))} entries" + (f"  相关: {sorted(entries)}" if entries else ""))


def extract_apk(apkpath, destroot):
    """Alpine apk = tar.gz（gzip），data 部分包含 usr/ lib/ etc/ 与 .PKGINFO。"""
    n = 0
    with tarfile.open(apkpath, mode="r:gz") as tf:
        for m in tf.getmembers():
            name = m.name
            while name.startswith("./"):
                name = name[2:]
            if not name or name.startswith(".SIGN") or name in (".PKGINFO", ".INSTALL"):
                continue
            if name.startswith("."):
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
                with tf.extractfile(m) as sf, open(target, "wb") as df:
                    shutil.copyfileobj(sf, df)
                os.chmod(target, m.mode)
                n += 1
    return n


if __name__ == "__main__":
    main()
