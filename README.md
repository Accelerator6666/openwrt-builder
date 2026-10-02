# OpenWrt Builder

A reproducible OpenWrt x86_64 firmware build based on the official OpenWrt source tree.

## Current target

- OpenWrt: 25.12.5
- Target: x86/64
- Build host: GitHub Actions / Ubuntu 24.04
- LuCI: enabled
- Root filesystem: 512 MiB
- DAE core: enabled
- Custom DAE LuCI UI: enabled
- DAE GeoIP / Geosite: enabled
- DDNS-Go: enabled
- LuCI DDNS-Go frontend: enabled
- KixDNS core: enabled
- Custom KixDNS LuCI UI: enabled

## DAE integration

The build keeps third-party inputs pinned in `scripts/sources.lock`.

Current integration:

- DDNS-Go 6.17.6 is compiled into the firmware from the pinned ImmortalWrt package definition.
- LuCI DDNS-Go 1.6.8 is pinned from `sirpdboy/luci-app-ddns-go` and compiled into the firmware.
- The ddns-go OpenWrt service/UCI schema is aligned with the LuCI frontend while keeping the newer 6.17.6 core binary.
- In LuCI the entry appears under **Services → DDNS-GO**; the full ddns-go web interface still listens on port 9876 when enabled.

- DAE OpenWrt package definition is pinned from `immortalwrt/packages`.
- That package builds the upstream `daeuniverse/dae` source and installs the OpenWrt procd service.
- `Accelerator6666/luci-app-dae-ui` is pinned to a specific commit and compiled directly into the firmware.
- The x86_64 kernel build enables the BPF/BTF options required by dae, including kernel BTF at `/sys/kernel/btf/vmlinux`.
- The build uses the host LLVM/Clang toolchain for eBPF generation.
- DAE is installed but remains disabled by default until a valid configuration is supplied and the service is enabled.
- DDNS-Go is installed but remains disabled by default; enable it after setting provider credentials and access controls.

The custom DAE UI includes persistent binary version selection, reboot-safe dispatch, last-good rollback and validation against the active OpenWrt dae configuration.

## KixDNS integration

- KixDNS 0.2.0 is installed from the upstream x86_64 musl release binary and verified by a pinned SHA256.
- The default listener is `127.0.0.1:5335` over UDP and TCP.
- The default upstream is `1.1.1.1:53`; edit `/etc/kixdns/pipeline.json` or use the LuCI UI before relying on it for production routing.
- `Accelerator6666/luci-app-kixdns-ui` 0.3.0 is pinned to a specific commit and compiled into the firmware.
- LuCI exposes **Services → KixDNS** with Overview, Visual Editor, Raw JSON, Backups, Diagnostics and Logs.
- KixDNS configuration is preserved as a conffile at `/etc/kixdns/pipeline.json`.

## Build

1. Open the **Actions** tab.
2. Select **Build OpenWrt**.
3. Click **Run workflow**.
4. Keep `v25.12.5` or enter another valid OpenWrt tag.
5. Wait for the DAE preflight check and firmware build to complete.
6. Download the `openwrt-x86_64-...` artifact.

Builds are manual only. Normal pushes do not start a full OpenWrt compilation.

The firmware artifact is release-ready and intentionally excludes package repositories,
SDK/toolchain archives, kernel debug archives and kmods. It keeps the flashable x86_64
images, manifest/profile/build metadata, the effective OpenWrt configuration and a
fresh `SHA256SUMS` file.

## Publish a GitHub Release

A successful build can be published without rebuilding it. Run the
`Publish OpenWrt Release` workflow and provide the successful build run ID.

Example:

```powershell
gh workflow run publish-release.yml `
  --repo Accelerator6666/openwrt-builder `
  --ref main `
  -f run_id=<successful-run-id> `
  -f openwrt_ref=v25.12.5
```

If the optional `tag` and `title` inputs are left blank, the release workflow
derives them from the successful source build. The default tag format is:

