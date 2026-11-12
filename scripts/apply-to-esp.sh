#!/bin/bash
# apply-to-esp.sh — 把一份 EFI 安全地刷进 ESP（带备份 + 刷后校验）
#
# 用法:
#   sudo ./scripts/apply-to-esp.sh ./EFI disk0s1
#   sudo ./scripts/apply-to-esp.sh ./EFI disk0s1 ~/Desktop/my-backup
#
# 做的事:
#   1. 挂载目标分区（若未挂载）
#   2. 把现有 EFI 整棵拷到备份目录（默认 ~/Desktop/EFI-backup-<时间>）
#   3. 删除并写入新 EFI
#   4. 校验 config.plist SHA-256 一致
#   5. 卸载分区
#
# 不做的事：不写 NVRAM、不改 BIOS、不碰系统盘。
# 回滚：把备份目录里的 EFI 拷回去即可。

set -euo pipefail

SRC="${1:-}"
DEV="${2:-}"
BAK="${3:-$HOME/Desktop/EFI-backup-$(date +%Y%m%d-%H%M%S)}"

if [ -z "$SRC" ] || [ -z "$DEV" ]; then
  echo "用法: sudo $0 <EFI目录> <ESP设备，例如 disk0s1> [备份目录]"
  echo
  echo "当前磁盘："
  diskutil list | sed -n '1,40p'
  exit 1
fi

[ "$(id -u)" -eq 0 ] || { echo "需要 root：sudo $0 ..."; exit 1; }
[ -f "$SRC/OC/config.plist" ] || { echo "$SRC 不像 EFI 目录（缺 OC/config.plist）"; exit 1; }

echo "== 目标分区 =="
diskutil info "$DEV" | sed -n '1,12p'
echo
echo "将要：用 $SRC 覆盖 $DEV 上的 EFI/，旧内容备份到 $BAK"
printf "确认继续？输入 yes: "
read -r ans
[ "$ans" = "yes" ] || { echo "已取消"; exit 1; }

# 1. 挂载
MNT=$(diskutil info -plist "$DEV" | plutil -extract MountPoint raw -o - - 2>/dev/null || true)
if [ -z "${MNT:-}" ] || [ "$MNT" = "/" ]; then
  echo "[1/5] 挂载 $DEV"
  diskutil mount "$DEV" >/dev/null
  sleep 1
  MNT=$(diskutil info -plist "$DEV" | plutil -extract MountPoint raw -o - -)
fi
echo "[1/5] 挂载点: $MNT"
[ -d "$MNT" ] || { echo "挂载失败"; exit 1; }

# 2. 备份
echo "[2/5] 备份现有 EFI → $BAK"
mkdir -p "$BAK"
if [ -d "$MNT/EFI" ]; then
  cp -R "$MNT/EFI" "$BAK/EFI"
  echo "      备份大小: $(du -sh "$BAK" | awk '{print $1}')"
else
  echo "      目标上没有 EFI/（全新分区）"
fi

# 3. 写入
echo "[3/5] 写入新 EFI"
rm -rf "$MNT/EFI"
cp -R "$SRC" "$MNT/EFI"
sync

# 4. 校验
echo "[4/5] 校验"
A=$(shasum -a 256 "$SRC/OC/config.plist" | awk '{print $1}')
B=$(shasum -a 256 "$MNT/EFI/OC/config.plist" | awk '{print $1}')
echo "      源:  $A"
echo "      目标: $B"
[ "$A" = "$B" ] || { echo "!! 哈希不一致，别重启，先把备份拷回去"; exit 1; }
echo "      SHA-256 一致 ✓"

# 5. 卸载
echo "[5/5] 卸载 $MNT"
diskutil unmount "$MNT" >/dev/null || true

cat <<EOF

完成。
  新 EFI : $SRC
  备份   : $BAK
  回滚   : cp -R "$BAK/EFI" "$MNT/EFI"   （先重新挂载 $DEV）

重启后如果开不了机：进 BIOS 或用 U 盘启动，把备份拷回 ESP 即可。
EOF
