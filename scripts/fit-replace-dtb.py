#!/usr/bin/env python3
"""Replace the device tree inside an existing FIT kernel image.

The OpenWrt ImageBuilder ships the kernel as a prebuilt FIT
(<device>-kernel.bin) and has no rule to rebuild it, so a patched DTB has
to be put into that FIT directly.  The FIT is decompiled, the data of the
flat_dt image node is replaced with /incbin/ of the new DTB, and mkimage
rebuilds it, recomputing the hashes.  Everything else stays as it was.

usage: fit-replace-dtb.py <fit-in> <new.dtb> <fit-out>
"""
import os
import re
import subprocess
import sys
import tempfile


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    fit_in, dtb, fit_out = sys.argv[1:]
    dtb = os.path.abspath(dtb)

    dts = subprocess.run(["dtc", "-q", "-I", "dtb", "-O", "dts", fit_in],
                         check=True, capture_output=True, text=True).stdout

    # node path -> indices of its own property lines (dtc puts one per line)
    lines = dts.split("\n")
    stack, props = [], {}
    for i, line in enumerate(lines):
        t = line.strip()
        if t.endswith("{"):
            stack.append(t[:-1].strip())
        elif t == "};":
            stack.pop()
        elif t:
            props.setdefault("/".join(stack), []).append(i)
    fdt = [n for n, idx in props.items()
           if any(lines[i].strip() == 'type = "flat_dt";' for i in idx)]
    if len(fdt) != 1:
        sys.exit("expected exactly one flat_dt image, found %r" % fdt)
    data = [i for i in props[fdt[0]] if lines[i].strip().startswith("data = ")]
    if len(data) != 1:
        sys.exit("flat_dt node %s has no inline data" % fdt[0])
    i = data[0]
    lines[i] = lines[i][:len(lines[i]) - len(lines[i].lstrip())] + \
        'data = /incbin/("%s");' % dtb
    print("replaced data of %s" % fdt[0].lstrip("/"))
    its = "\n".join(lines)

    # mkimage sets these itself
    its = re.sub(r'\n\t*timestamp = <[^>]*>;', '', its)
    its = re.sub(r'(\n\t*)value = <[^>]*>;', '', its)

    with tempfile.NamedTemporaryFile("w", suffix=".its", delete=False) as f:
        f.write(its)
        its_path = f.name
    try:
        subprocess.run(["mkimage", "-f", its_path, fit_out], check=True,
                       stdout=subprocess.DEVNULL)
    finally:
        os.unlink(its_path)


if __name__ == "__main__":
    main()
