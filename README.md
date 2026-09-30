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

## Development strategy

1. Reproduce a known buildable UWE5622 OpenWrt integration as a control baseline.
2. Rebase the driver onto the current `armbian/uwe5622` source.
3. Validate SDIO bring-up and 5 GHz AP operation.
4. Fix station enumeration and per-peer statistics where the firmware protocol permits it.
5. Stress-test reconnects, AP reloads, multicast and sustained traffic.

The development work lives on topic branches. `main` is kept as the project entry point until a tested baseline is ready.

## Upstream/reference sources

- OpenWrt: https://github.com/openwrt/openwrt
- Armbian UWE5622 driver: https://github.com/armbian/uwe5622
- Armbian firmware: https://github.com/armbian/firmware
- Existing OpenWrt integration reference: https://github.com/rizkirmdhnnn/openwrt-orangepi-zero3-wifi

Patch authorship and licensing are preserved when reference patches are imported.
