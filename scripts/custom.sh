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

patch_go_helper_include() {
  local makefile="$1"

  if grep -q '^include ../../lang/golang/golang-package.mk$' "$makefile"; then
    sed -i       's#include ../../lang/golang/golang-package.mk#include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk#'       "$makefile"
  elif grep -q '^include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk$' "$makefile"; then
    :
  else
    echo "Unexpected Go package helper include in $makefile" >&2
    exit 1
  fi
}

echo "========================================"
echo " OpenWrt custom source integration"
echo "========================================"
echo "OpenWrt directory: $OPENWRT_DIR"

mkdir -p "$OPENWRT_DIR/package/custom"

# ---------------------------------------------------------------------------
# DAE core package
# ---------------------------------------------------------------------------

DAE_DEST="$OPENWRT_DIR/package/custom/dae"
DAE_STAGE="$TMP_ROOT/dae-stage"

rm -rf "$DAE_DEST"
mkdir -p "$DAE_STAGE"

echo "Fetching dae package definition:"
echo "  repo   : $IMMORTALWRT_PACKAGES_REPO"
echo "  commit : $IMMORTALWRT_PACKAGES_COMMIT"

fetch_commit_archive   "$IMMORTALWRT_PACKAGES_REPO"   "$IMMORTALWRT_PACKAGES_COMMIT"   "net/dae"   "$DAE_STAGE"   "$TMP_ROOT/immortalwrt-dae"

mv "$DAE_STAGE/net/dae" "$DAE_DEST"
patch_go_helper_include "$DAE_DEST/Makefile"

# ---------------------------------------------------------------------------
# DDNS-Go core package
# ---------------------------------------------------------------------------

DDNS_GO_DEST="$OPENWRT_DIR/package/custom/ddns-go"
DDNS_GO_STAGE="$TMP_ROOT/ddns-go-stage"

rm -rf "$DDNS_GO_DEST"
mkdir -p "$DDNS_GO_STAGE"

echo "Fetching ddns-go package definition:"
echo "  repo   : $IMMORTALWRT_PACKAGES_REPO"
echo "  commit : $IMMORTALWRT_PACKAGES_COMMIT"

fetch_commit_archive   "$IMMORTALWRT_PACKAGES_REPO"   "$IMMORTALWRT_PACKAGES_COMMIT"   "net/ddns-go"   "$DDNS_GO_STAGE"   "$TMP_ROOT/immortalwrt-ddns-go"

mv "$DDNS_GO_STAGE/net/ddns-go" "$DDNS_GO_DEST"
patch_go_helper_include "$DDNS_GO_DEST/Makefile"

# ---------------------------------------------------------------------------
# DDNS-Go LuCI compatibility layer
#
# Keep the newer ddns-go core/package version from ImmortalWrt, but use the
# service/UCI schema expected by the pinned LuCI frontend.
# ---------------------------------------------------------------------------

DDNS_GO_COMPAT_STAGE="$TMP_ROOT/ddns-go-compat-stage"
DDNS_GO_LUCI_DEST="$OPENWRT_DIR/package/custom/luci-app-ddns-go"

rm -rf "$DDNS_GO_COMPAT_STAGE" "$DDNS_GO_LUCI_DEST"
mkdir -p "$DDNS_GO_COMPAT_STAGE"

echo "Fetching DDNS-Go LuCI compatibility files:"
echo "  repo   : $DDNS_GO_UI_REPO"
echo "  commit : $DDNS_GO_UI_COMMIT"

fetch_commit_archive   "$DDNS_GO_UI_REPO"   "$DDNS_GO_UI_COMMIT"   "ddns-go/files"   "$DDNS_GO_COMPAT_STAGE"   "$TMP_ROOT/ddns-go-ui-core"

rm -rf "$DDNS_GO_DEST/files"
cp -a "$DDNS_GO_COMPAT_STAGE/ddns-go/files" "$DDNS_GO_DEST/files"

# The LuCI frontend manages this filename directly.
sed -i   's#/etc/ddns-go/config.yaml#/etc/ddns-go/ddns-go-config.yaml#g'   "$DDNS_GO_DEST/Makefile"

echo "Fetching LuCI DDNS-Go frontend:"

fetch_commit_archive   "$DDNS_GO_UI_REPO"   "$DDNS_GO_UI_COMMIT"   "luci-app-ddns-go"   "$TMP_ROOT/ddns-go-luci-stage"   "$TMP_ROOT/ddns-go-ui-luci"

mv "$TMP_ROOT/ddns-go-luci-stage/luci-app-ddns-go" "$DDNS_GO_LUCI_DEST"

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
# Custom LuCI KixDNS UI
# ---------------------------------------------------------------------------

