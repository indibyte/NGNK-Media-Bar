#!/bin/zsh
# Removes NGNK Media Bar, its login item, and its MTMR button.
set -uo pipefail
APP="$HOME/Applications/NGNK Media Bar.app"
LABEL=com.ngnk.mediabar

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
[[ -x "$APP/Contents/MacOS/NGNKMediaBar" ]] && "$APP/Contents/MacOS/NGNKMediaBar" --remove-mtmr-button
rm -rf "$APP" "$HOME/Library/Application Support/NGNK Media Bar"
echo "Uninstalled NGNK Media Bar"
