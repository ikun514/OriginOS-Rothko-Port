#!/usr/bin/env python3
"""analyze_vivo_boot_requirements.py -- 对比 vivo system 的 VINTF compatibility matrix 与
rothko vendor 侧 manifest，列出"vivo 要求、但 rothko vendor 没有提供"的 HAL，并按风险分级。

背景:
  - vivo system 镜像里的 /system/etc/vintf/compatibility_matrix*.xml（type=framework）
    声明了 system 侧要求 device(vendor/odm) 必须提供的 HAL。
  - rothko 的 /vendor/etc/vintf/manifest.xml + manifest/*.xml、/odm/etc/vintf/...（type=device）
    是 vendor 实际提供的 HAL 清单。
  - v0.2 用 vivo system + rothko vendor/odm：若 matrix 要求的 HAL 缺失，system_server/
    hwservicemanager 在启动时会报错/崩溃。本工具按"是否可能阻塞"分级，指导补 stub 的优先级。

用法:
  python analyze_vivo_boot_requirements.py \
      --vivo-vintf 01_analysis/vintf/vivo_system \
      --rothko-vintf 01_analysis/vintf/rothko_vendor 01_analysis/vintf/rothko_odm \
      --out 01_analysis/vivo_boot_requirements.json --md 01_analysis/vivo_boot_requirements.md
  --selftest  用内置小样例验证逻辑（不需要设备/镜像）

分级规则（启发式，供决策参考）:
  BLOCKER_HIGH : matrix 要求（非 optional）且 HAL 名属于"system_server 启动强依赖"集合
  BLOCKER_MED  : matrix 要求（非 optional），非强依赖集合（可能延迟/降级）
  OPTIONAL     : matrix 里 optional="true"
"""
import argparse
import glob
import json
import os
import sys
import xml.etree.ElementTree as ET

# system_server / 启动早期强依赖的 HAL（按 AOSP 常见启动路径 + 常见厂商实现）
CRITICAL_HALS = {
    "android.hardware.health",
    "android.hardware.power",
    "android.hardware.audio",
    "android.hardware.graphics.allocator",
    "android.hardware.graphics.composer",
    "android.hardware.graphics.mapper",
    "android.hardware.keymaster",
    "android.hardware.security.keymint",
    "android.hardware.security.sharedsecret",
    "android.hardware.security.secureclock",
    "android.hardware.identity",
    "android.hardware.gatekeeper",
    "android.hardware.weaver",
    "android.hardware.vibrator",
    "android.hardware.sensors",
    "android.hardware.usb",
    "android.hardware.thermal",
    "android.hardware.boot",
    "android.hardware.camera.provider",
    "android.hardware.camera.device",
    "android.hardware.bluetooth",
    "android.hardware.wifi",
    "android.hardware.radio",
    "android.hardware.neuralnetworks",
    "android.hardware.drm",
    "android.hardware.media.c2",
    "android.hardware.media.omx",
    "android.hardware.memtrack",
    "android.hardware.secure_element",
    "android.hardware.oemlock",
    "android.hardware.rebootescrow",
    "android.hardware.dumpstate",
    "android.hardware.fastboot",
    "android.hardware.light",
    "android.hardware.power.stats",
    "android.hardware.health.storage",
    "android.hardware.renderscript",
    "android.hardware.configstore",
    "android.hardware.tetheroffload",
    "android.hardware.contexthub",
    "android.hardware.uwb",
    "android.hardware.nfc",
}

CRITICAL_PREFIXES = (
    "android.hardware.graphics.",
    "android.hardware.camera.",
    "android.hardware.security.",
    "android.hardware.media.",
    "android.hardware.audio.",
    "android.hardware.health.",
    "android.hardware.radio.",
)


def parse_xml(path):
    try:
        return ET.parse(path).getroot()
    except Exception as e:
        print("WARN: parse %s failed: %s" % (path, e), file=sys.stderr)
        return None


def parse_versions(elem):
    """<version>1.2</version> / <version>1</version> / <fqname>@1.0::IFoo/default</fqname>"""
    out = []
    for v in elem.findall("version"):
        try:
            txt = (v.text or "").strip()
            if not txt:
                continue
            parts = txt.split(".")
            out.append((int(parts[0]), int(parts[1]) if len(parts) > 1 else 0))
        except Exception:
            pass
    return out


def parse_ifaces(elem):
    ifaces = []
    for it in elem.findall("interface"):
        nm = (it.findtext("name") or "").strip()
        insts = [(i.text or "").strip() for i in it.findall("instance") if (i.text or "").strip()]
        if nm:
            ifaces.append({"name": nm, "instances": insts})
    return ifaces


def normalize_hal(h):
    fmt = (h.get("format") or "hidl").strip()
    name = (h.findtext("name") or "").strip()
    if not name:
        return None
    versions = parse_versions(h)
    ifaces = parse_ifaces(h)
    fq = []
    for f in h.findall("fqname"):
        txt = (f.text or "").strip()
        if txt:
            fq.append(txt)
    return {
        "format": fmt,
        "name": name,
        "versions": versions,
        "interfaces": ifaces,
        "fqnames": fq,
        "optional": (h.get("optional") or "false").strip().lower() == "true",
    }


