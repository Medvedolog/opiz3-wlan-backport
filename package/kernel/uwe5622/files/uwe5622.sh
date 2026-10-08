# Helpers for the UWE5622 scripts (sourced, not run).
#
# The image carries drivers for many USB Wi-Fi adapters; one plugged in at
# boot registers before the delayed UWE5622 and takes phy0/radio0. So the
# onboard radio is found by what it is, never by number.

UWE_MODALIAS=platform:unisoc_wifi

# phy name of the onboard radio (phy0, phy1, ...), empty if none
uwe_phy() {
	local p
	for p in /sys/class/ieee80211/*; do
		[ "$(cat "$p/device/modalias" 2>/dev/null)" = "$UWE_MODALIAS" ] || continue
		echo "${p##*/}"
		return 0
	done
	return 1
}

# wait up to $1 seconds (default 30) for the phy, print its name
uwe_wait_phy() {
	local i=0 n=${1:-30} phy
	while :; do
		phy=$(uwe_phy) && { echo "$phy"; return 0; }
		[ "$i" -ge "$n" ] && return 1
		sleep 1; i=$((i + 1))
	done
}

# wifi-device section(s) of the onboard radio (path platform/unisoc_wifi)
uwe_radios() {
	uci -q show wireless |
		sed -n "s/^wireless\.\([^.=]*\)\.path='platform\/unisoc_wifi.*$/\1/p"
}

# platform device of the SDIO host the module sits on: the mmc host with
# an mmc-pwrseq in its device tree node (the SD card slot has none)
uwe_mmc_host() {
	local h
	for h in /sys/class/mmc_host/*; do
		[ -e "$h/device/of_node/mmc-pwrseq" ] || continue
		readlink -f "$h/device"
		return 0
	done
	readlink -f /sys/class/mmc_host/mmc1/device 2>/dev/null
}

# rmmod with a timeout; a dead chip can block it. On timeout the rmmod is
# killed (if it can be) and the call fails, so callers never go on while
# the module is still there or still being removed.
uwe_unload() {
	local i=0 pid
	[ -d "/sys/module/$1" ] || return 0
	rmmod "$1" 2>/dev/null &
	pid=$!
	while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 20 ]; do
		sleep 1; i=$((i + 1))
	done
	if kill -0 "$pid" 2>/dev/null; then
		kill -9 "$pid" 2>/dev/null
		logger -t uwe5622 "rmmod $1 did not finish in 20 s"
		return 1
	fi
	wait "$pid" 2>/dev/null
	[ ! -d "/sys/module/$1" ]
}

uwe_load_wifi() {
	local opts
	opts=$(sed "s/#.*//" /etc/uwe5622.options 2>/dev/null | xargs)
	/sbin/insmod sprdwl_ng disable_powersave=1 $opts
}

# wifi up/down for the onboard radio(s) only. "up" asks netifd directly:
# "/sbin/wifi up" also runs "ubus call network reload", which restarts
# every interface still being set up, e.g. an LTE modem ModemManager is
# probing at boot (it went down and stayed down until something retried).
# A radio netifd does not know yet (config just created) needs the
# reload, so fall back to it then. After a config change call
# "ubus call network reload" first.
uwe_wifi() {
	local r
	for r in $(uwe_radios); do
		if [ "$1" = up ]; then
			ubus call network.wireless up "{\"device\":\"$r\"}" 2>/dev/null || {
				ubus call network reload
				sleep 2
				ubus call network.wireless up "{\"device\":\"$r\"}"
			}
		else
			/sbin/wifi "$1" "$r"
		fi
	done
}
