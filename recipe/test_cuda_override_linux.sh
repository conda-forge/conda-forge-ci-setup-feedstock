#!/bin/bash
# Verify that CONDA_OVERRIDE_CUDA_ARCH is exported correctly by the shipped
# run_conda_forge_build_setup script, both into the environment and into
# the conda-forge-ci-setup-activate.sh activation script.

SETUP_SCRIPT="${PREFIX}/bin/run_conda_forge_build_setup"

if [ ! -f "${SETUP_SCRIPT}" ]; then
    echo "FAIL: ${SETUP_SCRIPT} does not exist"
    exit 1
fi

# .ci_support/test_cuda_override*.yaml are shipped fixture files (see
# meta.yaml test.files), already in place in the test working directory.
export CI_SUPPORT="$(pwd)/.ci_support"

# Arguments: CONFIG name, expected CONDA_OVERRIDE_CUDA_ARCH
check_case() {
    export CONFIG="$1"
    local expected="$2"
    unset CONDA_OVERRIDE_CUDA_ARCH CONDA_OVERRIDE_CUDA 2>/dev/null

    echo "=== Running case ${CONFIG} ==="
    # Not gating on the script's own exit code: it also does unrelated
    # environment/network setup (conda config, driver detection, etc.) that
    # is out of scope for this check.
    #
    # Deliberately not run under `set -u`/`set -e`: `source`-ing the script
    # below would leak `set -u` into it before its own `set +u`/`set -u`
    # toggling takes effect, and it references optional CI-only variables
    # (e.g. FEEDSTOCK_ROOT) unguarded early on. It also leaves `set -u`
    # enabled afterwards, so every variable below is expanded with a ':-'
    # default, and it is disabled again before sourcing for the next case.
    set +u
    # shellcheck disable=SC1090
    source "${SETUP_SCRIPT}"

    if [ "${CONDA_OVERRIDE_CUDA_ARCH:-}" != "${expected}" ]; then
        echo "FAIL: expected CONDA_OVERRIDE_CUDA_ARCH=${expected} but got '${CONDA_OVERRIDE_CUDA_ARCH:-}'"
        exit 1
    fi

    ACTIVATE_SCRIPT="${CONDA_PREFIX:-}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
    if [ ! -f "${ACTIVATE_SCRIPT}" ]; then
        echo "FAIL: activate script ${ACTIVATE_SCRIPT} was not created"
        exit 1
    fi

    if ! grep -qF "export CONDA_OVERRIDE_CUDA_ARCH='${expected}'" "${ACTIVATE_SCRIPT}"; then
        echo "FAIL: activate script does not contain CONDA_OVERRIDE_CUDA_ARCH=${expected}"
        cat "${ACTIVATE_SCRIPT}"
        exit 1
    fi

    echo "PASS: case ${CONFIG}"
}

check_case test_cuda_override 9.0
check_case test_cuda_override_default 999.0

echo "All CONDA_OVERRIDE_CUDA_ARCH tests passed."
