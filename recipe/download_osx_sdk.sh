set -e

if [ -f ${CI_SUPPORT}/${CONFIG}.yaml ]; then
    csv=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value c_stdlib_version.0 "")
    mdt=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value MACOSX_DEPLOYMENT_TARGET.0 "")
    msv=$(cat ${CI_SUPPORT}/${CONFIG}.yaml | shyaml get-value MACOSX_SDK_VERSION.0 "")
    if [[ -n "${mdt}" && -z "${csv}" ]]; then
        echo "ERROR: config has MACOSX_DEPLOYMENT_TARGET but no c_stdlib_version."
        echo "       Add {{ stdlib('c') }} to the recipe and rerender."
        exit 1
    fi
fi

# Config values win, otherwise keep what the caller exported; except for the download tests here,
# which need MACOSX_SDK_VERSION from test_osx_sdk.sh regardless of what's in the variant configs.
# The fallback default follows c_stdlib_version for osx in conda-forge-pinning.
if [[ -z "${_CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS:-}" ]]; then
    export MACOSX_DEPLOYMENT_TARGET=${csv:-${MACOSX_DEPLOYMENT_TARGET:-11.0}}
    export MACOSX_SDK_VERSION=${msv:-${MACOSX_SDK_VERSION:-${MACOSX_DEPLOYMENT_TARGET}}}
fi

# SDK sources in order of preference: cdn_sdks.json (Apple's software update CDN,
# see discover_macos_sdks.py) and legacy_sdks.json (GitHub mirrors).
sdk_data_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sdk_sources=${OSX_SDK_SOURCES:-cdn legacy}
sdk_query() {
    jq -r --arg v "$2" "$3 // empty" "${sdk_data_dir}/$1_sdks.json"
}

# Exact versions first, then major-only versions like "15" (newest pinned minor)
actual_macosx_sdk_version=""
for src in ${sdk_sources}; do
    if [[ -n "$(sdk_query ${src} "${MACOSX_SDK_VERSION}" '.sdks[$v].url')" ]]; then
        actual_macosx_sdk_version=${MACOSX_SDK_VERSION}
        break
    fi
done
if [[ -z "${actual_macosx_sdk_version}" ]]; then
    for src in ${sdk_sources}; do
        actual_macosx_sdk_version=$(sdk_query ${src} "${MACOSX_SDK_VERSION}" '.aliases[$v]')
        if [[ -n "${actual_macosx_sdk_version}" ]]; then
            break
        fi
    done
fi
if [[ -z "${actual_macosx_sdk_version}" ]]; then
    echo "Unsupported SDK version (${MACOSX_SDK_VERSION}), please update conda-forge-ci-setup's cdn_sdks.json or legacy_sdks.json"
    exit 1
fi

# Download, verify and unpack the SDK from one source; returns non-zero so the next source can be tried
download_sdk() {
    local src=$1 url sha256 kind sdk tmp unpacked
    url=$(sdk_query ${src} "${actual_macosx_sdk_version}" '.sdks[$v].url')
    [[ -n "${url}" ]] || return 1
    sha256=$(sdk_query ${src} "${actual_macosx_sdk_version}" '.sdks[$v].sha256')
    kind=$(sdk_query ${src} "${actual_macosx_sdk_version}" '.sdks[$v].kind')
    sdk=$(sdk_query ${src} "${actual_macosx_sdk_version}" '.sdks[$v].sdk')

    tmp=$(mktemp -d "${sysroot_parent}/.download_osx_sdk.XXXXXX")
    echo "Downloading macOS ${actual_macosx_sdk_version} SDK from ${url}"
    curl -fL --retry 3 --output "${tmp}/sdk.${kind}" "${url}" \
        && echo "${sha256} *${tmp}/sdk.${kind}" | shasum -a 256 -c \
        || { rm -rf "${tmp}"; return 1; }

    case "${kind}" in
        (tar.xz)
            mkdir "${tmp}/out" && tar -xf "${tmp}/sdk.tar.xz" -C "${tmp}/out" \
                || { rm -rf "${tmp}"; return 1; }
            unpacked="${tmp}/out/${sdk}"
            ;;
        (pkg)
            if [[ "$(uname)" == "Darwin" ]]; then
                pkgutil --expand-full "${tmp}/sdk.pkg" "${tmp}/out" \
                    || { rm -rf "${tmp}"; return 1; }
                unpacked="${tmp}/out/Payload/Library/Developer/CommandLineTools/SDKs/${sdk}"
            else
                # unpack_pkg.py does the same as pkgutil, which only exists on macOS
                python "${sdk_data_dir}/unpack_pkg.py" "${tmp}/sdk.pkg" "${sdk}" "${tmp}/out/${sdk}" \
                    || { rm -rf "${tmp}"; return 1; }
                unpacked="${tmp}/out/${sdk}"
            fi
            ;;
        (*)
            echo "Unknown SDK package kind: ${kind}"
            rm -rf "${tmp}"
            return 1
            ;;
    esac

    # delete symlink that may exist already, e.g. MacOSX15.5.sdk -> MacOSX.sdk
    rm -rf "${CONDA_BUILD_SYSROOT}"
    mv "${unpacked}" "${CONDA_BUILD_SYSROOT}" || { rm -rf "${tmp}"; return 1; }
    rm -rf "${tmp}"
}

export CONDA_BUILD_SYSROOT="${OSX_SDK_DIR}/MacOSX${actual_macosx_sdk_version}.sdk"
if [[ ! -d ${CONDA_BUILD_SYSROOT} ]]; then
    sysroot_parent="$(dirname "$CONDA_BUILD_SYSROOT")"
    mkdir -p "$sysroot_parent"
    for src in ${sdk_sources}; do
        if download_sdk ${src}; then
            echo "unpacked SDK into ${sysroot_parent}:"
            ls ${sysroot_parent}
            break
        fi
    done
fi

if [[ -d "${CONDA_BUILD_SYSROOT}" ]]; then
   echo "Found CONDA_BUILD_SYSROOT: ${CONDA_BUILD_SYSROOT}"
else
   echo "Missing CONDA_BUILD_SYSROOT: ${CONDA_BUILD_SYSROOT}"
   exit 1
fi

if [[ -n "${_CONDA_FORGE_CI_SETUP_OSX_SDK_DOWNLOAD_TESTS:-}" || -n "${_CONDA_FORGE_CI_SETUP_OSX_SDK_CONFIG_TESTS:-}" ]]; then
    # files below are not writable during testing
    exit 0
fi

if [ ! -z "$CONFIG" ]; then
   echo "" >> ${CI_SUPPORT}/${CONFIG}.yaml
   echo "CONDA_BUILD_SYSROOT:" >> ${CI_SUPPORT}/${CONFIG}.yaml
   echo "- ${CONDA_BUILD_SYSROOT}" >> ${CI_SUPPORT}/${CONFIG}.yaml
   echo "" >> ${CI_SUPPORT}/${CONFIG}.yaml
fi

echo "export CONDA_BUILD_SYSROOT='${CONDA_BUILD_SYSROOT}'"                >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
echo "export MACOSX_DEPLOYMENT_TARGET='${MACOSX_DEPLOYMENT_TARGET}'"      >> "${CONDA_PREFIX}/etc/conda/activate.d/conda-forge-ci-setup-activate.sh"
