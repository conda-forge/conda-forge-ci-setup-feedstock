#!/usr/bin/env python3
"""Find macOS SDKs on Apple's software update CDN and pin them (stdlib only).

  discover   rescan Apple's catalogs and rewrite cdn_sdks.json (downloads
             every SDK package, so takes a while)
  list       show the pinned SDKs

This is a maintainer tool and is not part of the conda-forge-ci-setup package;
download_osx_sdk.sh only reads the resulting cdn_sdks.json.
"""

import gzip
import hashlib
import json
import plistlib
import re
import stat
import sys
import tempfile
import urllib.request
from pathlib import Path

from unpack_pkg import cpio_entries, sdk_path, unpack_payload

PINS_FILE = Path(__file__).parent / "cdn_sdks.json"

CHAIN = ["27", "26", "15", "14", "13", "12", "10.16", "10.15", "10.14", "10.13",
         "10.12", "10.11", "10.10", "10.9"]
CATALOGS = [  # one per macOS release; older ones keep products newer ones drop
    "https://swscan.apple.com/content/catalogs/others/index-" + "-".join(CHAIN[i:])
    + "-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog.gz"
    for i in range(len(CHAIN))
]

# Package URLs to check even if no catalog lists them any more.
SEED_URLS = [
    "https://swcdn.apple.com/content/downloads/22/62/041-88607/wg8avdk0jo75k9a13gentz9stwqgrqmcv6/CLTools_SDK_OSX1012.pkg",
    "https://swcdn.apple.com/content/downloads/33/36/041-90419-A_7JJ4H9ZHO2/xs88ob5wjz6riz7g6764twblnvksusg4ps/CLTools_SDK_macOS1013.pkg",
    "https://swcdn.apple.com/content/downloads/50/15/041-91747-A_WICZE7RNVZ/rayjnqf847xflt3tan8o8agod67eq88cav/CLTools_SDK_macOS1014.pkg",
    # Found via Wayback Machine snapshots of 2020-21 catalogs; still live on the CDN.
    "https://swcdn.apple.com/content/downloads/45/28/061-26566-A_R7LP2VO5QF/svs27at6zihaghh3wj0av4y3wdcriu4n2j/CLTools_macOS1014_SDK.pkg",
    "https://swcdn.apple.com/content/downloads/45/28/061-26566-A_R7LP2VO5QF/svs27at6zihaghh3wj0av4y3wdcriu4n2j/CLTools_macOS1015_SDK.pkg",
    "https://swcdn.apple.com/content/downloads/46/21/001-89745-A_56FM390IW5/v1um2qppgfdnam2e9cdqcqu2r6k8aa3lis/CLTools_macOSLMOS_SDK.pkg",
    "https://swcdn.apple.com/content/downloads/46/21/001-89745-A_56FM390IW5/v1um2qppgfdnam2e9cdqcqu2r6k8aa3lis/CLTools_macOSNMOS_SDK.pkg",
    "https://swcdn.apple.com/content/downloads/50/51/071-29699-A_YC8SX0OHH3/7479xojqghsvgtnt3dxjpnxuz9sjpmbmds/CLTools_macOSLMOS_SDK.pkg",
    "https://swcdn.apple.com/content/downloads/50/51/071-29699-A_YC8SX0OHH3/7479xojqghsvgtnt3dxjpnxuz9sjpmbmds/CLTools_macOSNMOS_SDK.pkg",
    # 11.0 (001-57005, 001-57076, 001-86075; Oct-Dec 2020) returned 403: removed from the CDN.
]


def vkey(v):
    return tuple(int(x) for x in v.split("."))


def load_pins():
    return json.loads(PINS_FILE.read_text())


def download(url, dest):
    """Download url to dest and return its sha256."""
    h = hashlib.sha256()
    with urllib.request.urlopen(url, timeout=300) as r, open(dest, "wb") as f:
        while chunk := r.read(1 << 20):
            h.update(chunk)
            f.write(chunk)
    return h.hexdigest()


