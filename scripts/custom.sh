#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:?OpenWrt source directory is required}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="$SCRIPT_DIR/sources.lock"

if [ ! -d "$OPENWRT_DIR" ]; then
  echo "OpenWrt directory does not exist: $OPENWRT_DIR" >&2
  exit 1
fi

if [ ! -f "$LOCK_FILE" ]; then
  echo "Missing source lock file: $LOCK_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$LOCK_FILE"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

fetch_commit_archive() {
  local repo="$1"
  local commit="$2"
  local subpath="$3"
  local destination="$4"
  local workdir="$5"

  git init -q "$workdir"
  git -C "$workdir" remote add origin "$repo"
  git -C "$workdir" fetch -q --depth 1 origin "$commit"

  mkdir -p "$destination"

  if [ -n "$subpath" ]; then
    git -C "$workdir" archive FETCH_HEAD "$subpath" | tar -x -C "$destination"
  else
    git -C "$workdir" archive FETCH_HEAD | tar -x -C "$destination"
  fi
}

echo "========================================"
echo " OpenWrt custom source integration"
echo "========================================"
echo "OpenWrt directory: $OPENWRT_DIR"

# ---------------------------------------------------------------------------
# DAE core package
#
# The package definition is pinned from ImmortalWrt packages because the
# official OpenWrt 25.12 packages feed does not currently ship net/dae.
# It is copied under package/custom so it is discovered without modifying
# the installed feeds index.
# ---------------------------------------------------------------------------

DAE_DEST="$OPENWRT_DIR/package/custom/dae"
DAE_STAGE="$TMP_ROOT/dae-stage"

rm -rf "$DAE_DEST"
mkdir -p "$DAE_STAGE"

echo "Fetching dae package definition:"
echo "  repo   : $IMMORTALWRT_PACKAGES_REPO"
echo "  commit : $IMMORTALWRT_PACKAGES_COMMIT"

fetch_commit_archive   "$IMMORTALWRT_PACKAGES_REPO"   "$IMMORTALWRT_PACKAGES_COMMIT"   "net/dae"   "$DAE_STAGE"   "$TMP_ROOT/immortalwrt-packages"

mkdir -p "$(dirname "$DAE_DEST")"
mv "$DAE_STAGE/net/dae" "$DAE_DEST"

# ImmortalWrt keeps dae inside feeds/packages/net/dae and therefore uses a
# relative include for the Go packaging helper. Since our copy lives in
# package/custom/dae, point it explicitly at the official packages feed.
if grep -q '^include ../../lang/golang/golang-package.mk$' "$DAE_DEST/Makefile"; then
  sed -i     's#include ../../lang/golang/golang-package.mk#include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk#'     "$DAE_DEST/Makefile"
else
  echo "Unexpected dae Makefile layout; refusing to build an unverified package definition." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# DDNS-Go
#
# The official OpenWrt 25.12 packages feed does not currently ship ddns-go,
# so use the same pinned ImmortalWrt packages commit as the dae package.
# ---------------------------------------------------------------------------

DDNS_GO_DEST="$OPENWRT_DIR/package/custom/ddns-go"
DDNS_GO_STAGE="$TMP_ROOT/ddns-go-stage"

rm -rf "$DDNS_GO_DEST"
mkdir -p "$DDNS_GO_STAGE"

echo "Fetching ddns-go package definition:"
echo "  repo   : $IMMORTALWRT_PACKAGES_REPO"
echo "  commit : $IMMORTALWRT_PACKAGES_COMMIT"

fetch_commit_archive \
  "$IMMORTALWRT_PACKAGES_REPO" \
  "$IMMORTALWRT_PACKAGES_COMMIT" \
  "net/ddns-go" \
  "$DDNS_GO_STAGE" \
  "$TMP_ROOT/immortalwrt-ddns-go"

mkdir -p "$(dirname "$DDNS_GO_DEST")"
mv "$DDNS_GO_STAGE/net/ddns-go" "$DDNS_GO_DEST"

if grep -q '^include ../../lang/golang/golang-package.mk
DAE_UI_DEST="$OPENWRT_DIR/package/custom/luci-app-dae-ui"

rm -rf "$DAE_UI_DEST"

echo "Fetching custom DAE LuCI UI:"
echo "  repo   : $DAE_UI_REPO"
echo "  commit : $DAE_UI_COMMIT"

fetch_commit_archive   "$DAE_UI_REPO"   "$DAE_UI_COMMIT"   ""   "$DAE_UI_DEST"   "$TMP_ROOT/dae-ui"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------

grep -q '^PKG_NAME:=dae
 "$DDNS_GO_DEST/Makefile"; then
  sed -i \
    's#include ../../lang/golang/golang-package.mk#include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk#' \
    "$DDNS_GO_DEST/Makefile"
else
  echo "Unexpected ddns-go Makefile layout; refusing to build an unverified package definition." >&2
  exit 1
fi
# ---------------------------------------------------------------------------
# Custom LuCI DAE UI
# ---------------------------------------------------------------------------

DAE_UI_DEST="$OPENWRT_DIR/package/custom/luci-app-dae-ui"

rm -rf "$DAE_UI_DEST"

echo "Fetching custom DAE LuCI UI:"
echo "  repo   : $DAE_UI_REPO"
echo "  commit : $DAE_UI_COMMIT"

fetch_commit_archive   "$DAE_UI_REPO"   "$DAE_UI_COMMIT"   ""   "$DAE_UI_DEST"   "$TMP_ROOT/dae-ui"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------

grep -q '^PKG_NAME:=dae$' "$DAE_DEST/Makefile"
grep -q '^PKG_NAME:=luci-app-dae-ui$' "$DAE_UI_DEST/Makefile"

