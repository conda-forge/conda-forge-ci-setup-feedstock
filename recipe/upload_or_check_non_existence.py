#!/usr/bin/env python
from __future__ import print_function

import argparse
import contextlib
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import time

from binstar_client.utils import get_server_api
import binstar_client.errors
from conda_build.conda_interface import subdir as conda_subdir
from conda_build.conda_interface import get_index
import conda_build.api

on_win = (sys.platform == "win32")


@contextlib.contextmanager
def get_temp_token(token):
    dn = tempfile.mkdtemp()
    fn = os.path.join(dn, "binstar.token")
    with open(fn, "w") as fh:
        fh.write(token)
    yield fn
    try:
        shutil.rmtree(dn)
    except OSError:
        if on_win:
            # On Windows, rmtree might have failed due to something else
            # accessing the directory -- just wait a bit and try again.
            time.sleep(0.1)
            shutil.rmtree(dn)
        else:
            raise


def built_distribution_already_exists(cli, meta, fname, owner):
    """
    Checks to see whether the built recipe (aka distribution) already
    exists on the owner/user's binstar account.

    """
    folder, basename = os.path.split(fname)
    _, platform = os.path.split(folder)
    distro_name = '{}/{}'.format(platform, basename)

    try:
        dist_info = cli.distribution(owner, meta.name(), meta.version(),
                                     distro_name)
    except binstar_client.errors.NotFound:
        dist_info = {}

    exists = bool(dist_info)
    # Unfortunately, we cannot check the md5 quality of the built distribution, as
    # this will depend on fstat information such as modification date (because
    # distributions are tar files). Therefore we can only assume that the distribution
    # just built, and the one on anaconda.org are the same.
#    if exists:
#        md5_on_binstar = dist_info.get('md5')
#        with open(fname, 'rb') as fh:
#            md5_of_build = hashlib.md5(fh.read()).hexdigest()
#
#        if md5_on_binstar != md5_of_build:
#            raise ValueError('This build ({}), and the build already on binstar '
#                             '({}) are different.'.format(md5_of_build, md5_on_binstar))
    return exists


def upload(token_fn, path, owner, channels):
    subprocess.check_call(['anaconda', '--quiet', '-t', token_fn,
                           'upload', path,
                           '--user={}'.format(owner),
                           '--channel={}'.format(channels)],
                          env=os.environ)


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


def main():
    token = os.environ.get('BINSTAR_TOKEN')

    description = ('Upload or check consistency of a built version of a '
                   'conda recipe with binstar. Note: The existence of the '
                   'BINSTAR_TOKEN environment variable determines '
                   'whether the upload should actually take place.')
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('recipe_dir', help='the conda recipe directory')
    parser.add_argument('owner', help='the binstar owner/user')
    parser.add_argument('--channel', help='the binstar channel', default='main')
    parser.add_argument("-m", "--variant-config-files", action="append",
                        help="path to conda_build_config.yaml defining your base matrix")
    args = parser.parse_args()
    recipe_dir, owner, channel = args.recipe_dir, args.owner, args.channel

    cli = get_server_api(token=token)
    metas = conda_build.api.render(recipe_dir, variant_config_files=args.variant_config_files)

    # Print the skipped distributions
    skipped_distributions = [ m for m, _, _ in metas if m.skip() ]
    for m in skipped_distributions:
        print("{} configuration was skipped in build/skip.".format(m.name()))


    # The list of built/not skipped distributions
    built_distributions = [(m, path)
                           for m, _, _ in metas
                           for path in conda_build.api.get_output_file_paths(m)
                           if not m.skip()]

    # These are the ones that already exist on the owner channel's
    existing_distributions = [path for m, path in built_distributions
                              if built_distribution_already_exists(cli, m, path, owner)]
    for d in existing_distributions:
        print('Distribution {} already exists for {}'.format(d, owner))


    # These are the ones that are new to the owner channel's
    new_distributions = [path for m, path in built_distributions
                         if not built_distribution_already_exists(cli, m, path, owner)]

    # This is the actual fix where we create the token file once and reuse it for all uploads
    if token:
      with get_temp_token(cli.token) as token_fn:
        for path in new_distributions:
            upload(token_fn, path, owner, channel)
            print('Uploaded {}'.format(path))
    else:
      for path in new_distributions:
          print("Distribution {} is new for {}, but no upload is taking place "
                "because the BINSTAR_TOKEN is missing.".format(path, owner))

if __name__ == '__main__':
    main()
