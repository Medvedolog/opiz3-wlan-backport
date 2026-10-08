# Hardware test plan

What to check on a board before a release, with the commands. Send the
output (or a screenshot) for every item; "works" without output does not
count. `. /lib/uwe5622.sh` gives `uwe_phy` and `uwe_radios` (the onboard
radio is not always phy0/radio0).

## Beta 1 (r14 and later)

| # | Area | How | Expected |
|---|---|---|---|
| 1 | First boot of a fresh image | flash, boot, wait 1 min, join `OPiZ3` (`12345678test`), open LuCI | AP up on 5 GHz ch 36 VHT80 (r18+); Board panel warns about the default password until it is changed |
| 2 | `wifi up` log | `logread \| grep -E "\-95\|\-12\|mixed HW"` after `wifi` | nothing (patch 280) |
| 3 | phy MAC, name | `. /lib/uwe5622.sh; cat /sys/class/ieee80211/$(uwe_phy)/macaddress; iwinfo \| head -3` | a real MAC; "Unisoc UWE5622" |
| 4 | Board panel | LuCI Status → Overview, "Board" | temperatures, CPU, driver, firmware version, SDIO 50 MHz |
| 5 | CPU frequency | LuCI System → CPU frequency; `cat /sys/devices/system/cpu/cpufreq/policy0/scaling_{governor,cur_freq}` | `ondemand`, ~480 MHz idle; a change applies |
| 6 | Per-client counters | `iw dev $(iw dev \| awk '/Interface/{print $2; exit}') station dump` | rx/tx bytes and packets grow |
| 7 | Per-client TX rate | `echo cp_txrate=1 >> /etc/uwe5622.options; reboot`; station dump; Board panel | tx bitrate close to the phone's link rate; firmware width per client |
| 8 | Recovery | `uwe5622-recover; logread -e uwe5622` | "Wi-Fi recovered", clients reconnect |
| 9 | Recovery with a USB Wi-Fi adapter plugged in at boot | `. /lib/uwe5622.sh; uwe_phy; uwe_radios; uwe_mmc_host`, then item 8 | UWE5622 found as phy1/radio1 if so; only it is restarted |
| 10 | Load | `iperf3 -s` on the board, a client runs `iperf3 -c <board> -t 600 -P 4`, repeat for a few hours | no assert (`logread \| grep -i assert` empty) |
| 11 | Upgrade without reflashing | from r10: `apk update && apk upgrade && apk add luci-app-opiz3-status && reboot` | everything above, settings kept |

## Client (STA) mode: the board takes its uplink over Wi-Fi

Use case: a cottage or a phone hotspot as the internet source. Not tested
in this project yet.

| # | Case | How | Look at |
|---|---|---|---|
| S1 | STA alone | LuCI Network → Wireless → Scan → Join network (creates `wwan`, zone `wan`) | connects, gets DHCP, internet works |
| S2 | Signal and rate | `iw dev <sta-if> link; iw dev <sta-if> station dump` | in STA mode the firmware may report signal and rates (unlike AP mode): record what is real |
| S3 | Speed | `iperf3 -c <host behind the uplink AP>` and the reverse `-R` | compare with AP mode (~160 Mbit/s) |
| S4 | Reconnect | reboot the uplink AP, or walk out of range and back | reconnects by itself; time to reconnect |
| S5 | AP + STA together (repeater) | keep our AP, add the STA interface on the **same radio**; the AP must use the uplink's channel | both up? `logread` for assert; does the AP follow the STA channel |
| S6 | 2.4 vs 5 GHz uplink | S1–S3 with the uplink AP on each band | differences, asserts |

CLI for S1, if LuCI is not at hand (radio from `uwe_radios`):

```sh
. /lib/uwe5622.sh; R=$(uwe_radios)
uci set network.wwan=interface
uci set network.wwan.proto=dhcp
uci add_list firewall.@zone[1].network=wwan     # zone[1] is "wan" on a default config
uci set wireless.wwan=wifi-iface
uci set wireless.wwan.device=$R
uci set wireless.wwan.mode=sta
uci set wireless.wwan.network=wwan
uci set wireless.wwan.ssid='UPLINK-SSID'
uci set wireless.wwan.encryption=psk2
uci set wireless.wwan.key='UPLINK-PASSWORD'
uci commit; /etc/init.d/firewall reload; wifi
```

### Travelmate (in the image from r15)

`travelmate` + `luci-app-travelmate` (LuCI Services → Travelmate) pick an
uplink from a list of known networks, reconnect, and can log into captive
portals. Off until enabled. With one radio it is the S5 case: the STA
scans and moves channels while our AP runs on the same radio.

| # | Case | Look at |
|---|---|---|
| T1 | Scan from LuCI Travelmate (AP running) | scan results appear; no assert; AP clients stay or come back |
| T2 | Two known uplinks, switch off the active one | Travelmate moves to the other; time; AP follows the channel |
| T3 | Uplink on a blocked channel (DFS 52–144, or 80 MHz where `max_bw_5g` forbids it) | fails cleanly (log line), no firmware assert |
| T4 | Captive portal (hotel/cafe hotspot), if available | login page reachable through LuCI |

For S5 the vendor driver has single-channel AP+STA support
(`STA_SOFTAP_SCC_MODE`); whether this firmware and our patches handle it is
exactly what the test shows.

## r19 test build (beta 2 candidate)

**S5 repeater (patch 290, per-interface MAC).** AP `OPiZ3` running, add a
client interface on the same radio (LuCI → Network → Wireless → Scan →
Join network, or Travelmate), uplink on 2.4 GHz.

```sh
iw dev | grep -E "Interface|addr|type|channel"   # two different addr
logread | grep -iE "setting MAC|sprdwl_set_mac|assert" | tail
```

