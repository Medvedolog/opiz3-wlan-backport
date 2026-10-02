# Reverse engineering `wcnmodem.bin` — SC2355 / Marlin3

Status: initial static analysis  
Date: 2026-10-02  
Target: Orange Pi Zero 3 / AW859A / UWE5622  
Firmware SHA-256: `119b87ce30875734a67462f7293fb8fe85acf3270fe8b78c978ae24be7715a80`  
Size: `947120` bytes

## 1. Executive summary

The Orange Pi / UWE5622 `wcnmodem.bin` is not an encrypted or compressed opaque container. It is a mostly flat executable firmware image for a Cortex-M-class processor, with a conventional vector table at the beginning, many absolute pointers, debug strings, source file names, command/event names and assert text.

The image is therefore suitable for useful static reverse engineering.

The first target was the firmware-side station/LUT path because the current OpenWrt driver can enumerate associated station MAC addresses but does not expose authoritative per-peer signal/rate data.

The most important initial findings are:

1. the image is linked at approximately `0x00100000`;
2. the vector table is Cortex-M compatible and the firmware contains an explicit `cm4_region` diagnostic string;
3. build identity is `MARLIN3_19B_W21.05.3 / sc2355_marlin3_lite_ott`, built 2021-12-15;
4. a firmware command/event name table is present in plain text and maps names to numeric identifiers;
5. firmware contains a function referenced by the string `update_sta_lut_data`;
6. its call site and body can be disassembled as Thumb-2;
7. the firmware maintains a much larger per-station record than the Linux host driver currently exposes: the reverse-engineered record stride is `0x228` (552 bytes);
8. the function copies a 24-byte station-status structure into a temporary local buffer and then decodes multiple packed bitfields before updating the station record;
9. there is a command/event ID mismatch between this firmware's diagnostic table and the current Armbian host header. This requires careful validation before changing any protocol IDs.

This makes the station/LUT path a realistic candidate for recovering additional per-peer information.

---

## 2. Image identity

Uploaded image:

```text
size    947120 bytes
sha256  119b87ce30875734a67462f7293fb8fe85acf3270fe8b78c978ae24be7715a80
```

Embedded build strings include:

```text
Platform Version: MARLIN3_19B_W21.05.3
Project Version:  sc2355_marlin3_lite_ott
12-15-2021 11:26:33
```

Other embedded strings identify the implementation as Marlin3 / SC2355 and contain many source component names, including examples such as:

```text
phy_marlin3.c
rf_marlin.c
rf_marlin_tpc.c
host_if_sdio.c
pld_sdio_hal.c
sdiom_cp.c
wifi_pm_ap.c
wifi_scan.c
mcc_station.c
machw_lut.c
ce_lut.c
```

The firmware is a common WCN image rather than a WLAN-only microcode blob. Strings also expose BT/FM components.

---

## 3. CPU architecture and load address

The first words are compatible with a Cortex-M vector table:

```text
file+0x0000  0x001a0f50   initial SP
file+0x0004  0x00100319   reset vector (Thumb bit set)
file+0x0008  0x0010037b
file+0x000c  0x0010039d
```

The reset vector points to file offset `0x319` when using base address `0x00100000`.

The image also contains:

```text
not config cm4_region,please config it!
```

For analysis, wrapping the raw file as an ARM ELF with:

```text
VMA   0x00100000
ISA   Thumb-2 / Cortex-M
entry 0x00100319
```

produces coherent disassembly.

---

## 4. Firmware command/event name table

A diagnostic table begins around file offset `0x798a0`. Each entry is effectively:

```c
struct {
    const char *name;
    uint32_t id;
};
```

Examples recovered directly from the image:

| Firmware table ID | Name |
|---:|---|
| 0x02 | WIFI_CMD_GET_INFO |
| 0x06 | WIFI_CMD_POWER_SAVE |
| 0x08 | WIFI_CMD_SET_CHANNEL |
| 0x11 | WIFI_CMD_GET_STATION |
| 0x12 | WIFI_CMD_START_AP |
| 0x39 | WIFI_CMD_LINK_STAT |
| 0x4c | WIFI_CMD_RSSI_MONITOR |
| 0x4e | WIFI_CMD_DFS_DETECT |
| 0xb0 | WIFI_EVENT_NEW_STATION |
| 0xe0 | WIFI_EVENT_SDIO_FLOW_CONTROL |
| 0xf6 | WIFI_EVENT_STA_LUT_INDICATION |

