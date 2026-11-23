#!/usr/bin/env python
from __future__ import print_function

import contextlib
import datetime
import json
import os
import shutil
import subprocess
import click
import tempfile
import time

from binstar_client.utils import get_server_api
import binstar_client.errors
from conda.base.context import context
import conda_build.api
import conda_build.config

from .feedstock_outputs import request_copy, split_pkg
from .utils import (
    compute_sha256sum,
    determine_build_tool,
    get_built_distribution_names_and_subdirs,
)

# A file named like this is written to the build folder after each successful
# copy request. The folder is also visible outside of docker, so CI can create
# attestations for exactly the packages that were sent to conda-forge.
ATTEST_SUBJECTS_PREFIX = "attest-subjects-"
CHANNEL_ALIAS = "https://conda.anaconda.org"

conda_subdir = context.subdir


@contextlib.contextmanager
def get_temp_token(token):
    dn = tempfile.mkdtemp()
    fn = os.path.join(dn, "binstar.token")
    with open(fn, "w") as fh:
        fh.write(token)
    yield fn
    try:
        shutil.rmtree(dn)
    except Exception:
        print(f"Failed to remove temporary directroy '{dn}'")


def built_distribution_already_exists(cli, name, version, fname, owner, channel):
    """Checks to see whether the built recipe (aka distribution) already
    exists on the owner/user's binstar account.

    NOTE: This function uses older nomeclature regarding conda channels and labels.
    Namely the `owner` is what we now call a `channel` and the `channel` is what we
    now call a `label`.

    Parameters
    ----------
    cli : binstar_client.utils.get_server_api
        The binstar client
    name : str
        The name of the package
    version : str
        The version of the package
    fname : str
        The path to the built distribution
    owner : str
        The owner/user of the binstar account.
    channel : str
        The channel to check for the distribution.

    Returns
    -------
    bool
        Whether the distribution already exists on the binstar account.
    """
    folder, basename = os.path.split(fname)
    _, platform = os.path.split(folder)

    if basename.endswith(".tar.bz2"):
        base_fname = basename[:-8]
    elif basename.endswith(".conda"):
        base_fname = basename[:-6]
    else:
        base_fname = basename

    exists = False
    for ext in [".tar.bz2", ".conda"]:
        distro_name = '{}/{}'.format(platform, base_fname + ext)
        try:
            dist_info = cli.distribution(owner, name, version, distro_name)
        except binstar_client.errors.NotFound:
            dist_info = {}

        exists = exists or (bool(dist_info) and channel in dist_info.get('labels', ()))
        # Unfortunately, we cannot check the md5 quality of the built distribution, as
        # this will depend on fstat information such as modification date (because
        # distributions are tar files). Therefore we can only assume that the distribution
        # just built, and the one on anaconda.org are the same.
        # if exists:
        #     md5_on_binstar = dist_info.get('md5')
        #     with open(fname, 'rb') as fh:
        #        md5_of_build = hashlib.md5(fh.read()).hexdigest()
        #
        #     if md5_on_binstar != md5_of_build:
        #        raise ValueError('This build ({}), and the build already on binstar '
        #                         '({}) are different.'.format(md5_of_build, md5_on_binstar))  # noqa

    return exists


def upload(token_fn, path, owner, channels, private_upload=False, force_metadata_update=True):
    cmd = ['anaconda', '--quiet', '--show-traceback', '-t', token_fn,
           'upload', path, '--user={}'.format(owner),
           '--channel={}'.format(channels)]
    if private_upload:
        cmd.append("--private")
    if force_metadata_update:
        cmd.append("--force-metadata-update")
    subprocess.check_call(cmd,  env=os.environ)


def delete_dist(token_fn, path, owner, channels):
    parts = path.split(os.sep)
    path = os.path.join(parts[-2], parts[-1])
    _, name, ver, _ = split_pkg(path)
    subprocess.check_call(
        [
            'anaconda', '--quiet', '-t', token_fn,
            'remove', '-f', '%s/%s/%s/%s/%s' % (
                owner, name, ver, parts[-2], parts[-1]),
        ],
        env=os.environ
    )


