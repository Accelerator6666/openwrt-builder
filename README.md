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

## DAE integration

The build keeps third-party inputs pinned in `scripts/sources.lock`.

Current integration:

- DDNS-Go 6.17.6 is compiled into the firmware from the pinned ImmortalWrt package definition. Its own web UI listens on port 9876 when the service is enabled.

- DAE OpenWrt package definition is pinned from `immortalwrt/packages`.
- That package builds the upstream `daeuniverse/dae` source and installs the OpenWrt procd service.
- `Accelerator6666/luci-app-dae-ui` is pinned to a specific commit and compiled directly into the firmware.
- The x86_64 kernel build enables the BPF/BTF options required by dae, including kernel BTF at `/sys/kernel/btf/vmlinux`.
- The build uses the host LLVM/Clang toolchain for eBPF generation.
- DAE is installed but remains disabled by default until a valid configuration is supplied and the service is enabled.
- DDNS-Go is installed but remains disabled by default; enable it after setting provider credentials and access controls.

The custom DAE UI includes persistent binary version selection, reboot-safe dispatch, last-good rollback and validation against the active OpenWrt dae configuration.

## Build

1. Open the **Actions** tab.
2. Select **Build OpenWrt**.
3. Click **Run workflow**.
4. Keep `v25.12.5` or enter another valid OpenWrt tag.
5. Wait for the DAE preflight check and firmware build to complete.
6. Download the `openwrt-x86_64-...` artifact.

Builds are manual only. Normal pushes do not start a full OpenWrt compilation.

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
