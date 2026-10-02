# Orange Pi Zero 3 WLAN backport for OpenWrt

Goal: make the onboard AW859A / UNISOC UWE5622 WLAN on Orange Pi Zero 3 behave like a normal OpenWrt radio on the OpenWrt 25.12 series.

## Targets

- OpenWrt 25.12.x / Linux 6.12
- 2.4 GHz and 5 GHz AP/STA operation
- cfg80211/nl80211 integration rather than vendor userspace glue
- working `iw dev wlan0 station dump` / LuCI associated-station list
- correct channel/frequency reporting
- reproducible package and image builds
- no edits inside `build_dir`

## Project scope

This repository builds on the community UWE5622 work rather than replacing it.

- **Armbian** maintains a broad, community-supported out-of-tree UWE5622 driver across multiple boards, transports and modern kernel releases. That work provides the current driver baseline used here.
- Earlier Orange Pi / GitHub ports, such as the Zero 3 Linux 6.x work, primarily solved board bring-up, DTS and vendor-driver API compatibility while keeping the original BSP code largely intact.
- **This project is narrower but deeper:** it focuses on making one difficult combination — Orange Pi Zero 3 + AW859A/UWE5622 + OpenWrt 25.12 — behave like a normal OpenWrt radio. Work therefore extends beyond kernel API porting into cfg80211/nl80211 semantics, AP station accounting, SDIO TX/RX correctness, delayed-probe safety, 5 GHz/VHT validation and reverse engineering of the closed Marlin3 firmware/host protocol.

The current effort should be treated as a small focused R&D project around a closed vendor radio stack, not merely as a kernel-version backport. See `docs/UWE5622-DRIVER-AUDIT.md` and `docs/WCNMODEM-REVERSE-ENGINEERING.md` for the evidence and current limitations.

## Development strategy

1. Reproduce a known buildable UWE5622 OpenWrt integration as a control baseline.
2. Rebase the driver onto the current `armbian/uwe5622` source.
3. Validate SDIO bring-up and 5 GHz AP operation.
4. Fix station enumeration and per-peer statistics where the firmware protocol permits it.
5. Stress-test reconnects, AP reloads, multicast and sustained traffic.

The development work lives on topic branches. `main` is kept as the project entry point until a tested baseline is ready.

## Credits and provenance

This project is downstream of several layers of vendor and community work. Directly carried or inherited work keeps its original authorship where available.

- **Spreadtrum / UNISOC** — original vendor WCN/WLAN BSP code from which the driver descends.
- **Armbian UWE5622 maintainers and contributors** — current source baseline used by this repository; the Armbian repository itself is forked from **EvilOlaf/uwe5622** and continues the modern-kernel maintenance effort.
- **jukeboge** — author of the directly carried OpenWrt compatibility patches `010`, `020` and `030`; their `From:` and `Signed-off-by:` lines are preserved verbatim.
- **Rizki Ramadhan** — author of the directly carried station/channel integration patches `060`, `080` and `090`; original authorship and `Signed-off-by:` lines are preserved. The related OpenWrt integration repository is linked below.
- **DeepAQ/openwrt-uwe5622-sunxi** — historical/reference implementation used to compare older OpenWrt integration and fixes. Its monolithic patch stack is not copied wholesale into the current package.
- **Doct2O/orangepi-zero3-mainline-linux-wifi** — reference for the earlier Orange Pi Zero 3 Linux 6.x bring-up and vendor-driver porting experience.
- **Orange Pi / Xunlong** — primary public provenance for the firmware files later mirrored by Armbian.

Later project-specific patches (`070`, `100`–`160`) are maintained in this repository and build on the above work. Where a patch is imported from another author, its original header and sign-off must remain intact.

## Upstream/reference sources

- OpenWrt: https://github.com/openwrt/openwrt
- Armbian UWE5622 driver: https://github.com/armbian/uwe5622
- Armbian firmware: https://github.com/armbian/firmware
- Existing OpenWrt integration reference: https://github.com/rizkirmdhnnn/openwrt-orangepi-zero3-wifi

Patch authorship and licensing are preserved when reference patches are imported.
