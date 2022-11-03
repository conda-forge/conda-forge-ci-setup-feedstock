#!/usr/bin/env python
from __future__ import print_function

import contextlib
import os
import shutil
import subprocess
import click
import tempfile
import time

from binstar_client.utils import get_server_api
import binstar_client.errors
from conda_build.conda_interface import subdir as conda_subdir
from conda_build.conda_interface import get_index
import conda_build.api
import conda_build.config

from .feedstock_outputs import request_copy, split_pkg

def get_built_distribution_names_and_subdirs(recipe_dir, variant):
    additional_config = {}
    for v in variant:
        variant_dir, base_name = os.path.split(v)
        clobber_file = os.path.join(variant_dir, 'clobber_' + base_name)
        if os.path.exists(clobber_file):
            additional_config = {
                'clobber_sections_file': clobber_file
            }
            break

    metas = conda_build.api.render(
        recipe_dir,
        variant_config_files=variant,
        finalize=False,
        bypass_env_check=True,
        **additional_config)

    # Print the skipped distributions
    skipped_distributions = [m for m, _, _ in metas if m.skip()]
    for m in skipped_distributions:
        print("{} configuration was skipped in build/skip.".format(m.name()))

    subdirs = set([m.config.target_subdir for m, _, _ in metas if not m.skip()])
    return set([m.name() for m, _, _ in metas if not m.skip()]), subdirs


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


def built_distribution_already_exists(cli, name, version, fname, owner):
    """
    Checks to see whether the built recipe (aka distribution) already
    exists on the owner/user's binstar account.

    """
    folder, basename = os.path.split(fname)
    _, platform = os.path.split(folder)
    distro_name = '{}/{}'.format(platform, basename)

    try:
        dist_info = cli.distribution(owner, name, version, distro_name)
    except binstar_client.errors.NotFound:
        dist_info = {}

    exists = bool(dist_info)
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


def upload(token_fn, path, owner, channels, private_upload=False):
    cmd = ['anaconda', '--quiet', '-t', token_fn,
           'upload', path, '--user={}'.format(owner),
           '--channel={}'.format(channels)]
    if private_upload:
        cmd.append("--private")
    subprocess.check_call(cmd,  env=os.environ)

def upload_ghcr(path, channel):
    from conda_oci_mirror.oci_mirror import upload_conda_package
    upload_conda_package(path, "ghcr.io", channel, "")

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


def distribution_exists_on_channel(binstar_cli, meta, fname, owner, channel='main'):
    """
    Determine whether a distribution exists on a specific channel.

    Note from @pelson: As far as I can see, there is no easy way to do this on binstar.

    """
    channel_url = '/'.join([owner, 'label', channel])
    fname = os.path.basename(fname)

    distributions_on_channel = get_index([channel_url],
                                         prepend=False, use_cache=False)

    try:
        on_channel = (distributions_on_channel[fname]['subdir'] ==
                      conda_subdir)
    except KeyError:
        on_channel = False

    return on_channel


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
):
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

    allowed_dist_names, allowed_subdirs = get_built_distribution_names_and_subdirs(recipe_dir, variant)

    # The list of built distributions
    paths = set()
    for subdir in list(allowed_subdirs) + [conda_build.config.subdir, 'noarch']:
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
        for path in paths if path.endswith('.tar.bz2')
        if split_pkg(path)[1] in allowed_dist_names
    ]

    # This is the actual fix where we create the token file once and reuse it
    # for all uploads
    if token:
        with get_temp_token(cli.token) as token_fn:
            if validate:
                to_copy_paths = []
                for name, version, path in built_distributions:
                    need_copy = True
                    for i in range(0, 5):
                        time.sleep(i*15)
                        if built_distribution_already_exists(
                            cli, name, version, path, prod_owner
                        ):
                            # package already in production
                            need_copy = False
                            break
                        elif not built_distribution_already_exists(
                            cli, name, version, path, owner
                        ):
                            upload(token_fn, path, owner, channel)
                            upload_ghcr(path, channel)
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
                        upload_ghcr(path, channel)
                    if need_copy:
                        to_copy_paths.append(path)

                if to_copy_paths and not request_copy(
                    feedstock,
                    to_copy_paths,
                    channel,
                    git_sha=git_sha,
                    comment_on_error=comment_on_error,
                ):
                    raise RuntimeError(
                        "copy from staging to production channel failed")
                else:
                    return True
            else:
                for name, version, path in built_distributions:
                    if not built_distribution_already_exists(
                        cli, name, version, path, owner
                    ):
                        upload(token_fn, path, owner, channel, private_upload=private_upload)
                        upload_ghcr(path, channel)
                    else:
                        print(
                            'Distribution {} already exists for {}'.format(path, owner))
                return True
    else:
        for name, version, path in built_distributions:
            if not built_distribution_already_exists(cli, name, version, path, owner):
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
):
    # perform a backoff in case we fail.  THis should limit the failures from
    # issues with the Anaconda api
    n_try = 10
    for i in range(1, n_try):
        try:
            res = upload_or_check(
                feedstock, recipe_dir, owner, channel, variant,
                validate=validate, git_sha=git_sha,
                comment_on_error=True if i == n_try-1 else False,
                private_upload=private_upload
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
def main(recipe_dir, owner, channel, variant):
    """
    Upload or check consistency of a built version of a conda recipe with binstar.
    Note: The existence of the BINSTAR_TOKEN environment variable determines
    whether the upload should actually take place."""
    return retry_upload_or_check(None, recipe_dir, owner, channel, variant)


if __name__ == '__main__':
    main()
