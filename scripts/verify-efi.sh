#!/bin/bash
# verify-efi.sh — 开箱前的自检：结构 / 引用完整性 / ocvalidate / 哈希
#
# 用法:
#   ./scripts/verify-efi.sh ./EFI
#   ./scripts/verify-efi.sh /Volumes/EFI/EFI
#
# 退出码 0 = 全部通过（可以拿去开机）；非 0 = 有问题，别刷。
# 依赖：只有 macOS 自带工具（bash / PlistBuddy / shasum / du）。

set -uo pipefail

EFI="${1:-./EFI}"
FAIL=0
WARN=0
PB=/usr/libexec/PlistBuddy

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m[ok]\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m[FAIL]\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
warn() { printf '  \033[33m[warn]\033[0m %s\n' "$*"; WARN=$((WARN+1)); }

say "== 检查 $EFI =="

# ---------- 1. 基本结构 ----------
say "[1] 结构"
for p in "BOOT/BOOTx64.efi" "OC/OpenCore.efi" "OC/config.plist" "OC/ACPI" "OC/Kexts" "OC/Drivers"; do
  if [ -e "$EFI/$p" ]; then ok "$p"; else bad "缺少 $p"; fi
done

# ---------- 2. config 可解析 ----------
say "[2] config.plist 可解析"
if ! $PB -c "Print :Kernel:Add" "$EFI/OC/config.plist" >/dev/null 2>&1; then
  bad "plist 无法解析，后面的检查没有意义"
  exit 1
fi
ok "plist 语法正确"

# ---------- 3. 引用完整性 ----------
say "[3] 引用完整性"

# 3.1 ACPI
ACPI_N=$($PB -c "Print :ACPI:Add" "$EFI/OC/config.plist" | grep -c '^ *Dict {')
i=0
while [ "$i" -lt "$ACPI_N" ]; do
  f=$($PB -c "Print :ACPI:Add:$i:Path" "$EFI/OC/config.plist" 2>/dev/null)
  en=$($PB -c "Print :ACPI:Add:$i:Enabled" "$EFI/OC/config.plist" 2>/dev/null)
  if [ -f "$EFI/OC/ACPI/$f" ]; then ok "ACPI/$f (Enabled=$en)"; else bad "ACPI/$f 不存在"; fi
  i=$((i+1))
done

# 3.2 Drivers
DRV_N=$($PB -c "Print :UEFI:Drivers" "$EFI/OC/config.plist" | grep -c '^ *Dict {')
i=0
while [ "$i" -lt "$DRV_N" ]; do
  f=$($PB -c "Print :UEFI:Drivers:$i:Path" "$EFI/OC/config.plist" 2>/dev/null)
  en=$($PB -c "Print :UEFI:Drivers:$i:Enabled" "$EFI/OC/config.plist" 2>/dev/null)
  if [ -f "$EFI/OC/Drivers/$f" ]; then ok "Drivers/$f (Enabled=$en)"; else bad "Drivers/$f 不存在"; fi
  i=$((i+1))
done

# 3.3 Kexts（只查 Enabled=true 的，禁用条目允许缺文件）
K_N=$($PB -c "Print :Kernel:Add" "$EFI/OC/config.plist" | grep -c '^ *Dict {')
ENABLED=0
MISSING=""
i=0
while [ "$i" -lt "$K_N" ]; do
  en=$($PB -c "Print :Kernel:Add:$i:Enabled" "$EFI/OC/config.plist" 2>/dev/null)
  bp=$($PB -c "Print :Kernel:Add:$i:BundlePath" "$EFI/OC/config.plist" 2>/dev/null)
  if [ "$en" = "true" ]; then
    ENABLED=$((ENABLED+1))
    [ -e "$EFI/OC/Kexts/$bp" ] || MISSING="$MISSING $bp"
  fi
  i=$((i+1))
done
if [ -z "$MISSING" ]; then
  ok "启用 kext 全部存在（$ENABLED / $K_N）"
else
  bad "启用但缺文件：$MISSING"
fi

# 3.4 Tools
T_N=$($PB -c "Print :Misc:Tools" "$EFI/OC/config.plist" | grep -c '^ *Dict {')
i=0
while [ "$i" -lt "$T_N" ]; do
  f=$($PB -c "Print :Misc:Tools:$i:Path" "$EFI/OC/config.plist" 2>/dev/null)
  if [ -f "$EFI/OC/Tools/$f" ]; then ok "Tools/$f"; else warn "Tools/$f 不存在（不影响开机）"; fi
  i=$((i+1))
done

# ---------- 4. 发布卫生检查 ----------
say "[4] 发布卫生"
BA=$($PB -c "Print :NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args" "$EFI/OC/config.plist" 2>/dev/null)
case "$BA" in
  *"-v "*|*"debug=0x100"*|*"keepsyms=1"*) warn "boot-args 还带调试参数：$BA" ;;
  *) ok "boot-args 干净：$BA" ;;
esac

TGT=$($PB -c "Print :Misc:Debug:Target" "$EFI/OC/config.plist" 2>/dev/null)
if [ "$TGT" = "0" ]; then ok "Misc.Debug.Target = 0"; else warn "Misc.Debug.Target = $TGT（发布版应为 0）"; fi

SER=$($PB -c "Print :PlatformInfo:Generic:SystemSerialNumber" "$EFI/OC/config.plist" 2>/dev/null)
case "$SER" in
  W00000000001|"") warn "SMBIOS 序列号是占位值（$SER），iMessage/App Store 会用不了" ;;
  *) ok "已配置序列号" ;;
esac

# ---------- 5. ocvalidate ----------
say "[5] ocvalidate"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OCV=""
for c in "$ROOT/tools/ocvalidate/ocvalidate" \
         "$ROOT/tools/opencore-release/Utilities/ocvalidate/ocvalidate" \
         "$ROOT/../tools/opencore-release/Utilities/ocvalidate/ocvalidate" \
         "$(command -v ocvalidate 2>/dev/null)"; do
  if [ -n "$c" ] && [ -x "$c" ]; then OCV="$c"; break; fi
done
if [ -n "$OCV" ]; then
  if out=$("$OCV" "$EFI/OC/config.plist" 2>&1); then
    echo "$out" | tail -3
    ok "ocvalidate 通过"
  else
    echo "$out"
    bad "ocvalidate 报错"
  fi
else
  warn "未找到 ocvalidate（把 OpenCore 的 Utilities/ocvalidate 放到 tools/ocvalidate/ 或加进 PATH）"
fi

# ---------- 6. 指纹 ----------
say "[6] 指纹"
say "  config.plist  $(shasum -a 256 "$EFI/OC/config.plist" | awk '{print $1}')"
say "  EFI 体积      $(du -sh "$EFI" | awk '{print $1}')"
say "  kext 目录数   $(ls -1 "$EFI/OC/Kexts" 2>/dev/null | wc -l | tr -d ' ')"

say ""
if [ "$FAIL" -gt 0 ]; then
  say "结果：$FAIL 项失败，$WARN 项警告 —— 不要拿去开机。"
  exit 1
fi
say "结果：全部通过（$WARN 项警告）。"
