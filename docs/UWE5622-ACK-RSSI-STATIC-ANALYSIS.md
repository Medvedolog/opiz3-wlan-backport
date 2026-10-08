# UWE5622/SC2355: static analysis of per-LUT TX statistics and candidate ACK RSSI

Date: 2026-10-08. **Static analysis only: no SDIO reads, firmware modification, runtime test or changes to driver/kernel.**

## Scope and reproducible inputs

- Firmware: UNISOC Marlin3 Lite, build MARLIN3_19B_W21.05.3, project sc2355_marlin3_lite_ott, 2021-12-15.
- Image size: 947120 bytes; SHA-256: 119b87ce30875734a67462f7293fb8fe85acf3270fe8b78c978ae24be7715a80.
- Immutable upstream binary: https://raw.githubusercontent.com/armbian/firmware/612bc7cc0e3539ea89c659049b7d8432e2de8ed7/uwe5622/wcnmodem.bin
- Vendor host/BSP source: https://github.com/armbian/uwe5622/tree/cc2835a3f935d5297e03cdce464c1785381a7b4d
- Host package pinning: package/firmware/uwe5622-firmware/Makefile and package/kernel/uwe5622/Makefile.
- Earlier deductions and hardware observations: WCNMODEM-REVERSE-ENGINEERING.md, especially sections 37, 46-48, 51, 56.1, 63.1-63.2.
- Reproduction program committed alongside this document: ../tools/wcnmodem-ack-rssi.py. It verifies the firmware's hash, resolves Thumb-2 PC-relative literals, emits address-tagged disassembly slices and enumerates image-wide occurrences of significant 32-bit constants. Requires Python 3 + Capstone, *not* a router.

Reproduce:

~~~sh
curl -fL -o wcnmodem.bin \
  https://raw.githubusercontent.com/armbian/firmware/612bc7cc0e3539ea89c659049b7d8432e2de8ed7/uwe5622/wcnmodem.bin
sha256sum wcnmodem.bin
python3 -m pip install capstone
python3 tools/wcnmodem-ack-rssi.py wcnmodem.bin /tmp/uwe5622-ack-rssi
# generated: ack-rssi-sites.S, ack-rssi-literals.txt, ack-rssi-call-map.txt
~~~

Firmware CPU addresses below assume Cortex-M Thumb-2, image base 0x00100000. The *physical* Wi-Fi MAC window 0x403xxxxx is not the image address translated by +0x40400000: it is a separate directly addressed peripheral/RAM window.

## Executive conclusion

**Established:** The firmware configures a 0x900-byte per-LUT TX-statistics buffer at bus 0x40341680 and passes its address into MAC configuration. It has a reader that copies 0x48 bytes for a selected LUT, optionally clears the hardware-side buffer, and feeds the rate-control path. The software path interprets a signed 32-bit sum and unsigned 16-bit count from offsets +0x40 and +0x44; it averages only when count is nonzero and the signed quotient is in [-128, 127]. A later consumer maintains a smoothed signed-byte value in the rate-control station state and clears its software accumulators, including when the average is rejected.

**Not established:** That MAC hardware actually writes ACK RSSI to those fields in this firmware configuration; the physical units or source of the sum; which hardware/ROM setting gates collection; the update cadence; or whether the unmoving AP-side value is due to zero samples, an out-of-range average, a disabled/conditional rate-control path, or something else. The "ACK RSSI" name is an interpretation based on per-LUT TX/ACK-oriented statistics and signed accumulation, *not* proof of signal units.

The earlier hardware observation (section 56.1) found a changing live rate index (12 -> 3 -> 11) while the putative RSSI byte stayed -35 at near/far/near distances. This proves TX rate control is active, **not** that the hardware count at +0x44 remained zero: that count was not sampled.

## 1. Initialization: 0x001532a8 / 0x001532e0

The first routine accepts a TX-statistics base address in r0 and stores it in the firmware-global structure found through *(u32 *)0x001201d8, offset +0x0c. It calls an initialization/clear helper with a byte count of 2304 (0x900 = 32 * 0x48), and programs the MAC register at 0x400f20b4. The source of the argument can be followed to the literal 0x40341680 used by the subsequent initialization sequence.

Relevant instructions (Thumb-2, address and encoded bytes retained):

