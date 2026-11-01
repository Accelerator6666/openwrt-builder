'use strict';
'require view';
'require rpc';
'require poll';
'require dom';

var readStatus = rpc.declare({
    object: 'file', method: 'read', params: [ 'path' ],
    expect: { data: '' }
});

var lookupIp = rpc.declare({
    object: 'geowan', method: 'lookup', params: [ 'ip' ]
});

var listBans = rpc.declare({
    object: 'geowan', method: 'list_bans',
    params: [ 'page', 'page_size', 'query', 'family', 'country_code',
              'asn', 'port', 'proto', 'sort' ]
});

var getBan = rpc.declare({
    object: 'geowan', method: 'get_ban', params: [ 'ip' ]
});

function timeString(epoch) {
    return epoch ? new Date(epoch * 1000).toLocaleString() : '—';
}

function durationString(seconds) {
    seconds = Math.max(0, Number(seconds) || 0);
    if (!seconds) return '已过期';
    var days = Math.floor(seconds / 86400);
    var hours = Math.floor((seconds % 86400) / 3600);
    var minutes = Math.floor((seconds % 3600) / 60);
    if (days) return days + ' 天 ' + hours + ' 小时';
    if (hours) return hours + ' 小时 ' + minutes + ' 分钟';
    return minutes + ' 分钟';
}

function dataFromRpc(data) {
    if (typeof data == 'string') return JSON.parse(data);
    if (data && typeof data.data == 'string') return JSON.parse(data.data);
    throw new Error('未收到有效的状态文件');
}

function card(label, value, note) {
    return E('div', { 'class': 'gw-card' }, [
        E('div', { 'class': 'gw-label' }, label),
        E('div', { 'class': 'gw-value' }, String(value)),
        E('div', { 'class': 'gw-note' }, note || '')
    ]);
}

function table(headers, rows) {
    return E('table', { 'class': 'table gw-table' }, [
        E('thead', {}, E('tr', {}, headers.map(function(h) {
            return E('th', {}, h);
        }))),
        E('tbody', {}, rows.length ? rows.map(function(cells) {
            return E('tr', {}, cells.map(function(c) {
                return E('td', {}, c == null ? '—' : String(c));
            }));
        }) : E('tr', {}, E('td', { 'colspan': headers.length }, '暂无数据')))
    ]);
}

function panel(title, body) {
    var children = [ E('h3', {}, title) ];
    if (Array.isArray(body))
        children = children.concat(body);
    else if (body != null)
        children.push(body);
    return E('section', { 'class': 'gw-panel' }, children);
}

function lookupPanel() {
    var input = E('input', {
        'type': 'text',
        'class': 'cbi-input-text',
        'placeholder': '输入公网 IPv4 或 IPv6 地址',
        'autocomplete': 'off',
        'spellcheck': 'false'
    });
    var button = E('button', {
        'type': 'button',
        'class': 'cbi-button cbi-button-action'
    }, '查询归属地');
    var result = E('div', { 'class': 'gw-lookup-result' }, '输入 IP 地址后查询本地离线数据库。');

    function runLookup() {
        var value = input.value.trim();
        if (!value) {
            dom.content(result, '请输入 IP 地址。');
            return;
        }
        button.disabled = true;
        dom.content(result, '正在查询……');
        lookupIp(value).then(function(data) {
            button.disabled = false;
            if (data.error) {
                dom.content(result, '查询失败：' + data.error);
                return;
            }
            if (data.lookup_status != 'ok') {
                var labels = {
                    invalid: 'IP 地址格式不正确',
                    non_global: '这是非公网地址，不进行公网归属地定位',
                    unavailable: 'GeoIP 数据库或 MMDB Reader 尚未安装',
                    not_found: '数据库中没有匹配记录'
                };
                dom.content(result, labels[data.lookup_status] || '未能取得归属信息');
                return;
            }
            dom.content(result, table(['字段', '查询结果'], [
                ['IP 地址', data.ip],
                ['国家 / 地区', (data.country_name || '未知') + (data.country_code ? ' (' + data.country_code + ')' : '')],
                ['大洲', data.continent_name || data.continent_code],
                ['省份 / 州', data.region],
                ['城市', data.city],
                ['ASN', data.asn ? 'AS' + data.asn : ''],
                ['网络组织', data.asn_org],
                ['数据源', data.provider + ' · ' + data.database_version]
            ]));
        }).catch(function(error) {
            button.disabled = false;
            dom.content(result, 'RPC 查询失败：' + String(error));
        });
    }

    button.addEventListener('click', runLookup);
    input.addEventListener('keydown', function(event) {
        if (event.key == 'Enter') runLookup();
    });

    return panel('IP 归属地查询（本地离线数据库）',
        E('div', { 'class': 'gw-lookup' }, [input, button, result]));
}

