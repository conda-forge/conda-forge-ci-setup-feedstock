#!/usr/bin/env python
import os
import shutil
import sys


def _try_move_file_or_dir(p, mangled_p):
    try:
        shutil.move(p, mangled_p)
        print("MOVED FILE/DIR %s -> %s" % (p, mangled_p))
    except shutil.Error:
        try:
            os.remove(p)
            print("REMOVED FILE %s " % p)
        except Exception as e:
            print("ERROR moving or removing FILE %s: %s" % (p, repr(e)))
            try:
                shutil.rmtree(p, ignore_errors=True)
                print("REMOVED DIR %s " % p)
            except Exception as e:
                print("ERROR moving or removing DIR %s: %s" % (p, repr(e)))
    sys.stdout.flush()


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
        _try_move_file_or_dir(pth, mangled_pth)


if __name__ == "__main__":
    main()
