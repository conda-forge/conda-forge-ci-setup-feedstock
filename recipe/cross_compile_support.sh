BUILD_PLATFORM=$(conda info --json | jq -r .platform)

if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
    HOST_PLATFORM=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value target_platform.0 ${BUILD_PLATFORM})
    CUDA_COMPILER_VERSION=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value cuda_compiler_version.0 None)
    CDT_NAME=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value cdt_name.0 cos6)
fi

HOST_PLATFORM=${HOST_PLATFORM:-${BUILD_PLATFORM}}
CUDA_COMPILER_VERSION=${CUDA_COMPILER_VERSION:-None}
CDT_NAME=${CDT_NAME:-cos6}

if [[ "${HOST_PLATFORM}" != "${BUILD_PLATFORM}" ]]; then
    echo "export CONDA_BUILD_CROSS_COMPILATION=1"                 >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
    export CONDA_BUILD_CROSS_COMPILATION=1
    if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
        echo "build_platform:"       >> ${CI_SUPPORT}/${CONFIG}.yaml
        echo "- ${BUILD_PLATFORM}"   >> ${CI_SUPPORT}/${CONFIG}.yaml
    fi
    if [[ "${BUILD_PLATFORM}" == "linux-64" && "${HOST_PLATFORM}" == linux-* ]]; then
        mamba create -n sysroot_${HOST_PLATFORM} --yes --quiet sysroot_${HOST_PLATFORM}
        HOST_PLATFORM_ARCH=${HOST_PLATFORM:6}
        if [[ -f ${CI_SUPPORT}/../recipe/yum_requirements.txt ]]; then
            for pkg in $(cat ${CI_SUPPORT}/../recipe/yum_requirements.txt); do
                if [[ "${pkg}" != "#"* && "${pkg}" != "" ]]; then
                    mamba install "${pkg}-cos7-${HOST_PLATFORM_ARCH}" -n sysroot_${HOST_PLATFORM} --yes --quiet || true
                fi
            done
        fi
        export QEMU_LD_PREFIX=$(find ${CONDA_PREFIX}/envs/sysroot_${HOST_PLATFORM} -name sysroot | head -1)
        if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
            echo "CMAKE_CROSSCOMPILING_EMULATOR: " >> ${CI_SUPPORT}/${CONFIG}.yaml
            echo "- /usr/bin/qemu-${HOST_PLATFORM_ARCH}-static"  >> ${CI_SUPPORT}/${CONFIG}.yaml
            echo "CROSSCOMPILING_EMULATOR: " >> ${CI_SUPPORT}/${CONFIG}.yaml
            echo "- /usr/bin/qemu-${HOST_PLATFORM_ARCH}-static"  >> ${CI_SUPPORT}/${CONFIG}.yaml
        fi


        if [[ "${CUDA_COMPILER_VERSION}" == "11.2" ]] && [[ "${CDT_NAME}" == "cos8" || "${CDT_NAME}" == "cos7" ]]; then
            # We use cdt_name=cos7 for rhel8 based nvcc till we figure out
            # a stable cos8 replacement.
            EXTRACT_DIR=$(mktemp -d)
            pushd ${EXTRACT_DIR}
                if [[ "${HOST_PLATFORM_ARCH}" == "aarch64" ]]; then
                    CUDA_HOST_PLATFORM_ARCH=sbsa
                else
                    CUDA_HOST_PLATFORM_ARCH=${HOST_PLATFORM_ARCH}
                fi
                for f in cuda-cudart-11-2-11.2.72-1 \
                        cuda-cudart-devel-11-2-11.2.72-1\
                        cuda-cupti-11-2-11.2.152-1 \
                        cuda-driver-devel-11-2-11.2.152-1 \
                        cuda-nvcc-11-2-11.2.152-1 \
                        cuda-nvml-devel-11-2-11.2.67-1 \
                        cuda-nvprof-11-2-11.2.67-1 \
                        cuda-nvrtc-11-2-11.2.152-1 \
                        cuda-nvrtc-devel-11-2-11.2.152-1 \
                        cuda-nvtx-11-2-11.2.67-1 \
                        libcublas-11-2-11.3.1.68-1 \
                        libcublas-devel-11-2-11.3.1.68-1 \
                        libcufft-11-2-10.4.1.152-1 \
                        libcufft-devel-11-2-10.4.1.152-1 \
                        libcurand-11-2-10.2.3.152-1 \
                        libcurand-devel-11-2-10.2.3.152-1 \
                        libcusolver-11-2-11.1.0.152-1 \
                        libcusolver-devel-11-2-11.1.0.152-1 \
                        libcusparse-11-2-11.4.1.1152-1 \
                        libcusparse-devel-11-2-11.4.1.1152-1 \
                        libnpp-11-2-11.2.1.68-1 \
                        libnpp-devel-11-2-11.2.1.68-1 \
                        libnvjpeg-11-2-11.4.0.152-1 \
                        libnvjpeg-devel-11-2-11.4.0.152-1 ; do
                    curl -L -O https://developer.download.nvidia.com/compute/cuda/repos/rhel8/${CUDA_HOST_PLATFORM_ARCH}/${f}.${HOST_PLATFORM_ARCH}.rpm
                    bsdtar -xvf ${f}.${HOST_PLATFORM_ARCH}.rpm
                done
                mv ./usr/local/cuda-${CUDA_COMPILER_VERSION}/targets/${CUDA_HOST_PLATFORM_ARCH}-linux ${CUDA_HOME}/targets/${CUDA_HOST_PLATFORM_ARCH}-linux
            popd
            rm -rf ${EXTRACT_DIR}
        elif [[ "${CUDA_COMPILER_VERSION}" == "11.2" ]]; then
	    echo "cross compiling with cuda == 11.2 and cdt != cos7/8 not supported yet"
	    exit 1
        elif [[ "${CUDA_COMPILER_VERSION}" != "None" ]]; then
	    # FIXME: can use anaconda.org/nvidia packages to get the includes and libs
	    # for cuda >=11.3.
	    echo "cross compiling with cuda != 11.2 not supported yet"
	    exit 1
        fi
    fi
fi
