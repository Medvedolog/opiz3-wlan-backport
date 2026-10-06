'use strict';

// ubus luci.opiz3 status: what the Overview page shows in the "Board" panel.
// Everything comes from sysfs/debugfs/tmp files; nothing here talks to the
// Wi-Fi chip, so polling it cannot disturb the radio.

import { readfile, lsdir, stat, readlink } from 'fs';
import { cursor } from 'uci';

// the Wi-Fi password the image sets on first boot (sprdwl-delay); the panel
// warns while it is still in use
const DEFAULT_KEY = '12345678test';

let nl80211;
try { nl80211 = require('nl80211'); } catch (e) { nl80211 = null; }

function rd(path) {
	let s = readfile(path);
	return (s == null) ? null : trim(s);
}

function num(path) {
	let s = rd(path);
	return (s == null || !match(s, /^-?[0-9]+$/)) ? null : +s;
}

function thermal() {
	let zones = [];
	for (let z in sort(lsdir('/sys/class/thermal') ?? [])) {
		if (!match(z, /^thermal_zone[0-9]+$/))
			continue;
		let t = num(`/sys/class/thermal/${z}/temp`);
		if (t == null)
			continue;
		push(zones, { type: rd(`/sys/class/thermal/${z}/type`) ?? z, temp: t });
	}
	return zones;
}

function cpu() {
	let p = '/sys/devices/system/cpu/cpu0/cpufreq';
	let words = (path) => filter(split(rd(path) ?? '', /[ \t]+/), (w) => length(w));
	return {
		cur: num(`${p}/scaling_cur_freq`),
		min: num(`${p}/scaling_min_freq`),
		max: num(`${p}/scaling_max_freq`),
		governor: rd(`${p}/scaling_governor`),
		governors: words(`${p}/scaling_available_governors`),
		frequencies: map(words(`${p}/scaling_available_frequencies`), (f) => +f),
	};
}

// the mmc host of the module: the one with an mmc-pwrseq in its device tree
// node (the SD card slot has none), as uwe_mmc_host in /lib/uwe5622.sh
function sdio_host() {
	for (let h in sort(lsdir('/sys/class/mmc_host') ?? []))
		if (stat(`/sys/class/mmc_host/${h}/device/of_node/mmc-pwrseq`))
			return h;
	return 'mmc1';
}

function sdio() {
	// "clock: 50000000 Hz", "timing spec: 2 (sd high-speed)", "bus width: 2 (4 bits)"
	let host = sdio_host();
	let ios = readfile(`/sys/kernel/debug/${host}/ios`);
	if (ios == null)
		return null;
	let r = { host: host };
	let m = match(ios, /actual clock:[ \t]*([0-9]+) Hz/) ?? match(ios, /clock:[ \t]*([0-9]+) Hz/);
	if (m) r.clock = +m[1];
	m = match(ios, /timing spec:[ \t]*[0-9]+ \(([^)]*)\)/);
	if (m) r.timing = m[1];
	m = match(ios, /bus width:[ \t]*[0-9]+ \(([0-9]+) bits\)/);
	if (m) r.width = +m[1];
	return r;
}

// "Platform Version: MARLIN3_19B_W21.05.3" is embedded in the firmware file
// the BSP downloads; read once per rpcd start
let fw_version_cache;
function fw_version() {
	if (fw_version_cache == null) {
		fw_version_cache = '';
		let fw = readfile('/lib/firmware/uwe5622/wcnmodem.bin');
		let i = fw ? index(fw, 'Platform Version:') : -1;
		if (i >= 0) {
			let m = match(substr(fw, i, 80), /^Platform Version:[ \t]*([A-Za-z0-9_.\-]+)/);
			if (m)
				fw_version_cache = m[1];
		}
	}
	return fw_version_cache;
}

// DHCP names and addresses by MAC, from dnsmasq's lease file
function leases() {
	let r = {};
	for (let l in split(readfile('/tmp/dhcp.leases') ?? '', '\n')) {
		let f = split(l, ' ');
		if (length(f) >= 4)
			r[lc(f[1])] = { ip: f[2], name: (f[3] == '*') ? null : f[3] };
	}
	return r;
}

