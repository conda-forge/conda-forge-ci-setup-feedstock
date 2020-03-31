from setuptools import setup

packages = ["conda_forge_ci_setup"]

setup(
    name="conda_forge_ci_setup",
    version="2.5.1",
    description="conda-forge-ci-utils",
    author="conda-forge/core",
    author_email="conda-forge/core@github.com",
    url="https://conda-forge.org",
    packages=packages,
    entry_points={
        "console_scripts": [
            "ff_ci_pr_build = conda_forge_ci_setup.ff_ci_pr_build:main",
            "upload_or_check_non_existence = conda_forge_ci_setup.upload_or_check_non_existence:main",
            "setup_conda_rc = conda_forge_ci_setup.build_utils:setup_conda_rc",
            "upload_package = conda_forge_ci_setup.build_utils:upload_package",
            "mangle_compiler = conda_forge_ci_setup.build_utils:mangle_compiler",
            "make_build_number = conda_forge_ci_setup.build_utils:make_build_number",
        ]
    },
)
