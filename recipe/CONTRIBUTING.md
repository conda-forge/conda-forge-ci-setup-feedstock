# conda-forge-ci-setup contributing guidelines

## Adding a new OSX SDK

SDKs are listed in two files, each mapping a version to a URL, sha256 and
package kind. `download_osx_sdk.sh` prefers `cdn_sdks.json` and falls back to
`legacy_sdks.json` for versions it lacks or when a download fails.

- `cdn_sdks.json`: Command Line Tools packages on Apple's software update CDN.
  Regenerate it with `python recipe/discover_macos_sdks.py discover`, which
  rescans Apple's catalogs and downloads every SDK package (so takes a while);
  `python recipe/discover_macos_sdks.py list` summarises it. Existing entries
  are kept as long as they still download.
- `legacy_sdks.json`: `.sdk.tar.xz` tarballs from GitHub mirrors such as
  https://github.com/joseluisq/macosx-sdks; edit it by hand.
- `test_osx_sdk.sh` downloads every SDK in both files.
- Temporarily test it works:
    1. Define `MACOSX_SDK_VERSION` in `conda_build_config.yaml`; e.g. `MACOS_SDK_VERSION: ["26.1"] # [osx]`.
    2. Add a dummy variable using in it `meta.yaml`; e.g. `{% set _dummy = MACOSX_SDK_VERSION %}`.
    3. Pick `osx` and a single Python version, and skip the rest; e.g. `skip: true # [not (osx and py==313)]`
    4. Rerender and push the commits.
    5. When everything passes, revert steps 1-4 and rerender again so it's ready for review/merge.
