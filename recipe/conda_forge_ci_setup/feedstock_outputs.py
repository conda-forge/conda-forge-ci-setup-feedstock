import os
import json
import time
import sys

import click
import requests
import conda_build.config
from conda_forge_metadata.feedstock_outputs import (
    package_to_feedstock,
    feedstock_outputs_config,
)

from .utils import (
    built_distributions_from_recipe_variant,
    compute_sha256sum,
    split_pkg,
    is_conda_forge_output_validation_on,
)


VALIDATION_ENDPOINT = "https://conda-forge.herokuapp.com"
STAGING = "cf-staging"


def _unix_dist_path(path):
    return "/".join(path.split(os.sep)[-2:])


def request_copy(feedstock, dists, channel, git_sha=None, comment_on_error=True):
    checksums = {}
    for path in dists:
        dist = _unix_dist_path(path)
        checksums[dist] = compute_sha256sum(path)

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
        "hash_type": "sha256",
        "provider": os.environ.get("CI", None),
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
        The GitHub repo, sans owner or `-feedstock` suffix. For example,
        for `numpy`, just use `numpy`, not `conda-forge/numpy-feedstock` or `numpy-feedstock`.
    outputs : list of str
        A list of outputs top validate. The list entries should be the
        full names with the platform directory, version/build info, and file extension
        (e.g., `noarch/blah-fa31b0-2020.04.13.15.54.07-py_0.tar.bz2`).

    Returns
    -------
    valid : dict
        A dict keyed on output name with True if it is valid and False
        otherwise.
    """
    if "/" in project:
        project = project.split("/")[-1]
    if project.endswith("-feedstock"):
        feedstock = project[:-len("-feedstock")]
    else:
        feedstock = project

    valid = {o: False for o in outputs}

    for dist in outputs:
        try:
            _, o, _, _ = split_pkg(dist)
        except RuntimeError:
            continue

        for i in range(3):  # three attempts
            try:
                registered_feedstocks = package_to_feedstock(o)
            except requests.exceptions.HTTPError as exc:
                if exc.response.status_code == 404:
                    # no output exists so see if we can add it
                    valid[dist] = feedstock_outputs_config().get("auto_register_all", False)
                    break
                elif i < 2:
                    # wait and retry
                    time.sleep(1)
                else:
                    # last attempt, i==2, did not work
                    # This should rarely happen, if ever
                    print(
                        "ERROR: Assuming package not allowed. "
                        f"Failed to get feedstock data. {type(exc)}: {exc}"
                    )
                    valid[dist] = False
            else:
                # make sure feedstock is ok
                valid[dist] = feedstock in registered_feedstocks
                break

    return valid


@click.command()
@click.argument("feedstock_name", type=str)
@click.option(
    '--recipe-dir',
    type=click.Path(exists=False, file_okay=False, dir_okay=True),
    default=None,
    help='the conda recipe directory'
)
@click.option(
    '--variant',
    '-m',
    multiple=True,
    type=click.Path(exists=False, file_okay=True, dir_okay=False),
    default=(),
    help="path to conda_build_config.yaml defining your base matrix",
)
def main(feedstock_name, recipe_dir, variant):
    """Validate the feedstock outputs."""


    if is_conda_forge_output_validation_on():
        distributions = built_distributions_from_recipe_variant(recipe_dir=recipe_dir, variant=variant)
        distributions = [os.path.relpath(p, conda_build.config.croot) for p in distributions]
        results = is_valid_feedstock_output(feedstock_name, distributions)

        print("validation results:\n%s" % json.dumps(results, indent=2), flush=True)
        print(
            "NOTE: Any outputs marked as False are not allowed for this feedstock. "
            "See https://conda-forge.org/docs/maintainer/infrastructure/#output-validation-and-feedstock-tokens "
            "for information on how to address this error.",
            flush=True,
        )

        if not all(v for v in results.values()):
            sys.exit(1)
    else:
        print("Output validation is turned off. Skipping validation.", flush=True)
