#!/bin/sh
# Installed root-owned; launchd runs this fixed command every ten seconds.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
umask 022
cache='/Library/Application Support/MacStats'
output=$(/usr/bin/mktemp "$cache/reading.XXXXXX")
trap '/bin/rm -f "$output"' EXIT HUP INT TERM
# Failed samples replace old readings too, so errors never look like fresh data.
if /usr/bin/powermetrics --samplers smc -i 1000 -n 1 > "$output" 2>&1; then
    :
fi
/bin/chmod 644 "$output"
/bin/mv -f "$output" "$cache/temperature.txt"