The complete table also exposes RTT, NAN, IBSS, packet offload, hang recovery, radar detection and power-related events.

### Important caution: IDs differ from the current host header

The current `armbian/uwe5622` host driver at commit `cc2835a3...` defines:

```text
WIFI_CMD_GET_STATION      0x10
WIFI_CMD_LLSTAT           0x38
WIFI_EVENT_NEW_STATION    0xa0
WIFI_EVENT_STA_LUT_INDEX  0xf5
```

while this firmware's embedded diagnostic table shows:

```text
WIFI_CMD_GET_STATION          0x11
WIFI_CMD_LINK_STAT            0x39
WIFI_EVENT_NEW_STATION        0xb0
WIFI_EVENT_STA_LUT_INDICATION 0xf6
```

This is not yet proof that the on-wire IDs are wrong in the current driver.

The host driver contains an explicit API-version synchronization mechanism (`api_version.c`) and the embedded firmware table may reflect a different internal enumeration or firmware generation. The existing working command path must not be modified purely from these strings.

However, this mismatch is important and must be investigated because event/version skew is a plausible source of subtle feature loss.

---

## 5. Host-side station data today

The current Linux driver asks firmware for a compact interface/station response:

```c
struct sprdwl_rate_info {
    u8 flags;
    u8 mcs;
    u16 legacy;
    u8 nss;
} __packed;

struct sprdwl_cmd_get_station {
    struct sprdwl_rate_info rate;
    s8 signal;
    u8 noise;
    u8 reserved;
    __le32 txfailed;
} __packed;
```

`sprdwl_get_station()` sends `WIFI_CMD_GET_STATION` with zero request payload and receives that compact structure.

This explains the current limitation: there is no MAC/LUT selector in the request, so the command by itself cannot obviously request statistics for a particular AP client.

The host also receives a separate LUT event:

```c
struct sprdwl_sta_lut_ind {
    u8 ctx_id;
    u8 action;
    u8 sta_lut_index;
    u8 ra[ETH_ALEN];
    u8 is_ht_enable;
    u8 is_vht_enable;
} __packed;
```

The Linux driver stores this in `peer_entry[]` and uses it mainly for TX routing / BA state / MAC tracking.

---

## 6. Firmware-side `update_sta_lut_data`

The firmware contains the string:

```text
update_sta_lut_data
```

at file offset `0x7924a`, runtime address approximately `0x0017924a`.

There is a direct absolute pointer to that string in the literal pool near `0x0012808c`.

The surrounding Thumb function starts at approximately:

```text
0x00127fce
```

and a full-image disassembly finds one direct call to it:

```text
0x00169ffa  bl 0x00127fce
```

This gives us both the function body and a call site.

### 6.1 Apparent calling convention

At the call site:

```asm
mov r2, sp
mov r1, r6
mov r0, r7
bl  0x00127fce
```

So the function receives three arguments:

```text
r0 = context / vdev-like index
r1 = pointer whose first byte is a station/LUT-like index
r2 = pointer to a station status structure built on the caller stack
```

Inside the callee:

```asm
ldrb r6, [r1]
...
movs r2, #0x18
mov  r1, r3
add  r0, sp, #0x48
bl   memcpy-like routine
```

The third argument is copied as exactly:

```text
0x18 = 24 bytes
```

before its packed fields are decoded.

This 24-byte structure is a high-value reverse-engineering target.

---

## 7. Firmware per-station record size

The function calculates a station-record address from the byte loaded from `r1`.

Relevant sequence:

```asm
ldrb r6, [r1]

add.w r0, r6, r6, lsl #2      ; r0 = 5 * index
add.w r1, r0, r6, lsl #6      ; r1 = 69 * index
ldr.w r0, [global, #4]
add.w r4, r0, r1, lsl #3      ; r4 = base + 552 * index
add.w r4, r4, #0x194
```

Therefore:

```text
69 * 8 = 552 bytes = 0x228
```

The firmware-side per-station object has a stride of **0x228 bytes** in this table.

This is significantly larger than the compact information maintained by the current Linux `sprdwl_peer_entry` path.

It strongly suggests that the firmware maintains richer per-peer state internally.

---

## 8. Packed station-status fields seen in the callee

