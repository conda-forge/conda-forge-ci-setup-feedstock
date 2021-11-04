BUILD_PLATFORM=$(conda info --json | jq -r .platform)

if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
    HOST_PLATFORM=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value target_platform.0 ${BUILD_PLATFORM})
fi

HOST_PLATFORM=${HOST_PLATFORM:-${BUILD_PLATFORM}}

if [[ "${HOST_PLATFORM}" != "${BUILD_PLATFORM}" ]]; then
    echo "export CONDA_BUILD_CROSS_COMPILATION=1"                 >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
    export CONDA_BUILD_CROSS_COMPILATION=1
    if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
        echo "build_platform:"       >> ${CI_SUPPORT}/${CONFIG}.yaml
        echo "- ${BUILD_PLATFORM}"   >> ${CI_SUPPORT}/${CONFIG}.yaml
    fi
    if [[ "${BUILD_PLATFORM}" == "linux-64" && "${HOST_PLATFORM}" == linux-* ]]; then
        conda create -n sysroot_${HOST_PLATFORM} --yes --quiet sysroot_${HOST_PLATFORM}
        for pkg in $(cat ${CI_SUPPORT}/../recipe/yum_requirements.txt); do
            if [[ "${pkg}" != "#"* && "${pkg}" != "" ]]; then
                conda install "${pkg}-cos7-${HOST_PLATFORM:6}" -n sysroot_${HOST_PLATFORM} --yes --quiet || true
            fi
        done
        export QEMU_LD_PREFIX=$(find ${CONDA_PREFIX}/envs/sysroot_${HOST_PLATFORM} -name sysroot | head -1)
        if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
            echo "CMAKE_CROSSCOMPILING_EMULATOR: " >> ${CI_SUPPORT}/${CONFIG}.yaml
            echo "- /usr/bin/qemu-$(echo $HOST_PLATFORM | cut -b 7-)-static"  >> ${CI_SUPPORT}/${CONFIG}.yaml
            echo "CROSSCOMPILING_EMULATOR: " >> ${CI_SUPPORT}/${CONFIG}.yaml
            echo "- /usr/bin/qemu-$(echo $HOST_PLATFORM | cut -b 7-)-static"  >> ${CI_SUPPORT}/${CONFIG}.yaml
        fi
    fi
fi