function blacklistPanel() {
    var query = E('input', {
        'type': 'text', 'class': 'cbi-input-text',
        'placeholder': '搜索 IP、国家、城市或网络组织',
        'autocomplete': 'off', 'spellcheck': 'false'
    });
    var family = E('select', { 'class': 'cbi-input-select' }, [
        E('option', { 'value': '0' }, '全部协议族'),
        E('option', { 'value': '4' }, 'IPv4'),
        E('option', { 'value': '6' }, 'IPv6')
    ]);
    var country = E('input', {
        'type': 'text', 'class': 'cbi-input-text',
        'placeholder': '国家代码，如 US、JP',
        'maxlength': '3', 'autocomplete': 'off'
    });
    var asn = E('input', {
        'type': 'number', 'class': 'cbi-input-text',
        'placeholder': 'ASN，如 15169', 'min': '1'
    });
    var port = E('input', {
        'type': 'number', 'class': 'cbi-input-text',
        'placeholder': '目标端口，如 31080', 'min': '1', 'max': '65535'
    });
    var proto = E('select', { 'class': 'cbi-input-select' }, [
        E('option', { 'value': '' }, '全部协议'),
        E('option', { 'value': 'TCP' }, 'TCP'),
        E('option', { 'value': 'UDP' }, 'UDP'),
        E('option', { 'value': 'ICMP' }, 'ICMP'),
        E('option', { 'value': 'ICMPV6' }, 'ICMPv6'),
        E('option', { 'value': 'GRE' }, 'GRE'),
        E('option', { 'value': 'ESP' }, 'ESP')
    ]);
    var sort = E('select', { 'class': 'cbi-input-select' }, [
        E('option', { 'value': 'last_seen' }, '最近发现优先'),
        E('option', { 'value': 'first_seen' }, '首次发现优先'),
        E('option', { 'value': 'expires_at' }, '即将过期优先'),
        E('option', { 'value': 'ip' }, '按 IP 排序')
    ]);
    var apply = E('button', {
        'type': 'button', 'class': 'cbi-button cbi-button-action'
    }, '查询 / 筛选');
    var clear = E('button', {
        'type': 'button', 'class': 'cbi-button'
    }, '清空条件');
    var summary = E('div', { 'class': 'gw-list-summary' }, '正在读取活跃黑名单……');
    var list = E('div', { 'class': 'gw-list-table' });
    var detail = E('div', { 'class': 'gw-ban-detail' });
    var previous = E('button', {
        'type': 'button', 'class': 'cbi-button'
    }, '上一页');
    var next = E('button', {
        'type': 'button', 'class': 'cbi-button'
    }, '下一页');
    var pageLabel = E('span', { 'class': 'gw-page-label' }, '第 1 页');
    var state = { page: 1, pages: 1, busy: false };

    function numberOrZero(value) {
        if (value == null || String(value).trim() === '') return 0;
        var parsed = Number(value);
        return Number.isInteger(parsed) && parsed >= 0 ? parsed : -1;
    }

    function showDetail(ip) {
        dom.content(detail, E('p', {}, '正在读取 ' + ip + ' 的详情……'));
        getBan(ip).then(function(data) {
            if (data.error || !data.found) {
                dom.content(detail, '未找到该 IP 的活动封禁记录。');
                return;
            }
            var item = data.item;
            var location = [item.region, item.city].filter(Boolean).join(' / ');
            var rows = [
                ['IP 地址', item.ip],
                ['协议族', 'IPv' + item.family],
                ['国家 / 地区', (item.country_name || '未知') + (item.country_code ? ' (' + item.country_code + ')' : '')],
                ['大洲', item.continent_name || item.continent_code],
                ['地区 / 城市', location],
                ['ASN', item.asn ? 'AS' + item.asn : ''],
                ['网络组织', item.asn_org],
                ['GeoIP 数据库', item.provider + ' · ' + item.database_version],
                ['归属查询状态', item.lookup_status],
                ['首次发现', timeString(item.first_seen)],
                ['最近发现', timeString(item.last_seen)],
                ['封禁到期', timeString(item.expires_at)],
                ['剩余封禁时间', durationString(item.remaining_seconds)],
                ['日志采样事件数', item.event_count]
            ];
            var events = (item.events || []).map(function(event) {
                return [timeString(event.ts), event.dst, event.port, event.proto];
            });
            dom.content(detail, E('div', {}, [
                E('h4', {}, 'IP 详情：' + item.ip),
                table(['字段', '信息'], rows),
                E('h4', {}, '最近日志样本（最多 30 条）'),
                table(['时间', '目标 IP', '目标端口', '协议'], events),
                E('p', { 'class': 'gw-muted' },
                    '日志样本受内核限速和 30 天保留策略影响，不代表该 IP 的全部连接或全部攻击次数。')
            ]));
        }).catch(function(error) {
            dom.content(detail, '详情查询失败：' + String(error));
        });
    }

    function renderPage(data) {
        if (data.error) {
            dom.content(summary, '查询失败：' + data.error);
            dom.content(list, '');
            return;
        }

        state.pages = Math.max(1, data.pages || 1);
        dom.content(summary,
            '共 ' + data.total + ' 条活跃封禁记录 · 第 ' + data.page +
            ' / ' + state.pages + ' 页 · 每页 ' + data.page_size + ' 条。' +
            '端口 / 协议筛选基于内核日志样本。');

        var rows = (data.items || []).map(function(item) {
            var location = [item.region, item.city].filter(Boolean).join(' / ');
            var asnText = item.asn ? 'AS' + item.asn + ' ' + (item.asn_org || '') : '';
            var button = E('button', {
                'type': 'button', 'class': 'cbi-button cbi-button-small'
            }, '详情');
            button.addEventListener('click', function() {
                showDetail(item.ip);
            });
            return E('tr', {}, [
                E('td', {}, item.ip),
                E('td', {}, 'IPv' + item.family),
                E('td', {}, item.country_name || item.country_code || '待识别'),
                E('td', {}, location || '—'),
                E('td', {}, asnText || '—'),
                E('td', {}, timeString(item.last_seen)),
                E('td', {}, timeString(item.expires_at)),
                E('td', {}, String(item.event_count || 0)),
                E('td', {}, button)
            ]);
        });

        dom.content(list, E('table', { 'class': 'table gw-table gw-blacklist-table' }, [
            E('thead', {}, E('tr', {}, [
                'IP 地址', '协议族', '国家', '地区 / 城市', 'ASN / 网络组织',
                '最近发现', '封禁到期', '日志样本', '详情'
            ].map(function(label) { return E('th', {}, label); }))),
            E('tbody', {}, rows.length ? rows :
                E('tr', {}, E('td', { 'colspan': '9' }, '没有符合条件的活跃封禁记录。')))
        ]));

        pageLabel.textContent = '第 ' + data.page + ' / ' + state.pages + ' 页';
        previous.disabled = state.busy || data.page <= 1;
        next.disabled = state.busy || data.page >= state.pages;
    }

    function loadPage(page) {
        if (state.busy) return;
        var familyValue = numberOrZero(family.value);
        var asnValue = numberOrZero(asn.value);
        var portValue = numberOrZero(port.value);
        if (familyValue < 0 || asnValue < 0 || portValue < 0) {
            dom.content(summary, '筛选数值格式不正确。');
            return;
        }

        state.page = page;
        state.busy = true;
        apply.disabled = true;
        previous.disabled = true;
        next.disabled = true;
        dom.content(summary, '正在查询黑名单……');

        listBans(
            page, 50, query.value.trim(), familyValue,
            country.value.trim().toUpperCase(), asnValue,
            portValue, proto.value, sort.value
        ).then(function(data) {
            state.busy = false;
            apply.disabled = false;
            renderPage(data);
        }).catch(function(error) {
            state.busy = false;
            apply.disabled = false;
            dom.content(summary, '黑名单查询 RPC 失败：' + String(error));
            previous.disabled = false;
            next.disabled = false;
        });
    }

    apply.addEventListener('click', function() { loadPage(1); });
    query.addEventListener('keydown', function(event) {
        if (event.key == 'Enter') loadPage(1);
    });
    clear.addEventListener('click', function() {
        query.value = '';
        family.value = '0';
        country.value = '';
        asn.value = '';
        port.value = '';
        proto.value = '';
        sort.value = 'last_seen';
        loadPage(1);
    });
    previous.addEventListener('click', function() {
        if (state.page > 1) loadPage(state.page - 1);
    });
    next.addEventListener('click', function() {
        if (state.page < state.pages) loadPage(state.page + 1);
    });

    var filterGrid = E('div', { 'class': 'gw-filter-grid' }, [
        E('label', {}, ['搜索', query]),
        E('label', {}, ['协议族', family]),
        E('label', {}, ['国家代码', country]),
        E('label', {}, ['ASN', asn]),
        E('label', {}, ['目标端口', port]),
        E('label', {}, ['协议', proto]),
        E('label', {}, ['排序', sort])
    ]);
    var controls = E('div', { 'class': 'gw-filter-actions' }, [
        apply, clear,
        E('span', { 'class': 'gw-filter-hint' },
            '说明：端口与协议条件匹配已采集到的拒绝日志样本。')
    ]);
    var pager = E('div', { 'class': 'gw-pagination' }, [
        previous, pageLabel, next
    ]);

    var root = panel('持久化黑名单查询与 IP 详情', [
        filterGrid, controls, summary, list, pager, detail
    ]);
    loadPage(1);
    return root;
}

