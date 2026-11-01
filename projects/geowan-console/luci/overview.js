'use strict';
'require view';
'require rpc';
'require poll';
'require dom';

var readStatus = rpc.declare({
    object: 'file', method: 'read', params: [ 'path' ],
    expect: { data: '' }
});

function timeString(epoch) {
    return epoch ? new Date(epoch * 1000).toLocaleString() : '—';
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

function draw(d) {
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
            card('IPv4 / IPv6 集合', (d.set_sizes && d.set_sizes['4'] != null ? d.set_sizes['4'] : '?')
                + ' / ' + (d.set_sizes && d.set_sizes['6'] != null ? d.set_sizes['6'] : '?'), '活跃 IP 条目数')
        ]),
        panel('24 小时拦截日志趋势（采样）', [
            bars,
            E('div', { 'class': 'gw-chart-axis' }, ['23 小时前', '当前'])
        ]),
        E('div', { 'class': 'gw-columns' }, [
            panel('日志样本最多的来源', table(['来源 IP', '日志数'],
                (d.top_sources || []).map(function(r) { return [r.ip, r.count]; }))),
            panel('目标端口（DNAT 后）', table(['端口', '用途', '日志数'],
                (d.top_ports || []).map(function(r) { return [r.port, r.service, r.count]; })))
        ]),
        panel('最近的拒绝记录', table(['时间', '来源 IP', '目标 IP', '目标端口', '协议'],
            (d.events || []).slice(0, 40).map(function(r) {
                return [timeString(r.time), r.src, r.dst, r.port, r.proto];
            }))),
        panel('持久化黑名单（最近 120 条）', table(['IP', '协议族', '有效期至'],
            (d.blacklist || []).map(function(r) {
                return [r.ip, 'IPv' + r.family, timeString(r.expires)];
            }))),
        (d.errors || []).length ? E('p', { 'class': 'gw-error' }, d.errors.join('；')) : E('span'),
        E('div', { 'class': 'gw-footer' }, [
            '更新：' + timeString(d.updated) + ' · ',
            d.disclaimer || '统计数据仅供防火墙运维使用。'
        ])
    ]);
}

return view.extend({
    load: function() {
        return readStatus('/tmp/geowan-console/status.json').then(dataFromRpc);
    },
    render: function(data) {
        var root = E('div', {}, draw(data));
        poll.add(function() {
            return readStatus('/tmp/geowan-console/status.json').then(function(next) {
                dom.content(root, draw(dataFromRpc(next)));
            }).catch(function() {
                /* Keep the last known snapshot visible during an RPC outage. */
            });
        }, 30);
        return root;
    },
    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
