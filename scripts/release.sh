#!/bin/bash
# release.sh — 发一个版本的「本地准备」一条龙（不联网、不推送）
#
# 用法:
#   ./scripts/release.sh r18 v1.0.1
#   ./scripts/release.sh r18 v1.0.1 --no-tag     # 只打包，不打标签
#
# 做的事:
#   1. verify-efi.sh 全量自检（不过就直接退出）
#   2. 打 zip（只含 EFI/，排除 .DS_Store）→ ../dist/EFI-fujitsu-u9310x-<版本>.zip
#   3. 生成 .sha256
#   4. 建 annotated tag（本地，不推送）
#   5. 打印后续要手动做的三步
#
# 不做的事: 不 push、不建 Release、不改 changelog —— 这三件由人确认后再做。

set -euo pipefail

VERSION="${1:-}"
TAG="${2:-}"
NO_TAG=0
[ "${3:-}" = "--no-tag" ] && NO_TAG=1

if [ -z "$VERSION" ] || [ -z "$TAG" ]; then
  echo "用法: $0 <版本，如 r18> <标签，如 v1.0.1> [--no-tag]"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== [1/5] 校验 EFI =="
./scripts/verify-efi.sh EFI

echo
echo "== [2/5] 打包 =="
OUT="$(cd "$ROOT/.." && pwd)/dist/EFI-fujitsu-u9310x-${VERSION}.zip"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT" "$OUT.sha256"
zip -r -X -q "$OUT" EFI -x "*.DS_Store"
echo "  $OUT"
echo "  $(du -h "$OUT" | awk '{print $1}')"

echo
echo "== [3/5] 哈希 =="
( cd "$(dirname "$OUT")" && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
cat "$OUT.sha256"

if [ "$NO_TAG" -eq 0 ]; then
  echo
  echo "== [4/5] 标签 =="
  if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "  $TAG 已存在，跳过（要重打先 git tag -d $TAG）"
  else
    git tag -a "$TAG" -m "$VERSION"
    echo "  已创建 $TAG（本地，未推送）"
  fi
else
  echo
  echo "== [4/5] 标签 == 已按 --no-tag 跳过"
fi

echo
echo "== [5/5] 接下来手动做 =="
cat <<EOF
  1) 确认 docs/changelog.md 顶部已加 "$VERSION" 段
  2) 推送代码与标签:
       git push origin main
       git push origin $TAG
  3) 网页发 Release（本机 HTTPS 被墙，只能用浏览器）:
       Tag 选 $TAG
       附件上传: $(basename "$OUT")
                 $(basename "$OUT").sha256
       Release notes: 复制 docs/changelog.md 里 "$VERSION" 那一段
EOF