def target_channel_url(owner, label):
    """The URL of the channel that packages uploaded to `owner/label` end up in."""
    if label == "main":
        return "{}/{}".format(CHANNEL_ALIAS, owner)
    return "{}/{}/label/{}".format(CHANNEL_ALIAS, owner, label)


class AttestSubjects:
    """The packages that one upload copied to production, for attestations.

    Each entry (filename, SHA-256 and target channel) is added to one JSON
    file in the build folder, named by the time the upload started, so that
    several uploads in one job (e.g. to more than one label) get their own
    file. The file is updated after every successful copy request, so retries
    add to it instead of replacing it.
    """

    def __init__(self, croot=None):
        if croot is None:
            croot = conda_build.config.croot
        timestamp = datetime.datetime.now(datetime.timezone.utc).strftime(
            "%Y%m%dT%H%M%S%fZ"
        )
        self.filename = os.path.join(
            croot, "{}{}.json".format(ATTEST_SUBJECTS_PREFIX, timestamp)
        )
        # the paths sent in a copy request, by any attempt of this upload
        self.requested = set()

    def add(self, paths, target_channel):
        subjects = []
        if os.path.exists(self.filename):
            with open(self.filename) as fp:
                subjects = json.load(fp)
        for path in sorted(paths):
            entry = {
                "name": os.path.basename(path),
                "sha256": compute_sha256sum(path),
                "target_channel": target_channel,
            }
            if entry not in subjects:
                subjects.append(entry)
        with open(self.filename, "w") as fp:
            json.dump(subjects, fp)
        print(
            "Wrote {} package(s) for attestation to {}".format(
                len(subjects), os.path.basename(self.filename)
            )
        )


def upload_or_check(
    feedstock,
    recipe_dir,
    owner,
    channel,
    variant,
    validate=False,
    git_sha=None,
    private_upload=False,
    prod_owner="conda-forge",
    comment_on_error=True,
    feedstock_root=None,
    attest_subjects=None,
):
    """Upload the built packages, or check that they exist.

    With `validate`, the packages that were copied to `prod_owner` are added
    to `attest_subjects` (an `AttestSubjects`), if given.
    """
    if validate and "STAGING_BINSTAR_TOKEN" in os.environ:
        token = os.environ["STAGING_BINSTAR_TOKEN"]
        print("Using STAGING_BINSTAR_TOKEN for anaconda.org uploads to %s." % owner)
    else:
        token = os.environ.get('BINSTAR_TOKEN')
        print("Using BINSTAR_TOKEN for anaconda.org uploads to %s." % owner)

    # Azure's tokens are filled when in PR and not empty as for the other cis
    # In pr they will have a value like '$(secret-name)'
    if token and token.startswith('$('):
        token = None

    cli = get_server_api(token=token)

    build_tool = determine_build_tool(feedstock_root)

    allowed_dist_names, allowed_subdirs = get_built_distribution_names_and_subdirs(
        recipe_dir=recipe_dir, variant=variant, build_tool=build_tool
    )

    # The list of built distributions
    paths = set()
    for subdir in list(allowed_subdirs) + [conda_subdir, 'noarch']:
        if not os.path.exists(os.path.join(conda_build.config.croot, subdir)):
            continue
        for p in os.listdir(os.path.join(conda_build.config.croot, subdir)):
            paths.add(os.path.join(subdir, p))

    built_distributions = [
        (
            split_pkg(path)[1],
            split_pkg(path)[2],
            os.path.join(conda_build.config.croot, path)
        )
        # TODO: flip this over to .conda when that format
        #  is in flight
        for path in paths if (path.endswith('.tar.bz2') or path.endswith(".conda"))
        if split_pkg(path)[1] in allowed_dist_names
    ]

    # This is the actual fix where we create the token file once and reuse it
    # for all uploads
    if token:
        with get_temp_token(cli.token) as token_fn:
            if validate:
                to_copy_paths = []
                # copied by a copy request of an earlier attempt that failed
                # for other packages
                copied_before = []
                for name, version, path in built_distributions:
                    need_copy = True
                    for i in range(0, 5):
                        time.sleep(i*15)
                        if built_distribution_already_exists(
                            cli, name, version, path, prod_owner, channel,
                        ):
                            # package already in production
                            need_copy = False
                            break
                        elif not built_distribution_already_exists(
                            cli, name, version, path, owner, channel,
                        ):
                            upload(token_fn, path, owner, channel)
                            break
                        else:
                            print(
                                "Distribution {} already exists on {}. "
                                "Waiting another {} seconds to "
                                "try uploading again.".format(path, owner, (i+1) * 15))
                    else:
                        print(
                            "WARNING: Distribution {} already existed in "
                            "{} for a while. Deleting and "
                            "re-uploading.".format(path, owner)
                        )
                        delete_dist(token_fn, path, owner, channel)
                        upload(token_fn, path, owner, channel)

                    if need_copy:
                        to_copy_paths.append(path)
                    elif (
                        attest_subjects is not None
                        and path in attest_subjects.requested
                    ):
                        copied_before.append(path)

                target_channel = target_channel_url(prod_owner, channel)
                if attest_subjects is not None:
                    if copied_before:
                        attest_subjects.add(copied_before, target_channel)
                    attest_subjects.requested.update(to_copy_paths)

                if to_copy_paths and not request_copy(
                    feedstock,
                    to_copy_paths,
                    channel,
                    git_sha=git_sha,
                    comment_on_error=comment_on_error,
                ):
                    raise RuntimeError(
                        "copy from staging to production channel failed")
                if attest_subjects is not None and to_copy_paths:
                    attest_subjects.add(to_copy_paths, target_channel)
                return True
            else:
                for name, version, path in built_distributions:
                    if not built_distribution_already_exists(
                        cli, name, version, path, owner, channel,
                    ):
                        upload(token_fn, path, owner, channel, private_upload=private_upload)
                    else:
                        print(
                            'Distribution {} already exists for {}'.format(path, owner))
                return True
    else:
        for name, version, path in built_distributions:
            if not built_distribution_already_exists(cli, name, version, path, owner, channel):
                print(
                    "Distribution {} is new for {}, but no upload is taking place "
                    "because the BINSTAR_TOKEN/STAGING_BINSTAR_TOKEN "
                    "is missing or empty.".format(path, owner))
            else:
                print('Distribution {} already exists for {}'.format(path, owner))
        return False


