#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""selftest_payload.py -- build a synthetic AOSP v2 payload and prove payload_extract.py works.

Covers every self-contained operation the extractor supports (REPLACE, REPLACE_BZ,
REPLACE_XZ, REPLACE_ZSTD, ZERO/DISCARD) plus a delta-only partition that must be
reported as NEEDS_BASELINE.  The synthetic payload carries real new_partition_info
sha256 values, so `--verify` is exercised end to end.

Usage:
    python selftest_payload.py [--keep]
Run it whenever payload_extract.py changes, or before trusting it on a new OTA package.
"""

import bz2
import hashlib
import lzma
import os
import shutil
import struct
import subprocess
import sys
import tempfile

BLOCK = 4096
HERE = os.path.dirname(os.path.abspath(__file__))
EXTRACTOR = os.path.join(HERE, "payload_extract.py")


# ---------------------------------------------------------------- varint/proto
def uv(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def key(field, wt):
    return uv((field << 3) | wt)


def fv(field, n):
    return key(field, 0) + uv(n)


def fb(field, data):
    return key(field, 2) + uv(len(data)) + data


def extent(start, num):
    return fv(1, start) + fv(2, num)


def partition_info(size, digest):
    return fv(1, size) + fb(2, digest)


def install_op(optype, data_offset, data, dst_extents, dst_len, data_hash=b""):
    """Self-contained op: payload bytes live in `data`."""
    out = fv(1, optype) + fv(2, data_offset) + fv(3, len(data))
    for start, num in dst_extents:
        out += fb(6, extent(start, num))
    out += fv(7, dst_len)
    if data_hash:
        out += fb(8, data_hash)
    return out


def delta_op(optype, src_extents, dst_extents, src_len, dst_len):
    """Delta op: needs the source image, carries no self-contained payload."""
    out = fv(1, optype) + fv(2, 0) + fv(3, 0)
    for start, num in src_extents:
        out += fb(4, extent(start, num))
    out += fv(5, src_len)
    for start, num in dst_extents:
        out += fb(6, extent(start, num))
    out += fv(7, dst_len)
    return out


def pattern(n, seed):
    return bytes(((i * 7 + seed * 31 + 13) & 0xFF) for i in range(n))


def build_payload(path):
    blobs = bytearray()
    partitions = []
    expected = {}

    # ---- partition "alpha": every self-contained op type --------------------
    chunks = []          # (op_proto_bytes, raw_data_for_blob)
    image = bytearray()

    def add(opt, raw, encoded, nblocks):
        start = len(image) // BLOCK
        image.extend(raw)
        off = len(blobs)
        blobs.extend(encoded)
        op = install_op(opt, off, encoded, [(start, nblocks)], len(raw),
                        hashlib.sha256(encoded).digest())
        chunks.append(op)

    add(0, pattern(BLOCK, 1), pattern(BLOCK, 1), 1)                       # REPLACE
    raw = pattern(BLOCK, 2)
    add(1, raw, bz2.compress(raw), 1)                                     # REPLACE_BZ
    raw = pattern(BLOCK * 2, 3)
    add(8, raw, lzma.compress(raw, format=lzma.FORMAT_XZ), 2)             # REPLACE_XZ
    import zstandard
    raw = pattern(BLOCK * 3, 4)
    add(14, raw, zstandard.ZstdCompressor(level=9).compress(raw), 3)      # REPLACE_ZSTD
    zero_start = len(image) // BLOCK
    image.extend(b"\x00" * (BLOCK * 2))                                   # ZERO
    chunks.append(install_op(6, 0, b"", [(zero_start, 2)], BLOCK * 2))

    alpha = bytearray()
    alpha += fb(1, b"alpha")
    alpha += fb(7, partition_info(len(image), hashlib.sha256(bytes(image)).digest()))
    for op in chunks:
        alpha += fb(8, op)
    partitions.append(alpha)
    expected["alpha"] = bytes(image)

    # ---- partition "beta": delta-only, must be reported NEEDS_BASELINE ------
    beta = fb(1, b"beta") + fb(7, partition_info(BLOCK * 4, b"\x42" * 32))
    beta += fb(8, delta_op(10, [(0, 4)], [(0, 4)], BLOCK * 4, BLOCK * 4))  # BROTLI_BSDIFF
    beta += fb(8, delta_op(4, [(0, 2)], [(2, 2)], BLOCK * 2, BLOCK * 2))   # SOURCE_COPY
    partitions.append(beta)

    manifest = fv(3, BLOCK) + fv(12, 9)
    for part in partitions:
        manifest += fb(13, part)

    with open(path, "wb") as f:
        f.write(b"CrAU")
        f.write(struct.pack(">Q", 2))              # version
        f.write(struct.pack(">Q", len(manifest)))
        f.write(struct.pack(">I", 0))              # metadata signature size
        f.write(manifest)
        f.write(blobs)
    return expected


def main():
    keep = "--keep" in sys.argv
    tmp = tempfile.mkdtemp(prefix="payload_selftest_")
    try:
        payload = os.path.join(tmp, "payload.bin")
        expected = build_payload(payload)
        print("built synthetic payload: %s (%d bytes)" % (payload, os.path.getsize(payload)))

        print("\n--- list mode ---")
        r = subprocess.run([sys.executable, EXTRACTOR, payload, "--quiet"],
                           capture_output=True, text=True)
        print(r.stdout or r.stderr)

        print("--- extract alpha (REPLACE/BZ/XZ/ZSTD/ZERO) with --verify ---")
        out = os.path.join(tmp, "out")
        r = subprocess.run([sys.executable, EXTRACTOR, payload, "--out", out,
                            "--partitions", "alpha", "--verify"],
                           capture_output=True, text=True)
        print(r.stdout or r.stderr)
        img = os.path.join(out, "alpha.img")
        ok = False
        if os.path.exists(img):
            with open(img, "rb") as f:
                got = f.read()
            ok = got == expected["alpha"]
            print("byte-for-byte compare vs expected image: %s (%d vs %d bytes)"
                  % ("PASS" if ok else "FAIL", len(got), len(expected["alpha"])))
        else:
            print("FAIL: alpha.img not produced")

        print("--- beta must be skipped as NEEDS_BASELINE ---")
        r2 = subprocess.run([sys.executable, EXTRACTOR, payload, "--out", out,
                             "--partitions", "beta"],
                            capture_output=True, text=True)
        print(r2.stdout or r2.stderr)
        beta_ok = "needs a baseline" in (r2.stdout + r2.stderr) and r2.returncode == 2

        print("\n=== SELFTEST %s ===" % ("PASS" if (ok and beta_ok) else "FAIL"))
        print("  self-contained extraction + sha256 verify : %s" % ("PASS" if ok else "FAIL"))
        print("  delta partition detected as NEEDS_BASELINE: %s" % ("PASS" if beta_ok else "FAIL"))
        return 0 if (ok and beta_ok) else 1
    finally:
        if keep:
            print("kept tmp dir: %s" % tmp)
        else:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
