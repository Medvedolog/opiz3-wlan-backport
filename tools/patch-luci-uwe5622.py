#!/usr/bin/env python3
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-luci-uwe5622.py <luci-feed-root>")

root = Path(sys.argv[1])

network_js = root / "modules/luci-base/htdocs/luci-static/resources/network.js"
status_js = root / "modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/60_wifi.js"

s = network_js.read_text(encoding="utf-8")
needle = """\t\tif (this.ubus('dev', 'iwinfo', 'type') == 'wl')
\t\t\ttype = 'Broadcom';

\t\treturn '%s %s Wireless Controller (%s)'.format(
"""
replacement = """\t\tif (this.ubus('dev', 'iwinfo', 'type') == 'wl')
\t\t\ttype = 'Broadcom';

\t\t/* The platform UWE5622 has no PCI/USB hardware ID for iwinfo to map. */
\t\tif (!type && this.getName() == 'radio0')
\t\t\ttype = 'UNISOC UWE5622';

\t\treturn '%s %s Wireless Controller (%s)'.format(
"""
if needle not in s:
    raise SystemExit("network.js branding insertion point not found")
network_js.write_text(s.replace(needle, replacement, 1), encoding="utf-8")

s = status_js.read_text(encoding="utf-8")

# Insert the unavailable-rate guard immediately after the function signature.
# Match whitespace flexibly because LuCI formatting differs between branches.
s, n = re.subn(
    r"(\bwifirate\(rate\)\s*\{\s*)",
    r"\1\t\t/* UWE5622 SoftAP firmware exposes no per-peer rate API. */\n"
    r"\t\tif (!rate || !rate.rate)\n"
    r"\t\t\treturn '—'; // rate information unavailable\n\n",
    s,
    count=1,
)
if n != 1:
    raise SystemExit("60_wifi.js wifirate() signature not found")

# Avoid presenting missing signal telemetry as 0 dBm.
s, n = re.subn(
    r"const q = Math\.min\(\(bss\.signal \+ 110\) / 70 \* 100, 100\);",
    "const q = bss.signal ? Math.min((bss.signal + 110) / 70 * 100, 100) : 0;",
    s,
    count=1,
)
if n != 1:
    raise SystemExit("60_wifi.js signal quality expression not found")

# Show an em dash when firmware does not expose per-peer signal.
sig_pat = re.compile(
    r"(?P<indent>\s*)if \(bss\.noise\) \{\n"
    r"(?P=indent)\tsig_value = '%d/%d\\xa0%s'\.format\(bss\.signal, bss\.noise, _\('dBm'\)\);"
)
m = sig_pat.search(s)
if not m:
    raise SystemExit("60_wifi.js signal display block not found")
indent = m.group("indent")
sig_repl = (
    indent + "if (!bss.signal) {\n"
    + indent + "\tsig_value = '—';\n"
    + indent + "\tsig_title = _('Signal information unavailable');\n"
    + indent + "}\n"
    + indent + "else if (bss.noise) {\n"
    + indent + "\tsig_value = '%d/%d\\xa0%s'.format(bss.signal, bss.noise, _('dBm'));"
)
s = sig_pat.sub(sig_repl, s, count=1)

status_js.write_text(s, encoding="utf-8")
