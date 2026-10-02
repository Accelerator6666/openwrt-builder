#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:?OpenWrt source directory is required}"
LOCK_FILE="${2:?Source lock file is required}"

# shellcheck disable=SC1090
source "$LOCK_FILE"

CUSTOM_DIR="$OPENWRT_DIR/package/custom"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$CUSTOM_DIR"

SRC="$TMP_ROOT/openwrt-add"
STAGE="$TMP_ROOT/stage"

git init -q "$SRC"
git -C "$SRC" remote add origin "$OPENWRT_ADD_REPO"
git -C "$SRC" fetch -q --depth 1 origin "$OPENWRT_ADD_COMMIT"

mkdir -p "$STAGE"

paths=(
  "imm_pkg/cpulimit"
  "luci-app-cpulimit"
  "luci-app-partexp/luci-app-partexp"
  "openwrt-einat-ebpf"
  "luci-app-einat"
  "luci-app-xlnetacc"
  "openwrt-bandix/openwrt-bandix"
  "luci-app-bandix/luci-app-bandix"
  "OpenAppFilter/oaf"
  "OpenAppFilter/open-app-filter"
  "OpenAppFilter/luci-app-oaf"
  "luci-app-zerotier"
  "openwrt_helloworld/luci-app-passwall"
  "openwrt_helloworld/chinadns-ng"
  "openwrt_helloworld/dns2socks"
  "openwrt_helloworld/geoview"
  "openwrt_helloworld/ipt2socks"
  "openwrt_helloworld/shadowsocks-rust"
  "openwrt_helloworld/shadowsocksr-libev"
  "openwrt_helloworld/simple-obfs"
  "openwrt_helloworld/tcping"
  "openwrt_helloworld/v2ray-plugin"
)

git -C "$SRC" archive FETCH_HEAD "${paths[@]}" | tar -x -C "$STAGE"

install_tree() {
  local source="$1"
  local name="$2"
  rm -rf "$CUSTOM_DIR/$name"
  cp -a "$STAGE/$source" "$CUSTOM_DIR/$name"
}

# Utility / system plugins.
install_tree "imm_pkg/cpulimit" "cpulimit"
install_tree "luci-app-cpulimit" "luci-app-cpulimit"

# Patch legacy cpulimit LuCI for OpenWrt 25.12. Its UI still uses luasrc/CBI,
# therefore luci-compat must be an explicit runtime dependency.
python3 - "$CUSTOM_DIR/luci-app-cpulimit/Makefile" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = "LUCI_DEPENDS:=+cpulimit"
new = "LUCI_DEPENDS:=+cpulimit +luci-compat"
if old not in text and new not in text:
    raise SystemExit("Unable to patch luci-app-cpulimit: LUCI_DEPENDS layout changed")
path.write_text(text.replace(old, new))
PY
install_tree "luci-app-partexp/luci-app-partexp" "luci-app-partexp"

# EINAT eBPF.
install_tree "openwrt-einat-ebpf" "einat-ebpf"
install_tree "luci-app-einat" "luci-app-einat"

# XLNetAcc.
install_tree "luci-app-xlnetacc" "luci-app-xlnetacc"

# Bandix core + LuCI.
install_tree "openwrt-bandix/openwrt-bandix" "bandix"
install_tree "luci-app-bandix/luci-app-bandix" "luci-app-bandix"

# Pin the x86_64 Bandix release binary instead of accepting PKG_HASH:=skip.
python3 - "$CUSTOM_DIR/bandix/Makefile" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = "else ifeq ($(ARCH),x86_64)\n\tPKG_HASH:=skip"
new = "else ifeq ($(ARCH),x86_64)\n\tPKG_HASH:=de7526fc165a61c1928d95345a03f5450fc3e2e2596bc406e285b59f338d115f"
if old not in text:
    raise SystemExit("Unable to pin Bandix x86_64 hash: expected Makefile block not found")
path.write_text(text.replace(old, new))
PY

# OpenAppFilter core, kernel module and LuCI.
install_tree "OpenAppFilter/oaf" "oaf"
install_tree "OpenAppFilter/open-app-filter" "open-app-filter"
install_tree "OpenAppFilter/luci-app-oaf" "luci-app-oaf"

# ZeroTier LuCI only. The zerotier core comes from the official OpenWrt 25.12
# packages feed to avoid duplicating the same package name.
install_tree "luci-app-zerotier" "luci-app-zerotier"

# PassWall LuCI plus only the support packages absent from the official
# OpenWrt 25.12 feeds. Official xray-core, sing-box, microsocks, haproxy and
# lyaml are intentionally reused from the normal packages feed.
install_tree "openwrt_helloworld/luci-app-passwall" "luci-app-passwall"
install_tree "openwrt_helloworld/chinadns-ng" "chinadns-ng"
install_tree "openwrt_helloworld/dns2socks" "dns2socks"
install_tree "openwrt_helloworld/geoview" "geoview"
install_tree "openwrt_helloworld/ipt2socks" "ipt2socks"
install_tree "openwrt_helloworld/shadowsocks-rust" "shadowsocks-rust"
install_tree "openwrt_helloworld/shadowsocksr-libev" "shadowsocksr-libev"
install_tree "openwrt_helloworld/simple-obfs" "simple-obfs"
install_tree "openwrt_helloworld/tcping" "tcping"
install_tree "openwrt_helloworld/v2ray-plugin" "v2ray-plugin"

# Sanity checks: package names must remain what the build config expects.
grep -q 'PKG_NAME:=luci-app-cpulimit' "$CUSTOM_DIR/luci-app-cpulimit/Makefile"
grep -q 'luci-compat' "$CUSTOM_DIR/luci-app-cpulimit/Makefile"
grep -q 'PKG_NAME:=luci-app-partexp' "$CUSTOM_DIR/luci-app-partexp/Makefile"
grep -q 'PKG_NAME:=einat-ebpf' "$CUSTOM_DIR/einat-ebpf/Makefile"
grep -q 'luci-app-einat' "$CUSTOM_DIR/luci-app-einat/Makefile"
grep -q 'PKG_NAME:=luci-app-xlnetacc' "$CUSTOM_DIR/luci-app-xlnetacc/Makefile"
grep -q 'PKG_NAME:=bandix' "$CUSTOM_DIR/bandix/Makefile"
grep -q 'LUCI_TITLE:=LuCI Bandix app for network traffic monitoring' "$CUSTOM_DIR/luci-app-bandix/Makefile"
grep -q 'KernelPackage/oaf' "$CUSTOM_DIR/oaf/Makefile"
grep -q 'PKG_NAME:=appfilter' "$CUSTOM_DIR/open-app-filter/Makefile"
grep -q 'PKG_NAME:=luci-app-oaf' "$CUSTOM_DIR/luci-app-oaf/Makefile"
grep -q 'LuCI for Zerotier' "$CUSTOM_DIR/luci-app-zerotier/Makefile"
grep -q 'PKG_NAME:=luci-app-passwall' "$CUSTOM_DIR/luci-app-passwall/Makefile"

echo "YAOF-derived package integration completed."
echo "Source commit: $OPENWRT_ADD_COMMIT"
