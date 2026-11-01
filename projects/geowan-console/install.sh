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

# Fail closed if live GeoWAN objects are absent. This does not reload fw4.
for object in \
    "set inet fw4 geo_cn4" "set inet fw4 geo_cn6" \
    "set inet fw4 geo_black4" "set inet fw4 geo_black6" \
    "chain inet fw4 geo_filter" "chain inet fw4 geo_wan_input" \
    "chain inet fw4 geo_wan_forward"; do
    set -- $object
    kind="$1"; family="$2"; table="$3"; name="$4"
    nft list "$kind" "$family" "$table" "$name" >/dev/null 2>&1 || {
        echo "Required nftables object missing: $object"
        echo "Run preflight.sh and resolve the mismatch before installing."
        exit 1
    }
done
fw4 check >/dev/null || {
    echo "fw4 check failed. Installation stopped; firewall was not reloaded."
    exit 1
}

# Stop an existing v0.2 monitor before replacing its executable or service file.
if [ -x /etc/init.d/geowan-monitor ]; then
    /etc/init.d/geowan-monitor stop 2>/dev/null || :
fi

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
cp "$BASE/scripts/monitor.init.sh" /etc/init.d/geowan-monitor
cp "$BASE/luci/overview.js" /www/luci-static/resources/view/geowan/overview.js
cp "$BASE/luci/geowan.css" /www/luci-static/resources/geowan/geowan.css
cp "$BASE/luci/menu.json" /usr/share/luci/menu.d/luci-app-geowan-console.json
cp "$BASE/luci/acl.json" /usr/share/rpcd/acl.d/luci-app-geowan-console.json

chmod 700 /usr/libexec/geowan-console/agent.py \
    /usr/libexec/geowan-console/task.sh \
    /usr/libexec/geowan-console/update.sh
chmod 755 /etc/init.d/geowan-console
chmod 755 /etc/init.d/geowan-monitor
chmod 644 /usr/share/luci/menu.d/luci-app-geowan-console.json \
    /usr/share/rpcd/acl.d/luci-app-geowan-console.json \
    /www/luci-static/resources/view/geowan/overview.js \
    /www/luci-static/resources/geowan/geowan.css

# Collection only. Weekly GeoIP refresh is deliberately NOT scheduled until
# the existing update-geowan.sh passes nft/fw4 validation on this router.
grep -Fq '# geowan-console-collect' /etc/crontabs/root 2>/dev/null || \
  echo '*/5 * * * * /usr/libexec/geowan-console/task.sh >/tmp/geowan-console-cron.log 2>&1 # geowan-console-collect' >> /etc/crontabs/root

/etc/init.d/geowan-console enable
/etc/init.d/geowan-monitor enable
/etc/init.d/cron enable
/etc/init.d/cron restart
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache
/usr/libexec/geowan-console/task.sh
/etc/init.d/geowan-monitor start
echo "GeoWAN Console installed. Open LuCI -> Services -> GeoWAN 安全面板."
echo "Database: /etc/geowan-console/telemetry.sqlite3"
echo "Fast monitor: counters every 5s, blacklist inventory/log scan every 15s; 5-minute reconciliation remains enabled."
echo "No new TCP/UDP port and no firewall rules modified."
