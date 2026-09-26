#!/bin/zsh
# Builds build/NGNK Media Bar.app (ad-hoc signed).
set -euo pipefail
ROOT=${0:A:h:h}
APP="$ROOT/build/NGNK Media Bar.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/"
swiftc -O "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/NGNKMediaBar"
codesign --force -s - "$APP"
echo "Built $APP"
