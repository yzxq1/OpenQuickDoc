#!/usr/bin/env bash
# 构建 OpenQuickDoc（Universal：arm64 + x86_64）
#   ./build.sh            仅构建到 build/
#   ./build.sh --install  构建并安装到 /Applications
#   ./build.sh --dmg      构建并打包 DMG 到 build/
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=0; DMG=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --dmg) DMG=1 ;;
    *) echo "未知参数: $arg"; exit 1 ;;
  esac
done

VERSION=$(plutil -extract CFBundleShortVersionString raw App/Info.plist)
EXT_ID=$(plutil -extract CFBundleIdentifier raw FinderSync/Info.plist)
BUILD=build
APP="$BUILD/OpenQuickDoc.app"
APPEX="$APP/Contents/PlugIns/OpenQuickDocFinderSync.appex"
MIN_OS=13.0

echo "===> OpenQuickDoc $VERSION"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"

# 为每个架构编译后用 lipo 合并
compile() { # $1=输出  $2=模块名  其余=swiftc 参数
  local out=$1 module=$2; shift 2
  local parts=()
  for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos$MIN_OS" -module-name "$module" -o "$out.$arch" "$@"
    parts+=("$out.$arch")
  done
  lipo -create "${parts[@]}" -output "$out"
  rm -f "${parts[@]}"
  strip -x "$out"
}

echo "===> 编译 Finder 扩展"
compile "$APPEX/Contents/MacOS/OpenQuickDocFinderSync" OpenQuickDocFinderSync \
  -parse-as-library -Xlinker -e -Xlinker _NSExtensionMain \
  Shared/*.swift FinderSync/FinderSync.swift -framework Cocoa -framework FinderSync
cp FinderSync/Info.plist "$APPEX/Contents/Info.plist"
cp Resources/blank.docx Resources/blank.xlsx Resources/blank.pptx "$APPEX/Contents/Resources/"

echo "===> 编译主程序"
compile "$APP/Contents/MacOS/OpenQuickDoc" OpenQuickDoc \
  Shared/*.swift App/Views.swift App/main.swift -framework Cocoa -framework SwiftUI
cp App/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

echo "===> 签名（ad-hoc）"
codesign --force --sign - --entitlements FinderSync/Entitlements.plist --timestamp=none "$APPEX"
codesign --force --sign - --entitlements App/Entitlements.plist --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/OpenQuickDoc"

if [[ $INSTALL == 1 ]]; then
  echo "===> 安装到 /Applications"
  killall OpenQuickDoc 2>/dev/null || true
  pkill -f OpenQuickDocFinderSync 2>/dev/null || true
  rm -rf /Applications/OpenQuickDoc.app
  ditto "$APP" /Applications/OpenQuickDoc.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/OpenQuickDoc.app
  pluginkit -a /Applications/OpenQuickDoc.app/Contents/PlugIns/OpenQuickDocFinderSync.appex
  pluginkit -e use -i "$EXT_ID"
  killall Finder 2>/dev/null || true
fi

if [[ $DMG == 1 ]]; then
  echo "===> 打包 DMG"
  STAGE="$BUILD/dmg"
  mkdir -p "$STAGE"
  ditto "$APP" "$STAGE/OpenQuickDoc.app"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -quiet -volname "OpenQuickDoc $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$BUILD/OpenQuickDoc-$VERSION.dmg"
  rm -rf "$STAGE"
  echo "DMG: $BUILD/OpenQuickDoc-$VERSION.dmg"
fi

echo "===> 完成"
