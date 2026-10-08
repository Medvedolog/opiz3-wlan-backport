# CP2 logging on UWE5622: switch_cp2_log, AT command, SDIO receive and host sink

Static research: 2026-10-08. Reference UWE5622 / Orange Pi Zero 3 / firmware MARLIN3_19B_W21.05.3 (2021-12-15). No hardware operations, no firmware edits, no new driver or image build.

## Executive result

The Allwinner/UWE5622 BSP **turns CP2 ARM logging off at boot** using `switch_cp2_log(false)`, which sends `at+armlog=0\r\n`. There is a matching `at+armlog=1` enable path, but on this build **ordinary CP2 log frames are routed to a file-writing callback** rather than Linux dmesg or the `/dev/slog_wcn0` character device. Writing `at+armlog=1` to the `/proc/mdbg/at_cmd` proc node also sets up that file sink.

There is **no evidence that stock firmware prints the raw per-LUT ACK-statistics `sum` and `count`** used by `0x00128554`. Switching the log on is thus useful for *observability*, **not** a proven RSSI fix. The CP-side AT handler / formatting internals may be partly in mask ROM: the host driver and the loadable image establish command support and receive plumbing but not every CP-side implementation detail.

Avoid switching on file logging on a router before directing the output to a tmpfs path with sufficient free space: the vendor default may write into `/etc`, which on OpenWrt can consume overlay flash.

## Exact sources

