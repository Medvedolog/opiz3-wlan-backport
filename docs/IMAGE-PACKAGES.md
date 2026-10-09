# What is in the image and why

The image is the official OpenWrt 25.12.5 ImageBuilder output for
`xunlong_orangepi-zero3` (and `-zero2`) with the package set from
`.github/workflows/build-ib.yml` (step "Build image"). The board is meant as a
small travel router: uplink over LTE modem, Wi-Fi client or USB Ethernet,
clients over the onboard Wi-Fi, optionally through a VPN. Everything on this
list is either needed for that or for diagnosing the Wi-Fi; anything else
installs with `apk` from the official repositories or ours.

**Русский ниже / Russian below.**

## Our packages (signed apk repository of this project)

| Package | Why |
|---|---|
| `kmod-uwe5622`, `uwe5622-firmware` | Onboard Wi-Fi: patched driver, firmware, recovery and channel-width clamp scripts, ModemManager ignore rule, first-boot AP (r18) |
| `iwinfo`, `libiwinfo`, `libiwinfo-data` | Rebuilt so LuCI and the `iwinfo` CLI show "Unisoc UWE5622" instead of "Generic" |
| `luci-app-opiz3-status` | "Board" panel (temperatures, CPU, Wi-Fi driver/firmware state, clients table) and System → CPU frequency |
| `luci-theme-footstrap` | Default LuCI theme (mobile-friendly); `luci-theme-bootstrap` stays as a fallback |
| `kmod-amneziawg`, `amneziawg-tools`, `luci-app-amneziawg` | WireGuard with obfuscation, for networks where plain WireGuard is blocked; built against the official kernel, so it is not in the official feed |

## Official packages

| Group | Packages | Why |
|---|---|---|
| Wi-Fi | `wpad-basic-mbedtls`, `wireless-regdb`, `iw`, `iwinfo` | WPA2/WPA3 AP and client, regulatory data, diagnostics |
| Travel uplink | `travelmate`, `luci-app-travelmate` | Picks and rejoins known hotspots in client mode |
| USB Wi-Fi | `kmod-mt7601u`, `kmod-mt76x0u`, `kmod-mt76x2u`, `kmod-mt7921u`, `kmod-mt7925u`, `kmod-rt2800-usb`, `kmod-rt73-usb`, `kmod-rtl8xxxu`, `kmod-rtl8192cu`, `kmod-rtw88-*u`, `kmod-ath9k-htc`, `kmod-ath6kl-usb`, `kmod-brcmfmac` | A second radio over USB (e.g. a separate client while the onboard Wi-Fi is the AP), without needing network access first to install a driver |
| LTE/3G modems | `modemmanager`, `qmi-utils` (`qmicli`), `uqmi`, `umbim`, `usb-modeswitch`, `comgt`, `comgt-ncm`, `kmod-usb-net-qmi-wwan`, `-cdc-mbim`, `-cdc-ncm`, `-rndis`, `-cdc-ether`, `-cdc-eem`, `-cdc-subset`, `kmod-usb-serial*`, `kmod-usb-acm`, `ppp`, `chat`, `luci-proto-qmi`, `-mbim`, `-ncm`, `-modemmanager` | Any common USB modem works as the uplink out of the box; `modem` and `wwan` are in the wan zone by default |
| USB Ethernet | `kmod-usb-net-rtl8152`, `-asix`, `-asix-ax88179`, `-smsc95xx`, `-lan78xx`, `-dm9601-ether`, `-sr9700`, `kmod-mii` | Second wired port (the board has one) |
| USB core | `kmod-usb-core`, `kmod-usb2`, `kmod-usb3` | Host ports |
| VPN | `kmod-wireguard`, `wireguard-tools`, `luci-proto-wireguard`, `kmod-tun` | Plain WireGuard; TUN for userspace VPNs and sing-box |
| Proxy routing | `sing-box`, `kmod-nft-tproxy`, `kmod-nf-tproxy`, `kmod-nft-socket`, `kmod-nft-nat`, `nftables-json`, `curl`, `jq`, `ca-bundle`, `coreutils-base64`, `bind-dig`, `kmod-inet-diag`, `kmod-netlink-diag` | Selective routing of traffic through a proxy (transparent proxy with nftables); the tools are what such setups expect to find |
| ucode | `ucode`, `ucode-mod-fs`, `ucode-mod-uci` | Used by the "Board" panel backend (rpcd ucode plugin: `fs`, `uci`) |
| LuCI | `luci`, `luci-ssl` | Web UI over HTTPS |
| Diagnostics | `usbutils`, `pciutils`, `picocom`, `coreutils`, `coreutils-timeout`, `coreutils-stty`, `ethtool`, `ip-full`, `ip-bridge`, `tcpdump`, `lsof`, `strace`, `iperf3`, `htop` | Debugging modems (`picocom` for AT commands), Wi-Fi throughput (`iperf3`), driver issues; `timeout` is used by our Wi-Fi scripts |

