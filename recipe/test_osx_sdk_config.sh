#!/bin/bash
# Check how download_osx_sdk.sh picks MACOSX_DEPLOYMENT_TARGET and
# MACOSX_SDK_VERSION from the CI config and the environment. Nothing is
# downloaded: the expected SDK directory is pre-created and curl is stubbed
# to fail, so a wrong version shows up as a failed case.

SCRIPT="${DOWNLOAD_OSX_SDK:-${PREFIX}/bin/download_osx_sdk.sh}"

# .ci_support/test_osx_sdk_*.yaml are shipped fixture files (see meta.yaml
# test.files), already in place in the test working directory.
CI_SUPPORT_DIR="$(pwd)/.ci_support"

stub_dir=$(mktemp -d)
printf '#!/bin/sh\necho "curl stub: unexpected SDK download" >&2\nexit 1\n' > "${stub_dir}/curl"
chmod +x "${stub_dir}/curl"

failures=0

# Arguments: CONFIG name (empty for none), expected SDK version or "error",
# then optional NAME=VALUE environment assignments.
check_case() {
    local config="$1"
    local expected="$2"
    shift 2
    local sdk_dir out rc
    sdk_dir=$(mktemp -d)
    if [[ "${expected}" != "error" ]]; then
        mkdir -p "${sdk_dir}/MacOSX${expected}.sdk"
    fi

    echo "=== CONFIG='${config}' $* (expect ${expected}) ==="
    out=$(env -u MACOSX_DEPLOYMENT_TARGET -u MACOSX_SDK_VERSION \
        PATH="${stub_dir}:${PATH}" \
        CI_SUPPORT="${CI_SUPPORT_DIR}" \
        CONFIG="${config}" \
        OSX_SDK_DIR="${sdk_dir}" \
        _CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS=1 \
        "$@" bash "${SCRIPT}" 2>&1)
    rc=$?
    echo "${out}"

    if [[ "${expected}" == "error" ]]; then
        if [[ ${rc} -ne 0 && "${out}" == *"but no c_stdlib_version"* ]]; then
            echo "PASS"
        else
            echo "FAIL: expected the c_stdlib_version error, got rc=${rc}"
            failures=$((failures + 1))
        fi
    elif [[ ${rc} -eq 0 && "${out}" == *"Found CONDA_BUILD_SYSROOT: ${sdk_dir}/MacOSX${expected}.sdk"* ]]; then
        echo "PASS"
    else
        echo "FAIL: expected MacOSX${expected}.sdk, got rc=${rc}"
        failures=$((failures + 1))
    fi
    rm -rf "${sdk_dir}"
}

# Config with c_stdlib_version and no MACOSX_SDK_VERSION (current pinning,
# staged-recipes): the SDK follows c_stdlib_version.
check_case test_osx_sdk_stdlib 11.0
# An explicit MACOSX_SDK_VERSION in the config wins.
check_case test_osx_sdk_pinned 13.3
# MACOSX_DEPLOYMENT_TARGET without c_stdlib_version is OK.
check_case test_osx_sdk_mdt_only 11.0
# MACOSX_DEPLOYMENT_TARGET without c_stdlib_version but with a compiler_version errors.
check_case test_osx_sdk_mdt_and_compiler_version error
# No config: an exported MACOSX_SDK_VERSION is kept (test_osx_sdk.sh relies on this).
check_case "" 14.5 MACOSX_SDK_VERSION=14.5
# No config and nothing exported: the 10.9 default.
check_case "" 10.9

rm -rf "${stub_dir}"
if [[ ${failures} -ne 0 ]]; then
    echo "${failures} case(s) failed"
    exit 1
fi
echo "All download_osx_sdk.sh config tests passed."
