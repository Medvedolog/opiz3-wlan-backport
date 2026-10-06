'use strict';
'require baseclass';
'require rpc';

var callStatus = rpc.declare({
	object: 'luci.opiz3',
	method: 'status'
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
		return L.resolveDefault(callStatus(), {});
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
