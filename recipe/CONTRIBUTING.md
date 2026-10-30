# conda-forge-ci-setup contributing guidelines

## Adding a new OSX SDK

SDKs are downloaded from Apple's software update CDN by `fetch_macos_sdk.py`,
which pins each package's URL and sha256.

- Run `python recipe/fetch_macos_sdk.py discover` to rescan Apple's catalogs; it
  rewrites the pin table at the top of the script. This downloads every SDK
  package so takes a while.
- Review the diff (`python recipe/fetch_macos_sdk.py list` summarises the pins)
  and commit it. `test_osx_sdk.sh` downloads every pinned SDK.
- If the newest SDK of a major version changed, update the fallback
  expectations in `test_osx_sdk_config.sh`.
- Temporarily test it works:
    1. Define `MACOSX_SDK_VERSION` in `conda_build_config.yaml`; e.g. `MACOS_SDK_VERSION: ["26.1"] # [osx]`.
    2. Add a dummy variable using in it `meta.yaml`; e.g. `{% set _dummy = MACOSX_SDK_VERSION %}`.
    3. Pick `osx` and a single Python version, and skip the rest; e.g. `skip: true # [not (osx and py==313)]`
    4. Rerender and push the commits.
    5. When everything passes, revert steps 1-4 and rerender again so it's ready for review/merge.
