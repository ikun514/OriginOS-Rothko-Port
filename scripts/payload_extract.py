#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""payload_extract.py -- Android OTA payload.bin parser / extractor (AOSP update_engine).

Pure-python, no protoc, no external AOSP tools. Works on full payloads and inspects
incremental (delta) payloads, reporting which partitions would need a baseline image.

Binary layout (update_engine, payload_metadata.cc):
    offset 0 : magic          'CrAU'          (4 bytes)
    offset 4 : version        u64 big-endian  (2 for current OTA)
    offset 12: manifest_size  u64 big-endian
    offset 20: sig_size       u32 big-endian  (ONLY when version >= 2)
    offset 20/24 : DeltaArchiveManifest protobuf, manifest_size bytes
    then     : metadata signature              sig_size bytes
    data blob area starts at:
                 version 1 -> 20 + manifest_size
                 version 2 -> 24 + manifest_size + sig_size      <-- data_offset is relative to THIS

Protobuf messages actually used (update_metadata.proto):
    DeltaArchiveManifest { 3 block_size, 4 signatures_offset, 5 signatures_size,
                           12 minor_version, 13 repeated PartitionUpdate partitions,
                           15 dynamic_partition_metadata }
    PartitionUpdate      { 1 partition_name, 7 size, 8 repeated InstallOperation operations,
                           13 old_partition_info, 14 new_partition_info }
    InstallOperation     { 1 type, 2 data_offset, 3 data_length,
                           4 repeated Extent src_extents, 5 src_length,
                           6 repeated Extent dst_extents, 7 dst_length,
                           8 data_sha256_hash, 9 src_sha256_hash }
    Extent               { 1 start_block, 2 num_blocks }         (* block_size bytes each)
    PartitionInfo        { 1 size, 2 hash }

Operation types: 0 REPLACE, 1 REPLACE_BZ, 2 MOVE*, 3 BSDIFF*, 4 SOURCE_COPY*,
  5 SOURCE_BSDIFF*, 6 ZERO, 7 DISCARD, 8 REPLACE_XZ, 9 PUFFDIFF*, 10 BROTLI_BSDIFF*,
  11 ZUCCHINI*, 12 LZ4DIFF_BSDIFF*, 13 LZ4DIFF_PUFFDIFF*, 14 REPLACE_ZSTD (vendor ext.)
  (* = needs baseline image -> reported as NEEDS_BASELINE and skipped)

Usage
    python payload_extract.py payload.bin                    # list partitions / ops
    python payload_extract.py payload.bin --json info.json   # + dump manifest summary JSON
    python payload_extract.py payload.bin --out DIR --verify # extract extractable partitions
    python payload_extract.py payload.bin --out DIR --partitions system,vendor --jobs 4
    python payload_extract.py payload.bin --probe-op 14      # identify an unknown/vendor op code
    python payload_extract.py update.zip                     # payload.bin inside a zip is handled

Notes
  * Optional decompressors are imported lazily: zstandard / brotli from 00_tools\\pylibs.
  * --partial additionally writes the partitions that need a baseline, with only the
    self-contained operations applied (holes stay zero). Such images are NOT bootable;
    they are for inspection / diffing only.