## Not in the image on purpose

- OpenVPN (the image check fails if it gets in): heavy, and WireGuard/AmneziaWG cover the use case.
- mwan3, watchcat, nlbwmon: install with `apk` if needed.
- Bluetooth: outside this project.

## Image changes beyond packages

- Wi-Fi nodes added to the device tree inside the kernel FIT image.
- Our apk key and repository address (`/etc/apk/repositories.d/customfeeds.list`).
- Footstrap set as the default theme.
- `modem` and `wwan` added to the wan firewall zone.

---

# По-русски

Образ — официальный ImageBuilder OpenWrt 25.12.5 с набором пакетов из
`.github/workflows/build-ib.yml` (шаг «Build image»). Плата задумана как
маленький роутер в дорогу: интернет через LTE-модем, Wi-Fi-клиент или
USB-Ethernet, раздача по встроенному Wi-Fi, при желании через VPN. В образе
только то, что нужно для этого и для диагностики Wi-Fi; остальное ставится
через `apk`.

## Наши пакеты (подписанный apk-репозиторий проекта)

| Пакет | Зачем |
|---|---|
| `kmod-uwe5622`, `uwe5622-firmware` | Встроенный Wi-Fi: исправленный драйвер, прошивка, скрипты восстановления и урезания ширины, правило для ModemManager, точка доступа при первом запуске (r18) |
| `iwinfo`, `libiwinfo`, `libiwinfo-data` | Пересобраны, чтобы LuCI и `iwinfo` показывали «Unisoc UWE5622», а не «Generic» |
| `luci-app-opiz3-status` | Панель «Board» (температуры, CPU, драйвер и прошивка Wi-Fi, таблица клиентов) и System → CPU frequency |
| `luci-theme-footstrap` | Тема LuCI по умолчанию (удобна с телефона); `luci-theme-bootstrap` оставлена запасной |
| `kmod-amneziawg`, `amneziawg-tools`, `luci-app-amneziawg` | WireGuard с обфускацией — там, где обычный WireGuard блокируют; собран под официальное ядро, в официальном репозитории его нет |

## Официальные пакеты

| Группа | Зачем |
|---|---|
| Wi-Fi: `wpad-basic-mbedtls`, `wireless-regdb`, `iw`, `iwinfo` | Точка доступа и клиент WPA2/WPA3, региональные правила, диагностика |
| `travelmate`, `luci-app-travelmate` | Выбор и переподключение к известным хотспотам в режиме клиента |
| USB Wi-Fi (mt76, rt2800, rtl8xxxu, rtw88, ath9k-htc, ath6kl, brcmfmac) | Второе радио по USB (например, клиент, пока встроенный Wi-Fi — точка доступа) без поиска интернета для установки драйвера |
| Модемы: ModemManager, QMI, MBIM, NCM, RNDIS, serial, ppp, `luci-proto-*` | Любой распространённый USB-модем сразу работает как интернет; `modem` и `wwan` уже в зоне wan |
| USB-Ethernet (rtl8152, asix, ax88179, smsc95xx, lan78xx, dm9601, sr9700) | Второй проводной порт (на плате он один) |
| VPN: `kmod-wireguard`, `wireguard-tools`, `luci-proto-wireguard`, `kmod-tun` | Обычный WireGuard; TUN для VPN в userspace и sing-box |
| Маршрутизация через прокси: `sing-box`, nft tproxy/socket/nat, `nftables-json`, `curl`, `jq`, `ca-bundle`, `base64`, `dig` | Выборочная отправка трафика через прокси (прозрачный прокси на nftables); утилиты — то, что такие схемы ожидают найти |
| `ucode`, `ucode-mod-fs`, `ucode-mod-uci` | Бэкенд панели «Board» (rpcd ucode: `fs`, `uci`) |
| `luci`, `luci-ssl` | Веб-интерфейс по HTTPS |
| Диагностика: `usbutils`, `picocom`, `ethtool`, `ip-full`, `tcpdump`, `lsof`, `strace`, `iperf3`, `htop`, `coreutils-timeout` и др. | Отладка модемов (`picocom` для AT-команд), скорость Wi-Fi (`iperf3`), драйвера; `timeout` нужен нашим скриптам Wi-Fi |

## Чего нет специально

- OpenVPN (проверка образа падает, если он попал): тяжёлый, WireGuard/AmneziaWG закрывают задачу.
- mwan3, watchcat, nlbwmon — ставятся через `apk`, если нужны.
- Bluetooth — вне проекта.

## Изменения образа помимо пакетов

- Узлы Wi-Fi добавлены в device tree внутри FIT-образа ядра.
- Ключ и адрес нашего apk-репозитория (`/etc/apk/repositories.d/customfeeds.list`).
- Footstrap — тема по умолчанию.
- `modem` и `wwan` в зоне wan firewall.
