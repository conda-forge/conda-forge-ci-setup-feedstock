import hashlib
import os

import conda_build.config

def built_distributions():
    "List conda artifacts in conda-build's root workspace"
    paths = (
            [
                os.path.join('noarch', p)
                for p in os.listdir(os.path.join(conda_build.config.croot, 'noarch'))  # noqa
            ]
            + [
                os.path.join(conda_build.config.subdir, p)
                for p in os.listdir(os.path.join(conda_build.config.croot, conda_build.config.subdir))  # noqa
            ])
    return [
            path
            for path in paths
            if (path.endswith('.tar.bz2') or path.endswith(".conda"))
        ]


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
