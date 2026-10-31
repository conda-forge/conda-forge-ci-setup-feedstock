#!/bin/bash
set -e

# Download every SDK from each source in macosx_sdks_{cdn,legacy}.json.
# On Linux only check one small SDK from Apple's CDN, which exercises
# unpack_pkg.py instead of pkgutil.
tests=()
if [[ "$(uname)" == "Linux" ]]; then
  tests+=("cdn 10.12")
else
  for source in cdn legacy; do
    for version in $(jq -r '.sdks | keys[]' "${CONDA_PREFIX}/share/conda-forge-ci-setup/macosx_sdks_${source}.json"); do
      tests+=("${source} ${version}")
    done
  done
fi
export _CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS=1
for test in "${tests[@]}"; do
  read source version <<< "${test}"
  echo "Testing SDK download for $version from $source ..."
  export OSX_SDK_SOURCES="${source}"
  export MACOSX_SDK_VERSION="${version}"
  export OSX_SDK_DIR=$(mktemp -d)
  bash "${CONDA_PREFIX}/bin/download_osx_sdk.sh"
  # ensure we actually downloaded the right version
  test -d "$OSX_SDK_DIR/MacOSX${version}.sdk"
  test -f "$OSX_SDK_DIR/MacOSX${version}.sdk/SDKSettings.plist"
  # To test locally:
  # bash "recipe/download_osx_sdk.sh"
  rm -rf $OSX_SDK_DIR
  unset MACOSX_SDK_VERSION
  unset OSX_SDK_DIR
  sleep 1
done
unset _CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS OSX_SDK_SOURCES
