#!/bin/sh
# Install the companion dashboard; existing GeoWAN / DNAT rules untouched.
set -eu
BASE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
[ -f "$BASE/agent/geowan_agent.py" ] || { echo "Run from project directory"; exit 1; }
[ -x /sbin/fw4 ] || { echo "OpenWrt firewall4 required"; exit 1; }
[ -x /usr/bin/python3 ] || {
    echo "Python3 required. For OpenWrt 25.12 use: apk update && apk add python3 python3-sqlite3"
    exit 1
}
/usr/bin/python3 -c 'import sqlite3, json, ipaddress' || {
    echo "Missing Python SQLite module. Install python3-sqlite3."
    exit 1
}
[ -d /usr/share/luci/menu.d ] || { echo "LuCI is required"; exit 1; }
[ -d /usr/share/rpcd/acl.d ] || { echo "rpcd is required"; exit 1; }

mkdir -p /usr/libexec/geowan-console \
    /usr/share/luci/menu.d /usr/share/rpcd/acl.d \
    /www/luci-static/resources/view/geowan \
    /www/luci-static/resources/geowan \
    /etc/geowan-console /tmp/geowan-console
chmod 700 /etc/geowan-console

cp "$BASE/agent/geowan_agent.py" /usr/libexec/geowan-console/agent.py
cp "$BASE/scripts/task.sh" /usr/libexec/geowan-console/task.sh
cp "$BASE/scripts/update.sh" /usr/libexec/geowan-console/update.sh
cp "$BASE/scripts/init.sh" /etc/init.d/geowan-console
cp "$BASE/luci/overview.js" /www/luci-static/resources/view/geowan/overview.js
cp "$BASE/luci/geowan.css" /www/luci-static/resources/geowan/geowan.css
cp "$BASE/luci/menu.json" /usr/share/luci/menu.d/luci-app-geowan-console.json
cp "$BASE/luci/acl.json" /usr/share/rpcd/acl.d/luci-app-geowan-console.json

chmod 700 /usr/libexec/geowan-console/agent.py \
    /usr/libexec/geowan-console/task.sh \
    /usr/libexec/geowan-console/update.sh
chmod 755 /etc/init.d/geowan-console
chmod 644 /usr/share/luci/menu.d/luci-app-geowan-console.json \
    /usr/share/rpcd/acl.d/luci-app-geowan-console.json \
    /www/luci-static/resources/view/geowan/overview.js \
    /www/luci-static/resources/geowan/geowan.css

# Idempotent crontab markers. No unreviewed firewall changes.
grep -Fq '# geowan-console-collect' /etc/crontabs/root 2>/dev/null || \
  echo '*/5 * * * * /usr/libexec/geowan-console/task.sh >/tmp/geowan-console-cron.log 2>&1 # geowan-console-collect' >> /etc/crontabs/root
grep -Fq '# geowan-console-update' /etc/crontabs/root 2>/dev/null || \
  echo '17 4 * * 1 /usr/libexec/geowan-console/update.sh >/tmp/geowan-console-update.log 2>&1 # geowan-console-update' >> /etc/crontabs/root

/etc/init.d/geowan-console enable
/etc/init.d/cron enable
/etc/init.d/cron restart
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache
/usr/libexec/geowan-console/task.sh
echo "GeoWAN Console installed. Open LuCI -> Services -> GeoWAN 安全面板."
echo "Database: /etc/geowan-console/telemetry.sqlite3"
echo "No new TCP/UDP port and no firewall rules modified."
