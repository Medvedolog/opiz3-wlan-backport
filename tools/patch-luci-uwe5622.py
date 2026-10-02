#!/usr/bin/env python3
from pathlib import Path
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
needle = "\twifirate(rate) {\n"
replacement = """\twifirate(rate) {
\t\t/* UWE5622 SoftAP firmware exposes no per-peer rate API. */
\t\tif (!rate || !rate.rate)
\t\t\treturn '—'; // rate information unavailable

"""
if needle not in s:
    raise SystemExit("60_wifi.js rate insertion point not found")
s = s.replace(needle, replacement, 1)

needle = """\t\t\t\tconst q = Math.min((bss.signal + 110) / 70 * 100, 100);
"""
replacement = """\t\t\t\tconst q = bss.signal ? Math.min((bss.signal + 110) / 70 * 100, 100) : 0;
"""
if needle not in s:
    raise SystemExit("60_wifi.js signal quality insertion point not found")
s = s.replace(needle, replacement, 1)

needle = """\t\t\t\tif (bss.noise) {
\t\t\t\t\tsig_value = '%d/%d\\xa0%s'.format(bss.signal, bss.noise, _('dBm'));
"""
replacement = """\t\t\t\tif (!bss.signal) {
\t\t\t\t\tsig_value = '—';
\t\t\t\t\tsig_title = _('Signal information unavailable');
\t\t\t\t}
\t\t\t\telse if (bss.noise) {
\t\t\t\t\tsig_value = '%d/%d\\xa0%s'.format(bss.signal, bss.noise, _('dBm'));
"""
if needle not in s:
    raise SystemExit("60_wifi.js signal display insertion point not found")
status_js.write_text(s.replace(needle, replacement, 1), encoding="utf-8")
