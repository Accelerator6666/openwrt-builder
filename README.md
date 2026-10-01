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
