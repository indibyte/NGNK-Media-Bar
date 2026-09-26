#!/bin/zsh
# Builds and installs NGNK Media Bar, starts it at login, and adds its button to MTMR's main bar.
set -euo pipefail
ROOT=${0:A:h:h}
APP="$HOME/Applications/NGNK Media Bar.app"
BIN="$APP/Contents/MacOS/NGNKMediaBar"
LABEL=com.ngnk.mediabar
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
MTMR_CONFIG="$HOME/Library/Application Support/MTMR/items.json"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

"$ROOT/scripts/build.sh"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$APP"
cp -R "$ROOT/build/NGNK Media Bar.app" "$APP"
"$LSREGISTER" -f "$APP"

if [[ -f "$MTMR_CONFIG" ]]; then
  BACKUP="$MTMR_CONFIG.backup-$(date +%Y%m%d-%H%M%S)"
  cp "$MTMR_CONFIG" "$BACKUP"
  "$BIN" --install-mtmr-button
  echo "Added the now-playing button to MTMR (previous config: $BACKUP)"
else
  echo "MTMR config not found at $MTMR_CONFIG; install MTMR, run it once, then re-run this script."
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo "Installed $APP (starts at login)"
