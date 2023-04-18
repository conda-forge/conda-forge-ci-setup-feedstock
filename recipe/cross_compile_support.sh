#!/bin/bash

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
    echo "export CONDA_BUILD_CROSS_COMPILATION=1" >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
    export CONDA_BUILD_CROSS_COMPILATION=1
    if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
        echo "build_platform:"       >> ${CI_SUPPORT}/${CONFIG}.yaml
        echo "- ${BUILD_PLATFORM}"   >> ${CI_SUPPORT}/${CONFIG}.yaml
    fi
    if [[ "${BUILD_PLATFORM}" == "linux-64" && "${HOST_PLATFORM}" == linux-* ]]; then
        mamba create -n sysroot_${HOST_PLATFORM} --yes --quiet sysroot_${HOST_PLATFORM}
        HOST_PLATFORM_ARCH=${HOST_PLATFORM:6}
        if [[ -f ${RECIPE_ROOT}/yum_requirements.txt ]]; then
            for pkg in $(cat ${RECIPE_ROOT}/yum_requirements.txt); do
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
                # download manifest for latest 11.2.x patch version
                curl -L https://developer.download.nvidia.com/compute/cuda/repos/rhel8/${CUDA_HOST_PLATFORM_ARCH}/version_11.2.2.json > manifest.json
                # packages for which we also need to install the -devel version
                # (names need "_" not "-" to match spelling in manifest);
                # some packages don't have a key in the manifest, so we
                # need to do a mapping, in this case new_key:from_old
                declare -a DEVELS=(
                    "cuda_cudart_devel:cuda_cudart"
                    "cuda_driver_devel:cuda_cudart"
                    "cuda_nvrtc_devel:cuda_nvrtc"
                    "libcublas_devel:libcublas"
                    "libcufft_devel:libcufft"
                    "libcurand_devel:libcurand"
                    "libcusolver_devel:libcusolver"
                    "libcusparse_devel:libcusparse"
                    "libnpp_devel:libnpp"
                    "libnvjpeg_devel:libnvjpeg"
                    "cuda-compat:nvidia_driver"
                )
                # add additional packages to manifest with same version (and formatting)
                # as for key "from_old" specified in the mapping above
                for map in "${DEVELS[@]}"; do
                    new_key=$(echo $map | cut -d ':' -f1)
                    from_old=$(echo $map | cut -d ':' -f2)
                    DEVELQUERY="${DEVELQUERY:+${DEVELQUERY} | }. += {${new_key}: {version: .${from_old}.version}}"
                done
                # update manifest.json with devel packages
                jq "${DEVELQUERY}" manifest.json > manifest_ext.json

                # collect as <pkg>:<ver> to avoid further json-parsing within loop
                jq 'keys[] as $k | "\($k):\(.[$k] | .version)"' manifest_ext.json > versions.txt

                # map names from spelling in manifest to RPMs:
                # remove quotes; normalize "_" -> "-"; remove "-api" suffix from cuda-sanitizer;
                # also need to adapt "_dev" -> "-devel" (specifically for cuda_nvml_dev), which
                # in turn requires us to undo the "overshoot" for the other devel-packages
                sed 's/"//g' versions.txt | sed 's/_/-/g' | sed 's/-api//g' | sed 's/-dev/-devel/g' | sed 's/-develel/-devel/g' > rpms.txt

                # filter packages from manifest down to what we need for cross-compilation
                grep -E "cuda-(compat|cudart|cupti|driver|nvcc|nvml|nvprof|nvrtc|nvtx).*|lib(cu|npp|nvjpeg).*" rpms.txt > rpms_cc.txt

                echo "Installing the following packages (<pkg>:<version>)"
                cat rpms_cc.txt

                # read names & versions for necessary RPMs; download & install them
                cat rpms_cc.txt | while read pv; do
                    pkg=$(echo $pv | cut -d ':' -f1)
                    ver=$(echo $pv | cut -d ':' -f2)
                    extra="11-2-"
                    suffix="-1"

                    fn="${pkg}-${extra}${ver}${suffix}.${HOST_PLATFORM_ARCH}.rpm"
                    echo "Downloading & installing: $fn"
                    curl -L -O https://developer.download.nvidia.com/compute/cuda/repos/rhel8/${CUDA_HOST_PLATFORM_ARCH}/${fn}
                    bsdtar -xvf ${fn}
                done
                # daisy-chain the copying because the docker images only have very specific combinations allowed, see
                # https://github.com/conda-forge/docker-images/blob/main/scripts/run_commands
                mkdir -p /opt/conda/targets/
                mv ./usr/local/cuda-${CUDA_COMPILER_VERSION}/targets/${CUDA_HOST_PLATFORM_ARCH}-linux /opt/conda/targets/${CUDA_HOST_PLATFORM_ARCH}-linux
                /usr/bin/sudo cp -r /opt/conda/targets/${CUDA_HOST_PLATFORM_ARCH}-linux ${CUDA_HOME}/targets/${CUDA_HOST_PLATFORM_ARCH}-linux

		# Need libcuda.so.1 in test phase to test the executables
		mv ./usr/local/cuda-${CUDA_COMPILER_VERSION}/compat/* ${QEMU_LD_PREFIX}/usr/lib/
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
