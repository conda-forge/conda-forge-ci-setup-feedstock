import hashlib
import os

import conda_build.config
from conda.base.context import context

try:
    from ruamel_yaml import safe_load
except ImportError:
    from yaml import safe_load

CONDA_BUILD = "conda-build"
RATTLER_BUILD = "rattler-build"

def built_distributions(subdirs=()):
    "List conda artifacts in conda-build's root workspace"
    if not subdirs:
        subdirs = context.subdir, "noarch"
    paths = []
    for subdir in subdirs:
        for path in os.listdir(os.path.join(conda_build.config.croot, subdir)):
            if path.endswith((".tar.bz2", ".conda")):
                paths.append(os.path.join(conda_build.config.croot, subdir, path))
    return paths


def split_pkg(pkg):
    if pkg.endswith(".tar.bz2"):
        pkg = pkg[:-len(".tar.bz2")]
    elif pkg.endswith(".conda"):
        pkg = pkg[:-len(".conda")]
    else:
        raise RuntimeError("Can only process packages that end in .tar.bz2 or .conda!")
    plat, pkg_name = pkg.split(os.path.sep)
    name_ver, build = pkg_name.rsplit('-', 1)
    name, ver = name_ver.rsplit('-', 1)
    return plat, name, ver, build


def compute_sha256sum(pth):
    h = hashlib.sha256()

    with open(pth, 'rb') as fp:
        chunk = 0
        while chunk != b'':
            chunk = fp.read(1024)
            h.update(chunk)

    return h.hexdigest()

def human_readable_bytes(number):
    for unit in ['bytes', 'KB', 'MB', 'GB', 'TB']:
        if abs(number) < 1024.0:
            return f"{number:3.1f}{unit}"
        number /= 1024.0
    return f"{number:3.1f}{unit}"


def determine_build_tool(feedstock_root):
    build_tool = CONDA_BUILD

    if feedstock_root and os.path.exists(os.path.join(feedstock_root, "conda-forge.yml")):
        with open(os.path.join(feedstock_root, "conda-forge.yml")) as f:
            conda_forge_config = safe_load(f)

            if conda_forge_config.get("conda_build_tool", CONDA_BUILD) == RATTLER_BUILD:
                build_tool = RATTLER_BUILD

    return build_tool