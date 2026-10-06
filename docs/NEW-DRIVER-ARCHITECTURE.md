# UWE5622 (AW859A): architecture of a new Wi-Fi driver and firmware protocol map

Status: design draft. Everything under "Protocol" is taken from the vendor
driver (armbian/uwe5622 `cc2835a`, GPL-2.0, read as a specification) and from
the reverse engineering of `wcnmodem.bin` MARLIN3_19B_W21.05.3
(`docs/WCNMODEM-REVERSE-ENGINEERING.md`). Items marked *(RE)* come from the
firmware, items marked *(unverified)* still need a hardware check.

## 1. Why, and what not

The vendor stack is about 36k lines of Wi-Fi code (`unisocwifi`) on top of
about 40k lines of BSP (`unisocwcn`: SDIO, firmware loader, GNSS, BT tty,
procfs, PCIe/USB paths, kernel 3.x compatibility). Fixing it piecemeal
(series 010-230) makes it safe to run; it cannot make it reviewable.

Goals of the new driver:
- AP and STA only, through cfg80211 (hostapd / wpa_supplicant do the SME).
- One kernel (6.12+), no compatibility `#if`s, no global state outside the
  hardware-interface layer.
- Errors are return codes, never `BUG_ON` or a firmware assert provoked by a
  bad request: everything that reaches the firmware is validated first.
- Honest reporting: only what the firmware or host actually measures.
- Firmware crash recovery inside the kernel.

Non-goals: P2P, NAN, RTT, GSCAN, IBSS, TDLS, WoWLAN, vendor NL80211 commands,
Bluetooth (out of scope: not needed for an OpenWrt router), PCIe/USB variants.

## 2. Layers

```
 cfg80211 / nl80211  (hostapd, wpa_supplicant, iw, LuCI)
        |
 uwe-cfg80211.c   wiphy, bands and limits, vif ops, station info
        |
 uwe-cmd.c        command/response/event engine, timeouts, IDs
 uwe-tx.c         data TX: 802.3 -> tx_msdu_dscr, per-TID queues, flow control
 uwe-rx.c         data RX: rx_msdu_desc, BA reorder, defrag, per-LUT stats
        |
 uwe-hif.c        channel transport (SDIO ports), packet header (PUH)
        |
 phase 1: vendor BSP (uwe5622_bsp_sdio: sprdwcn_bus_* API, firmware download)
 phase 2: own SDIO + loader (sdio_func, request_firmware, sync handshake)
```

Planned size: about 7-8k lines in total for phase 1.

| File | Content | ~lines |
|---|---|---|
| uwe-core.c | probe/remove, firmware info, vif lifecycle, recovery | 1200 |
| uwe-cfg80211.c | cfg80211_ops for AP/STA, bands, regdomain, station info | 2000 |
| uwe-cmd.c | cmd/rsp matching by id, sync/async, event dispatch | 900 |
| uwe-tx.c | TX path, LUT/TID mapping, ADDBA triggers, flow control | 1200 |
| uwe-rx.c | RX path, BA reorder buffer, defrag, counters | 1300 |
| uwe-hif.c | port setup, buffer pools, PUH, BSP adapter | 600 |
| uwe-debugfs.c | peer stats, firmware station table, rx dumps | 400 |

## 3. Protocol map

### 3.1 Boot (BSP today, own loader in phase 2)

- Power: the board DT provides `mmc-pwrseq-simple` (PG18 reset, RTC 32k
  clock) and two fixed regulators on mmc1 (`zero3-dtb-add-wifi.py`). SDIO
  card detect follows a rescan.
- Firmware image (`wcnmodem.bin`, Cortex-M, linked at 0x100000) is written
  over the SDIO direct-access window to bus address 0x40500000 (CP address
  + 0x40400000).
- Sync block `struct wcn_sync_info_t` right after the image:
  `SYNC_ADDR = 0x405E73B0` on UWE5622 (= 0x40500000 + image size 0xE73B0).
  `init_status` walks through `0xF0F0F0F0` in progress, `...F1` calibration
  waiting, `...F2` cali written, `...F3` cali finished, `...F4` SDIO
  re-init done, `...F5` SDIO ready, `...F6..F8` bind-verify handshake
  (`CONFIG_AW_BIND_VERIFY`: 16 bytes transformed by the host and written
  back to `bind_verify_data`). Other fields: `sdio_config`, `tsx_dac_data`
  (calibration), mem power-down ranges.
