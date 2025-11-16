set -e

# We don't change the default here to a newer SDK to ensure that old, non-rerendered feedstock keep working.
if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
   export MACOSX_DEPLOYMENT_TARGET=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value MACOSX_DEPLOYMENT_TARGET.0 10.9)
fi

export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-10.9}

# Some project require a new SDK version even though they can target older versions
if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
    export MACOSX_SDK_VERSION=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value MACOSX_SDK_VERSION.0 0)
    export WITH_LATEST_OSX_SDK=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value WITH_LATEST_OSX_SDK.0 0)
    if [[ "${WITH_LATEST_OSX_SDK}" != "0" ]]; then
        echo "Setting WITH_LATEST_OSX_SDK is removed. Use MACOSX_SDK_VERSION to specify an explicit version for the SDK."
        export MACOSX_SDK_VERSION=10.15
    fi
fi

if [[ "${MACOSX_SDK_VERSION:-0}" == "0" ]]; then
    export MACOSX_SDK_VERSION="$MACOSX_DEPLOYMENT_TARGET"
fi

if [[ $(echo "${MACOSX_SDK_VERSION}" | cut -d "." -f 1) -ge 11 ]]; then
    # From v11 onwards, we only support the last minor release in each major series,
    # which is equivalent to patch releases in the 10.x series.
    actual_macosx_sdk_version=$(
        case "${MACOSX_SDK_VERSION}" in
            (26|26.*) echo "26.0" ;;
            (15|15.*) echo "15.5" ;;
            (14|14.*) echo "14.5" ;;
            (13|13.*) echo "13.3" ;;
            (12|12.*) echo "12.3" ;;
            (11|11.*) echo "11.3" ;;
            (*) echo "Unsupported SDK version (${MACOSX_SDK_VERSION}), please update conda-forge-ci-setup's download_osx_sdk.sh" ;;
        esac
    )
    # We used to rely on `alexey-lysiuk/macos-sdk`, but this other repo has more versions
    sdk_dl_url="https://github.com/joseluisq/macosx-sdks/releases/download/${actual_macosx_sdk_version}/MacOSX${actual_macosx_sdk_version}.sdk.tar.xz"
else
    actual_macosx_sdk_version="${MACOSX_SDK_VERSION}"
    sdk_dl_url="https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX${actual_macosx_sdk_version}.sdk.tar.xz"
fi

export CONDA_BUILD_SYSROOT="${OSX_SDK_DIR}/MacOSX${actual_macosx_sdk_version}.sdk"
if [[ ! -d ${CONDA_BUILD_SYSROOT} ]]; then
    echo "Downloading macOS ${MACOSX_SDK_VERSION} SDK from ${sdk_dl_url}"
    curl -L --output "MacOSX${actual_macosx_sdk_version}.sdk.tar.xz" "${sdk_dl_url}"
    sdk_sha256=$(
        # IMPORTANT: When adding new versions, update test_osx_sdk.sh too!
        case "${actual_macosx_sdk_version}" in
            # https://github.com/joseluisq/macosx-sdks/blob/master/macosx_sdks.json:
            ("26.0") echo "07ccaa2891454713c3a230dd87283f76124193309d9a7617ebee45354c9302d2" ;;
            ("15.5") echo "c15cf0f3f17d714d1aa5a642da8e118db53d79429eb015771ba816aa7c6c1cbd" ;;
            ("14.5") echo "6e146275d19f027faa2e8354da5e0267513abf013b8f16ad65a231653a2b1c5d" ;;
            ("13.3") echo "518e35eae6039b3f64e8025f4525c1c43786cc5cf39459d609852faf091e34be" ;;
            ("12.3") echo "3abd261ceb483c44295a6623fdffe5d44fc4ac2c872526576ec5ab5ad0f6e26c" ;;
            ("11.3") echo "9adc1373d3879e1973d28ad9f17c9051b02931674a3ec2a2498128989ece2cb1" ;;
            # https://github.com/phracker/MacOSX-SDKs/releases/tag/11.3:
            # Ran `openssl sha256` manually on the files there on 2024-04-02.
            ("10.15") echo "ac75d9e0eb619881f5aa6240689fce862dcb8e123f710032b7409ff5f4c3d18b" ;;
            ("10.14") echo "123dcd2e02051bed8e189581f6eea1b04eddd55a80f98960214421404aa64b72" ;;
            ("10.13") echo "1d2984acab2900c73d076fbd40750035359ee1abe1a6c61eafcd218f68923a5a" ;;
            ("10.12") echo "b314704d85934481c9927a0450db1768baf9af9efe649562fcb1a503bb44512f" ;;
            ("10.11") echo "d080fc672d94f95eb54651c37ede80f61761ce4c91f87061e11a20222c8d00c8" ;;
            ("10.10") echo "3839b875df1f2bc98893b8502da456cc0b022c4666bc6b7eb5764a5f915a9b00" ;;
            ("10.9") echo "fcf88ce8ff0dd3248b97f4eb81c7909f2cc786725de277f4d05a2b935cc49de0" ;;
            (*) echo "Unknown version & hash, please update conda-forge-ci-setup's download_osx_sdk.sh" ;;
        esac)
    echo "${sdk_sha256} *MacOSX${actual_macosx_sdk_version}.sdk.tar.xz" | shasum -a 256 -c
    if [ "${_CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS:-0}" != "0" ]; then
        rm "MacOSX${actual_macosx_sdk_version}"*".sdk.tar.xz"
        exit 0
    fi
    sysroot_parent="$(dirname "$CONDA_BUILD_SYSROOT")"
    mkdir -p "$sysroot_parent"
    # delete symlink that may exist already, e.g. MacOSX15.5.sdk -> MacOSX.sdk
    rm -rf "$CONDA_BUILD_SYSROOT"
    tar -xf MacOSX${actual_macosx_sdk_version}.sdk.tar.xz -C "$sysroot_parent"
fi

if [ ! -z "$CONFIG" ]; then
   echo "" >> ${CI_SUPPORT}/${CONFIG}.yaml
   echo "CONDA_BUILD_SYSROOT:" >> ${CI_SUPPORT}/${CONFIG}.yaml
   echo "- ${CONDA_BUILD_SYSROOT}" >> ${CI_SUPPORT}/${CONFIG}.yaml
   echo "" >> ${CI_SUPPORT}/${CONFIG}.yaml
fi

echo "export CONDA_BUILD_SYSROOT='${CONDA_BUILD_SYSROOT}'"                >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
echo "export MACOSX_DEPLOYMENT_TARGET='${MACOSX_DEPLOYMENT_TARGET}'"      >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"

if [[ -d "${CONDA_BUILD_SYSROOT}" ]]; then
   echo "Found CONDA_BUILD_SYSROOT: ${CONDA_BUILD_SYSROOT}"
else
   echo "Missing CONDA_BUILD_SYSROOT: ${CONDA_BUILD_SYSROOT}"
   exit 1
fi
