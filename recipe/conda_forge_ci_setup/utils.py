import hashlib
import os

import conda_build.api
import conda_build.config
from conda.base.context import context
from conda_build.variants import combine_specs, parse_config_file
import joblib

try:
    from ruamel_yaml import safe_load
except ImportError:
    from yaml import safe_load

import rattler_build_conda_compat.render

CONDA_BUILD = "conda-build"
RATTLER_BUILD = "rattler-build"

os.makedirs(".joblib_cache", exist_ok=True)
JOBLIB_MEMORY = joblib.Memory(".joblib_cache", verbose=0)


@JOBLIB_MEMORY.cache
def get_built_distribution_names_and_subdirs(recipe_dir=None, variant=None, build_tool=None):
    feedstock_root = os.environ.get(
        "FEEDSTOCK_ROOT",
        os.getcwd(),
    )
    if recipe_dir is None:
        recipe_dir = os.path.join(feedstock_root, "recipe")
    if build_tool is None:
        build_tool = determine_build_tool(feedstock_root)
    if not variant:
        if "CONFIG_FILE" in os.environ:
            variant = [os.environ.get("CONFIG_FILE")]
        else:
            variant = [
                os.path.join(
                    os.environ.get("CI_SUPPORT", os.path.join(feedstock_root, ".ci_support")),
                    os.environ.get("CONFIG") + ".yaml"
                )
            ]

    additional_config = {}
    for v in variant:
        variant_dir, base_name = os.path.split(v)
        clobber_file = os.path.join(variant_dir, 'clobber_' + base_name)
        if os.path.exists(clobber_file):
            additional_config = {
                'clobber_sections_file': clobber_file
            }
            break

    if build_tool == RATTLER_BUILD:
        # some conda-build magic here
        with open(variant[-1]) as f:
            final_variant = safe_load(f)
        extra_args = {}
        if "target_platform" in final_variant:
            target_platform = final_variant["target_platform"][0]
            if target_platform != "noarch":
                platform, arch = target_platform.split("-")
                extra_args = {
                    "platform": platform,
                    "arch": arch
                }

        config = conda_build.config.Config(**extra_args)

        specs = {}
        for _variant_fname in variant:
            specs[_variant_fname] = parse_config_file(_variant_fname, config)
        final_variant = combine_specs(specs, log_output=False)

        metas = rattler_build_conda_compat.render.render(
            recipe_dir,
            variants=final_variant,
            config=config,
            finalize=False,
            bypass_env_check=True,
            **additional_config
        )
    else:
        metas = conda_build.api.render(
            recipe_dir,
            variant_config_files=variant,
            finalize=False,
            bypass_env_check=True,
            **additional_config
        )

    # Print the skipped distributions
    skipped_distributions = [m for m, _, _ in metas if m.skip()]
    for m in skipped_distributions:
        print("{} configuration was skipped in build/skip.".format(m.name()))

    subdirs = set([m.config.target_subdir for m, _, _ in metas if not m.skip()])
    subdirs |= set(["noarch"])  # always include noarch
    return set([m.name() for m, _, _ in metas if not m.skip()]), subdirs


def built_distributions(subdirs=()):
    "List conda artifacts in conda-build's root workspace"
    if not subdirs:
        subdirs = context.subdir, "noarch"
    paths = []
    for subdir in subdirs:
        for path in os.listdir(os.path.join(conda_build.config.croot, subdir)):
            if path.endswith((".tar.bz2", ".conda")):
                paths.append(os.path.join(conda_build.config.croot, subdir, path))
    return paths


def built_distributions_from_recipe_variant(recipe_dir=None, variant=None, build_tool=None):
    def _dist_name(dist):
        return split_pkg(os.path.relpath(dist, conda_build.config.croot))[1]

    allowed_dist_names, allowed_subdirs = get_built_distribution_names_and_subdirs(
        recipe_dir=recipe_dir,
        variant=variant,
        build_tool=build_tool,
    )
    return [
        dist
        for dist in built_distributions(subdirs=allowed_subdirs)
        if _dist_name(dist) in allowed_dist_names
    ]



def split_pkg(pkg):
    if pkg.endswith(".tar.bz2"):
        pkg = pkg[:-len(".tar.bz2")]
    elif pkg.endswith(".conda"):
        pkg = pkg[:-len(".conda")]
    else:
        raise RuntimeError("Can only process packages that end in .tar.bz2 or .conda!")
    plat, pkg_name = pkg.split(os.path.sep)
    name_ver, build = pkg_name.rsplit('-', 1)
    name, ver = name_ver.rsplit('-', 1)
    return plat, name, ver, build


def compute_sha256sum(pth):
    h = hashlib.sha256()

    with open(pth, 'rb') as fp:
        chunk = 0
        while chunk != b'':
            chunk = fp.read(1024)
            h.update(chunk)

    return h.hexdigest()

def human_readable_bytes(number):
    for unit in ['bytes', 'KB', 'MB', 'GB', 'TB']:
        if abs(number) < 1024.0:
            return f"{number:3.1f}{unit}"
        number /= 1024.0
    return f"{number:3.1f}{unit}"


def determine_build_tool(feedstock_root):
    build_tool = CONDA_BUILD

    if feedstock_root and os.path.exists(os.path.join(feedstock_root, "conda-forge.yml")):
        with open(os.path.join(feedstock_root, "conda-forge.yml")) as f:
            conda_forge_config = safe_load(f)

            if conda_forge_config.get("conda_build_tool", CONDA_BUILD) == RATTLER_BUILD:
                build_tool = RATTLER_BUILD

    return build_tool


def is_conda_forge_output_validation_on():
    feedstock_root = os.environ.get("FEEDSTOCK_ROOT", os.getcwd())
    ison = False
    if os.path.exists(os.path.join(feedstock_root, "conda-forge.yml")):
        with open(os.path.join(feedstock_root, "conda-forge.yml")) as f:
            conda_forge_config = safe_load(f)
            ison = conda_forge_config.get("conda_forge_output_validation", False)
    return ison