def collect(dirpaths, kind):
    """kind: 'matrix' -> 取 compatibility-matrix 根; 'manifest' -> 取 manifest 根"""
    result = []
    for d in dirpaths:
        if not os.path.isdir(d):
            continue
        files = sorted(glob.glob(os.path.join(d, "*.xml")))
        files += sorted(glob.glob(os.path.join(d, "manifest", "*.xml")))
        for p in files:
            root = parse_xml(p)
            if root is None:
                continue
            tag = root.tag
            if kind == "matrix" and tag != "compatibility-matrix":
                continue
            if kind == "manifest" and tag != "manifest":
                continue
            for h in root.findall("hal"):
                nh = normalize_hal(h)
                if nh:
                    nh["_file"] = os.path.basename(p)
                    nh["_matrix_type"] = (root.get("type") or "").strip()
                    nh["_matrix_version"] = (root.get("version") or "").strip()
                    result.append(nh)
    return result


def version_ok(req, have):
    """AIDL: major 必须相等（minor 无所谓，vendor 可以更高）;
       HIDL: major 相等且 have.minor >= req.minor"""
    if not req:
        return True
    for (rmaj, rmin) in req:
        for (hmaj, hmin) in have:
            if hmaj == rmaj and (hmin >= rmin):
                return True
    return False


def iface_ok(req_ifaces, have_ifaces):
    """matrix 里列出的 interface+instance 都必须被 manifest 提供"""
    have_map = {x["name"]: set(x["instances"]) for x in have_ifaces}
    for ri in req_ifaces:
        if ri["name"] not in have_map:
            return False, "missing interface %s" % ri["name"]
        for inst in ri["instances"]:
            if inst not in have_map[ri["name"]]:
                return False, "missing instance %s/%s" % (ri["name"], inst)
    return True, ""


def severity(req):
    name = req["name"]
    if req["optional"]:
        return "OPTIONAL"
    if name in CRITICAL_HALS or any(name.startswith(p) for p in CRITICAL_PREFIXES):
        return "BLOCKER_HIGH"
    return "BLOCKER_MED"


def analyze(vivo_vintf_dirs, rothko_vintf_dirs, verbose=False):
    matrices = collect(vivo_vintf_dirs, "matrix")
    manifests = collect(rothko_vintf_dirs, "manifest")
    # 按 (format, name) 建索引
    have = {}
    for h in manifests:
        have.setdefault((h["format"], h["name"]), []).append(h)

    missing = []
    satisfied = 0
    for req in matrices:
        if req.get("_matrix_type") == "device":
            continue  # vivo system 里也可能带 device 类型 matrix（针对自身 vendor），跳过
        cands = have.get((req["format"], req["name"]), [])
        ok = False
        reason = "not declared by rothko vendor/odm manifest"
        for c in cands:
            if not version_ok(req["versions"], c["versions"]):
                reason = "declared but version incompatible (req=%s have=%s)" % (req["versions"], c["versions"])
                continue
            iok, why = iface_ok(req["interfaces"], c["interfaces"])
            if not iok:
                reason = "declared but %s" % why
                continue
            ok = True
            break
        if ok:
            satisfied += 1
            continue
        sev = severity(req)
        missing.append({
            "format": req["format"],
            "name": req["name"],
            "versions": req["versions"],
            "interfaces": req["interfaces"],
            "fqnames": req["fqnames"],
            "optional_in_matrix": req["optional"],
            "severity": sev,
            "reason": reason,
            "matrix_file": req["_file"],
            "matrix_version": req["_matrix_version"],
        })

    # 汇总：同名 HAL 可能在多个 matrix 文件重复，去重合并
    merged = {}
    for m in missing:
        key = (m["format"], m["name"], json.dumps(m["versions"]))
        if key in merged:
            merged[key]["occurrences"] += 1
            merged[key]["matrix_file"] += "," + m["matrix_file"]
            continue
        mm = dict(m)
        mm["occurrences"] = 1
        merged[key] = mm
    out = list(merged.values())
    order = {"BLOCKER_HIGH": 0, "BLOCKER_MED": 1, "OPTIONAL": 2}
    out.sort(key=lambda x: (order.get(x["severity"], 3), x["name"]))

    summary = {
        "matrix_hal_entries": len(matrices),
        "rothko_manifest_hal_entries": len(manifests),
        "satisfied": satisfied,
        "missing_unique": len(out),
        "missing_by_severity": {
            "BLOCKER_HIGH": sum(1 for x in out if x["severity"] == "BLOCKER_HIGH"),
            "BLOCKER_MED": sum(1 for x in out if x["severity"] == "BLOCKER_MED"),
            "OPTIONAL": sum(1 for x in out if x["severity"] == "OPTIONAL"),
        },
    }
    return {"summary": summary, "missing": out,
            "matrices": sorted({m["_file"] for m in matrices}),
            "manifests": sorted({m["_file"] for m in manifests})}


