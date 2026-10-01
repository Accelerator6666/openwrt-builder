#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:?OpenWrt source directory is required}"

echo "Running custom OpenWrt pre-build hook"
echo "OpenWrt directory: $OPENWRT_DIR"

# Future customizations belong here, for example:
# - add or modify feeds
# - patch defaults
# - integrate DAE / KixDNS / custom LuCI packages
