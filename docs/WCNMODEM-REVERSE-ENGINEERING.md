# Reverse engineering `wcnmodem.bin` — SC2355 / Marlin3

Status: static analysis, revision 2 (§36–§43; corrections in §36)  
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
9. ~~there is a command/event ID mismatch between this firmware's diagnostic table and the current Armbian host header~~ — **corrected in §36.1**: the table is `{id, name}`, not `{name, id}`, and its IDs match the host header exactly.
10. **revision 2 result (§37–§42):** no existing host command or event exports per-peer signal or rate in AP mode. `GET_STATION` resolves a peer only in station-type contexts; in AP mode it returns an empty rate and a calibration-only signal value.

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

> **Superseded by §36.1.** The table below was parsed with the wrong pairing (each name was paired with the *next* entry's ID). The real IDs match the host header; the rest of this section is kept for history.

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

The arithmetic first establishes a **0x228-byte station stride**. Independent init/reset routines later found in the same image clear exactly `0x228` bytes for each station object, so the current conclusion is stronger: the firmware station state block is exactly **0x228 = 552 bytes**.

This is significantly larger than the compact information maintained by the current Linux `sprdwl_peer_entry` path and confirms that firmware maintains much richer per-peer state internally.

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
| command-table IDs are on-wire IDs | ~~Low~~ High after §36.1 (table re-parsed as `{id, name}`) |
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


---

## 16. Station-table xref sweep

A full Thumb disassembly sweep for the station-table index arithmetic found a family of functions using the same `index * 0x228` addressing scheme.

Confirmed sites include code around:

```text
0x001261d8
0x00126584
0x0012695a
0x00126c4c
0x00126cac
0x001276ca
0x00127812
0x001278ac
0x00127fe0
0x00128214
0x00128302
0x001287ee
```

The repeated sequence is equivalent to:

```text
tmp = index * 5
tmp = tmp + index * 64
record = table_base + tmp * 8 + 0x194

=> record = table_base + index * 0x228 + 0x194
```

This confirms that `0x228` is not an accidental constant from one function: it is the stride used throughout a substantial station/peer subsystem.

The surrounding functions read/write fields around:

```text
record + 0x00
record + 0x10
record + 0x12
record + 0x14
record + 0x19
record + 0x2c
record + 0xa4 .. 0xb3
record + 0xec .. 0xee
record + 0x120 .. 0x124
```

Several helpers also access auxiliary areas related to the same indexed object beyond the first 0x194-byte offset.

---

## 17. `ar_update_tx_statistic_info` located

The firmware contains the symbol/debug name:

```text
ar_update_tx_statistic_info
```

at file offset `0x7925e`.

Its absolute string pointer is referenced from code inside the function beginning at approximately:

```text
0x00128554
```

This function again derives the station record using the `0x228` stride.

Using:

```text
R = table_base + station_index * 0x228 + 0x194
```

the routine works with areas including approximately:

```text
R + 0x00
R + 0xb4
R + 0xec
R + 0xed
R + 0xf0
R + 0x212
R + 0x214
```

The function allocates local temporary tables and iterates over **24 entries**:

```asm
...
adds r5, #1
uxtb r5, r5
cmp  r5, #0x18
blo  ...
```

Within this loop it accumulates pairs of counters and later merges them into station-local statistics.

Two particularly clear accumulators are:

```text
R + 0x212 : 16-bit accumulator/count
R + 0x214 : 32-bit accumulator/sum
```

The routine adds newly calculated values into those fields.

There are two direct call sites to this function currently identified:

```text
0x00128cc8
0x00128d6c
```

Both occur in TX processing/control code, supporting the interpretation that this function updates per-peer automatic-rate/TX statistics.

This is strong evidence that useful rate/retry/goodput state is maintained per station inside firmware.

---

## 18. `find_rate0_idx_by_goodput` and goodput EWMA field

The adjacent firmware symbol/debug name:

```text
find_rate0_idx_by_goodput
```

is referenced by a function at approximately:

```text
0x00126d54
```

This function accesses the same station object.

It computes:

```text
sample = (signed)sum / count
```

from the pair:

```text
R + 0x212  count
R + 0x214  sum
```

and stores a signed 8-bit smoothed value at:

```text
R + 0x211
```

On the first sample it stores the value directly. On later samples the code performs an approximately 50/50 moving average:

```text
new = (old + sample) * 50 / 100
```

and then clears the two accumulators.

### Important correction

Because `R + 0x211` is accessed with `ldrsb`, it initially looked like a possible RSSI-like signed field.

The function-name xref proves that interpreting it as RSSI would be premature/wrong: this field belongs to the firmware's **goodput/rate-selection logic**.

This is why field semantics in the reverse-engineered structure are only assigned when supported by function/context evidence.

---

## 19. Rate-control state is richer than current host reporting

The current host `GET_STATION` response exposes only:

```text
flags
MCS
legacy bitrate
NSS
signal
noise
txfailed
```

Firmware internally maintains substantially more data:

- a 0x228-byte indexed peer/station record;
- a 24-entry TX/rate statistics pass;
- per-entry accumulated counters;
- goodput-derived moving-average state;
- HT/VHT/capability state;
- multiple rate-selection helpers;
- per-peer TX update paths called from TX completion/control logic.

This makes a host-only extension increasingly plausible.

The best next target is no longer simply `GET_STATION`. It is to identify a firmware command/event serialization path that reads the same automatic-rate statistics object.

If such a path already exists, the OpenWrt driver can potentially expose meaningful per-peer rate/retry information without modifying firmware.

---

## 20. RSSI search status

No per-peer RSSI field is considered proven yet.

The signed field at `R + 0x211` has now been classified as goodput/rate-selection state, not RSSI.

The RSSI search should instead focus on:

1. functions that combine a station/LUT index with receive descriptor metadata;
2. per-peer power-management / roaming functions;
3. code paths that write signed PHY measurements into the 0x228-byte record;
4. host serialization paths for `GET_STATION`, link stats, CQM or RSSI-monitor responses.

This remains open.


---

## 21. Reconstructed compact per-rate table inside each peer record

Further disassembly of `ar_update_tx_statistic_info` gives a much clearer layout for the tail of the 0x228-byte station record.

Define:

```text
R = table_base + station_index * 0x228 + 0x194
```

The function creates a pointer:

```text
rate_table = R + 0xF0
```

and iterates exactly 24 entries.

For each entry it calculates:

```text
entry = rate_table + index * 12
```

The multiplication is explicit:

```asm
add.w r1, r5, r5, lsl #1   ; 3 * index
add.w r1, r4, r1, lsl #2   ; base + 12 * index
```

The function then updates:

```text
entry + 0x04 : 32-bit accumulated counter
entry + 0x08 : 32-bit accumulated counter
```

while `entry + 0x00` is not modified in this accumulation path.

This strongly suggests a compact firmware rate-stat entry such as:

```c
struct fw_rate_bucket_candidate {
    uint32_t rate_descriptor_or_key; /* semantics not yet proven */
    uint32_t counter_a;
    uint32_t counter_b;
};
```

with:

```text
24 entries * 12 bytes = 288 bytes = 0x120
```

which fits exactly from:

```text
R + 0x0F0
through approximately
R + 0x20F
```

Immediately after this array are the already identified aggregate fields:

```text
R + 0x212 : 16-bit sample/count accumulator
R + 0x214 : 32-bit sum accumulator
```

used by `find_rate0_idx_by_goodput`.

This is one of the strongest structural findings so far: firmware maintains a **24-bucket per-peer rate/statistics table** that is absent from the compact current Linux `GET_STATION` response.

### Why this matters

The current Linux vendor structures define:

```c
struct wifi_rate_stat {
    struct wifi_rate rate;
    u32 tx_mpdu;
    u32 rx_mpdu;
    u32 mpdu_lost;
    u32 retries;
    u32 retries_short;
    u32 retries_long;
};
```

The firmware table is not byte-for-byte the same format, but its existence strongly supports the hypothesis that the richer Android/vendor per-peer reporting path was designed around firmware-maintained rate buckets and was lost or left unwired in this community driver generation.

The next task is to determine the semantics of the two 32-bit counters and the first 32-bit rate descriptor/key.


---

## 16. Adjacent unnamed TX-status quality updater at 0x001288ca

A deeper Thumb-2 pass located a second TX-status/statistics routine adjacent to the named automatic-rate code. This function is **not** `ar_update_tx_statistic_info`; the embedded name `ar_update_tx_statistic_info` belongs to the distinct function at `0x00128554` (its string is referenced from instructions around `0x001286a4` and `0x001286f8`).

The unnamed function begins at approximately:

```text
0x001288ca
```

and is called directly from:

```text
0x00132ae4
```

inside a TX completion/status path.

The call is gated by an event/type value equal to `3`, which is consistent with this being one specific TX completion/status case rather than generic station maintenance.

### 16.1 Same 0x228-byte station object

The routine resolves the station object with the same index arithmetic found in `update_sta_lut_data`:

```text
station_index -> index * 0x228
record_base   -> table_base + index * 0x228 + 0x194
```

This independently confirms that the structure is a shared per-peer object used by both station/LUT setup and TX-rate/statistics logic.

### 16.2 TX outcome counters

The routine keeps a four-counter block near the end of each 0x228-byte station record:

| Record offset | Size | Observed behavior |
|---:|---:|---|
| `+0x21a` | u16 | total sample counter |
| `+0x21c` | u16 | outcome bucket 0 counter |
| `+0x21e` | u16 | outcome bucket 1 counter |
| `+0x220` | u16 | outcome bucket 2 counter |
| `+0x218` | u8 | distribution/EWMA initialized flag |
| `+0x222` | u8 | smoothed percentage bucket 0 |
| `+0x223` | u8 | smoothed percentage bucket 1 |
| `+0x224` | u8 | smoothed percentage bucket 2 |

The TX status path extracts:

```text
(input + 0x1f) & 0x03
```

and uses values `0`, `1`, and `2` to select one of the three outcome counters.

The total counter at `+0x21a` is incremented alongside those outcome-specific counters.

The exact semantic names of the three values are not yet proven, so they should currently be called **TX outcome buckets**, not success/retry/fail.

### 16.3 100-sample update window

The routine checks the total counter modulo 100.

At the end of a 100-sample window it calculates:

```text
bucket_percent = 100 * bucket_count / total_count
```

for all three buckets.

On the first completed window, those percentages are stored directly into:

```text
+0x222
+0x223
+0x224
```

and `+0x218` is set to 1.

On later windows the routine applies an EWMA:

```text
smoothed = (75 * old + 25 * new) / 100
```

The exact instruction sequence proves the weights:

```text
new * 25
old * 75
sum / 100
```

After the update, the counters at:

```text
+0x21a
+0x21c
+0x21e
+0x220
```

are reset to zero for the next window.

### 16.4 Why this matters

This is the first recovered **true per-peer runtime quality statistic** in the closed firmware.

It is not a global radio metric. The calculation is performed against the same LUT-indexed 0x228-byte station object used by association logic.

Therefore firmware internally maintains, per client:

- rolling TX outcome distribution;
- 100-sample raw counters;
- three smoothed percentage values;
- state indicating whether the EWMA is initialized.

This is strong evidence that richer per-client rate-control telemetry exists inside firmware even though the current Linux driver exports only MAC/HT/VHT state through the LUT event.

### 16.5 Relationship to rate control

The same firmware image contains the strings `find_rate0_idx_by_goodput` and `ar_update_tx_statistic_info` in the same internal diagnostic-name area. That supports a relationship with the adaptive-rate/goodput subsystem, but it does **not** name the function at `0x001288ca`; that routine remains unnamed in the current analysis.

The exact mapping of:

```text
bucket 0
bucket 1
bucket 2
```

to PHY outcomes remains to be resolved from the TX descriptor/status bit definitions before they are exposed to userspace with semantic names.

### 16.6 Direct call site

The only direct call found so far is:

```text
0x00132ae4 -> 0x001288ca
```

At that point firmware passes:

```text
r0 = interface/context index
r1 = TX status/descriptor-like object
```

The caller reaches this routine only for one TX event/type branch.

This gives the next reverse-engineering target: decode the input object fields around offsets `0x1e` and `0x1f` and identify the enum represented by the low two bits.

---

## 17. Practical host-side consequence

The per-peer statistics problem is now narrower.

We no longer need to prove that firmware tracks per-client TX quality; it does.

The remaining problem is finding a host-visible path to those values.

Preferred order:

1. locate an existing firmware command/event that serializes the 0x228-byte station state or a subset of it;
2. inspect the firmware-side implementation of `WIFI_CMD_LINK_STAT`;
3. inspect any NPI/debug command that reads these offsets;
4. only if no readout exists, consider a minimal firmware patch or a host-assisted indirect read mechanism.

A firmware patch is **not** the first choice.

The desirable OpenWrt implementation remains:

```text
firmware existing telemetry
    -> sprdwl host command/event
    -> peer_entry / station_info
    -> cfg80211 dump_station
    -> iw / iwinfo / LuCI
```

### Confidence

| Finding | Confidence |
|---|---|
| `ar_update_tx_statistic_info` located at ~0x001288ca | High |
| uses same LUT-indexed 0x228 station object | High |
| +0x21a is total window counter | High |
| +0x21c/+0x21e/+0x220 are three TX outcome counters | High |
| +0x222/+0x223/+0x224 are smoothed percentages | High |
| EWMA weights are 75% old / 25% new | High |
| low two bits of input+0x1f select the three buckets | High |
| semantic names of the buckets | Not yet proven |


---

## 22. Rate-control state machine call graph

The `find_rate0_idx_by_goodput` routine at approximately `0x00126d54` has two direct callers in the firmware:

```text
0x00127560
0x0012763c
```

Both calls are inside the same station-indexed rate-control state machine beginning around `0x001274f2`.

That state machine:

- obtains a station/LUT index from the first byte of its station argument;
- derives the same `index * 0x228` station lane;
- accesses state around the `+0x194`, `+0x248`, and `+0x284` lanes;
- invokes `find_rate0_idx_by_goodput`;
- compares its result with a cached rate-selection byte around `+0xa5`;
- updates state-machine states in the first few bytes of the `+0x194` lane;
- eventually passes the chosen/updated value onward to another rate-control routine.

This makes the recovered chain concrete:

```text
TX completion / statistics producer
        |
        v
ar_update_tx_statistic_info() @ ~0x00128554
        |
        v
24 x 12-byte per-rate buckets
        |
        v
find_rate0_idx_by_goodput() @ ~0x00126d54
        |
        v
station rate-control state machine @ ~0x001274f2
```

### Two direct callers of the TX statistics updater

`ar_update_tx_statistic_info()` itself also has two direct call sites:

```text
0x00128cc8
0x00128d6c
```

The first call is guarded by TX/status state and a threshold comparison before passing a station-indexed object.

The second occurs while iterating a 32-bit station bitmap and looking up active station entries.

This is strong evidence that the function is fed from real transmit-status/completion processing rather than from configuration-only code.

### Practical consequence

Per-client retry/rate information is definitely computed inside firmware on a station-indexed basis.

The remaining problem is not whether the data exists; it is locating the serializer/export path from this internal rate-control state to the host protocol.

That sharply narrows the next search.


---

## 23. Station block size is now proven to be exactly 0x228 bytes

A broader search for the station-index addressing pattern found two station initialization/reset routines around:

```text
0x001281fe
0x001282f4
```

Both calculate:

```text
station = global_base + station_index * 0x228 + 0x194
```

and then immediately call a memory-clear helper with:

```asm
mov.w r1, #0x228
mov   r0, station
bl    clear/memset-like helper
```

followed by initialization of fields inside that same region.

Therefore `0x228` is no longer merely an observed inter-station stride.

It is the actual size of the station state block cleared/initialized by firmware:

```text
sizeof(firmware_station_state) = 0x228 = 552 bytes
```

Observed defaults after clear include fields around:

```text
+0x2c
+0xa4
+0xa5
+0xa6
+0xa7
+0xa8
+0xad
+0xec
+0xed
+0xee
```

Some of these are directly consumed by the recovered rate-control state machine.

This establishes a much stronger basis for reconstructing the internal station object.

---

## 24. Host-interface WLAN output handler identified

The firmware contains a contiguous function-name cluster:

```text
send_hif_in_link_to_host
set_hif_in_link
hif_host_wlan_out_req_handler
```

The string `hif_host_wlan_out_req_handler` is referenced from code around:

```text
0x00139f1c
```

inside a larger function beginning approximately:

```text
0x00139ce2
```

The behavior of this function matches a host/WLAN request dispatcher:

- reads request type/subtype fields;
- branches over several request classes;
- validates payload lengths;
- iterates linked/request buffers;
- invokes WLAN/MLME handlers;
- ends through a common response/host-link path.

A nearby helper beginning around:

```text
0x00139c9e
```

dispatches on a small set of request categories after subtracting a fixed base from a request field.

Another common response path is invoked around:

```text
0x00139e82 -> 0x001391d4
```

with a request-derived value and a small status/result object.

This region is now the primary candidate for locating the exact serializer used by:

- `GET_STATION`;
- `LINK_STAT/LLSTAT`;
- station/LUT indications.

### Why this matters

Previous work established that rich per-station rate data exists internally.

This host-interface dispatcher gives us the opposite side of the problem: the generic path by which firmware responses are prepared for the Linux driver.

The next reverse-engineering step is therefore to connect:

```text
station/rate-control state
        -> command-specific response builder
        -> hif_host_wlan_out_req_handler / set_hif_in_link
        -> SDIO host response
```

Once a command-specific builder is identified, response structure offsets can be mapped directly against the current host driver structs.


---

## 25. Firmware command-name IDs are an internal namespace, not the host wire IDs

> **Superseded by §36.1.** The conclusion of this section came from the mis-paired table parse. There is no internal namespace: the IDs are identical to the host's. The `0x38` response ID in §35 is consistent with this.

The embedded firmware command/event table was parsed directly as `{name_ptr, id}` pairs.

Examples:

```text
0x02 WIFI_CMD_GET_INFO
0x06 WIFI_CMD_POWER_SAVE
0x08 WIFI_CMD_SET_CHANNEL
0x11 WIFI_CMD_GET_STATION
0x29 WIFI_CMD_ADDBA_REQ
0x38 WIFI_CMD_DELBA_REQ
0x39 WIFI_CMD_LINK_STAT
0x4c WIFI_CMD_RSSI_MONITOR
0xb0 WIFI_EVENT_NEW_STATION
0xf6 WIFI_EVENT_STA_LUT_INDICATION
```

The current host driver uses:

```text
0x01 WIFI_CMD_GET_INFO
0x05 WIFI_CMD_POWER_SAVE
0x07 WIFI_CMD_SET_CHANNEL
0x10 WIFI_CMD_GET_STATION
0x28 WIFI_CMD_ADDBA_REQ
0x29 WIFI_CMD_DELBA_REQ
0x38 WIFI_CMD_LLSTAT
0x89 WIFI_EVENT_RSSI_MONITOR
0xa0 WIFI_EVENT_NEW_STATION
0xf5 WIFI_EVENT_STA_LUT_INDEX
```

The firmware names therefore show a systematic internal-enum shift and some preserved/reserved ranges.

Crucially, inspection of host command construction shows that `sprdwl_ng` writes the host enum value directly into the wire header:

```c
hdr->cmd_id = cmd_id;
```

There is no +1/-1 translation in `__sprdwl_cmd_getbuf()`.

The hardware already works for many commands using those host values.

Therefore the embedded firmware table must **not** be treated as proof of the actual wire IDs.

The safest current interpretation is:

> the firmware string table exposes an internal/debug command namespace that differs from the host-visible wire protocol.

This is important because patching host IDs to match the string table would likely break working commands.

The previous protocol-skew concern remains historically interesting, but it is no longer a candidate for a direct fix.

---

## 26. HIF dispatcher is one layer above command-specific WLAN handlers

The recovered routine around `0x00139ce2` handles generic HIF/WLAN request classes.

It does not directly switch on `GET_STATION` or `LINK_STAT` command IDs.

Instead it:

1. validates an outer request class;
2. walks request/link buffers;
3. derives a WLAN/vdev-like context;
4. invokes lower-level handlers;
5. returns through a common response function near `0x001391d4`.

This means the command-specific serializer is one layer below the HIF dispatcher.

The current search therefore targets:

```text
wire cmd header
    -> WLAN command dispatcher
    -> command-specific handler
    -> response buffer
    -> generic HIF response path
```

rather than trying to identify `GET_STATION` directly inside the HIF outer switch.

---

## 27. Current-rate state is a real station-block field

The station block field at approximately:

```text
station + 0xa5
```

has many direct reads/writes in the recovered automatic rate-control region.

Confirmed accesses cluster around:

```text
0x00126d88
0x0012752c
0x00127558
0x00127564
0x001275b6
0x001275e2
0x00127602
0x0012760a
0x00127640
0x00127650
0x0012765a
0x00127666
0x00128ec8
0x00129004
0x001290bc
0x00129226
```

The field is compared against, updated from, and fed back into the rate-selection state machine.

It is therefore a high-confidence **rate-selection/current-rate state byte**, although its exact encoding is not yet proven.

The next useful task is to find a reader of `station + 0xa5` outside the rate-control subsystem.

Such a reader is a strong candidate for:

- `GET_STATION` response construction;
- `LINK_STAT` export;
- telemetry/debug reporting.

---

## 28. Public-source search result

Exact public GitHub code search for the internal firmware names:

```text
WIFI_CMD_PREPARE_CONNECT
WIFI_CMD_LINK_STAT
WIFI_EVENT_STA_LUT_INDICATION
```

returned no matching public source.

Therefore the binary analysis is currently providing information that is not recoverable from a straightforward public source-code lookup.

This increases the value of keeping the reverse-engineering notes and address map in-tree.


---

## 29. 5-byte firmware rate descriptor matches `sprdwl_rate_info`

A key routine beginning at approximately:

```text
0x00128e90
```

reads the current station rate state from the 0x228-byte station block and writes a compact descriptor to its third argument.

The output layout is exactly five bytes:

```text
+0x00  flags / PHY-mode bits
+0x01  rate/MCS index
+0x02  16-bit legacy-rate-like value
+0x04  NSS / auxiliary rate byte
```

This matches the packed host structure byte-for-byte:

```c
struct sprdwl_rate_info {
    u8 flags;
    u8 mcs;
    u16 legacy;
    u8 nss;
} __packed;
```

The routine performs different encodings depending on the internal PHY/rate mode and sets flag bits in byte 0. It reads the selected/current rate from:

```text
station + 0xa5
```

and follows that index through firmware rate tables before constructing the five-byte result.

This is the strongest connection so far between the internal automatic-rate-control state and the Linux-visible `GET_STATION` ABI.

---

## 30. Candidate station-info / GET_STATION response path at 0x00143c0c

The rate-descriptor builder at `0x00128e90` has exactly one direct caller in the firmware image:

```text
0x00143d28
```

inside a function beginning at approximately:

```text
0x00143c0c
```

That caller:

1. determines a station/connection object for the supplied context;
2. calculates and clamps a signed signal-like value to approximately:
   `[-100, 63]`;
3. zero-initializes a small stack result area;
4. calls `0x00128e90` to generate the five-byte rate descriptor;
5. passes:
   - context/index,
   - signed signal value,
   - pointer to the generated rate descriptor,
   - an auxiliary zero/default value
   to a single external helper.

The key sequence is:

```asm
mov  r2, sp
mov  r1, station
mov  r0, ctx
bl   0x00128e90      ; build 5-byte rate descriptor

mov  r3, r10         ; auxiliary/default field
mov  r2, sp          ; rate descriptor
sxtb r1, r4          ; signed signal
mov  r0, r6          ; context
bl   0x00206bfc
```

The external target `0x00206bfc` lies outside this flat firmware image, most likely in ROM or another separately mapped image.

Importantly, `0x00206bfc` has only one direct call site in the analyzed firmware: this station-info path.

### Why this strongly resembles `GET_STATION`

The current host ABI expects:

```c
struct sprdwl_cmd_get_station {
    struct sprdwl_rate_info rate; /* 5 bytes */
    s8 signal;                    /* 1 byte */
    u8 noise;                     /* 1 byte */
    u8 reserved;                  /* 1 byte */
    __le32 txfailed;              /* 4 bytes */
} __packed;
```

The firmware caller independently supplies:

- the exact 5-byte rate structure;
- a signed signal value;
- an auxiliary/default argument.

This is a very strong structural match.

The remaining four-byte `txfailed` field is not populated visibly in the caller and is therefore a plausible responsibility of the external/ROM helper `0x00206bfc`.

At this stage the function at `0x00143c0c` should be described as:

> a high-confidence station-info response path and strong candidate for the firmware-side GET_STATION handler.

It is not yet labelled definitively as GET_STATION because the final external helper and command-dispatch registration are outside the analyzed flat image. **Update:** confirmed in §38 and §39. The handler sends response ID `0x10`, and it resolves no peer in AP/GO contexts.

---

## 31. Station-info handler is registered as a firmware callback

The function at `0x00143c0c` is not reached through a normal direct `BL` from the analyzed image.

Instead, its Thumb pointer:

```text
0x00143c0d
```

is loaded during firmware initialization from literal slot:

```text
0x00141628
```

and written into a large firmware callback/interface structure:

```asm
ldr.w r0, =0x00143c0d
str.w r0, [global_interface, #0x78c]
```

The registration code is around:

```text
0x0014126e
```

This explains why no direct caller was initially visible: the routine is invoked indirectly through a callback table owned by another firmware/ROM layer.

That architecture is consistent with the external helper call at `0x00206bfc`.

A likely call chain is therefore:

```text
host WLAN command / ROM dispatcher
        |
        v
registered callback @ interface + 0x78c
        |
        v
station-info handler @ 0x00143c0c
        |
        +-- calculate signal
        +-- build sprdwl_rate_info-compatible descriptor
        |
        v
ROM/external response helper @ 0x00206bfc
        |
        v
HIF/SDIO response
```

This is a much tighter candidate mapping than the earlier generic HIF analysis.

---

## 32. Consequence for OpenWrt station statistics

The firmware path now explains why the current host `GET_STATION` response has exactly the fields it does:

- rate information is derived from the internal rate-control state;
- signal is separately calculated/clamped;
- the compact result is passed to a common external response helper.

However, this path still appears to describe one context/current connection rather than an arbitrary AP peer selected by MAC address.

That matches the host API limitation:

```c
sprdwl_get_station(...)
/* request payload length = 0 */
```

There is no peer MAC or LUT index in the request.

Therefore:

- `GET_STATION` is now increasingly likely to be suitable for STA/interface-level status;
- per-client AP statistics still need a different export path;
- `LLSTAT`, a LUT-indexed event, or another firmware callback remains the most promising route for true AP per-peer data.

The reverse engineering has nevertheless recovered the exact firmware-side rate encoding path needed to interpret/export current-rate state correctly.


---

## 35. LLSTAT firmware GET path recovered: response is aggregate-only

The real wire-command path for host `WIFI_CMD_LLSTAT` was identified in the firmware.

A dispatcher beginning at approximately:

```text
0x001423d8
```

examines the first byte of the command payload (the LLSTAT subcommand) and returns through the common command-response helper with:

```asm
movs r1, #0x38
b.w  0x002073a4
```

The value `0x38` is the actual host-visible wire command ID used by the current driver for `WIFI_CMD_LLSTAT`.

~~This independently confirms that the embedded string-table IDs are not the wire IDs.~~ With the corrected `{id, name}` parse (§36.1), the table itself also gives `0x38 = WIFI_CMD_LINK_STAT`, so the table IDs and the wire IDs agree.

### GET branch

The GET branch reaches:

```text
0x0015ef86
```

That routine updates/captures the current aggregate statistics and then sends exactly:

```text
0x60 = 96 bytes
```

to the host:

```asm
movs r2, #0x60
mov  r1, stats_base
mov  r0, ctx
bl   0x00207a84
```

The current host-side response structure is:

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

For `WIFI_AC_MAX == 4`, the total size is:

```text
4 + 4 + (4 * 16) + 4 + 4 + 8 + 8 = 96 bytes = 0x60
```

So the firmware response size matches `sizeof(struct sprdwl_llstat_data)` exactly.

### Consequence

For this firmware build, LLSTAT GET is **aggregate-only**.

It does not serialize:

- `wifi_peer_info[]`;
- per-peer MAC addresses;
- per-peer `wifi_rate_stat` arrays;
- the 0x228-byte station objects;
- the 24 internal per-rate buckets.

Therefore the rich peer structures present in the Linux vendor API are not backed by this LLSTAT response path in this firmware revision.

This closes the hypothesis that the missing AP client statistics can be recovered simply by parsing a larger LLSTAT response.

The remaining promising routes are now narrower:

1. a dedicated station/LUT event or callback;
2. another command not currently consumed by the Linux driver;
3. adding a new host-visible exporter backed by the already-recovered per-station firmware state;
4. as a last resort, firmware modification.

The immediate next reverse-engineering target is the producer of `WIFI_EVENT_STA_LUT_INDEX/INDICATION` and any neighboring event path that may already export rate/signal fields.

---

# Revision 2 — host-visible export paths

These sections were produced independently of §29–§35 above and overlap with them in places: §29 ↔ §40 (rate formatter), §30–§31 ↔ §39 (GET_STATION handler), §35 ↔ §41 (LLSTAT). Where they overlap they agree. Revision 2 adds: the corrected name-table parse (§36.1), confirmation of `0x00143c0c` as GET_STATION through its response ID (§38), the AP-mode behaviour (§39), the internal rate-descriptor encoding (§40), and the negative results for STA_LUT and WFD_MIB (§41).

Date: 2026-10-02
Method: full Thumb-2 linear sweep of `0x00100130..0x00179200` (Capstone, Cortex-M mode), literal-pool resolution, xrefs by direct `bl`/`b.w` target. Reproduce with `tools/wcnmodem-re.py wcnmodem.bin out/` (writes `fw.S`, `fwtable.txt`, `cmdmap.txt`). All addresses below are runtime addresses with image base `0x00100000`.

## 36. Corrections to revision 1

### 36.1 The command/event name table is `{id, name}`

The word immediately before the first name pointer is the ID of that entry:

```text
0x0017989c  0x00000001        id
0x001798a0  0x0017c348  ->  "WIFI_CMD_GET_INFO"
0x001798a4  0x00000002        id
0x001798a8  0x0017c35c  ->  "WIFI_CMD_SET_REGDOM"
...
```

The table has 96 entries (`0x0017989c..0x00179b9c`) and is consumed by the lookup routine at `0x00142426`:

```asm
ldr   r2, =0x0017989c       ; table base = first id word
ldrh  r4, [r2, r1, lsl #3]  ; entry.id
cmp   r4, r0
...
ldr   r0, [r2 + r1*8 + 4]   ; entry.name
```

Re-parsed with the correct pairing, every ID matches the current Armbian host header:

| ID | Firmware name | Host name |
|---:|---|---|
| 0x01 | WIFI_CMD_GET_INFO | WIFI_CMD_GET_INFO |
| 0x10 | WIFI_CMD_GET_STATION | WIFI_CMD_GET_STATION |
| 0x11 | WIFI_CMD_START_AP | WIFI_CMD_START_AP |
| 0x38 | WIFI_CMD_LINK_STAT | WIFI_CMD_LLSTAT |
| 0x4b | WIFI_CMD_RSSI_MONITOR | WIFI_CMD_RSSI_MONITOR |
| 0x53 | (not in the name table) | WIFI_CMD_SET_WOWLAN |
| 0x89 | — | WIFI_EVENT_RSSI_MONITOR |
| 0xa0 | WIFI_EVENT_NEW_STATION | WIFI_EVENT_NEW_STATION |
| 0xb0 | WIFI_EVENT_CQM | WIFI_EVENT_CQM |
| 0xf5 | WIFI_EVENT_STA_LUT_INDICATION | WIFI_EVENT_STA_LUT_INDEX |
| 0xf9 | WIFI_EVENT_WFD_MIB_COUNTER | WIFI_EVENT_WFD_MIB_CNT |

The "systematic +1 shift" in §4 and §25 was a parse artefact. Each name had been paired with the ID of the *following* entry, which also explains the apparent `DELBA_REQ = 0x38` and `NEW_STATION = 0xb0`. There is no protocol skew to investigate, and the table contains no command that the host does not already know.

### 36.2 `ar_update_tx_statistic_info` is `0x00128554` only

The name string at `0x0017925e` is loaded through the literal at `0x00128918` by two instructions, both inside `0x00128554`:

```text
0x001286a4  ldr r2, [pc, #0x270]  ; =0x0017925e
0x001286f8  ldr r2, [pc, #0x21c]  ; =0x0017925e
```

`0x00128554` (callers `0x00128cc8`, `0x00128d6c`; 24 × 12-byte buckets) is `ar_update_tx_statistic_info`. The routine at `0x001288ca` (caller `0x00132ae4`; three outcome buckets, 100-sample window, 75/25 EWMA) is a different, unnamed function. The first §16 already reflects this ("Adjacent unnamed TX-status quality updater at 0x001288ca").

---

## 37. A large part of the WLAN stack runs from ROM

Many calls and tail-branches leave the image, which ends at `0x001e73b0`:

```text
0x002073a4  command response sender     (33 call sites)
0x00206748  event sender                (20 call sites)
0x002143dc  station-entry lookup by (ctx, index)
0x002053cc  / 0x0021816e  signal readers used by GET_STATION
```

No part of `wcnmodem.bin` maps there. `wcnmodem.bin` therefore extends a mask-ROM WLAN stack: it carries some command handlers, rate control and glue, and calls into ROM for the rest. Handlers for `GET_INFO`, `CONNECT`, `SCAN`, `SET_KEY` and so on are not in the image at all.

Consequence: any field that is maintained only by ROM code (in particular the per-peer RSSI storage behind `0x0021816e`) cannot be located from this image alone.

## 38. Command response sender and handler map

`0x00143c0c` is reached through the callback slot at interface `+0x78c` (§31), and it answers with response ID `0x10`. That confirms it as the `GET_STATION` handler, rather than only a candidate.

`0x002073a4(ctx, cmd_id, status, buf)` sends a command response. Every in-image call loads `cmd_id` into `r1` immediately before the call, which yields this handler map (function entry → command):

| ID | Command | Handler(s) in image |
|---:|---|---|
| 0x0c | SCHED_SCAN | 0x0014199e |
| 0x0d | DISCONNECT | 0x00143732, 0x001468c2 |
| 0x10 | **GET_STATION** | **0x00143c0c** |
| 0x11 | START_AP | 0x001431ec |
| 0x15 | TX_MGMT | 0x00142548, 0x0014257c, 0x00146c58, 0x00146db2 |
| 0x16 | REGISTER_FRAME | 0x00143eb4 |
| 0x17 | REMAIN_CHAN | 0x00146c58 |
| 0x19 | SET_IES | 0x00143a16 |
| 0x1a | NOTIFY_IP_ACQUIRED | 0x001428e2 |
| 0x38 | **LINK_STAT / LLSTAT** | **0x001423d8** |
| 0x39..0x3f | IBSS family | 0x00141d60 .. 0x00141f04 |
| 0x40 | RND_MAC_ADDR | 0x0014363e |
| 0x48 | SPECIAL_DATA | 0x00143970 |
| 0x4b | RSSI_MONITOR | 0x00142306 |
| 0x4c | DOWNLOAD_INI | 0x001423a8 |
| 0x4e | HANG_RECOVERY_START | 0x00141ce8 |
| 0x53 | SET_WOWLAN | 0x00143d3e |
| 0x54 | PACKET_OFFLOAD | 0x001436aa |

The host command dispatcher entry is around `0x0014244a`. It rejects IDs `>= 0x55`, logs the name through `0x00142426`, and indexes per-command byte tables at `0x00179798` and `0x0018ac28`.

## 39. `WIFI_CMD_GET_STATION` handler (`0x00143c0c`)

Reconstructed control flow:

```c
int fw_get_station(int ctx, void *buf /* request reused as response */)
{
    u8 rate[8] = {0};          /* sp+0 .. sp+7 */
    s8 signal = 0;
    void *peer = NULL;
    u8 type = ctx_table[ctx]->type;          /* *(*(0x122e74 + ctx*4)) */

    if (!(type == 0 || type == 2 || type == 5) && rom_state(ctx) != 1)
        return send_rsp(ctx, 0x10, -7, buf);  /* not connected */
    /* (type 0/2/5 additionally require rom_state(ctx) == 1 or < 5) */

    if (type == 0) {                           /* station-type context */
        peer   = rom_sta_entry(ctx, rom_bss_index(ctx));
        signal = rom_signal_ctx(peer);         /* 0x2053cc */
    } else if (type == 2) {                    /* P2P-client-type context */
        peer   = rom_sta_entry(ctx, rom_bss_index(ctx));
        if (peer)
            signal = rom_signal_peer(peer);    /* 0x21816e */
    }
    /* every other context type (AP, GO, ...) leaves peer = NULL, signal = 0 */

    if (rom_channel(ctx) >= 36)
        signal += rom_5g_offset(ctx);          /* 0x218b06 */
    signal = clamp(signal, -100, 63);
    signal += rf_rssi_offset(rom_channel(ctx));/* 0x131f8a */
    if (signal > 0)
        signal = 0;

    if (peer)
        fw_fill_rate_info(ctx, peer, rate);    /* 0x128e90 */

    return rom_build_station_rsp(ctx, signal, rate, buf);   /* 0x206bfc */
}
```

Findings:

1. **The request payload is never read.** There is no MAC or LUT selector, which confirms the host-side observation.
2. The peer is always "the BSS we are connected to" (`rom_bss_index(ctx)`), and only for station-type contexts.
3. **In AP and GO mode no peer is resolved.** The rate block stays all-zero, and `signal` is just the band/channel calibration offsets clamped to `<= 0`. It is not a measurement.
4. The response is built in ROM (`0x00206bfc`) from `signal` and the 8-byte rate block. This matches the host's `struct sprdwl_cmd_get_station` layout (`rate_info`, signal, noise, reserved, txfailed).

**Driver consequence.** `get_station` in AP mode must not copy this reply into every associated station. It now reports only the `ASSOCIATED` flag and per-station connected time; see `package/kernel/uwe5622/patches/120-unisocwifi-ap-mode-report-real-station-data.patch`.

## 40. Per-peer rate formatter (`0x00128e90`)

`fw_fill_rate_info(ctx, peer, out)` produces exactly the host `struct sprdwl_rate_info { u8 flags; u8 mcs; u16 legacy; u8 nss; }` for **any** peer entry:

```text
T     = *(0x17d68c + 4)                       rate-control base
idx   = peer[0]                               LUT/station index
S     = T + idx*0x228 + 0x194                 station state block (§23)
RS    = T + idx*0x228 + 0x1c0                 per-peer rate set, 5-byte entries
mode  = byte at T + idx*0x228 + 0x23d         (S + 0xa9 is set to 1 when mode == 0)

cur   = (mode == 0 || mode == 1) ? S[0xa4] - 1 : S[0xa5]
D     = T + RS[cur*5] * 7                     7-byte rate descriptor

switch (D[3]) {
case 0: case 1:  out.legacy = D[2] * 10;  out.nss = 0;                    break; /* D[2] in Mbit/s -> 100 kbit/s */
case 2:          out.mcs = D[1] & 0x7f;   out.nss = 0; out.flags |= 1;    break; /* HT  -> RATE_INFO_FLAGS_MCS */
case 3:          out.mcs = D[1] & 0x0f;   out.nss = D[4] ? 2 : 1;
                 out.flags |= 2;                                          break; /* VHT -> RATE_INFO_FLAGS_VHT_MCS */
}
if (RS[cur*5 + 3])   out.flags |= 0x40;       /* short GI (host maps BIT(6)) */
if (S[0xad] == 1)    out.flags |= 0x04;       /* 40 MHz */
if (S[0xad] == 2)    out.flags |= 0x08;       /* 80 MHz */
```

This settles several open items from revision 1:

- `S + 0xa5` is the **current TX rate-set index** chosen by rate control (§27). `S + 0xa4` is the rate-set size, used while the state machine is in its initial modes.
- `S + 0xad` is the **peer bandwidth**: 0 = 20, 1 = 40, 2 = 80 MHz.
- The per-peer rate set at `+0x1c0` holds 5-byte entries: descriptor index, ?, ?, SGI flag, ….
- The global 7-byte rate descriptors encode the PHY type (`[3]`: 0/1 legacy, 2 HT, 3 VHT), the MCS (`[1]`), the legacy rate in Mbit/s (`[2]`, scaled ×10 into the host's 100 kbit/s units), and VHT NSS (`[4]`).

Only `GET_STATION` calls `0x00128e90` (single caller, `0x00143d28`). The firmware can describe the TX rate of every peer, but it is only ever asked to do so for the AP we are connected to.

## 41. Other candidate export paths: all negative

| Path | Producer | Payload | Per-peer signal/rate? |
|---|---|---|---|
| `LINK_STAT` (0x38) | `0x001423d8` → subtype 1 → `0x0015ef86` → `0x00207a84` | fixed 0x60 bytes from `*(0x120180) + 0xa8` | **No**: one global block, the aggregate `struct sprdwl_llstat_data` |
| `STA_LUT_INDICATION` (0xf5) | `0x00144406` → `0x00206748` | 11 bytes: `ctx, action, lut, ra[6], ht, vht` | **No**: byte-identical to host `struct sprdwl_sta_lut_ind` |
| `WFD_MIB_COUNTER` (0xf9) | `0x00134c08` → `0x0014415e` | 0x84 bytes: ctx + 4 words from `0x181f3c + ctx*20` + 0x48 + 0x28 copied blocks | **No**: per context (interface), not per peer |
| `NEW_STATION` (0xa0) | ROM | — | not in image |
| `RSSI_MONITOR` (0x4b) | `0x00142306` | configuration only; result events come from ROM | — |

The `wifi_peer_info` / `wifi_rate_stat` structures in host `vendor.h` cannot be filled from any message this firmware sends.

## 42. Conclusion for OpenWrt per-client statistics

Without modifying firmware:

- **Available per peer:** MAC (association events), LUT index, HT/VHT capability (`STA_LUT_INDICATION`), association time (host-side), and host-side TX/RX counters if the driver counts them per LUT (`tx_msg.c` already resolves `dscr->sta_lut_index` per frame).
- **Not available per peer in AP mode:** signal, TX bitrate, retries/failures.

The minimal firmware-side change that would expose the per-peer TX rate is small and uses only existing routines: in the `GET_STATION` handler, when the context is AP or GO and the request carries a LUT index, set `peer = rom_sta_entry(ctx, lut)` and fall through to `0x00128e90`. Per-peer signal would additionally need `0x0021816e(peer)`, whose AP-mode semantics live in ROM and are unverified. This remains a last resort. It also needs answers to questions that are open today:

1. Does the loader verify a checksum or signature over `wcnmodem.bin`?
2. Is there free space, or a patch/hook mechanism, inside the image?
3. Does `0x0021816e` return a meaningful value for an AP-side peer?

## 43. Updated confidence table

| Finding | Confidence |
|---|---|
| name table layout `{id, name}`; IDs equal host wire IDs | High |
| `0x002073a4` is the command response sender, `r1 = cmd_id` | High |
| `0x00143c0c` is the `GET_STATION` handler | High |
| `GET_STATION` ignores the request payload | High |
| `GET_STATION` resolves no peer in AP/GO contexts | High |
| `0x00128e90` formats host `sprdwl_rate_info` for an arbitrary peer | High |
| `S+0xa5` current rate-set index, `S+0xad` bandwidth | High |
| `LINK_STAT`, `STA_LUT`, `WFD_MIB` carry no per-peer signal/rate | High |
| ROM provides response/event senders and RSSI readers | High |
| context type 0 = STA, 2 = P2P client (exact enum values) | Medium |
| meaning of `0x0021816e` for AP-side peers | Unknown (ROM) |

---

# Revision 3 — station table, per-peer RSSI, channel handling, host access

Same image as before (MARLIN3_19B_W21.05.3, linked at `0x00100000`). Driver
patches referenced below live in `package/kernel/uwe5622/patches/`; the
protocol summary for a new driver is in `docs/NEW-DRIVER-ARCHITECTURE.md`.

## 44. AP channel comes from the beacon IEs in `START_AP` (`0x001431ec`)

```c
ds = find_ie(head, 3 /* DS Parameter Set */, &len, head_len);  /* ROM 0x209846 */
if (ds && len > 0 && ds[2] - 1 <= 13) {                          /* channel 1..14 */
        vht = find_ie(head, 0xc0 /* VHT Operation */, &len, head_len);
        if (vht && len > 0)
                vht[0] = 0xff;                                     /* hide VHT op on 2.4 GHz */
}
rom_start_ap(...);                                                 /* ROM 0x209ac4 */
```

- The firmware derives the AP channel from the DS Parameter Set IE of the
  beacon head. hostapd does not put a DS IE into 5 GHz beacons, so without
  it the firmware programs no valid channel. DeepAQ's fix (append a DS IE
  built from the HT Operation primary channel) is ported as patch 180 and
  verified on hardware: 5 GHz ch36 HT20 and VHT80 start with `ret=0`.
- `WIFI_CMD_SET_CHANNEL` (0x07) carries only a `u8` primary channel; it
  cannot describe width or centre frequency.

## 45. RF code asserts instead of rejecting a channel

- `0x00157c20` (RF channel set, `rf_marlin.c:1010`) asserts on
  `!(IS_2G_CHANNEL(pri20) || IS_5G_CHANNEL(center))`; it starts with the
  `ch - 1 <= 13` 2.4 GHz test.
- The channel-context switch callback `0x00151f7a` (`base_chan_clutch`)
  applies the requested channel without validation.

Consequence: anything the host lets through can kill the firmware, and the
host does not recover by itself (§54). Patch 200 advertises only verified
widths and channels so cfg80211 rejects the rest before it reaches the
firmware.

## 46. Rate-control station table: fixed address `0x0017e390`

`0x00126128`:

```asm
ldr  r1, =0x17d68c
ldr  r0, =0x17e390
str  r0, [r1, #4]        ; *(0x17d690) = 0x17e390
movw r1, #0x2420
b.w  0x10bcc6            ; memset(0x17e390, 0, 0x2420)
```

- `T = 0x0017e390`, length `0x2420`: 16 station blocks of `0x228` bytes
  (`15*0x228 + 0x194 + 0x228 = 0x2414 <= 0x2420`). The bytes at
  `0x17d68c` in the file are code; the region is reused as data at run time.
- With `sta = T + idx*0x228` (the base §40 adds `0x194` to), the formatter
  fields in absolute offsets are: mode `sta+0x23d`, rate index
  `sta+0x238` (modes 0/1: value - 1) or `sta+0x239`, rate set
  `sta+0x1c0 + 5*index` (byte 0 descriptor code, byte 3 SGI), bandwidth
  `sta+0x241` (1 = 40, 2 = 80 MHz), descriptor `T + 7*code`.

## 47. The table index is the hardware LUT

`0x001539b0(lut, out, clear)`:

```c
if (lut >= 0x20) return 0;
mac_reg_lock(0x400f20bc);                            /* 0x400f20ec - 0x30 */
src = *(*(u32 *)0x1201d8 + 0xc) + lut * 0x48;        /* MAC per-LUT TX statistics */
memcpy(out, src, 0x48);
if (clear) memset(src, 0, 0x48);
mac_reg_unlock(0x400f20bc);
```

`0x00128554` (`ar_update_tx_statistic_info`, §36.2) calls it with the same
index it uses for the station block. The rate-control index is therefore the
hardware station LUT, the same number the host sees as `sta_lut_index` in
`rx_msdu_desc`/`tx_msdu_dscr` and in `WIFI_EVENT_STA_LUT_INDEX`.

## 48. Per-peer ACK RSSI (resolves §20)

Chain: hardware TX statistics → station block → smoothed average.

1. The 0x48-byte per-LUT block from §47 holds per-rate attempt/success
   pairs, a **signed sum at `+0x40`** and a **count at `+0x44`** (u16).
2. `0x00128554` adds them to the station block when the average fits a
   signed byte (`(sum/count) + 0x80 <= 0xff`):
   `sta+0x3a8 += sum` (s32), `sta+0x3a6 += count` (u16).
   It also accumulates per-rate counters at `sta+0x284 + 12*i`
   (`+4`, `+8`, 24 entries); `0x00126d54` computes `100*[+4]/[+8]` from them
   and compares it with 35.
3. `0x00126d54` (logs with the function name `find_rate0_idx_by_goodput`):

```c
if (count = *(u16 *)(sta+0x3a6)) {
        avg = *(s32 *)(sta+0x3a8) / count;
        if ((u32)(avg + 0x80) <= 0xff) {
                if (sta[0x3a4] == 1)
                        sta[0x3a5] = ((s8)sta[0x3a5] + avg) * 50 / 100;
                else {
                        sta[0x3a4] = 1;
                        sta[0x3a5] = avg;
                }
        }
        *(u16 *)(sta+0x3a6) = 0;
        *(s32 *)(sta+0x3a8) = 0;
}
```

A per-LUT, per-ACK signed value averaged and range-checked as `s8` is taken
to be the client's **ACK RSSI in dBm**: valid flag `sta+0x3a4`, value
`sta+0x3a5`. Confidence medium until compared on hardware with the
client's own reading (patch 230 prints it as `rssi`).

## 49. The rate-control block holds no MAC

`0x001281fe` initialises a block when a station is added:
`memset(sta+0x194, 0, 0x228)`, then `[+0x194] = 7`, clears bits 9..11 of
`u16 [+0x1a8]`, `[+0x238] = 1`, `[+0x23a] = 0xfb` (if the second argument is
set), `[+0x1c0] = 0x12631c()`, `[+0x239] = 0`, `[+0x241] = 0`,
`[+0x280] = 0`, `[+0x281] = 0x63`, `[+0x282] = 0xc6`. No 6-byte copy into the
block exists anywhere in the users of `0x17d68c`. The MAC lives in the ROM
station structure (`rom_sta_entry`, `0x002143dc`, first byte = index). To
attribute a block to a client use the LUT (§47) and the host's
`peer_entry[lut]` MAC (patch 230 prints it as `lut-peer`).

## 50. `GET_STATION` signal path details

In addition to §39: `0x00236694(ctx)` returns the current channel; for
channel `>= 36` the 5 GHz offset `0x00218b06(ctx)` is added; the result is
clamped to `-100..63`, the RF RSSI offset `0x00131f8a(channel)` is added
and positive values are forced to 0. The AP/GO rejection is the
`tst r0, #0xfd` context-type test at the start of the handler: a one-site
patch point if firmware modification is ever attempted (§42).

## 51. Host access to CP memory

- Bus address = CP address + `0x40400000`: the image linked at `0x100000` is
  downloaded to `0x40500000`, and the UWE5622 sync block sits right after it
  at `SYNC_ADDR 0x405E73B0` (`0x40500000 + 0xE73B0`, the image size). The
  BSP's UWE5622 dump table also reads `0x100000` directly.
- Read path: `sprdwcn_bus_direct_read()` → `sdiohal_dt_read()`. On sunxi a
  failed direct transfer sets `dt_rw_fail` and the card-dump status, after
  which every later direct transfer fails and `start_marlin()` refuses to
  run: Wi-Fi is gone until the BSP is reloaded. Read only proven addresses.
  The early `dt_rw_fail` return also leaked the card reference (fixed by
  patch 220).
- Patch 230 (`cp_sta_table` in debugfs) reads `*(0x17d690)` first and only
  reads the table when it equals `0x17e390`.

## 52. No per-frame rate/RSSI on the SDIO RX path

`struct rx_mh_desc` (`data_rate`, `rss1/rss2`, `snr1/snr2/snr_combo`,
`phy_rx_mode`) precedes the MSDU only on PCIe (`mm.c`, address-buffer
path). On SDIO the buffer is `sdiohal_puh` + `rx_msdu_desc` (28 bytes) +
frame. The only possible carrier is a gap when `msdu_offset > 28`; patch 210
(`rx_desc_dump`) records the `msdu_offset` range and raw bytes to check.

## 53. Image integrity

No signature or checksum check of `wcnmodem.bin` was found on the host side.
`CONFIG_AW_BIND_VERIFY` is a chip-binding handshake (16 bytes read from the
sync block, transformed, written back), not an image check. Whether the CP
boot ROM checks the image is unknown; a one-byte change in an unused string
would answer it.

## 54. Assert and recovery flow (host)

With `CONFIG_CP2_ASSERT = 0` (default in `wcn_procfs.c`):

1. CP assert message (`mdbg_assert_read`) or a host-detected command timeout
   (`sprdwl_atcmd_assert` → `mdbg_assert_interface`) stops loopcheck,
   notifies subscribers (`marlin_reset_notify_call(ASSERTED)`) and calls
   `marlin_cp2_reset()` (power off Wi-Fi and BT).
2. On Allwinner (`CONFIG_WCN_POWER_UP_DOWN`) power-off is real:
   `chip_power_off()` unregisters the SDIO driver and removes the card.
3. `sprdwl_ng` (`CP2_RESET_SUPPORT`) stops its TX thread and sends a
   `change` uevent on the `unisoc_wifi` platform device.
4. The vendor expects an Android daemon to reload the driver; the next
   `start_marlin()` powers on, rescans SDIO and downloads the firmware again.

OpenWrt has no such daemon. `uwe5622-recover` + the hotplug handler do the
reload (package files, commit `cb13d24`).

## 55. Confidence (revision 3)

| Finding | Confidence |
|---|---|
| AP channel from the DS IE in START_AP; VHT op hidden on 2.4 GHz | High (code + hardware) |
| RF assert on unprogrammable channel, no validation in the switch callback | High |
| station table at `0x17e390`, 16 x `0x228` | High |
| table index = hardware LUT | High |
| ACK RSSI at `sta+0x3a5` (valid `+0x3a4`) | Medium, pending hardware comparison |
| no MAC in the rate-control block | High |
| bus = CP + `0x40400000`, `SYNC_ADDR` derivation | High |
| no per-frame rate/RSSI on SDIO RX | High (unless the `msdu_offset` gap carries it) |
| no host-side image signature | High; CP boot ROM unknown |

---

# Revision 4 — first hardware readings of the station table

Image: official-kernel build (`build-ib.yml`, run 37418761145), driver
patches 010–230. Board: Orange Pi Zero 3. AP on ch36, `htmode VHT20`,
WPA2-PSK, `max_bw_5g=20`. One Android phone associated, about 1 m away.

## 56. `cp_sta_table` on hardware: LUT mapping holds, first decoder read the wrong index (2026-10-06)

Board, patch 230 output (station lines; raw dump omitted):

```
table 0x17e390 len 0x2420
 0 mode 0 idx   0 code   0 type 0 legacy raw 1 (x10 = 10) sgi 0 bw 20
 1 mode 0 idx   0 code   5 type 1 legacy raw 6 (x10 = 60) sgi 0 bw 20
 4 mode 0 idx   0 code   5 type 1 legacy raw 6 (x10 = 60) sgi 0 bw 20
 6 mode 0 idx  12 code  43 type 3 VHT MCS 9 NSS 1 sgi 1 bw 80 rssi -35 lut-peer 76:85:83:55:68:5e
```

`peer_stats` (patch 150) on the board: LUT 6, ctx 1, MAC
`76:85:83:55:68:5e`, HT 1, VHT 1. The phone reported link speed 433 Mbit/s,
5 GHz, Wi-Fi 5, its MAC `76:85:83:55:68:5E`, signal "high".

Second reading, phone moved to another room (phone: −73 dBm): block 6 is
**byte-for-byte unchanged** (`VHT MCS 9 NSS 1 sgi 1 bw 80 rssi -35`). A
VHT80 MCS9 link is impossible at −73 dBm, so these fields are not the live
rate-control state.

| Finding | Evidence | Confidence |
|---|---|---|
| Table index = hardware LUT (§47) | block 6 ↔ host `peer_entry[6]` = the phone's MAC | **High (hardware)** |
| Rate fields at `sta+0x238..0x241` are the current TX rate (§46) | first reading equalled the phone's 433, but identical at −73 dBm | **Low**: likely the initial (top) rate of the set, not updated |
| ACK RSSI at `sta+0x3a5` (§48) | −35 at 1 m and again at −73 dBm | **Low**: not updating, or updated only on events not seen here |
| Blocks 0, 1, 4 | legacy 1/6 Mbit/s, no RSSI, no host peer: broadcast/management or own entries | Medium |

Working hypothesis: this table keeps per-peer rate-control *configuration*
(rate set, initial index); the live state is maintained elsewhere, possibly
in the ROM part of the WLAN stack (§37). Next step: diff full dumps taken
at different distances and after traffic to find any bytes that change.


### 56.1 Three dumps: the live rate index is `sta+0x239`

Full dumps were taken near the board (phone −25 dBm), in another room
(−69 dBm) and near again (−19 dBm). Inside block 6 (absolute
`0xe84..0x10ac`) only these bytes change:

| Offset in block (`sta+`) | Near −25 | Far −69 | Near −19 | Meaning |
|---|---|---|---|---|
| `0x238` | 13 | 13 | 13 | number of entries in the peer's rate set |
| `0x239` | 12 | **3** | 11 | **current rate index** (rate control) |
| `0x241` | 2 | 2 | 2 | bandwidth, 2 = 80 MHz |
| `0x2e4..0x314` step 12, byte 1 | 100,97,98,96,99 | 0,0,0,0,0 | 0,0,100,100 | per-rate delivery %, rates 8..12 |
| `0x1a0..0x1a7` (two u32) | 1, 1 | 3651, 651 | 3651, 651 | counters, not yet identified |
| `0x3a4`/`0x3a5` | 1 / −35 | 1 / −35 | 1 / −35 | "ACK RSSI": set once, **not updated** |

The rate set of this peer (`sta+0x1c0`, 5 bytes per entry: descriptor code,
?, ?, SGI, ?) decodes through the descriptor table at `T + 7*code`:

| idx | code | rate (80 MHz) |
|---|---|---|
| 0 | 5 | legacy 6 Mbit/s |
| 1–9 | 8,15,19,23,28,33,37,39,41 | VHT MCS0..8, NSS1 |
| 10 | 43 | VHT MCS9 (390) |
| 11 | 43, SGI | VHT MCS9 SGI (433) |
| 12 | 43, SGI, last byte 1 | VHT MCS9 SGI (433) |

So: near the board index 11–12 (433 Mbit/s), at −69 dBm index 3 =
VHT80 MCS2 = 88 Mbit/s. The firmware's rate control works and the current
TX rate to each client is readable. The §40 formatter's `sta+0x238 − 1` for
modes 0/1 is the **top** of the set (patch 230 printed that, hence the
constant output); the live value is `sta+0x239`.

Per-client signal is still missing: `sta+0x3a5` keeps its first value. Per
§48 it is only updated when the hardware per-LUT block reports a non-zero
RSSI count, which apparently does not happen here.

| Finding | Confidence |
|---|---|
| Current TX rate = rate set entry `sta+0x239` | **High (3 hardware points)** |
| `sta+0x238` = rate-set size | High |
| Per-rate delivery % at `sta+0x284 + 12*i` (byte 1) | Medium |
| `sta+0x3a5` is a live RSSI | **Rejected**: static after association |

## 57. The firmware uses 80 MHz although the host configured 20 MHz

Same moment: `iw dev phy0-ap0 info` reports `channel 36 (5180 MHz), width:
20 MHz`, hostapd runs `VHT20`, patch 200 advertises no 40/80 MHz, yet the
client receives at **VHT80**.

Independent evidence: the phone's own statistics showed RX (AP → phone)
390 Mbit/s = VHT80 MCS8 SGI, above any 20 or 40 MHz rate. This does not
depend on the table (§56).

So the operating bandwidth towards a peer is chosen by the firmware (likely
from the peer's VHT capabilities and the firmware's own channel context),
not from the host's channel definition. Patch 200 limits what cfg80211 and
hostapd request; it does not bind the firmware.

Open questions:

- Where the firmware takes the width from: the VHT/HT Operation IEs of the
  START_AP beacon (hostapd writes channel width 0 for VHT20), the peer's
  capabilities in the association, or a default of the channel context
  (`base_chan_clutch`, §45).
- Whether the radio really occupies 80 MHz on air (iperf3 throughput above
  the VHT20 ceiling of ~87 Mbit/s PHY would show it) and what happens on a
  channel where 80 MHz is not allowed (e.g. ch 165, or 140 with DFS off).
- Whether the RF assert of §45 can be reached this way.

Until resolved, the documented default "20 MHz" describes the host
configuration only.

## 58. The RX descriptor gap is the 802.11 header: no per-frame RSSI on SDIO (2026-10-06)

Patch 210 (`rx_desc_dump`) on hardware, iperf3 from the phone (LUT 6), near
(−25 dBm) and far (−70 dBm). `sizeof(rx_msdu_desc)` = 28, `msdu_offset`
38..78.

Near, one sample (descriptor | gap):

```
134eea05f8c3314000011335003d90956c7905000000000200000000 |
8841 5000 1c792d6e5c6d 76858355685e 1c792d6e5c6d 9095 8000 0000000000000000 6c790020
```

Far:

```
133e420008a2324003013337002d40e2479e06000000000200000000 |
8841 3000 1c792d6e5c6d 76858355685e 020001de7788 40e2 0000 0000000000000000 479e
```

- All 28 descriptor bytes map onto `struct rx_msdu_desc` (rx_msg.h): header
  word (type, ctx, offset, length), buffer address, MSDU/MPDU flags and LUT
  index, MAC-header flags + TID + sequence number, PN low/high + cipher,
  `rsvd5` = 0. Near/far differences are flags (first/last MSDU, A-MSDU),
  sequence numbers and PN only.
- The gap between the descriptor and the payload is the received **802.11
  MAC header**: frame control `0x4188` (QoS data, ToDS, protected),
  duration, addr1 = AP, addr2 = client, addr3, sequence control, QoS control
  (A-MSDU bit set in the near case), then PN bytes.
- Nothing in descriptor or gap follows the signal. The only value that
  moves with distance is the Duration field (0x50 near, 0x2c..0x30 far), a
  function of the rate, not of the signal.

Confirms §52: the SDIO RX path carries no per-frame RSSI. Per-client
signal, if anywhere, is in CP memory outside the station table (§56.1):
next step is a bulk read of the firmware data area near/far (patch 260).


## 59. TX power and antennas: what the host can and cannot see (2026-10-06)

Why LuCI/`iwinfo` show no TX power, and why netifd logged
`command failed: Not supported (-95)` on every `wifi up`.

**Host interface.** The only power command is `WIFI_CMD_POWER_SAVE`
sub-type `SPRDWL_SET_TX_POWER` (3), `struct sprdwl_cmd_power_save
{ u8 sub_type; u8 value; }`. The vendor driver uses it only for the SAR
vendor command (`vendor.c`): value `0` selects the "BDF0" SAR limit, `-1`
removes it. There is no reply with a power value and no "get" sub-type.
`SPRDWL_CAPA_TX_POWER` (bit 28 of the `GET_INFO` capabilities) exists, but
nothing in the driver reads a level back. So cfg80211 `get_tx_power` has no
data source, and a number in LuCI would be invented. Patch 280 does not add
one.

**Where the power comes from.** `wifi_2355b001_1ant.ini`, downloaded with
the firmware:

| Section | Keys | Reading |
|---|---|---|
| 2 Board Config | `TxChain_Mask = 2`, `RxChain_Mask = 2` | Only chain 1 is used (one antenna) |
| 3 Board Config TPC | `TPC_Goal_Chain1 = 159,167,162,152,159,167,162,152` | Closed-loop power targets per band group; chain 0 all zero |
| 6 Rate To Power (BW 20M) | `11b_Power`, `11ag_Power`, `11n_Power`, `11ac_Power` | Per-rate offsets (higher MCS → larger value) |
| 7 Power Backoff | `HT40/VHT40/VHT80_Power_offset = 0`, `SAR = 0`, `Mean_Power_offset = 36` | No extra back-off for wide channels |
| 9 Band Edge Power offset | per-channel tables for BW20/40/80 | Edge-channel reductions |

The units are not documented. If `TPC_Goal` is in 1/8 dB the targets are
19–21 dBm, which is plausible for this module, but that is a guess and is
not shown in the UI.

**What wifi-scripts call.** `/lib/netifd/wireless/mac80211.sh` (25.12, ucode)
runs on every start:

```
iw phy phy0 set antenna <tx> <rx>     # "all" = 0xffffffff
iw phy phy0 set distance <distance>   # coverage class
iw phy phy0 set txpower auto          # or "fixed <n>00"
```

Without `set_antenna` and `set_tx_power` cfg80211 answers `-EOPNOTSUPP`
(the two `-95` lines). `set distance` reaches the driver's
`set_wiphy_params` with only `WIPHY_PARAM_COVERAGE_CLASS` set; the driver
then sent `SET_PARAM` with RTS = frag = 0 to the firmware. `sprdwl_set_param`
returns `-ENOMEM` when it cannot get a command buffer, so this is the likely
(not confirmed) source of the occasional `Out of memory (-12)` line.

Patch 280: one antenna (`available_antennas_tx/rx = 1` unless the firmware
reports a mask); `set_antenna` accepts the mask already in effect (cfg80211
has already reduced "all" to it) and refuses others; `set_tx_power` accepts
`auto` and refuses `fixed`/`limited`; `set_wiphy_params` returns early when
neither RTS nor fragmentation changed. A user-set `txpower` in
`/etc/config/wireless` therefore still logs `-95`, which is correct: the
firmware cannot do it.

## 60. Open: where the channel width stops following the host (test plan)

§57 shows the firmware at 80 MHz (rate-control `sta+0x241 = 2`, phone link
390/433 Mbit/s, iperf3 ~160 Mbit/s) while the host configured 20 MHz. So
`max_bw_5g=20` limits the host configuration only. Hypothesis, unconfirmed:
the firmware picks the width from its own and the client's VHT capabilities
and ignores the host `chandef`.

Matrix, same client, same place, channel 36:

| `max_bw_5g` / htmode | `START_AP` log (patch 170: `chandef`, `ds`, `ht_pri`, `ht_sec`, `vht_w`, `vht_cf0`) | `sta+0x241` (`cp_sta_table`) | phone link rate | iperf3 |
|---|---|---|---|---|
| 20 / VHT20 | ? | ? | ? | ? |
| 40 / VHT40 | ? | ? | ? | ? |
| 80 / VHT80 | ? | ? | ? | ? |

Chain to locate the break: cfg80211 `chandef` → beacon HT/VHT Operation →
`START_AP` command → CP station table bandwidth → client PHY rate. If
`sta+0x241` stays 2 in all three rows, the host width is decorative for the
firmware, and the next step is the `START_AP` / `NEW_STA` fields the firmware
actually reads for bandwidth.

## 61. Recovery on hardware: a driver reload cannot restart the chip (2026-10-06, r15)

`uwe5622-recover` run by hand on a Zero 3 with an AP and a client:

1. `rmmod sprdwl_ng` → `marlin power off`, `sdiohal_remove`.
2. `insmod sprdwl_ng` → `start_marlin`, SDIO card found, firmware written
   ("combin_img 0 ... successful"), but `marlin_start_run read reset reg
   val:0x0` (a cold start reads `0x1`), `marlin_write_cali_data sync
   init_state:0x0` repeated, `check_cp_ready sync val:0x0`, card dump,
   `marlin download timeout`, `probe ... failed with error -1`.
   The BSP's power control is "chip en dummy" on this board: the chip is
   never reset, and a firmware downloaded into it does not start.
3. Both modules unloaded, `4021000.mmc` unbind/bind (`mmc0: card 8800
   removed` / `new high speed SDIO card`), BSP and driver loaded:
   `reset reg val:0x1`, cali sync `0xf0f0f0f1`, CP ready, AP up again
   (as **phy2**: phy numbers keep counting, so nothing may assume phy0).
   About 10 s.

So the only working recovery on the Zero 3 is the host reset (wifi-pwrseq
toggles PG18). From r16 `uwe5622-recover` does that directly; the driver
reload step, which cost ~60 s and a card dump, is gone.

## 62. VHT80 configured on the host: host and firmware agree (2026-10-06, r15)

With `max_bw_5g=80` and htmode VHT80 on channel 36 (`iwinfo`: HT Mode VHT80,
center channel 42) the per-client TX rate read from the firmware (patch 240)
stays at VHT-MCS 9, 80 MHz, short GI, 1 stream (433.3 Mbit/s) for two
clients; 1 h 14 min with moderate traffic, no assert, SoC ~54 °C. With
`max_bw_5g=20` the firmware also used 80 MHz with the same clients (§57,
§60), so the only change is that the host configuration now says what the
air does. `max_bw_5g` defaults to 80 from r17. Open: whether the firmware
honours a host width *below* what the client supports (the §60 matrix
row 20/VHT20 says no).

## 63. Wi-Fi RAM at `0x40300000`: hardware per-LUT tables, and a firmware command for a per-context MAC (2026-10-06, static)

Second pass over `wcnmodem.bin` (sha256 `119b87ce…a80`) with two questions:
where the hardware keeps per-client data that §56.1 could not find in the
image RAM, and how the AP interface could get its own MAC (repeater).

### 63.1 Readable windows, from the vendor's own crash dump

The BSP crash dump for UWE5622 (`unisocwcn/platform/wcn_dump.c`,
`include/uwe562x_glb.h`, `include/uwe5622_glb.h`) reads, besides the image
RAM (CP `0x100000` = bus `0x40500000`, §51), these bus addresses directly
with `sprdwcn_bus_direct_read()`, after checking the Wi-Fi power domain:

| Bus address | Size | Vendor name |
|---|---|---|
| `0x400f0000` | `0x120` | `WIFI_AON_MAC` |
| `0x400f1000` | `0xd100` | `WIFI_RTN_PD_MAC` (MAC registers) |
| `0x40300000` | `0x4a800` | `WIFI_352K/298K_RAM` |
| `0x400b0000..0x400b7618` | small | PHY/RF interface registers |

The firmware uses the same addresses (literal `0x4034a800` = end of the
`0x4a800` RAM), so for peripherals CP address = bus address; only the image
RAM is offset. `cp_mem` (patch 260) covers none of these windows.

### 63.2 Hardware per-LUT tables in Wi-Fi RAM

`0x001532e0` (MAC init) stores buffer addresses in the global block
`*(0x1201d8)` and programs them into MAC registers; `0x001532a8` does the
same for the TX-statistics buffer and clears it:

| Bus address | Size | Layout | Programmed into | Used by the image |
|---|---|---|---|---|
| `0x40340000` | `0xc80` | 32 × `0x64` (one per LUT) | `0x400f1174` | `+0x30..+0x3c` written on key/PN setup (`0x155bc4`); `+0x43` bit 7, `+0x4c` bit 15, `+0x4e` read (`0x155e18..0x155e4a`) |
| `0x40340c80` | `0x200` | — | `0x400fc058` | not read by the image |
| `0x40340e80` | `0x200` | 32 × 16? | `0x400f1174 + 8` | not read by the image |
| `0x40341080` | `0x200` | 32 × 16? | `0x400f1174 + 0x10` | not read by the image |
| `0x40341280` | `0x200` | 32 × 16? | `0x400fc058 - 0x18` | not read by the image |
| `0x40341480` | `0x200` | 32 × 16? | `0x400fc058 - 0x10` | not read by the image |
| **`0x40341680`** | **`0x900`** | **32 × `0x48`** | `0x400f20b4` | `0x001539b0` (§47): copy + clear per LUT |

So the "MAC per-LUT TX statistics" block of §47/§48 is **not** a register
window but a buffer the MAC writes at `0x40341680 + lut*0x48`; its
`+0x40` (s32 sum) / `+0x44` (u16 count) are the ACK-RSSI accumulators that
feed `sta+0x3a5`. `0x001539b0` selects the LUT in `0x400f8758` (bits 0..5),
locks `0x400f20bc`, copies and clears.

Why `sta+0x3a5` never moved on hardware (§56.1) has two candidate reasons,
both testable by reading `0x40341680` directly:

1. the count at `+0x44` stays 0 (the MAC does not collect ACK RSSI in this
   configuration), or
2. the average is outside `-128..127` (`(sum/count) + 0x80 <= 0xff` fails),
   for example because the hardware sums in a finer unit; then the
   firmware discards every sample, while the host can still scale it.

The four 16-byte-per-LUT tables are filled by hardware only (no reader in
the image; the ROM may read them). A per-LUT RX signal value, if the MAC
keeps one, would be in one of them or in the 100-byte station entry.

### 63.3 `WIFI_CMD_RND_MAC_ADDR` (0x40), subtype 2: set a context's MAC

Handler `0x0014363e(ctx, buf)`: `ctx >= 3` → error; subtype = `buf[0xc]`
(the first payload byte after the command header), MAC = `buf + 0xd`.

| Subtype | Handler | What it does |
|---|---|---|
| 0, 1 | `0x0014358a` | scan random address; only for context type 0 (station), else `-8` |
| **2** | **`0x001435ee`** | MAC must be unicast (bit 0 of byte 0 clear, else `-8`); then ROM `0x231466(ctx, mac)`, `0x218742(ctx, mac)`, and `0x2026d8(ctx, 0x21876a(ctx))` (writes the address to the MAC hardware). **No context-type check.** |

The host already has this command: `wlan_cmd_set_rand_mac(priv, ctx_id,
SPRDWL_CONNECT_RANDOM_ADDR (= 2), addr)` in `rnd_mac_addr.c`, used before
connect when a station has a random MAC (`cfg80211.c`, `has_rand_mac`).
`RND_MAC_SUPPORT` is enabled in the build. What is missing is the AP side:
`sprdwl_set_mac()` (`main.c`) stores a new address only in STATION mode,
so with OpenWrt's per-interface MACs the AP context keeps the chip MAC,
identical to the station context (repeater failure, TEST-PLAN S5).

### 63.4 Next steps

1. **Repeater:** driver patch: accept the address in AP mode too
   (`sprdwl_set_mac`), and send subtype 2 for the AP context before
   `START_AP` when its address differs from the chip MAC. Test S5.
2. **Per-client signal:** debugfs reader for the bus windows above
   (`0x40340000..0x40341f80` first, 8 KB, inside the vendor-dumped
   `0x40300000` window), decoded per LUT; then the near/far/near test
   of §56.1 on this window. The `0x40341680` block is cleared by the
   firmware on each rate-control poll, so a read shows a partial sum/count;
   the ratio is still the average.

| Finding | Confidence |
|---|---|
| Per-LUT TX-statistics buffer at bus `0x40341680`, 32 × `0x48` | High (static: allocation, size `0x900`, register write, reader §47) |
| Per-LUT 100-byte station entries at `0x40340000` | Medium (stride and users; meaning of fields open) |
| Windows readable over SDIO | High for the vendor-dumped ranges (vendor crash dump reads them); read only while Wi-Fi is up |
| Subtype 2 of command 0x40 sets the MAC of any context `< 3` | High (static); not yet tried on hardware |

## 64. Beacon assembly is in ROM; the image passes hostapd's template through (Country IE question, 2026-10-08)

A tester set `country 'DE'` and saw no Country element (IE 7) in the air.
OpenWrt's wifi-scripts set `ieee80211d=1` by default when a country is set,
so hostapd puts the Country IE into the beacon tail; the host driver copies
head and tail unchanged into `WIFI_CMD_START_AP` (it only appends a DS
Parameter Set IE when missing, patch 180).

In the image:

- `START_AP` handler `0x001431ec`: rejects templates longer than `0x300`
  bytes (status `0x11`), edits the DS (3) / VHT Operation (`0xc0`) IEs
  (§44) and hands the template to ROM `0x00209ac4`. Nothing else is read
  or removed.
- `WIFI_CMD_SET_IES` (`0x19`) handler `0x00143a16`: IE set type < 5,
  length 1..`0x165`, passed to ROM as well.
- The image's IE lookups (ROM `find_ie` `0x00209846`) are for IDs 3,
  `0xc0`, `0xdd` (vendor, `0x147044`) and `0x3b` (supported operating
  classes, `0x1631d0`). No code in the image builds, reads or strips a
  Country IE.

So whether the Country IE reaches the air is decided in ROM, which is not
in `wcnmodem.bin` and cannot be read statically. Open, on hardware:

1. hostapd config has `country_code=DE` and `ieee80211d=1`
   (`/var/run/hostapd-phy0.conf`);
2. the element is in beacons and/or probe responses (sniffer);
3. if hostapd sends it and the air has none, ROM drops it: then the next
   step is a ROM read over SDIO (only addresses proven readable, §51/§63.1).

The regulatory rules themselves (channels, power) go to the firmware
separately (`WIFI_CMD_SET_REGDOM` from the driver's reg notifier) and do
not depend on the Country IE.

## 65. A TV-box firmware: what the build identity says (2026-10-08)

Facts:

- The firmware reports `Platform Version: MARLIN3_19B_W21.05.3`,
  `Project Version: sc2355_marlin3_lite_ott`, built 2021-12-15 (every boot
  log, `WCND at cmd read`).
- `marlin3_lite` is the chip: the vendor BSP calls the UWE5622 Marlin3 Lite
  (`*_M3L` sizes in `uwe562x_glb.h`); it is not a "lite firmware" flag.
- `ott` is the product line the build is for: over-the-top TV boxes.
- The vendor host driver is built with `-DOTT_UWE` (unisocwifi/Makefile),
  which switches the TX descriptor offsets and a TLV in `WIFI_CMD_GET_INFO`
  handling (`cmdevt.c`, `tx_msg.c`) to the OTT variant.
- No newer public `wcnmodem.bin` for the UWE5622 is known.

Reading (not a vendor statement): the firmware is tuned for a TV box that
joins a home network. Its AP side is minimal and fragile, which matches
what this project kept running into: channel from the beacon IEs (§44),
asserts on channels it cannot tune (§45), no per-peer signal/rate in AP
mode (§37–§43, §56), beacon assembly in ROM (§64).

## 66. Assert `pri20_offset == NO_OFFSET` on repeater teardown (2026-10-08)

Seen once in a repeater stress test (TEST-PLAN, "Repeater stress test"):
AP and station on 2.4 GHz channel 2 (the AP had followed the station's
channel, OpenWrt restarted it there), both up and stable for 7 s; on
`wifi` the station was disconnected (`reason=3 locally_generated`) and,
0.2 s before the host tore the interfaces down, the firmware asserted:

    WCN Assert in rf_marlin.c line 1016, pri20_offset == NO_OFFSET

`pri20_offset` is the position of the primary 20 MHz channel inside the
operating bandwidth (the RF code keeps it per channel context). Reading:
the deauth/close of the station context left a channel context whose
offset is unset, and the RF code checks it on the next tune. Not
reproduced on purpose yet; the AP-only loop never hit it. The chip reset
path (`marlin_cp2_reset` → `uwe5622-recover`) worked.


## 67. Static follow-up: why ACK-RSSI candidate remains static (2026-10-08)

Detailed fresh Thumb-2 reconstruction, exact instruction excerpts, reproducible
analyzer and conclusions:
[UWE5622-ACK-RSSI-STATIC-ANALYSIS.md](UWE5622-ACK-RSSI-STATIC-ANALYSIS.md)
and [tools/wcnmodem-ack-rssi.py](../tools/wcnmodem-ack-rssi.py).

- Firmware maps a 0x900-byte (32 x 0x48) TX-statistics buffer to bus
  0x40341680 and sets its address in the MAC configuration (0x1532a8,
  0x1532e0).
- Firmware's 0x1539b0 snapshots the chosen LUT's 0x48-byte record and can
  clear that record. 0x128554 calls it with clear=1: a transient zero in
  hardware RAM would not prove sampling is disabled.
- At 0x128710-0x128750 the signed sum/count from offsets +0x40/+0x44
  enters software accumulation only if count > 0 and sum/count is in
  [-128,127]. At 0x126d54 the software accumulator is smoothed into
  sta+0x3a5 after the same range test and reset even on rejection.
- Therefore the stale hardware-test value at sta+0x3a5 does **not** prove
  that the hardware ACK count stays at zero. Candidate explanations are:
  no hardware samples; a signed-average range rejection (possible
  scaling/unit mismatch); a conditional software processing path; or
  incorrect interpretation of the fields as RSSI. None is proven.
- MAC/ROM configuration and the meaning of CHIP_SLP bits on UWE5622 are
  still not established. Do **not** enable wifi_ram_force=1 or read unknown
  power-domain windows to resolve this. No router or firmware was modified.

This section refines, rather than replaces, the mapping in sections 47-48
and 63.2. RX rate remains deliberately out of scope.

Open firmware tasks, separate from the beta2 work; `wcnmodem.bin` stays
unmodified until both are done:

1. One-byte integrity test: change one byte of a diagnostic string whose
   cross-references were checked first. Not `WCN_VER`: the version string
   may take part in the CP/host handshake. A clean boot proves only that
   this change is not rejected, not that the chip checks nothing; a failed
   boot needs its cause analysed.
2. Trace `switch_cp2_log` end to end (host command, CP2 log control, log
   transport, host receive) and find whether the values before the range
   filter at 0x128554 can be logged without touching rate control. The
   stock log may not contain them.

A modified firmware is published only as a separate debug package, never in
the images, and only once the right to redistribute a modified binary is
established (the firmware is proprietary).


## 68. CP2 firmware logging traced end-to-end (2026-10-08, static)

Full source-level research: [UWE5622-CP2-LOG-STATIC-ANALYSIS.md](UWE5622-CP2-LOG-STATIC-ANALYSIS.md).

- `switch_cp2_log(flag)` in the pinned vendor `loopcheck.c` sends
  `at+armlog=1/0\r\n` over SDIO AT TX and waits up to 3 s for the
  reply. Allwinner's `CONFIG_CPLOG_DEBUG` is not enabled: after
  `get_cp2_version`, normal boot invokes `switch_cp2_log(false)`.
- `/proc/mdbg/at_cmd` is an existing host control interface. Writing
  `at+armlog=1` first invokes `wcn_debug_init()` to prepare the
  file sink and then forwards the command. The AT reply arrives on RX 13;
  logs arrive **separately** on SDIO RX 15.
- With no `CONFIG_WCND` in our Allwinner profile, log RX dispatches
  into `log_rx_callback()`, **not** `mdbg_ring_write()`. Thus neither
  `dmesg` nor `/dev/slog_wcn0` is the normal sink. Vendor defaults may
  create `/etc/unisoc_cp2log_*.txt`: dangerous for OpenWrt overlay.
- The pinned `wcnmodem.bin` contains AT diagnostic command strings
  `+ARMLOG`, `+LOGLEVEL`, `+LOGSWITCH`, `+FLUSHWCNLOG`; their detailed
  CP-side implementations may be in ROM. No proven stock message exposes
  the per-LUT pre-filter `sum/count` values needed to resolve RSSI.
- This is **static analysis only**; no firmware, driver, image or
  router configuration changed. Enabling or patching firmware logging is
  postponed until after the repeater beta2 investigations.

