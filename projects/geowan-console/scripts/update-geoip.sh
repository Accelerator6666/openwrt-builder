#!/bin/sh
# Download and atomically activate DB-IP Lite MMDB files.
# This script updates only GeoIP enrichment data; it never touches nftables.
set -eu

ROOT="/etc/geowan-console/geoip"
RELEASE="${1:-$(date -u +%Y-%m)}"

case "$RELEASE" in
    [0-9][0-9][0-9][0-9]-0[1-9]|[0-9][0-9][0-9][0-9]-1[0-2]) ;;
    *) echo "Usage: $0 [YYYY-MM]"; exit 2 ;;
esac

command -v gzip >/dev/null 2>&1 || { echo "gzip is required"; exit 1; }
/usr/bin/python3 -c 'import maxminddb' >/dev/null 2>&1 || {
    echo "Install GeoIP reader first: apk add python3-maxminddb"
    exit 1
}

if [ -L "$ROOT/current" ] &&
   [ -f "$ROOT/current/metadata.json" ] &&
   grep -Fq "\"release\": \"$RELEASE\"" "$ROOT/current/metadata.json"; then
    echo "DB-IP Lite $RELEASE is already active."
    exit 0
fi

mkdir -p "$ROOT/releases"
STAGE="$ROOT/.staging-$RELEASE-$$"
RELEASE_DIR="$ROOT/releases/$RELEASE"
mkdir -m 700 "$STAGE"

cleanup() {
    [ ! -d "$STAGE" ] || rm -rf "$STAGE"
}
trap cleanup EXIT HUP INT TERM

fetch_file() {
    url="$1"
    output="$2"
    if command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -O "$output" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$output" "$url"
    else
        echo "uclient-fetch or wget is required"
        return 1
    fi
}

for kind in country city asn; do
    archive="$STAGE/$kind.mmdb.gz"
    target="$STAGE/$kind.mmdb"
    url="https://download.db-ip.com/free/dbip-$kind-lite-$RELEASE.mmdb.gz"

    echo "Downloading DB-IP Lite $kind ($RELEASE)"
    fetch_file "$url" "$archive"
    gzip -t "$archive"
    gzip -dc "$archive" > "$target"
    [ -s "$target" ] || { echo "Empty MMDB: $target"; exit 1; }
    rm -f "$archive"
done

echo "Validating MMDB files and recording metadata"
/usr/bin/python3 - "$STAGE" "$RELEASE" <<'PY'
import hashlib
import json
import os
import sys
import time
import maxminddb

directory, release = sys.argv[1:3]
files = {}
for kind in ("country", "city", "asn"):
    path = os.path.join(directory, kind + ".mmdb")
    reader = maxminddb.open_database(path)
    metadata = reader.metadata()
    reader.close()
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    files[kind] = {
        "filename": kind + ".mmdb",
        "size": os.path.getsize(path),
        "sha256": digest.hexdigest(),
        "mmdb_build_epoch": getattr(metadata, "build_epoch", None)
    }

record = {
    "provider": "DB-IP Lite",
    "release": release,
    "updated_at": int(time.time()),
    "attribution": "IP Geolocation by DB-IP",
    "attribution_url": "https://db-ip.com",
    "license": "CC BY 4.0",
    "files": files
}
with open(os.path.join(directory, "metadata.json"), "w", encoding="utf-8") as stream:
    json.dump(record, stream, ensure_ascii=False, indent=2)
os.chmod(os.path.join(directory, "metadata.json"), 0o600)
PY

chmod 644 "$STAGE"/*.mmdb
if [ -d "$RELEASE_DIR" ]; then
    CURRENT_TARGET="$(readlink "$ROOT/current" 2>/dev/null || true)"
    if [ "$CURRENT_TARGET" = "releases/$RELEASE" ]; then
        echo "Refusing to replace the active release directory in place."
        exit 1
    fi
    rm -rf "$RELEASE_DIR"
fi
mv "$STAGE" "$RELEASE_DIR"
/usr/bin/python3 - "$ROOT" "$RELEASE" <<'PY'
import os
import sys
root, release = sys.argv[1:3]
temporary = os.path.join(root, ".current-" + str(os.getpid()))
current = os.path.join(root, "current")
try:
    os.symlink("releases/" + release, temporary)
    os.replace(temporary, current)
finally:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
PY

echo "DB-IP Lite $RELEASE activated."
echo "Attribution required: https://db-ip.com"

if [ -x /etc/init.d/geowan-monitor ]; then
    /etc/init.d/geowan-monitor restart || {
        echo "WARNING: monitor restart failed; restart it manually."
    }
fi

echo "GeoIP enrichment will process active bans in bounded batches."
echo "No nftables rules, WAN policies or port forwards were changed."