def print_md(res, out_md):
    s = res["summary"]
    lines = []
    lines.append("# vivo system VINTF 需求 vs rothko vendor HAL 覆盖\n")
    lines.append("- vivo matrix 条目: %d" % s["matrix_hal_entries"])
    lines.append("- rothko manifest HAL 条目: %d" % s["rothko_manifest_hal_entries"])
    lines.append("- 已满足: %d" % s["satisfied"])
    lines.append("- 缺失(去重): %d  (BLOCKER_HIGH=%d, BLOCKER_MED=%d, OPTIONAL=%d)"
                 % (s["missing_unique"], s["missing_by_severity"]["BLOCKER_HIGH"],
                    s["missing_by_severity"]["BLOCKER_MED"], s["missing_by_severity"]["OPTIONAL"]))
    lines.append("")
    lines.append("| severity | format | HAL | versions | 缺失原因 | matrix 文件 |")
    lines.append("|---|---|---|---|---|---|")
    for m in res["missing"]:
        vers = ",".join("%d.%d" % v for v in m["versions"]) if m["versions"] else (m["fqnames"][0] if m["fqnames"] else "-")
        lines.append("| %s | %s | `%s` | %s | %s | %s |"
                     % (m["severity"], m["format"], m["name"], vers, m["reason"], m["matrix_file"]))
    txt = "\n".join(lines) + "\n"
    with open(out_md, "w", encoding="utf-8") as f:
        f.write(txt)
    print(txt)
    print("[md] -> %s" % out_md)


SELFTEST_MATRIX = """<?xml version="1.0" encoding="UTF-8"?>
<compatibility-matrix version="1.0" type="framework">
  <hal format="aidl" optional="false">
    <name>android.hardware.health</name>
    <version>3</version>
    <interface><name>IHealth</name><instance>default</instance></interface>
  </hal>
  <hal format="aidl" optional="false">
    <name>android.hardware.vibrator</name>
    <version>3</version>
    <interface><name>IVibrator</name><instance>default</instance></interface>
  </hal>
  <hal format="hidl">
    <name>android.hardware.camera.provider</name>
    <version>2.4</version>
    <interface><name>ICameraProvider</name><instance>legacy/0</instance></interface>
  </hal>
  <hal format="aidl" optional="true">
    <name>android.hardware.nfc</name>
    <version>1</version>
    <interface><name>INfc</name><instance>default</instance></interface>
  </hal>
  <hal format="aidl" optional="false">
    <name>android.hardware.some.optionalmissing</name>
    <version>1</version>
  </hal>
</compatibility-matrix>
"""

SELFTEST_MANIFEST = """<?xml version="1.0" encoding="UTF-8"?>
<manifest version="1.0" type="device">
  <hal format="aidl">
    <name>android.hardware.health</name>
    <version>2</version>
    <interface><name>IHealth</name><instance>default</instance></interface>
  </hal>
  <hal format="hidl">
    <name>android.hardware.camera.provider</name>
    <version>2.3</version>
    <interface><name>ICameraProvider</name><instance>legacy/0</instance></interface>
  </hal>
  <hal format="aidl">
    <name>android.hardware.vibrator</name>
    <version>3</version>
    <interface><name>IVibrator</name><instance>default</instance></interface>
  </hal>
</manifest>
"""


def selftest():
    import tempfile
    d = tempfile.mkdtemp(prefix="vintf_selftest_")
    vd = os.path.join(d, "vivo")
    rd = os.path.join(d, "rothko")
    os.makedirs(vd); os.makedirs(rd)
    open(os.path.join(vd, "compatibility_matrix.test.xml"), "w", encoding="utf-8").write(SELFTEST_MATRIX)
    open(os.path.join(rd, "manifest.xml"), "w", encoding="utf-8").write(SELFTEST_MANIFEST)
    res = analyze([vd], [rd])
    print(json.dumps(res["summary"], indent=2))
    expected = {
        ("BLOCKER_HIGH", "android.hardware.camera.provider"),   # version 2.4 > 2.3
        ("BLOCKER_HIGH", "android.hardware.health"),            # version 3 > 2
        ("BLOCKER_MED", "android.hardware.some.optionalmissing"),
        ("OPTIONAL", "android.hardware.nfc"),
    }
    got = {(m["severity"], m["name"]) for m in res["missing"]}
    print("missing:", sorted(got))
    ok = got == expected
    print("SELFTEST:", "PASS" if ok else "FAIL (expected %s)" % sorted(expected))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vivo-vintf", nargs="+", default=[])
    ap.add_argument("--rothko-vintf", nargs="+", default=[])
    ap.add_argument("--out", default="01_analysis/vivo_boot_requirements.json")
    ap.add_argument("--md", default="01_analysis/vivo_boot_requirements.md")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        sys.exit(selftest())
    if not args.vivo_vintf or not args.rothko_vintf:
        print(__doc__)
        sys.exit(2)
    res = analyze(args.vivo_vintf, args.rothko_vintf)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(res, f, indent=2, ensure_ascii=False)
    print("[json] -> %s" % args.out)
    print_md(res, args.md)


if __name__ == "__main__":
    main()
