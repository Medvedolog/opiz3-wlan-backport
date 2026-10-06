#!/usr/bin/env python3
"""Add the UWE5622 (AW859A) SDIO Wi-Fi description to a prebuilt Orange Pi
Zero 3 DTB, as target/linux/sunxi/patches-6.12/900-...-zero3.patch does at
the source level: two always-on regulators, an mmc-pwrseq-simple node
driving the PG18 reset with the RTC 32k clock, and mmc1 enabled as a
non-removable 4-bit SDIO bus.

Used on the official ImageBuilder's DTB, so the image keeps the official
kernel (and its kmod ABI) while getting Wi-Fi. Needs dtc and fdtget.

usage: zero3-dtb-add-wifi.py <in.dtb> <out.dtb>
"""
import re
import subprocess
import sys

MMC1 = "mmc@4021000"
GPIO_ACTIVE_LOW = 1
PG = 6  # port G


def run(*args):
    return subprocess.run(args, check=True, capture_output=True,
                          text=True).stdout


def nodes(dtb, path="/"):
    yield path
    out = run("fdtget", "-l", dtb, path)
    for name in out.split():
        yield from nodes(dtb, path.rstrip("/") + "/" + name)


def prop(dtb, path, name, typ="s"):
    try:
        return run("fdtget", "-t", typ, dtb, path, name).strip()
    except subprocess.CalledProcessError:
        return None


def find(dtb, all_nodes, pred, what):
    hits = [p for p in all_nodes if pred(p)]
    if len(hits) != 1:
        sys.exit(f"error: expected one {what}, found {hits}")
    return hits[0]


def main(src, dst):
    all_nodes = list(nodes(src))
    if any(p.endswith("/wifi-pwrseq") for p in all_nodes):
        sys.exit("error: DTB already has wifi-pwrseq")

    pio = find(src, all_nodes, lambda p: "allwinner,sun50i-h616-pinctrl"
               in (prop(src, p, "compatible") or ""), "H616 pinctrl")
    rtc = find(src, all_nodes, lambda p: "allwinner,sun50i-h616-rtc"
               in (prop(src, p, "compatible") or ""), "H616 RTC")
    mmc1 = find(src, all_nodes, lambda p: p.endswith("/" + MMC1), MMC1)
    vcc5v = [p for p in all_nodes
             if prop(src, p, "regulator-name") == "vcc-5v"]

    used = [int(v) for v in (prop(src, p, "phandle", "u") for p in all_nodes)
            if v]
    nxt = max(used, default=0) + 1
    new_ph = {}  # node path -> phandle to add

    def phandle(path):
        nonlocal nxt
        v = prop(src, path, "phandle", "u")
        if v:
            return int(v)
        if path not in new_ph:
            new_ph[path] = nxt
            nxt += 1
        return new_ph[path]

    ph_pio, ph_rtc = phandle(pio), phandle(rtc)
    ph_5v = phandle(vcc5v[0]) if len(vcc5v) == 1 else None
    ph_33, ph_io, ph_seq = nxt, nxt + 1, nxt + 2
    nxt += 3

    dts = run("dtc", "-q", "-I", "dtb", "-O", "dts", src).splitlines()

    # give existing nodes that lacked one a phandle
    for path, ph in new_ph.items():
        name = path.rsplit("/", 1)[1]
        depth = path.count("/")
        hdr = re.compile(r"^" + "\t" * depth + r"(\S+: )?" + re.escape(name)
                         + r" \{$")
        i = next(i for i, l in enumerate(dts) if hdr.match(l))
        dts.insert(i + 1, "\t" * (depth + 1) + f"phandle = <{ph:#x}>;")

    # mmc1: enable and wire up
    depth = mmc1.count("/")
    ind = "\t" * depth
    hdr = re.compile(r"^" + ind + r"(\S+: )?" + re.escape(MMC1) + r" \{$")
    start = next(i for i, l in enumerate(dts) if hdr.match(l))
    end = next(i for i in range(start + 1, len(dts)) if dts[i] == ind + "};")
    drop = ("status", "vmmc-supply", "vqmmc-supply", "mmc-pwrseq",
            "bus-width", "non-removable", "mmc-ddr-1_8v")
    body = [l for l in dts[start + 1:end]
            if l.strip().split(" ")[0].rstrip(";") not in drop]
    pi = ind + "\t"
    body += [
        pi + f"vmmc-supply = <{ph_33:#x}>;",
        pi + f"vqmmc-supply = <{ph_io:#x}>;",
        pi + f"mmc-pwrseq = <{ph_seq:#x}>;",
        pi + "bus-width = <0x04>;",
        pi + "non-removable;",
        pi + "mmc-ddr-1_8v;",
        pi + 'status = "okay";',
    ]
    dts[start + 1:end] = body

    # new top-level nodes, before the root node closes
    vin = [f"\t\tvin-supply = <{ph_5v:#x}>;"] if ph_5v else []
    new = [
        "",
        "\tregulator-vcc33-wifi {",
        '\t\tcompatible = "regulator-fixed";',
        '\t\tregulator-name = "vcc33-wifi";',
        "\t\tregulator-min-microvolt = <3300000>;",
        "\t\tregulator-max-microvolt = <3300000>;",
        "\t\tregulator-always-on;",
        *vin,
        f"\t\tphandle = <{ph_33:#x}>;",
        "\t};",
        "",
        "\tregulator-vcc-wifi-io {",
        '\t\tcompatible = "regulator-fixed";',
        '\t\tregulator-name = "vcc-wifi-io";',
        "\t\tregulator-min-microvolt = <1800000>;",
        "\t\tregulator-max-microvolt = <1800000>;",
        "\t\tregulator-always-on;",
        f"\t\tvin-supply = <{ph_33:#x}>;",
        f"\t\tphandle = <{ph_io:#x}>;",
        "\t};",
        "",
        "\twifi-pwrseq {",
        '\t\tcompatible = "mmc-pwrseq-simple";',
        f"\t\tclocks = <{ph_rtc:#x} 0x01>;",
        '\t\tclock-names = "osc32k-out";',
        f"\t\treset-gpios = <{ph_pio:#x} {PG:#x} 0x12 {GPIO_ACTIVE_LOW:#x}>;",
        "\t\tpost-power-on-delay-ms = <200>;",
        f"\t\tphandle = <{ph_seq:#x}>;",
        "\t};",
    ]
    root_end = max(i for i, l in enumerate(dts) if l == "};")
    dts[root_end:root_end] = new

    subprocess.run(["dtc", "-q", "-I", "dts", "-O", "dtb", "-o", dst, "-"],
                   input="\n".join(dts) + "\n", text=True, check=True)
    print(f"{dst}: mmc1 enabled, pwrseq/regulators added "
          f"(pio={ph_pio:#x} rtc={ph_rtc:#x} vcc5v={ph_5v})")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
