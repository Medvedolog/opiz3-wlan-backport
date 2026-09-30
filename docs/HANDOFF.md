# Orange Pi Zero 3 WLAN Backport — HANDOFF

Date: 2026-09-30  
Repository: `Medvedolog/opiz3-wlan-backport`  
Working branch: `dev/owrt-25.12-uwe5622-current`

## 1. Goal

Make the onboard AW859A / UNISOC UWE5622 Wi-Fi on Orange Pi Zero 3 behave like a normal OpenWrt radio on OpenWrt 25.12.x / Linux 6.12.

Primary release target:

```
OpenWrt 25.12.5
sunxi/cortexa53
xunlong_orangepi-zero3
```

The goal is stable AP/STA operation, not merely a loadable vendor driver.

## 2. Current branch/head

Current head at this handoff:

```
618c9ffc5c9878f6e2040f81a0ae3420caea1391
ci: drop nonexistent ip-neighbor package
```

Do not assume a later run/commit result without checking GitHub.

## 3. Pinned source

Driver:

```
armbian/uwe5622
cc2835a3f935d5297e03cdce464c1785381a7b4d
```

Driver source hash:

```
8ca548db6885ccdbaebe4f1f0089dda485377b36ea7ce20fb3e70bfdcfd935d5
```

Firmware source commit:

```
612bc7cc0e3539ea89c659049b7d8432e2de8ed7
```

Firmware files:

```
wcnmodem.bin
wifi_2355b001_1ant.ini
```

## 4. Main package structure

```
package/kernel/uwe5622/
package/firmware/uwe5622-firmware/
```

Kernel modules:

```
uwe5622_bsp_sdio.ko
sprdwl_ng.ko
```

Relevant docs:

```
docs/TECHNICAL-SPEC.md
docs/PORTING-NOTES.md
docs/HANDOFF.md
```

## 5. Current patches

```
010-openwrt-cfg80211-backport-api.patch
020-enable-external-kbuild-config-symbols.patch
030-fix-cfg80211-netdev-locking.patch
060-unisocwifi-implement-dump-station.patch
070-unisocwifi-fix-remaining-vlas.patch
080-cfg80211-set-wiphy-params-backport-radio-idx.patch
090-unisocwifi-implement-get-channel-and-station-details.patch
```

Important: old reconnect/roam, power-save and other patches whose logic already exists upstream in the pinned Armbian source were deliberately removed. Do not re-add them without proving a regression.

## 6. OpenWrt cfg80211 issue

Do not use Linux kernel version alone to choose vendor cfg80211 callback prototypes.

OpenWrt uses mac80211/cfg80211 backports.

Current build explicitly uses:

```
-DOPENWRT_CFG80211_BACKPORT
```

and backport headers from OpenWrt's staged mac80211 package.

This affects at least:

- beacon callback API;
- `set_wiphy_params`;
- channel callbacks.

## 7. Boot-hang safety rule

This is critical.

Early automatic module loading was observed to risk wedging boot during SDIO probe.

Therefore the package has no normal KernelPackage AutoLoad.

Instead:

```
/etc/init.d/sprdwl-delay
```

loads Wi-Fi after the rest of boot/network has progressed.

Current module policy includes:

```
modprobe sprdwl_ng disable_powersave=1
```

Never "simplify" this back to early autoload without real hardware evidence.

If Wi-Fi fails, Ethernet must remain usable.

## 8. Device tree

Patch:

```
target/linux/sunxi/patches-6.12/900-arm64-dts-h616-add-wifi-orangepi-zero2-zero3.patch
```

Adds/enables:

- 3.3 V Wi-Fi rail;
- 1.8 V IO rail;
- 32 kHz clock;
- PG18 reset;
- mmc-pwrseq;
- mmc1 SDIO;
- 4-bit bus;
- 1.8 V DDR;
- non-removable device.

Full-image CI decompiles the built DTB and checks the resulting mmc1 node.

## 9. Station handling

Patch 060 implements associated station enumeration so:

```
iw dev <ap> station dump
```

can list associated MAC addresses and LuCI/iwinfo can show clients.

Firmware limitation remains:

`WIFI_CMD_GET_STATION` has no peer-MAC argument.

Therefore per-client RSSI/rate may not be authoritative.

Release policy:

- client enumeration: required;
- perfect per-client RSSI/rate: not required for first usable baseline.

## 10. Channel reporting

Patch 090 and related compatibility work are intended to make OpenWrt channel reporting useful.

Validate on hardware with:

```
iw dev <ifname> info
iw phy
```

Do not infer VHT80 only from a visible 5 GHz SSID.

## 11. Power saving

Current default:

```
disable_powersave=1
```