DAE_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_DEST/Makefile" | head -n1)"
DAE_UI_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_UI_DEST/Makefile" | head -n1)"

echo "Integrated dae package version: ${DAE_VERSION:-unknown}"
echo "Integrated luci-app-dae-ui version: ${DAE_UI_VERSION:-unknown}"
echo "Custom source integration completed."
 "$DAE_DEST/Makefile"
grep -q '^PKG_NAME:=ddns-go
 "$DDNS_GO_DEST/Makefile"; then
  sed -i \
    's#include ../../lang/golang/golang-package.mk#include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk#' \
    "$DDNS_GO_DEST/Makefile"
else
  echo "Unexpected ddns-go Makefile layout; refusing to build an unverified package definition." >&2
  exit 1
fi
# ---------------------------------------------------------------------------
# Custom LuCI DAE UI
# ---------------------------------------------------------------------------

DAE_UI_DEST="$OPENWRT_DIR/package/custom/luci-app-dae-ui"

rm -rf "$DAE_UI_DEST"

echo "Fetching custom DAE LuCI UI:"
echo "  repo   : $DAE_UI_REPO"
echo "  commit : $DAE_UI_COMMIT"

fetch_commit_archive   "$DAE_UI_REPO"   "$DAE_UI_COMMIT"   ""   "$DAE_UI_DEST"   "$TMP_ROOT/dae-ui"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------

grep -q '^PKG_NAME:=dae$' "$DAE_DEST/Makefile"
grep -q '^PKG_NAME:=luci-app-dae-ui$' "$DAE_UI_DEST/Makefile"

DAE_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_DEST/Makefile" | head -n1)"
DAE_UI_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_UI_DEST/Makefile" | head -n1)"

echo "Integrated dae package version: ${DAE_VERSION:-unknown}"
echo "Integrated luci-app-dae-ui version: ${DAE_UI_VERSION:-unknown}"
echo "Custom source integration completed."
 "$DDNS_GO_DEST/Makefile"
grep -q '^PKG_NAME:=luci-app-dae-ui
 "$DDNS_GO_DEST/Makefile"; then
  sed -i \
    's#include ../../lang/golang/golang-package.mk#include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk#' \
    "$DDNS_GO_DEST/Makefile"
else
  echo "Unexpected ddns-go Makefile layout; refusing to build an unverified package definition." >&2
  exit 1
fi
# ---------------------------------------------------------------------------
# Custom LuCI DAE UI
# ---------------------------------------------------------------------------

DAE_UI_DEST="$OPENWRT_DIR/package/custom/luci-app-dae-ui"

rm -rf "$DAE_UI_DEST"

echo "Fetching custom DAE LuCI UI:"
echo "  repo   : $DAE_UI_REPO"
echo "  commit : $DAE_UI_COMMIT"

fetch_commit_archive   "$DAE_UI_REPO"   "$DAE_UI_COMMIT"   ""   "$DAE_UI_DEST"   "$TMP_ROOT/dae-ui"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------

grep -q '^PKG_NAME:=dae$' "$DAE_DEST/Makefile"
grep -q '^PKG_NAME:=luci-app-dae-ui$' "$DAE_UI_DEST/Makefile"

DAE_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_DEST/Makefile" | head -n1)"
DAE_UI_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_UI_DEST/Makefile" | head -n1)"

echo "Integrated dae package version: ${DAE_VERSION:-unknown}"
echo "Integrated luci-app-dae-ui version: ${DAE_UI_VERSION:-unknown}"
echo "Custom source integration completed."
 "$DAE_UI_DEST/Makefile"

DAE_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_DEST/Makefile" | head -n1)"
DDNS_GO_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DDNS_GO_DEST/Makefile" | head -n1)"
DAE_UI_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_UI_DEST/Makefile" | head -n1)"

echo "Integrated dae package version: ${DAE_VERSION:-unknown}"
echo "Integrated ddns-go package version: ${DDNS_GO_VERSION:-unknown}"
echo "Integrated luci-app-dae-ui version: ${DAE_UI_VERSION:-unknown}"
echo "Custom source integration completed."
 "$DDNS_GO_DEST/Makefile"; then
  sed -i \
    's#include ../../lang/golang/golang-package.mk#include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk#' \
    "$DDNS_GO_DEST/Makefile"
else
  echo "Unexpected ddns-go Makefile layout; refusing to build an unverified package definition." >&2
  exit 1
fi
# ---------------------------------------------------------------------------
# Custom LuCI DAE UI
# ---------------------------------------------------------------------------

DAE_UI_DEST="$OPENWRT_DIR/package/custom/luci-app-dae-ui"

rm -rf "$DAE_UI_DEST"

echo "Fetching custom DAE LuCI UI:"
echo "  repo   : $DAE_UI_REPO"
echo "  commit : $DAE_UI_COMMIT"

fetch_commit_archive   "$DAE_UI_REPO"   "$DAE_UI_COMMIT"   ""   "$DAE_UI_DEST"   "$TMP_ROOT/dae-ui"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------

grep -q '^PKG_NAME:=dae$' "$DAE_DEST/Makefile"
grep -q '^PKG_NAME:=luci-app-dae-ui$' "$DAE_UI_DEST/Makefile"

DAE_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_DEST/Makefile" | head -n1)"
DAE_UI_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_UI_DEST/Makefile" | head -n1)"

echo "Integrated dae package version: ${DAE_VERSION:-unknown}"
echo "Integrated luci-app-dae-ui version: ${DAE_UI_VERSION:-unknown}"
echo "Custom source integration completed."
