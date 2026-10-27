#!/bin/bash
# Run as the logged-in user, not with sudo. Only system installation is elevated.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$EUID" -eq 0 ]]; then
    echo 'Run bash scripts/install.sh as your normal user (without sudo).' >&2
    exit 1
fi
bash "$ROOT_DIR/scripts/build_app.sh"
APP='/Applications/MacStats.app'
CACHE='/Library/Application Support/MacStats'
DAEMON='/Library/LaunchDaemons/local.macstats.temperature.plist'
AGENT="$HOME/Library/LaunchAgents/local.macstats.app.plist"
DOMAIN="gui/$(id -u)"
# Authenticate before changing any installed files.
sudo -v
# Stop the previous installation before replacing it. A missing job is normal.
launchctl bootout "$DOMAIN/local.macstats.app" 2>/dev/null || true
sudo launchctl bootout system/local.macstats.temperature 2>/dev/null || true
# Quit any manually launched copy, too.
/usr/bin/pkill -x MacStats 2>/dev/null || true
sudo /usr/bin/install -d -o root -g wheel -m 755 "$CACHE"
sudo /usr/bin/install -o root -g wheel -m 755 "$ROOT_DIR/Resources/collect-temperature.sh" "$CACHE/collect-temperature.sh"
sudo /usr/bin/install -o root -g wheel -m 644 "$ROOT_DIR/Resources/LaunchDaemons/local.macstats.temperature.plist" "$DAEMON"
sudo /usr/bin/ditto "$ROOT_DIR/dist/MacStats.app" "$APP"
sudo /usr/sbin/chown -R root:wheel "$APP"
sudo /bin/chmod -R go-w "$APP"
sudo launchctl enable system/local.macstats.temperature
sudo launchctl bootstrap system "$DAEMON"
mkdir -p "$(dirname "$AGENT")"
cat > "$AGENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>local.macstats.app</string>
    <key>ProgramArguments</key><array><string>/Applications/MacStats.app/Contents/MacOS/MacStats</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
PLIST
chmod 644 "$AGENT"
launchctl enable "$DOMAIN/local.macstats.app"
launchctl bootstrap "$DOMAIN" "$AGENT"
echo 'Installed. MacStats starts at login; temperatures should appear within 20 seconds.'
