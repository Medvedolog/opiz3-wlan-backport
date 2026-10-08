#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Reproduce the pinned UWE5622 firmware ACK-RSSI static evidence.

Usage: python3 tools/wcnmodem-ack-rssi.py wcnmodem.bin [output-dir]
Requires: python3 -m pip install capstone
Never accesses SDIO, a running board, or /sys.
"""
import hashlib
import pathlib
import struct
import sys

BASE = 0x00100000
SIZE = 947120
SHA256 = "119b87ce30875734a67462f7293fb8fe85acf3270fe8b78c978ae24be7715a80"

# Function intervals, NOT a linear disassembly of the entire file. End offsets
# delimit evidence slices; they are not claimed to be exact function ends.
SLICES = {
    "tx_stats_init": (0x1532a8, 0x1532e0),
    "mac_tables_init": (0x1532e0, 0x153394),
    "per_lut_snapshot_and_clear": (0x1539b0, 0x153a3e),
    "tx_rate_statistics": (0x128554, 0x128786),
    "rssi_ewma": (0x126d54, 0x126e14),
}
LITERALS = {
    0x40341680: "per-LUT TX stats buffer (32 * 0x48)",
    0x400f20b4: "MAC stats-buffer configuration register",
    0x400f8758: "MAC per-LUT selector",
    0x400f1174: "MAC LUT-buffer configuration register",
    0x001201d8: "firmware global holding table pointers",
}
CALLS = {
    0x153190: 0x1532e0,
    0x1285d0: 0x1539b0,
    0x128cc8: 0x128554,
    0x128d6c: 0x128554,
}


def u32(image, addr):
    off = addr - BASE
    if off < 0 or off + 4 > len(image):
        raise ValueError(f"address outside image: {addr:#x}")
    return struct.unpack_from("<I", image, off)[0]


def extract(image):
    try:
        from capstone import Cs, CS_ARCH_ARM, CS_MODE_THUMB, CS_MODE_MCLASS
        from capstone.arm import ARM_OP_IMM, ARM_OP_MEM, ARM_REG_PC
    except ImportError as exc:
        raise SystemExit("Install Capstone: python3 -m pip install capstone") from exc

    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB | CS_MODE_MCLASS)
    md.detail = True
    lines = []
    for name, (start, end) in SLICES.items():
        lines.append(f"\n== {name} [{start:#010x}, {end:#010x}) ==")
        chunk = image[start - BASE:end - BASE]
        for ins in md.disasm(chunk, start):
            suffix = ""
            if ins.mnemonic.startswith("ldr") and len(ins.operands) >= 2:
                mem = ins.operands[1]
                if mem.type == ARM_OP_MEM and mem.mem.base == ARM_REG_PC:
                    # Thumb literal loads use Align(PC,4) with PC=ins.addr+4.
                    literal = ((ins.address + 4) & ~3) + mem.mem.disp
                    if BASE <= literal <= BASE + len(image) - 4:
                        suffix = f"  ; [{literal:#010x}] = {u32(image, literal):#010x}"
            if ins.mnemonic in ("bl", "blx", "b", "b.w") and ins.operands:
                dst = ins.operands[0]
                if dst.type == ARM_OP_IMM:
                    suffix += f"  ; target {dst.imm:#010x}"
            lines.append(f"{ins.address:08x}: {ins.bytes.hex():<12} {ins.mnemonic:<10} {ins.op_str}{suffix}")
    return "\n".join(lines) + "\n"


def literal_sites(image):
    lines = []
    for word, description in LITERALS.items():
        target = struct.pack("<I", word)
        offsets = [i for i in range(0, len(image) - 3, 2)
                   if image[i:i + 4] == target]
        lines.append(f"{word:#010x} {description}: " +
                     (", ".join(hex(BASE + i) for i in offsets) or "none"))
    return "\n".join(lines) + "\n"


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    path = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2]) if len(sys.argv) == 3 else pathlib.Path(".")
    image = path.read_bytes()
    digest = hashlib.sha256(image).hexdigest()
    if len(image) != SIZE or digest != SHA256:
        raise SystemExit(f"Unexpected firmware: bytes={len(image)}, sha256={digest}")
    for addr, expected in ((0x1536d4, 0x40341680),
                           (0x1536ac, 0x400f20b4),
                           (0x153acc, 0x400f8758)):
        actual = u32(image, addr)
        if actual != expected:
            raise SystemExit(f"Literal mismatch at {addr:#x}: {actual:#x} != {expected:#x}")
    disassembly = extract(image)
    sites = literal_sites(image)
    out.mkdir(parents=True, exist_ok=True)
    (out / "ack-rssi-sites.S").write_text(disassembly, encoding="utf-8")
    (out / "ack-rssi-literals.txt").write_text(sites, encoding="utf-8")
    summary = "\n".join(f"{src:#010x} -> {dst:#010x}" for src, dst in CALLS.items())
    (out / "ack-rssi-call-map.txt").write_text(
        "Verified Thumb BL sites (compare against ack-rssi-sites.S; some callers are outside the slices):\n"
        + summary + "\n", encoding="utf-8")
    print(f"Verified SHA-256: {digest}")
    print(sites, end="")
    print("Wrote ack-rssi-sites.S, ack-rssi-literals.txt, ack-rssi-call-map.txt")


if __name__ == "__main__":
    main()
