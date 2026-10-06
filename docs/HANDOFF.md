# Orange Pi Zero 3 WLAN / UWE5622 — HANDOFF

> **Historical snapshot (2026-09-30).** Branch names, the repository path and
> the patch list below describe the state at that date. The current state is
> in the [README](../README.md); the firmware findings since then are in
> [WCNMODEM-REVERSE-ENGINEERING.md](WCNMODEM-REVERSE-ENGINEERING.md), revision 3.


Date: 2026-09-30  
Repository: `Medvedolog/opiz3-wlan-backport`  
Working branch: `dev/owrt-25.12-uwe5622-current`

## 1. Goal

Get the onboard AW859A / UNISOC UWE5622 Wi-Fi of Orange Pi Zero 3 working as a normal OpenWrt radio on OpenWrt 25.12/Linux 6.12.

Target is not just successful compilation.

Required end result:

- stable AP/STA;
- 2.4 and 5 GHz;
- cfg80211/nl80211 integration;
- hostapd/OpenWrt control;
- client MAC enumeration;
- LuCI associated-client visibility;
- correct channel reporting;
- practical 5 GHz throughput;
- long-run stability.

## 2. Current branch/head

```
branch: dev/owrt-25.12-uwe5622-current
head at 2026-09-30 snapshot:
c3a6f1315bacaaf5f20cd3b3bbe26442286fce2f
```

Do not work on main unless explicitly instructed.

## 3. Baseline

```
OpenWrt 25.12.x
CI image release: 25.12.5
target: sunxi/cortexa53
profile: xunlong_orangepi-zero3
kernel: 6.12
```

Driver source pinned to:

```
armbian/uwe5622
cc2835a3f935d5297e03cdce464c1785381a7b4d
```

Source hash is pinned in the package Makefile.

## 4. Current repository structure

Important files:

```
package/kernel/uwe5622/
package/firmware/uwe5622-firmware/
target/linux/sunxi/patches-6.12/
target/linux/sunxi/image/
scripts/collect-debug.sh
.github/workflows/build-packages.yml
.github/workflows/build-image.yml
docs/PORTING-NOTES.md
docs/TECHNICAL-SPEC.md
docs/HANDOFF.md
```

## 5. Current driver adaptations

Current patch set includes:

```
010 cfg80211 backport API
020 external Kbuild symbols
030 cfg80211/netdev locking
060 dump_station / client enumeration
070 VLA cleanup
080 set_wiphy_params backport API
090 get_channel and station details
```

OpenWrt cfg80211 comes from backports, so callback ABI cannot be selected only by Linux kernel version.

The package defines:

```
OPENWRT_CFG80211_BACKPORT
```

for compatibility logic.

## 6. Station/client support

This is a major project requirement.

Current code has:

- associated-station tracking;
- `dump_station`;
- client MAC enumeration;
- additional station fields;
- channel reporting.

Required test:

```
iw dev <ap> station dump
```

must list associated MAC addresses.

LuCI/iwinfo must also show clients.

Important limitation:

Firmware `WIFI_CMD_GET_STATION` has no peer-MAC argument.

Therefore current per-client RSSI/rate cannot be considered authoritative.

Do not fake or overstate per-client statistics.

Client enumeration is a release requirement. Perfect per-client signal/rate is not.

## 7. 5 GHz goal

Driver exposes 5 GHz if firmware reports the capability and carries HT/VHT data.

Initial hardware test channels:

```
36
40
44
48
```

Do not infer VHT80 simply from a 5 GHz SSID.

Verify:

- `iw dev ... info`;
- actual channel/frequency;
- association;
- local iperf3 throughput;
- sustained operation.

Pragmatic first throughput goal is at least about 150 Mbit/s on 5 GHz if client/RF conditions permit.

Stability is more important than peak throughput.

## 8. Power saving

Current policy:

```
sprdwl_ng disable_powersave=1
```

This is intentional.

Reason: avoid multicast/broadcast/ARP/ND/mDNS instability while making the AP usable.

Do not re-enable by default until hardware testing proves it stable.

## 9. Delayed module loading

The kmod intentionally does NOT AutoLoad at the normal early boot stage.

Current loader:

```
/etc/init.d/sprdwl-delay
```

Reason:

Early SDIO probe previously had a failure mode where the board could hang before network startup, leaving the gateway unreachable.

The current safety invariant is:

> Wi-Fi failure may disable Wi-Fi, but must not take down wired manageability.

Do not remove delayed loading until repeated cold-boot tests prove early probe safe.

## 10. Device-tree requirements

The generated Zero 3 DTB must have a valid MMC1/WLAN node with:

```
status = "okay"
vmmc-supply
vqmmc-supply
mmc-pwrseq
bus-width
non-removable
mmc-ddr-1_8v
```

The full-image CI decompiles the generated DTB and checks the actual node.

## 11. Debug bundle

Use:

```
scripts/collect-debug.sh <router-ip>
```

The script collects:

- OpenWrt/board info;
- dmesg/logread;
- modules;
- SDIO;
- DT state;
- `iw`;
- station dump;
- iwinfo;
- networking/routes;
- UCI;
- firmware/probe information.

Wi-Fi credentials are redacted.

Always collect a bundle after first hardware boot before making large driver changes.

## 12. CI

### Fast package CI

```
.github/workflows/build-packages.yml
```

Builds UWE5622 kmod + firmware against OpenWrt 25.12.5 SDK.

It imports matching OpenWrt mac80211 sources because cfg80211 backport headers are required.

Validates important symbols inside `sprdwl_ng.ko`.

### Full image CI

