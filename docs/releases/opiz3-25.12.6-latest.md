# Orange Pi Zero 3, Zero 2W and Zero 2: OpenWrt 25.12.6 with UWE5622 Wi-Fi

[По-русски](#по-русски) · [Changelog](../../CHANGELOG.md) · [GitHub pre-release](https://github.com/Medvedolog/opiz3-wlan-backport/releases/tag/opiz3-25.12.6-latest)

Published 2026-10-29 from [`e38db9b327e357c668e184cf96a8d628eafeea40`](https://github.com/Medvedolog/opiz3-wlan-backport/commit/e38db9b327e357c668e184cf96a8d628eafeea40) for `sunxi/cortexa53`. This is a project **pre-release** built on official OpenWrt **25.12.6**, not an OpenWrt distribution image. It uses Linux **6.12.112** and the **6.18.55** mac80211 backport; the H618 images retain U-Boot **2026.04**. The sunxi sysupgrade method did not change.

The project's [signed 25.12.6 APK feed](https://medvedolog.github.io/opiz3-wlan-backport/25.12.6/sunxi-cortexa53/packages.adb) includes UWE5622 and the extra packages. The [25.12.5 feed](https://medvedolog.github.io/opiz3-wlan-backport/25.12.5/sunxi-cortexa53/packages.adb) remains available for existing installations. Match both official kmods and the project's feed to your installed OpenWrt version; changing the feed alone does not upgrade the firmware.

## Downloads

| Board | squashfs microSD | ext4 microSD |
| --- | --- | --- |
| Orange Pi Zero 3 | [squashfs][z3-s] | [ext4][z3-e] |
| Orange Pi Zero 2W | [squashfs][z2w-s] | [ext4][z2w-e] |
| Orange Pi Zero 2 | [squashfs][z2-s] | [ext4][z2-e] |

The same release contains the matching [x86-64 Linux ImageBuilder][ib], [SHA-256 checksums][sums], one package manifest per board, and a CycloneDX SBOM for Zero 3. For testing, check the checksum and boot from a spare microSD before replacing a working system.

## Validation

The [image CI][image-ci] and [package CI][packages-ci] succeeded for the published commit. The GitHub release description mentions board testing in general; published detailed hardware results are for [25.12.5 beta 2](opiz3-25.12.5-beta2.md) and its [later test reports](../TEST-PLAN.md). They are useful baseline evidence, not a repeat of the hardware tests on these exact 25.12.6 binaries. First boot, Wi-Fi association and sustained traffic, Ethernet after reboot where applicable, and any upgrade path should be checked on your board.

## По-русски

[История изменений](../../CHANGELOG.ru.md) · [Предрелиз на GitHub](https://github.com/Medvedolog/opiz3-wlan-backport/releases/tag/opiz3-25.12.6-latest)

Предрелиз опубликован 29 октября 2026 года из коммита `e38db9b327e357c668e184cf96a8d628eafeea40` для `sunxi/cortexa53`. Это сборка проекта на официальной базе OpenWrt **25.12.6**, а не официальный образ OpenWrt. Ядро **6.12.112**, бэкпорт mac80211 **6.18.55**. В образах для H618 сохранён U-Boot **2026.04**; способ sysupgrade на sunxi не изменился.

[Подписанный APK-репозиторий 25.12.6](https://medvedolog.github.io/opiz3-wlan-backport/25.12.6/sunxi-cortexa53/packages.adb) содержит UWE5622 и дополнительные пакеты. [Репозиторий 25.12.5](https://medvedolog.github.io/opiz3-wlan-backport/25.12.5/sunxi-cortexa53/packages.adb) остаётся доступен. И официальные модули ядра, и APK-репозиторий проекта должны соответствовать установленной версии OpenWrt. Смена адреса репозитория не обновляет прошивку.

Образы ext4 и squashfs для трёх плат перечислены в таблице выше. Также доступны [ImageBuilder для Linux x86-64][ib], [контрольные суммы SHA-256][sums], отдельный список пакетов для каждой платы и CycloneDX SBOM для Zero 3. Для первой проверки сверьте SHA-256 и загрузитесь с запасной microSD.

[Сборка образов][image-ci] и [сборка пакетов][packages-ci] для опубликованного коммита прошли в CI. В описании релиза есть общие отметки о проверках плат, но подробные результаты относятся к [25.12.5 beta 2](opiz3-25.12.5-beta2.md) и [последующим отчётам](../TEST-PLAN.md), а не к отдельным испытаниям опубликованных образов 25.12.6. На своей плате проверьте первую загрузку, подключение клиентов и передачу данных по Wi-Fi, Ethernet после перезагрузки (если есть) и нужный вам сценарий обновления.

[z3-s]: https://github.com/Medvedolog/opiz3-wlan-backport/releases/download/opiz3-25.12.6-latest/openwrt-25.12.6-sunxi-cortexa53-xunlong_orangepi-zero3-squashfs-sdcard.img.gz
[z3-e]: https://github.com/Medvedolog/opiz3-wlan-backport/releases/download/opiz3-25.12.6-latest/openwrt-25.12.6-sunxi-cortexa53-xunlong_orangepi-zero3-ext4-sdcard.img.gz
[z2w-s]: https://github.com/Medvedolog/opiz3-wlan-backport/releases/download/opiz3-25.12.6-latest/openwrt-25.12.6-sunxi-cortexa53-xunlong_orangepi-zero2w-squashfs-sdcard.img.gz
[z2w-e]: https://github.com/Medvedolog/opiz3-wlan-backport/releases/download/opiz3-25.12.6-latest/openwrt-25.12.6-sunxi-cortexa53-xunlong_orangepi-zero2w-ext4-sdcard.img.gz
[z2-s]: https://github.com/Medvedolog/opiz3-wlan-backport/releases/download/opiz3-25.12.6-latest/openwrt-25.12.6-sunxi-cortexa53-xunlong_orangepi-zero2-squashfs-sdcard.img.gz
[z2-e]: https://github.com/Medvedolog/opiz3-wlan-backport/releases/download/opiz3-25.12.6-latest/openwrt-25.12.6-sunxi-cortexa53-xunlong_orangepi-zero2-ext4-sdcard.img.gz
[ib]: https://github.com/Medvedolog/opiz3-wlan-backport/releases/download/opiz3-25.12.6-latest/openwrt-imagebuilder-25.12.6-sunxi-cortexa53.Linux-x86_64-opiz3.tar.zst
[sums]: https://github.com/Medvedolog/opiz3-wlan-backport/releases/download/opiz3-25.12.6-latest/sha256sums
[image-ci]: https://github.com/Medvedolog/opiz3-wlan-backport/actions/runs/40950266131
[packages-ci]: https://github.com/Medvedolog/opiz3-wlan-backport/actions/runs/40950265989
