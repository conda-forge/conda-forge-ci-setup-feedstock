from pathlib import Path

import click
import conda_build.config
from conda_package_handling.api import list_contents

from .utils import built_distributions, compute_sha256sum, human_readable_bytes


@click.command()
def main():
    for artifact in sorted(built_distributions()):
        path = Path(artifact)
        relpath = path.relative_to(conda_build.config.croot)
        print("-" * len(str(relpath)))
        print(relpath)
        print("-" * len(str(relpath)))
        print("-- Size:", human_readable_bytes(path.stat().st_size))
        print("-- SHA256:", compute_sha256sum(path))
        print("-- Contents:")
        list_contents(artifact, verbose=True)
