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

## 16. Recovered per-peer TX quality statistics inside firmware

A deeper Thumb-2 pass located the firmware routine referenced by the embedded function name:

```text
ar_update_tx_statistic_info
```

The function begins at approximately:

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

The same firmware image contains the function-name string:

```text
0find_rate0_idx_by_goodput
```

immediately adjacent in the internal symbol-name area to:

```text
ar_update_tx_statistic_info
```

This strongly suggests the recovered counters belong to the adaptive-rate/goodput algorithm.

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

## 16. Rate-control/statistics pipeline recovered

A broader search for all references to the same station-indexed memory region found a second highly relevant firmware function.

The embedded string:

```text
ar_update_tx_statistic_info
```

is referenced from a literal pool at approximately `0x00128918`.

The associated Thumb-2 function starts at approximately:

```text
0x00128554
```

and has at least two direct call sites:

```text
0x00128cc8
0x00128d6c
```

This routine uses the same station/LUT index extraction pattern as `update_sta_lut_data()`:

```asm
ldrb  r5, [r1]
add.w r0, r5, r5, lsl #2
add.w r1, r0, r5, lsl #6
...
add.w r6, base, r1, lsl #3
```

which again yields an index stride of:

```text
0x228 bytes
```

### Important terminology correction

The current evidence proves a **station-indexed stride of 0x228 bytes**.

It does **not** yet prove that a single C structure is exactly 0x228 bytes long.

Several routines access multiple station-indexed memory lanes at fixed offsets from the same global base, for example around:

```text
+0x194
+0x248
+0x284
```

while retaining the same `index * 0x228` spacing.

The safest description is therefore:

> firmware maintains station-indexed state with a 0x228-byte index stride across several related state/statistics regions.

This wording replaces the earlier stronger "record size" interpretation.

---

## 17. 24 internal TX/rate statistic buckets

`ar_update_tx_statistic_info()` operates on a table beginning at the station-indexed region around:

```text
base + station_index * 0x228 + 0x284
```

A loop iterates exactly:

```text
0x18 = 24
```

entries.

Each entry is addressed with a 12-byte stride:

```asm
add.w r1, r5, r5, lsl #1
add.w r1, r4, r1, lsl #2
```

which is equivalent to:

```text
entry = table + index * 12
```

Within each entry, two 32-bit fields at offsets `+4` and `+8` are accumulated/updated.

Another loop computes:

```text
value = counter_at_+4 * 100 / counter_at_+8
```

when the denominator is at least 3.

That result is stored in a temporary array and the per-bucket counters are then cleared.

This is strong evidence for a firmware-internal rate/statistics table.

The exact semantic names of the two counters are not yet proven, but their usage is consistent with a success/goodput/retry quality ratio used by automatic rate control.

---

## 18. `find_rate0_idx_by_goodput` located

The embedded string:

```text
find_rate0_idx_by_goodput
```

is directly referenced from the function beginning at approximately:

```text
0x00126d54
```

This function reads the same 24-entry statistics table used by
`ar_update_tx_statistic_info()`.

For every bucket it:

1. checks the denominator/counter at entry offset `+8`;
2. when at least three samples exist, computes:

```text
(entry+4) * 100 / (entry+8)
```

3. records the resulting percentage;
4. clears the two counters;
5. scans the resulting 24-element quality array to select/update rate-control state.

The function also maintains a signed averaged metric using two adjacent aggregate fields around:

```text
stats + 0x122  (16-bit count)
stats + 0x124  (32-bit accumulated value)
```

It computes:

```text
average = accumulated_value / sample_count
```

and stores a smoothed signed byte at approximately:

```text
stats + 0x121
```

with a 50/50 update when a previous value exists.

The exact physical meaning of this signed metric is not proven yet. It must not be labelled RSSI until a producer xref confirms that interpretation.

---

## 19. Relationship between station status and rate statistics

We now have two concrete firmware-side stages:

```text
update_sta_lut_data()
    |
    | 24-byte packed station/capability status
    v
station-indexed state (+0x194 lane)

ar_update_tx_statistic_info()
    |
    | TX/rate samples
    v
24 x 12-byte statistic buckets (+0x284 lane)
    |
    v
find_rate0_idx_by_goodput()
    |
    | percentage/quality calculation
    | bucket reset
    | rate selection / smoothing
    v
automatic rate-control state
```

This confirms that the firmware has per-station rate-control statistics that are substantially richer than the current Linux `GET_STATION` response.

---

## 20. New implication for per-client OpenWrt statistics

The most promising path is now more specific.

The firmware already computes per-station, per-rate data internally.

The host driver already defines:

```c
struct wifi_peer_info
struct wifi_rate_stat
```

but does not populate them in the current LLSTAT implementation.

Therefore the next reverse-engineering target is to identify a firmware routine that serializes either:

- the 24 internal rate buckets;
- the selected/current rate derived from them;
- the smoothed station metric;
- retry/failure counters;

into a host response or event.

If such an existing exporter exists, OpenWrt can gain real per-client statistics without patching firmware.

---

## 21. Useful embedded diagnostic strings for the next pass

Relevant strings already located in the image include:

```text
[ds:0x%02x ts:0x%02x retry:%d fc:%d]
calc_roam_factor rssi=%d, trigger=%d
send_notify_cqm_to_host rssi_low_count=%d, beacon_link_loss=%d
low rssi, rssi
roam_param_init, rssi_thold=%d
Unexpected station entry LUT index
machw_lut.c
mcc_station.c
ce_lut.c
```

These provide additional anchors for separating:

- real RSSI/RCPI paths;
- TX descriptor retry counters;
- station LUT management;
- rate-control statistics.

The next step is to follow xrefs from the explicit RSSI strings and determine whether those routines access the same station-indexed state.


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
