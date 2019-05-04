
:: 2 cores available on Appveyor workers: https://www.appveyor.com/docs/build-environment/#build-vm-configurations
:: CPU_COUNT is passed through conda build: https://github.com/conda/conda-build/pull/1149
set CPU_COUNT=2

set PYTHONUNBUFFERED=1

conda.exe config --set show_channel_urls true
conda.exe config --set auto_update_conda false
conda.exe config --set add_pip_as_python_dependency false

call setup_x64

:: Set the conda-build working directory to a smaller path
if "%CONDA_BLD_PATH%" == "" (
    set "CONDA_BLD_PATH=C:\\bld\\"
)

echo >> .ci_support/%CONFIG%.yaml
echo CI: >> .ci_support/%CONFIG%.yaml
echo - %CI% .ci_support/%CONFIG%.yaml
echo >> .ci_support/%CONFIG%.yaml

cat .ci_support/%CONFIG%.yaml

echo set "CONDA_BLD_PATH=%CONDA_BLD_PATH%"         > "%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"
echo set "CPU_COUNT=%CPU_COUNT%"                  >> "%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"
echo set "PYTHONUNBUFFERED=%PYTHONUNBUFFERED%"    >> "%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"

conda.exe info
conda.exe config --show-sources
conda.exe list --show-channel-urls
