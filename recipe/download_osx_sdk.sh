if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
   export MACOSX_DEPLOYMENT_TARGET=$(cat .ci_support/${CONFIG}.yaml | shyaml get-value MACOSX_DEPLOYMENT_TARGET.0 10.9)
fi

export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-10.9}

if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
   export WITH_LATEST_OSX_SDK=$(cat .ci_support/${CONFIG}.yaml | shyaml get-value WITH_LATEST_OSX_SDK.0 0)
fi

if [[ "$WITH_LATEST_OSX_SDK" == "1" ]]; then
    # Typically, we want to build with the latest SDK, even though the deployment target may be older.
    # See: https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/cross_development/Configuring/configuring.html#//apple_ref/doc/uid/10000163i-CH1-SW1
    export MACOSX_SDK_VERSION=10.15
else
    export MACOSX_SDK_VERSION=$MACOSX_DEPLOYMENT_TARGET
fi

export CONDA_BUILD_SYSROOT="${OSX_SDK_DIR}/MacOSX${MACOSX_SDK_VERSION}.sdk"

if [[ ! -d ${CONDA_BUILD_SYSROOT} || "$OSX_FORCE_SDK_DOWNLOAD" == "1" ]]; then
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

echo "export CONDA_BUILD_SYSROOT='${CONDA_BUILD_SYSROOT}'"                 > "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
echo "export MACOSX_DEPLOYMENT_TARGET='${MACOSX_DEPLOYMENT_TARGET}'"      >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"

if [[ -d "${CONDA_BUILD_SYSROOT}" ]]; then
   echo "Found CONDA_BUILD_SYSROOT: ${CONDA_BUILD_SYSROOT}"
else
   echo "Missing CONDA_BUILD_SYSROOT: ${CONDA_BUILD_SYSROOT}"
   exit 1
fi
