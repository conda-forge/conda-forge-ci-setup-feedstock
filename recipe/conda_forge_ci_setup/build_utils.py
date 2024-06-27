import os
import re
import sys
import subprocess
import platform

try:
    from ruamel_yaml import safe_load, safe_dump
except ImportError:
    from yaml import safe_load, safe_dump

import click


from conda_forge_ci_setup.upload_or_check_non_existence import retry_upload_or_check

from .feedstock_outputs import STAGING
from .utils import determine_build_tool, CONDA_BUILD

call = subprocess.check_call

_global_config = {
    "channels": {
        "sources": ["conda-forge", "defaults"],
        "targets": [["conda-forge", "main"]],
    }
}

cf_conda_build_defaults = {"pkg_format": "2", "zstd_compression_level": 19}


arg_feedstock_root = click.argument(
    "feedstock_root", type=click.Path(exists=True, file_okay=False, dir_okay=True)
)
arg_recipe_root = click.argument(
    "recipe_root", type=click.Path(exists=True, file_okay=False, dir_okay=True)
)
arg_config_file = click.argument(
    "config_file", type=click.Path(exists=True, file_okay=True, dir_okay=False)
)

def update_global_config(feedstock_root):
    """Merge the conda-forge.yml with predefined system defaults"""
    if os.path.exists(os.path.join(feedstock_root, "conda-forge.yml")):
        with open(os.path.join(feedstock_root, "conda-forge.yml")) as f:
            repo_config = safe_load(f)
        for k1, k2 in [("channels", "sources"), ("channels", "targets")]:
            if (k1 in repo_config) and (k2 in repo_config[k1]):
                _global_config[k1][k2] = repo_config[k1][k2]


def fail_if_outdated_windows_ci(feedstock_root):
    if sys.platform != "win32":
        return

    if "APPVEYOR_ACCOUNT_NAME" in os.environ:
        provider = "appveyor"
        if os.environ["APPVEYOR_ACCOUNT_NAME"] != "conda-forge":
            return
        if "APPVEYOR_PULL_REQUEST_NUMBER" not in os.environ:
            return
    elif "BUILD_REPOSITORY_NAME" in os.environ:
        provider = "azure"
        if not os.environ["BUILD_REPOSITORY_NAME"].startswith("conda-forge/"):
            return
        if "SYSTEM_PULLREQUEST_PULLREQUESTID" not in os.environ:
            return
    else:
        return

    with open(os.path.join(feedstock_root, "conda-forge.yml")) as f:
        config = safe_load(f)
        if "provider" in config and "win" in config["provider"]:
            provider_cfg = config["provider"]["win"]
            if provider_cfg != "azure":
                return
            if provider == "appveyor":
                raise RuntimeError(
                    "This PR needs a rerender to switch from appveyor to azure")
            if (
                provider == "azure"
                and (
                    os.getenv("UPLOAD_PACKAGES", "False") == "False"
                    or os.path.exists(".appveyor.yml")
                )
            ):
                raise RuntimeError(
                    "This PR needs a rerender to switch from appveyor to azure")


def fail_if_travis_not_allowed_for_arch(config_file, feedstock_root):
    specific_config = safe_load(open(config_file))
    if "channel_targets" in specific_config:
        channels = [c.strip().split(" ") for c in specific_config["channel_targets"]]
    else:
        update_global_config(feedstock_root)
        channels = _global_config["channels"]["targets"]

    upload_to_conda_forge = any(owner == "conda-forge" for owner, _ in channels)

    if (
        upload_to_conda_forge
        and os.environ.get("CI", None) == "travis"
        and (
            platform.uname().machine.lower() in ["x86_64", "amd64"]
            or platform.system().lower() != "linux"
        )
    ):
        raise RuntimeError("Travis CI cannot be used on x86_64 in conda-forge!")


