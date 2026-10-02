# UWE5622 driver audit and optimization plan

Date: 2026-10-02
Branch: `dev/uwe5622-driver-audit`
Base: `dev/owrt-25.12-uwe5622-current` @ `505a1546ae35a21928a004c7ff9b75e2a906f5be`
Target: Orange Pi Zero 3 / AW859A / UNISOC UWE5622, OpenWrt 25.12, Linux 6.12

## Executive summary

The current OpenWrt package already uses the right upstream lineage:

- driver: `armbian/uwe5622` pinned at `cc2835a3f935d5297e03cdce464c1785381a7b4d`;
- transport: out-of-tree `uwe5622_bsp_sdio.ko`;
- WLAN: out-of-tree `sprdwl_ng.ko`;
- firmware: currently mirrored from `armbian/firmware`.

Do not replace the current driver with the DeepAQ patch stack. The DeepAQ OpenWrt port is useful as a historical/reference implementation, but it carries an older monolithic Armbian patch series inside mac80211. The current Armbian standalone driver has already absorbed later reconnect/roam fixes, flexible-array cleanups, spanning-write fixes and modern-kernel maintenance.

The useful optimization work is therefore not a wholesale driver swap. It is:

1. trim Android/vendor-only code from the OpenWrt build;
2. improve cfg80211/AP integration;
3. instrument and optimize the SDIO TX/RX path;
4. identify real per-peer statistics exposed by firmware/events;
5. fix the root cause of power-save instability;
6. fix the early SDIO probe hang so delayed loading can eventually be removed;
7. validate and correct 5 GHz/VHT capability/channel handling.

No optimization is allowed to weaken the wired-recovery invariant or claim functionality that has not been proven on hardware.

## 1. Source baseline

### Current package

`package/kernel/uwe5622/Makefile` pins:

```
armbian/uwe5622
cc2835a3f935d5297e03cdce464c1785381a7b4d
```

This source contains both the UNISOC WCN/SDIO transport and the cfg80211 WLAN driver.

### Armbian status

The pinned commit is newer than the August 2026 `d6bec7538a0b4b67e35715ad71eaa056555524cb` revision. Between `d6bec75` and the pinned source Armbian integrated important fixes, including:

- connection/roam state reconciliation;
- holding/validating cfg80211 BSS references for asynchronous connection events;
- later modern-kernel maintenance.

Therefore an apparent "newer" reference that merely uses DeepAQ's old Armbian patch stack is not a better driver baseline.

### DeepAQ status

`DeepAQ/openwrt-uwe5622-sunxi` integrates the old UWE5622 source as a roughly 13 MB patch under `package/kernel/mac80211/patches/unisoc/`.

It contains useful historical fixes such as:

- system-load reduction by replacing uninterruptible TX completion waiting;
- spanning/flexible-array fixes;
- kernel API compatibility patches;
- MAC-address handling fixes.

These are references only. Before importing any DeepAQ patch, verify that the equivalent is not already present in the pinned Armbian source.

### Patch and source provenance

Keep three categories distinct when discussing upstream credit:

| Category | Source / author | How it is used here |
|---|---|---|
| Original BSP | Spreadtrum / UNISOC | Base vendor WCN/WLAN implementation inherited through the community driver |
| Current driver baseline | Armbian `uwe5622` maintainers/contributors | Pinned source tree; modern-kernel fixes and multi-platform maintenance are inherited directly |
| Earlier repository lineage | `EvilOlaf/uwe5622` | Armbian's current repository is forked from this earlier community tree |
| Direct patch author | `jukeboge` | Patches `010`, `020`, `030`; original `From:` and `Signed-off-by:` retained |
| Direct patch author | Rizki Ramadhan | Patches `060`, `080`, `090`; original `From:` and `Signed-off-by:` retained |
| Historical/reference only | DeepAQ `openwrt-uwe5622-sunxi` | Used to compare older OpenWrt fixes; not used as the current source baseline |
| Historical/reference only | Doct2O Zero 3 Linux 6.x port | Used as evidence/reference for board bring-up and conservative vendor-driver adaptation |
| Firmware provenance | Orange Pi / Xunlong, via Armbian mirror | Public source lineage for `wcnmodem.bin` and companion firmware assets |

Patches `070`, `100`–`160` are project-local work unless a future patch header states otherwise. Do not remove or rewrite third-party authorship when rebasing or refreshing a patch.

This distinction matters: citing a repository used for comparison is not the same as claiming its code is carried, and inheriting fixes through the pinned Armbian tree is different from importing those fixes as local patches.

### Scope relative to Armbian and earlier community ports

This project is downstream of, and dependent on, substantial community work. Its scope is different rather than universally larger.

**Armbian's scope is broader.** The current `armbian/uwe5622` repository is a community-maintained out-of-tree driver for multiple ARM SBCs and modern kernel releases. It carries the vendor WCN/WLAN stack forward across kernel API changes and provides the baseline used by this OpenWrt package. That breadth, multi-board maintenance and continuing kernel compatibility work are outside the scope of this repository.

**Earlier Orange Pi Zero 3 ports concentrated on bring-up.** Public Zero 3 Linux 6.x work describes the port mainly as adapting the vendor 5.4 driver to a newer kernel, fixing DTS/wiring and replacing or re-exporting changed kernel APIs while deliberately keeping the vendor driver as intact as practical. That work established an important proof that the hardware could operate outside the original vendor kernel.

**The present repository is narrower but deeper in one deployment model:** Orange Pi Zero 3 / AW859A / UWE5622 as an OpenWrt router radio. The work therefore includes several layers that a conventional kernel port does not have to solve:

1. OpenWrt cfg80211/mac80211-backport ABI integration rather than only mainline-kernel compatibility;
2. AP/STA semantics visible through nl80211, `iw`, iwinfo, LuCI and hostapd;
3. honest station accounting, including removal of firmware/interface values that cannot be attributed to an AP peer;
4. host-side per-LUT RX/TX instrumentation and TX-path ownership/concurrency fixes;
5. reproducible SDK full/lean builds, image builds and generated-DTB validation;
6. preservation of wired manageability through delayed WLAN loading while early SDIO probe remains unsafe;
7. binary reverse engineering of `wcnmodem.bin`, including the firmware command/event ABI, station-record layout and rate-control state;
8. investigation of live CP-memory observation as a possible way to recover AP per-peer rate without modifying proprietary firmware.

A useful way to describe the engineering depth is:

| Layer | Typical result |
|---|---|
| Board bring-up | WLAN powers up and SDIO enumerates |
| Kernel port | Vendor driver builds and loads on a newer kernel |
| OpenWrt integration | cfg80211/nl80211/AP/STA work with normal OpenWrt tooling |
| Runtime correctness | station reporting, TX/RX ownership, recovery and long-run behavior are corrected and instrumented |
| Firmware/protocol RE | undocumented host/firmware behavior and limits are recovered and verified |
| CP-state recovery | missing telemetry is reconstructed from internal firmware state without changing the firmware |

The project is currently operating mainly in the fourth and fifth layers, with exploratory work beginning on the sixth. This classification is descriptive, not a claim that the project supersedes Armbian: Armbian remains the wider driver-maintenance effort and the source baseline.

References:

- Armbian UWE5622 driver: https://github.com/armbian/uwe5622
- Orange Pi Zero 3 Linux 6.x community port: https://github.com/Doct2O/orangepi-zero3-mainline-linux-wifi
- Firmware reverse-engineering notes: `WCNMODEM-REVERSE-ENGINEERING.md`

## 2. High-value finding: the WLAN build enables substantial unused functionality unconditionally

The current upstream `unisocwifi/Makefile` unconditionally defines:

```
IBSS_SUPPORT
IBSS_RSN_SUPPORT
NAN_SUPPORT
RTT_SUPPORT
ACS_SUPPORT
RX_HW_CSUM
WMMAC_WFA_CERTIFICATION
COMPAT_SAMPILE_CODE
RND_MAC_SUPPORT
ATCMD_ASSERT
TCPACK_DELAY_SUPPORT
SPLIT_STACK
OTT_UWE
CP2_RESET_SUPPORT
```

and unconditionally links objects including:

```
npi.o
vendor.o
tcp_ack.o
ibss.o
nan.o
tracer.o
rtt.o
rnd_mac_addr.o
debug.o
```

For the initial OpenWrt Zero 3 target the required feature set is much narrower:

- cfg80211/nl80211;
- AP;
- STA;
- WPA2/WPA3 as provided by hostapd/firmware capabilities;
- 2.4 GHz;
- 5 GHz;
- HT/VHT;
- regulatory handling;
- multicast;
- normal power/recovery paths.

### Candidate experiment A: OpenWrt lean profile

Introduce OpenWrt-specific build switches rather than deleting vendor code.

First trim candidates:

- NAN;
- RTT;
- IBSS;
- NPI/test interface;
- WMM certification-only paths;
- Android vendor command paths not required by hostapd;
- random-MAC machinery if normal OpenWrt MAC policy replaces it.

Do **not** remove in the first pass:

- TCP ACK handling;
- reorder/QoS;
- CP2 reset/recovery;
- regulatory code;
- ACS until AP channel behavior is fully understood;
- multicast handling;
- any code participating in firmware API version negotiation.

Each trim must be independently build-tested and hardware-tested. Record module sizes before/after.

## 3. TX path audit

**Fixed (patch `130`):** `sprdwl_get_msg_buf()` used `kzalloc(GFP_KERNEL)` to grow the data pool when it was more than 80% in use. It is called from `ndo_start_xmit`, which runs with BH disabled, so this was a sleeping allocation in atomic context. It now uses `GFP_ATOMIC` and is counted in `tx_stats` (`data_pool_expand`, `data_pool_expand_fail`). The pool still grows without bound while above the threshold. Whether to cap it should be decided from hardware `tx_stats` data, not blindly.

The WLAN driver has a large vendor TX path built around:

- `tx_msg.c`;
- `wl_intf.c`;
- `qos.c`;
- `tcp_ack.c`;
- WCN SDIO bus queues.

### Observations

`sprdwl_get_msg_buf()` dynamically expands the TX QoS message pool with `kzalloc(GFP_KERNEL)` once pool usage crosses 80%. This is functional but is worth measuring under sustained traffic because it may cause allocation churn and unbounded growth in bad conditions.

The datapath carries multiple list locks and per-peer/per-AC queue operations. Hardware profiling is required before changing locking; this is a likely throughput/latency optimization area, but blind lock removal is unsafe.

The driver already contains the historical fix which avoids permanently inflating load average through an uninterruptible completion wait; do not re-import the old DeepAQ patch without checking the current source.

### Instrumentation required before optimization

Add optional counters for:

- TX pool current/max allocation;
- pool expansion count;
- allocation failures;
- SDIO list allocation failures;
- packets per SDIO push;
- TX queue depth by AC;
- time from netdev xmit to bus completion;
- flow-control stop/wake count;
- dropped packets by reason.

Instrumentation must be disabled or low-cost by default.

## 4. RX path audit

Audit:

- `rx_msg.c`;
- `reorder.c`;
- `defrag.c`;
- WCN SDIO RX batching.

Measure:

- packets per RX transaction;
- reorder queue depth;
- duplicate/out-of-window drops;
- copy count from SDIO buffer to skb;
- multicast/broadcast losses;
- checksum-offload behavior.

No RX optimization should proceed until DHCP, ARP, IPv6 ND and mDNS remain reliable for long runs.

## 5. Station accounting

Current OpenWrt patches correctly enumerate associated station MACs, but firmware command `WIFI_CMD_GET_STATION` has no peer-MAC argument.

Therefore current signal/rate values must not be described as authoritative per-client metrics.

