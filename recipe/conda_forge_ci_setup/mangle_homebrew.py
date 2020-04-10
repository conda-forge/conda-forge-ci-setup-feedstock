#!/usr/bin/env python
import os
import subprocess
import shutil
import uuid
import tempfile
import contextlib
import sys


HOMEBREW_UNINSTALL_URL = \
    "https://raw.githubusercontent.com/Homebrew/install/master/uninstall"

KNOWN_PATHS = [
    "/usr/local/Caskroom",
    "/usr/local/Cellar",
    "/usr/local/lib/gcc",
    "/usr/local/lib/perl5",
    "/usr/local/lib/perl6",
    "/usr/local/lib/perl7",
    "/usr/local/include/c++",
    "/usr/local/Frameworks/Python.framework",
]

# https://stackoverflow.com/questions/6194499/pushd-through-os-system
@contextlib.contextmanager
def pushd(new_dir):
    previous_dir = os.getcwd()
    os.chdir(new_dir)
    try:
        yield
    finally:
        os.chdir(previous_dir)


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

    # move all of the stuff except miniconda
    potential_dirs = os.listdir("/usr/local")
    for pth in potential_dirs:
        if os.path.exists(pth) and os.path.isdir(pth) and pth not in ["bin"]:
            mangled_pth = _mangele_path(pth, mangled_dir)
            _try_move_file_or_dir(pth, mangled_pth)

    # now we let homebrew do the rest
    # with tempfile.TemporaryDirectory() as tmpdir:
    #     with pushd(tmpdir):
    #         # get the homebrew uninstall script
    #         subprocess.run(
    #             [
    #                 "curl",
    #                 "-fsSL",
    #                 HOMEBREW_UNINSTALL_URL,
    #                 "-o",
    #                 "uninstall_homebrew",
    #             ],
    #             check=True,
    #         )
    #         subprocess.run(["chmod", "+x", "uninstall_homebrew"], check=True)
    #
    #         # run it in dry run to get everything it would remove
    #         subprocess.run(
    #             ["./uninstall_homebrew", "-f"],
    #             check=True,
    #         )


if __name__ == "__main__":
    main()
