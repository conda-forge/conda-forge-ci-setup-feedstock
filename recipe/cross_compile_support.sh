BUILD_PLATFORM=$(conda info --json | jq -r .platform)

if [ -f .ci_support/${CONFIG}.yaml ]; then
    HOST_PLATFORM=$(cat .ci_support/${CONFIG}.yaml | shyaml get-value target_platform ${BUILD_PLATFORM})
fi

HOST_PLATFORM=${HOST_PLATFORM:-${BUILD_PLATFORM}}

if [[ "${HOST_PLATFORM}" != "${BUILD_PLATFORM}" ]]; then
    echo "export CONDA_BUILD_CROSS_COMPILATION=1"                 > "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
    export CONDA_BUILD_CROSS_COMPILATION=1
fi
