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
    export MACOSX_SDK_VERSION=$MACOSX_DEPLOYMENT_TARGET
fi

export CONDA_BUILD_SYSROOT="${OSX_SDK_DIR}/MacOSX${MACOSX_SDK_VERSION}.sdk"

if [[ ! -d ${CONDA_BUILD_SYSROOT} ]]; then
    echo "Downloading ${MACOSX_SDK_VERSION} sdk"

    if [[ $(echo "${MACOSX_SDK_VERSION}" | cut -d "." -f 1) -gt 11 ]]; then
        # We used to rely on `alexey-lysiuk/macos-sdk`, but this other repo has more versions
        url="https://github.com/joseluisq/macosx-sdks/releases/download/${MACOSX_SDK_VERSION}/MacOSX${MACOSX_SDK_VERSION}.sdk.tar.xz"
    else
        url="https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX${MACOSX_SDK_VERSION}.sdk.tar.xz"
    fi
    curl -L --output MacOSX${MACOSX_SDK_VERSION}.sdk.tar.xz "${url}"
    sdk_sha256=$(
        # IMPORTANT: When adding new versions, update test_osx_sdk.sh too!
        case "${MACOSX_SDK_VERSION}" in
            # https://github.com/joseluisq/macosx-sdks/blob/master/macosx_sdks.json:
            ("26.0") echo "07ccaa2891454713c3a230dd87283f76124193309d9a7617ebee45354c9302d2" ;;
            ("15.5") echo "c15cf0f3f17d714d1aa5a642da8e118db53d79429eb015771ba816aa7c6c1cbd" ;;
            ("15.4") echo "a0b7b66912ac0da0e45b304a332bacdbe58ca172220820d425edb28213962f81" ;;
            ("15.2") echo "b090a2bd6b0566616da8bdb9a88ab84e842fd3f44ff4be6a3d795a599d462a0e" ;;
            ("15.1") echo "8792422534fec12b7237bca3988ff1033fc73f718bb2751493778247b5bf0d2d" ;;
            ("15.0") echo "9df0293776fdc8a2060281faef929bf2fe1874c1f9368993e7a4ef87b1207f98" ;;
            ("14.5") echo "6e146275d19f027faa2e8354da5e0267513abf013b8f16ad65a231653a2b1c5d" ;;
            ("14.4") echo "5170364da96521a8cfeb4c7b8ffa810f82bd7494bd7a93653b6054101ac6cbe7" ;;
            ("14.2") echo "f8d1eef4657df91d3ea8a8ee810d3e14e0291032a64d6643e8add4c5155e6f60" ;;
            ("14.0") echo "5e4d3be6b445f0eacc0333ff2117e93e4433d8c4fe44053a14f735033a98aaa9" ;;
            ("13.3") echo "518e35eae6039b3f64e8025f4525c1c43786cc5cf39459d609852faf091e34be" ;;
            ("13.1") echo "efa167d0e463e40f9a3f3e95a2d4f265552834442872341d5669d3264ba9b702" ;;
            ("13.0") echo "6e9bd8683866afb310f538757744c606a924f5ba9baa71550ce337eb2695d1a2" ;;
            ("12.3") echo "3abd261ceb483c44295a6623fdffe5d44fc4ac2c872526576ec5ab5ad0f6e26c" ;;
            ("12.1") echo "a1a6d4340faa7d2744f1fc63b093226da90681288507446b98795a26a6ade4bb" ;;
            ("12.0") echo "ac07f28c09e6a3b09a1c01f1535ee71abe8017beaedd09181c8f08936a510ffd" ;;
            # https://github.com/phracker/MacOSX-SDKs/releases/tag/11.3:
            # Ran `openssl sha256` manually on the files there on 2024-04-02.
            ("11.3") echo "cd4f08a75577145b8f05245a2975f7c81401d75e9535dcffbb879ee1deefcbf4" ;;
            ("11.1") echo "68797baaacb52f56f713400de306a58a7ca00b05c3dc6d58f0a8283bcac721f8" ;;
            ("11.0") echo "d3feee3ef9c6016b526e1901013f264467bb927865a03422a9cb925991cc9783" ;;
            ("10.15") echo "ac75d9e0eb619881f5aa6240689fce862dcb8e123f710032b7409ff5f4c3d18b" ;;
            ("10.14") echo "123dcd2e02051bed8e189581f6eea1b04eddd55a80f98960214421404aa64b72" ;;
            ("10.13") echo "1d2984acab2900c73d076fbd40750035359ee1abe1a6c61eafcd218f68923a5a" ;;
            ("10.12") echo "b314704d85934481c9927a0450db1768baf9af9efe649562fcb1a503bb44512f" ;;
            ("10.11") echo "d080fc672d94f95eb54651c37ede80f61761ce4c91f87061e11a20222c8d00c8" ;;
            ("10.10") echo "3839b875df1f2bc98893b8502da456cc0b022c4666bc6b7eb5764a5f915a9b00" ;;
            ("10.9") echo "fcf88ce8ff0dd3248b97f4eb81c7909f2cc786725de277f4d05a2b935cc49de0" ;;
            (*) echo "Unknown version & hash, please update conda-forge-ci-setup's download_osx_sdk.sh" ;;
        esac)
    echo "${sdk_sha256} *MacOSX${MACOSX_SDK_VERSION}.sdk.tar.xz" | shasum -a 256 -c
    if [ "${_CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS:-0}" != "0" ]; then
        exit 0
    fi
    mkdir -p "$(dirname "$CONDA_BUILD_SYSROOT")"
    # delete symlink that may exist already, e.g. MacOSX15.5.sdk -> MacOSX.sdk
    rm -rf $CONDA_BUILD_SYSROOT
    tar -xf MacOSX${MACOSX_SDK_VERSION}.sdk.tar.xz -C "$(dirname "$CONDA_BUILD_SYSROOT")"
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
