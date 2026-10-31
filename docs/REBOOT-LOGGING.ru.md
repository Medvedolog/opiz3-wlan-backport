# Как поймать причину внезапной перезагрузки

[English](REBOOT-LOGGING.md)

Если плата перезагружается сама (например, на beta 2 так бывало на Zero 3 с
клиентами на точке 5 ГГц), обычный `logread` после ребута пуст: лог хранится
в памяти. Ниже — как писать лог на SD-карту, что прислать после ребута и как
потом всё выключить.

## 1. Писать системный лог в файл

`/root` лежит на overlay (на SD-карте), поэтому файл переживает перезагрузку:

```sh
uci set system.@system[0].log_file='/root/syslog.log'
uci set system.@system[0].log_size='4096'
uci commit system
/etc/init.d/log restart
logger -t test "persistent log on"; tail -2 /root/syslog.log
```

- `log_size` — размер в КБ. Когда файл его превышает, он переименовывается в
  `/root/syslog.log.old` и пишется заново, так что SD-карта не забивается.
  Этот же параметр задаёт размер буфера лога в памяти (4 МБ — для платы с
  1 ГБ и больше это немного).
- В файл попадают и сообщения ядра (`kern.*`), в том числе драйвера Wi-Fi.

## 2. Раз в минуту записывать состояние платы

Если перед ребутом что-то росло (температура, нагрузка, расход памяти,
число клиентов), это будет видно в логе:

```sh
cat > /root/opiz3-mon.sh <<'EOS'
#!/bin/sh
t=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | tr '\n' ' ')
m=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
s=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | while read i; do iw dev $i station dump | grep -c Station; done | tr '\n' ' ')
logger -t opiz3-mon "up=$(cut -d' ' -f1 /proc/uptime) load=$(cut -d' ' -f1-3 /proc/loadavg) temp=$t memavail=${m}kB stations=$s"
EOS
chmod +x /root/opiz3-mon.sh
echo '* * * * * /root/opiz3-mon.sh' >> /etc/crontabs/root
/etc/init.d/cron enable; /etc/init.d/cron restart
```

Температура — в тысячных долях градуса (`52000` = 52 °C), память — в КБ,
`stations` — число клиентов на каждом интерфейсе.

## 3. После внезапной перезагрузки прислать

```sh
ls -la /root/syslog.log*
grep -n "Booting Linux\|opiz3-mon\|assert\|recover\|watchdog\|Oops\|panic\|thermal\|under-voltage" /root/syslog.log | tail -60
tail -150 /root/syslog.log
```

Самое ценное — последние строки **перед** строкой `Booting Linux`. Если ребут
был давно и файл уже переименовался, те же команды выполнить для
`/root/syslog.log.old`. Можно просто приложить оба файла.

## Что важно знать

- **Мгновенное зависание или паника ядра** часто не успевают записаться в
  файл: плата перезагружается по сторожевому таймеру, и лог обрывается на
  полуслове. Это тоже информация: если лог оборвался без ошибок, вероятнее
  всего это зависание ядра или проблема с питанием. Тогда поможет только
  UART-консоль, подключённая во время работы: в ней будет видна паника.
- **Питание.** С клиентами на 5 ГГц и нагрузкой провалы питания — частая
  причина ребутов. Нужен блок на 5 В 3 А и короткий толстый кабель.
- **Если падает прошивка Wi-Fi** (строки `assert` / `recover`), плата сама
  перезагружаться не должна: драйвер перезапускает чип. Такой лог тоже
  присылайте.

## 4. Когда тест закончится — выключить

Лог в файл лучше выключить, чтобы не изнашивать SD-карту:

```sh
uci delete system.@system[0].log_file
uci delete system.@system[0].log_size
uci commit system
/etc/init.d/log restart
sed -i '/opiz3-mon/d' /etc/crontabs/root; /etc/init.d/cron restart
rm -f /root/opiz3-mon.sh
```
