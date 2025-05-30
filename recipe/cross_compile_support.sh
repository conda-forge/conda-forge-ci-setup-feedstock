#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
BUILD_PLATFORM=$(conda info --json | jq -r .platform)

if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
    HOST_PLATFORM=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value target_platform.0 ${BUILD_PLATFORM})
    CUDA_COMPILER_VERSION=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value cuda_compiler_version.0 None)
    MICROARCH_LEVEL_NEEDED=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value microarch_level.0 1)
fi

# When compiling natively we use the docker image's glibc
# We do the same now when cross-compiling by creating a
# conda environment for host platform with the same glibc
# as the docker glibc.
# For eg: when cross compiling for linux-aarch64 in a
# docker image with linux-anvil-x86_64:alma9 image, we use
# glibc=2.28 for QEMU while still building the package for
# glib=2.17
DOCKER_GLIBC_VERSION=$(conda info --json | jq -r '.virtual_pkgs[] | select(.[0] == "__glibc")[1]')
GLIBC_VERSION=${DOCKER_GLIBC_VERSION:-2.17}

HOST_PLATFORM=${HOST_PLATFORM:-${BUILD_PLATFORM}}
CUDA_COMPILER_VERSION=${CUDA_COMPILER_VERSION:-None}

if [[ "${HOST_PLATFORM}" != "${BUILD_PLATFORM}" ]]; then
    echo "export CONDA_BUILD_CROSS_COMPILATION=1" >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
    export CONDA_BUILD_CROSS_COMPILATION=1
    if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
        echo "build_platform:"       >> ${CI_SUPPORT}/${CONFIG}.yaml
        echo "- ${BUILD_PLATFORM}"   >> ${CI_SUPPORT}/${CONFIG}.yaml
    fi
    if [[ "${BUILD_PLATFORM}" == "linux-64" && "${HOST_PLATFORM}" == linux-* ]]; then
        micromamba create -p /opt/conda/envs/sysroot_${HOST_PLATFORM} --root-prefix ~/.conda \
            --yes --quiet --override-channels --channel conda-forge --strict-channel-priority \
            sysroot_${HOST_PLATFORM}=${GLIBC_VERSION}
        HOST_PLATFORM_ARCH=${HOST_PLATFORM:6}
        if [[ -f ${RECIPE_ROOT}/yum_requirements.txt ]]; then
            cat ${RECIPE_ROOT}/yum_requirements.txt | while read pkg; do
                if [[ "${pkg}" != "#"* && "${pkg}" != "" ]]; then
                    micromamba install -p /opt/conda/envs/sysroot_${HOST_PLATFORM} --root-prefix ~/.conda \
                    --yes --quiet --override-channels --channel conda-forge --strict-channel-priority \
                    "${pkg}-conda-${HOST_PLATFORM_ARCH}" || true
                fi
            done
        fi
        export QEMU_LD_PREFIX=$(find /opt/conda/envs/sysroot_${HOST_PLATFORM} -name sysroot | head -1)
        if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
            echo "CMAKE_CROSSCOMPILING_EMULATOR: " >> ${CI_SUPPORT}/${CONFIG}.yaml
            echo "- /usr/bin/qemu-${HOST_PLATFORM_ARCH}-static"  >> ${CI_SUPPORT}/${CONFIG}.yaml
            echo "CROSSCOMPILING_EMULATOR: " >> ${CI_SUPPORT}/${CONFIG}.yaml
            echo "- /usr/bin/qemu-${HOST_PLATFORM_ARCH}-static"  >> ${CI_SUPPORT}/${CONFIG}.yaml
        fi
        /usr/bin/qemu-${HOST_PLATFORM_ARCH}-static --version


        if [[ "${CUDA_COMPILER_VERSION}" == "11.2" || "${CUDA_COMPILER_VERSION}" == "11.8" ]]; then
            EXTRACT_DIR=$(mktemp -d)
            pushd ${EXTRACT_DIR}
                if [[ "${HOST_PLATFORM_ARCH}" == "aarch64" ]]; then
                    CUDA_HOST_PLATFORM_ARCH=sbsa
                else
                    CUDA_HOST_PLATFORM_ARCH=${HOST_PLATFORM_ARCH}
                fi
                # download manifest for latest CUDA patch version
                CUDA_MANIFEST_VERSION=$(
                    case "${CUDA_COMPILER_VERSION}" in
                        ("11.2") echo "11.2.2" ;;
                        ("11.8") echo "11.8.0" ;;
                        (*) echo "" ;;
                    esac)
                if [[ "${CUDA_MANIFEST_VERSION}" == "" ]]; then
                    echo 'cross compiling with cuda not in (11.2, 11.8, 12.*) not supported yet'
                    exit 1
                fi
                curl -L https://developer.download.nvidia.com/compute/cuda/repos/rhel8/${CUDA_HOST_PLATFORM_ARCH}/version_${CUDA_MANIFEST_VERSION}.json > manifest.json
                # packages for which we also need to install the -devel version
                # (names need "_" not "-" to match spelling in manifest);
                # some packages don't have a key in the manifest, so we
                # need to do a mapping, in this case new_key:from_old;
                # also new_key needs "_" not "-" as jq stumbles otherwise,
                # will be mapped to "-" below for rpm-names anyway
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
                    "cuda_compat:nvidia_driver"
                )

                # Some packages are added after CUDA 11.2+.
                # Handle them seperately here.
                # Take version info from packages available in the manifest.
                if [[ "${CUDA_COMPILER_VERSION}" == "11.8" ]]; then
                    DEVELS+=(
                        "cuda_profiler_api:cuda_sanitizer_api"
                    )
                fi

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

                # map names from spelling in manifest to RPMs: remove quotes; normalize "_" -> "-";
                # also need to adapt "_dev" -> "-devel" (specifically for cuda_nvml_dev), which
                # in turn requires us to undo the "overshoot" for the other devel-packages
                sed 's/"//g' versions.txt | sed 's/_/-/g' | sed 's/sanitizer-api/sanitizer/g' | sed 's/-dev/-devel/g' | sed 's/-develel/-devel/g' > rpms.txt

                # filter packages from manifest down to what we need for cross-compilation
                grep -E "cuda-(cccl|compat|cudart|cupti|driver|nvcc|nvml|nvprof|nvrtc|nvtx|profiler).*|lib(cu|npp|nvjpeg).*" rpms.txt > rpms_cc.txt

                echo "Installing the following packages (<pkg>:<version>)"
                cat rpms_cc.txt

                # read names & versions for necessary RPMs; download & install them
                cat rpms_cc.txt | while read pv; do
                    pkg=$(echo $pv | cut -d ':' -f1)
                    ver=$(echo $pv | cut -d ':' -f2)
                    extra="${CUDA_COMPILER_VERSION/\./-}"
                    suffix="-1"

                    fn="${pkg}-${extra}-${ver}${suffix}.${HOST_PLATFORM_ARCH}.rpm"
                    echo "Downloading & installing: $fn"
                    curl -L -O https://developer.download.nvidia.com/compute/cuda/repos/rhel8/${CUDA_HOST_PLATFORM_ARCH}/${fn}
                    bsdtar -xvf ${fn}
                    rm ${fn}
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
        elif [[ "${CUDA_COMPILER_VERSION}" == 12* ]]; then
            # No extra steps necessary for CUDA 12, handled through new packages
            true
        elif [[ "${CUDA_COMPILER_VERSION}" != "None" ]]; then
            echo 'cross compiling with cuda not in (11.2, 11.8, 12.*) not supported yet'
            exit 1
        fi
    fi
