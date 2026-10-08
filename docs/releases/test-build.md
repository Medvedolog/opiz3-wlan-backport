## What is in this test build / Что в этой тестовой сборке

Beta 2 candidate, frozen 2026-10-08: only fixes from here on.
Кандидат в beta 2, заморожен 2026-10-08: дальше только исправления.

- **Ethernet after `reboot` (Zero 3)**: U-Boot 2026.04 stopped resetting the
  PHY at boot, so after a warm reboot eth0 failed to start
  (`EMAC reset timeout`) until a power cycle. Our U-Boot resets it again;
  `/etc/init.d/opiz3-emac` retries as a fallback. Verified on hardware.
  **Ethernet после `reboot`**: U-Boot 2026.04 перестал сбрасывать PHY при
  старте, и после перезагрузки eth0 не поднимался до передёргивания
  питания. Наш U-Boot снова его сбрасывает, скрипт `opiz3-emac` —
  запасной путь. Проверено на железе.
- **Wi-Fi driver r30**: patch 330 fixes a vendor bug where a missed
  firmware loopcheck blocked its own recovery; patch 320 logs every
  interface step as `sprdwl: lc ...` (for the repeater hang); patch 310
  waits for the firmware to finish a disconnect.
  **Драйвер Wi-Fi r30**: патч 330 — ошибка производителя, из-за которой
  пропущенный ответ прошивки блокировал восстановление; патч 320 пишет
  каждый шаг интерфейсов как `sprdwl: lc ...`; патч 310 ждёт, пока
  прошивка закончит отключение.
- LTE modem at boot is no longer restarted by the Wi-Fi start.
  Модем при загрузке больше не перезапускается запуском Wi-Fi.
- Footstrap 0.14.14.

## What to test / Что проверить

The release gate in [TEST-PLAN.md](https://github.com/Medvedolog/opiz3-wlan-backport/blob/claude/intelligent-wright-4m40dg/docs/TEST-PLAN.md):
first boot (AP `OPiZ3` and modem come up), Ethernet after `reboot` /
power cycle / sysupgrade, Wi-Fi over three reboots, LuCI over cable and
AP. Then, if you can: repeater (client + AP), USB Ethernet and USB Wi-Fi
adapters, the 1.5 GB board, Zero 2 / Zero 2W.

## Known problems / Известные проблемы

- Repeater (client + AP) can freeze the board on a Wi-Fi restart (about 1
  in 10 in stress tests); rarely the same freeze at boot without a client.
  The watchdog reboots it after ~16 s. With a UART attached, send the last
  `sprdwl: lc` and `WCN` lines.
  Репитер может вешать плату при перезапуске Wi-Fi (примерно 1 из 10),
  изредка то же при загрузке без клиента; watchdog перезагружает через
  ~16 с. Если подключён UART — пришлите последние строки `sprdwl: lc` и
  `WCN`.
- The country code is only partly applied to the onboard Wi-Fi: the
  kernel's channel limits work (DE: ch 14 off, 149-165 at 13 dBm), but the
  driver gives the firmware world rules and the beacon has no country
  code. Fix after beta 2.
  Страна применяется к встроенному Wi-Fi не полностью: ограничения каналов
  ядра работают (DE: канал 14 выключен, 149–165 — 13 дБм), но драйвер
  отдаёт прошивке мировые правила, и в маяке нет кода страны. Исправление
  после beta 2.