**Status (2026-10-02, RE revision 2):** resolved as far as the existing protocol allows. The firmware `GET_STATION` handler resolves no peer at all in AP/GO mode: the rate is empty and the signal is a calibration offset. `LINK_STAT`, `STA_LUT_INDICATION` and `WFD_MIB_COUNTER` carry no per-peer signal or rate either (`WCNMODEM-REVERSE-ENGINEERING.md` §39–§42). Patch `120` makes AP-mode `get_station` report only real per-station data (the `ASSOCIATED` flag and per-station connected time) and return `-ENOENT` for unknown peers; with a full station table it returns success with an empty `station_info`. Per-LUT TX/RX byte and packet counters are implemented in patch `150` (debugfs `peer_stats` only). After hardware validation, the next steps are reporting RX through `station_info` and finding the latest TX completion point that still knows the LUT, so that TX can be reported as transmitted rather than enqueued.

Fixed in `160`: `sprdwl_tx_msg_func()` called `prepare_addba(intf, dscr->sta_lut_index, msg->skb, ...)` *after* `sprdwl_queue_data_msg_buf()`, and outside the data branch. For data frames this was a use-after-free race with the TX thread. For command buffers it was an out-of-bounds read of `tx_num[32]`, indexed by command-payload bytes (`peer_entry` is NULL there, so no ADDBA was sent). `prepare_addba()` now runs inside the data/QoS branch before the enqueue, and `msg_type` is read into a local before queueing. Validate under sustained bidirectional iperf3.

### Next reverse-engineering target

Trace all data associated with:

- `WIFI_EVENT_NEW_STATION`;
- STA/LUT add/update/remove events;
- TX completion/status;
- link-layer statistics (`WIFI_CMD_LLSTAT`);
- RSSI monitor events;
- firmware TLVs;
- per-peer QoS/LUT structures.

Goal: determine whether peer RSSI/rate exists elsewhere in the firmware protocol. If not, retain MAC enumeration and explicitly mark radio/interface metrics as such.

## 6. 5 GHz / VHT path

Firmware reports capabilities through `WIFI_CMD_GET_INFO`. The response includes:

- `SPRDWL_CAPA_5G`;
- HT capability information;
- VHT capability information;
- VHT MCS map;
- antenna information.

The complete control path to audit is:

```
hostapd
 -> nl80211/cfg80211
 -> sprdwl cfg80211 callbacks
 -> WIFI_CMD_SET_CHANNEL
 -> WIFI_CMD_START_AP
 -> firmware
```

### Hardware validation

For channel 36/40/44/48 record:

- requested channel;
- requested width;
- kernel-reported channel/width;
- client-reported PHY;
- negotiated MCS/NSS when available;
- local Ethernet-to-WLAN iperf3 throughput.

A visible 5 GHz SSID is not proof of correct VHT80 operation.

## 7. Power-save root cause

Current OpenWrt policy is:

```
sprdwl_ng disable_powersave=1
```

Keep this default during stabilization.

The optimization objective is not simply to re-enable power saving. First identify which transition causes loss/stall:

- firmware PS entry;
- firmware PS exit;
- WCN sleep;
- SDIO wake;
- multicast filtering/offload;
- host wake signaling.

Add targeted counters/logging around those transitions, then test ARP, DHCP renewal, IPv6 ND and multicast during idle/wake cycles.

Only enable PS by default after long-run hardware validation.

## 8. Early probe / delayed module load

Current `sprdwl-delay` protects wired manageability because early SDIO probe has previously hung boot.

This workaround must remain until the root cause is identified.

Audit candidates:

- mmc1 power sequence;
- regulator readiness;
- SDIO function enumeration timing;
- WCN firmware download;
- completion waits without timeout;
- SDIO interrupt setup;
- firmware-ready handshake;
- failure cleanup/reprobe.

Target end state: normal OpenWrt module autoload with bounded failures. A failed WLAN probe must never make Ethernet management unavailable.

## 9. WCN transport scope

The upstream WCN tree supports multiple chips/transports/platforms. The OpenWrt package currently builds the Allwinner UWE5622 SDIO configuration, so many USB/PCIe/Rockchip/Amlogic paths are already excluded by preprocessor configuration.

