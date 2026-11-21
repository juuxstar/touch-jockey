#!/bin/bash
# Builds Touch Jockey with swiftc directly.
#
# SwiftPM (`swift build`) needs a full Xcode install; with only the Command Line
# Tools it fails looking up the platform path. This script compiles the same
# sources and assembles build/TouchJockey.app plus build/tj-analyze.
#
#   ./build.sh            release build
#   ./build.sh debug      debug build
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-release}"
OPT="-O"; [ "$MODE" = "debug" ] && OPT="-Onone -g"
TARGET="arm64-apple-macos13.0"
OUT=build
mkdir -p "$OUT/obj"

CORE=(Sources/TJCore/*.swift)

echo "› TJCore"
swiftc $OPT -target "$TARGET" -parse-as-library -emit-library -static -emit-module \
  -module-name TJCore -emit-module-path "$OUT/obj/TJCore.swiftmodule" \
  -o "$OUT/obj/libTJCore.a" "${CORE[@]}"

echo "› tj-analyze"
swiftc $OPT -target "$TARGET" -I "$OUT/obj" -L "$OUT/obj" -lTJCore \
  -o "$OUT/tj-analyze" Sources/tj-analyze/main.swift

echo "› TouchJockey.app"
APP="$OUT/TouchJockey.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc $OPT -target "$TARGET" -parse-as-library -I "$OUT/obj" -L "$OUT/obj" -lTJCore \
  -o "$APP/Contents/MacOS/TouchJockey" Sources/TouchJockey/*.swift
cp -R Sources/TouchJockey/Surface "$APP/Contents/Resources/Surface"

# App icon from the official 1024 px PNG.
ICONSET="$OUT/obj/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Sources/TouchJockey/Surface/tj-icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Sources/TouchJockey/Surface/tj-icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Touch Jockey</string>
  <key>CFBundleDisplayName</key><string>Touch Jockey</string>
  <key>CFBundleIdentifier</key><string>dev.touchjockey.app</string>
  <key>CFBundleExecutable</key><string>TouchJockey</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Touch Jockey talks to the phones and tablets you use as controllers.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "done: $APP"
