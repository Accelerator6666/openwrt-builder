# GeoWAN Console v0.1.0（开发预览）

为 **OpenWrt 25.12 / firewall4 / nftables** 设计的独立 GeoIP 防护可视化和持久化伴侣，中文 LuCI 页面，无额外监听端口。

> **状态：代码已提交，尚未在目标路由器做实机验收。请先备份再部署。**
> 该组件只观测已经存在的 GeoWAN nftables 规则，不会修改 WAN 防火墙策略、DNAT、PPPoE、daed 或代理分流。

## 功能

- LuCI → 服务 → **GeoWAN 安全面板**：当前被阻断 IP、包计数、过去 24 小时拦截日志趋势、来源 IP、目标端口、最近事件、过期时间。
- SQLite 持久保存被封锁 IP 和最近 30 天的**采样**内核日志；每 5 分钟采集一次；系统重启或 firewall4 重载后自动尝试恢复未过期的封禁集合。
- 每周一 04:17，包装执行系统上已有的 **/usr/local/sbin/update-geowan.sh**，先快照、更新 GeoIP，再恢复动态集合。
- IPv4/IPv6 分别维护统计；前端只读，走现有 LuCI/rpcd 身份验证和单一状态 JSON 文件。
- 不在 LAN/WAN 开放新端口，不将日志发布到公网，不需要 Node/npm、Docker 或独立 Web 服务。

## 运行要求

- OpenWrt 25.12.x、firewall4/nftables、LuCI、rpcd。
- 已部署 /etc/nftables.d/90-geo-wan.nft，包含：
  - `geo_black4` / `geo_black6` 动态 set
  - `geo_filter` 统计链
  - `geo_wan_input` / `geo_wan_forward`
- Python 3 + SQLite 模块（在 OpenWrt 25.12 的 apk 镜像中是 `python3` 和 `python3-sqlite3`）。
- 预留持久空间；数据库位置 `/etc/geowan-console/telemetry.sqlite3`，目录 0700；tmpfs 状态位于 `/tmp/geowan-console/status.json`。

## 安装（从开发分支获取项目）

在路由器 LAN 侧 SSH 中执行：

```sh
apk update
apk add python3 python3-sqlite3 git
cd /root
git clone --depth 1 --branch feature/geowan-console-v0.1 \
  https://github.com/Accelerator6666/openwrt-builder.git geowan-source
cd /root/geowan-source/projects/geowan-console
sh install.sh
```

再重新登录 LuCI，打开 **服务 → GeoWAN 安全面板**。

> 如 `apk` 无法下载依赖，请先排查仓库网络与 DNS；安装脚本本身不会运行包管理器。

## 验收命令

```sh
/usr/bin/python3 /usr/libexec/geowan-console/agent.py collect
/usr/bin/python3 /usr/libexec/geowan-console/agent.py restore
cat /tmp/geowan-console/status.json
nft list set inet fw4 geo_black4
grep geowan-console /etc/crontabs/root
logread | grep GEOWAN | tail
```

日志 `/tmp/geowan-console-cron.log` 与 `/tmp/geowan-console-update.log` 为**临时日志**；长期事件数据在 SQLite。

## 数据含义

- **丢弃包数**：当前 nftables 规则加载周期内的 counter；firewall4 reload/reboot 会归零。
- **事件/来源排行/趋势**：仅来自 `GEOWAN4` / `GEOWAN6` 内核日志的样本。现有 GeoWAN 规则使用全局日志限速，不会完整记录每个 IP 和每次包命中；任何基于它的统计都不是攻击总量。
- **动态黑名单**：当前拒绝的*非 CN 来源 IP*，不等于已经证实为恶意攻击者。CN IP 仍可能攻击。
- **GeoIP**：CN 归属表包括大陆地址，不代表攻击者的真实所在地；香港/澳门/台湾网段在默认 CN 表外。
- **IPv6**：有规则和数据读取功能，但在没有 IPv6 WAN 默认路由时可能没有实际 IPv6 入站流量。

## 安全边界

1. 严禁把 LuCI 面板或状态文件直接暴露公网。仅通过 LAN 或 VPN 管理。
2. 反代、SSL VPN 和 RDP 的端口映射完全由你现有防火墙配置管理；本项目不会自动禁用、启用或改写。
3. SQLite 包含来源 IP、时间、目的 IP/端口等敏感运维日志，请不要上传至公开 GitHub。
4. 保护入口只是防护面的一部分；JumpServer、FortiGate 和 Windows 仍应分别启用 MFA/NLA/账户锁定与安全补丁。
5. 恢复逻辑在 nft 动态集合存在且未过期时工作；若原规则缺失，会跳过并报告，不会建立一个宽松的替代防火墙。

## 卸载

```sh
cd /root/geowan-source/projects/geowan-console
sh uninstall.sh
# 如确定不再需要审计数据：
# sh uninstall.sh --purge-data
```

卸载不会改动现有 GeoWAN 或其他防火墙规则。

## 测试

```sh
python3 -m unittest discover -s tests -v
sh -n install.sh uninstall.sh scripts/*.sh
```

后续方向：更细粒度的入站速率控制、用户确认的可信 IP 白名单、远程 Syslog、真实来源国家 ASN 归属分析。均须在独立评审后增加，不能在采集组件里偷偷修改防火墙。