Do not spend effort deleting source files that are not linked into our modules. Measure actual linked sections first with `size`, `nm` and module section data.

The WLAN module is a better first trim target because its Makefile explicitly links NAN/RTT/IBSS/NPI/etc. into `sprdwl_ng.ko`.

## 10. Firmware provenance

Current firmware contents are traceable to the official Orange Pi/Xunlong firmware repository. The current Armbian copy of `wcnmodem.bin` is byte-identical at Git blob level to the Orange Pi version published in 2022.

Future packaging should prefer the primary public Orange Pi/Xunlong source over an Armbian mirror, subject to completing redistribution-license verification.

Firmware source code has not been found publicly, so optimization scope is the Linux driver, protocol usage, SDIO transport and configuration rather than internal Marlin3 firmware algorithms.

## 11. Patch strategy

Do not create one large "optimized driver" patch.

Use small patches with one measurable purpose:

1. instrumentation only;
2. optional lean-build switches;
3. remove one unused feature at a time;
4. cfg80211/AP correctness fixes;
5. per-peer statistics if proven;
6. power-save fix;
7. early-probe fix;
8. datapath optimization only after measurements.

Every functional patch must preserve a straightforward revert path.

## 12. CI additions

Add fast checks before performance work:

- build full `sprdwl_ng.ko`;
- build lean `sprdwl_ng.ko`;
- report module sizes;
- ensure AP/STA/cfg80211 symbols remain;
- ensure required firmware command/event symbols remain;
- reject accidental loss of 5 GHz/VHT code;
- reject accidental early autoload until probe safety is proven.

Full-image CI remains authoritative for package/DT integration.

## 13. Hardware benchmark matrix

Use the same image/kernel ABI for A/B tests.

Baseline metrics:

- cold boot success rate;
- `wifi reload` success rate;
- reconnect success rate;
- 2.4 GHz TCP throughput;
- 5 GHz TCP throughput;
- latency under load;
- two-client AP test;
- multicast/ARP/ND/mDNS;
- 12+ hour traffic;
- kernel warnings;
- firmware/SDIO resets;
- module memory/size.

Performance changes are accepted only if stability does not regress.

## 14. Immediate implementation order

### P0: correctness first

1. finish reliable 2.4/5 GHz AP channel handling;
2. verify current reconnect/roam fixes on OpenWrt;
3. diagnose early probe hang;
4. preserve correct client enumeration.

### P1: observability

5. add TX/RX/SDIO counters needed for profiling (TX pool/flow/drop part done: patch `130`, `/sys/kernel/debug/sprdwl_debug/tx_stats`; RX and SDIO batching still open);
6. expose a compact debug dump;
7. record firmware capability response relevant to 5 GHz/VHT.

### P2: lean build

8. make NAN/RTT/IBSS/NPI optional for the OpenWrt build (patch `110`; fixed 2026-10-02: the previous `110` had a wrong hunk header, so GNU patch silently dropped the object-list hunk and the lean module still linked `npi.o`, `ibss.o`, `nan.o` and `rtt.o`. Measured against Linux 6.12/arm64: full 2.29 MB, lean 2.06 MB, about −228 KB);
9. compare module size and behavior;
10. consider further vendor-glue trimming only after dependency proof.

### P3: performance

11. profile SDIO batching and TX pool behavior;
12. optimize only measured bottlenecks;
13. retest VHT throughput.

### P4: cleanup for upstreamability

14. remove temporary diagnostics not useful upstream;
15. normalize patch authorship/Signed-off-by;
16. document firmware provenance/license status;
17. split OpenWrt submission into reviewable logical patches.

## 15. First conclusion

There is substantial Linux-side optimization scope, but the highest-value work is not speculative micro-optimization.

The immediate concrete opportunities are:

- compile out vendor features OpenWrt does not use;
- improve observability of the SDIO datapath;
- finish 5 GHz/cfg80211 correctness;
- identify whether firmware exposes real per-peer metrics;
- remove the two current operational workarounds only after fixing their causes: forced power-save disable and delayed module loading.

The current Armbian source remains the preferred baseline.
