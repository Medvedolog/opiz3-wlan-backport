#!/bin/sh
# Look for a per-client signal value in the UWE5622 Wi-Fi RAM tables.
#
# Run on the board (needs patch 300, /sys/kernel/debug/sprdwl_debug/wifi_ram;
# layout in docs/WCNMODEM-REVERSE-ENGINEERING.md §63.2):
#
#   sh wifi-ram-diff.sh grab near1   # client near the board (-20..-35 dBm)
#   sh wifi-ram-diff.sh grab far     # client in another room (-60..-80 dBm)
#   sh wifi-ram-diff.sh grab near2   # client near again
#   sh wifi-ram-diff.sh diff         # print candidates
#   sh wifi-ram-diff.sh stats NAME   # ACK RSSI sum/count per LUT of one grab
#
# Keep traffic running from the client during each grab (video, iperf3).
# Each grab takes 5 reads one second apart. A candidate is a byte that is
# the same within each grab's reads +-3, close between near1 and near2, and
# at least 10 away from them in far. Offsets are mapped to table/LUT/field.
# Send the output of diff and stats (not the dumps). The client's LUT is in
# /sys/kernel/debug/sprdwl_debug/cp_sta_table ("lut-peer").

DIR=/tmp/wifiram
SRC=/sys/kernel/debug/sprdwl_debug/wifi_ram
N=5

where() {
	# offset -> region lut field (awk)
	awk '
	function m(o) {
		if (o < 3200) return sprintf("sta   lut %2d +0x%02x", int(o / 100), o % 100)
		if (o < 5760) { t = int((o - 3200) / 512); r = (o - 3200) % 512
			return sprintf("tbl%d  lut %2d +0x%02x", t, int(r / 16), r % 16) }
		r = o - 5760
		return sprintf("txst  lut %2d +0x%02x", int(r / 72), r % 72)
	}
	{ printf "0x%04x %s %s\n", $1, m($1), substr($0, index($0, $2)) }'
}

case "$1" in
grab)
	[ -n "$2" ] || { echo "usage: $0 grab NAME"; exit 1; }
	[ -r "$SRC" ] || { echo "$SRC missing (needs patch 300)"; exit 1; }
	mkdir -p "$DIR"
	i=1
	while [ $i -le $N ]; do
		cat "$SRC" > "$DIR/$2.$i.bin" || { echo "read failed"; exit 1; }
		[ $i -lt $N ] && sleep 1
		i=$((i + 1))
	done
	ls -l "$DIR/$2".*.bin | tail -1
	sh "$0" stats "$2"
	;;
stats)
	[ -s "$DIR/$2.1.bin" ] || { echo "missing $DIR/$2.1.bin"; exit 1; }
	# per-LUT TX statistics at 0x1680 + lut*0x48: s32 sum +0x40, u16 count +0x44
	for f in "$DIR/$2".*.bin; do
		l=0
		while [ $l -lt 32 ]; do
			o=$((5760 + l * 72 + 64))
			s=$(od -An -td4 -j $o -N4 "$f" | tr -d ' ')
			c=$(od -An -tu2 -j $((o + 4)) -N2 "$f" | tr -d ' ')
			[ "$s" != 0 ] || [ "$c" != 0 ] &&
				echo "$(basename "$f") lut $l sum $s count $c" \
				     "avg $([ "$c" -gt 0 ] && echo $((s / c)) || echo -)"
			l=$((l + 1))
		done
	done
	;;
diff)
	command -v paste >/dev/null || { echo "paste missing: apk add coreutils-paste"; exit 1; }
	for n in near1 far near2; do
		[ -s "$DIR/$n.1.bin" ] || { echo "missing $DIR/$n.1.bin"; exit 1; }
		i=1
		while [ $i -le $N ]; do
			od -An -v -tu1 -w1 "$DIR/$n.$i.bin" > "$DIR/$n.$i.txt"
			i=$((i + 1))
		done
		# per byte: min and max over the grab's reads
		paste "$DIR/$n".*.txt | awk '{ lo = hi = $1
			for (i = 2; i <= NF; i++) { if ($i < lo) lo = $i; if ($i > hi) hi = $i }
			print lo, hi }' > "$DIR/$n.mm"
	done
	paste -d' ' "$DIR/near1.mm" "$DIR/far.mm" "$DIR/near2.mm" | awk '
	function s8(v) { return v > 127 ? v - 256 : v }
	{
		off = NR - 1
		if ($2 - $1 > 3 || $4 - $3 > 3 || $6 - $5 > 3) next
		a = $1; f = $3; b = $5
		d = a - b; if (d < 0) d = -d
		x = a - f; if (x < 0) x = -x
		y = b - f; if (y < 0) y = -y
		if (d <= 6 && x >= 10 && y >= 10) {
			printf "%d near1 %3d(%4d) far %3d(%4d) near2 %3d(%4d)\n",
			       off, a, s8(a), f, s8(f), b, s8(b)
			n++
		}
	}
	END { if (!n) print "no candidates" > "/dev/stderr" }' | where
	rm -f "$DIR"/*.txt "$DIR"/*.mm
	;;
*)
	sed -n '2,20p' "$0"
	;;
esac