- [Pinned Armbian driver](https://github.com/armbian/uwe5622/tree/cc2835a3f935d5297e03cdce464c1785381a7b4d), which is what the project's `package/kernel/uwe5622/Makefile` builds (`CONFIG_AW_WIFI_DEVICE_UWE5622=y`).
- [loopcheck.c](https://github.com/armbian/uwe5622/blob/cc2835a3f935d5297e03cdce464c1785381a7b4d/unisocwcn/platform/loopcheck.c): `at_cmd_send` 25–51, `switch_cp2_log` 83–103, completion 219–225.
- [wcn_boot.c](https://github.com/armbian/uwe5622/blob/cc2835a3f935d5297e03cdce464c1785381a7b4d/unisocwcn/platform/wcn_boot.c): log-off on boot 3240–3266.
- [wcn_procfs.c](https://github.com/armbian/uwe5622/blob/cc2835a3f935d5297e03cdce464c1785381a7b4d/unisocwcn/platform/wcn_procfs.c): AT responses 219–263, proc command handling 770–825, AT TX 980–989, `/proc/mdbg/at_cmd` creation 1179–1210, channel callbacks 1100–1145.
- [wcn_txrx.c](https://github.com/armbian/uwe5622/blob/cc2835a3f935d5297e03cdce464c1785381a7b4d/unisocwcn/platform/wcn_txrx.c): log channel RX worker 158–220, `mdbg_send` and `mdbg_receive` 224–241.
- [wcn_txrx.h](https://github.com/armbian/uwe5622/blob/cc2835a3f935d5297e03cdce464c1785381a7b4d/unisocwcn/platform/wcn_txrx.h): SDIO channel enumeration 95–112.
- [rdc_debug.c](https://github.com/armbian/uwe5622/blob/cc2835a3f935d5297e03cdce464c1785381a7b4d/unisocwcn/platform/rdc_debug.c): file destinations 16–75, `log_rx_callback` 178–276, `wcn_debug_init` 580–622.
- [wcn_log.c](https://github.com/armbian/uwe5622/blob/cc2835a3f935d5297e03cdce464c1785381a7b4d/unisocwcn/platform/wcn_log.c): `/dev/slog_wcn*`, ring read 89–155, initialization 255–367.
- [unisocwcn/Makefile](https://github.com/armbian/uwe5622/blob/cc2835a3f935d5297e03cdce464c1785381a7b4d/unisocwcn/Makefile): **Allwinner block** ~305–327, `CONFIG_WCN_LOOPCHECK` on, `CONFIG_CPLOG_DEBUG` commented out; the OpenWrt package does not override this.
- Firmware: [pinned `wcnmodem.bin`](https://raw.githubusercontent.com/armbian/firmware/612bc7cc0e3539ea89c659049b7d8432e2de8ed7/uwe5622/wcnmodem.bin), SHA-256 `119b87ce30875734a67462f7293fb8fe85acf3270fe8b78c978ae24be7715a80`, length 947120 bytes.

## 1. Host-side log control

`unisocwcn/platform/loopcheck.c` contains:

~~~c
void switch_cp2_log(bool flag)
{
    char a[32];
    /* ... */
    mutex_lock(&atcmd_lock);
    sprintf(a, "at+armlog=%d\r\n", flag ? 1 : 0);
    ret = at_cmd_send(a, sizeof(a));  /* sends 32-byte buffer */
    /* wait up to 3 * HZ for atcmd_completion */
    mutex_unlock(&atcmd_lock);
}
~~~

- `at_cmd_send` packs the request behind `PUB_HEAD_RSV` and sends it using `sprdwcn_bus_push_list` on `WCN_AT_TX` (SDIO channel 0). Note the helper passes `sizeof(a)=32`, not `strlen(a)`; the buffer is not entirely initialized by `sprintf`. This deserves attention **if modifying this helper**, but the present research does not claim it caused a failure.
- `get_cp2_version()` runs first on successful firmware boot. With `CONFIG_WCND` and `CONFIG_CPLOG_DEBUG` undefined in the Allwinner profile, `wcn_boot.c` then calls `switch_cp2_log(false)`.
- `switch_cp2_log` is a BSP **kernel C function**, not itself a firmware symbol or sysfs parameter. It is not exposed directly to userspace. The existing userspace route is the proc AT writer (below).

There is a second, user-accessible path through `/proc/mdbg/at_cmd`:

1. The procfs `mdbg_proc_write` recognizes the exact prefix `at+armlog=1`.
2. It calls `wcn_debug_init()` to prepare the log-file path.
3. It then passes the AT command via `mdbg_send_atcmd(..., WCN_ATCMD_WCND)` → `mdbg_send(..., MDBG_SUBTYPE_AT)` → `mdbg_comm_write` → SDIO AT TX.
4. The proc node also supports `logpath=` and related log file limits; the implementation uses `wcn_set_log_file_path` and checks whether the destination file can be opened. This is **not** a read-only operation, and is deliberately not invoked by this investigation.

`at+armlog=0` does **not** initialize a file sink; it simply forwards the command to CP2.

## 2. AT acknowledgement path

On SDIO the host uses separate channels:

| Purpose | SDIO channel |
|---|---:|
| AT TX to CP | 0 |
| Loopcheck RX | 12 |
| AT response RX | 13 |
| Assert RX | 14 |
| CP ARM log / ring RX | 15 |

`mdbg_at_cmd_read` is registered for AT responses. In the default/non-`CONFIG_WCND` case it copies the CP reply to `mdbg_proc->at_cmd.buf`, logs `WCND at cmd read:...`, completes the procfs response and invokes `complete_kernel_atcmd()`; the latter signals `atcmd_completion` for `switch_cp2_log`.

Thus a response `OK` after a log command confirms a command/response exchange, **not** that the log stream has data, that the file path is writable, or that RSSI metrics are actually emitted.

## 3. CP log RX and selected Linux sink

`mdbg_ringc_ops` registers `mdbg_log_read` on `WCN_RING_RX` (SDIO channel 15). It schedules `mdbg_ring_rx_task`, which uses `struct bus_puh_t` for frame length, strips `PUB_HEAD_RSV` bytes and dispatches:

~~~c
#ifdef CONFIG_WCN_SDIO
    rx->addr = mbuf_node->buf + PUB_HEAD_RSV;
    puh = (struct bus_puh_t *)mbuf_node->buf;
#ifdef CONFIG_WCND
    mdbg_ring_write(ring, rx->addr, puh->len);
#else
    log_rx_callback(rx->addr, puh->len);
#endif
#endif
~~~

**Crucial build distinction:**

- `CONFIG_WCND=y`: the receive worker fills an in-kernel `mdbg_ring`. The device `/dev/slog_wcn0` reads this ring through `wcnlog_read` → `mdbg_receive`.
- **Our Allwinner/OpenWrt profile, without `CONFIG_WCND`:** the worker calls `log_rx_callback` directly, which writes files using `kernel_write`. `/dev/slog_wcn0` may still be created by `wcn_log.c`, but **it is not fed by this normal RX path**. It should not be presented as the expected CP2 log collector on our build.
- No path here forwards the complete CP log stream into Linux `printk`/`dmesg`. Some AT responses, exceptions and host-side diagnostics **do** appear in dmesg, but they are different paths.

`log_rx_callback` returns without storing data until either `debug_inited` or `debug_user_inited` is true. Therefore merely enabling CP logging through a kernel call with no sink setup can silently lose received lines. The procfs `at+armlog=1` route prepares the file sink in advance.

## 4. Default file destination and OpenWrt safety

The vendor `rdc_debug.c` default list is `/etc`, `/data/unisoc_dbg`, `/data`, `/mnt/UDISK`. The names follow `unisoc_cp2log_%d.txt`; the default rotation is two files of 20 MiB each (unless overridden). This is designed for vendor systems, **not** low-ROM OpenWrt routers.

As a result, `at+armlog=1` without a prior logpath override may start writing `/etc/unisoc_cp2log_0.txt` to writable overlay storage. If runtime collection is ever approved after beta2, use a tmpfs destination via `logpath=` **before** enabling, and impose tight log limits; check mounted filesystems and kernel build first. No live command is recommended as part of the static phase.

`CONFIG_CPLOG_DEBUG` is a **compile-time** switch that changes startup behavior: the boot path calls `wcn_debug_init()` when enabled instead of shutting logging off. Changing it modifies the BSP package, not `wcnmodem.bin`; it is *not* a safe no-effect toggle, since it writes to files and changes CP log traffic.

## 5. Evidence from the exact loadable firmware

The pinned `wcnmodem.bin` was read statically as a flat image linked at CPU base `0x00100000`; it has these embedded strings:

| Image CPU address | String |
|---|---|
| `0x0010c890` | `+ARMLOG` |
| `0x0010c8dc` (in that string group) | `+LOGSWITCH` |
| `0x0010c8e8` | `+LOGLEVEL` |
| `0x0010c8f4` (in that string group) | `+DEBUG` |
| `0x0010c90c` (in that string group) | `+FLUSHWCNLOG` |
| `0x00101a18` | `PSEUDO_ATC: AP_SEND_CMD_AT_ARMLOG_FLUSH_RESIDUAL_LOG_TO_AP_FILL` |
| `0x0017924a` | `update_sta_lut_data` |
| `0x0017925e` | `ar_update_tx_statistic_info` |

The listed command strings and their start addresses were recovered from the pinned binary's byte sequence; these addresses locate static strings, **not** necessarily executable firmware handlers or registration table entries.

The firmware also has `+SPATGETCP2INFO` and `+LOOPCHECK` strings in the same command-name cluster. That corroborates an AT diagnostic subsystem but **does not prove** that `+LOGLEVEL` selects rate-control instrumentation, or that the handler for `+ARMLOG` resides in the loadable part rather than ROM. Searching 32-bit literal words for direct pointers to `+ARMLOG` / `+LOGLEVEL` did **not** find direct pointers in this image. A ROM-registered table or relative addressing scheme remains possible; do not infer that the strings are unused.

No existing diagnostic format string explicitly names both the LUT TX-statistics `sum` and `count` fields immediately around the recovered `0x00128554` / `0x00126d54` paths. This supports the caution that **enabling stock CP logging alone is not a proven way to recover ACK RSSI**. A generic numeric/binary message or a ROM-only formatter cannot be excluded without a runtime log or ROM disassembly.

## 6. Remaining unknowns and a safe research order

**Answered statically:** exact host command, boot default, host response completion, SDIO channels, RX callback branch chosen on Allwinner, default file path, and file-vs-ring distinction. No runtime access is needed to establish these code paths.

**Not answered statically:** exact semantics of CP-side `+ARMLOG`, `+LOGLEVEL` and `+LOGSWITCH`; number and severity of messages after enabling; whether their output is text, framed binary or a mixture; and whether the firmware ever prints per-LUT `sum/count` without a new instrumentation patch.

Suggested future work, **after repeater beta2**:

1. Keep the stock firmware unchanged. If a controlled runtime experiment is approved, inspect the BSP build profile and force the file sink onto tmpfs, with strict size/rotation limits, *before* issuing `at+armlog=1`. Use Ethernet/UART for control and persist only a bounded diagnostic excerpt.
2. Capture the beginning of the stock stream to identify packet framing and whether the image contains relevant existing messages; do **not** assume everything in it is ASCII.
3. If no pre-filtered values are present, any subsequent change needs explicit instrumentation at the `0x00128554` sum/count consumer or a proven existing CP logging primitive, which constitutes **firmware patching** and is out of the current scope.
4. A future debug image requires a separate package and licensing review. The existing production firmware, images and beta2 driver remain untouched.

**Conclusion:** The host logging route is recoverable and plausibly reusable for future instrumentation. Merely opening CP2 logging is **insufficient evidence** to obtain per-client RSSI, and the production OpenWrt BSP's file sink creates a real flash-wear/overlay-fill risk if used without redirecting it.
