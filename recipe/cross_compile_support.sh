BUILD_PLATFORM=$(conda info --json | jq -r .platform)

if [[ ${BUILD_PLATFORM} == "linux-64" ]]; then
  export BUILD="x86_64-conda-linux-gnu"
  echo "export BUILD=\"${BUILD}\"" >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
elif [[ ${BUILD_PLATFORM} == "linux-ppc64le" ]]; then
  export BUILD="powerpc64le-conda-linux-gnu"
  echo "export BUILD=\"${BUILD}\"" >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
elif [[ ${BUILD_PLATFORM} == "linux-aarch64" ]]; then
  export BUILD="aarch64-conda-linux-gnu"
  echo "export BUILD=\"${BUILD}\"" >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
fi

if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
    HOST_PLATFORM=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value target_platform.0 ${BUILD_PLATFORM})
fi

HOST_PLATFORM=${HOST_PLATFORM:-${BUILD_PLATFORM}}

if [[ "${HOST_PLATFORM}" != "${BUILD_PLATFORM}" ]]; then
    echo "export CONDA_BUILD_CROSS_COMPILATION=1"                 >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
    export CONDA_BUILD_CROSS_COMPILATION=1
fi
