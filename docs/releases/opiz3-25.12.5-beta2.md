# Orange Pi Zero 3 / Zero 2W / Zero 2 — OpenWrt 25.12.5 with onboard Wi-Fi (UWE5622), beta 2

**Русский ниже / Russian below.**

Official OpenWrt 25.12.5 kernel: every kmod from downloads.openwrt.org
installs with `apk`. The Wi-Fi driver and our packages come from the signed
package repository of this project (GitHub Pages), which the image already
trusts. What is in the image and why:
[docs/IMAGE-PACKAGES.md](https://github.com/Medvedolog/opiz3-wlan-backport/blob/main/docs/IMAGE-PACKAGES.md).

## New since beta 1

- **Repeater (access point and client on one radio).** Each interface now
  gets its own MAC: the driver takes the address of a new interface
  (`NL80211_FEATURE_MAC_ON_CREATE`) and passes it to the firmware, and
  OpenWrt no longer reuses (renames) interfaces of this radio. Put the
  access point on the uplink's channel.
- **Access point on the first boot, for real.** In beta 1 a first-boot race
  left the radio as OpenWrt's disabled default. The AP is named after the
  board: `OPiZ3`, `OPiZ2W`, `OPiZ2`; password `12345678test` — change it.
- **Orange Pi Zero 2W image.** Same Wi-Fi wiring as the Zero 3 (vendor device
  tree checked). No Ethernet on this board: join the `OPiZ2W` AP.
- **1.5 GB boards.** Zero 3 and Zero 2W images carry U-Boot 2026.04, which
  detects 1.5 and 3 GB of RAM (OpenWrt's U-Boot 2025.01 does not: beta 1
  does not boot on 1.5 GB boards).
- **USB Wi-Fi adapters** are tied to their MAC and no longer added as a new
  radio on every boot (the H616/H618 USB bus numbers change between boots).
- Docs: where the chip, firmware and driver come from and under which
  terms; the firmware is a TV-box build (`sc2355_marlin3_lite_ott`), which
  explains most of its access point limits.

## Verified on hardware

- Everything listed for beta 1 (Zero 3).
- Zero 2W (1 GB): boots, Wi-Fi up, AP on 5 GHz VHT80, a client joins; the
  first-boot AP came up by itself.
- Zero 3 (1 GB): boots with U-Boot 2026.04; `sysupgrade -n -p` over the
  network from the r19 test image; the first-boot AP came up by itself
  (5 GHz channel 36, VHT80, 34 s after power-on).
- Repeater on the Zero 3: client to a phone hotspot and the `OPiZ3` AP on
  one radio, 2.4 GHz channel 1, separate MACs (`1c:79:…` AP, `1e:79:…`
  client); LAN clients reach the internet through the hotspot.
- TO BE FILLED IN BEFORE RELEASE: 1.5 GB board, USB adapter.

## Known limitations

- Repeater: set the radio channel to the uplink's channel. When the uplink
  is on another channel the chip moves the AP to it (seen once in testing);
  clients of the AP may drop and have to reconnect.
- Repeater: during testing the board hung once on `firewall reload` and
  rebooted once by itself shortly after boot, both with the client
  interface up; not reproduced yet, under investigation.
- `channel auto` does not work for the AP; pick a channel.
- No per-client signal (RSSI) and RX rate in AP mode; the firmware does
  not report them.
- The Country element (802.11d) may not be broadcast even with a country
  set: the beacon is assembled in the chip's ROM. Channels and power still
  follow the country.
- DFS channels (52–144), 160 MHz and 40 MHz on 2.4 GHz are blocked.
- Orange Pi Zero 2 image: built, untested — testers wanted.

## Install or upgrade

Fresh install: write the `…-squashfs-sdcard.img.gz` of your board to a
microSD card.

From beta 1 without a card:

    wget -O /tmp/fw.img.gz <link to the image of this release>
    sysupgrade -n -p /tmp/fw.img.gz

`-O` is needed: OpenWrt's `wget` follows GitHub's redirect and would save
the file under the redirect's name.

`-p` writes the whole image including the bootloader: without it
OpenWrt 25.12.5's sysupgrade on sunxi does not write U-Boot. `-n` starts
from scratch (first boot again); drop it to keep the settings.

Packages only (driver, panel): `apk update && apk upgrade && reboot`.

## Reporting a problem

Issues on GitHub with `logread`, `dmesg | tail -100`,
`. /lib/uwe5622.sh; uwe_phy; uwe_radios` and what you did.

---

# По-русски

Официальное ядро OpenWrt 25.12.5: любые kmod с downloads.openwrt.org
ставятся через `apk`. Драйвер Wi-Fi и наши пакеты — из подписанного
репозитория проекта (GitHub Pages), образ ему уже доверяет. Что в образе и
зачем — [docs/IMAGE-PACKAGES.md](https://github.com/Medvedolog/opiz3-wlan-backport/blob/main/docs/IMAGE-PACKAGES.md).

## Что нового по сравнению с beta 1

- **Репитер (точка доступа и клиент на одном радио).** У каждого интерфейса
  теперь свой MAC: драйвер принимает адрес нового интерфейса и передаёт его
  прошивке, а OpenWrt больше не переиспользует интерфейсы этого радио.
  Канал точки ставьте равным каналу аплинка.
- **Точка доступа при первой загрузке теперь действительно поднимается.** В
  beta 1 из-за гонки при первом старте радио оставалось стоковым и
  выключенным. Имя сети — по плате: `OPiZ3`, `OPiZ2W`, `OPiZ2`; пароль
  `12345678test` — смените его.
- **Образ для Orange Pi Zero 2W.** Разводка Wi-Fi та же, что у Zero 3
  (сверено с device tree вендора). Ethernet на плате нет: подключайтесь к
  точке `OPiZ2W`.
- **Платы с 1,5 ГБ.** В образах Zero 3 и Zero 2W стоит U-Boot 2026.04,
  который умеет 1,5 и 3 ГБ памяти (U-Boot 2025.01 из OpenWrt — нет: beta 1
  на таких платах не загружается).
- **USB-свистки Wi-Fi** привязываются к своему MAC и больше не добавляются
  новым радио при каждой загрузке (на H616/H618 номера USB-шин меняются).
- Документация: откуда чип, прошивка и драйвер и под какими лицензиями;
  прошивка собрана для ТВ-приставок (`sc2355_marlin3_lite_ott`) — отсюда
  большинство ограничений режима точки доступа.

## Проверено на железе

- Всё, что было в beta 1 (Zero 3).
- Zero 2W (1 ГБ): загружается, Wi-Fi работает, точка на 5 ГГц VHT80,
  клиент подключается; точка при первой загрузке поднялась сама.
- Zero 3 (1 ГБ): загружается с U-Boot 2026.04; `sysupgrade -n -p` по сети с
  тестового образа r19; точка при первой загрузке поднялась сама (5 ГГц,
  канал 36, VHT80, через 34 с после включения).
- Репитер на Zero 3: клиент к хотспоту телефона и точка `OPiZ3` на одном
  радио, 2,4 ГГц канал 1, разные MAC (`1c:79:…` точка, `1e:79:…` клиент);
  клиенты LAN выходят в интернет через хотспот.
- ЗАПОЛНИТЬ ПЕРЕД ВЫПУСКОМ: плата на 1,5 ГБ, USB-свисток.

## Известные ограничения

- Репитер: канал радио ставьте равным каналу аплинка. Если аплинк на
  другом канале, чип переводит точку на него (замечено один раз); клиенты
  точки при этом могут отвалиться и переподключиться.
- Репитер: в тестах плата один раз зависла на `firewall reload` и один раз
  сама перезагрузилась вскоре после старта, оба раза с поднятым клиентом;
  пока не воспроизведено, разбираемся.
- `channel auto` для точки не работает — выберите канал.
- Нет уровня сигнала (RSSI) и RX-скорости клиентов в режиме точки:
  прошивка их не отдаёт.
- Элемент Country (802.11d) может не передаваться в эфир даже при заданной
  стране: маяк собирает ПЗУ чипа. Каналы и мощность всё равно по стране.
- Каналы DFS (52–144), 160 МГц и 40 МГц на 2.4 ГГц закрыты.
- Образ Orange Pi Zero 2 собран, но не проверен — нужны тестеры.

## Установка и обновление

Новая установка: запишите `…-squashfs-sdcard.img.gz` своей платы на
microSD.

С beta 1 без карты:

    wget -O /tmp/fw.img.gz <ссылка на образ этого релиза>
    sysupgrade -n -p /tmp/fw.img.gz

`-O` обязателен: `wget` в OpenWrt после переадресации GitHub сохраняет
файл под именем из адреса переадресации.

`-p` записывает образ целиком, вместе с загрузчиком: без него sysupgrade
OpenWrt 25.12.5 на sunxi U-Boot не обновляет. `-n` — с нуля (снова первая
загрузка); без него настройки сохранятся.

Только пакеты (драйвер, панель): `apk update && apk upgrade && reboot`.

## Если что-то не так

Issue на GitHub с `logread`, `dmesg | tail -100`,
`. /lib/uwe5622.sh; uwe_phy; uwe_radios` и описанием действий.
