import os
from setuptools import setup, find_packages

# PKG_VERSION is set by both rattler-build and conda-build.
__version__ = os.environ.get("PKG_VERSION", "0.0.1")

setup(
    name="conda_forge_ci_setup",
    version=__version__,
    description="conda-forge-ci-utils",
    author="conda-forge/core",
    author_email="conda-forge/core@github.com",
    url="https://conda-forge.org",
    packages=find_packages(),
    entry_points={
        "console_scripts": [
            "ff_ci_pr_build = conda_forge_ci_setup.ff_ci_pr_build:main",
            "upload_or_check_non_existence = conda_forge_ci_setup.upload_or_check_non_existence:main",  # noqa
            "setup_conda_rc = conda_forge_ci_setup.build_utils:setup_conda_rc",
            "upload_package = conda_forge_ci_setup.build_utils:upload_package",
            "mangle_compiler = conda_forge_ci_setup.build_utils:mangle_compiler",  # noqa
            "make_build_number = conda_forge_ci_setup.build_utils:make_build_number",  # noqa
            "mangle_homebrew = conda_forge_ci_setup.mangle_homebrew:main",
            "validate_recipe_outputs = conda_forge_ci_setup.feedstock_outputs:main",  # noqa
            "inspect_artifacts = conda_forge_ci_setup.inspect_artifacts:main",
        ]
    },
)