- After boot the host downloads the INI/calibration set
  (`WIFI_CMD_DOWNLOAD_INI` 0x4c) and syncs versions
  (`WIFI_CMD_SYNC_VERSION` 0x09), then `WIFI_CMD_GET_INFO` 0x01 returns
  capabilities, MAC, versions, HT/VHT capability blocks.

### 3.2 Channel transport (SDIO)

| Port | Direction | Use |
|---|---|---|
| 8  | TX | commands |
| 10 | TX | data |
| 22 | RX | responses and events |
| 23 | RX | packet log |
| 24 | RX | data |

Every SDIO packet starts with a 32-bit public header (`sdiohal_puh`):
`pad:6 check_sum:1 len:16 eof:1 subtype:4 type:4`. With `check_sum` set a
16-bit TCP checksum computed by hardware follows the MSDU.

Flow control: firmware sends `WIFI_EVENT_SDIO_FLOWCON` (0xB3) with per-queue
credits; the host must not exceed them (vendor `qos.c`/`tx_msg.c`).

### 3.3 Message header

One byte common header: `type:3 reserv:1 rsp:1 ctx_id:3`.
`type`: 0 command, 1 event, 2 data, 3 special data, 4 PCIe address, 5 packet
log. `ctx_id` is the virtual interface (firmware MAC context).

Command / response (`sprdwl_cmd_hdr`, packed, little endian):

| Offset | Field | |
|---|---|---|
| 0 | common | type=0, rsp=1 if a response is wanted |
| 1 | cmd_id | u8 |
| 2 | plen | le16, includes this header |
| 4 | mstime | le32, host timestamp, echoed |
| 8 | status | s8, in responses: 0 ok, -1 arg, -2 get result, -3 exec, -4 malloc, -5 wifi mode, -6 error, -7 cannot exec, -8 not supported, -9 CRC, -10 INI index, -11 length, -127 other |
| 9 | rsp_cnt | u8 |
| 10 | reserv[2] | |
| 12 | payload | |

Firmware command IDs (host enum, confirmed against the firmware dispatch
table *(RE)* where an address is given in `docs/WCNMODEM-...`):

| ID | Command | In new driver |
|---|---|---|
| 0x01 | GET_INFO | yes |
| 0x02 | SET_REGDOM | yes |
| 0x03/0x04 | OPEN / CLOSE (vif) | yes |
| 0x05 | POWER_SAVE | yes |
| 0x06 | SET_PARAM (rts/frag) | yes |
| 0x07 | SET_CHANNEL (u8 primary only) | no: AP channel comes from START_AP IEs *(RE)* |
| 0x09 | SYNC_VERSION | yes |
| 0x0a | CONNECT | yes (STA) |
| 0x0b | SCAN | yes |
| 0x0d | DISCONNECT | yes |
| 0x0e | KEY | yes |
| 0x0f | SET_PMKSA | yes |
| 0x10 | GET_STATION | STA only: no peer lookup in AP mode *(RE 0x143c0c)* |
| 0x11 | START_AP | yes |
| 0x12 | DEL_STATION | yes |
| 0x15/0x16 | TX_MGMT / REGISTER_FRAME | yes (hostapd SME) |
| 0x17/0x18 | REMAIN_CHAN / CANCEL | later |
| 0x19 | SET_IE | yes |
| 0x1a | NOTIFY_IP_ACQUIRED | yes (power save hint) |
| 0x23 | ASSERT | debug only |
| 0x24 | FLUSH_SDIO | yes |
| 0x27 | MULTICAST_FILTER | later |
| 0x28/0x29 | ADDBA_REQ / DELBA_REQ | yes |
| 0x38 | LLSTAT | yes (aggregate only *(RE)*) |
| 0x44 | BA | yes |
| 0x47 | SET_MAX_CLIENTS_ALLOWED | yes |
| 0x4b | RSSI_MONITOR | later |
| 0x4c | DOWNLOAD_INI | yes |
| 0x4e | HANG_RECEIVED | yes (recovery) |
| 0x4f | RESET_BEACON | yes |
| 0x54 | PACKET_OFFLOAD | no |

Events (type=1, IDs from 0x80):

