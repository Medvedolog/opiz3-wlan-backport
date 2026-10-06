# Orange Pi Zero 3 — OpenWrt 25.12.5 with onboard Wi-Fi (UWE5622), beta 1

**Русский ниже / Russian below.**

Official OpenWrt 25.12.5 kernel: every kmod from downloads.openwrt.org
installs with `apk`. The Wi-Fi driver and our packages come from the signed
repository https://croissantpie12.github.io/opiz3-wlan-backport/ , which the
image already trusts.

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
  host width vs firmware width), System → CPU frequency (governor,
  `ondemand` by default), Travelmate.

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

Wi-Fi is **off** (as in stock OpenWrt): LuCI → Network → Wireless → Edit,
set an SSID and a WPA2 key, Enable. Set a root password
(System → Administration).

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
репозитория https://croissantpie12.github.io/opiz3-wlan-backport/ ,
образ ему уже доверяет.

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
  прошивки), System → CPU frequency (по умолчанию `ondemand`), Travelmate.

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

Wi-Fi **выключен** (как в стоковом OpenWrt): LuCI → Network → Wireless →
Edit, задайте SSID и пароль WPA2, Enable. Задайте пароль root
(System → Administration).

Обновление без перепрошивки: `apk update && apk upgrade && reboot`

## Если что-то не так

Создайте issue с `logread`, `dmesg | tail -100`,
`. /lib/uwe5622.sh; uwe_phy; uwe_radios` и описанием действий. Падения
прошивки видны в `logread` как `assert` или `recovering Wi-Fi`.
