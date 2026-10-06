#!/bin/sh
# Look for a per-client signal value in the UWE5622 firmware memory.
#
# Run on the board (needs patch 260, /sys/kernel/debug/sprdwl_debug/cp_mem):
#
#   sh cp-mem-diff.sh grab near1     # client near the board (-20..-35 dBm)
#   sh cp-mem-diff.sh grab far       # client in another room (-60..-80 dBm)
#   sh cp-mem-diff.sh grab near2     # client near again
#   sh cp-mem-diff.sh diff           # print candidates
#
# Keep some traffic running from the client during each grab (video, iperf3).
# A candidate is a byte that, read as signed, is in -50..-10 in both "near"
# dumps (and close between them) and at least 15 lower, in -100..-45, in the
# "far" dump. Output: CP address, offset into the dump, near1/far/near2.
# Send the candidate list (not the dumps).

DIR=/tmp/cpmem
SRC=/sys/kernel/debug/sprdwl_debug/cp_mem
BASE=1048576	# 0x100000

case "$1" in
grab)
	[ -n "$2" ] || { echo "usage: $0 grab NAME"; exit 1; }
	[ -r "$SRC" ] || { echo "$SRC missing (needs patch 260)"; exit 1; }
	mkdir -p "$DIR"
	cat "$SRC" > "$DIR/$2.bin" || { echo "read failed"; exit 1; }
	ls -l "$DIR/$2.bin"
	;;
diff)
	for n in near1 far near2; do
		[ -s "$DIR/$n.bin" ] || { echo "missing $DIR/$n.bin"; exit 1; }
		od -An -v -td1 -w1 "$DIR/$n.bin" > "$DIR/$n.txt"
	done
	paste "$DIR/near1.txt" "$DIR/far.txt" "$DIR/near2.txt" | awk -v base="$BASE" '
	{
		a = $1 + 0; f = $2 + 0; b = $3 + 0; off = NR - 1
		d = a - b; if (d < 0) d = -d
		if (a >= -50 && a <= -10 && b >= -50 && b <= -10 && d <= 8 &&
		    f >= -100 && f <= -45 && a - f >= 15 && b - f >= 15) {
			printf "cp 0x%06x off 0x%05x  near1 %4d  far %4d  near2 %4d\n",
			       base + off, off, a, f, b
			n++
		}
	}
	END { printf "%d candidates\n", n }'
	rm -f "$DIR"/*.txt
	;;
*)
	sed -n '2,20p' "$0"
	;;
esac
