#!/bin/sh
# Weekly managed refresh. Snapshot BEFORE fw4 reload empties dynamic sets.
set -eu
LOCK=/tmp/geowan-console.update.lock
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null || :' EXIT
UPDATER=/usr/local/sbin/update-geowan.sh
[ -x "$UPDATER" ] || { echo "GeoWAN updater not installed"; exit 1; }
/usr/bin/python3 /usr/libexec/geowan-console/agent.py collect
"$UPDATER"
/usr/bin/python3 /usr/libexec/geowan-console/agent.py restore
/usr/bin/python3 /usr/libexec/geowan-console/agent.py collect
