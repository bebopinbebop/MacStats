#!/bin/bash
set -euo pipefail
if [[ "$EUID" -eq 0 ]]; then
    echo 'Run this script without sudo.' >&2
    exit 1
fi
sudo -v
launchctl bootout "gui/$(id -u)/local.macstats.app" 2>/dev/null || true
sudo launchctl bootout system/local.macstats.temperature 2>/dev/null || true
/usr/bin/pkill -x MacStats 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.macstats.app.plist"
sudo rm -f /Library/LaunchDaemons/local.macstats.temperature.plist
sudo rm -rf '/Library/Application Support/MacStats' /Applications/MacStats.app
echo 'Removed MacStats, automatic startup, and the temperature service. Source files are preserved.'