def scan(pkg, tmp):
    """Return {sdk_dir: version} for each real SDK directory in pkg."""
    unpack_payload(pkg, tmp / "payload.cpio")
    versions = {}
    with open(tmp / "payload.cpio", "rb") as f:
        for name, mode, _, _, size in cpio_entries(f):
            sdk, rest = sdk_path(name)
            if sdk and rest == ["SDKSettings.plist"] and stat.S_ISREG(mode):
                versions[sdk] = plistlib.loads(f.read(size))["Version"]
            elif sdk and rest == ["SDKSettings.json"] and sdk not in versions:
                versions[sdk] = json.loads(f.read(size))["Version"]
    return versions


def show_list():
    pins = load_pins()
    for v in sorted(pins["sdks"], key=vkey):
        p = pins["sdks"][v]
        also = [a for a, t in pins["aliases"].items() if t == v]
        print(f"{v:<8} {p['date']:<10}  {p['product']:<10} {p['size'] / 2**20:5.1f} MiB"
              + (f"  (also: {', '.join(also)})" if also else ""))


def discover():
    old = load_pins()["sdks"]
    # Candidate package URLs -> catalog post date ("" if no catalog lists it).
    candidates = {u: "" for u in SEED_URLS}
    candidates.update({p["url"]: p["date"] for p in old.values()})
    for cat in CATALOGS:
        try:
            data = gzip.decompress(urllib.request.urlopen(cat, timeout=120).read())
        except Exception as e:
            print(f"skip catalog ({e}): {cat}", file=sys.stderr)
            continue
        for product in plistlib.loads(data)["Products"].values():
            for pkg in product.get("Packages", []):
                url = pkg["URL"].replace("http://", "https://")
                if (re.search(r"/CLTools_[^/]*SDK[^/]*\.pkg$", url)
                        and pkg.get("Size", 0) > 1 << 20):  # skip tiny stub packages
                    candidates[url] = str(product.get("PostDate", ""))[:10]

    found = []  # one record per SDK per package
    for i, (url, date) in enumerate(sorted(candidates.items()), 1):
        print(f"[{i}/{len(candidates)}] {url.rsplit('/', 1)[-1]}", file=sys.stderr)
        try:
            with tempfile.TemporaryDirectory() as tmp:
                tmp = Path(tmp)
                sha = download(url, tmp / "sdk.pkg")
                size = (tmp / "sdk.pkg").stat().st_size
                versions = scan(tmp / "sdk.pkg", tmp)
        except Exception as e:
            print(f"  failed: {e}", file=sys.stderr)
            continue
        product = re.search(r"/(\d{3}-\d{5})", url).group(1)
        for sdk, version in versions.items():
            print(f"  -> {sdk} ({version})", file=sys.stderr)
            found.append({"version": version, "sdk": sdk, "url": url, "sha256": sha,
                          "size": size, "product": product, "date": date})

    # Keep existing pins whose package still downloads, so Apple reposting a
    # package never silently changes what CI gets; new versions take the most
    # recently posted package.
    ok = {r["url"] for r in found}
    pins = {v: p for v, p in old.items() if p["url"] in ok}
    for r in sorted(found, key=lambda r: r["date"]):
        if r["version"] not in pins or pins[r["version"]]["url"] == r["url"]:
            pins[r["version"]] = {"kind": "pkg", **{k: r[k] for k in (
                "sdk", "url", "sha256", "size", "product", "date")}}
    for v, p in old.items():
        if v not in pins:
            print(f"WARNING: {v} no longer downloads; keeping its old pin", file=sys.stderr)
            pins[v] = p

    # "15" -> highest 15.x, "10.15" -> highest 10.15.x, when not pinned exactly.
    aliases = {}
    for v in sorted(pins, key=vkey):
        parts = v.split(".")
        for n in range(1, len(parts)):
            short = ".".join(parts[:n])
            if short not in pins and short != "10":
                aliases[short] = v

    PINS_FILE.write_text(json.dumps({"aliases": aliases, "sdks": pins}, indent=2,
                                    sort_keys=True) + "\n")
    print(f"Pinned {len(pins)} SDKs: {', '.join(sorted(pins, key=vkey))}", file=sys.stderr)


if __name__ == "__main__":
    args = sys.argv[1:]
    if args == ["list"]:
        show_list()
    elif args == ["discover"]:
        discover()
    else:
        sys.exit(__doc__)
