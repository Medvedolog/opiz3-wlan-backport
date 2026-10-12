#!/usr/bin/env python3
"""Check the LuCI signal-icon edits of luci-app-opiz3-status against a rootfs.

Applies usr/share/opiz3/luci-nosig.json the way /usr/sbin/opiz3-luci-nosig
does on the board (every anchor exactly once) to copies of the rootfs files,
and checks the result with "node --check" when node is available. Fails if
an anchor is missing, so a LuCI update that moves the code shows up in CI
instead of silently leaving the old icons on the board.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

root = sys.argv[1]
table = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "package", "luci",
                     "luci-app-opiz3-status", "root", "usr", "share", "opiz3", "luci-nosig.json")
t = json.load(open(table))
node = shutil.which("node")
failed = False

with tempfile.TemporaryDirectory() as tmp:
    for f in t["files"]:
        s = open(root + f["path"]).read()
        for old, new in f["edits"]:
            if s.count(old) != 1:
                print(f"{f['path']}: anchor found {s.count(old)} times: {old[:70]}")
                failed = True
                break
            s = s.replace(old, new)
        else:
            out = os.path.join(tmp, os.path.basename(f["path"]))
            open(out, "w").write(s)
            if node and subprocess.run([node, "--check", out]).returncode:
                print(f"{f['path']}: syntax error after the edits")
                failed = True

sys.exit(1 if failed else 0)
