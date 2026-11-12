#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make-release.py — 把一份「调试用 EFI」转成「发布用 EFI」

做的事（只有这些，全部幂等，可重复执行）：
  1. boot-args 去掉调试三件套：-v / debug=0x100 / keepsyms=1
  2. Misc.Debug.Target      = 0      （不再往 ESP 写 opencore-*.txt）
  3. Misc.Debug.SysReport   = false  （不再每次开机生成 SysReport）
  4. Misc.Debug.AppleDebug  = false  （不显示 Apple 引导日志）
  5. 删除 Misc.Entries 里 Enabled=false 的占位条目
  6. 复制整棵 EFI 树到输出目录
  7. 若本机有 ocvalidate，自动校验并打印 SHA-256

用法：
    python3 scripts/make-release.py --in ./EFI-work --out ./EFI
    python3 scripts/make-release.py --in ./EFI --check-only

注意：不碰 DeviceProperties / Quirks / kext 列表 / SMBIOS —— 那些是功能性的，
      发布版和调试版必须完全一致，否则「发布版能开机、调试版不能」这类问题永远查不清。
"""

import argparse
import hashlib
import os
import plistlib
import shutil
import subprocess
import sys

DEBUG_TOKENS = ("-v", "debug=0x100", "keepsyms=1")

RELEASE_DEBUG = {
    "Target": 0,
    "SysReport": False,
    "AppleDebug": False,
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def clean_boot_args(cfg):
    key = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
    nv = cfg.get("NVRAM", {}).get("Add", {}).get(key, {})
    if "boot-args" not in nv:
        return None, None
    old = nv["boot-args"]
    # 按空格切分，整词匹配才删（避免把 -igfxvesa 之类误伤）
    tokens = [t for t in old.split() if t not in DEBUG_TOKENS]
    new = " ".join(tokens)
    nv["boot-args"] = new
    return old, new


def clean_debug(cfg):
    dbg = cfg.setdefault("Misc", {}).setdefault("Debug", {})
    changed = {}
    for k, v in RELEASE_DEBUG.items():
        if dbg.get(k) != v:
            changed[k] = (dbg.get(k), v)
            dbg[k] = v
    return changed


def drop_disabled_entries(cfg):
    entries = cfg.get("Misc", {}).get("Entries", [])
    kept = [e for e in entries if e.get("Enabled", True)]
    dropped = len(entries) - len(kept)
    if dropped:
        cfg["Misc"]["Entries"] = kept
    return dropped


def find_ocvalidate(root):
    cands = [
        os.path.join(root, "tools/opencore-release/Utilities/ocvalidate/ocvalidate"),
        os.path.join(root, "Utilities/ocvalidate/ocvalidate"),
        shutil.which("ocvalidate"),
    ]
    for c in cands:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True, help="输入的 EFI 目录（含 BOOT/ 与 OC/）")
    ap.add_argument("--out", dest="dst", help="输出目录；--check-only 时可省略")
    ap.add_argument("--check-only", action="store_true", help="只校验，不写文件")
    args = ap.parse_args()

    src_cfg = os.path.join(args.src, "OC", "config.plist")
    if not os.path.isfile(src_cfg):
        sys.exit(f"找不到 {src_cfg}")

    with open(src_cfg, "rb") as f:
        cfg = plistlib.load(f)

    print(f"[in ] {src_cfg}")
    print(f"[in ] sha256 = {sha256(src_cfg)}")

    old_ba, new_ba = clean_boot_args(cfg)
    if old_ba is None:
        print("[warn] 没有找到 NVRAM.boot-args，跳过")
    else:
        print("[1/3] boot-args")
        print(f"      - {old_ba}")
        print(f"      + {new_ba}")

    changed = clean_debug(cfg)
    print("[2/3] Misc.Debug")
    if changed:
        for k, (o, n) in changed.items():
            print(f"      {k}: {o} -> {n}")
    else:
        print("      已经是发布值，无需改动")

    dropped = drop_disabled_entries(cfg)
    print(f"[3/3] Misc.Entries: 删除禁用占位条目 {dropped} 条")

    if args.check_only:
        return

    if not args.dst:
        sys.exit("需要 --out")

    if os.path.abspath(args.dst) == os.path.abspath(args.src):
        sys.exit("--out 不能等于 --in（先输出到新目录，验收后再替换）")

    if os.path.exists(args.dst):
        shutil.rmtree(args.dst)
    shutil.copytree(args.src, args.dst, symlinks=True)

    dst_cfg = os.path.join(args.dst, "OC", "config.plist")
    with open(dst_cfg, "wb") as f:
        plistlib.dump(cfg, f, sort_keys=False)

    print(f"[out] {dst_cfg}")
    print(f"[out] sha256 = {sha256(dst_cfg)}")

    ocv = find_ocvalidate(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if ocv:
        print(f"[chk] {ocv}")
        r = subprocess.run([ocv, dst_cfg], capture_output=True, text=True)
        print((r.stdout or r.stderr).strip())
        if r.returncode != 0:
            sys.exit("ocvalidate 校验失败，别拿去开机")
    else:
        print("[chk] 未找到 ocvalidate，跳过（强烈建议补上）")


if __name__ == "__main__":
    main()