"""

import argparse
import bz2
import collections
import hashlib
import json
import lzma
import os
import struct
import sys
import time
import zipfile

MAGIC = b"CrAU"

OP_NAMES = {
    0: "REPLACE",
    1: "REPLACE_BZ",
    2: "MOVE",
    3: "BSDIFF",
    4: "SOURCE_COPY",
    5: "SOURCE_BSDIFF",
    6: "ZERO",
    7: "DISCARD",
    8: "REPLACE_XZ",
    9: "PUFFDIFF",
    10: "BROTLI_BSDIFF",
    11: "ZUCCHINI",
    12: "LZ4DIFF_BSDIFF",
    13: "LZ4DIFF_PUFFDIFF",
    14: "REPLACE_ZSTD",
}
# op types that cannot be produced without the previous (source) partition contents
NEEDS_BASELINE = {2, 3, 4, 5, 9, 10, 11, 12, 13}
SELF_CONTAINED = {0, 1, 6, 7, 8, 14}


# --------------------------------------------------------------------------- #
# generic protobuf wire-format reader
# --------------------------------------------------------------------------- #
def read_varint(buf, pos):
    result = 0
    shift = 0
    while True:
        b = buf[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            return result, pos
        shift += 7
        if shift > 70:
            raise ValueError("varint too long")


def parse_msg(buf):
    """Parse a protobuf message without schema -> {field_number: [(wire_type, value), ...]}."""
    fields = collections.defaultdict(list)
    pos = 0
    n = len(buf)
    while pos < n:
        key, pos = read_varint(buf, pos)
        field, wt = key >> 3, key & 7
        if wt == 0:
            val, pos = read_varint(buf, pos)
        elif wt == 1:
            val = buf[pos:pos + 8]
            pos += 8
        elif wt == 2:
            ln, pos = read_varint(buf, pos)
            val = buf[pos:pos + ln]
            pos += ln
        elif wt == 5:
            val = buf[pos:pos + 4]
            pos += 4
        else:
            raise ValueError("unsupported wire type %d (field %d)" % (wt, field))
        fields[field].append((wt, val))
    return fields


def gv(msg, field, default=0):
    """Get scalar (varint) field."""
    vals = msg.get(field)
    if not vals:
        return default
    for wt, v in vals:
        if wt == 0:
            return v
    return default


def gb(msg, field, default=b""):
    """Get length-delimited field."""
    vals = msg.get(field)
    if not vals:
        return default
    for wt, v in vals:
        if wt == 2:
            return v
    return default


def sub_msgs(msg, field):
    return [v for wt, v in msg.get(field, []) if wt == 2]


def sha256_hex(data):
    return hashlib.sha256(data).hexdigest()


# --------------------------------------------------------------------------- #
# payload header + manifest
# --------------------------------------------------------------------------- #
class Payload(object):
    def __init__(self, path):
        self.path = path
        with open(path, "rb") as f:
            head = f.read(4)
            if head != MAGIC:
                raise ValueError("%s: not a payload (magic=%r)" % (path, head))
            raw = f.read(8 + 8)
            if len(raw) != 16:
                raise ValueError("truncated header")
            self.version, self.manifest_size = struct.unpack(">QQ", raw)
            self.sig_size = 0
            if self.version >= 2:
                self.sig_size = struct.unpack(">I", f.read(4))[0]
            hdr = 4 + 8 + 8 + (4 if self.version >= 2 else 0)
            self.header_size = hdr
            self.manifest_raw = f.read(self.manifest_size)
            if len(self.manifest_raw) != self.manifest_size:
                raise ValueError("truncated manifest")
        # data blob area: header + manifest + metadata signature
        self.blob_offset = self.header_size + self.manifest_size + self.sig_size
        self.size = os.path.getsize(path)
        self.block_size = 4096
        self.minor_version = 0
        self.dynamic_partition_metadata = {}
        self.partitions = []
        self._parse_manifest()

    # ---- manifest ---------------------------------------------------------
    def _parse_manifest(self):
        m = parse_msg(self.manifest_raw)
        self.block_size = gv(m, 3, 4096) or 4096
        self.minor_version = gv(m, 12, 0)
        self.signatures_offset = gv(m, 4, 0)
        self.signatures_size = gv(m, 5, 0)
        dyn = gb(m, 15)
        if dyn:
            d = parse_msg(dyn)
            self.dynamic_partition_metadata = {
                "snapshot_enabled": bool(gv(d, 1, 0)),
                "vabc_enabled": bool(gv(d, 2, 0)),
                "vabc_compression_param": gb(d, 3).decode("utf-8", "replace"),
                "cow_version": gv(d, 4, 0),
            }
        for pbuf in sub_msgs(m, 13):
            self.partitions.append(self._parse_partition(pbuf))
        self.partitions.sort(key=lambda p: p["name"])

    def _parse_partition(self, pbuf):
        p = parse_msg(pbuf)
        name = gb(p, 1).decode("utf-8", "replace")
        # field 7: scalar 'size' in classic AOSP manifests, but a PartitionInfo
        # submessage ({1: size, 2: sha256}) in newer ones (minor_version >= 5).
        declared = 0
        for wt, v in p.get(7, []):
            if wt == 0:
                declared = v
        # field 6 = old_partition_info, field 7 (message form) = new_partition_info
        old_info = None
        for wt, v in p.get(6, []):
            if wt == 2:
                old_info = self._parse_partition_info(v)
                if old_info:
                    break
        new_info = None
        for wt, v in p.get(7, []):
            if wt == 2:
                new_info = self._parse_partition_info(v)
                if new_info:
                    break
        if new_info is None:
            new_info = self._find_partition_info(p, prefer=14)
        if old_info is None:
            old_info = self._find_partition_info(p, prefer=13)

        ops = [self._parse_op(o) for o in sub_msgs(p, 8)]
        old_ops = [self._parse_op(o) for o in sub_msgs(p, 6)]

        # final partition size: prefer max dst extent end (works even without field 7)
        max_dst = 0
        for o in ops:
            for start, num in o["dst"]:
                end = start + num
                if end > max_dst:
                    max_dst = end
        computed = max_dst * self.block_size
        final_size = declared or computed
        if new_info and new_info.get("size"):
            final_size = new_info["size"]

        counts = collections.Counter(OP_NAMES.get(o["type"], "OP_%d" % o["type"]) for o in ops)
        types = {o["type"] for o in ops}
        needs_base = bool(types & NEEDS_BASELINE)
        has_self = bool(types & SELF_CONTAINED)
        return {
            "name": name,
            "size": final_size,
            "declared_size": declared,
            "computed_size": computed,
            "ops": ops,
            "old_ops": old_ops,
            "n_ops": len(ops),
            "n_blocks": max_dst,
            "op_counts": dict(counts),
            "op_types": sorted(types),
            "needs_baseline": needs_base,
            # usable raw image only if every op is self-contained
            "extractable": not needs_base,
            "partial_possible": has_self,
            "new_partition_hash": new_info.get("hash") if new_info else b"",
            "old_partition_hash": old_info.get("hash") if old_info else b"",
        }

    def _parse_op(self, obuf):
        o = parse_msg(obuf)
        try:
            dtype = gv(o, 1, 0)
        except Exception:
            dtype = 0
        return {
            "type": dtype,
            "data_offset": gv(o, 2, 0),
            "data_length": gv(o, 3, 0),
            "src": [self._parse_extent(e) for e in sub_msgs(o, 4)],
            "src_length": gv(o, 5, 0),
            "dst": [self._parse_extent(e) for e in sub_msgs(o, 6)],
            "dst_length": gv(o, 7, 0),
            "data_hash": gb(o, 8),
            "src_hash": gb(o, 9),
        }

    @staticmethod
    def _parse_extent(ebuf):
        e = parse_msg(ebuf)
        return (gv(e, 1, 0), gv(e, 2, 0))

    @staticmethod
    def _parse_partition_info(raw):
        """Strictly parse a PartitionInfo {1: uint64 size, 2: bytes sha256(32)}."""
        try:
            pi = parse_msg(raw)
        except Exception:
            return None
        if not set(pi.keys()) <= {1, 2}:
            return None
        h = gb(pi, 2)
        if len(h) != 32:  # a real PartitionInfo always carries a 32 byte sha256
            return None
        return {"size": gv(pi, 1, 0), "hash": h}

    @classmethod
    def _find_partition_info(cls, pmsg, prefer):
        """Locate a PartitionInfo submessage in legacy layouts (field number varies)."""
        order = [prefer] + [f for f in (13, 14, 11, 12, 10, 9) if f != prefer]
        for f in order:
            for raw in sub_msgs(pmsg, f):
                pi = cls._parse_partition_info(raw)
                if pi:
                    return pi
        return None

    # ---- helpers ----------------------------------------------------------
    def blob(self, off, length):
        with open(self.path, "rb") as f:
            f.seek(self.blob_offset + off)
            return f.read(length)

    def summary(self):
        return {
            "payload": self.path,
            "payload_size": self.size,
            "version": self.version,
            "manifest_size": self.manifest_size,
            "metadata_signature_size": self.sig_size,
            "header_size": self.header_size,
            "data_blob_offset": self.blob_offset,
            "block_size": self.block_size,
            "minor_version": self.minor_version,
            "dynamic_partition_metadata": self.dynamic_partition_metadata,
            "n_partitions": len(self.partitions),
            "partitions": [
                {
                    "name": p["name"],
                    "size": p["size"],
                    "computed_size": p["computed_size"],
                    "n_ops": p["n_ops"],
                    "op_counts": p["op_counts"],
                    "needs_baseline": p["needs_baseline"],
                    "extractable": p["extractable"],
                    "new_partition_sha256": p["new_partition_hash"].hex(),
                    "old_partition_sha256": p["old_partition_hash"].hex(),
                }
                for p in self.partitions
            ],
        }


# --------------------------------------------------------------------------- #
# decompressors
# --------------------------------------------------------------------------- #
_OP14_DECODER = {"name": None}  # memo: which codec op type 14 actually uses


def _try_codecs(blob, expected):
    """Try the decompressors an OEM might use for a REPLACE-style op."""
    attempts = [
        ("zstd", lambda b: _zstd(b, expected)),
        ("brotli", lambda b: _brotli(b, expected)),
        ("xz", lambda b: lzma.decompress(b)),
        ("bz2", lambda b: bz2.decompress(b)),
    ]
    out = []
    for name, fn in attempts:
        try:
            data = fn(blob)
        except Exception as e:
            out.append((name, None, str(e)[:80]))
            continue
        out.append((name, data, ""))
    return out


def _zstd(blob, expected):
    import zstandard
    d = zstandard.ZstdDecompressor()
    try:
        return d.decompress(blob, max_output_size=max(expected, 1))
    except Exception:
        # stream form
        import io
        return d.stream_reader(io.BytesIO(blob)).read()


def _brotli(blob, expected):
    import brotli
    return brotli.decompress(blob)


def decode_blob(op, blob, block_size):
    """Return (data, codec) for a self-contained op."""
    t = op["type"]
    expected = op["dst_length"] or (sum(n for _, n in op["dst"]) * block_size)
    if t == 0 or t == 6 or t == 7:
        return blob, "raw"
    if t == 1:
        return bz2.decompress(blob), "bz2"
    if t == 8:
        try:
            return lzma.decompress(blob, format=lzma.FORMAT_XZ), "xz"
        except lzma.LZMAError:
            return lzma.decompress(blob), "lzma"
    if t == 14:
        # vendor extension: identify the actual codec once, then reuse
        if _OP14_DECODER["name"]:
            name = _OP14_DECODER["name"]
            if name == "zstd":
                return _zstd(blob, expected), "zstd"
            if name == "brotli":
                return brotli_decompress(blob), "brotli"
            if name == "xz":
                return lzma.decompress(blob), "xz"
            if name == "bz2":
                return bz2.decompress(blob), "bz2"
            if name == "raw":
                return blob, "raw"
        results = _try_codecs(blob, expected)
        good = [(n, d) for (n, d, _e) in results if d is not None and len(d) == expected]
        if not good:
            good = [(n, d) for (n, d, _e) in results if d is not None]
        if not good:
            raise ValueError("op14: no codec could decompress the blob (len=%d, expected=%d)"
                             % (len(blob), expected))
        name, data = good[0]
        _OP14_DECODER["name"] = name
        return data, name
    raise ValueError("op type %d is not self-contained" % t)


def brotli_decompress(blob):
    import brotli
    return brotli.decompress(blob)


# --------------------------------------------------------------------------- #
# extraction
# --------------------------------------------------------------------------- #
def extract_partition(payload_path, part, out_dir, verify=False, partial=False):
    t0 = time.time()
    p = Payload(payload_path)
    block_size = p.block_size
    final_size = part["size"]
    out_path = os.path.join(out_dir, part["name"] + ".img")
    written_ops = 0
    skipped_ops = 0
    codecs = collections.Counter()
    op_verify_fail = 0
    op_verify_done = 0

    with open(payload_path, "rb") as src, open(out_path, "wb") as dst:
        for op in part["ops"]:
            t = op["type"]
            dst_total = sum(n for _, n in op["dst"]) * block_size
            if t in NEEDS_BASELINE:
                skipped_ops += 1
                if not partial:
                    continue
                continue  # even in partial mode we cannot apply it: leave zeros
            if t in (6, 7):
                written_ops += 1
                continue  # file already zero-filled / truncated
            length = op["data_length"]
            if length == 0:
                continue
            src.seek(p.blob_offset + op["data_offset"])
            blob = src.read(length)
            if len(blob) != length:
                raise IOError("%s: short read for op at data_offset=%d" %
                              (part["name"], op["data_offset"]))
            if verify and op["data_hash"]:
                h = hashlib.sha256(blob).hexdigest()
                if h != op["data_hash"].hex():
                    op_verify_fail += 1
            data, codec = decode_blob(op, blob, block_size)
            codecs[codec] += 1
            if len(data) != dst_total:
                raise IOError("%s: op type %s produced %d bytes, dst extents expect %d"
                              % (part["name"], OP_NAMES.get(t, t), len(data), dst_total))
            if verify and op["data_hash"]:
                op_verify_done += 1
            off = 0
            for start_block, num_blocks in op["dst"]:
                nbytes = num_blocks * block_size
                dst.seek(start_block * block_size)
                dst.write(data[off:off + nbytes])
                off += nbytes
            written_ops += 1
        dst.truncate(final_size)

    # hash of the produced image
    h = hashlib.sha256()
    with open(out_path, "rb") as f:
        while True:
            chunk = f.read(8 << 20)
            if not chunk:
                break
            h.update(chunk)
    img_sha = h.hexdigest()
    status = "OK"
    if part["needs_baseline"] and not partial:
        status = "NEEDS_BASELINE"
    elif part["needs_baseline"]:
        status = "PARTIAL_NEEDS_BASELINE"
    verified = None
    if verify and part["new_partition_hash"]:
        verified = (img_sha == part["new_partition_hash"].hex())
        if not verified and status == "OK":
            status = "HASH_MISMATCH"
    return {
        "name": part["name"],
        "status": status,
        "out": out_path,
        "size": final_size,
        "sha256": img_sha,
        "expected_sha256": part["new_partition_hash"].hex(),
        "verified": verified,
        "ops_written": written_ops,
        "ops_skipped": skipped_ops,
        "codecs": dict(codecs),
        "op_hash_mismatch": op_verify_fail,
        "seconds": round(time.time() - t0, 2),
    }


# --------------------------------------------------------------------------- #
# reporting
# --------------------------------------------------------------------------- #
def human(n):
    if n is None:
        return "-"
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(n) < 1024.0 or unit == "TiB":
            return ("%.2f %s" % (n, unit)) if unit != "B" else ("%d B" % n)
        n /= 1024.0


def print_table(payload):
    print("payload : %s (%s)" % (payload.path, human(payload.size)))
    print("version : %d   manifest: %d B   metadata sig: %d B   block: %d   minor: %d"
          % (payload.version, payload.manifest_size, payload.sig_size,
             payload.block_size, payload.minor_version))
    print("data blob offset: %d (0x%x)" % (payload.blob_offset, payload.blob_offset))
    if payload.dynamic_partition_metadata:
        print("dynamic partition metadata: %s" % json.dumps(payload.dynamic_partition_metadata))
    print()
    hdr = "%-16s %12s %10s %-8s %-8s %s" % (
        "partition", "final size", "ops", "extract", "baseline", "op types")
    print(hdr)
    print("-" * len(hdr))
    for p in payload.partitions:
        print("%-16s %12s %10d %-8s %-8s %s" % (
            p["name"], human(p["size"]), p["n_ops"],
            "yes" if p["extractable"] else "no",
            "yes" if p["needs_baseline"] else "no",
            ", ".join("%s x%d" % (k, v) for k, v in sorted(p["op_counts"].items()))))
    print("-" * len(hdr))
    tot = sum(p["size"] for p in payload.partitions)
    n_ok = sum(1 for p in payload.partitions if p["extractable"])
    print("%d partitions, total final size %s (%d B); fully extractable now: %d/%d"
          % (len(payload.partitions), human(tot), tot, n_ok, len(payload.partitions)))
    if n_ok < len(payload.partitions):
        bad = [p["name"] for p in payload.partitions if not p["extractable"]]
        print("NEEDS_BASELINE (delta ops, cannot be rebuilt without the source image):")
        for i in range(0, len(bad), 8):
            print("   " + ", ".join(bad[i:i + 8]))


def probe_op(payload, optype, samples=3):
    print("probing op type %d (%s)" % (optype, OP_NAMES.get(optype, "?")))
    tried = 0
    for part in payload.partitions:
        hits = [o for o in part["ops"] if o["type"] == optype]
        if not hits:
            continue
        op = hits[0]
        blob = payload.blob(op["data_offset"], op["data_length"])
        expected = op["dst_length"] or sum(n for _, n in op["dst"]) * payload.block_size
        print("\n[%s] data_offset=%d data_length=%d dst_length=%d blob_sha256=%s"
              % (part["name"], op["data_offset"], op["data_length"], expected,
                 sha256_hex(blob)))
        if op["data_hash"]:
            print("  op.data_sha256_hash = %s  (match=%s)"
                  % (op["data_hash"].hex(), op["data_hash"].hex() == sha256_hex(blob)))
        for name, data, err in _try_codecs(blob, expected):
            if data is None:
                print("  %-8s FAIL %s" % (name, err))
            else:
                print("  %-8s ok   len=%d expected=%d %s"
                      % (name, len(data), expected, "MATCH" if len(data) == expected else "MISMATCH"))
        tried += 1
        if tried >= samples:
            break


# --------------------------------------------------------------------------- #
def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Parse/extract Android OTA payload.bin (AOSP update_engine format).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__)
    ap.add_argument("payload", help="payload.bin, or a .zip that contains payload.bin")
    ap.add_argument("--out", metavar="DIR", help="extract partitions into DIR")
    ap.add_argument("--partitions", metavar="LIST", default="",
                    help="comma separated subset of partition names (default: all)")
    ap.add_argument("--json", metavar="FILE", help="write manifest summary JSON to FILE")
    ap.add_argument("--verify", action="store_true",
                    help="verify per-op data hashes and whole-partition sha256")
    ap.add_argument("--partial", action="store_true",
                    help="also write partitions that need a baseline (holes = zeros, NOT bootable)")
    ap.add_argument("--jobs", type=int, default=4, help="parallel partitions during extraction (default 4)")
    ap.add_argument("--probe-op", type=int, metavar="N",
                    help="try to identify which codec op type N uses (e.g. 14 for vivo/oplus)")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)

    path = args.payload
    tmp_extracted = None
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as z:
            names = [n for n in z.namelist() if n.lower().endswith("payload.bin")]
            if not names:
                print("error: %s has no payload.bin (entries: %s)" % (path, z.namelist()[:20]),
                      file=sys.stderr)
                return 1
            member = names[0]
            base = os.path.dirname(os.path.abspath(path))
            target = os.path.join(base, "payload.bin")
            if os.path.exists(target) and os.path.getsize(target) == z.getinfo(member).file_size:
                print("using already-extracted %s" % target)
                path = target
            else:
                print("extracting %s (%s) from %s ..." % (member, human(z.getinfo(member).file_size), path))
                with z.open(member) as src, open(target, "wb") as dst:
                    while True:
                        chunk = src.read(16 << 20)
                        if not chunk:
                            break
                        dst.write(chunk)
                path = target
                tmp_extracted = target

    payload = Payload(path)
    if not args.quiet:
        print_table(payload)

    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(payload.summary(), f, indent=1, ensure_ascii=False)
        print("\nwrote %s" % args.json)

    if args.probe_op is not None:
        probe_op(payload, args.probe_op)
        return 0

    if not args.out:
        return 0

    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)
    wanted = [s.strip() for s in args.partitions.split(",") if s.strip()]
    todo = [p for p in payload.partitions if not wanted or p["name"] in wanted]
    if wanted:
        missing = sorted(set(wanted) - {p["name"] for p in payload.partitions})
        if missing:
            print("warning: partitions not present in payload: %s" % ", ".join(missing))
    runnable = [p for p in todo if p["extractable"] or args.partial]
    skipped = [p for p in todo if p not in runnable]
    if not runnable:
        print("\nnothing to extract: every selected partition needs a baseline image.")
        return 2

    print("\nextracting %d partition(s) into %s" % (len(runnable), out_dir))
    results = []
    if args.jobs <= 1 or len(runnable) == 1:
        for p in runnable:
            r = extract_partition(path, p, out_dir, args.verify, args.partial)
            results.append(r)
            _print_result(r)
    else:
        from concurrent.futures import ThreadPoolExecutor, as_completed
        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            futs = {ex.submit(extract_partition, path, p, out_dir, args.verify, args.partial): p
                    for p in runnable}
            for fut in as_completed(futs):
                r = fut.result()
                results.append(r)
                _print_result(r)

    results.sort(key=lambda r: r["name"])
    total = sum(r["size"] for r in results)
    print("\n--- summary ---")
    print("%-16s %-26s %12s %s" % ("partition", "status", "size", "sha256"))
    for r in results:
        print("%-16s %-26s %12s %s" % (r["name"], r["status"], human(r["size"]), r["sha256"]))
    print("%d image(s), %s total, %.1fs" % (len(results), human(total),
                                            sum(r["seconds"] for r in results)))
    if skipped:
        print("skipped (needs baseline): %s" % ", ".join(p["name"] for p in skipped))
    bad = [r for r in results if r["status"] != "OK"]
    if bad:
        print("WARNING: %d image(s) not fully reconstructed: %s"
              % (len(bad), ", ".join("%s(%s)" % (r["name"], r["status"]) for r in bad)))
        return 2
    return 0


def _print_result(r):
    extra = ""
    if r["codecs"]:
        extra += "  codecs=" + ",".join("%s x%d" % (k, v) for k, v in sorted(r["codecs"].items()))
    if r["verified"] is not None:
        extra += "  verified=%s" % r["verified"]
    if r["op_hash_mismatch"]:
        extra += "  OP_HASH_MISMATCH=%d" % r["op_hash_mismatch"]
    print("+ %-16s %-12s %s %5.1fs -> %s%s"
          % (r["name"], r["status"], human(r["size"]), r["seconds"], r["out"], extra))


if __name__ == "__main__":
    sys.exit(main())
