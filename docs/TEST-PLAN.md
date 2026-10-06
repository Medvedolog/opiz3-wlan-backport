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
