#!/bin/zsh
# Builds build/NGNK Media Bar.app (ad-hoc signed).
set -euo pipefail
ROOT=${0:A:h:h}
APP="$ROOT/build/NGNK Media Bar.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/"
swiftc -O "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/NGNKMediaBar"
clang -dynamiclib -fobjc-arc -O2 -framework Foundation "$ROOT/Helper/NowPlayingHelper.m" \
    -o "$APP/Contents/Resources/NowPlayingHelper.dylib"
codesign --force -s - "$APP"
echo "Built $APP"
