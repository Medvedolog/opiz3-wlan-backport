# Catching the cause of a spontaneous reboot

[Русский](REBOOT-LOGGING.ru.md)

If the board reboots on its own (on beta 2 this was seen on the Zero 3 with
clients on the 5 GHz AP), plain `logread` is empty after the reboot: the log
lives in RAM. Below: how to write the log to the SD card, what to send after
a reboot, and how to turn it all off afterwards.

## 1. Write the system log to a file

`/root` is on the overlay (on the SD card), so the file survives a reboot:

```sh
uci set system.@system[0].log_file='/root/syslog.log'
uci set system.@system[0].log_size='4096'
uci commit system
/etc/init.d/log restart
logger -t test "persistent log on"; tail -2 /root/syslog.log
```

- `log_size` is in KB. When the file grows past it, it is renamed to
  `/root/syslog.log.old` and a new one is started, so the SD card does not
  fill up. The same option also sets the in-RAM log buffer (4 MB is small on
  a board with 1 GB or more).
- Kernel messages (`kern.*`), including the Wi-Fi driver, go to the file too.

## 2. Log the board state once a minute

If something grew before the reboot (temperature, load, memory use, number
of clients), it shows in the log:

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

Temperature is in millidegrees (`52000` = 52 °C), memory in KB, `stations`
is the client count per interface.

## 3. After a spontaneous reboot, send

```sh
ls -la /root/syslog.log*
grep -n "Booting Linux\|opiz3-mon\|assert\|recover\|watchdog\|Oops\|panic\|thermal\|under-voltage" /root/syslog.log | tail -60
tail -150 /root/syslog.log
```

The most useful part is the last lines **before** the `Booting Linux` line.
If the reboot was a while ago and the file has already been rotated, run the
same commands on `/root/syslog.log.old`, or just attach both files.

## Good to know

- **An instant hang or a kernel panic** often does not make it to the file:
  the watchdog reboots the board and the log stops mid-line. That is still
  information: a log that ends with no errors most likely means a kernel hang
  or a power problem. Only a UART console attached while the board runs will
  show the panic then.
- **Power.** With 5 GHz clients and load, supply dips are a common cause of
  reboots. Use a 5 V 3 A supply and a short, thick cable.
- **If the Wi-Fi firmware crashes** (`assert` / `recover` lines), the board
  should not reboot: the driver restarts the chip. Send that log too.

## 4. When the test is over, turn it off

Turn file logging off so it does not wear out the SD card:

```sh
uci delete system.@system[0].log_file
uci delete system.@system[0].log_size
uci commit system
/etc/init.d/log restart
sed -i '/opiz3-mon/d' /etc/crontabs/root; /etc/init.d/cron restart
rm -f /root/opiz3-mon.sh
```
