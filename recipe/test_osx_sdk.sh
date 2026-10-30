#!/bin/bash
set -e

# Every SDK pinned in fetch_macos_sdk.py; the fallbacks for versions that are
# not pinned are covered by test_osx_sdk_config.sh
versions=($(python "${CONDA_PREFIX}/bin/fetch_macos_sdk.py" list | awk '{print $1}'))
[[ ${#versions[@]} -gt 0 ]]
export _CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS=1
for version in "${versions[@]}"; do
  echo "Testing SDK download for $version ..."
  export MACOSX_SDK_VERSION="${version}"
  export OSX_SDK_DIR=$(mktemp -d)
  bash "${CONDA_PREFIX}/bin/download_osx_sdk.sh"
  # ensure we actually downloaded the right version
  test -d "$OSX_SDK_DIR/MacOSX${version}.sdk"
  # To test locally:
  # bash "recipe/download_osx_sdk.sh"
  rm -rf $OSX_SDK_DIR
  unset MACOS_SDK_VERSION
  unset OSX_SDK_DIR
  sleep 1
done
unset _CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS
