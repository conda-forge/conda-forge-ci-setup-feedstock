import os
import sys
import hashlib
import json
import pprint

import conda_build
import conda_build.config
import requests
import click

VALIDATION_ENDPOINT = "https://conda-forge.herokuapp.com"
STAGING = "cf-staging"


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


def request_copy(feedstock, dists, channel):
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
    built_distributions = [
        _unix_dist_path(path) for path in paths if path.endswith('.tar.bz2')
    ]

    print("validating outputs:\n%s" % pprint.pformat(built_distributions))

    r = requests.post(
        "%s/feedstock-outputs/validate" % VALIDATION_ENDPOINT,
        json={
            "feedstock": feedstock_name,
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
