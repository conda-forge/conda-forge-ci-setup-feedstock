#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
BUILD_PLATFORM=${BUILD_PLATFORM:-$(conda info --json | jq -r .platform)}

if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
    HOST_PLATFORM=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value host_platform.0 None)
    TARGET_PLATFORM=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value target_platform.0 None)
    CUDA_COMPILER_VERSION=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value cuda_compiler_version.0 None)
    MICROARCH_LEVEL_NEEDED=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value microarch_level.0 1)
    if [ "${HOST_PLATFORM}" = "None" ]; then
      if [ "${TARGET_PLATFORM}" = "None" ]; then
        TARGET_PLATFORM=${BUILD_PLATFORM}
      fi
      HOST_PLATFORM=${TARGET_PLATFORM}
    elif [ "${TARGET_PLATFORM}" = "None" ]; then
      TARGET_PLATFORM=${HOST_PLATFORM}
    fi
else
    HOST_PLATFORM=${HOST_PLATFORM:-${BUILD_PLATFORM}}
    TARGET_PLATFORM=${TARGET_PLATFORM:-${BUILD_PLATFORM}}
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
                    "${pkg}-conda-${HOST_PLATFORM_ARCH}" sysroot_${HOST_PLATFORM}=${GLIBC_VERSION} || true
                fi
            done
        fi
        micromamba list -p /opt/conda/envs/sysroot_${HOST_PLATFORM}
        export QEMU_LD_PREFIX=$(find /opt/conda/envs/sysroot_${HOST_PLATFORM} -name sysroot | head -1)
        if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
            echo "CMAKE_CROSSCOMPILING_EMULATOR: " >> ${CI_SUPPORT}/${CONFIG}.yaml
            echo "- /usr/bin/qemu-${HOST_PLATFORM_ARCH}-static"  >> ${CI_SUPPORT}/${CONFIG}.yaml
            echo "CROSSCOMPILING_EMULATOR: " >> ${CI_SUPPORT}/${CONFIG}.yaml
            echo "- /usr/bin/qemu-${HOST_PLATFORM_ARCH}-static"  >> ${CI_SUPPORT}/${CONFIG}.yaml
        fi
        /usr/bin/qemu-${HOST_PLATFORM_ARCH}-static --version

        if [[ "${CUDA_COMPILER_VERSION}" = "None" ]] || [[ "${CUDA_COMPILER_VERSION:0:2}" -ge 12 ]]; then
          true;
        else
            echo "cross compiling with cuda "${CUDA_COMPILER_VERSION}" no longer supported. CUDA 12+ is required.";
            exit 1;
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
