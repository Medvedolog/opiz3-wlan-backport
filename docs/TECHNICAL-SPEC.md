# Orange Pi Zero 3 UWE5622 WLAN Backport — Technical Specification

Status: active development  
Date snapshot: 2026-09-30  
Repository: `Medvedolog/opiz3-wlan-backport`  
Primary branch: `dev/owrt-25.12-uwe5622-current`

## 1. Purpose

The project provides a reproducible OpenWrt integration for the onboard AW859A / UNISOC UWE5622 Wi-Fi module on Orange Pi Zero 3.

The target is not merely "driver loads". The target is a normal OpenWrt radio with:

- cfg80211/nl80211 integration;
- AP and STA operation;
- 2.4 GHz and 5 GHz support;
- working hostapd/wpad integration;
- associated-station enumeration visible through `iw`, iwinfo and LuCI;
- correct channel/frequency reporting;
- stable reconnect/reload behavior;
- reproducible kernel package, firmware package and full-image builds;
- failure isolation so a Wi-Fi driver problem does not make the router unreachable.

## 2. Target platform

Primary target:

```
OpenWrt: 25.12.x
Pinned image release: 25.12.5
Kernel: Linux 6.12
Target: sunxi/cortexa53
Profile: xunlong_orangepi-zero3
Board SoC: Allwinner H618
Wi-Fi module: AW859A / UNISOC UWE5622
Transport: SDIO on mmc1
```

The repository overlay must remain buildable without edits inside OpenWrt `build_dir`.

## 3. Upstream sources and pinning

Driver source:

```
https://github.com/armbian/uwe5622
commit: cc2835a3f935d5297e03cdce464c1785381a7b4d
```

Driver tarball hash:

```
8ca548db6885ccdbaebe4f1f0089dda485377b36ea7ce20fb3e70bfdcfd935d5
```

Firmware source:

```
https://github.com/armbian/firmware
commit: 612bc7cc0e3539ea89c659049b7d8432e2de8ed7
```

Firmware files currently packaged:

```
wcnmodem.bin
wifi_2355b001_1ant.ini
```

Reference integrations may be used for porting ideas, but source revisions, patches and license provenance must remain explicit.

## 4. OpenWrt package layout

The integration is split into:

```
package/kernel/uwe5622
package/firmware/uwe5622-firmware
```

Kernel package outputs:

```
uwe5622_bsp_sdio.ko
sprdwl_ng.ko
```

Firmware installs under:

```
/lib/firmware/uwe5622/
```

The package must build against OpenWrt's mac80211 backport headers, not generic in-tree cfg80211 assumptions.

## 5. cfg80211/mac80211 compatibility model

OpenWrt 25.12 uses cfg80211/mac80211 backports whose callback signatures may not match what a vendor driver would infer from `LINUX_VERSION_CODE`.

Therefore vendor-driver API selection must use an explicit OpenWrt compatibility define:

```
OPENWRT_CFG80211_BACKPORT
```

Current relevant patches:

```
010-openwrt-cfg80211-backport-api.patch
020-enable-external-kbuild-config-symbols.patch
030-fix-cfg80211-netdev-locking.patch
060-unisocwifi-implement-dump-station.patch
070-unisocwifi-fix-remaining-vlas.patch
080-cfg80211-set-wiphy-params-backport-radio-idx.patch
090-unisocwifi-implement-get-channel-and-station-details.patch
```

Do not re-add patches whose equivalent behavior already exists in the pinned Armbian source.

## 6. Device-tree requirements

The board device tree must enable the onboard UWE5622 SDIO path.

Required `mmc1` properties include:

```
vmmc-supply
vqmmc-supply
mmc-pwrseq
bus-width = <4>
non-removable
mmc-ddr-1_8v
status = "okay"
```

The overlay also provides:

- 3.3 V Wi-Fi rail;
- 1.8 V IO rail;
- `mmc-pwrseq-simple`;
- PG18 reset;
- RTC 32 kHz clock;
- post-power-on delay.

CI must validate the built DTB rather than only checking patch text.

## 7. Boot-safety invariant

Wi-Fi must not become a single point of failure for the router.

The UWE5622 modules MUST NOT be blindly autoloaded during the earliest kmodloader phase.

Observed risk: probing `uwe5622_bsp_sdio` too early can stall boot sufficiently that Ethernet is up electrically but the router becomes unreachable.

Current policy:

- no KernelPackage AutoLoad for the UWE5622 pair;
- load through `/etc/init.d/sprdwl-delay`;
- delay until core network boot has progressed;
- load `sprdwl_ng` with `disable_powersave=1`.

If the Wi-Fi driver fails to probe, Ethernet/SSH/LuCI must remain usable for diagnosis.

Any future attempt to restore early autoload requires explicit hardware evidence that boot-hang behavior is gone.

## 8. Power-save policy

Current default:

```
sprdwl_ng disable_powersave=1
```

Rationale: AP/router stability is higher priority than marginal power savings.

Known risk when vendor power saving is active includes broadcast/multicast degradation that may affect:

- ARP;
- IPv6 ND;
- mDNS;
- other multicast/broadcast control traffic.

Power saving may be reconsidered only after stability testing.

## 9. AP/STA functional requirements

Baseline functional targets:

### AP

- 2.4 GHz AP works;
- 5 GHz AP works on non-DFS channels;
- WPA2-PSK works;
- repeated association/disassociation is stable;
- multiple clients can associate concurrently.

### STA

- station mode can scan and associate;
- reconnect after AP loss works;
- `wifi reload` does not leave stale interface state.

### 5 GHz/VHT

Initial non-DFS test channels:

```
36 / 40 / 44 / 48
```

Target mode:

```
VHT80
```

A visible 5 GHz SSID is not sufficient proof of VHT80. Validate using:

- `iw dev <ifname> info`;
- negotiated station capabilities;
- local iperf3 throughput;
- channel/frequency observations.

## 10. Station enumeration and metrics

Associated-station enumeration is required.

The driver must support:

```
iw dev <ap> station dump
```

and expose associated MAC addresses to LuCI/iwinfo.

Important firmware limitation:

`WIFI_CMD_GET_STATION` does not accept a peer MAC argument. Therefore rate/signal data returned by the vendor command may represent interface/radio-level state rather than the requested individual peer.

Consequences:

- associated client MAC enumeration is a release requirement;
- per-client RSSI/rate accuracy is best-effort;
- UI must not present unverified per-peer metrics as authoritative;
- per-client RSSI/rate accuracy is not a first-release blocker.

## 11. Channel reporting

The integration must provide useful cfg80211 channel state.

Expected behavior:

- `iw dev <ifname> info` reports channel/frequency correctly;
- `get_channel` callback works with OpenWrt backport API;
- AP/STA state remains consistent after reload/reconnect.

Channel reporting must be verified on real hardware.

## 12. Stability requirements

Before calling the WLAN port usable, hardware testing should include:

- cold boot;
- warm reboot;
- repeated `wifi reload`;
- repeated AP start/stop;
- repeated client reconnect;
- two or more clients;
- sustained wired-to-Wi-Fi iperf3;
- multicast sanity;
- mDNS sanity;
- IPv6 ND sanity;
- at least 12 hours of sustained traffic/stability.

Use local iperf3, not an Internet speed test.

## 13. Failure isolation and recovery

Failures must be classified instead of handled by blind reload loops.

At minimum distinguish:

- SDIO device missing;
- BSP module failed to load;
- WLAN module failed to load;
- firmware load failure;
- cfg80211 registration failure;
- wlan interface absent;
- hostapd failure;
- association failure;
- data-path failure;
- multicast/broadcast degradation.

Recovery should start from the narrowest level:

1. inspect SDIO presence;
2. inspect module state;
3. reload WLAN module if safe;
4. reload BSP only when necessary;
5. restart wireless config/hostapd;
6. full reboot only as last resort during development.

Do not introduce an automatic reboot loop.

## 14. Diagnostic contract

The repository includes:

```
scripts/collect-debug.sh
```

The collector should remain able to capture:

- board/OpenWrt identity;
- dmesg/logread;
- loaded modules;
- memory/cmdline;
- SDIO devices;
- relevant device-tree state;
- phy/interface state;
- station dump/iwinfo;
- network addresses/routes;
- services;
- sanitized wireless/network config;
- storage state;
- firmware/driver log evidence.

Wi-Fi credentials must be redacted.

The diagnostic bundle should remain sufficient to determine whether failure is in:

```
DT/SDIO
-> BSP
-> WLAN module
-> firmware
-> cfg80211
-> hostapd/wpad
-> association
-> data path
```

## 15. Build pipelines

### SDK package build

Workflow:

```
.github/workflows/build-packages.yml
```

Purpose:

- faster driver/firmware compile loop;
- official OpenWrt 25.12.5 SDK;
- fetch matching mac80211 package source from the SDK-pinned OpenWrt commit;
- compile UWE5622 + firmware;
- verify important symbols.

This workflow is a development accelerator, not a substitute for a full image build.

### Full image build

Workflow:

```
.github/workflows/build-image.yml
```

Purpose:

- clone official OpenWrt `v25.12.5`;
- apply the Zero 3 WLAN overlay;
- build the complete Orange Pi Zero 3 image;
- verify required packages;
- verify UWE5622 driver symbols;
- verify delayed-load policy;
- decompile and validate the built DTB;
- publish image/manifest/checksum artifacts.

Full-image success is the stronger release signal.

## 16. Image profile

Current test image intentionally includes more than the Wi-Fi driver so the board can act as a development gateway and modem testbed.

Core additions include:

### WLAN

```
kmod-uwe5622
uwe5622-firmware
wireless-regdb
iw
iwinfo
wpad-basic-mbedtls
```

### LuCI

```
luci
luci-ssl
luci-theme-footstrap
luci-theme-bootstrap
```

### Cellular modem stack

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

### USB serial/modem drivers

