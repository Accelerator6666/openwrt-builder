# OpenWrt Builder

A reproducible OpenWrt firmware build repository based on the official OpenWrt source tree.

## Current target

- OpenWrt: 25.12.5
- Target: x86/64
- Build host: GitHub Actions / Ubuntu 24.04
- LuCI: enabled
- Firmware size: 512 MiB root filesystem

## Build

1. Open the **Actions** tab.
2. Select **Build OpenWrt**.
3. Click **Run workflow**.
4. Keep `v25.12.5` or enter another valid OpenWrt tag.
5. Download the firmware artifact after the workflow completes.

## Repository layout

```text
.github/workflows/   GitHub Actions workflows
configs/             OpenWrt build configurations
scripts/             Build customization scripts
files/               Files copied into the firmware rootfs
package/custom/      Local OpenWrt packages
```

The first milestone is a clean, reproducible x86_64 build. DAE, KixDNS and the custom LuCI UI can be added after the base build is verified.