Keep it this way for stability testing.

Power saving can be revisited only after multicast/broadcast, reconnect and long-run stability are proven.

## 12. Build workflows

### Fast package build

```
.github/workflows/build-packages.yml
```

Uses official OpenWrt 25.12.5 SDK and pulls the matching mac80211 source tree.

Purpose: faster compile iteration for UWE5622/firmware.

### Full image

```
.github/workflows/build-image.yml
```

Clones official OpenWrt `v25.12.5`, applies overlay, stages Footstrap, builds a complete Orange Pi Zero 3 image and validates artifacts.

Full-image build is the stronger signal.

## 13. Current CI state at handoff

Full image workflow:

```
Build test image (OpenWrt 25.12.5) #7
run id: 36739712280
head: 618c9ffc
state at handoff: IN PROGRESS
```

Already passed:

- checkout;
- dependency installation;
- OpenWrt clone;
- WLAN overlay application;
- Footstrap staging;
- feed update;
- package/image config preflight;
- source download.

At handoff it was running the full image compile step.

Do not report it as successful until the run completes.

Previous full-image run #6 failed only at image configuration preflight because the requested package `ip-neighbor` does not exist in the selected OpenWrt feed.

That was fixed by:

```
618c9ffc ci: drop nonexistent ip-neighbor package
```

## 14. Image additions made today

The 512 MiB rootfs development image now includes:

- LuCI + SSL;
- Bootstrap + Footstrap;
- UWE5622 driver/firmware;
- wireless-regdb/iw/iwinfo/wpad;
- ModemManager;
- QMI/MBIM/NCM tooling;
- USB serial modem drivers;
- USB WWAN network drivers;
- common USB Ethernet adapters;
- diagnostics tools;
- iperf3/htop.

The image is intentionally a broad development gateway/testbed, not a minimal production image.

## 15. Modem-ready package stack

The current image workflow requests:

```
modemmanager
uqmi
umbim
usb-modeswitch
comgt
comgt-ncm
luci-proto-qmi
luci-proto-mbim
luci-proto-ncm
luci-proto-modemmanager
```

plus USB serial/net drivers and diagnostics.

This is intended to support future `medvemodem` testing on the same OPi Zero 3 image.

Do not couple WLAN correctness to MedveModem. They are separate projects.

## 16. Hardware validation sequence

Once a full image build is green:

1. flash image;
2. verify Ethernet/SSH/LuCI before Wi-Fi load;
3. capture `scripts/collect-debug.sh` output;
4. confirm SDIO device exists;
5. confirm `uwe5622_bsp_sdio` loads;
6. confirm firmware loads;
7. confirm `sprdwl_ng` loads;
8. confirm phy appears;
9. confirm wlan interface appears;
10. test 2.4 GHz AP;
11. test 5 GHz channel 36/40/44/48;
12. verify VHT80;
13. verify `station dump`;
14. verify LuCI client list;
15. test STA mode;
16. test repeated `wifi reload`;
17. test reconnect/cold boot;
18. test ARP/mDNS/IPv6 ND;
19. run sustained wired<->Wi-Fi iperf3;
20. run 12+ hour stability test.

## 17. Debug collector

Run from another machine:

```
sh scripts/collect-debug.sh <router-ip>
```

It collects board, kernel, SDIO, DT, module, Wi-Fi, network and configuration evidence while redacting Wi-Fi secrets.

Use it before making speculative driver changes.

## 18. First release criteria

Do not block first usable WLAN baseline on perfect vendor metrics.

Required:

- safe boot;
- phy/wlan present;
- AP 2.4 GHz;
- AP 5 GHz non-DFS;
- STA operation;
- associated-client enumeration;
- channel reporting;
- reload/reconnect stability;
- multicast/basic LAN health;
- sustained traffic;
- 12+ hour stability.

Not required initially:

- perfect per-client RSSI/rate;
- DFS;
- Bluetooth;
- maximum theoretical speed;
- optimized power saving.

## 19. Development discipline

- stay on dev/topic branches;
- no merge to main without explicit request;
- no tag/release without explicit request;
- no source fixes directly in `build_dir`;
- keep driver/firmware pinned;
- preserve license/provenance;
- keep Ethernet-safe delayed loading;
- validate built DTB and symbols;
- never claim a CI build passed without checking it;
- prioritize stable AP/client enumeration over cosmetic metrics.

## 20. Next action

First check whether run #7 finished.

If green:

- record the successful commit/run in this handoff;
- download/flash the image;
- begin hardware validation using the sequence above.

If it failed:

- inspect the first real build/validation error;
- fix only that concrete failure in the dev branch;
- do not redesign unrelated WLAN logic.
