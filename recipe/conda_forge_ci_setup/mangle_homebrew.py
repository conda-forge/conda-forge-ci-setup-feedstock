#!/usr/bin/env python
import os
import subprocess
import shutil
import uuid
import tempfile
import contextlib


MANGLE_STR = 'h' + uuid.uuid4().hex[0:6]
HOMEBREW_UNINSTALL_URL = \
    "https://raw.githubusercontent.com/Homebrew/install/master/uninstall"

# https://stackoverflow.com/questions/6194499/pushd-through-os-system
@contextlib.contextmanager
def pushd(new_dir):
    previous_dir = os.getcwd()
    os.chdir(new_dir)
    try:
        yield
    finally:
        os.chdir(previous_dir)


def _mangele_path(pth):
    """mangle a path by adding a random string to the front and the back of the
    filename"""
    parts = os.path.split(pth)
    new_parts = [parts[0], parts[1]]
    new_parts[1] = MANGLE_STR + "_" + parts[1] + "_" + MANGLE_STR
    return os.path.join(*new_parts)


def main():
    with tempfile.TemporaryDirectory() as tmpdir:
        with pushd(tmpdir):
            # get the homebrew uninstall script
            subprocess.run(
                [
                    "curl",
                    "-fsSL",
                    HOMEBREW_UNINSTALL_URL,
                    "-o",
                    "uninstall_homebrew",
                ],
                check=True,
            )
            subprocess.run(["chmod", "+x", "uninstall_homebrew"], check=True)

            # run it in dry run to get everything it would remove
            proc_out = subprocess.check_output(
                ["./uninstall_homebrew", "--dry-run"],
                stderr=subprocess.STDOUT
            )

            try:
                proc_out = proc_out.decode("utf-8")
            except Exception:
                pass

    # now go through the lines and move the files to a mangled path
    # if that fails, then remove them, else pass
    for line in proc_out.splitlines():
        # this block handles links and gets both parts
        if "->" in line:
            parts = line.split("->")
        else:
            parts = [line]

        for p in parts:
            # ignore homebrew printing stuff
            if p.startswith("==>"):
                continue

            # sometimes it does this
            if p.startswith("Would delete "):
                p = p[len("Would delete "):]

            # finally do some cleanup
            p = p.strip()

            # and then remove
            if len(p) > 0 and os.path.exists(p) and os.path.isfile(p):
                mangled_p = _mangele_path(p)
                try:
                    shutil.move(p, mangled_p)
                    print("MOVED %s -> %s" % (p, mangled_p))
                except shutil.Error:
                    try:
                        os.remove(p)
                        print("REMOVED %s " % p)
                    except Exception as e:
                        print("ERROR moving or removing %s: %s" % (p, repr(e)))


if __name__ == "__main__":
    main()
