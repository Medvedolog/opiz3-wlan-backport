'use strict';
'require view';
'require form';
'require rpc';

var callStatus = rpc.declare({
	object: 'luci.opiz3',
	method: 'status'
});

function mhz(khz) {
	return '%d MHz'.format(khz / 1000);
}

return view.extend({
	load: function() {
		return L.resolveDefault(callStatus(), {});
	},

	render: function(st) {
		var cpu = st.cpu || {},
		    m, s, o;

		m = new form.Map('opiz3', _('CPU frequency'),
			_('CPU frequency scaling of the Allwinner H616/H618. OpenWrt starts with "performance" (always the top frequency); "ondemand" runs at the lowest frequency when idle and goes to the top under load.') + '<br />' +
			_('Now: %s, governor %s.').format(cpu.cur ? mhz(cpu.cur) : '?', cpu.governor || '?') + ' ' +
			_('The kernel lowers the frequency by itself at 60 and 70 °C (thermal trips); higher frequencies than the table below are not offered.'));

		s = m.section(form.NamedSection, 'cpufreq', 'cpufreq');
		s.addremove = false;

		o = s.option(form.ListValue, 'governor', _('Governor'));
		(cpu.governors || [ 'ondemand', 'performance', 'powersave' ]).forEach(function(g) {
			o.value(g);
		});
		o.default = 'ondemand';

		o = s.option(form.ListValue, 'min_freq', _('Minimum frequency'));
		o.value('', _('hardware minimum'));
		(cpu.frequencies || []).forEach(function(f) { o.value(String(f), mhz(f)); });

		o = s.option(form.ListValue, 'max_freq', _('Maximum frequency'));
		o.value('', _('hardware maximum'));
		(cpu.frequencies || []).forEach(function(f) { o.value(String(f), mhz(f)); });
		o.validate = function(section_id, value) {
			var min = this.section.formvalue(section_id, 'min_freq');
			if (value && min && +value < +min)
				return _('Maximum must not be below minimum');
			return true;
		};

		return m.render();
	}
});
