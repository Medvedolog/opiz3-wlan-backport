# Orange Pi Zero 3 (and Zero 2): onboard Wi-Fi (AW859A / UWE5622) on OpenWrt 25.12

The Orange Pi Zero 3 has an onboard AW859A module (UNISOC UWE5622, SDIO).
Mainline Linux has no driver for it and OpenWrt does not support it. This
repository makes it a working OpenWrt radio on **official OpenWrt 25.12.5**:
2.4 and 5 GHz, AP and client, configured from LuCI/UCI like any other radio.

What sets it apart from earlier builds:

- **Official OpenWrt kernel.** The image is made with the official
  ImageBuilder, so every kmod from downloads.openwrt.org installs with `apk`.
  The driver and the few other packages OpenWrt does not ship come from our
  own signed apk repository.
- **The driver is fixed, not just compiled.** The vendor driver is hardened
  against the crashes found so far (25 patches, 010–280). It reports only
  numbers that are actually measured, and it refuses settings that crash
  the firmware.
- **The firmware is understood.** The Wi-Fi firmware was reverse engineered
  far enough to explain its failures. All findings are published in
  [docs/](docs/).

> Status: **beta.** 2.4 GHz and 5 GHz AP mode (including VHT80) is verified on
> a Zero 3 (about 160 Mbit/s with iperf3, the "Unisoc UWE5622" name in LuCI,
> the client list). The newest pieces (240–280: per-client TX rate, crash
> recovery with SDIO host reset, the board status panel) are built and
> checked in CI but still await hardware confirmation.
> See [Status](#status).

## Кратко по-русски

Встроенный Wi-Fi Orange Pi Zero 3 (AW859A/UWE5622) на **официальном OpenWrt
25.12.5**: 2,4 и 5 ГГц, точка доступа и клиент, настройка через LuCI.

- **Официальные kmod ставятся через `apk`.** Образ собран из официального ядра
  через ImageBuilder. Драйвер, прошивка, AmneziaWG и Footstrap лежат в нашем
  подписанном apk-репозитории.
- **Драйвер исправлен, а не просто собран.** Исправлены переполнения, гонки и
  утечки. Прошивка защищена от режимов, на которых она падает. После её
  падения драйвер перезапускается сам. Статистика клиентов показывает только
  реально измеренное.
- **Прошивка `wcnmodem.bin` разобрана.** Найдено, почему 5 ГГц не поднимались,
  где хранятся скорость и RSSI клиентов и почему прошивка падает. Всё описано
  в [docs/](docs/).
- **Что работает, что ждёт проверки и что не сделано** — в разделе
  [Status](#status). Скачать образ — в разделе [Download](#download).

## Contents

- [Status](#status)
- [Boards](#boards)
- [Performance](#performance)
- [Download](#download)
- [Background: earlier attempts](#background-earlier-attempts)
- [What this project adds](#what-this-project-adds)
- [What we are still working on](#what-we-are-still-working-on)
- [Driver patch series](#driver-patch-series)
- [Building](#building)
- [Diagnostics](#diagnostics)
- [Documentation](#documentation)
- [Credits and license](#credits-and-license)

## Status

| Area | State |
|---|---|
| SDIO bring-up, firmware download, `wlan0` / `phy0` | Works |
| 2.4 GHz AP, HT20 | Works |
| 5 GHz AP, ch36 | Works; the firmware transmits at 80 MHz even when the host configures 20 MHz (see [Performance](#performance)) |
| Client (STA) mode | Not yet tested in this project |
| Associated clients in `iw station dump` / LuCI | MAC list works |
| Per-client RX/TX bytes and packets | Built (270, awaits hardware check). TX counts what was queued to the firmware, not what the client acknowledged |
| Per-client TX bitrate | Experimental: `cp_txrate=1` in `/etc/uwe5622.options` (240), read from the firmware rate-control table; the decoding matches hardware dumps |
| Per-client RSSI (live) | Not available: not in any host event or RX descriptor; searched for in firmware memory (`cp_mem`, 260) |
| Per-client RX bitrate | Not available |
| Driver name in LuCI | Works: "Unisoc UWE5622" instead of "Generic" (iwinfo patch); `iwinfo` CLI fix built (awaits hardware check) |
| Power save | Off by default; a bug that silently ignored the option is fixed |
| Crash recovery after a firmware assert | Built (awaits hardware check) |
| Unsupported widths/channels blocked | Built (awaits hardware check) |
| DFS channels (52–144) | Blocked by default |
| 160 MHz, ch 34, ch 184+ | Blocked |
| Autoload at boot | Delayed load after the network is up, so a stuck SDIO probe cannot block Ethernet ([roadmap](#what-we-are-still-working-on), item 4) |

Defaults are deliberately conservative: 20 MHz on both bands, no DFS. They
are module parameters in `/etc/uwe5622.options`:

```
max_bw_2g=20      # 20 or 40
max_bw_5g=20      # 20, 40 or 80 (80 verified to start)
allow_dfs=0
```

The driver advertises only these widths and channels, and
`uwe5622-clamp-htmode` lowers `htmode` in the wireless config to match.
Without this, a setting the firmware cannot handle makes it assert, and
Wi-Fi is gone until a reboot.

## Boards

| Board | SoC | Image | State |
|---|---|---|---|
| Orange Pi Zero 3 | H618 | `xunlong_orangepi-zero3` | **Tested** on hardware |
| Orange Pi Zero 2 | H616 | `xunlong_orangepi-zero2` | **Built, untested: testers wanted.** Same Wi-Fi module and wiring as the Zero 3 (shared `sun50i-h616-orangepi-zero.dtsi`, PG18 reset); the DTB change is identical to kernel patch 900 |

Other boards that carry the AW859A / UWE5622 module (per vendor
specifications, not verified here):

- **Orange Pi Zero 2W** (H618): in OpenWrt as `xunlong_orangepi-zero2w`;
  needs its own Wi-Fi device-tree nodes.
- **Orange Pi 3 LTS** (H6): the board the original OpenWrt package was
  written for; OpenWrt has no separate 3 LTS profile.
- Other boards and TV boxes with this module.

What carries over to any of them:

- the driver patches (010–280) and the packages in the apk repository,
  which are built for `sunxi/cortexa53` (H6, H616, H618);
- the firmware analysis in [docs/](docs/): `wcnmodem.bin` is the same file;
- patch 250 (SDIO driver re-registration) on every Allwinner board.

Per board, what is needed: the Wi-Fi nodes in the device tree (SDIO
controller, power rails, reset GPIO), an image profile in CI, and a test on
hardware. Reports with `scripts/collect-debug.sh` output are welcome.

## Performance

Measured on a Zero 3, 5 GHz ch36, one antenna, Android phone at about 1 m,
old image (patches up to 230):

| Test | Result |
|---|---|
| iperf3 phone → board, 5 streams | 160 Mbit/s (above the ~87 Mbit/s VHT20 PHY ceiling: the link really is 80 MHz) |
| Phone link rate (phone's own statistics) | RX 390 / TX 433 Mbit/s (VHT80 MCS8/9, SGI) |
| Rate control at −69 dBm (`cp_sta_table`) | VHT80 MCS2 |
| Client 1 iperf3 unlimited + client 2 speed test | client 2 ≤ 5 Mbit/s |
| Client 1 iperf3 limited to 50 Mbit/s + client 2 speed test | client 2 76 down / 31 up (internet ceiling ~100) |
| CPU during the load | 85–95 % idle, no core saturated |

Reading: the aggregate ceiling is about 160 Mbit/s and an unlimited TCP
upload from one client takes nearly all of it; below saturation the clients
share fairly. The CPU is idle, the SDIO RX thread waits on I/O, and the
SDIO bus runs in High Speed mode (50 MHz, 4 bit, ~200 Mbit/s raw), which
fits the ceiling. Next experiment: SDIO UHS SDR50 (100 MHz) in the device
tree.

## Download

Each build produces:

- **Image** (`opiz3-image-25.12.5`): squashfs and ext4 SD-card images.
  Flash them like any OpenWrt sunxi image.
- **ImageBuilder** (`opiz3-imagebuilder-25.12.5`): the official ImageBuilder
  with the Wi-Fi device tree already in the kernel, our packages, the key and
  the repository. Build your own package set with it:
  ```
  make image PROFILE=xunlong_orangepi-zero3 PACKAGES="... kmod-uwe5622 uwe5622-firmware ..."
  ```
- **apk repository** on GitHub Pages:
  `https://<owner>.github.io/opiz3-wlan-backport/25.12.5/sunxi-cortexa53/packages.adb`.
  The image ships its key and repository address, so `apk update`
  and `apk add` work for both the official repositories and ours.

Releases are published as `opiz3-25.12.5-latest`. Until the repository owner
has configured the signing key, builds are available only as Actions
artifacts.

The default image includes:
- LuCI with the Footstrap theme;
- AmneziaWG and WireGuard;
- sing-box;
- USB Wi-Fi drivers;
- modem support (ModemManager, QMI, MBIM, NCM, RNDIS, serial).

Anything else can be installed with `apk`.

## Background: earlier attempts

People have been trying to get this Wi-Fi onto OpenWrt for years. This
project builds on their work.

- **OpenWrt upstream.**
  [openwrt/openwrt#18494](https://github.com/openwrt/openwrt/issues/18494)
  ("Wi-Fi (AW859A) not detected on Orange Pi Zero 3", 24.10.0) was closed as
  *not planned*. The only available driver is a large out-of-tree vendor
  driver, and that is not material OpenWrt merges. The board's Wi-Fi is
  therefore unsupported in official images.
- **[armbian/uwe5622](https://github.com/armbian/uwe5622).** The maintained
  vendor driver (UNISOC WCN transport + `sprdwl_ng` cfg80211 driver) for
  Armbian kernels. Our base, pinned at `cc2835a`.
- **[DeepAQ/openwrt-uwe5622-sunxi](https://github.com/DeepAQ/openwrt-uwe5622-sunxi).**
  An early OpenWrt integration. It carries an older driver as a ~13 MB patch
  inside OpenWrt's `mac80211` package. Its key fix, adding the DS Parameter
  Set IE to 5 GHz beacons, is what makes 5 GHz AP mode work at all. We carry
  it as patch 180, and §44 of the reverse-engineering notes explains why it is
  needed.
- **[rizkirmdhnnn/openwrt-orangepi-zero3-wifi](https://github.com/rizkirmdhnnn/openwrt-orangepi-zero3-wifi).**
  OpenWrt packaging used here as the control baseline when the port started.
- **[Anieake/openwrt-orangepi-zero2-zero3-wifi-modem](https://github.com/Anieake/openwrt-orangepi-zero2-zero3-wifi-modem)**
  (the 4PDA forum build). A complete image on OpenWrt 25.12.0 with
  DeepAQ-based Wi-Fi, modem support and Bluetooth. Its README lists the Zero 2
  as working and the Zero 3 as needing verification. It uses its own kernel
  and replaces `mac80211`, so official kmods cannot be installed, and the
  build needs manual `-Werror` edits in `build_dir`.

All of these make the radio come up. None of them changed the driver beyond
building it. The crashes, the hangs, the meaningless client statistics and
the firmware's behaviour stayed as they were.

## What this project adds

| | Vendor driver / earlier builds | This project |
|---|---|---|
| OpenWrt | 24.10 / 25.12.0, custom kernel | 25.12.5, **official kernel** |
| Official kmods via `apk` | No (kernel ABI differs) | **Yes** |
| Driver base | Older vendor source | Current Armbian `cc2835a` + 25 patches |
| 5 GHz AP | Via DeepAQ's DS IE fix | Same fix, root cause found in the firmware |
| Memory safety | Vendor code as is | Fixed: ADDBA array overflow (190), sleeping allocation in atomic context (130), ADDBA/queue race (160), leaked card reference (220), stack VLAs (070) |
| Client list in LuCI | No `dump_station` in the vendor driver | Implemented (060) |
| Client statistics | Vendor driver returns the radio's own values for every client | Only what is really measured: host counters per client (150); no fake RSSI/rate (120, 140) |
| Firmware-crashing settings | Accepted | Blocked in cfg80211 (200) |
| Firmware crash | Vendor driver does not recover: Wi-Fi dead until reboot | Automatic driver reload, rate-limited (`uwe5622-recover`) |
| Name in LuCI | "Generic" | "Unisoc UWE5622" (iwinfo patch; also in the `iwinfo` CLI) |
| Board status | None | LuCI Overview panel: SoC temperatures, CPU frequency, Wi-Fi driver state and firmware, host vs firmware channel width, SDIO bus clock, firmware recoveries (`luci-app-opiz3-status`) |
| CPU frequency | Kernel default "performance" (always 1512 MHz) | `ondemand` by default; governor and min/max in LuCI System → CPU frequency (`/etc/config/opiz3`). No overclocking: the table stops at the SoC's 1512 MHz / 1.10 V, and Wi-Fi is limited by SDIO, not the CPU |
| Firmware internals | Unknown | Reverse engineered, published ([notes](docs/WCNMODEM-REVERSE-ENGINEERING.md)) |
| Build | Manual steps | CI: SDK + ImageBuilder, signed repo, image checks |

The firmware findings explain three long-standing problems:

1. **Why 5 GHz needed DeepAQ's fix.** The firmware takes the AP channel from
   the DS Parameter Set IE in the beacon. hostapd does not put that IE into
   5 GHz beacons (§44).
2. **Why some channel settings kill Wi-Fi until reboot.** The RF code asserts
   instead of rejecting a channel it cannot tune, and the vendor host driver
   does not recover (§45). Patch 200 and `uwe5622-recover` address both
   halves.
3. **Why LuCI shows no signal or rate per client.** No host command or event
   exports them in AP mode (§37–§43, §52). The firmware does track them in a
   per-station rate-control table, and the table index equals the hardware
   station LUT (§46–§49). Patch 230 reads that table over SDIO for diagnosis.

## What we are still working on

1. **Hardware confirmation of the latest series.**
   - Patches 240–280 (`cp_txrate=1` against what the phone reports).
   - Crash recovery (driver reload, then SDIO host reset).
   - The channel clamp.
   - VHT80 under sustained load (iperf3 over 12+ hours).
2. **Per-client RSSI and rate.**
   - TX rate: confirm `cp_txrate=1` against the phone's link rate, then make
     it the default.
   - RSSI: diff firmware memory near/far/near (`scripts/cp-mem-diff.sh`).
3. **Power save.** Find which transition (firmware PS, WCN sleep, SDIO wake)
   loses multicast or stalls, before enabling it again.
4. **Normal autoload.** Find why the SDIO probe can hang at boot, so the
   delayed-load workaround can go.
5. **A new driver.**
   - The vendor stack is about 76k lines.
   - A cfg80211 AP/STA driver for this firmware is planned at about 7–8k
     lines, with validation before anything reaches the firmware and
     in-kernel crash recovery.
   - Design and protocol map: [docs/NEW-DRIVER-ARCHITECTURE.md](docs/NEW-DRIVER-ARCHITECTURE.md).
   - This is also the only realistic path towards upstream.

## Driver patch series

Applied on top of `armbian/uwe5622@cc2835a` in
[`package/kernel/uwe5622/patches/`](package/kernel/uwe5622/patches/):

| Patch | Purpose |
|---|---|
| 010, 080 | OpenWrt cfg80211 backport API (`change_beacon`, `set_wiphy_params`) |
| 020 | External Kbuild configuration symbols |
| 030 | cfg80211-aware netdev registration and locking |
| 060 | `dump_station`: associated clients in `iw` and LuCI |
| 070 | Remove the remaining stack VLAs |
| 090 | `get_channel` and station details |
| 110 | Optional lean profile (no IBSS/NAN/RTT) |
| 120, 140 | Report only real per-station data and honest station flags |
| 130 | Non-sleeping TX pool growth; `tx_stats` debugfs |
| 150 | Host-side per-LUT traffic counters; `peer_stats` debugfs |
| 160 | Prepare ADDBA before queueing the data frame |
| 170 | Log the channel IEs of `START_AP` |
| 180 | DS Parameter Set IE for 5 GHz `START_AP` (after DeepAQ) |
| 190 | Fix an out-of-bounds write of per-TID ADDBA timestamps |
| 200 | Advertise only verified widths and channels (`max_bw_2g`, `max_bw_5g`, `allow_dfs`) |
| 210 | `rx_desc_dump` debugfs (RX descriptor survey) |
| 220 | Release the card reference on the `dt_rw_fail` early return |
| 230 | `cp_sta_table` debugfs: firmware per-station rate/RSSI state |
| 240 | Per-client TX rate from the firmware rate-control table (`cp_txrate=1`, off by default) |
| 250 | BSP: unregister the SDIO driver on Allwinner, so a driver reload works (no `-EBUSY`) |
| 260 | `cp_mem` debugfs: read-only dump of the firmware data area (RE) |
| 270 | Per-client bytes and packets (host counters) |
| 280 | Quiet `wifi up`: antenna and TX power "auto" accepted instead of `-95`, distance no longer sent to the firmware as an empty `SET_PARAM` (a possible source of `-12` on a healthy chip; a `-12` after a firmware assert is a dead chip and is not affected); phy MAC (no `00:00:00…`); TCP/UDP checksum features without the "mixed HW and IP checksum" warning |

Further pieces:

- **Kernel patch 900:**
  [`target/linux/sunxi/patches-6.12/`](target/linux/sunxi/patches-6.12/)
  adds the Wi-Fi nodes to the Zero 2 / Zero 3 device tree.
  [`scripts/zero3-dtb-add-wifi.py`](scripts/zero3-dtb-add-wifi.py) produces
  the same result on the official DTB.
- **iwinfo patch 900:** identifies platform Wi-Fi devices by modalias.
  The 25.12 `iwinfo` command line tool is a ucode script with its own
  device table; `uwe5622-iwinfo-name` (run at boot) adds the same modalias
  fallback there.
- **`luci-app-opiz3-status`:** a "Board" panel on Status → Overview. Data
  comes from an rpcd ucode plugin (`ubus call luci.opiz3 status`) that only
  reads sysfs/debugfs, never the chip. TX power is not shown anywhere as a
  number: the firmware takes it from its ini file and has no command to
  read it back, so LuCI keeps showing no value rather than an invented one.

## Building

Two workflows in `.github/workflows/`:

- **`build-ib.yml` (main).** Official SDK for the packages, official
  ImageBuilder for the image. It:
  - adds the Wi-Fi DTB to the prebuilt FIT kernel;
  - validates the image (packages, DTB inside the FIT, rootfs files, iwinfo);
  - publishes the signed repository to `gh-pages` and a rolling release.

  Packages are rebuilt only when `package/` or the package job changes.
  Otherwise the last signed repository is reused and a run takes a few
  minutes. Rebuilds start from a cached SDK `build_dir`. Manual-run inputs:
  `rebuild_packages`, `clean_sdk`.
- **`build-image.yml`.** Full source build with kernel patch 900, for
  development. Its kernel is not the official one, so official kmods do not
  install on it.

One-time setup for publishing:

1. Generate a signing key:
   `openssl ecparam -name prime256v1 -genkey -noout -out opiz3-wlan.key`.
2. Store its contents in the secret `APK_SIGN_KEY` (Settings → Secrets →
   Actions).
3. Settings → Pages → Deploy from branch `gh-pages`. The branch appears after
   the first publishing run.

## Diagnostics

On the board:

```sh
dmesg | grep -e sprdwl -e 'channel limits'
cat /sys/module/sprdwl_ng/parameters/max_bw_5g
iw dev; iw dev wlan0 station dump
logread -e uwe5622-recover
cat /sys/kernel/debug/sprdwl_debug/peer_stats     # host per-client counters
cat /sys/kernel/debug/sprdwl_debug/cp_sta_table   # firmware rate/RSSI table
```

From a PC, `scripts/collect-debug.sh <ip>` collects a full diagnostic bundle,
with the Wi-Fi keys masked. Attach it to an issue.

## Documentation

| Document | Contents |
|---|---|
| [WCNMODEM-REVERSE-ENGINEERING.md](docs/WCNMODEM-REVERSE-ENGINEERING.md) | Firmware reverse engineering, revisions 1–3 (§1–§55) |
| [NEW-DRIVER-ARCHITECTURE.md](docs/NEW-DRIVER-ARCHITECTURE.md) | New driver design, SDIO/command protocol map, milestones |
| [UWE5622-DRIVER-AUDIT.md](docs/UWE5622-DRIVER-AUDIT.md) | Audit of the vendor driver and the fix plan |
| [TECHNICAL-SPEC.md](docs/TECHNICAL-SPEC.md) | Requirements, acceptance tests, CI and package policy |
| [PORTING-NOTES.md](docs/PORTING-NOTES.md) | Porting decisions for OpenWrt 25.12 / Linux 6.12 |
| [HANDOFF.md](docs/HANDOFF.md) | Historical snapshot (2026-09-30) of the earlier work |
| [tools/wcnmodem-re.py](tools/wcnmodem-re.py) | Helper for the firmware analysis |

## Credits and license

- The UWE5622 driver: UNISOC, maintained by the Armbian project (GPL-2.0).
- The 5 GHz DS IE fix and the first OpenWrt integration: DeepAQ.
- OpenWrt packaging reference: rizkirmdhnnn.
- The forum build that showed what users need: Anieake.
- Footstrap theme: VizzleTF. AmneziaWG packages: 2Grey.

Patch authorship is kept in each patch. Everything in this repository is
GPL-2.0 ([LICENSE](LICENSE)). The firmware files are redistributed from
[armbian/firmware](https://github.com/armbian/firmware) under their own
terms.