```
.github/workflows/build-image.yml
```

Builds a complete Orange Pi Zero 3 microSD image.

Includes:

- WLAN driver/firmware;
- LuCI;
- Footstrap;
- iw/iwinfo;
- iperf3;
- modem stack;
- common USB Ethernet drivers;
- diagnostics.

It validates:

- final image exists;
- required packages are in manifest;
- driver symbols exist;
- delayed-load policy remains;
- generated DTB has required MMC1 properties.

## 13. Current full-image status at handoff

Latest completed full-image run:

```
workflow: Build test image (OpenWrt 25.12.5)
run #7
run id: 36739712280
head: 618c9ffc5c9878f6e2040f81a0ae3420caea1391
overall conclusion: failure (post-build DTB QA only)
```

The image build itself completed successfully.

Confirmed by the final manifest/validation before the DTB check:

- ext4 and squashfs Orange Pi Zero 3 images were generated;
- UWE5622 kmod and firmware are present;
- LuCI and Footstrap are present;
- the complete requested modem/QMI/MBIM/NCM/USB serial stack is present;
- common USB Ethernet drivers are present;
- diagnostics packages are present;
- `sprdwl_cfg80211_dump_station`, `sprdwl_add_assoc_sta`,
  `sprdwl_cfg80211_get_channel` and `disable_powersave` symbols are present;
- delayed-load policy check passed.

Generated compressed image sizes in run #7 were approximately:

```
ext4-sdcard.img.gz      19 MiB
squashfs-sdcard.img.gz 15 MiB
```

Artifact was uploaded successfully:

```
artifact id: 11117250580
artifact name: opiz3-openwrt-25.12.5-uwe5622-test
artifact size: 33968727 bytes
artifact sha256: ccdb9cbc87878224335a4c6e2624894b6e89842a03a2019e5ebb44789b9af445
```

The red workflow result does **not** indicate a compile or image-generation
failure.

The failure occurred only in the final generated-DTB QA. Inspection of the
saved artifact showed `mmc1-node.dts` was empty. The generated-DTS extractor
used incorrect brace escaping in its awk expressions, so it failed to select
the `mmc@4021000` node before any property validation took place.

This CI parser bug was fixed after run #7 in commit:

```
c3a6f1315bacaaf5f20cd3b3bbe26442286fce2f
ci: fix DTB node brace parsing
```

The fix changes only post-build DTB validation. No driver, DTS patch, package
selection or image content was changed by that commit.

Therefore:

- run #7 images are valid build artifacts and are suitable for hardware testing;
- run #7 does **not** constitute a completed DTB acceptance check;
- the corrected DTB QA must pass on the next substantive full-image build;
- do not trigger a full rebuild solely to turn this historical CI run green.

## 14. Test image package set

The development image intentionally contains a broad test stack.

WLAN:

```
kmod-uwe5622
uwe5622-firmware
wireless-regdb
iw
iwinfo
wpad-basic-mbedtls
luci
luci-ssl
luci-theme-footstrap
luci-theme-bootstrap
iperf3
htop
```

Cellular/modem stack includes MM/QMI/MBIM/NCM/serial/tethering support.

USB Ethernet includes common Realtek, ASIX, SMSC, LAN78xx, DM9601 and SR9700 families where packages exist.

This is a development image, not a minimal production image.

## 15. Hardware acceptance plan

After obtaining a microSD image:

1. boot with Ethernet connected;
2. confirm board remains reachable;
3. collect debug bundle;
4. confirm SDIO device;
5. confirm transport module;
6. confirm `sprdwl_ng`;
7. confirm firmware;
8. confirm wlan phy/interface;
9. configure 2.4 GHz AP;
10. connect client;
11. verify station dump;
12. configure 5 GHz channel 36/40/44/48;
13. connect at least two clients;
14. verify LuCI/iwinfo client list;
15. run Ethernet-to-WLAN iperf3;
16. repeat `wifi reload`;
17. repeat client reconnect;
18. test DHCP/ARP/mDNS/IPv6 ND/multicast;
19. reboot repeatedly;
20. run 12+ hour stability test.

## 16. Important non-goals / do not regress

Do not:

- move fixes into `build_dir`;
- depend on vendor custom userspace for normal AP operation;
- reintroduce early module AutoLoad without proof;
- re-enable power save by default;
- report fake per-client RSSI/rate;
- call visible SSID proof of a working 5 GHz/VHT path;
- call successful compile proof of hardware support;
- merge/tag/release without explicit instruction.

## 17. Immediate next action

Use the run #7 image for the first hardware acceptance pass:

- download and flash the preferred `.img.gz`;
- boot on real OPi Zero 3 with wired management available;
- collect the debug bundle before large driver changes;
- verify SDIO, firmware and delayed UWE5622 module loading;
- test 2.4 GHz and 5 GHz AP/STA behavior;
- verify station enumeration in `iw`, iwinfo and LuCI;
- measure local Ethernet-to-WLAN throughput;
- exercise reload/reconnect/reboot behavior;
- proceed toward the 12+ hour stability test.

On the next substantive full-image CI run, confirm that the corrected generated
DTB QA passes. Do not spend a full rebuild only to revalidate the historical
run #7 CI parser failure.

## 18. Success definition

The first usable milestone is:

```
OpenWrt 25.12 boots from microSD
-> wired management remains safe
-> UWE5622 loads
-> 5 GHz AP works
-> associated clients are visible in iw/LuCI
-> sustained local throughput >= ~150 Mbit/s where conditions allow
-> repeated reload/reconnect does not destabilize the board
```

Final confidence requires long-run testing, not a one-shot association.
