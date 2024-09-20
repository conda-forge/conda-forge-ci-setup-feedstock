from pathlib import Path

import click
import conda_build.config
from conda_package_handling.api import list_contents

from .utils import (
    built_distributions,
    built_distributions_from_recipe_variant,
    compute_sha256sum,
    human_readable_bytes,
)


@click.command()
@click.option(
    '--all-packages',
    is_flag=True,
    help='inspect all packages found in the conda-build root directory'
)
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
def main(all_packages, recipe_dir, variant):
    if all_packages:
        distributions = built_distributions()
    else:
        distributions = built_distributions_from_recipe_variant(recipe_dir=recipe_dir, variant=variant)

    for artifact in sorted(distributions):
        path = Path(artifact)
        relpath = path.relative_to(conda_build.config.croot)
        print("-" * len(str(relpath)))
        print(relpath)
        print("-" * len(str(relpath)))
        print("-- Size:", human_readable_bytes(path.stat().st_size))
        print("-- SHA256:", compute_sha256sum(path))
        print("-- Contents:")
        list_contents(artifact, verbose=True)