```text
v25.12.5-x86_64-r<build-run-number>
```

The release workflow verifies that the source run completed successfully, downloads
the already release-ready firmware artifact, verifies `SHA256SUMS`, and uploads the
firmware images plus build metadata to a GitHub Release. It does not rebuild OpenWrt.

### x86_64 image selection

| Boot/filesystem | Image | Typical use |
| --- | --- | --- |
| UEFI + squashfs | `*-squashfs-combined-efi.img.gz` | Recommended normal installation on modern x86_64 hardware |
| Legacy BIOS + squashfs | `*-squashfs-combined.img.gz` | Recommended normal installation on legacy BIOS systems |
| UEFI + ext4 | `*-ext4-combined-efi.img.gz` | UEFI installation when an ext4 root filesystem is preferred |
| Legacy BIOS + ext4 | `*-ext4-combined.img.gz` | Legacy BIOS installation when an ext4 root filesystem is preferred |

Rootfs-only images and `kernel.bin` are retained for advanced/manual deployment.
For upgrades, keep the existing boot mode and filesystem family unless deliberately
migrating, back up the configuration first, and verify the selected image against
`SHA256SUMS`.

## Repository layout

```text
.github/workflows/   GitHub Actions workflows
configs/             OpenWrt build configurations
scripts/             Build customization and pinned source definitions
files/               Files copied into the firmware rootfs
package/custom/      Local OpenWrt packages
```

## Source update policy

Do not follow third-party `main` branches implicitly during a firmware build. Update the commit IDs in `scripts/sources.lock` deliberately, review the changes, then run a new firmware build. This keeps an older firmware reproducible even after upstream repositories change.


## Additional LuCI applications

The x86_64 image also includes the following requested applications:

- `luci-app-partexp`
- `luci-app-cpulimit` + `cpulimit`
- `luci-app-sqm` + official OpenWrt `sqm-scripts`
- `luci-app-einat` + `einat-ebpf`
- `luci-app-xlnetacc`
- `luci-app-bandix` + `bandix`
- `luci-app-oaf` + OpenAppFilter userland/kernel components
- `luci-app-zerotier` + official OpenWrt 25.12 `zerotier`
- `luci-app-passwall`

The YAOF-derived package definitions are pinned to a specific
`QiuSimons/OpenWrt-Add` commit in `scripts/sources.lock`. PassWall reuses
official OpenWrt 25.12 packages when they are available and imports only the
missing support packages from the pinned YAOF package set. Bandix's x86_64
release asset is additionally pinned by SHA256.

EINAT and DAE share the BPF/BTF-capable kernel configuration. Because EINAT,
PassWall and their dependencies substantially increase build work, the GitHub
Actions job has a five-hour hard timeout.


## LuCI 25.12 compatibility

The requested LuCI applications are checked against the OpenWrt 25.12 LuCI architecture.

| Package | UI architecture | Compatibility handling |
| --- | --- | --- |
| luci-app-partexp | Modern JavaScript + menu.d + rpcd ACL | Native |
| luci-app-sqm | Official modern JavaScript LuCI | Native |
| luci-app-einat | Modern JavaScript + menu.d + rpcd ucode | Native |
| luci-app-bandix | Modern JavaScript + menu.d + rpcd | Native |
| luci-app-zerotier | Modern JavaScript + menu.d + rpcd ACL | Native |
| luci-app-cpulimit | Legacy Lua/CBI | Explicit luci-compat dependency added during integration |
| luci-app-xlnetacc | Legacy Lua/CBI | Upstream package already depends on luci-compat |
| luci-app-oaf | Legacy Lua/CBI | Upstream package already depends on luci-compat |
| luci-app-passwall | Hybrid Lua/CBI + JavaScript | Upstream package already depends on luci-compat |

The build explicitly enables `CONFIG_PACKAGE_luci-compat=y` and fails its
preflight if a known legacy LuCI package loses the `luci-compat` dependency
or if a modern package loses its JavaScript view directory.