| ID | Event | |
|---|---|---|
| 0x80 | CONNECT | STA result |
| 0x81 | DISCONNECT | |
| 0x82 | SCAN_DONE | |
| 0x83 | MGMT_FRAME | AP: auth/assoc to hostapd |
| 0x84 | MGMT_TX_STATUS | |
| 0x85 | REMAIN_CHAN_EXPIRED | |
| 0x86 | MIC_FAIL | |
| 0xA0 | NEW_STATION | AP: station added/removed |
| 0xB0 | CQM | |
| 0xB3 | SDIO_FLOWCON | TX credits |
| 0xE0 | SDIO_SEQ_NUM | |
| 0xF3 | BA | BA session state |
| 0xF5 | STA_LUT_INDEX | MAC to hardware LUT mapping |
| 0xF6 | HANG_RECOVERY | |
| 0xF7 | THERMAL_WARN | |
| 0xFA | FW_PWR_DOWN | power save |
| 0xFB | CHAN_CHANGED | |

### 3.4 Data path

TX: 802.3 frame behind `tx_msdu_dscr`: common (type=2, ctx), `offset`,
tx_ctrl (checksum offload, sw_rate, swq_flag), `pkt_len`, buffer_info
(`msdu_tid:4`, `mac_data_offset:4`), `sta_lut_index`, `color_bit`. The
host picks the LUT from the destination MAC (`STA_LUT_INDEX` events) and the
TID from the 802.1D priority; TID 0-15 are legal (vendor bug: arrays sized 7,
fixed by patch 190).

RX: `rx_msdu_desc` (7 words): `ctx_id`, `msdu_offset`, `msdu_len`,
`sta_lut_valid/index`, flags (bc/mc, wlan-to-wlan, eapol, qos, ampdu,
amsdu, ba_session), `tid`, `seq_num`, PN, `cipher_type`, `frag_num`. The
host does **BA reordering and defragmentation** (vendor `reorder.c`,
`defrag.c`): this is the largest piece of the data path. On SDIO there is no
per-frame rate/RSSI (`rx_mh_desc` exists only on PCIe; patch 210 checks the
gap).

### 3.5 Firmware facts that shape the design *(RE)*

- START_AP: the firmware takes the AP channel from the beacon IEs; it needs
  a DS Parameter Set IE (on 5 GHz too: patch 180) and hides VHT Operation
  on a 2.4 GHz DS channel.
- RF code asserts (`rf_marlin.c:1010`) on a channel it cannot program
  instead of returning an error: the driver must only offer verified
  widths/channels (patch 200 logic becomes part of `uwe-cfg80211.c`).
- AP mode has no per-peer RSSI/rate command; the firmware's rate-control
  table is at CP 0x17e390 (16 x 0x228), index = hardware LUT; rate fields at
  +0x238/+0x239/+0x1c0/+0x241, smoothed ACK RSSI at +0x3a5 (valid +0x3a4)
  *(unverified)*. Readable over the direct-access window, so
  `get_station` can report real TX rate and signal for this firmware build.
- After an assert the BSP powers Wi-Fi off and removes the card; a new
  `start_marlin()` reloads the firmware. The new driver does this itself
  from the reset notifier (no userspace helper).

## 4. Phases and acceptance tests

| Milestone | Scope | Accept when |
|---|---|---|
| M0 bring-up | probe on BSP, GET_INFO, wiphy registered | `iw phy` shows bands, MAC matches the vendor driver |
| M1 STA open | scan, connect, data | `iw scan`; ping/iperf3 to the test PC's AP |
| M2 STA WPA2/WPA3 | keys, PMKSA | wpa_supplicant connects, 4-way handshake ok |
| M3 AP | START_AP, mgmt frames, NEW_STATION, keys | hostapd WPA2 AP, test PC associates |
| M4 throughput | TX credits, BA reorder, ADDBA | iperf3 both directions >= vendor driver |
| M5 stats | per-LUT counters, firmware table rate/RSSI | `iw station dump` matches the client's view |
| M6 recovery | in-kernel reset after assert | forced assert (`/proc/mdbg/at_cmd`) -> AP back without reboot |
| M7 own BSP | SDIO + loader, BSP module dropped | M0-M6 again |

## 5. Test bench

- Orange Pi Zero 3 on the official-kernel image (build-ib.yml), so modules
  built with the SDK load with `insmod` without reflashing.
- A Linux PC with a Wi-Fi card as the peer (client for AP tests, AP for STA
  tests), iperf3 on both, ssh to the board.
- A USB-UART on the board's debug header: the only way back in when a driver
  bug takes the network down.
- Ideally a switchable power supply (USB relay or smart plug) for cold
  resets the agent can trigger itself.
