# Porting notes: Orange Pi Zero 3 / UWE5622

## Baseline

Target: OpenWrt 25.12.x, sunxi/cortexa53, Linux 6.12.

Driver source is pinned to Armbian UWE5622 commit
`cc2835a3f935d5297e03cdce464c1785381a7b4d`.

The transport and WLAN modules are kept external to the kernel tree:

- `uwe5622_bsp_sdio.ko`
- `sprdwl_ng.ko`

OpenWrt's cfg80211 headers come from mac80211 backports, so kernel-version
tests in the vendor driver are not sufficient to select cfg80211 callback
prototypes. Patches 010 and 080 deliberately key off
`OPENWRT_CFG80211_BACKPORT`.

## Patches still carried

- 010: OpenWrt cfg80211 backport prototype for `change_beacon`
- 020: external Kbuild bind-verification symbol
- 030: cfg80211-aware netdev registration/unregistration
- 060: associated-station enumeration / `dump_station`
- 080: OpenWrt cfg80211 backport prototype for `set_wiphy_params`
- 090: channel reporting and additional station fields

The old reconnect/roam, power-save and VLA patches are not carried: their
equivalents are already in the pinned Armbian source.

## 5 GHz / VHT

The current driver exposes a 5 GHz band when firmware reports
`SPRDWL_CAPA_5G`, and installs HT/VHT capabilities from firmware. The Armbian
board firmware contains calibration/power tables for the 5 GHz channels and
VHT80.

The AP start command sends the complete beacon to firmware. OpenWrt/hostapd's
requested channel information therefore needs to be verified on hardware with
`iw dev ... info` and over-the-air throughput; merely seeing a 5 GHz SSID is
not sufficient proof that VHT80 is active.

## Station accounting limitation

Firmware command `WIFI_CMD_GET_STATION` has no peer-MAC argument. The vendor
`.get_station` callback therefore returns radio/interface-level rate/signal
data even when cfg80211 asks about a particular AP client.

Patch 060 fixes enumeration, so `iw dev <ap> station dump` and LuCI can list
associated MAC addresses. Per-client RSSI/rate must not be presented as
authoritative until a firmware command/event carrying per-peer metrics is
identified.

The station event provides MAC + association IE. The STA-LUT event additionally
provides LUT index and HT/VHT flags, but no RSSI/rate.

Per-client RSSI/rate accuracy is explicitly not a release blocker. The first
goal is stable AP operation plus reliable associated-client enumeration.

## Power saving

The current Armbian driver has a `disable_powersave=1` module parameter.
For this OpenWrt AP port, firmware power saving is disabled by default:
`sprdwl_ng disable_powersave=1`.

Stability is the priority. The extra power draw is accepted to avoid the known
risk of broadcast/multicast loss affecting ARP, IPv6 ND and mDNS. Hardware
testing still verifies these protocols explicitly.

## Hardware acceptance

Initial non-DFS test target:

- AP on channel 36/40/44/48
- VHT80
- WPA2-PSK
- two or more associated clients
- `iw dev <ap> station dump` lists associated client MAC addresses
- LuCI/iwinfo shows the associated clients; per-client RSSI/rate is best-effort
- repeated `wifi reload`, client reconnect, and cold boot
- sustained iperf3 from wired Ethernet to Wi-Fi
- multicast/mDNS/IPv6 ND sanity checks
- 12+ hour traffic stability before calling the driver usable

Throughput is measured with local iperf3, not an Internet speed test.
