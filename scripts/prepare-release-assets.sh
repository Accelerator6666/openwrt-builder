#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${1:-openwrt/bin/targets/x86/64}"
OUTPUT_DIR="${2:-release-assets}"

if [ ! -d "$SOURCE_ROOT" ]; then
  echo "Source directory does not exist: $SOURCE_ROOT" >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

copy_with_unique_name() {
  local src="$1"
  local name="${2:-$(basename "$src")}"
  local dst="$OUTPUT_DIR/$name"

  if [ -e "$dst" ]; then
    if cmp -s "$src" "$dst"; then
      return 0
    fi
    echo "Duplicate release filename with different contents: $name" >&2
    exit 1
  fi

  cp -a "$src" "$dst"
}

# Keep only flashable x86_64 images and useful build metadata. Deliberately
# exclude package repositories, SDK/toolchain archives, kernel debug archives
# and kmods so a firmware release stays small and focused.
while IFS= read -r -d '' file; do
  copy_with_unique_name "$file"
done < <(
  find "$SOURCE_ROOT" -type f \(
    -name '*-combined*.img.gz' -o
    -name '*-rootfs*.img.gz' -o
    -name '*-targz-rootfs.tar.gz' -o
    -name 'rootfs.tar.gz' -o
    -name '*-kernel.bin' -o
    -name '*.manifest' -o
    -name '*.bom.cdx.json' -o
    -name 'profiles.json' -o
    -name 'config.buildinfo' -o
    -name 'feeds.buildinfo' -o
    -name 'version.buildinfo'
  \) -print0
)

# When preparing a release from a downloaded Actions artifact, preserve the
# builder-specific metadata as well, but give it unambiguous names.
while IFS= read -r -d '' file; do
  case "$file" in
    */build-info/build.txt) copy_with_unique_name "$file" "builder-build.txt" ;;
    */build-info/openwrt.config) copy_with_unique_name "$file" "builder-openwrt.config" ;;
    */build-info/diffconfig.txt) copy_with_unique_name "$file" "builder-diffconfig.txt" ;;
  esac
done < <(find "$SOURCE_ROOT" -type f -path '*/build-info/*' -print0 2>/dev/null || true)

# A successful x86_64 release must contain at least one complete disk image.
if ! find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*-combined*.img.gz' -print -quit | grep -q .; then
  echo "No combined x86_64 disk image was found under: $SOURCE_ROOT" >&2
  exit 1
fi

cat > "$OUTPUT_DIR/IMAGE_GUIDE.txt" <<'EOF'
OpenWrt x86_64 image guide
==========================

Recommended fresh-install images:
  * *-squashfs-combined-efi.img.gz  - UEFI systems; squashfs + writable overlay.
  * *-squashfs-combined.img.gz      - Legacy BIOS systems; squashfs + writable overlay.

Alternative ext4 images:
  * *-ext4-combined-efi.img.gz      - UEFI systems with an ext4 root filesystem.
  * *-ext4-combined.img.gz          - Legacy BIOS systems with an ext4 root filesystem.

Rootfs-only images and kernel.bin are intended for advanced/manual deployment.
For upgrades, keep the same boot mode and filesystem family unless you are
performing a deliberate migration, and back up the configuration first.

Verify the selected file against SHA256SUMS before writing it to disk.
EOF

# Inventory first, then checksum every release asset except SHA256SUMS itself.
(
  cd "$OUTPUT_DIR"
  {
    echo 'Release asset inventory'
    echo '======================='
    echo
    find . -maxdepth 1 -type f ! -name 'FILES.txt' ! -name 'SHA256SUMS' -printf '%f\t%s bytes\n' | sort
  } > FILES.txt

  find . -maxdepth 1 -type f ! -name 'SHA256SUMS' -printf '%f\0' \
    | sort -z \
    | xargs -0 sha256sum > SHA256SUMS
)

echo "Prepared release assets:"
find "$OUTPUT_DIR" -maxdepth 1 -type f -printf '  %f\n' | sort
