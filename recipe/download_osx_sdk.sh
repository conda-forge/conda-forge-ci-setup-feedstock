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

if [[ "$MACOSX_SDK_VERSION" == "11.0" ]]; then
    if [[ "$CI" == "travis" ]]; then
        export OSX_SDK_DIR_NEW=/Applications/Xcode-12.for.macOS.Universal.Apps.beta.2.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs
    elif [[ "$CI" == "azure" ]]; then
        export OSX_SDK_DIR_NEW=/Applications/Xcode_12.2.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs
        if [[ ! -d "${OSX_SDK_DIR_NEW}" ]]; then
            export OSX_SDK_DIR_NEW=/Applications/Xcode_12_beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs
        fi
    else
        export OSX_SDK_DIR_NEW=/
    fi
    if [[ ! -d "${OSX_SDK_DIR_NEW}/MacOSX${MACOSX_SDK_VERSION}.sdk" ]]; then
        tmpdir=$(mktemp -d)
        mkdir -p $tmpdir
        pushd $tmpdir
            curl -L -O https://github.com/alexey-lysiuk/macos-sdk/archive/0ecfb46da65f2f1fab77059ebb43de3ac7b0edad.tar.gz
            tar -xf 0ecfb46da65f2f1fab77059ebb43de3ac7b0edad.tar.gz
            mv macos-sdk-0ecfb46da65f2f1fab77059ebb43de3ac7b0edad/MacOSX11.0.sdk ${OSX_SDK_DIR}/
        popd
    else
        export OSX_SDK_DIR=${OSX_SDK_DIR_NEW}
    fi
fi

export CONDA_BUILD_SYSROOT="${OSX_SDK_DIR}/MacOSX${MACOSX_SDK_VERSION}.sdk"

if [[ ! -d ${CONDA_BUILD_SYSROOT} ]]; then
    echo "Downloading ${MACOSX_SDK_VERSION} sdk"
    curl -L -O https://github.com/phracker/MacOSX-SDKs/releases/download/10.15/MacOSX${MACOSX_SDK_VERSION}.sdk.tar.xz
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
