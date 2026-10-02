# Orange Pi Zero 3 WLAN / UWE5622 — Technical Specification

Date: 2026-09-30  
Repository: `Medvedolog/opiz3-wlan-backport`  
Development branch: `dev/owrt-25.12-uwe5622-current`

## 1. Goal

Make the onboard AW859A / UNISOC UWE5622 WLAN on Orange Pi Zero 3 behave as a normal OpenWrt wireless device on the OpenWrt 25.12 series.

The target is not merely "module loads" or "SSID appears". The target is usable OpenWrt integration:

- stable 2.4 GHz and 5 GHz AP/STA operation;
- cfg80211/nl80211 integration;
- hostapd/OpenWrt control without vendor userspace glue;
- associated client enumeration;
- correct channel/frequency reporting;
- useful LuCI/iwinfo status;
- sustained traffic stability;
- reproducible package and full-image builds.

## 2. Platform baseline

Target:

```
Board: Orange Pi Zero 3
SoC: Allwinner H618
OpenWrt: 25.12.x
Reference release used in CI: 25.12.5
Target: sunxi/cortexa53
Kernel: Linux 6.12
Wi-Fi module/chipset: AW859A / UNISOC UWE5622
Transport: SDIO
```

The current driver source is pinned to:

```
armbian/uwe5622
commit cc2835a3f935d5297e03cdce464c1785381a7b4d
```

The driver remains external to the kernel tree.

Expected modules:

```
uwe5622_bsp_sdio.ko
sprdwl_ng.ko
```

## 3. Upstream/reference sources

Primary references:

- OpenWrt source tree;
- Armbian UWE5622 driver;
- Armbian firmware;
- existing community OpenWrt UWE5622 integrations used only as porting references.

Patch authorship/licensing must be preserved where third-party code is carried.

The project should converge toward normal OpenWrt APIs rather than preserving unnecessary vendor glue.

## 3.1 R&D scope and project boundary

This specification covers more than a conventional kernel-version port.

The project deliberately reuses the current Armbian UWE5622 driver as its source baseline. Armbian's responsibility is broader: maintaining the community vendor-derived stack across multiple boards and modern Linux versions. Earlier Orange Pi Zero 3 community work also provided important board/DTS and Linux 6.x bring-up experience.

The additional R&D scope in this repository exists because the target is not merely a loadable driver but a router-grade OpenWrt radio. In scope are:

- OpenWrt-specific cfg80211/nl80211 behavior;
- correct AP and STA state reporting;
- truthful per-station data rather than interface-level values relabeled as peer data;
- host-side per-LUT traffic accounting;
- SDIO TX/RX correctness and concurrency defects discovered under router workloads;
- deterministic SDK and full-image CI, including generated-DTB QA;
- 5 GHz/VHT functional and throughput validation;
- power-save and early-probe failure analysis;
- static reverse engineering of the closed Marlin3/SC2355 firmware where required to establish protocol behavior;
- diagnostic live CP-memory reading only when necessary to recover otherwise unavailable telemetry, initially as an experimental/read-only path.

Out of scope unless later evidence makes them necessary:

- replacing the Armbian project as the general UWE5622 maintainer;
- rewriting the complete vendor WLAN/WCN stack;
- claiming unsupported RSSI/rate information;
- modifying `wcnmodem.bin` merely to make user interfaces look complete.

The engineering objective is therefore **narrow platform scope with deep behavioral validation**. Work is accepted only when it improves the defined OpenWrt use case and can be verified in CI and/or on the target hardware.

## 4. Architectural principle

The project should minimize invasive OpenWrt changes.

Prefer:

- a normal OpenWrt kmod package;
- a separate firmware package;
- target DTS enablement;
- narrow compatibility patches;
- cfg80211/nl80211 behavior visible to normal OpenWrt tooling.

Avoid:

- edits inside `build_dir`;
- runtime binary patching;
- large vendor init stacks when kernel/OpenWrt mechanisms are sufficient;
- hard dependency on custom userspace for basic AP/STA operation.

## 5. Current package layout

### Kernel package

```
package/kernel/uwe5622/
```

Builds:

```
uwe5622_bsp_sdio.ko
sprdwl_ng.ko
```

### Firmware package

```
package/firmware/uwe5622-firmware/
```

Installs required UWE5622 firmware/calibration assets.

### Target support

```
target/linux/sunxi/patches-6.12/
target/linux/sunxi/image/
```

Contains the Zero 3/Zero 2 SDIO WLAN DTS enablement and device-package integration.

## 6. OpenWrt cfg80211 backport compatibility

