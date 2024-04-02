from pathlib import Path

import click
import conda_build.config
from conda_package_handling.api import list_contents

from .utils import built_distributions, compute_sha256sum


@click.command()
def main():
    for artifact in sorted(built_distributions()):
        path = Path(artifact)
        relpath = path.relative_to(conda_build.config.croot)
        print(relpath)
        print("-" * len(str(relpath)))
        print("-- SHA256:", compute_sha256sum(path))
        print("-- Contents:")
        list_contents(artifact, verbose=True)
