from pathlib import Path
import os

import click
import conda_build.config
from conda_package_handling.api import list_contents

from .utils import (
    built_distributions,
    compute_sha256sum,
    get_built_distribution_names_and_subdirs,
    human_readable_bytes,
)


@click.command()
def main():
    allowed_dist_names, allowed_subdirs = get_built_distribution_names_and_subdirs()
    distributions = built_distributions(subdirs=allowed_subdirs)
    distributions = [
        dist
        for dist in distributions
        if any(os.path.basename(dist).startswith(allowed + "-") for allowed in allowed_dist_names)
    ]

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