OpenWrt 25.12 uses cfg80211/mac80211 backport headers whose callback ABI cannot safely be selected only from the base Linux kernel version.

The driver therefore uses an explicit:

```
OPENWRT_CFG80211_BACKPORT
```

build define where necessary.

Current compatibility patches include support for:

- `change_beacon` callback shape;
- `set_wiphy_params` callback shape;
- cfg80211-aware netdev locking/registration;
- other kernel-6.12/OpenWrt backport API differences.

Kernel-version-only API selection is not sufficient.

## 7. Current patch set

Current carried patches include:

```
010-openwrt-cfg80211-backport-api.patch
020-enable-external-kbuild-config-symbols.patch
030-fix-cfg80211-netdev-locking.patch
060-unisocwifi-implement-dump-station.patch
070-unisocwifi-fix-remaining-vlas.patch
080-cfg80211-set-wiphy-params-backport-radio-idx.patch
090-unisocwifi-implement-get-channel-and-station-details.patch
100-unisocwifi-program-ap-channel-before-start.patch
110-openwrt-lean-profile.patch
120-unisocwifi-ap-mode-report-real-station-data.patch
130-unisocwifi-tx-pool-gfp-atomic-and-tx-stats.patch
140-unisocwifi-honest-station-flags.patch
150-unisocwifi-per-lut-host-counters.patch
160-unisocwifi-prepare-addba-before-enqueue.patch
```

All patches apply to the pinned source with `patch -F0` (no fuzz).

Some functionality previously carried by local patches has already moved into the pinned Armbian source and should not be duplicated.

## 8. DTS / SDIO bring-up

Orange Pi Zero 3 WLAN requires correct SDIO/MMC1 board description.

The built DTB must expose the WLAN SDIO node with the required properties, including:

```
status = "okay"
vmmc-supply
vqmmc-supply
mmc-pwrseq
bus-width
non-removable
mmc-ddr-1_8v
```

CI decompiles the actual generated DTB and validates the complete `mmc@4021000` node rather than trusting source patch presence alone.

## 9. Delayed module-load policy

The UWE5622 package intentionally does not use normal early kmod AutoLoad.

Reason:

- early SDIO probe has previously been capable of hanging boot before normal network availability;
- for a router/gateway image this failure mode is unacceptable because it can make the board unreachable.

The current policy is:

```
boot networking
-> delayed init service
-> modprobe UWE5622 transport
-> modprobe sprdwl_ng
```

The helper is:

```
/etc/init.d/sprdwl-delay
```

A WLAN driver failure should disable WLAN, not brick remote access to the gateway.

This policy can only be relaxed after repeated hardware tests prove early probe is safe.

## 10. Power-save policy

Firmware power saving is disabled by default for stability:

```
sprdwl_ng disable_powersave=1
```

Reason:

- stability has priority over idle power;
- firmware/vendor power saving has a known risk profile around multicast/broadcast delivery;
- affected traffic classes may include ARP, IPv6 ND and mDNS.

Acceptance testing must explicitly include those traffic classes.

Do not re-enable power saving by default until sustained hardware tests prove it safe.

## 11. 2.4 GHz and 5 GHz operation

The driver must support both bands when firmware advertises the required capability.

For 5 GHz, minimum initial validation should use non-DFS channels:

```
36
40
44
48
```

5 GHz acceptance must verify more than SSID visibility.

Required evidence:

- correct `iw dev <iface> info`;
- correct reported channel/frequency;
- actual client association;
- local iperf3 traffic;
- stable operation under sustained load.

VHT80 should be treated as validated only after hardware evidence confirms it is actually operating as requested.

## 12. Station enumeration

A central project goal is proper AP client visibility.

Current implementation includes:

- `dump_station` support;
- association tracking;
- client MAC enumeration;
- additional station fields where firmware exposes them.

Acceptance requirement:

```
iw dev <ap> station dump
```

must list associated client MAC addresses.

LuCI/iwinfo should also show associated clients.

## 13. Per-client statistics limitation

The current firmware API has an important limitation:

```
WIFI_CMD_GET_STATION
```

does not provide a peer-MAC selector.

Therefore the vendor `.get_station` path can return interface/radio-level signal/rate data even when cfg80211 requests data for a specific AP peer.

Consequences:

- client enumeration can be correct;
- client MAC addresses can be correct;
- per-client RSSI/rate must not be presented as authoritative until a firmware event/command carrying peer-specific metrics is identified.

The STA-LUT event provides useful identity/capability information such as:

- LUT index;
- HT/VHT flags;

but not sufficient peer-specific RSSI/rate telemetry.

Per-client RSSI/rate accuracy is not a blocker for the first usable release.

Firmware reverse engineering (`WCNMODEM-REVERSE-ENGINEERING.md` §39–§42) has since shown that in AP/GO mode the firmware does not resolve a peer for `GET_STATION` at all, and that no other existing message carries per-peer signal or rate. Patch `120` therefore makes AP-mode `get_station` report only:

- the `ASSOCIATED` flag (the driver has seen the firmware association report; authentication/authorization are hostapd state and are not claimed);
- per-station connected time;

and leaves signal, bitrate, tx_failed and traffic counters unset. If the driver's station table (16 entries) is full and the peer is not listed, `get_station` succeeds with an empty `station_info`, so hostapd does not drop the client but nothing is invented about it. Managed (STA) mode still uses the firmware reply, which there does describe the single peer, the AP we are connected to. Since patch `140` it also claims only `ASSOCIATED`, and only while connected.

Per-client traffic is counted on the host (patch `150`) and exposed for validation in `/sys/kernel/debug/sprdwl_debug/peer_stats`:

| Counter | Source | Meaning |
|---|---|---|
| `rx_packets`, `rx_bytes` | `rx_msdu_desc.sta_lut_index`, `msdu_len` | 802.3 MSDUs the firmware delivered for the LUT |
| `tx_enqueued_packets`, `tx_enqueued_bytes` | `tx_msdu_dscr.sta_lut_index`, `pkt_len` | frames queued towards the LUT, not proof of transmission |
| `rx_lut_invalid`, `rx_lut_ctx_mismatch` | global | RX frames that could not be attributed |

They are not reported through `station_info` until validated on hardware. The SDIO `rx_msdu_desc` carries no RSSI or PHY rate (those fields exist only in `rx_mh_desc`, the memory-header path used by PCIe).

## 14. Channel reporting

The driver must implement cfg80211 channel reporting sufficiently for normal OpenWrt tooling.

Current work includes `get_channel` support and channel state propagation.

Acceptance:

- current AP/STA channel shown correctly by `iw`;
- no stale channel after reload/reconnect;
- correct 2.4/5 GHz distinction;
- LuCI/iwinfo sees consistent channel information.

## 15. Stability requirements

A successful probe or one working association is not sufficient.

Required tests include:

- cold boot;
- repeated reboot;
- repeated `wifi reload`;
- AP stop/start;
- client reconnect loops;
- two or more associated clients;
- sustained Ethernet-to-WLAN traffic;
- multicast traffic;
- mDNS;
- IPv6 ND;
- DHCP;
- ARP;
- interface up/down;
- 5 GHz sustained operation.

Minimum long-run target before calling the WLAN usable:

```
12+ hours sustained traffic / normal operation
```

## 16. Throughput target

Throughput is measured with local iperf3, not an Internet speed test.

The initial pragmatic target is:

- stable 5 GHz AP;
- at least ~150 Mbit/s real local throughput if hardware/firmware conditions permit;
- no severe packet loss or periodic stalls.

Higher throughput is desirable but secondary to stability and correct OpenWrt behavior.

## 17. Debug/diagnostic collection

The repository includes:

```
scripts/collect-debug.sh
```

It gathers a structured bundle including:

- board/OpenWrt version;
- dmesg;
- logread;
- loaded modules;
- memory/cmdline;
- SDIO devices;
- device tree state;
- ieee80211/iw state;
- link and station dump;
- iwinfo;
- network/link/route state;
- services;
- UCI network/firewall/dhcp/wireless;
- storage;
- UWE5622 firmware/probe details.

Wi-Fi credentials are redacted.

The diagnostic tool should remain safe to attach to bug reports.

Future improvement should add:

- explicit driver version/source commit;
- loaded firmware hashes;
- channel/width summary;
- station-count summary;
- recent driver resets/timeouts;
- SDIO error counters when available.

## 18. CI strategy

Two build paths are maintained.

### Fast SDK package build

Workflow:

```
.github/workflows/build-packages.yml
```

Purpose:

- fast iteration on kmod/firmware;
- compile against the exact OpenWrt release SDK;
- import matching OpenWrt mac80211 package sources;
- validate required symbols in `sprdwl_ng.ko`.

### Full image build

Workflow:

```
.github/workflows/build-image.yml
```

Purpose:

- build the actual Orange Pi Zero 3 image;
- validate package selection;
- validate generated DTB;
- validate driver symbols;
- produce microSD-flashable `.img.gz`.

Current full-image reference:

```
OpenWrt 25.12.5
sunxi/cortexa53
xunlong_orangepi-zero3
rootfs part size: 512 MiB
```

## 19. Test image package policy

The development image intentionally contains more tooling than a minimal production router image.

WLAN/test packages include:

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

The image also carries a broad cellular-modem and USB-Ethernet test stack so the board can serve as a development gateway.

Relevant modem stack includes:

```
modemmanager
uqmi
umbim
usb-modeswitch
comgt
comgt-ncm
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
luci-proto-qmi
luci-proto-mbim
luci-proto-ncm
luci-proto-modemmanager
```

USB Ethernet coverage includes common Realtek/ASIX/SMSC/LAN78xx/DM9601/SR9700 families where available.

## 20. Footstrap

Footstrap is the default test-image LuCI theme target.

Current CI pins:

```
luci-theme-footstrap v0.14.13
```

Bootstrap remains present as a fallback.

The WLAN driver must not depend on theme-specific behavior.

## 21. Build reproducibility

Required rules:

- pin driver source commit;
- pin package/source hash;
- build against a fixed OpenWrt release/tag for test artifacts;
- never patch inside `build_dir`;
- validate resulting kernel module symbols;
- validate resulting DTB;
- upload image manifest and sha256 sums.

## 22. Release acceptance

A release candidate is acceptable only after hardware testing proves:

### Boot

- board boots reliably;
- Ethernet remains reachable even if WLAN fails;
- delayed WLAN loading does not stall boot.

### Driver

- both UWE5622 modules load;
- firmware loads;
- wlan interface appears;
- no persistent crash/reset loop.

### AP

- 2.4 GHz AP works;
- 5 GHz AP works;
- WPA2 association works;
- multiple clients can associate.

### Client visibility

- `iw station dump` lists client MACs;
- LuCI/iwinfo lists associated clients;
- no claim of authoritative per-client RSSI/rate until firmware support is proven.

### Channel

- correct channel/frequency;
- 5 GHz channel visible correctly;
- no stale channel after reload.

### Stability

- repeated reload/reconnect;
- multicast/ARP/IPv6 ND/mDNS sanity;
- sustained iperf3;
- 12+ hour stability test.

### Performance

- practical 5 GHz throughput target around or above 150 Mbit/s where RF/client conditions allow.

## 23. Current implementation snapshot — 2026-09-30

Working branch:

```
dev/owrt-25.12-uwe5622-current
```

Current branch head at snapshot:

```
618c9ffc5c9878f6e2040f81a0ae3420caea1391
```

Implemented:

- UWE5622 kernel package;
- firmware package;
- Zero 3/Zero 2 SDIO DTS enablement;
- OpenWrt cfg80211 backport compatibility;
- cfg80211/netdev locking fixes;
- VLA cleanup;
- `dump_station`;
- associated-client tracking;
- `get_channel`;
- additional station information;
- delayed-load safety policy;
- power saving disabled by default;
- debug bundle collector;
- fast SDK package workflow;
- full OpenWrt 25.12.5 image workflow;
- modem-ready/USB-Ethernet-rich development image configuration;
- Footstrap integration.

Not yet proven on hardware to release standard:

- stable 5 GHz AP operation;
- actual VHT80 behavior;
- sustained throughput target;
- multi-client stability;
- 12+ hour stability;
- robust reboot/reload/reconnect behavior;
- client enumeration behavior in the final image on real hardware;
- absence of SDIO/firmware hangs over time.

At snapshot time the latest full image workflow was still in the `Build image` step and had not yet uploaded an artifact. Do not infer success until the workflow completes.

## 24. Immediate next steps

1. finish/verify the current full-image build;
2. flash the generated `.img.gz` to microSD;
3. boot with wired Ethernet available for recovery;
4. run `scripts/collect-debug.sh`;
5. verify module load and firmware probe;
6. verify 2.4 GHz AP;
7. verify 5 GHz AP on non-DFS channel;
8. verify `iw station dump` and LuCI client list;
9. run local iperf3;
10. stress reload/reconnect;
11. run multicast/ARP/IPv6 ND/mDNS checks;
12. run long-duration stability test;
13. only after hardware evidence, simplify/remove compatibility/safety workarounds where justified.

## 25. Development discipline

- keep work on development branches;
- do not merge to main unless explicitly requested;
- do not tag/release without explicit instruction;
- preserve a wired recovery path during WLAN testing;
- do not treat module load as proof of functional Wi-Fi;
- do not treat visible 5 GHz SSID as proof of VHT80;
- do not report interface-level signal as per-client signal;
- do not re-enable firmware power saving by default without stability evidence;
- do not remove delayed module loading until early-probe safety is proven;
- prefer minimal compatibility patches over invasive rewrites;
- keep builds reproducible and source-pinned.
