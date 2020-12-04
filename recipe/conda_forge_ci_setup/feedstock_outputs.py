import os
import hashlib
import json
import tempfile
import subprocess
import shutil

import conda_build
import conda_build.config
import requests
import click

VALIDATION_ENDPOINT = "https://conda-forge.herokuapp.com"
STAGING = "cf-staging"
OUTPUTS_REPO = "https://github.com/conda-forge/feedstock-outputs.git"


def _get_sharded_path(output):
    chars = [c for c in output if c.isalnum()]
    while len(chars) < 3:
        chars.append("z")

    return os.path.join("outputs", chars[0], chars[1], chars[2], output + ".json")


def split_pkg(pkg):
    if not pkg.endswith(".tar.bz2"):
        raise RuntimeError("Can only process packages that end in .tar.bz2")
    pkg = pkg[:-8]
    plat, pkg_name = pkg.split(os.path.sep)
    name_ver, build = pkg_name.rsplit('-', 1)
    name, ver = name_ver.rsplit('-', 1)
    return plat, name, ver, build


def _unix_dist_path(path):
    return "/".join(path.split(os.sep)[-2:])


def _compute_md5sum(pth):
    h = hashlib.md5()

    with open(pth, 'rb') as fp:
        chunk = 0
        while chunk != b'':
            chunk = fp.read(1024)
            h.update(chunk)

    return h.hexdigest()


def request_copy(feedstock, dists, channel, git_sha=None, comment_on_error=True):
    checksums = {}
    for path in dists:
        dist = _unix_dist_path(path)
        checksums[dist] = _compute_md5sum(path)

    if "FEEDSTOCK_TOKEN" not in os.environ or os.environ["FEEDSTOCK_TOKEN"] is None:
        print(
            "ERROR you must have defined a FEEDSTOCK_TOKEN in order to "
            "perform output copies to the production channels!"
        )
        return False

    headers = {"FEEDSTOCK_TOKEN": os.environ["FEEDSTOCK_TOKEN"]}
    json_data = {
        "feedstock": feedstock,
        "outputs": checksums,
        "channel": channel,
        "comment_on_error": comment_on_error,
    }
    if git_sha is not None:
        json_data["git_sha"] = git_sha
    r = requests.post(
        "%s/feedstock-outputs/copy" % VALIDATION_ENDPOINT,
        headers=headers,
        json=json_data,
    )

    try:
        results = r.json()
    except Exception as e:
        print(
            "ERROR getting output validation information "
            "from the webservice:",
            repr(e)
        )
        results = {}

    print("copy results:\n%s" % json.dumps(results, indent=2))

    return r.status_code == 200


def is_valid_feedstock_output(project, outputs):
    """Test if feedstock outputs are valid (i.e., the outputs are allowed for that
    feedstock). Optionally register them if they do not exist.

    Parameters
    ----------
    project : str
        The GitHub repo.
    outputs : list of str
        A list of ouputs top validate. The list entries should be the
        full names with the platform directory, version/build info, and file extension
        (e.g., `noarch/blah-fa31b0-2020.04.13.15.54.07-py_0.tar.bz2`).

    Returns
    -------
    valid : dict
        A dict keyed on output name with True if it is valid and False
        otherwise.
    """
    if project.endswith("-feedstock"):
        feedstock = project[:-len("-feedstock")]
    else:
        feedstock = project

    valid = {o: False for o in outputs}

    tmpdir = None
    try:
        tmpdir = tempfile.mkdtemp('_recipe')
        repo_path = os.path.join(tmpdir, "feedstock-outputs")

        subprocess.run(
            ["git", "clone", "--depth=1", OUTPUTS_REPO, repo_path],
            check=True,
        )

        for dist in outputs:
            try:
                _, o, _, _ = split_pkg(dist)
            except RuntimeError:
                continue

            opth = _get_sharded_path(o)
            pth = os.path.join(repo_path, opth)

            if not os.path.exists(pth):
                # no output exists and we can add it
                valid[dist] = True
            else:
                # make sure feedstock is ok
                with open(pth, "r") as fp:
                    data = json.load(fp)
                valid[dist] = feedstock in data["feedstocks"]
    finally:
        if tmpdir is not None:
            # windows builds on azure sometimes fail when trying to remove
            # tmpdirs, so we try and if it fails just move on
            try:
                shutil.rmtree(tmpdir)
            except Exception:
                pass

    return valid


@click.command()
@click.argument("feedstock_name", type=str)
def main(feedstock_name):
    """Validate the feedstock outputs."""

    paths = (
        [
            os.path.join('noarch', p)
            for p in os.listdir(os.path.join(conda_build.config.croot, 'noarch'))  # noqa
        ]
        + [
            os.path.join(conda_build.config.subdir, p)
            for p in os.listdir(os.path.join(conda_build.config.croot, conda_build.config.subdir))  # noqa
        ])
    built_distributions = [path for path in paths if path.endswith('.tar.bz2')]

    results = is_valid_feedstock_output(feedstock_name, built_distributions)

    print("validation results:\n%s" % json.dumps(results, indent=2))
    print("NOTE: Any outputs marked as False are not allowed for this feedstock.")

    # FIXME: removing this for now - we can add extra arguments for us to
    # compute the output names properly later
    # if not all(v for v in results.values()):
    #     sys.exit(1)
