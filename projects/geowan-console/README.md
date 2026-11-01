# GeoWAN Console v0.1.0（开发预览）

为 **OpenWrt 25.12 / firewall4 / nftables** 设计的独立 GeoIP 防护可视化和持久化伴侣，中文 LuCI 页面，无额外监听端口。

> **状态：代码已提交，尚未在目标路由器做实机验收。请先备份再部署。**
> 该组件只观测已经存在的 GeoWAN nftables 规则，不会修改 WAN 防火墙策略、DNAT、PPPoE、daed 或代理分流。

## 功能

- LuCI → 服务 → **GeoWAN 安全面板**：当前被阻断 IP、包计数、过去 24 小时拦截日志趋势、来源 IP、目标端口、最近事件、过期时间。
- SQLite 持久保存被封锁 IP 和最近 30 天的**采样**内核日志；每 5 分钟采集一次；系统重启或 firewall4 重载后自动尝试恢复未过期的封禁集合。
- GeoIP 更新包装脚本已提供，但**不会自动排程**：此前设备上的 /usr/local/sbin/update-geowan.sh 曾因生成 nft 语法错误导致 fw4 check 失败。修复并实机验证前，不自动运行。
- IPv4/IPv6 分别维护统计；前端只读，走现有 LuCI/rpcd 身份验证和单一状态 JSON 文件。
- 不在 LAN/WAN 开放新端口，不将日志发布到公网，不需要 Node/npm、Docker 或独立 Web 服务。

## 运行要求

- OpenWrt 25.12.x、firewall4/nftables、LuCI、rpcd。
- 已部署 /etc/nftables.d/90-geo-wan.nft，包含：
  - geo_cn4 / geo_cn6
  - geo_black4 / geo_black6 动态 set
  - geo_filter、geo_wan_input、geo_wan_forward
  - 内核日志前缀 GEOWAN4 / GEOWAN6
- Python 3 + SQLite 模块（OpenWrt 25.12 apk 包为 python3 和 python3-sqlite3）。
- 数据库 /etc/geowan-console/telemetry.sqlite3，目录权限 0700；状态文件 /tmp/geowan-console/status.json。

## 第一阶段：只读预检

先在路由器执行：

    cd /root/geowan-source/projects/geowan-console
    sh preflight.sh

脚本只读取系统、nftables 对象、JSON 集合样本、日志和磁盘信息，并执行 fw4 check；**不会 reload 防火墙、修改 nftables、写数据库或执行 GeoIP 更新**。如输出 FAIL，先停止并排查，不要安装。

## 安装（预检通过后）

    apk update
    apk add python3 python3-sqlite3 git
    cd /root
    git clone --depth 1 --branch feature/geowan-console-v0.1 https://github.com/Accelerator6666/openwrt-builder.git geowan-source
    cd /root/geowan-source/projects/geowan-console
    sh preflight.sh
    sh install.sh

打开 LuCI：**服务 → GeoWAN 安全面板**。

安装会先检查所需 nftables 对象及 fw4 check。自动任务只有每 5 分钟采集与尝试恢复；每周 GeoIP 更新**保持关闭**，直到现有更新脚本通过独立语法修复和实机验证。

## 验收命令

    /usr/bin/python3 /usr/libexec/geowan-console/agent.py collect
    /usr/bin/python3 /usr/libexec/geowan-console/agent.py restore
    cat /tmp/geowan-console/status.json
    nft list set inet fw4 geo_black4
    grep geowan-console /etc/crontabs/root
    logread | grep GEOWAN | tail

## 数据含义

- **丢弃包数**：当前 nftables 规则加载周期内的 counter；firewall4 reload/reboot 会归零。
- **事件/来源排行/趋势**：仅来自 GEOWAN4 / GEOWAN6 内核日志的样本。现有规则使用全局日志限速，不会完整记录每个 IP 和每次包命中；任何基于它的统计都不是攻击总量。
- **动态黑名单**：当前拒绝的非 CN 来源 IP，不等于已经证实为恶意攻击者。
- **GeoIP**：CN 归属表不是攻击者真实所在地；香港/澳门/台湾网段在默认 CN 表外。
- **IPv6**：设备没有 IPv6 WAN 默认路由时，可能没有实际 IPv6 入站流量。

## 安全边界

1. 不要把 LuCI 面板或状态文件直接暴露公网。仅通过 LAN 或 VPN 管理。
2. RDP、SSL VPN、JumpServer 的端口映射由现有防火墙配置管理；本项目不改动。
3. SQLite 包含来源 IP、时间、目的 IP/端口等敏感运维日志，不要上传公开 GitHub。
4. 黑名单恢复依赖已存在且未过期的 nft 动态集合；若规则缺失，会跳过并报告，不会建立替代防火墙。

## 卸载

    cd /root/geowan-source/projects/geowan-console
    sh uninstall.sh
    # 如确认不再需要审计数据：
    # sh uninstall.sh --purge-data

卸载不会改动现有 GeoWAN 或其他防火墙规则。

## 测试

    python3 -m unittest discover -s tests -v
    sh -n install.sh uninstall.sh scripts/*.sh preflight.sh
    node --check luci/overview.js
