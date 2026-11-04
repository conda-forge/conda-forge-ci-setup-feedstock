#!/usr/bin/env python3
"""Extract one SDK from a macOS Command Line Tools .pkg (stdlib only).

  unpack_pkg.py PKG SDK DEST   extract SDKs/<SDK>/ from PKG into DEST

This is the equivalent of `pkgutil --expand-full` for platforms without it:
flat .pkg (xar archive) -> Payload (pbzx or gzip) -> cpio (odc).
"""

import gzip
import lzma
import os
import re
import shutil
import stat
import struct
import sys
import tempfile
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path


def unpack_payload(pkg, out):
    """Decompress the cpio archive inside a flat .pkg into the file `out`."""
    with open(pkg, "rb") as f:
        magic, hsize, _, toc_len, _, _ = struct.unpack(">4sHHQQI", f.read(28))
        if magic != b"xar!":
            raise ValueError(f"{pkg} is not a flat .pkg")
        f.seek(hsize)
        toc = ET.fromstring(zlib.decompress(f.read(toc_len)))
        member = next(e for e in toc.iter("file") if e.findtext("name") == "Payload")
        f.seek(hsize + toc_len + int(member.findtext("data/offset")))
        data = f.read(int(member.findtext("data/length")))

    with open(out, "wb") as o:
        if data[:4] == b"pbzx":  # header, then chunks of [size, length, xz data]
            pos = 12
            while pos < len(data):
                _, length = struct.unpack(">QQ", data[pos:pos + 16])
                chunk = data[pos + 16:pos + 16 + length]
                o.write(lzma.decompress(chunk) if chunk[:6] == b"\xfd7zXZ\x00" else chunk)
                pos += 16 + length
        elif data[:2] == b"\x1f\x8b":
            o.write(gzip.decompress(data))
        else:
            raise ValueError(f"unknown Payload format in {pkg}")


def cpio_entries(f):
    """Yield (name, mode, (dev, ino), nlink, size) per odc cpio entry; the
    entry's data starts at f.tell() when yielded."""
    while True:
        h = f.read(76)
        if h[:6] != b"070707":
            raise ValueError("bad cpio header")
        dev, ino = int(h[6:12], 8), int(h[12:18], 8)
        mode, nlink = int(h[18:24], 8), int(h[36:42], 8)
        namesize, size = int(h[59:65], 8), int(h[65:76], 8)
        name = f.read(namesize)[:-1].decode("utf-8", "surrogateescape")
        if name == "TRAILER!!!":
            return
        start = f.tell()
        yield name, mode, (dev, ino), nlink, size
        f.seek(start + size)


def sdk_path(name):
    """'./Library/.../SDKs/MacOSX14.5.sdk/usr/x' -> ('MacOSX14.5.sdk', ['usr', 'x'])."""
    parts = [p for p in name.split("/") if p not in ("", ".")]
    for i in range(len(parts) - 1):
        if parts[i] == "SDKs" and re.fullmatch(r"MacOSX[\d.]*\.sdk", parts[i + 1]):
            return parts[i + 1], parts[i + 2:]
    return None, None


def extract(pkg, sdk, dest, tmp):
    """Extract SDKs/<sdk>/ from pkg into dest, refusing paths that escape it."""
    unpack_payload(pkg, tmp / "payload.cpio")
    dest.mkdir(parents=True)
    root = os.path.realpath(dest)
    hardlinks = {}
    with open(tmp / "payload.cpio", "rb") as f:
        for name, mode, ino, nlink, size in cpio_entries(f):
            s, rest = sdk_path(name)
            if s != sdk or not rest:
                continue
            target = dest.joinpath(*rest)
            parent = os.path.realpath(target.parent)
            if ".." in rest or not (parent == root or parent.startswith(root + os.sep)):
                raise ValueError(f"unsafe path in package: {name}")
            if stat.S_ISDIR(mode):
                target.mkdir(parents=True, exist_ok=True)
            elif stat.S_ISLNK(mode):
                os.symlink(f.read(size).decode(), target)
            elif stat.S_ISREG(mode):
                if nlink > 1 and ino in hardlinks:  # odc repeats the data for each link
                    os.link(hardlinks[ino], target)
                    continue
                with open(target, "xb") as out:  # "x": never overwrite or follow
                    shutil.copyfileobj(_limited(f, size), out)
                os.chmod(target, mode & 0o755)
                hardlinks[ino] = target


class _limited:
    """File-like view of the next `size` bytes of f, for copyfileobj."""

    def __init__(self, f, size):
        self.f, self.left = f, size

    def read(self, n=-1):
        n = self.left if n < 0 else min(n, self.left)
        self.left -= n
        return self.f.read(n)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    pkg, sdk, dest = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    with tempfile.TemporaryDirectory() as tmp:
        try:
            extract(pkg, sdk, dest, Path(tmp))
        except BaseException:
            shutil.rmtree(dest, ignore_errors=True)
            raise
