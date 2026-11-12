#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""partition_budget.py -- logical-partition footprint budget for the OriginOS -> rothko port.

Reads vivo PD2339 final partition sizes from the parsed payload manifest JSON
(01_analysis/vivo_payload_full.json, produced by payload_extract.py --json) and
compares them against the fixed physical capacity of rothko's `super` partition.

super is a dm-linear (uncompressed) container: every byte of a logical partition
occupies a byte of super, so the budget is a pure sum.  Upper bound is the
physical size of the super partition, minus the lp metadata + alignment reserve.

Usage:
    python partition_budget.py [vivo_payload_full.json] [--out budget_tables.md]
"""

import json
import os
import sys

G = 1024.0 ** 3
MIB = 1024.0 ** 2

# --------------------------------------------------------------------------- #
# Table B -- rothko (Redmi K70 Ultra) current logical partitions, measured on device
# --------------------------------------------------------------------------- #
ROTHKO = {
    "system": 879894528,
    "vendor": 1644707840,
    "product": 4478963712,
    "system_ext": 936296448,
    "odm": 881057792,
    "odm_dlkm": 348160,
    "vendor_dlkm": 21970944,
    "mi_ext": 126640128,
}
ROTHKO_SUPER = 9663676416          # /dev/block/by-name/super physical size (9 GiB)
SUPER_RESERVE = 60 * 1024 * 1024   # lp metadata (2 x ~1 MiB) + backup geometry + alignment slack

# fallback vivo numbers if the JSON is unavailable
VIVO_FALLBACK = {
    "system": 7934083072,
    "vendor": 3135754240,
    "product": 393981952,
    "system_ext": 411910144,
    "odm": 4780032,
    "odm_dlkm": 348160,
    "vendor_dlkm": 45801472,
    "system_dlkm": 14913536,
}
VIVO_DYNAMIC = ["system", "vendor", "product", "system_ext", "odm",
                "odm_dlkm", "vendor_dlkm", "system_dlkm"]

OUT = []


def p(s=""):
    OUT.append(s)


def load_vivo(path):
    if not path or not os.path.exists(path):
        return dict(VIVO_FALLBACK)
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    out = {}
    for part in d["partitions"]:
        if part["name"] in VIVO_DYNAMIC:
            out[part["name"]] = part["size"]
    for k, v in VIVO_FALLBACK.items():
        out.setdefault(k, v)
    return out


def table(title, rows):
    p("### " + title)
    p()
    p("| partition | bytes | GiB | GB |")
    p("|---|---:|---:|---:|")
    for name, n in rows:
        p("| %s | %d | %.3f | %.2f |" % (name, n, n / G, n / 1e9))
    tot = sum(n for _, n in rows)
    p("| **total** | **%d** | **%.3f** | **%.2f** |" % (tot, tot / G, tot / 1e9))
    p()


def main():
    args = [a for a in sys.argv[1:]]
    json_path = None
    out_path = None
    i = 0
    while i < len(args):
        if args[i] == "--out" and i + 1 < len(args):
            out_path = args[i + 1]
            i += 2
            continue
        json_path = args[i]
        i += 1
    if json_path is None:
        json_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                 "..", "01_analysis", "vivo_payload_full.json")

    vivo = load_vivo(json_path)
    vivo_rows = [(k, vivo[k]) for k in VIVO_DYNAMIC if k in vivo]
    rothko_rows = [(k, ROTHKO[k]) for k in ROTHKO]
    rothko_sum = sum(ROTHKO.values())
    vivo_sum = sum(n for _, n in vivo_rows)
    headroom = ROTHKO_SUPER - rothko_sum - SUPER_RESERVE

    r_sys, v_sys = ROTHKO["system"], vivo["system"]
    base = (ROTHKO["vendor"] + ROTHKO["odm"] + ROTHKO["odm_dlkm"] + ROTHKO["vendor_dlkm"])
    mi = ROTHKO["mi_ext"]
    vivo_triple = vivo["system"] + vivo["product"] + vivo["system_ext"]
    placeholder = 64 * 1024 * 1024   # two 32 MiB placeholder product/system_ext

    p("# Partition footprint budget (super = %.0f GiB / %d bytes)" % (ROTHKO_SUPER / G, ROTHKO_SUPER))
    p()
    table("Table A -- vivo PD2339 (OriginOS 16.2.13.1) dynamic partitions", vivo_rows)
    table("Table B -- rothko (Redmi K70 Ultra) current logical partitions", rothko_rows)

    p("## Capacity constraint")
    p()
    p("| item | bytes | GiB |")
    p("|---|---:|---:|")
    p("| super physical size | %d | %.3f |" % (ROTHKO_SUPER, ROTHKO_SUPER / G))
    p("| rothko logical partitions now | %d | %.3f |" % (rothko_sum, rothko_sum / G))
    p("| reserve (lp metadata / alignment) | %d | %.3f |" % (SUPER_RESERVE, SUPER_RESERVE / G))
    p("| **usable headroom** | **%d** | **%.3f** |" % (headroom, headroom / G))
    p("| vivo all dynamic partitions | %d | %.3f |" % (vivo_sum, vivo_sum / G))
    p()

    only_swap = rothko_sum - r_sys + v_sys
    p("## Question 1: replace ONLY system, keep every other rothko partition")
    p()
    p("- rothko total %.3f GiB - rothko system %.3f GiB + vivo system %.3f GiB = **%.3f GiB**"
      % (rothko_sum / G, r_sys / G, v_sys / G, only_swap / G))
    p("- over the %.0f GiB hard cap by **%.3f GiB**; net growth is %.3f GiB while the free headroom is only %.3f GiB"
      % (ROTHKO_SUPER / G, only_swap / G - ROTHKO_SUPER / G,
         (v_sys - r_sys) / G, headroom / G))
    p()
    p("Even dropping rothko `product` (4.171 GiB) as well does not save the naive swap:")
    p("  %.3f GiB -> still over by %.3f GiB." % (
        (only_swap - ROTHKO["product"]) / G,
        (only_swap - ROTHKO["product"]) / G - ROTHKO_SUPER / G))
    p()

    combos = [
        ("Combo 1", "full port: vivo system+product+system_ext + rothko vendor/odm/dlkm + mi_ext",
         vivo_triple + base + mi,
         "most complete: keeps the whole OriginOS app/service set, and mi_ext for rothko HyperOS vendor services"),
        ("Combo 2", "full port but no mi_ext",
         vivo_triple + base,
         "saves 0.118 GiB; only safe if rothko vendor init/fstab never mounts /mi_ext"),
        ("Combo 3", "minimal: only vivo system + rothko vendor/odm/dlkm, product/system_ext as 64 MiB placeholders",
         vivo["system"] + base + placeholder,
         "drops vivo product/system_ext (HyperOS-side apps lost); highest boot risk"),
    ]
    p("## Question 2: three candidate combinations")
    p()
    p("rothko kept set (vendor family, hardware-bound, cannot be dropped): vendor + odm + odm_dlkm + vendor_dlkm = %.3f GiB"
      % (base / G))
    p()
    p("| combo | content | total GiB | margin vs 9 GiB | must shrink vivo system by |")
    p("|---|---|---:|---:|---:|")
    for name, desc, total, _note in combos:
        margin = ROTHKO_SUPER - SUPER_RESERVE - total
        p("| %s | %s | %.3f | %+.0f MiB | %.3f GiB |"
          % (name, desc, total / G, margin / MIB, max(0.0, -margin) / G))
    p()
    for name, desc, total, note in combos:
        margin = ROTHKO_SUPER - SUPER_RESERVE - total
        p("- **%s** (%.3f GiB, margin %+.0f MiB): %s" % (name, total / G, margin / MIB, note))
    p()

    p("## Max allowed vivo system size per combo")
    p()
    p("| combo | fixed non-system part GiB | max vivo system GiB | shrink needed vs 7.389 GiB |")
    p("|---|---:|---:|---:|")
    caps = [
        ("Combo 1", vivo["product"] + vivo["system_ext"] + base + mi),
        ("Combo 2", vivo["product"] + vivo["system_ext"] + base),
        ("Combo 3", base + placeholder),
    ]
    for name, fixed in caps:
        cap = ROTHKO_SUPER - SUPER_RESERVE - fixed
        p("| %s | %.3f | %.3f | %.3f GiB (%.1f%%) |"
          % (name, fixed / G, cap / G, (v_sys - cap) / G, (v_sys - cap) / v_sys * 100))
    p()

    p("## Conclusions")
    p()
    p("1. The naive swap (only system) is impossible: over by %.1f GiB." % (only_swap / G - ROTHKO_SUPER / G))
    p("2. Even the most aggressive combo 3 requires vivo system <= %.3f GiB (currently 7.389 GiB)."
      % ((ROTHKO_SUPER - SUPER_RESERVE - base - placeholder) / G))
    p("3. The one lever that does not require deleting files: rebuild system.erofs with")
    p("   zstd/lz4hc compression + dedupe when repacking. If the vivo image is uncompressed")
    p("   or only lz4-level, zstd-19 typically saves 15-30%%: 7.389 x 0.80 = %.2f GiB, which"
      % (7.389 * 0.80))
    p("   makes combo 3 fit outright and combo 2/1 close enough for targeted pruning.")
    p("4. Whether mi_ext can be dropped depends on rothko's vendor init/fstab forcing a mount;")
    p("   confirm against the vendor image in 02_base before deciding.")

    text = "\n".join(OUT) + "\n"
    if out_path:
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(text)
        print("wrote %s (%d bytes)" % (out_path, len(text.encode("utf-8"))))
    else:
        try:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
