import os
import sys
import hashlib
import json
import functools

import conda_build
import requests
import click

try:
    from ruamel_yaml import safe_load
except ImportError:
    from yaml import safe_load

VALIDATION_ENDPOINT = "https://conda-forge.herokuapp.com"
STAGING = "cf-staging"


def _compute_md5sum(pth):
    h = hashlib.md5()

    with open(pth, 'rb') as fp:
        chunk = 0
        while chunk != b'':
            chunk = fp.read(1024)
            h.update(chunk)

    return h.hexdigest()


def request_copy(dists, channel):
    checksums = {}
    for dist in dists:
        pth, distname = dist.split(os.path.sep, 1)
        checksums[dist] = _compute_md5sum(dist)

    feedstock = os.path.basename(os.getcwd())

    if "FEEDSTOCK_TOKEN" not in os.environ:
        print(
            "ERROR you must have defined a FEEDSTOCK_TOKEN in order to "
            "perform output copies to the production channels!"
        )

    headers = {"FEEDSTOCK_TOKEN": os.environ["FEEDSTOCK_TOKEN"]}
    json_data = {
        "feedstock": feedstock,
        "outputs": checksums,
        "channel": channel,
    }
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


@functools.lru_cache(maxsize=1)
def _should_validate():
    if os.path.exists("conda-forge.yml"):
        with open("conda-forge.yml", "r") as fp:
            cfg = safe_load(fp)

        return cfg.get("conda_forge_output_validation", False)
    else:
        return False


@click.command()
def main():
    """Validate the feedstock outputs."""

    if not _should_validate():
        sys.exit(0)

    feedstock = os.path.basename(os.getcwd())

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

    r = requests.post(
        "%s/feedstock-outputs/validate" % VALIDATION_ENDPOINT,
        json={
            "feedstock": feedstock,
            "outputs": built_distributions,
        },
    )

    if r.status_code != 200:
        print(
            "ERROR: output validation failed - your recipe/feedstock is "
            "producing outputs that are already used by another "
            "recipe/feedstock!"
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

    print("validation results:\n%s" % json.dumps(results, indent=2))

    if r.status_code != 200:
        sys.exit(1)
