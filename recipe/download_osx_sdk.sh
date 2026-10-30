set -e

if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
    csv=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value c_stdlib_version.0 "")
    mdt=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value MACOSX_DEPLOYMENT_TARGET.0 "")
    msv=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value MACOSX_SDK_VERSION.0 "")
    if [[ -n "${mdt}" && -z "${csv}" ]]; then
        echo "ERROR: config has MACOSX_DEPLOYMENT_TARGET but no c_stdlib_version."
        echo "       Add {{ stdlib('c') }} to the recipe and rerender."
        exit 1
    fi
fi

# Config values win, otherwise keep what the caller exported; except for the download tests here,
# which need MACOSX_SDK_VERSION from test_osx_sdk.sh regardless of what's in the variant configs.
# The fallback default follows c_stdlib_version for osx in conda-forge-pinning.
if [[ -z "${_CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS:-}" ]]; then
    export MACOSX_DEPLOYMENT_TARGET=${csv:-${MACOSX_DEPLOYMENT_TARGET:-11.0}}
    export MACOSX_SDK_VERSION=${msv:-${MACOSX_SDK_VERSION:-${MACOSX_DEPLOYMENT_TARGET}}}
fi

# SDKs older than 10.13 are not available from Apple any more
if [[ "${MACOSX_SDK_VERSION}" =~ ^10\.([0-9]|1[01])(\.|$) ]]; then
    echo "WARNING: macOS ${MACOSX_SDK_VERSION} SDK is not available, using 10.13 instead"
    export MACOSX_SDK_VERSION=10.13
fi

# Pinned SDKs from Apple's software update CDN; versions that are not pinned
# fall back to the newest pinned SDK of the same major version
CONDA_BUILD_SYSROOT=$(python "$(dirname "${BASH_SOURCE[0]}")/fetch_macos_sdk.py" fetch "${MACOSX_SDK_VERSION}" --dest "${OSX_SDK_DIR}")
export CONDA_BUILD_SYSROOT

if [[ -d "${CONDA_BUILD_SYSROOT}" ]]; then
   echo "Found CONDA_BUILD_SYSROOT: ${CONDA_BUILD_SYSROOT}"
else
   echo "Missing CONDA_BUILD_SYSROOT: ${CONDA_BUILD_SYSROOT}"
   exit 1
fi

if [[ -n "${_CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS:-}" || -n "${_CONDA_FORGE_CI_SETUP_OSX_SDK_CONFIG_TESTS:-}" ]]; then
    # files below are not writable during testing
    exit 0
fi

if [ ! -z "$CONFIG" ]; then
   echo "" >> ${CI_SUPPORT}/${CONFIG}.yaml
   echo "CONDA_BUILD_SYSROOT:" >> ${CI_SUPPORT}/${CONFIG}.yaml
   echo "- ${CONDA_BUILD_SYSROOT}" >> ${CI_SUPPORT}/${CONFIG}.yaml
   echo "" >> ${CI_SUPPORT}/${CONFIG}.yaml
fi

echo "export CONDA_BUILD_SYSROOT='${CONDA_BUILD_SYSROOT}'"                >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
echo "export MACOSX_DEPLOYMENT_TARGET='${MACOSX_DEPLOYMENT_TARGET}'"      >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
