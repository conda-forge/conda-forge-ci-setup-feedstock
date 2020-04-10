#!/usr/bin/env python
import os
import shutil
import uuid
import sys


def _mangele_path(pth, new_dir):
    """mangle a path by adding a random string to the front and the back of the
    filename and moving it to a new dir"""
    mangle_str = 'h' + uuid.uuid4().hex[0:6]
    parts = os.path.split(pth)
    new_parts = [new_dir, parts[1]]
    new_parts[1] = mangle_str + "_" + parts[1] + "_" + mangle_str
    return os.path.join(*new_parts)


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
    mangled_dir = "/usr/local/mangled_homebrew_files_%s" % uuid.uuid4().hex
    os.makedirs(mangled_dir, exist_ok=True)

    excluded_dirs = [
        os.path.basename(mangled_dir),
        "bin",
        "miniconda",
    ]

    # move all of the stuff except miniconda
    potential_dirs = os.listdir("/usr/local")
    for _pth in potential_dirs:
        pth = os.path.join("/usr", "local", _pth)
        if (
            os.path.exists(pth)
            and os.path.isdir(pth)
            and _pth not in excluded_dirs
        ):
            mangled_pth = _mangele_path(pth, mangled_dir)
            _try_move_file_or_dir(pth, mangled_pth)


if __name__ == "__main__":
    main()
