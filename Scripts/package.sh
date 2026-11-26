#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
product=BambuPrintColorCheck
bundle="$stage/$product.app"
./build.sh "$bundle"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Contents/Info.plist")
out="$PWD/dist/$version"
mkdir -p "$out"
archive="$product-$version-macOS-arm64.zip"
codesign --verify --deep --strict "$bundle"
ditto -c -k --norsrc --keepParent "$bundle" "$out/$archive"
cp Docs/INSTALL-{Chinese,English}.txt "$out/"
cp Assets/FilamentColorCheck.png "$out/$product-icon.png"
(cd "$out" && shasum -a 256 "$archive" "$product-icon.png" INSTALL-{Chinese,English}.txt > SHA256SUMS.txt)
