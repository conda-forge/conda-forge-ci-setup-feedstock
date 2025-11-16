#!/bin/bash
set -e

# Keep it in sync with the case block in download_osx_sdk.sh
versions=(
    "26"
    "15"
    "14"
    "13"
    "12"
    "11"
    "10.15"
    "10.14"
    "10.13"
    "10.12"
    "10.11"
    "10.10"
    "10.9"
)
export _CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS=1
for version in "${versions[@]}"; do
  echo "Testing SDK download for $version ..."
  export MACOSX_SDK_VERSION="${version}"
  export OSX_SDK_DIR=$(mktemp -d)
  bash "${CONDA_PREFIX}/bin/download_osx_sdk.sh"
  rm -rf $OSX_SDK_DIR
  rm "MacOSX${version}.sdk.tar.xz"
  unset MACOS_SDK_VERSION
  unset OSX_SDK_DIR
  sleep 1
done
unset _CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS
