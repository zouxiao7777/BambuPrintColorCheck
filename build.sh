#!/bin/bash
set -eu
cd "$(dirname "$0")"
app="${1:-BambuPrintColorCheck.app}/Contents"
icons=$(mktemp -d)
trap 'rm -rf "$icons"' EXIT
mkdir -p "$app/MacOS" "$app/Resources/Web"
xcrun clang++ -arch arm64 -mmacosx-version-min=14.0 -std=c++17 -O3 Sources/paths.cpp -o "$app/MacOS/plate-paths"
xcrun swiftc -O -target arm64-apple-macos14.0 Sources/*.swift -o "$app/MacOS/PlatePreview"
cp Web/* "$app/Resources/Web/"
xcrun swift Scripts/make-icon.swift Assets/FilamentColorCheck.png "$icons/PrintColorCheck.iconset"
iconutil -c icns "$icons/PrintColorCheck.iconset" -o "$app/Resources/PrintColorCheck.icns"
cp "$icons/PrintColorCheck.iconset/icon_128x128@2x.png" "$app/Resources/Web/AboutIcon.png"
cp -R Resources/*.lproj "$app/Resources/"
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PlatePreview</string>
<key>CFBundleName</key><string>打印配色核对</string>
<key>CFBundleIdentifier</key><string>local.platepreview.macos</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>PrintColorCheck.icns</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>读取所选 Bambu Studio 发送窗口中可见的耗材卡，以生成配色核对图。</string>
</dict></plist>
PLIST
codesign --force --sign - "${app%/Contents}"
