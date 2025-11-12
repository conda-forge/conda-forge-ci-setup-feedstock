# conda-forge-ci-setup contributing guidelines

## Adding a new OSX SDK

Usually fetched from https://github.com/joseluisq/macosx-sdks.

- Add checksums to `download_osx_sdk.sh` and `test_osx_sdk.sh`. 
- Temporarily test it works:
    1. Define `MACOSX_SDK_VERSION` in `conda_build_config.yaml`; e.g. `MACOS_SDK_VERSION: ["26.1"] # [osx]`.
    2. Add a dummy variable using in it `meta.yaml`; e.g. `{% set _dummy = MACOSX_SDK_VERSION %}`.
    3. Pick `osx` and a single Python version and skip the rest; e.g. `skip: true # [not (osx and py=313)]`
    4. Patch `download_osx_sdk.sh` so the line `if [[ ! -d ${CONDA_BUILD_SYSROOT} ]]; then` is always true; e.g. `if [[ 1 == 1 ]]; then`.
    5. Rerender and push the commits.
    6. When everything passes, revert steps 1-4 and rerender again.
