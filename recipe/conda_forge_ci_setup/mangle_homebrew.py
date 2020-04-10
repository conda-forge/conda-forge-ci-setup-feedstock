#!/usr/bin/env python
import os
import shutil


def main():
    # make the mangled path
    mangled_dir = "/usr/local/conda_mangled"
    os.makedirs(mangled_dir, exist_ok=True)

    excluded_dirs = [
        "conda_mangled",
        "miniconda",
    ]

    # move all of the stuff except miniconda
    potential_dirs = os.listdir("/usr/local")
    for _pth in potential_dirs:
        pth = os.path.join("/usr/local", _pth)
        if _pth in excluded_dirs:
            continue
        mangled_pth = os.path.join(mangled_dir, _pth)
        shutil.move(pth, mangled_pth)
        print("MOVED %s -> %s" % (pth, mangled_pth), flush=True)


if __name__ == "__main__":
    main()