After copying the 24-byte status object to the stack, the function decodes multiple packed bitfields.

Observed operations include:

```asm
ubfx ..., field, #3, #1
ubfx ..., field, #4, #1
ubfx ..., field, #5, #3
ubfx ..., field, #8, #1
ubfx ..., field, #9, #1
ubfx ..., field, #10, #2
```

and nibble extraction from bytes at offsets around `+1/+2/+3/+4/+5`.

The function later copies the complete 24-byte temporary object into the per-station record and derives several cached fields at offsets around:

```text
record + 0xac
record + 0xad
record + 0xae
record + 0xb2
```

One path also manipulates bit `0x100` and bit `0x200` in a 16-bit status field.

This appears consistent with a PHY/peer capability/state object containing HT/VHT/rate/aggregation or power-state information, but exact field names are not yet proven.

No field should be renamed to RSSI/rate/MCS in our code until its semantics are confirmed from additional xrefs.

---

## 9. Connection to the current Linux LUT path

Linux `sprdwl_event_sta_lut()` currently records:

- LUT index;
- context ID;
- peer MAC;
- HT enable;
- VHT enable;
- BA state.

Firmware clearly maintains a substantially larger structure for the same peer/LUT concept.

A likely architecture is:

```text
firmware MAC/PHY station object (~0x228 bytes)
        |
        +-- LUT index
        +-- capability/status object
        +-- rate/aggregation/power state
        +-- internal counters
        |
        v
compact WIFI_EVENT_STA_LUT_INDICATION
        |
        v
Linux peer_entry[]
```

The current event is therefore probably only a notification/key for a richer internal firmware object.

The next goal is to find an existing command or event capable of exporting more of that object without modifying firmware.

---

## 10. Most promising next targets

### A. `WIFI_CMD_LINK_STAT` / host `WIFI_CMD_LLSTAT`

Firmware contains `WIFI_CMD_LINK_STAT` in its command-name table.

Current host code calls the related feature `WIFI_CMD_LLSTAT`.

This is the highest-priority candidate for already-supported rich statistics.

Work needed:

1. locate all xrefs to the command-name table and command dispatcher;
2. identify the handler corresponding to link statistics;
3. recover response structure size/layout;
4. compare with host `llstat` structures;
5. check whether AP mode includes per-LUT/per-peer records.

### B. firmware references to the 0x228-byte station table

Find every routine that indexes the same base with stride `0x228`.

This should identify readers/writers for:

- rate state;
- RSSI/RCPI;
- retry/failure counters;
- power state;
- BA/aggregation state.

A function that both indexes the table and sends a host event/command response is especially valuable.

### C. `WIFI_EVENT_STA_LUT_INDICATION`

Locate the firmware-side event construction.

Recover the exact payload used by this 2021 firmware and compare it byte-for-byte with:

```c
struct sprdwl_sta_lut_ind
```

in current Armbian.

This also helps resolve the apparent event-ID skew.

### D. API/version translation

Investigate whether the firmware's string-table IDs are:

- actual wire IDs;
- internal enum IDs;
- an older/newer API generation;
- deliberately offset IDs used only for diagnostics.

Do not patch IDs until this is proven.

---

## 11. Practical implication for OpenWrt

The reverse engineering already changes the strategy for client statistics.

Previously the working assumption was that firmware might expose only one interface-wide `GET_STATION` response.

We now know that firmware internally maintains indexed per-peer state with a 0x228-byte record and has explicit LUT-update logic.

Therefore a realistic path exists to obtain better AP client statistics by one of:

1. using an existing firmware link-stat command correctly;
2. decoding an existing event currently ignored by the driver;
3. correlating LUT index with another exported status path;
4. only as a last resort, extending firmware behavior.

The first three do not require patching `wcnmodem.bin`.

---

## 12. Current confidence levels

| Finding | Confidence |
|---|---|
| Cortex-M / Thumb firmware | High |
| image base near 0x00100000 | High |
| Marlin3/SC2355 firmware identity | High |
| build date/version | High |
| command/event name table exists | High |
| `update_sta_lut_data` function located | High |
| one direct call site located | High |
| station record stride = 0x228 | High |
| input station-status object size = 24 bytes | High |
| exact meaning of packed bits | Low/medium |
| command-table IDs are on-wire IDs | Low |
| richer per-peer signal/rate is exportable without firmware patch | Medium, promising |