function draw(d, lookupNode, blacklistNode) {
    var counters = d.counters || {};
    var total = (counters.black4 || 0) + (counters.geo4 || 0) +
                (counters.black6 || 0) + (counters.geo6 || 0);
    var hours = d.hours || [];
    var max = Math.max(1, ...hours.map(function(h) { return h.count || 0; }));
    var bars = E('div', { 'class': 'gw-bars' }, hours.map(function(h) {
        return E('div', {
            'class': 'gw-bar',
            'title': timeString(h.time) + ': ' + h.count + ' 条日志样本',
            'style': 'height:' + Math.max(3, Math.round((h.count || 0) / max * 100)) + '%'
        });
    }));
    var header = E('div', { 'class': 'gw-heading' }, [
        E('div', {}, [
            E('h2', {}, 'GeoWAN 安全防护'),
            E('p', {}, 'OpenWrt firewall4 · WAN 入站观测 · 只读控制台')
        ]),
        E('span', { 'class': 'gw-status ' + (d.status == 'ok' ? 'ok' : 'warn') },
            d.status == 'ok' ? '采集正常' : '数据不完整')
    ]);

    return E('div', { 'class': 'gw-app' }, [
        E('link', { 'rel': 'stylesheet', 'href': L.resource('geowan/geowan.css') }),
        header,
        E('div', { 'class': 'gw-cards' }, [
            card('活跃黑名单记录', d.active_bans || 0, 'IPv4 / IPv6 · 过期自动释放'),
            card('本次规则加载以来丢弃包', total, 'nftables counter，非历史累计'),
            card('过去 24 小时日志样本', d.samples_24h || 0, '受内核日志限速影响'),
            card('监控数据更新', timeString(d.updated), d.collector && d.collector.mode == 'fast' ? '快速监控运行中' : '定时对账模式'),
            card('GeoIP 数据库', d.geoip && d.geoip.enabled ? d.geoip.database_version : '未安装', d.geoip ? ('已识别 ' + d.geoip.resolved_active_bans + ' / ' + d.geoip.active_bans + ' 个活跃 IP') : '离线归属查询'),
            card('IPv4 / IPv6 集合', (d.set_sizes && d.set_sizes['4'] != null ? d.set_sizes['4'] : '?')
                + ' / ' + (d.set_sizes && d.set_sizes['6'] != null ? d.set_sizes['6'] : '?'), '活跃 IP 条目数')
        ]),
        lookupNode || E('span'),
        panel('24 小时拦截日志趋势（采样）', [
            bars,
            E('div', { 'class': 'gw-chart-axis' }, ['23 小时前', '当前'])
        ]),
        E('div', { 'class': 'gw-columns' }, [
            panel('日志样本最多的来源', table(['来源 IP', '国家', '城市', 'ASN', '日志数'],
                (d.top_sources || []).map(function(r) {
                    return [r.ip, r.country || r.country_code, r.city, r.asn ? ('AS' + r.asn + ' ' + (r.asn_org || '')) : '', r.count];
                }))),
            panel('日志目标端口（DPT）', table(['端口', '用途', '日志样本'],
                (d.top_ports || []).map(function(r) { return [r.port, r.service, r.count]; })))
        ]),
        E('div', { 'class': 'gw-columns' }, [
            panel('海外来源国家排行（活跃封禁 IP）', table(['国家', '国家代码', 'IP 数'],
                (d.top_countries || []).map(function(r) { return [r.country, r.code, r.ips]; }))),
            panel('来源 ASN / 网络组织排行', table(['ASN', '网络组织', 'IP 数'],
                (d.top_asns || []).map(function(r) { return [r.asn ? ('AS' + r.asn) : '', r.organization, r.ips]; })))
        ]),
        panel('最近的拒绝记录（日志样本）', table(['时间', '来源 IP', '国家', '城市', '目标 IP', '目标端口', '协议'],
            (d.events || []).slice(0, 40).map(function(r) {
                return [timeString(r.time), r.src, r.country || r.country_code, r.city, r.dst, r.port, r.proto];
            }))),
        blacklistNode || E('span'),
        (d.errors || []).length ? E('p', { 'class': 'gw-error' }, d.errors.join('；')) : E('span'),
        E('div', { 'class': 'gw-footer' }, [
            '更新：' + timeString(d.updated) + ' · ' +
            (d.collector ? ('采集：' + d.collector.mode + ' · 黑名单扫描：' + d.collector.inventory_interval_seconds + ' 秒 · ') : ''),
            d.disclaimer || '统计数据仅供防火墙运维使用。',
            d.geoip && d.geoip.enabled ? E('a', { 'href': d.geoip.attribution_url, 'target': '_blank', 'rel': 'noopener noreferrer' }, 'IP Geolocation by DB-IP') : ''
        ])
    ]);
}

return view.extend({
    load: function() {
        return readStatus('/tmp/geowan-console/status.json').then(dataFromRpc);
    },
    render: function(data) {
        var lookup = lookupPanel();
        var blacklist = blacklistPanel();
        var app = draw(data, lookup, blacklist);
        var root = E('div', {}, app);
        poll.add(function() {
            return readStatus('/tmp/geowan-console/status.json').then(function(next) {
                var refreshed = draw(dataFromRpc(next), lookup, blacklist);
                dom.content(root, refreshed);
            }).catch(function() {
                /* Keep the last known snapshot visible during an RPC outage. */
            });
        }, 5);
        return root;
    },
    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