Then a phone joins `OPiZ3`: gets an IP, has internet through the uplink.
Expected: the AP moves to the uplink's channel (single radio).

**Per-client signal (patch 300, `wifi_ram`).** AP with one phone, traffic
running on it:

```sh
sh wifi-ram-diff.sh grab near1     # phone next to the board
sh wifi-ram-diff.sh grab far       # phone in another room
sh wifi-ram-diff.sh grab near2     # next to the board again
sh wifi-ram-diff.sh diff
grep lut-peer /sys/kernel/debug/sprdwl_debug/cp_sta_table
```

Send the output of `grab` (ACK RSSI per LUT) and `diff`, plus the phone's
own signal reading for each position.

If `grab` fails with "Resource temporarily unavailable", the power check
refused (r19 test image, 2026-10-07): `dmesg | grep wifi_ram` shows the
CHIP_SLP value (from r20). `echo 1 > /sys/module/sprdwl_ng/parameters/wifi_ram_force`
reads without the check; if that read fails, the Wi-Fi stops and
uwe5622-recover brings it back in ~14 s.

## Repeater stress test (r23, Zero 3, 2026-10-08)

AP `OPiZ3` and a client to a phone hotspot on one radio, 2.4 GHz, a loop of
`wifi` every 40–60 s (each `wifi` tears down and recreates both
interfaces). UART console attached.

| Run | Result |
|---|---|
| AP + client, 10 cycles | board reset on cycle 10, while the interfaces were being recreated; nothing in the log |
| AP only, 20 cycles | clean |
| AP + client, ~8 cycles | one firmware assert (`WCN Assert in rf_marlin.c line 1016, pri20_offset == NO_OFFSET`) while a connected client was torn down; `uwe5622-recover` brought Wi-Fi back as phy1 in ~13 s; cfg80211 `WARNING` (core.c:1321) on the driver unload, no oops |
| AP + client, hardware watchdog stopped | hard hang on cycle 2, ~2 s after the AP came up (client associating): no kernel output on UART, magic SysRq over UART break did not answer |
| AP + client, station started 3 s after the AP (test patch of wpa_supplicant.uc) | board froze in cycle 4 right after the AP was torn down (`phy0-ap0: left promiscuous mode`, then nothing): the hang is in the teardown of the connected station, not in creating the interfaces; the delay is removed again (r26) |

The hard hang leaves no trace: the kernel has no soft/hard lockup detector
(`/proc/sys/kernel/watchdog*` absent) and the CPUs stop answering the UART,
which points at a bus-level stall (SDIO/MMIO access to the chip) rather than
a software deadlock. With the hardware watchdog running (default) the board
resets after ~16 s.

Both the firmware assert and this hang come right after the teardown of a
*connected* station starts (deauth, then the interface is deleted while the
firmware is still handling it). Next: disconnect the station and wait for
the firmware's disconnect event before deleting the interface. After one
watchdog reset the Ethernet failed to probe (`EMAC reset timeout`, -110)
until a power cycle.

## Orange Pi Zero 2W, test image (r22, 2026-10-07)

A tester's debug archive, ext4 image, 1 GB board:

- boots (OpenWrt's `xunlong_orangepi-zero2w` profile, our U-Boot build);
- `mmc1: new high speed SDIO card at address 8800`, chip id `0x2355b001`,
  firmware `MARLIN3_19B_W21.05.3`, CP ready: the Wi-Fi nodes added by
  `zero3-dtb-add-wifi.py` are right for this board;
- `phy0-ap0` AP `OPiZ3`, 5 GHz channel 44, VHT80, `AP-ENABLED` 34 s after
  boot; a client joined; no assert in the log;
- first boot: the tester reports that `OPiZ3` came up by itself after
  flashing (the archive is from a later boot: channel 44 set by hand, no
  first-boot log line), so the first-boot AP fix is confirmed by report;
- not covered: 1.5 GB variant, STA mode, recovery.

## Results 2026-10-06 (Zero 3, r15 image with r16/r17 fixes) → beta 1

| # | Result |
|---|---|
| 1 | ✅ AP off after flashing (stock OpenWrt), driver up, no `-95` |
| 2 | ✅ (after r16: no `radio0 (Not found)` on first boot) |
| 3 | ✅ real MAC; "Unisoc UWE5622" in LuCI and CLI |
| 4 | ✅ temperatures ~45–55 °C, SDIO 50 MHz 4-bit, firmware version |
| 5 | ✅ `ondemand` 480 MHz idle; governor/limits apply. Max 1416 MHz on this chip (speed bin) |
| 6 | ✅ bytes/packets grow per client |
| 7 | ✅ 433.3 Mbit/s VHT-MCS 9 80 MHz SGI, live (292.5 MCS 7 at another moment) |
| 8 | ✅ r15 script: ~80 s (driver reload never works, RE §61); r16 script: 13.5 s |
| 9 | ✅ radio found as phy2/phy4 after recoveries |
| 10 | ✅ VHT80, 1 h 14 min, two clients, moderate load, no assert, ~54 °C |
| S1 | ✅ 2.4 GHz phone hotspot, DHCP, internet |
| S2 | ✅ STA mode reports signal (−27 dBm) and rate |
| S4 | ✅ reconnect ~35 s after the uplink returns |
| S5 | ❌ AP and STA share one MAC, clients cannot join (beta 2) |
| T1 | ✅ scan while the AP runs, no client drop |
| — | LTE (QMI) uplink with Wi-Fi clients ✅ after adding `modem` to the wan zone (image does it from r17) |
| — | LuCI width change with `max_bw_5g=20` left the AP down (fixed in r17 by clamping on every apply) |
