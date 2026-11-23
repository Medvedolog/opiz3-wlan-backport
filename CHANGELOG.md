# Changelog

[По-русски](CHANGELOG.ru.md)

## OpenWrt 25.12.6 rolling pre-release — 2026-10-29

- Rebuilt on official OpenWrt 25.12.6: Linux **6.12.112**, mac80211 backport **6.18.55**. The H618 images retain the project's U-Boot 2026.04 build; sunxi sysupgrade behavior is unchanged.
- Published ext4 and squashfs microSD images for Zero 3, Zero 2W and Zero 2, a matching x86-64 ImageBuilder, manifests, and checksums from `e38db9b`.
- The signed 25.12.6 APK feed is published alongside the retained 25.12.5 feed. Use the feed matching the installed OpenWrt version; do not mix kmods across versions.
- CI build evidence is available for this exact release. Detailed hardware results are from **25.12.5 beta 2**, not a new 25.12.6 acceptance run.

[Release notes and downloads](docs/releases/opiz3-25.12.6-latest.md)

## OpenWrt 25.12.5

- [Rolling pre-release](https://github.com/Medvedolog/opiz3-wlan-backport/releases/tag/opiz3-25.12.5-latest): LuCI now reports unknown per-client signal as unknown, and ships the AmneziaWG 2.0/3.1 page.
- [Beta 2](docs/releases/opiz3-25.12.5-beta2.md): fixed first-boot AP and Zero 3 Ethernet after reboot; added the Zero 2W image and updated UWE5622 recovery. AP+STA repeater mode remained experimental. [Hardware test records](docs/TEST-PLAN.md) include later Zero 2 reports.
- [Beta 1](docs/releases/opiz3-25.12.5-beta1.md): initial beta on the official OpenWrt kernel with onboard UWE5622 Wi-Fi and a signed project APK feed.
