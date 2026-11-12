#!/bin/bash
# diagnose-macos.sh — 一次性取证：把这份输出贴到 issue 里，基本能定位 90% 的问题
#
# 用法:
#   bash scripts/diagnose-macos.sh            # 只读，不需要 root
#   bash scripts/diagnose-macos.sh > diag.txt 2>&1
#
# 会脱敏：序列号 / UUID / MAC / IP / SSID 只保留前 6 位或直接打码。

set -uo pipefail
mask() { sed -E 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/xx:xx:xx:xx:xx:xx/g' \
              | sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/x.x.x.x/g' \
              | sed -E 's/[A-Z0-9]{8,14}/<SERIAL>/g'; }

echo "########## 1) 系统 ##########"
sw_vers
echo
echo "########## 2) 硬件 ##########"
system_profiler SPHardwareDataType 2>/dev/null | sed -n '1,25p' | mask

echo
echo "########## 3) 显卡 / 显示 ##########"
system_profiler SPDisplaysDataType 2>/dev/null | mask
echo "--- ioreg ---"
ioreg -l 2>/dev/null | grep -E "AAPL,ig-platform-id|IOFBMemorySize|MetalPluginName" | head -10

echo
echo "########## 4) 音频 ##########"
system_profiler SPAudioDataType 2>/dev/null | sed -n '1,40p'
echo "--- HDEF layout ---"
ioreg -rn HDEF 2>/dev/null | grep -iE "layout-id|hda-gfx" | head
echo "--- kext ---"
kextstat 2>/dev/null | grep -Ei "AppleALC|VerbStub|AppleHDA" | awk '{print $6, $7}'

echo
echo "########## 5) 网络 ##########"
kextstat 2>/dev/null | grep -Ei "AirportItlwm|itlwm|IntelMausi" | awk '{print $6, $7}'
echo "--- 接口 ---"
ifconfig 2>/dev/null | grep -E "^en[0-9]|status:|inet " | head -20 | mask
echo "--- 无线详情 ---"
system_profiler SPAirPortDataType 2>/dev/null | sed -n '1,45p' | mask
echo "--- 蓝牙 ---"
system_profiler SPBluetoothDataType 2>/dev/null | sed -n '1,25p' | mask
kextstat 2>/dev/null | grep -Ei "IntelBluetooth|BlueTool|IntelBTPatcher" | awk '{print $6, $7}'

echo
echo "########## 6) CPU 电源管理 ##########"
echo -n "xcpm.mode = "; sysctl -n machdep.xcpm.mode 2>/dev/null
echo -n "vectors_loaded_count = "; sysctl -n machdep.xcpm.vectors_loaded_count 2>/dev/null
pmset -g therm 2>/dev/null
kextstat 2>/dev/null | grep -Ei "X86PlatformPlugin|ACPI_SMC_PlatformPlugin|VirtualSMC|CpuTscSync" | awk '{print $6, $7}'

echo
echo "########## 7) 电源 / 睡眠 ##########"
pmset -g
pmset -g assertions 2>/dev/null | head -15

echo
echo "########## 8) 存储 ##########"
system_profiler SPNVMeDataType 2>/dev/null | sed -n '1,20p' | mask
diskutil info disk0 2>/dev/null | grep -iE "TRIM|Solid State|Volume Name"

echo
echo "########## 9) USB ##########"
ioreg -r -c AppleUSBXHCIPCI -w0 2>/dev/null | grep -oE "HS[0-9]+|SS[0-9]+|USR[0-9]+" | sort -u | tr '\n' ' '; echo
system_profiler SPUSBDataType 2>/dev/null | grep -E "Product ID|Vendor ID|Manufacturer|Built-In" | head -30

echo
echo "########## 10) OpenCore / NVRAM ##########"
nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version 2>/dev/null
nvram boot-args 2>/dev/null
nvram -p 2>/dev/null | grep -E "csr-active-config|revpatch" | mask

echo
echo "########## 11) 显示 override / 缩放残留 ##########"
ls -la /Library/Displays 2>&1
ls -la "$HOME/Library/LaunchAgents" 2>/dev/null
command -v displayplacer >/dev/null && displayplacer list 2>/dev/null | tail -3

echo
echo "########## 12) 最近崩溃 / 签名异常 ##########"
ls -lt ~/Library/Logs/DiagnosticReports 2>/dev/null | head -5
echo "--- bluetoothd 签名（这是已知问题，见 known-issues #1）---"
codesign --verify --verbose=1 /usr/sbin/bluetoothd 2>&1 | head -3

echo
echo "########## 13) 已加载第三方 kext ##########"
kextstat -l 2>/dev/null | grep -v "com.apple" | awk '{print $6, $7}'