def retry_upload_or_check(
    feedstock,
    recipe_dir,
    owner,
    channel,
    variant,
    validate=False,
    git_sha=None,
    private_upload=False,
    feedstock_root=None,
):
    # perform a backoff in case we fail.  THis should limit the failures from
    # issues with the Anaconda api
    n_try = 10
    attest_subjects = AttestSubjects()
    for i in range(1, n_try):
        try:
            res = upload_or_check(
                feedstock, recipe_dir, owner, channel, variant,
                validate=validate, git_sha=git_sha,
                comment_on_error=True if i == n_try-1 else False,
                private_upload=private_upload,
                feedstock_root=feedstock_root,
                attest_subjects=attest_subjects,
            )
            return res
        except Exception as e:
            # exponential backoff, wait at least 10 seconds
            timeout = max(1.75 ** i, 10)
            print(
                "Failed to upload due to {}. Trying again in {} seconds".format(
                    e, timeout))
            time.sleep(timeout)
    raise TimeoutError("Did not manage to upload package.  Failing.")


@click.command()
@click.argument('recipe_dir',
                type=click.Path(exists=True, file_okay=False, dir_okay=True),
                )  # help='the conda recipe directory'
@click.argument('owner')  # help='the binstar owner/user'
@click.option('--channel', default='main',
              help='the anaconda label channel')
@click.option('--variant', '-m', multiple=True,
              type=click.Path(exists=True, file_okay=True, dir_okay=False),
              help="path to conda_build_config.yaml defining your base matrix")
@click.option('--feedstock-root', '-f',
              multiple=False,
              default=None,
              type=click.Path(exists=True, file_okay=False, dir_okay=True),
              help="path to feedstock")
def main(recipe_dir, owner, channel, variant, feedstock_root):
    """
    Upload or check consistency of a built version of a conda recipe with binstar.
    Note: The existence of the BINSTAR_TOKEN environment variable determines
    whether the upload should actually take place."""
    return retry_upload_or_check(None, recipe_dir, owner, channel, variant, feedstock_root=feedstock_root)


if __name__ == '__main__':
    main()
