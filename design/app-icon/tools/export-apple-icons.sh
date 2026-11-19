#!/usr/bin/env bash
# 从一张 1536×1536 方形母版导出 Apple 全套 App 图标（iOS + macOS）。
#
# 用法：
#   ./tools/export-apple-icons.sh                       # 默认用 source/deer-final-1536.png
#   ./tools/export-apple-icons.sh source/w-mark-1536.png # 指定其它母版（如 W 标）
#   ./tools/export-apple-icons.sh <母版> ios            # 只导 iOS
#   ./tools/export-apple-icons.sh <母版> macos          # 只导 macOS
#
# 说明：只做缩放，不改构图；输出全部为无 alpha 的 PNG（App Store 对图标的要求）。
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$(cd "$HERE/../.." && pwd)"
SRC="${1:-$HERE/source/deer-final-1536.png}"
TARGET="${2:-both}"

[ -f "$SRC" ] || { echo "找不到母版：$SRC" >&2; exit 1; }

IOS_DIR="$PROJ/ios/Runner/Assets.xcassets/AppIcon.appiconset"
MAC_DIR="$PROJ/macos/Runner/Assets.xcassets/AppIcon.appiconset"

# iOS：文件名 → 像素尺寸
IOS="Icon-App-20x20@1x:20 Icon-App-20x20@2x:40 Icon-App-20x20@3x:60 \
Icon-App-29x29@1x:29 Icon-App-29x29@2x:58 Icon-App-29x29@3x:87 \
Icon-App-40x40@1x:40 Icon-App-40x40@2x:80 Icon-App-40x40@3x:120 \
Icon-App-60x60@2x:120 Icon-App-60x60@3x:180 Icon-App-76x76@1x:76 \
Icon-App-76x76@2x:152 Icon-App-83.5x83.5@2x:167 Icon-App-1024x1024@1x:1024"

# macOS：沿用 Flutter 模板的 app_icon_*.png 命名
MAC="app_icon_16:16 app_icon_32:32 app_icon_64:64 app_icon_128:128 \
app_icon_256:256 app_icon_512:512 app_icon_1024:1024"

export_set() {
  local dir="$1" list="$2"
  mkdir -p "$dir"
  for spec in $list; do
    local name="${spec%%:*}" px="${spec##*:}"
    sips -z "$px" "$px" "$SRC" --out "$dir/$name.png" >/dev/null
  done
  echo "  → $dir"
}

echo "母版：$SRC"
if [ "$TARGET" = "both" ] || [ "$TARGET" = "ios" ]; then
  echo "导出 iOS 15 张："
  export_set "$IOS_DIR" "$IOS"
fi
if [ "$TARGET" = "both" ] || [ "$TARGET" = "macos" ]; then
  echo "导出 macOS 7 张："
  export_set "$MAC_DIR" "$MAC"
fi
echo "完成。重新编译看效果：flutter build ios --release / flutter build macos --debug"
