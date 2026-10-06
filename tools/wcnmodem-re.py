#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Reproduce the static analysis in docs/WCNMODEM-REVERSE-ENGINEERING.md.

usage: wcnmodem-re.py wcnmodem.bin [outdir]

Writes to outdir (default: current directory):
  fw.S        Thumb-2 linear sweep of the code region, literal pools resolved
  fwtable.txt firmware command/event name table as "id name"
  cmdmap.txt  command id -> in-image handler(s), derived from calls to the
              ROM command-response sender at 0x002073a4

Requires: pip install capstone
"""
import os
import re
import struct
import sys

import capstone

BASE = 0x00100000
CODE = (0x130, 0x79200)          # file offsets of the code region
NAME_TABLE = 0x7989c             # file offset of the first {id, name} entry
RSP_SENDER = 0x002073a4          # ROM: send command response (ctx, id, st, buf)


def cstr(d, addr):
    off = addr - BASE
    if not 0 <= off < len(d):
        return None
    end = d.find(b'\0', off)
    s = d[off:end]
    if len(s) > 3 and all(32 <= c < 127 for c in s):
        return s.decode()
    return None


def name_table(d):
    out, off = [], NAME_TABLE
    while True:
        ident, ptr = struct.unpack_from('<II', d, off)
        name = cstr(d, ptr)
        if name is None or ident > 0x1000:
            return out
        out.append((ident, name))
        off += 8


def disassemble(d, path):
    md = capstone.Cs(capstone.CS_ARCH_ARM,
                     capstone.CS_MODE_THUMB | capstone.CS_MODE_MCLASS)
    md.skipdata = True
    lines = []
    for ins in md.disasm(d[CODE[0]:CODE[1]], BASE + CODE[0]):
        ops = ins.op_str
        if ins.mnemonic.startswith('ldr') and '[pc' in ops:
            try:
                imm = int(ops.split('#')[-1].rstrip(']'), 16) if '#' in ops else 0
                lit = ((ins.address + 4) & ~3) + imm
                ops += '\t; =%#x' % struct.unpack_from('<I', d, lit - BASE)[0]
            except (ValueError, struct.error):
                pass
        lines.append('%x:\t%s\t%s' % (ins.address, ins.mnemonic, ops))
    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    return lines


def command_map(lines, names):
    target = '#%#x' % RSP_SENDER
    res = {}
    for i, line in enumerate(lines):
        if target not in line or not re.search(r'\tbl?(\.w)?\t', line):
            continue
        cid = None
        for j in range(i - 1, max(i - 6, 0), -1):
            m = re.search(r'movs\tr1, #(0x[0-9a-f]+|\d+)$', lines[j])
            if m:
                cid = int(m.group(1), 0)
                break
        fn = None
        for j in range(i, max(i - 600, 0), -1):
            if re.search(r'\tpush(\.w)?\t\{.*lr\}', lines[j]):
                fn = '0x' + lines[j].split(':')[0]
                break
        if cid is not None:
            res.setdefault(cid, set()).add(fn or '?')
    return ['%#04x %-30s %s' % (c, names.get(c, '?'), ' '.join(sorted(res[c])))
            for c in sorted(res)]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    d = open(sys.argv[1], 'rb').read()
    out = sys.argv[2] if len(sys.argv) > 2 else '.'
    os.makedirs(out, exist_ok=True)

    table = name_table(d)
    with open(os.path.join(out, 'fwtable.txt'), 'w') as f:
        f.writelines('%#04x %s\n' % e for e in table)

    lines = disassemble(d, os.path.join(out, 'fw.S'))
    cmap = command_map(lines, dict(table))
    with open(os.path.join(out, 'cmdmap.txt'), 'w') as f:
        f.write('\n'.join(cmap) + '\n')

    print('%d table entries, %d instructions, %d commands with handlers'
          % (len(table), len(lines), len(cmap)))


if __name__ == '__main__':
    main()
