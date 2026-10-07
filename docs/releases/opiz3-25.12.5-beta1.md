# Orange Pi Zero 3 — OpenWrt 25.12.5 with onboard Wi-Fi (UWE5622), beta 1

**Русский ниже / Russian below.**

Official OpenWrt 25.12.5 kernel: every kmod from downloads.openwrt.org
installs with `apk`. The Wi-Fi driver and our packages come from the signed
package repository of this project (GitHub Pages), which the image already
trusts.

## Verified on hardware (Zero 3)

- 5 GHz access point, channel 36, **VHT80** (default): clients at
  VHT-MCS 9 / 433 Mbit/s; 1 h+ without a firmware crash. Throughput is
  limited to about 160 Mbit/s by the SDIO bus.
- 2.4 GHz access point (HT20).
- **Client mode** on 2.4 GHz (e.g. a phone hotspot as the uplink):
  reconnects by itself when the uplink comes back.
- **LTE modem as the uplink** (QMI modem via ModemManager), Wi-Fi for the
  clients. `modem` and `wwan` interfaces are in the wan zone out of the box.
- Client list with per-client bytes and packets; per-client TX rate with
  `cp_txrate=1` in `/etc/uwe5622.options`.
- Firmware crash recovery without a reboot (~14 s).
- "Board" panel on Status → Overview (temperatures, CPU, Wi-Fi driver,
  host width vs firmware width, Wi-Fi clients table: name, IP, MAC,
  bytes, TX rate, connected time), System → CPU frequency (governor,
  `ondemand` by default), Travelmate.
- Access point on the first boot (see "After flashing").

What is in the image and why:
[docs/IMAGE-PACKAGES.md](https://github.com/Medvedolog/opiz3-wlan-backport/blob/main/docs/IMAGE-PACKAGES.md).

## Known limitations

- **AP and client at the same time (repeater) does not work**: clients see
  the AP but cannot join. Use client mode with Ethernet for the LAN, or the
  AP with an LTE/Ethernet uplink. Fix planned for beta 2.
- No per-client signal (RSSI) and no RX rate in AP mode: the firmware does
  not report them. TX power is not shown either.
- DFS channels (52–144), 160 MHz and 40 MHz on 2.4 GHz are blocked
  (untested). `channel auto` does not work for the AP; pick a channel.
- Orange Pi Zero 2 image: built, untested — testers wanted.

## After flashing

The board starts a Wi-Fi access point: SSID **`OPiZ3`**, 5 GHz channel 36,
WPA2, password **`12345678test`**. Connect to it and open
http://192.168.1.1.

If the radio shows up as `OpenWrt`, disabled (seen on a clean flash: a
first-boot race, fixed in beta 2), run `/usr/sbin/uwe5622-default-ap;
wifi` once, or set an SSID and key in LuCI → Network → Wireless.

**This password is public: change it right away** (LuCI → Network →
Wireless → Edit → Wireless Security). Until then the "Board" panel shows a
warning. Set a root password (System → Administration).

Upgrade an existing install without reflashing:
`apk update && apk upgrade && reboot`

## Reporting a problem

Open an issue with `logread`, `dmesg | tail -100`,
`. /lib/uwe5622.sh; uwe_phy; uwe_radios` and what you did. Firmware
crashes show as `assert` or `recovering Wi-Fi` in `logread`.

---

# По-русски

Официальное ядро OpenWrt 25.12.5: любые kmod с downloads.openwrt.org
ставятся через `apk`. Драйвер Wi-Fi и наши пакеты — из подписанного
репозитория пакетов проекта (GitHub Pages), образ ему уже доверяет.

## Проверено на железе (Zero 3)

- Точка доступа 5 ГГц, канал 36, **VHT80** (по умолчанию): клиенты на
  VHT-MCS 9 / 433 Мбит/с, больше часа без падений прошивки. Реальная
  скорость упирается в шину SDIO — около 160 Мбит/с.
- Точка доступа 2.4 ГГц (HT20).
- **Режим клиента** на 2.4 ГГц (например, хотспот телефона как интернет),
  сам переподключается.
- **LTE-модем как интернет** (QMI, ModemManager), раздача по Wi-Fi.
  Интерфейсы `modem` и `wwan` уже в зоне wan.
- Список клиентов с байтами и пакетами; TX-скорость клиента —
  `cp_txrate=1` в `/etc/uwe5622.options`.
- Восстановление после падения прошивки без перезагрузки (~14 с).
- Панель «Board» на главной (температуры, CPU, драйвер, ширина хоста и
  прошивки, таблица Wi-Fi клиентов: имя, IP, MAC, байты, TX-скорость,
  время подключения), System → CPU frequency (по умолчанию `ondemand`),
  Travelmate.
- Точка доступа сразу после прошивки (см. «После прошивки»).

Что в образе и зачем:
[docs/IMAGE-PACKAGES.md](https://github.com/Medvedolog/opiz3-wlan-backport/blob/main/docs/IMAGE-PACKAGES.md).

## Известные ограничения

- **Точка доступа и клиент одновременно (репитер) не работают**: сеть
  видна, но клиенты не подключаются. Используйте клиент + LAN по кабелю или
  точку доступа + LTE/кабель. Исправление — в beta 2.
- Нет уровня сигнала (RSSI) и RX-скорости клиентов в режиме точки
  доступа: прошивка их не отдаёт. Мощность передатчика тоже не
  показывается.
- Каналы DFS (52–144), 160 МГц и 40 МГц на 2.4 ГГц закрыты (не
  проверены). `channel auto` для точки доступа не работает — выберите
  канал.
- Образ для Orange Pi Zero 2 собран, но не проверен — нужны тестеры.

## После прошивки

Плата сама поднимает точку доступа: SSID **`OPiZ3`**, 5 ГГц, канал 36,
WPA2, пароль **`12345678test`**. Подключитесь и откройте
http://192.168.1.1.

Если радио появилось как `OpenWrt` и выключено (бывает на чистой
прошивке: гонка при первой загрузке, исправлено в beta 2), выполните один
раз `/usr/sbin/uwe5622-default-ap; wifi` или задайте SSID и пароль в
LuCI → Network → Wireless.

**Пароль публичный — смените его сразу** (LuCI → Network → Wireless →
Edit → Wireless Security). Пока не сменён, в блоке «Board» висит
предупреждение. Задайте пароль root (System → Administration).

Обновление без перепрошивки: `apk update && apk upgrade && reboot`

## Если что-то не так

Создайте issue с `logread`, `dmesg | tail -100`,
`. /lib/uwe5622.sh; uwe_phy; uwe_radios` и описанием действий. Падения
прошивки видны в `logread` как `assert` или `recovering Wi-Fi`.