```
kmod-usb-core
kmod-usb2
kmod-usb3
kmod-usb-serial
kmod-usb-serial-wwan
kmod-usb-serial-option
kmod-usb-acm
kmod-usb-net
kmod-usb-net-cdc-ether
kmod-usb-net-rndis
kmod-usb-net-cdc-ncm
kmod-usb-net-cdc-mbim
kmod-usb-net-qmi-wwan
kmod-usb-net-cdc-eem
kmod-usb-net-cdc-subset
kmod-mii
```

### USB Ethernet fallback

```
kmod-usb-net-rtl8152
kmod-usb-net-asix
kmod-usb-net-asix-ax88179
kmod-usb-net-smsc95xx
kmod-usb-net-lan78xx
kmod-usb-net-dm9601-ether
kmod-usb-net-sr9700
```

### Diagnostics

```
usbutils
pciutils
picocom
coreutils
coreutils-timeout
coreutils-stty
ethtool
ip-full
ip-bridge
tcpdump
lsof
strace
iperf3
htop
ppp
chat
```

Package names must be preflight-checked against the pinned OpenWrt release before image build.

## 17. Footstrap

Current image build stages:

```
luci-theme-footstrap v0.14.13
```

This is a convenience/theme addition and must not become coupled to WLAN functionality.

The image must remain diagnosable with Bootstrap even if Footstrap breaks.

## 18. Current implementation snapshot — 2026-09-30

Current branch head at the time of this snapshot:

```
618c9ffc5c9878f6e2040f81a0ae3420caea1391
```

Driver source is pinned to:

```
cc2835a3f935d5297e03cdce464c1785381a7b4d
```

Implemented repository components include:

- UWE5622 kernel package;
- UWE5622 firmware package;
- OpenWrt cfg80211 compatibility patches;
- netdev locking fixes;
- station enumeration support;
- channel reporting support;
- VLA build fixes;
- SDIO/device-tree enablement;
- delayed module-load safety policy;
- debug collector;
- SDK package workflow;
- complete image workflow;
- 512 MiB rootfs test image;
- LuCI + Footstrap;
- modem-ready USB/QMI/MBIM/ModemManager stack;
- common USB Ethernet fallback drivers.

At this snapshot, full-image workflow run #7:

```
run id: 36739712280
state: in progress
```

It has already passed:

- checkout;
- host dependency install;
- OpenWrt clone;
- overlay application;
- Footstrap staging;
- feed update;
- image configuration/package preflight;
- source download.

It is currently at full image compilation.

Do NOT claim this run is green until its final result is checked.

The previous full-image run #6 failed during package preflight because `ip-neighbor` is not a valid package in the pinned release. That request was removed in commit:

```
618c9ffc ci: drop nonexistent ip-neighbor package
```

## 19. Acceptance criteria

A buildable package alone is insufficient.

A usable baseline requires:

### Build

- UWE5622 package builds;
- firmware package builds;
- complete Orange Pi Zero 3 image builds;
- expected packages are present in manifest;
- expected driver symbols exist;
- built DTB contains required mmc1 properties.

### Boot

- board remains reachable over Ethernet;
- Wi-Fi probe cannot wedge the boot path;
- delayed-load service behaves deterministically.

### WLAN

- phy appears;
- wlan interface appears;
- 2.4 GHz AP works;
- 5 GHz non-DFS AP works;
- STA mode works;
- station enumeration works;
- channel reporting works.

### Stability

- repeated reload/reconnect works;
- multicast/ARP/IPv6 ND remain healthy;
- sustained local traffic passes;
- 12+ hour run is stable.

## 20. Development priorities

Priority order:

1. obtain a green full OpenWrt 25.12.5 image build;
2. boot image on real Orange Pi Zero 3 and confirm Ethernet-safe delayed Wi-Fi load;
3. capture debug bundle;
4. validate SDIO/BSP/firmware/phy bring-up;
5. validate 2.4 GHz;
6. validate 5 GHz non-DFS + VHT80;
7. validate station enumeration/channel reporting;
8. run reload/reconnect/multicast tests;
9. run sustained traffic/stability test;
10. only then consider optional tuning such as re-enabling power saving or improving per-client metrics.

## 21. Non-goals for first usable baseline

Not required before first usable release:

- perfect per-client RSSI;
- perfect per-client PHY rate;
- DFS certification/coverage;
- maximum theoretical throughput;
- aggressive power-saving optimization;
- Bluetooth integration;
- replacing the vendor firmware protocol.

First milestone is stable, recoverable OpenWrt Wi-Fi on the onboard UWE5622.

## 22. Development discipline

- Work on dev/topic branches.
- Do not merge to `main` without explicit instruction.
- Do not tag/release without explicit instruction.
- Never edit generated `build_dir` files as the source of a fix.
- Keep source and firmware revisions pinned.
- Preserve licensing/provenance.
- Validate built artifacts, not only source patches.
- Do not call a CI build successful without checking the current run.
- Preserve Ethernet access and diagnostic recoverability above convenience.