KIXDNS_UI_DEST="$OPENWRT_DIR/package/custom/luci-app-kixdns-ui"

rm -rf "$KIXDNS_UI_DEST"

echo "Fetching custom KixDNS LuCI UI:"
echo "  repo   : $KIXDNS_UI_REPO"
echo "  commit : $KIXDNS_UI_COMMIT"

fetch_commit_archive \
  "$KIXDNS_UI_REPO" \
  "$KIXDNS_UI_COMMIT" \
  "" \
  "$KIXDNS_UI_DEST" \
  "$TMP_ROOT/kixdns-ui"

# ---------------------------------------------------------------------------
# Curated YAOF-derived packages
# ---------------------------------------------------------------------------

bash "$SCRIPT_DIR/integrate-yaof-packages.sh" "$OPENWRT_DIR" "$LOCK_FILE"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------

grep -q '^PKG_NAME:=dae$' "$DAE_DEST/Makefile"
grep -q '^PKG_NAME:=ddns-go$' "$DDNS_GO_DEST/Makefile"
grep -q '^PKG_NAME:=luci-app-ddns-go$' "$DDNS_GO_LUCI_DEST/Makefile"
grep -q '^PKG_NAME:=luci-app-dae-ui

grep -q '/etc/ddns-go/ddns-go-config.yaml' "$DDNS_GO_DEST/Makefile"
grep -q "option port '9876'" "$DDNS_GO_DEST/files/ddns-go.conf"

DAE_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_DEST/Makefile" | head -n1)"
DDNS_GO_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DDNS_GO_DEST/Makefile" | head -n1)"
DDNS_GO_LUCI_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DDNS_GO_LUCI_DEST/Makefile" | head -n1)"
DAE_UI_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_UI_DEST/Makefile" | head -n1)"
KIXDNS_UI_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$KIXDNS_UI_DEST/Makefile" | head -n1)"

echo "Integrated dae package version: ${DAE_VERSION:-unknown}"
echo "Integrated ddns-go package version: ${DDNS_GO_VERSION:-unknown}"
echo "Integrated luci-app-ddns-go version: ${DDNS_GO_LUCI_VERSION:-unknown}"
echo "Integrated luci-app-dae-ui version: ${DAE_UI_VERSION:-unknown}"
echo "Integrated luci-app-kixdns-ui version: ${KIXDNS_UI_VERSION:-unknown}"
echo "Custom source integration completed."
 "$DAE_UI_DEST/Makefile"
grep -q '^PKG_NAME:=luci-app-kixdns-ui

grep -q '/etc/ddns-go/ddns-go-config.yaml' "$DDNS_GO_DEST/Makefile"
grep -q "option port '9876'" "$DDNS_GO_DEST/files/ddns-go.conf"

DAE_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_DEST/Makefile" | head -n1)"
DDNS_GO_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DDNS_GO_DEST/Makefile" | head -n1)"
DDNS_GO_LUCI_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DDNS_GO_LUCI_DEST/Makefile" | head -n1)"
DAE_UI_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_UI_DEST/Makefile" | head -n1)"

echo "Integrated dae package version: ${DAE_VERSION:-unknown}"
echo "Integrated ddns-go package version: ${DDNS_GO_VERSION:-unknown}"
echo "Integrated luci-app-ddns-go version: ${DDNS_GO_LUCI_VERSION:-unknown}"
echo "Integrated luci-app-dae-ui version: ${DAE_UI_VERSION:-unknown}"
echo "Custom source integration completed."
 "$KIXDNS_UI_DEST/Makefile"

grep -q '/etc/ddns-go/ddns-go-config.yaml' "$DDNS_GO_DEST/Makefile"
grep -q "option port '9876'" "$DDNS_GO_DEST/files/ddns-go.conf"

DAE_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_DEST/Makefile" | head -n1)"
DDNS_GO_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DDNS_GO_DEST/Makefile" | head -n1)"
DDNS_GO_LUCI_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DDNS_GO_LUCI_DEST/Makefile" | head -n1)"
DAE_UI_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$DAE_UI_DEST/Makefile" | head -n1)"

echo "Integrated dae package version: ${DAE_VERSION:-unknown}"
echo "Integrated ddns-go package version: ${DDNS_GO_VERSION:-unknown}"
echo "Integrated luci-app-ddns-go version: ${DDNS_GO_LUCI_VERSION:-unknown}"
echo "Integrated luci-app-dae-ui version: ${DAE_UI_VERSION:-unknown}"
echo "Custom source integration completed."
