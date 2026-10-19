#!/bin/bash
set -e

# Keep it in sync with the case block in download_osx_sdk.sh
versions=(
    "26"
    "26.1"
    "26.0"
    "15"
    "15.5"
    "15.4"
    "15.2"
    "15.1"
    "15.0"
    "14"
    "14.5"
    "14.4"
    "14.2"
    "14.0"
    "13"
    "13.3"
    "13.1"
    "13.0"
    "12"
    "12.3"
    "12.1"
    "12.0"
    "11"
    "11.3"
    "11.1"
    "11.0"
    "10.15"
    "10.14"
    "10.13"
    "10.12"
    "10.11"
    "10.10"
    "10.9"
)
export _CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS=1

# Run download_osx_sdk.sh for one version and check the SDK it settled on.
# CONFIG/CI_SUPPORT must be unset: in CI they point at this feedstock's own
# .ci_support file, whose (absent) MACOSX_SDK_VERSION would otherwise override
# the one under test and silently fall back to the deployment target.
run_sdk_script() {
  local version="$1" out rc=0
  export OSX_SDK_DIR=$(mktemp -d)
  out=$(MACOSX_SDK_VERSION="${version}" env -u CONFIG -u CI_SUPPORT \
        bash "${CONDA_PREFIX}/bin/download_osx_sdk.sh" 2>&1) || rc=$?
  # To test locally, use "recipe/download_osx_sdk.sh" above instead.
  echo "${out}"
  rm -rf "${OSX_SDK_DIR}"
  unset OSX_SDK_DIR
  if [[ ${rc} == 0 ]] && ! grep -Eq "^Found CONDA_BUILD_SYSROOT: .*/MacOSX${version//./\\.}\." <<< "${out}"; then
    echo "MACOSX_SDK_VERSION=${version} did not produce a MacOSX${version}* SDK"
    env | grep -E "^(MACOSX|CONFIG|CI_SUPPORT|OSX_SDK|CONDA_BUILD_SYSROOT|_CONDA_FORGE)" | sort
    OSX_SDK_DIR=$(mktemp -d) MACOSX_SDK_VERSION="${version}" env -u CONFIG -u CI_SUPPORT \
      bash -x "${CONDA_PREFIX}/bin/download_osx_sdk.sh" 2>&1 | head -40
    return 2
  fi
  return ${rc}
}

for version in "${versions[@]}"; do
  echo "Testing SDK download for $version ..."
  run_sdk_script "${version}"
  sleep 1
done

# SDKs without a pinned download come from the selected Xcode; test the one
# this runner's Xcode provides, unless it has a pinned download
xcode_version=$(python -c 'import json, sys; print(json.load(open(sys.argv[1]))["Version"])' \
  "$(xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/SDKSettings.json")
if [[ " ${versions[*]} " == *" ${xcode_version} "* ]]; then
  echo "Skipping SDK $xcode_version from the selected Xcode: it has a pinned download"
else
  echo "Testing SDK $xcode_version from the selected Xcode ..."
  run_sdk_script "${xcode_version}"
fi

# Unsupported or unavailable versions must fail loudly
for version in "27" "99.0"; do
  echo "Testing that SDK $version is rejected ..."
  if run_sdk_script "${version}"; then
    echo "MACOSX_SDK_VERSION=${version} should have failed"
    exit 1
  fi
done
unset _CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS
