#!/usr/bin/env bash
# Build MacDown Lite — an arm64-native, read-only Markdown viewer.
# Requires only the Xcode Command Line Tools (clang + swiftc).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

APP_NAME="MacDown Lite"
EXEC_NAME="MacDownLite"
MIN_MACOS="13.0"
ARCH="${ARCH:-arm64}"
BUILD_DIR="$HERE/build"
OBJ_DIR="$BUILD_DIR/obj"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

SDK_FLAGS=(-arch "$ARCH" -mmacosx-version-min="$MIN_MACOS")

echo "==> 1/5  编译 C 渲染内核 (hoedown, $ARCH)"
mkdir -p "$OBJ_DIR"
for f in Sources/choedown/*.c; do
    name="$(basename "$f" .c)"
    clang "${SDK_FLAGS[@]}" -O2 -fPIC -I Sources/choedown -c "$f" -o "$OBJ_DIR/$name.o"
done
rm -f "$OBJ_DIR/libhoedown.a"
ar rcs "$OBJ_DIR/libhoedown.a" "$OBJ_DIR"/*.o
echo "        $(ls "$OBJ_DIR"/*.o | wc -l | tr -d ' ') objects -> libhoedown.a"

echo "==> 2/5  编译 Swift 应用"
mkdir -p "$BUILD_DIR/bin"
swiftc \
    -O -swift-version 5 \
    -target "$ARCH-apple-macos$MIN_MACOS" \
    -I Sources/choedown \
    Sources/MacDownLite/*.swift \
    -L "$OBJ_DIR" -lhoedown \
    -framework AppKit -framework WebKit \
    -o "$BUILD_DIR/bin/$EXEC_NAME"

echo "==> 3/5  组装 .app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/bin/$EXEC_NAME" "$APP_DIR/Contents/MacOS/$EXEC_NAME"
cp Info.plist "$APP_DIR/Contents/Info.plist"

echo "==> 4/5  拷贝资源 (主题 / Prism / 帮助)"
cp -R Resources/Themes "$APP_DIR/Contents/Resources/Themes"
mkdir -p "$APP_DIR/Contents/Resources/prism"
cp Resources/prism/* "$APP_DIR/Contents/Resources/prism/"
cp Resources/Help.md "$APP_DIR/Contents/Resources/Help.md"
cp Resources/search.js "$APP_DIR/Contents/Resources/search.js"
cp Resources/export-model.js "$APP_DIR/Contents/Resources/export-model.js"
cp -R Resources/mathjax "$APP_DIR/Contents/Resources/mathjax"

# App icon (generated on first build, then cached).
if [ ! -f "$BUILD_DIR/AppIcon.icns" ]; then
    swift tools/make_icon.swift "$BUILD_DIR/AppIcon.iconset" >/dev/null
    iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"
fi
cp "$BUILD_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "==> 5/5  签名 (ad-hoc)"
# iCloud Drive tags files with com.apple.FinderInfo / fileprovider xattrs,
# and codesign refuses to sign a bundle carrying such detritus. Strip first.
xattr -cr "$APP_DIR" 2>/dev/null || true
if sign_out=$(codesign --force --sign - "$APP_DIR" 2>&1); then
    if codesign --verify "$APP_DIR" >/dev/null 2>&1; then
        echo "        签名校验通过"
    else
        echo "        ⚠️  签名完成但校验未通过"
    fi
else
    echo "        ⚠️  签名失败："
    echo "$sign_out" | sed 's/^/          /'
fi

echo
echo "构建完成: $APP_DIR"
file "$APP_DIR/Contents/MacOS/$EXEC_NAME"
