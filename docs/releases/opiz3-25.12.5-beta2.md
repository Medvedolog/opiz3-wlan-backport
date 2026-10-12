# Orange Pi Zero 3 / Zero 2W / Zero 2 — OpenWrt 25.12.5 with onboard Wi-Fi (UWE5622), beta 2

**Русский ниже / Russian below.**

OpenWrt 25.12.5 with the official kernel, so every kmod from
downloads.openwrt.org installs with `apk`. The onboard Wi-Fi driver and the
project's packages come from its signed repository on GitHub Pages, which
the image already trusts. What is in the image and why:
[IMAGE-PACKAGES.md](https://github.com/Medvedolog/opiz3-wlan-backport/blob/main/docs/IMAGE-PACKAGES.md).

| Board | Image | State |
|---|---|---|
| Orange Pi Zero 3 (1 GB) | `xunlong_orangepi-zero3` | tested, release gate passed |
| Orange Pi Zero 2W (1 GB) | `xunlong_orangepi-zero2w` | tested by a user: boots, AP up, clients join |
| Orange Pi Zero 3 / Zero 2W 1.5 GB | same images | should boot (U-Boot 2026.04), not tested |
| Orange Pi Zero 2 | `xunlong_orangepi-zero2` | built, untested: testers wanted |

## What's new since beta 1

### Fixes

- **Ethernet after `reboot` (Zero 3).** After a warm reboot the port stayed
  dead until the power was cycled (`EMAC reset timeout`). Linux powers the
  PHY down when the interface goes down, and U-Boot 2026.04 no longer
  resets it at boot. Our U-Boot resets it again; `/etc/init.d/opiz3-emac`
  retries the controller as a fallback.
- **Access point on the first boot.** In beta 1 a first-boot race left the
  radio as OpenWrt's disabled default. Now the AP comes up by itself.
- **LTE modem at boot.** Starting Wi-Fi no longer restarts the modem
  interface while ModemManager is still probing it.
- **USB Wi-Fi adapters** are tied to their MAC and no longer appear as a
  new radio on every boot (USB bus numbers change between boots on
  H616/H618).

### Wi-Fi driver (kmod-uwe5622 r30)

- **Repeater (AP + client on one radio), experimental.** Each interface
  gets its own MAC (the driver passes the new interface's address to the
  firmware); OpenWrt no longer reuses interfaces of this radio.
- Patch 310: on a disconnect the driver waits for the firmware to finish
  before the interface is deleted (deleting earlier crashed the firmware).
- Patch 320: every interface step is logged as `sprdwl: lc ...`, to see
  where a Wi-Fi restart stops.
- Patch 330: fixes a vendor bug where a missed firmware heartbeat
  (loopcheck) blocked its own recovery; the firmware is now reset and
  Wi-Fi comes back.

### Boards and hardware

- **Orange Pi Zero 2W image.** Same Wi-Fi wiring as the Zero 3. No
  Ethernet on this board: join the `OPiZ2W` AP after the first boot.
- **1.5 GB boards.** Zero 3 and Zero 2W images carry U-Boot 2026.04, which
  detects 1.5 and 3 GB of RAM (beta 1 does not boot on 1.5 GB boards).
- **USB2 and USB3 enabled:** the two extra USB ports on the 13-pin header
  (Zero 2, Zero 3) and on the expansion board connector (Zero 2W). The
  upstream device tree leaves them off.

### Web interface and tools

- LuCI theme **Footstrap 0.14.14** in the project's warm dark palette.
  A paw-print background is installed but off: Footstrap menu ->
  Wallpaper -> Pattern, or `opiz3-pattern paws` (`opiz3-pattern off` to
  remove).
- **Board panel** (Status): temperature, CPU frequency, Wi-Fi clients and
  a warning while the AP still has the default password.
- `qmi-utils` (`qmicli`) for QMI modems, next to ModemManager.
- `scripts/collect-debug.sh`: one command on the board collects logs and
  configuration for a report, with passwords and keys masked.

## Verified on hardware

Release gate on the final image (Zero 3, 1 GB, 2026-10-11):

- first boot: AP `OPiZ3` on 5 GHz channel 36, LTE modem up, a phone joins;
- Ethernet and the AP after three `reboot`s, a power cycle and
  `sysupgrade -n -p`: no `EMAC reset timeout`, no firmware errors;
- LuCI over the cable ~20 s after boot, over the AP ~40 s;
- USB2/USB3: all four controllers come up; a device on the header pins was
  not tested.

Earlier on beta 2 test images: Zero 2W (5 GHz VHT80, clients join,
first-boot AP); repeater on the Zero 3 (client to a phone hotspot plus the
`OPiZ3` AP on one radio, separate MACs, LAN clients online through the
hotspot).

Not tested on hardware: 1.5 GB boards, USB Wi-Fi and USB Ethernet adapters,
the Zero 2 image.

## Known limitations

- **Repeater can hang the board.** With the AP and the client both on, a
  Wi-Fi restart (LuCI "Save & Apply" on the wireless page, `wifi`, the AP
  moving to the uplink's channel) froze the board in about one of ten
  restarts in a stress test; the watchdog reboots it after ~16 s. That
  figure was measured with a third-party modem service installed (next
  item) and is being rechecked without it. Change Wi-Fi settings with the
  client disabled, and put the AP on the uplink's channel: otherwise the
  chip moves the AP there and its clients reconnect.
- **Modem tools that rebind the modem's serial ports.** A service that
  unbinds and rebinds a USB modem's serial ports (`option` driver) while
  ModemManager holds them is a suspect (not proven) for random freezes,
  reboots and kernel oopses seen with several modems on a powered hub;
  the Wi-Fi driver and the hub's power are suspects too. Keep such a tool
  and ModemManager off the same ports. Dell DW5821e (413c:81e0): the
  image's usb-modeswitch rule sets its USB configuration to 0 again on
  every USB add event; being checked.
- **Country code only partly applied to the onboard Wi-Fi.** The kernel
  applies the country's channel limits (DE: channel 14 off, 149-165 at
  13 dBm), but the vendor driver knows only US, CN, NL, CZ, JP and TR and
  gives the firmware world rules for any other, and the beacon carries no
  country code. A fix is planned after beta 2.
- `channel auto` does not work for the AP: pick a channel.
- No per-client signal (RSSI) or RX rate in AP mode: the firmware does not
  report them.
- DFS channels (52-144), 160 MHz and 40 MHz on 2.4 GHz are blocked.
- Power: give the board its own 5 V 3 A supply. A board fed from the same
  hub as USB modems can freeze or reboot.

## Install

Two image types per board, both on microSD:

- `…-squashfs-sdcard.img.gz` (**recommended**): read-only base plus an
  overlay for your changes; `firstboot` returns to defaults.
- `…-ext4-sdcard.img.gz`: the whole root writable, more space for
  packages, no `firstboot`.

Write the `.img.gz` with balenaEtcher or Rufus (no need to unpack), insert,
power on. After ~40 s join the AP `OPiZ3` / `OPiZ2W` / `OPiZ2`, password
`12345678test`, or plug in a cable; LuCI is at http://192.168.1.1, user
`root`, no password. Set a root password and change the Wi-Fi password.

## Upgrade from beta 1 or a test build

Over the network, on the board. Keep the image type you have
(`mount | grep ' / '`: `overlay` = squashfs, `ext4` = ext4). Zero 3,
squashfs, keeping the settings:

    wget -O /tmp/fw.img.gz https://github.com/Medvedolog/opiz3-wlan-backport/releases/download/opiz3-25.12.5-beta2/openwrt-25.12.5-sunxi-cortexa53-xunlong_orangepi-zero3-squashfs-sdcard.img.gz
    sysupgrade -p /tmp/fw.img.gz

For the Zero 2W or Zero 2 replace `zero3` with `zero2w` or `zero2`; for
ext4 replace `squashfs` with `ext4`.

- `-p` is required: it writes the whole image including U-Boot. Without
  it OpenWrt 25.12.5's sysupgrade on sunxi leaves the old bootloader, and
  the Ethernet fix and 1.5 GB support are in the bootloader.
- Add `-n` to start from scratch (first boot again). Use it when switching
  between squashfs and ext4.
- `-O` in `wget` is required: without it the file is saved under the name
  of GitHub's redirect.

Packages only (driver, panel, theme), without a new image:
`apk update && apk upgrade && reboot`. This does not update U-Boot.

## Reporting a problem

On the board:

    wget -O /tmp/collect-debug.sh https://raw.githubusercontent.com/Medvedolog/opiz3-wlan-backport/main/scripts/collect-debug.sh
    sh /tmp/collect-debug.sh

Attach the archive it prints to an issue or to the
[reports discussion](https://github.com/Medvedolog/opiz3-wlan-backport/discussions/1),
with the board, the image and what you did. With a serial console
attached, add the last `sprdwl: lc` and `WCN` lines.

---

# По-русски

OpenWrt 25.12.5 с официальным ядром: любые kmod с downloads.openwrt.org
ставятся через `apk`. Драйвер встроенного Wi-Fi и пакеты проекта — из его
подписанного репозитория на GitHub Pages, образ ему уже доверяет. Что в
образе и зачем —
[IMAGE-PACKAGES.md](https://github.com/Medvedolog/opiz3-wlan-backport/blob/main/docs/IMAGE-PACKAGES.md).

| Плата | Образ | Состояние |
|---|---|---|
| Orange Pi Zero 3 (1 ГБ) | `xunlong_orangepi-zero3` | проверена, проверка перед выпуском пройдена |
| Orange Pi Zero 2W (1 ГБ) | `xunlong_orangepi-zero2w` | проверена пользователем: загружается, точка работает, клиенты подключаются |
| Zero 3 / Zero 2W на 1,5 ГБ | те же образы | должны загружаться (U-Boot 2026.04), не проверено |
| Orange Pi Zero 2 | `xunlong_orangepi-zero2` | собран, не проверен — нужны тестеры |

## Что нового по сравнению с beta 1

### Исправления

- **Ethernet после `reboot` (Zero 3).** После горячей перезагрузки порт
  оставался мёртвым до передёргивания питания (`EMAC reset timeout`).
  Linux выключает PHY, когда интерфейс опускается, а U-Boot 2026.04
  перестал сбрасывать его при старте. Наш U-Boot снова это делает,
  `/etc/init.d/opiz3-emac` — запасной путь.
- **Точка доступа при первой загрузке.** В beta 1 из-за гонки при первом
  старте радио оставалось стоковым и выключенным. Теперь точка поднимается
  сама.
- **LTE-модем при загрузке.** Запуск Wi-Fi больше не перезапускает
  интерфейс модема, пока ModemManager его опрашивает.
- **USB-свистки Wi-Fi** привязаны к своему MAC и больше не появляются новым
  радио при каждой загрузке (номера USB-шин на H616/H618 меняются).

### Драйвер Wi-Fi (kmod-uwe5622 r30)

- **Репитер (точка + клиент на одном радио), экспериментально.** У каждого
  интерфейса свой MAC (драйвер передаёт прошивке адрес нового интерфейса);
  OpenWrt больше не переиспользует интерфейсы этого радио.
- Патч 310: при отключении клиента драйвер ждёт, пока прошивка закончит,
  и только потом удаляет интерфейс (раньше это роняло прошивку).
- Патч 320: каждый шаг интерфейсов пишется в журнал как `sprdwl: lc ...` —
  видно, где остановился перезапуск Wi-Fi.
- Патч 330: исправлена ошибка производителя, из-за которой пропущенный
  контрольный ответ прошивки (loopcheck) блокировал её же восстановление;
  теперь прошивка сбрасывается, и Wi-Fi возвращается.

### Платы и железо

- **Образ для Orange Pi Zero 2W.** Разводка Wi-Fi та же, что у Zero 3.
  Ethernet на плате нет: после первой загрузки подключайтесь к точке
  `OPiZ2W`.
- **Платы на 1,5 ГБ.** В образах Zero 3 и Zero 2W стоит U-Boot 2026.04,
  который видит 1,5 и 3 ГБ памяти (beta 1 на таких платах не грузится).
- **Включены USB2 и USB3:** два дополнительных USB-порта на 13-контактной
  гребёнке (Zero 2, Zero 3) и на разъёме платы расширения (Zero 2W). В
  штатном описании платы они выключены.

### Веб-интерфейс и инструменты

- Тема LuCI **Footstrap 0.14.14** в тёплой тёмной палитре проекта. Фон с
  лапами установлен, но выключен: меню Footstrap -> Wallpaper -> Pattern,
  или `opiz3-pattern paws` (`opiz3-pattern off` — убрать).
- **Панель платы** (Состояние): температура, частота процессора, клиенты
  Wi-Fi и предупреждение, пока у точки стандартный пароль.
- `qmi-utils` (`qmicli`) для QMI-модемов, рядом с ModemManager.
- `scripts/collect-debug.sh`: одной командой на плате собирает журналы и
  настройки для отчёта, пароли и ключи скрыты.

## Проверено на железе

Проверка перед выпуском на финальном образе (Zero 3, 1 ГБ, 2026-10-11):

- первая загрузка: точка `OPiZ3` на 5 ГГц, канал 36, LTE-модем поднялся,
  телефон подключается;
- Ethernet и точка после трёх `reboot`, передёргивания питания и
  `sysupgrade -n -p`: без `EMAC reset timeout` и ошибок прошивки;
- LuCI по кабелю через ~20 с после загрузки, через точку через ~40 с;
- USB2/USB3: все четыре контроллера поднимаются; устройство на контактах
  гребёнки не проверялось.

Раньше на тестовых образах beta 2: Zero 2W (5 ГГц VHT80, клиенты, точка
при первой загрузке); репитер на Zero 3 (клиент к хотспоту телефона и
точка `OPiZ3` на одном радио, разные MAC, клиенты LAN выходят в интернет
через хотспот).

Не проверено на железе: платы на 1,5 ГБ, USB-свистки Wi-Fi и Ethernet,
образ Zero 2.

## Известные ограничения

- **Репитер может вешать плату.** Когда включены и точка, и клиент,
  перезапуск Wi-Fi («Сохранить и применить» на странице беспроводной сети,
  `wifi`, переезд точки на канал аплинка) в нагрузочном тесте вешал плату
  примерно в одном случае из десяти; watchdog перезагружает её через
  ~16 с. Цифра получена при установленной сторонней службе для модемов
  (следующий пункт) и перепроверяется без неё. Настройки Wi-Fi меняйте с
  выключенным клиентом, а канал точки ставьте равным каналу аплинка: иначе
  чип сам переведёт точку туда, и её клиенты переподключатся.
- **Утилиты для модемов, перепривязывающие их порты.** Служба, которая
  отвязывает и снова привязывает последовательные порты USB-модема
  (драйвер `option`), пока их держит ModemManager, может портить память
  ядра — это одна из версий (не доказана) случайных зависаний,
  перезагрузок и падений ядра с несколькими модемами на активном хабе;
  под подозрением также драйвер Wi-Fi и питание хаба. Не давайте такой
  утилите и ModemManager одни и те же порты. Dell DW5821e (413c:81e0):
  правило usb-modeswitch из образа заново ставит модему USB-конфигурацию 0
  при каждом подключении USB-устройства; разбираемся.
- **Страна применяется к встроенному Wi-Fi не полностью.** Ограничения
  каналов ядро применяет (DE: канал 14 выключен, 149–165 — 13 дБм), но
  драйвер производителя знает только US, CN, NL, CZ, JP и TR и для
  остальных стран отдаёт прошивке мировые правила, а в маяке нет кода
  страны. Исправление — после beta 2.
- `channel auto` для точки не работает: выберите канал.
- Нет уровня сигнала (RSSI) и скорости приёма клиентов в режиме точки:
  прошивка их не отдаёт.
- Каналы DFS (52–144), 160 МГц и 40 МГц на 2,4 ГГц закрыты.
- Питание: дайте плате свой блок 5 В 3 А. Плата, запитанная от одного хаба
  с USB-модемами, может зависать и перезагружаться.

## Установка

Для каждой платы два вида образа, оба для microSD:

- `…-squashfs-sdcard.img.gz` (**рекомендуется**): основа только для
  чтения плюс отдельный слой для ваших изменений; `firstboot` возвращает к
  заводским настройкам.
- `…-ext4-sdcard.img.gz`: весь корень доступен для записи, больше места
  под пакеты, без `firstboot`.

Запишите `.img.gz` через balenaEtcher или Rufus (распаковывать не нужно),
вставьте карту, включите. Через ~40 с подключитесь к точке `OPiZ3` /
`OPiZ2W` / `OPiZ2` с паролем `12345678test` или по кабелю; LuCI — на
http://192.168.1.1, пользователь `root` без пароля. Задайте пароль root и
смените пароль Wi-Fi.

## Обновление с beta 1 или тестовой сборки

По сети, прямо на плате. Оставайтесь на том же виде образа
(`mount | grep ' / '`: `overlay` — squashfs, `ext4` — ext4). Zero 3,
squashfs, с сохранением настроек:

    wget -O /tmp/fw.img.gz https://github.com/Medvedolog/opiz3-wlan-backport/releases/download/opiz3-25.12.5-beta2/openwrt-25.12.5-sunxi-cortexa53-xunlong_orangepi-zero3-squashfs-sdcard.img.gz
    sysupgrade -p /tmp/fw.img.gz

Для Zero 2W или Zero 2 замените `zero3` на `zero2w` или `zero2`; для ext4
замените `squashfs` на `ext4`.

- `-p` обязателен: записывает образ целиком, вместе с U-Boot. Без него
  sysupgrade OpenWrt 25.12.5 на sunxi оставляет старый загрузчик, а
  исправление Ethernet и поддержка 1,5 ГБ — именно в загрузчике.
- `-n` — начать с нуля (снова первая загрузка). Нужен при переходе между
  squashfs и ext4.
- `-O` в `wget` обязателен: без него файл сохранится под именем из адреса
  переадресации GitHub.

Только пакеты (драйвер, панель, тема), без нового образа:
`apk update && apk upgrade && reboot`. U-Boot так не обновляется.

## Если что-то не так

На плате:

    wget -O /tmp/collect-debug.sh https://raw.githubusercontent.com/Medvedolog/opiz3-wlan-backport/main/scripts/collect-debug.sh
    sh /tmp/collect-debug.sh

Приложите архив, путь к которому он выведет, к issue или в
[обсуждение для отчётов](https://github.com/Medvedolog/opiz3-wlan-backport/discussions/1),
с платой, образом и описанием действий. Если подключён UART — добавьте
последние строки `sprdwl: lc` и `WCN`.
