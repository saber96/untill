#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="$PWD/build/Untill.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$PWD/build/module-cache"
arch="$(uname -m)"
swiftc -swift-version 5 -target "$arch-apple-macos14.0" -O \
    -module-cache-path "$PWD/build/module-cache" Sources/*.swift -o "$app/Contents/MacOS/Untill"
cp Assets/Untill.icns "$app/Contents/Resources/Untill.icns"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign "${UNTILL_SIGN_IDENTITY:--}" "$app"
codesign --verify --strict "$app"
printf '%s\n' "$app"