fi

if [[ "${HOST_PLATFORM}" == "linux-64" && "${MICROARCH_LEVEL_NEEDED:-}" == "4" ]]; then
  MICROARCH_LEVEL=$(python ${SCRIPT_DIR}/get_x86_64_level.py)
  if [[ "$MICROARCH_LEVEL" != "4" ]]; then
    curl -L -O https://downloadmirror.intel.com/850782/sde-external-9.53.0-2025-03-16-lin.tar.xz
    mkdir -p ~/.sde
    tar -xf sde-external-9.53.0-2025-03-16-lin.tar.xz -C ~/.sde --strip-components=1
    echo "CROSSCOMPILING_EMULATOR:"                                               >> ${CI_SUPPORT}/${CONFIG}.yaml
    echo "- '$HOME/.sde/sde64 -cpuid_in $HOME/.sde/misc/cpuid/skx/cpuid.def -- '" >> ${CI_SUPPORT}/${CONFIG}.yaml
    echo "CMAKE_TEST_LAUNCHER:"                                                   >> ${CI_SUPPORT}/${CONFIG}.yaml
    echo "- '$HOME/.sde/sde64 -cpuid_in $HOME/.sde/misc/cpuid/skx/cpuid.def -- '" >> ${CI_SUPPORT}/${CONFIG}.yaml

    # TODO: figure out how to set this for only host environment and not build env
    export CONDA_OVERRIDE_ARCHSPEC=x86_64_v4
  fi
fi