def maybe_use_dot_conda(feedstock_root):
    """Maybe set the .condarc to use .conda files."""
    if os.path.exists(os.path.join(feedstock_root, "conda-forge.yml")):
        with open(os.path.join(feedstock_root, "conda-forge.yml")) as f:
            repo_config = safe_load(f)

        conda_build_config_vars = repo_config.get("conda_build", {})
        for k, v in cf_conda_build_defaults.items():
            if k not in conda_build_config_vars:
                conda_build_config_vars[k] = v

        for k, v in conda_build_config_vars.items():
            if v is not None:
                call([
                    "conda", "config", "--env", "--set",
                    f"conda_build.{k}", str(v)
                ])


@click.command()
@arg_feedstock_root
@arg_recipe_root
@arg_config_file
def setup_conda_rc(feedstock_root, recipe_root, config_file):

    fail_if_outdated_windows_ci(feedstock_root)

    fail_if_travis_not_allowed_for_arch(config_file, feedstock_root)

    maybe_use_dot_conda(feedstock_root)

    with open(config_file) as f:
        specific_config = safe_load(f)
        if "channel_sources" in specific_config:
            channels = []
            last_channel = None
            for source in specific_config["channel_sources"]:
                # channel_sources might be part of some zip_key
                channels.extend([c.strip() for c in source.split(",")])

                if last_channel is not None and last_channel != source:
                    print(
                        "WARNING: Differing channel_sources found in config file.\n"
                        "When searching for a package conda-build will only consider "
                        "the first channel that contains any version of the package "
                        "due to strict channel priority.\n"
                        "As all channel_source entries are added to the build environment, this could "
                        "lead to unexpected behaviour."
                    )
                else:
                    last_channel = source
        else:
            update_global_config(feedstock_root)
            channels = _global_config["channels"]["sources"]

        try:
            call(["conda", "config", "--env", "--remove", "channels", "defaults"])
        except subprocess.CalledProcessError:
            pass

        for c in reversed(channels):
            call(["conda", "config", "--env", "--add", "channels", c])

        call(["conda", "config", "--env", "--set", "show_channel_urls", "true"])


@click.command()
@arg_feedstock_root
@arg_recipe_root
@arg_config_file
@click.option("--validate", is_flag=True)
@click.option("--private", is_flag=True)
@click.option("--feedstock-name", type=str, default=None)
def upload_package(feedstock_root, recipe_root, config_file, validate, private, feedstock_name):
    if feedstock_name is None and validate:
        raise RuntimeError("You must supply the --feedstock-name option if validating!")
    if feedstock_name and "/" in feedstock_name:
        print("INFO: --feedstock-name should not contain slashes. Using the last component.")
        feedstock_name = feedstock_name.split("/")[-1]

    specific_config = safe_load(open(config_file))
    if "channel_targets" in specific_config:
        channels = [c.strip().split(" ") for c in specific_config["channel_targets"]]
        source_channels = ",".join(
            [c.strip() for c in specific_config["channel_sources"]])
    else:
        update_global_config(feedstock_root)
        channels = _global_config["channels"]["targets"]
        source_channels = ",".join(_global_config["channels"]["sources"])

    if "UPLOAD_ON_BRANCH" in os.environ:
        if "GIT_BRANCH" not in os.environ:
            print(
                "WARNING: UPLOAD_ON_BRANCH env variable set, "
                "but GIT_BRANCH not set. Skipping check")
        else:
            if os.environ["UPLOAD_ON_BRANCH"] != os.environ["GIT_BRANCH"]:
                print(
                    "The branch {} is not configured to be "
                    "uploaded".format(os.environ["GIT_BRANCH"]))
                return

    upload_to_conda_forge = any(owner == "conda-forge" for owner, _ in channels)
    if upload_to_conda_forge and "channel_sources" in specific_config:
        allowed_channels = [
            "conda-forge", "conda-forge/label/\S+", "defaults", "c4aarch64",
            "c4armv7l"]
        for source_channel in source_channels.split(","):
            if source_channel.startswith('https://conda-web.anaconda.org/'):
                source_channel = source_channel[len('https://conda-web.anaconda.org/'):]
            for pattern in allowed_channels:
                if re.fullmatch(pattern, source_channel):
                    break
            else:
                print(
                    "Uploading to %s with source channel '%s' "
                    "is not allowed" % ("conda-forge", source_channel))
                return

    build_tool = determine_build_tool(feedstock_root)
    if build_tool != CONDA_BUILD and upload_to_conda_forge:
        # make sure that we are not uploading to the main conda-forge channel
        # when building packages with `rattler-build`
        if ["conda-forge", "main"] in channels:
            print(
                "Uploading to conda-forge's main channel is not yet allowed when building with rattler-build.\n"
                "You can set a label channel in the channel_targets section of the config file\n"
                "to upload to a label channel."
            )
            return

    # get the git sha of the current commit
    git_sha = subprocess.run(
        "git rev-parse HEAD",
        check=True,
        stdout=subprocess.PIPE,
        shell=True,
        cwd=feedstock_root,
    ).stdout.decode("utf-8").strip()
    if len(git_sha) == 0:
        git_sha = None
        print("Did not find git SHA for this build!")
    else:
        print("Found git SHA %s for this build!" % git_sha)

    for owner, channel in channels:
        if validate and owner == "conda-forge":
            retry_upload_or_check(
                feedstock_name, recipe_root, STAGING, channel,
                [config_file], validate=True, git_sha=git_sha,
                feedstock_root=feedstock_root,
            )
        else:
            retry_upload_or_check(
                feedstock_name, recipe_root, owner, channel,
                [config_file], validate=False, private_upload=private,
                feedstock_root=feedstock_root,
            )


