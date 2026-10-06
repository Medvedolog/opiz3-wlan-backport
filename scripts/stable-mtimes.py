#!/usr/bin/env python3
"""Give every file a modification time derived from its content.

OpenWrt names a package's .prepared stamp after the paths and mtimes of the
files in its package directory, and rebuilds when that name changes.  Fresh
checkouts and clones get new mtimes on every CI run, so a cached build_dir
would be rebuilt from scratch every time.  With mtimes taken from the
content, an unchanged package keeps its stamp and is not rebuilt, and a
changed file gets a different mtime, so its package is.

The times land around 2001-2002, older than any stamp, so they never make
something look newer than its build.

usage: stable-mtimes.py <dir>...
"""
import hashlib
import os
import sys

BASE = 1000000000


def stable_time(path):
    h = hashlib.md5()
    if os.path.islink(path):
        h.update(os.readlink(path).encode())
    else:
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
    return BASE + int(h.hexdigest()[:6], 16)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    count = 0
    for top in sys.argv[1:]:
        for root, dirs, files in os.walk(top):
            if ".git" in dirs:
                dirs.remove(".git")
            for name in files:
                p = os.path.join(root, name)
                t = stable_time(p)
                os.utime(p, (t, t), follow_symlinks=False)
                count += 1
            # directories too: some rules look at them
            os.utime(root, (BASE, BASE))
    print("stable mtimes: %d files" % count)


if __name__ == "__main__":
    main()
