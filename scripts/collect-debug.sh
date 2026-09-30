#!/bin/sh
# Kumpulkan bundel diagnosa dari Orange Pi Zero 3 yang menjalankan image ini.
# Dijalankan dari komputer lain (Mac/Linux), bukan di board:
#
#   sh collect-debug.sh [ip]        # default 192.168.8.1
#
# Hasil: direktori opz3-debug-<timestamp>/ berisi semua yang dibutuhkan untuk
# mendiagnosis masalah Wi-Fi, boot, maupun jaringan — siap dilampirkan ke
# issue atau dianalisis. Kunci Wi-Fi disamarkan sebelum disimpan.
set -eu

HOST="${1:-192.168.8.1}"
OUT="opz3-debug-$(date +%Y%m%d-%H%M%S)"
# IP-nya sama dengan perangkat lama, jadi host key pasti berubah. Jangan
# sentuh known_hosts utama; pakai yang sekali-pakai.
SSH="ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/opz3-test-hostkey -o ConnectTimeout=10 root@$HOST"

mkdir -p "$OUT"
echo ">> mengumpulkan dari $HOST ke $OUT/"

grab() { # grab <nama-file> <perintah di board>
	printf '  %-28s' "$1"
	if $SSH "$2" > "$OUT/$1" 2>&1; then echo ok; else echo GAGAL; fi
}

grab 00-board.txt        'ubus call system board; echo; cat /etc/openwrt_release'
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
grab 11-config.txt       'uci show network; uci show firewall | head -40; uci show dhcp | head -30; uci show wireless 2>/dev/null | sed -E "s/(key|psk)=.*/\1=<DISAMARKAN>/"'
grab 12-storage.txt      'df -h; echo; cat /proc/partitions'
grab 13-fw-info.txt      'dmesg | grep -iE "sprdwl|wcn|uwe|chip_model|fw_capa|mmc1"; echo; ls -la /lib/firmware/uwe5622/ 2>&1'

echo
echo ">> selesai: $(ls "$OUT" | wc -l | tr -d ' ') berkas di $OUT/"
echo ">> cek cepat:"
grep -h "chip_model" "$OUT/13-fw-info.txt" 2>/dev/null || echo "   ! chip_model tidak ditemukan — chip belum ter-probe"
grep -h "MemTotal" "$OUT/04-meminfo.txt" 2>/dev/null
if [ -s "$OUT/08-link.txt" ] && grep -q "station dump" "$OUT/08-link.txt"; then
	if awk '/station dump/{f=1;next} /iwinfo/{f=0} f&&NF' "$OUT/08-link.txt" | grep -q .; then
		echo "   station dump: BERISI (fix dump_station BEKERJA)"
	else
		echo "   station dump: kosong (belum terhubung, atau fix belum bekerja)"
	fi
fi