@click.command()
@arg_feedstock_root
@arg_recipe_root
@arg_config_file
def make_build_number(feedstock_root, recipe_root, config_file):
    """
    General logic

        The purpose of this is to ensure that the new compilers have build
        numbers > 1000 and legacy compilers have a build number < 1000.

        This is done by reading the build_number_decrement which is rendered
        into all the recipes.

        For linux and osx we want to avoid building for the legacy compilers
        with build numbers > 1000

    Example matrix
        - {'compiler_c': 'toolchain_c', 'build_number_decrement': 1000}
        - {'compiler_c': 'gcc',         'build_number_decrement': 0}

    """
    specific_config = safe_load(open(config_file))
    build_number_dec = int(specific_config.get("build_number_decrement", [0])[0])
    if build_number_dec == 0:
        return

    use_legacy_compilers = False
    for key in {"c", "cxx", "fortran"}:
        if "toolchain_{}".format(key) in specific_config.get(
                '{}_compiler'.format(key), ""):
            use_legacy_compilers = True
            break

    import conda_build.api

    rendered_recipe = conda_build.api.render(
        recipe_path=recipe_root, variants=specific_config
    )
    build_numbers = set()
    for recipe, _, _ in rendered_recipe:
        build_numbers.add(int(recipe.get_value("build/number")))
    if len(build_numbers) > 1:
        raise ValueError("More than one build number found, giving up")
    if len(build_numbers) == 0:
        print("> conda-forge:: No build number found.  Presuming build string")
        return
    try:
        build_number_int = build_numbers.pop()

        if build_number_int < 1000:
            if not use_legacy_compilers:
                raise ValueError(
                    "Only legacy compilers only valid with build numbers < 1000"
                )
            new_build_number = build_number_int
        else:
            new_build_number = build_number_int - build_number_dec

        config_dir, filename = os.path.split(config_file)
        with open(os.path.join(config_dir, "clobber_" + filename), "w") as fo:
            data = {"build": {"number": new_build_number}}
            print("> conda-forge:: Build number clobber {} -> {}".format(
                build_number_int, new_build_number))
            safe_dump(data, fo)
    except ValueError:
        # This is a NON string build number
        # we have this for things like the blas mutex and a few other similar cases
        print("> conda-forge:: No build number clobber gererated!")
        import traceback
        traceback.print_exc()


@click.command()
@arg_feedstock_root
@arg_recipe_root
@arg_config_file
def mangle_compiler(feedstock_root, recipe_root, config_file):
    """Try hard to break the compilers for osx"""
    # TODO
