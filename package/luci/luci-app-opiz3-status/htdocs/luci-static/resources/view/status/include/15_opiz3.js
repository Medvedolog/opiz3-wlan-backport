'use strict';
'require baseclass';
'require rpc';

var callStatus = rpc.declare({
	object: 'luci.opiz3',
	method: 'status'
});

var callIwinfoInfo = rpc.declare({
	object: 'iwinfo',
	method: 'info',
	params: [ 'device' ]
});

var callIwinfoAssoc = rpc.declare({
	object: 'iwinfo',
	method: 'assoclist',
	params: [ 'device' ],
	expect: { results: [] }
});

var zoneNames = {
	'cpu-thermal': _('CPU'),
	'gpu-thermal': _('GPU'),
	've-thermal': _('Video engine'),
	'ddr-thermal': _('DRAM')
};

function tempCell(mC) {
	var c = mC / 1000,
	    color = c >= 85 ? '#d9534f' : (c >= 70 ? '#f0ad4e' : null);

	return E('span', color ? { 'style': 'color:' + color + ';font-weight:bold' } : {},
		'%.1f °C'.format(c));
}

function yesNo(v) {
	return v ? _('yes') : _('no');
}

return baseclass.extend({
	title: _('Board'),

	load: function() {
		return L.resolveDefault(callStatus(), {}).then(function(st) {
			var ifs = ((st.wifi || {}).ifaces || []);
			return Promise.all(ifs.map(function(ifname) {
				return Promise.all([
					L.resolveDefault(callIwinfoInfo(ifname), {}),
					L.resolveDefault(callIwinfoAssoc(ifname), [])
				]).then(function(r) {
					return { ifname: ifname, info: r[0], assoc: r[1] };
				});
			})).then(function(ifaces) {
				st.ifaces = ifaces;
				return st;
			});
		});
	},

	render: function(st) {
		var rows = [],
		    w = st.wifi || {},
		    cpu = st.cpu || {};

		(st.thermal || []).forEach(function(z) {
			rows.push([ _('Temperature') + ': ' + (zoneNames[z.type] || z.type), tempCell(z.temp) ]);
		});
		if (!(st.thermal || []).length)
			rows.push([ _('Temperature'), _('no sensors') ]);

		if (cpu.cur)
			rows.push([ _('CPU frequency'), '%d MHz'.format(cpu.cur / 1000) +
				(cpu.max ? ' / %d MHz'.format(cpu.max / 1000) : '') +
				(cpu.governor ? ' (' + cpu.governor + ')' : '') ]);

		var drv;
		if (w.phy)
			drv = _('running') + ' (' + w.phy + (w.mac ? ', ' + w.mac : '') + ')';
		else if (w.driver)
			drv = _('loaded, no radio');
		else if (w.bsp)
			drv = _('SDIO part only (sprdwl_ng not loaded)');
		else
			drv = _('not loaded');
		rows.push([ _('Wi-Fi UWE5622'), drv ]);

		if (w.sdio && w.sdio.clock)
			rows.push([ _('Wi-Fi SDIO bus'), '%d MHz'.format(w.sdio.clock / 1000000) +
				(w.sdio.width ? ', %d-bit'.format(w.sdio.width) : '') +
				(w.sdio.timing ? ', ' + w.sdio.timing : '') ]);

		if (w.firmware)
			rows.push([ _('Wi-Fi firmware'), w.firmware ]);

		/* the host width (what cfg80211/hostapd configured) next to the width
		 * the firmware uses per client, which can differ (it was seen at
		 * 80 MHz with the host at 20); the latter needs cp_txrate=1 */
		var cpRate = /^(Y|1)$/.test((w.params || {}).cp_txrate || '');
		(st.ifaces || []).forEach(function(i) {
			var info = i.info || {};
			if (!info.channel)
				return;
			rows.push([ _('Wi-Fi channel') + ' (' + i.ifname + ')',
				_('channel %d (%d MHz), host width: %s').format(info.channel,
					info.frequency, info.htmode || '?') ]);

			var cl = (i.assoc || []).map(function(a) {
				var tx = a.tx || {};
				if (!cpRate || !tx.rate)
					return null;
				return a.mac + ': ' + (tx.mhz ? tx.mhz + ' MHz' : '?') +
					(tx.vht ? ', VHT-MCS ' + tx.mcs + ' ' + tx.nss + 'SS' : (tx.mcs != null ? ', MCS ' + tx.mcs : '')) +
					', %.1f Mbit/s'.format(tx.rate / 1000);
			}).filter(function(x) { return x; });

			if (!(i.assoc || []).length)
				return;
			rows.push([ _('Wi-Fi width used by the firmware'),
				cpRate ? (cl.length ? E('span', {}, cl.reduce(function(acc, c, n) {
					if (n) acc.push(E('br'));
					acc.push(c);
					return acc;
				}, [])) : _('no rate yet')) :
				_('unknown: set cp_txrate=1 in /etc/uwe5622.options') ]);
		});

		var params = Object.keys(w.params || {}).map(function(k) {
			return k + '=' + w.params[k];
		});
		if (params.length)
			rows.push([ _('Wi-Fi driver options'), params.join(', ') ]);

		var rec = w.recoveries ? String(w.recoveries) : _('none');
		if (w.last_recovery && st.now)
			rec += ' (' + _('last %s ago').format('%t'.format(st.now - w.last_recovery)) + ')';
		rows.push([ _('Wi-Fi firmware recoveries'), rec ]);

		var table = E('table', { 'class': 'table' });
		rows.forEach(function(r) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, [ r[0] ]),
				E('td', { 'class': 'td left' }, [ r[1] ])
			]));
		});
		return table;
	}
});
