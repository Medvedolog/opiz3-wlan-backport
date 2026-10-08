#!/bin/sh
# Collect a diagnostic bundle directly ON the board (OpenWrt), not from
# another computer. Contributed by a tester; extended here.
#
#   wget -O /tmp/collect-debug.sh https://raw.githubusercontent.com/Medvedolog/opiz3-wlan-backport/main/scripts/collect-debug.sh
#   sh /tmp/collect-debug.sh
#
# Output: /tmp/<board-name>-debug-<timestamp>/ and a .tar.gz of it, with
# everything needed to diagnose Wi-Fi, boot and network issues.
# Passwords, keys and PINs in the configuration are masked before saving;
# the logs still contain MAC addresses and host names.
# No jq required.
set -eu

# --- board name from /etc/board.json -----------------------------------------
# OpenWrt 24.10/25.x stores model as an object:
#   "model": { "id": "xunlong,orangepi-zero2w", "name": "OrangePi Zero 2W" }
# We take model.id (always present, unique, no spaces) and sanitize it.
BOARD_NAME=""
if [ -f /etc/board.json ]; then
	BOARD_NAME=$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /etc/board.json \
		| head -n1 \
		| tr ',' '-' \
		| tr ' ' '_' \
		| tr -cd 'A-Za-z0-9._-')
fi
[ -n "$BOARD_NAME" ] || BOARD_NAME="openwrt"

OUT="/tmp/${BOARD_NAME}-debug-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$OUT"
echo ">> board: $BOARD_NAME"
echo ">> collecting into $OUT/"

grab() { # grab <filename> <command on board>
	printf '  %-28s' "$1"
	if sh -c "$2" > "$OUT/$1" 2>&1; then echo ok; else echo FAILED; fi
}

# masks the value of every option that can hold a secret
MASK='sed -E "s/^([^=]*\.(key|psk|password|passwd|secret|private_key|preshared_key|sae_password|auth_secret|pin|pincode|wpa_passphrase)(=|[0-9]*=)).*/\1<MASKED>/"'

grab 00-board.txt        'ubus call system board; echo; cat /etc/openwrt_release; echo; uptime'
grab 01-dmesg.txt        'dmesg'
grab 02-logread.txt      'logread'
grab 03-modules.txt      'lsmod'
grab 04-meminfo.txt      'grep MemTotal /proc/meminfo; free -m; cat /proc/cmdline'
grab 05-sdio.txt         'ls -la /sys/bus/sdio/devices/ 2>&1; echo; for d in /sys/bus/sdio/devices/*; do echo "== $d"; cat $d/vendor $d/device 2>/dev/null; done'
grab 06-devicetree.txt   'echo -n "mmc@4021000 status: "; cat /proc/device-tree/soc/mmc@4021000/status 2>&1; echo; ls /proc/device-tree/ | grep -iE "wifi|vcc"'
grab 07-wireless.txt     'ls /sys/class/ieee80211/ 2>&1; echo; iw dev 2>&1; echo; iw phy 2>&1 | head -60'
grab 08-link.txt         'for i in $(iw dev 2>/dev/null | awk "/Interface/ {print \$2}"); do echo "== $i"; iw dev $i link; echo "-- station dump:"; iw dev $i station dump; echo "-- iwinfo:"; iwinfo $i info; done'
grab 09-network.txt      'ip -br link; echo; ip -br addr; echo; ip route; echo; bridge vlan show 2>&1'
grab 10-services.txt     'ls /etc/rc.d/ | grep ^S; echo; netstat -tlnp 2>/dev/null | head -25'
grab 11-config.txt       "{ uci show network; uci show firewall | head -40; uci show dhcp | head -30; uci show wireless 2>/dev/null; } | $MASK"
grab 12-storage.txt      'df -h; echo; cat /proc/partitions'
grab 13-fw-info.txt      'dmesg | grep -iE "sprdwl|wcn|uwe|chip_model|fw_capa|mmc1"; echo; ls -la /lib/firmware/uwe5622/ 2>&1'
grab 14-countrycode.txt  'uci show wireless | grep "\.country="; for f in /var/run/hostapd-phy*.conf; do echo "== $f"; grep -E "^country_code|^ieee80211d|^ieee80211h" "$f"; done; iw reg get; dmesg | grep -iE "reg_notify|RegDomain|wrong country|Set as default"; for p in $(ls /sys/class/ieee80211/); do echo "== $p"; iw phy $p channels | grep -E "MHz|Maximum TX"; done'
grab 15-versions.txt     'apk info -v 2>/dev/null | grep -E "uwe5622|opiz3|footstrap|wpad|hostapd|iwinfo|kernel" ; echo; ls -la /etc/init.d/opiz3-emac /lib/uwe5622.sh 2>&1'
grab 16-events.txt       'logread | grep -E "uwe5622|WCN Assert|loopcheck|opiz3|EMAC|watchdog|sprdwl: lc" | tail -200'

echo
echo ">> done: $(ls "$OUT" | wc -l | tr -d ' ') files in $OUT/"
echo ">> quick check:"
grep -h "kmod-uwe5622" "$OUT/15-versions.txt" 2>/dev/null || echo "   ! kmod-uwe5622 not installed"
grep -h "chip_model" "$OUT/13-fw-info.txt" 2>/dev/null || echo "   ! chip_model not found (the chip has not been probed yet)"
grep -h "MemTotal" "$OUT/04-meminfo.txt" 2>/dev/null
n=$(grep -c "WCN Assert" "$OUT/02-logread.txt" 2>/dev/null || true)
echo "   firmware asserts in this boot: ${n:-0}"
if [ -s "$OUT/08-link.txt" ] && grep -q "station dump" "$OUT/08-link.txt"; then
	n=$(grep -c "^Station" "$OUT/08-link.txt" || true)
	echo "   stations in station dump: ${n:-0}"
fi

echo
echo ">> archiving..."
ARCHIVE="${OUT}.tar.gz"
if tar czf "$ARCHIVE" -C /tmp "$(basename "$OUT")"; then
	echo ">> archive ready: $ARCHIVE"
	echo ">> fetch it with:  scp -O root@<board-ip>:$ARCHIVE ."
	echo "   (-O: OpenWrt has no SFTP server, newer scp needs the old protocol)"
else
	echo "   ! tar failed, the files are still in $OUT/"
fi