~~~asm
001532a8: 10b5       push    {r4, lr}
001532aa: 0446       mov     r4, r0
001532ac: fe48       ldr     r0, [pc, #1016]  ; literal 0x1536a8 -> 0x001201d8
001532ae: 4ff41061   mov.w   r1, #2304         ; 0x900
001532b2: 0068       ldr     r0, [r0]
001532b4: c460       str     r4, [r0, #12]    ; global->tx_statistics_base
001532b6: 2046       mov     r0, r4
001532b8: b8f705fd   bl      <buffer-clear helper>
001532bc: 2146       mov     r1, r4
001532be: fb48       ldr     r0, [pc, #1004] ; literal 0x1536ac -> 0x400f20b4
001532c0: 25f00afe   bl      <MAC register programming helper>
001532e0: 10b5       push    {r4, lr}
001532e4: f34a       ldr     r2, [pc, #972]  ; literal 0x1536b4 -> 0x40340c80
001532e6: f249       ldr     r1, [pc, #968]  ; literal 0x1536b0 -> 0x40340000
001532ea: c0e90612   strd    r1, r2, [r0, #24]
0015339a: cc48       ldr     r0, [pc, #816]  ; literal 0x1536d4 -> 0x40341680
~~~

Note: 0x0015339a is part of the following routine and merely illustrates the literal use; it is **not** the call site into 0x001532a8. The exact full call chain is preserved by the regeneration tool. The literal 0x40341680 occurs once in the pinned image at 0x001536d4. The register address 0x400f20b4 occurs in the literal pools at 0x001536ac, 0x00179cfc and 0x0017adf8 (the latter two need not be executable references).

The initialization at 0x001532e0 also configures the other Wi-Fi MAC tables: 0x40340000, 0x40340c80, 0x40340e80, 0x40341080, 0x40341280 and 0x40341480. These are distinct from the per-LUT TX-statistics buffer.

## 2. Read, lock and conditional clear: 0x001539b0

The LUT reader is called by 0x00128554 at 0x001285d0. It rejects LUT indices >= 32, obtains the TX-statistics base pointer via *(0x1201d8) + 0x0c, computes base + LUT * 0x48, interacts with a MAC LUT-selector at 0x400f8758 and a lock-related address 0x400f20bc (0x400f20ec - 0x30). Its arguments are LUT, output buffer and clear flag.

~~~asm
001539b0: f8b5       push    {r3, r4, r5, r6, r7, lr}
001539b2: 1546       mov     r5, r2              ; clear
001539b4: 0e46       mov     r6, r1              ; output
001539b6: 0446       mov     r4, r0              ; LUT
001539b8: 2028       cmp     r0, #32
001539da: 3d48       ldr     r0, [pc, #244]    ; 0x001201d8
001539dc: 04ebc401   add.w   r1, r4, r4, lsl #3
001539e2: 0068       ldr     r0, [r0]
001539e6: c068       ldr     r0, [r0, #12]
001539e8: 00ebc104   add.w   r4, r0, r1, lsl #3 ; LUT * 72
00153a08: 4822       movs    r2, #72
00153a0a: 2146       mov     r1, r4
00153a0c: 3046       mov     r0, r6
00153a0e: b8f7aaf8   bl      <copy 0x48 bytes>
00153a12: 012d       cmp     r5, #1
00153a2a: 4821       movs    r1, #72
00153a2c: 2046       mov     r0, r4
00153a2e: b8f74af9   bl      <clear 0x48 bytes>
~~~

This is a **destructive snapshot** when clear=1. Empty or small values returned by a separately timed reader would not automatically mean that collection is disabled. It may have raced the firmware's normal polling/clear.

## 3. Producer/consumer on firmware side: 0x00128554

The rate-control updater 0x00128554 is reached from 0x00128cc8 and 0x00128d6c, and calls the per-LUT reader at 0x001285d0. It initializes a 72-byte temporary region (stack + 220), invokes the reader with clear=1, and processes rate/outcome counters.

~~~asm
00128576: 4821       movs    r1, #72
00128578: 37a8       add     r0, sp, #220
0012857e: e3f7a2fb   bl      <memory initialization helper>
001285ca: 0122       movs    r2, #1            ; destructive snapshot
001285cc: 37a9       add     r1, sp, #220
001285ce: 4046       mov     r0, r8           ; LUT
001285d0: 2bf0eef9   bl      0x001539b0
00128710: 0604       lsls    r6, r0, #16
00128712: 4798       ldr     r0, [sp, #284]    ; sum
00128714: 360c       lsrs    r6, r6, #16     ; count (u16)
00128718: 26d0       beq     <no samples>
0012871a: 95fbf6f7   sdiv    r7, r5, r6       ; signed sum / count
00128738: 07f18000   add.w   r0, r7, #128
0012873c: ff28       cmp     r0, #255
0012873e: 0ad8       bhi     <discard average>
00128740: d4f82401   ldr.w   r0, [r4, #292]  ; station accumulator
00128744: 2844       add     r0, r5
00128746: c4f82401   str.w   r0, [r4, #292]
0012874a: b4f82201   ldrh.w r0, [r4, #290]  ; sample count
0012874e: 3044       add     r0, r6
00128750: a4f82201   strh.w r0, [r4, #290]
~~~

The 72-byte source structure has a signed sum at +0x40 and a u16 count at +0x44. The software station fields above map to sta+0x3a8 (signed sum) and sta+0x3a6 (count), since the local register r4 references sta+0x284 at this point. The conditional path checks signed mean within -128..127 *before* accumulation. There is no automatic scale-factor conversion to dBm in this path.

## 4. Smoothed per-station value: 0x00126d54

This next stage divides software accumulator by count; when the result fits signed 8-bit range, it sets or smooths the byte at sta+0x3a5 using 50/100 EWMA-like arithmetic. The validity marker is sta+0x3a4. Crucially, both software accumulator fields are reset afterward even if the range check failed.

~~~asm
00126d94: b4f82201   ldrh.w  r0, [r4, #290]  ; sta+0x3a6
00126d98: 10b3       cbz     r0, <skip if count zero>
00126d9a: d4f82411   ldr.w   r1, [r4, #292]  ; sta+0x3a8
00126d9e: 91fbf0f3   sdiv    r3, r1, r0
00126da2: 03f18002   add.w   r2, r3, #128
00126da6: ff2a       cmp     r2, #255
00126da8: 26d8       bhi     <skip update>
00126db2: 0120       movs    r0, #1
00126db4: 84f82001   strb.w  r0, [r4, #288]  ; sta+0x3a4
00126db8: 84f82131   strb.w  r3, [r4, #289]  ; sta+0x3a5
00126de6: 3221       movs    r1, #50
00126dea: 4843       muls    r0, r1, r0
00126dec: 6421       movs    r1, #100
00126dee: 90fbf1f0   sdiv    r0, r0, r1
00126df2: 84f82101   strb.w  r0, [r4, #289]
00126e0a: 0020       movs    r0, #0
00126e0c: a4f82201   strh.w r0, [r4, #290]  ; clear accumulated count
00126e10: c4f82401   str.w  r0, [r4, #292]  ; clear accumulated sum
~~~

The actual control flow contains branches not shown in this abbreviated evidence excerpt. Regenerate the full slices to inspect every branch and to avoid treating a shortened trace as complete pseudocode.

## 5. Why sta+0x3a5 can remain constant

Hypotheses, **not yet distinguished**:

1. **No incoming samples (count=0):** the MAC statistic producer is disabled, the hardware/ROM has no ACK metric on this variant, or the relevant traffic/statistics path is not active.
2. **Out-of-range quotient:** +0x44 is nonzero but (s32 sum)/(u16 count) is outside [-128,127] due to a different physical unit/scale or corruption; firmware explicitly rejects the value while still draining/resetting buffers. This is a *plausible*, not demonstrated, scaling mismatch.
3. **Gated processing:** rate-control updater or its accumulator consumer is skipped for the observed AP peer under runtime mode/flags or timing; live TX-rate adaptation alone does not show that this particular metric is propagated.
4. **Wrong interpretation:** +0x40/+0x44 may be a signed statistic that is not ACK RSSI in dBm. This interpretation cannot be proven only by division and signed-byte storage.

The binary establishes that memory at 0x40341680 is **configured and consumed**. It does not establish the internal register semantics of the MAC block, a physical writer at the individual offset, or the power-domain state. Some behavior lives in mask ROM and the hardware RTL, neither supplied in wcnmodem.bin. No firmware patch that forces/report fake RSSI is justified.

## 6. Static next steps, without touching hardware

1. Trace the helpers called at 0x001532b8/0x001532c0 and the register bitfields configuring 0x400f20b4 (buffer enable, counter enable, and interrupt/event settings). Resolve their calling conventions and effects; do not assume the register is a DMA engine simply because a RAM address is programmed.
2. Decode the full 0x00128554 and 0x00126d54 control-flow graphs, including mode flags and all early returns, to establish which contexts reach each statistic path. The extracted slices are supplied by the tool.
3. Trace ROM calls and MAC reads near 0x001539b0 (0x400f8758 and 0x400f20bc), classify the snapshot lock and selectors.
4. Compare static configuration with related SC2355 variants if compatible firmware images are available; keep build IDs/hashes separate, and never apply another image's register masks to UWE5622 unverified.
5. No wifi_ram_force=1, no direct reads of uncertain CHIP_SLP power domains, and no write to firmware until safety is independently established.

## Evidence / confidence

| Claim | Evidence | Confidence |
|---|---|---|
| 0x40341680 mapped as a 0x900-byte, 32x0x48 table | init routines, register literal, lookup in global pointer | High (static) |
| Snapshot/clear 0x48 bytes per LUT | 0x001539b0 and call with clear=1 at 0x001285d0 | High (static) |
| Per-LUT fields +0x40 (s32) / +0x44 (u16) are accumulated with signed average/range validation | 0x00128554, 0x00128710-0x00128750 | High (static) |
| sta+0x3a5 is signed, smoothed, and stale in near/far/near hardware test | 0x00126d54, prior section 56.1 | High |
| These fields physically measure ACK RSSI in dBm | No direct source semantics or measured raw buffer | **Unproven** |
| Reason unchanged sta+0x3a5 | Multiple unresolved paths, no safe raw hardware sample | **Unknown** |

This report supersedes *only the inference* that the firmware definitely has stopped collecting ACK RSSI. Earlier hardware measurements and all other RE sections remain intact.