// stations of our AP interfaces, the same data as "iw dev X station dump"
// (one netlink dump; the driver answers from its own counters)
function clients(ifaces) {
	let out = [];
	if (!nl80211)
		return out;
	let names = leases();
	for (let ifname in ifaces) {
		let st = nl80211.request(nl80211.const.NL80211_CMD_GET_STATION,
			nl80211.const.NLM_F_DUMP, { dev: ifname }) ?? [];
		for (let s in st) {
			let i = s.sta_info ?? {};
			let tx = i.tx_bitrate ?? {};
			let mac = lc(s.mac ?? '');
			push(out, {
				ifname: ifname,
				mac: mac,
				name: names[mac]?.name,
				ip: names[mac]?.ip,
				rx_bytes: i.rx_bytes64 ?? i.rx_bytes,
				tx_bytes: i.tx_bytes64 ?? i.tx_bytes,
				connected: i.connected_time,
				signal: i.signal,
				tx_rate: tx.bitrate32 ?? tx.bitrate,
				tx_mcs: tx.vht_mcs ?? tx.mcs,
				tx_vht: (tx.vht_mcs != null),
				tx_mhz: tx.width_80 ? 80 : (tx['40_mhz_width'] ? 40 : (tx.bitrate32 ?? tx.bitrate) ? 20 : null),
			});
		}
	}
	return out;
}

// any of our Wi-Fi networks still on the default password
function default_key() {
	let c = cursor();
	let radios = {};
	let found = false;
	c.foreach('wireless', 'wifi-device', (d) => {
		if (index(d.path ?? '', 'platform/unisoc_wifi') == 0)
			radios[d['.name']] = true;
	});
	c.foreach('wireless', 'wifi-iface', (w) => {
		if (radios[w.device] && w.disabled != '1' && w.key == DEFAULT_KEY)
			found = true;
	});
	return found;
}

function wifi() {
	let w = {
		bsp: !!stat('/sys/module/uwe5622_bsp_sdio'),
		driver: !!stat('/sys/module/sprdwl_ng'),
		phy: null,
		params: {},
		recoveries: 0,
		last_recovery: null,
	};

	for (let phy in sort(lsdir('/sys/class/ieee80211') ?? [])) {
		let dev = readlink(`/sys/class/ieee80211/${phy}/device`);
		if (dev && match(dev, /unisoc_wifi$/)) {
			w.phy = phy;
			w.mac = rd(`/sys/class/ieee80211/${phy}/macaddress`);
			// its network interfaces (phy0-ap0, ...), for iwinfo in the page
			w.ifaces = filter(sort(lsdir(`/sys/class/ieee80211/${phy}/device/net`) ?? []),
				(n) => stat(`/sys/class/net/${n}/phy80211`));
			break;
		}
	}

	for (let p in [ 'disable_powersave', 'max_bw_5g', 'cp_txrate' ]) {
		let v = rd(`/sys/module/sprdwl_ng/parameters/${p}`);
		if (v != null)
			w.params[p] = v;
	}

	// uwe5622-recover appends the time of every recovery
	let times = rd('/tmp/uwe5622-recover.times');
	if (times) {
		let t = filter(split(times, '\n'), (l) => length(l));
		w.recoveries = length(t);
		w.last_recovery = length(t) ? +t[length(t) - 1] : null;
	}

	w.sdio = sdio();
	w.firmware = fw_version();
	w.clients = clients(filter(w.ifaces ?? [], (n) => !match(n, /-sta[0-9]*$/)));
	w.default_key = default_key();
	return w;
}

return {
	'luci.opiz3': {
		status: {
			call: function() {
				return {
					thermal: thermal(),
					cpu: cpu(),
					wifi: wifi(),
					uptime: +split(rd('/proc/uptime') ?? '0', ' ')[0],
					now: time(),
				};
			}
		}
	}
};