---

## 13. Next analysis checkpoint

The next checkpoint should produce:

- reconstructed `WIFI_CMD_LINK_STAT` handler;
- candidate firmware response layout;
- list of functions referencing the 0x228-byte peer table;
- exact `STA_LUT_INDICATION` producer;
- comparison against current Armbian host structs;
- a concrete host-side patch proposal only if the protocol evidence is sufficient.

No firmware bytes have been modified at this stage.


---

## 14. LLSTAT host path contains dormant per-peer data structures

A second pass over the current Armbian host driver found an important asymmetry.

The vendor API defines rich per-rate and per-peer structures:

```c
struct wifi_rate {
    u32 preamble:3;
    u32 nss:2;
    u32 bw:3;
    u32 ratemcsidx:8;
    u32 reserved:16;
    u32 bitrate;
};

struct wifi_rate_stat {
    struct wifi_rate rate;
    u32 tx_mpdu;
    u32 rx_mpdu;
    u32 mpdu_lost;
    u32 retries;
    u32 retries_short;
    u32 retries_long;
};

struct wifi_peer_info {
    u8 type;
    u8 peer_mac_address[6];
    u32 capabilities;
    u32 num_rate;
    struct wifi_rate_stat rate_stats[];
};
```

and `struct wifi_iface_stat` contains:

```c
u32 num_peers;
struct wifi_peer_info peer_info[];
```

However the actual firmware response currently consumed by
`sprdwl_vendor_get_llstat_handler()` is only:

```c
struct sprdwl_llstat_data {
    int rssi_mgmt;
    u32 bcn_rx_cnt;
    struct sprdwl_wmm_ac_stat ac[WIFI_AC_MAX];
    u32 on_time;
    u32 on_time_scan;
    u64 radio_tx_time;
    u64 radio_rx_time;
};
```

This contains aggregate interface/radio counters only.

The current handler fills:

- beacon count;
- management RSSI;
- aggregate WMM AC counters;
- radio on/tx/rx/scan time;

but does **not** fill:

- `iface_st->num_peers`;
- `iface_st->peer_info[]`;
- `wifi_rate_stat` records.

This is significant because the host-side API already has the exact data model needed by LuCI/OpenWrt for per-client rate/retry information, while the currently used firmware response path exposes only aggregate counters.

### Working hypothesis

One of the following is likely true:

1. a richer LLSTAT firmware subcommand/version existed but is not used by this driver revision;
2. per-peer records are available through another command/event and were intended to be merged into `wifi_iface_stat`;
3. the 0x228-byte firmware station object is the source from which a richer link-stat response could be generated;
4. vendor Android userspace once consumed an additional path that the community Linux port no longer wires up.

This makes `wifi_peer_info` / `wifi_rate_stat` an important historical clue, not dead structure definitions to delete.

---

## 15. First reconstructed firmware station-update routine

The function associated with the embedded name `update_sta_lut_data` is located at approximately:

```text
0x00127fce
```

and has one direct call found in the full Thumb disassembly:

```text
0x00169ffa  bl 0x00127fce
```

At the call site:

```asm
mov r2, sp
mov r1, r6
mov r0, r7
bl  0x00127fce
```

The caller constructs a packed status object on its stack before the call.

Inside the callee the station index is read from the first byte of argument 2 and converted to a record address:

```asm
ldrb  r6, [r1]
add.w r0, r6, r6, lsl #2
add.w r1, r0, r6, lsl #6
ldr.w r0, [global, #4]
add.w r4, r0, r1, lsl #3
add.w r4, r4, #0x194
```

Equivalent address arithmetic:

```text
record = table_base + station_index * 0x228 + 0x194
```

The routine then copies 24 bytes from the caller-provided status block:

```asm
movs r2, #0x18
...
bl memcpy-like routine
```

and decodes multiple packed capability/state fields.

This is strong evidence that firmware has a substantial station-state object keyed by station/LUT index, while only a small subset reaches the current Linux driver.

### Reverse-engineering direction from here

The highest-value next step is to find every code path using the same 0x228 stride and classify them into:

- update/write paths;
- statistics readers;
- rate-control readers;
- power-management readers;
- host-response/event producers.

A reader that both indexes the same table and serializes data to the host would likely expose the missing per-peer statistics without requiring firmware modification.
