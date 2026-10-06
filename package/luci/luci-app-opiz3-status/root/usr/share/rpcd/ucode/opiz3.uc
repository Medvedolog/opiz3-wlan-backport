'use strict';

// ubus luci.opiz3 status: what the Overview page shows in the "Board" panel.
// Everything comes from sysfs/debugfs/tmp files; nothing here talks to the
// Wi-Fi chip, so polling it cannot disturb the radio.

import { readfile, lsdir, stat, readlink } from 'fs';

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
	return {
		cur: num(`${p}/scaling_cur_freq`),
		max: num(`${p}/scaling_max_freq`),
		governor: rd(`${p}/scaling_governor`),
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
