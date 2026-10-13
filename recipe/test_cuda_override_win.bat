@echo off
setlocal

:: Verify that CONDA_OVERRIDE_CUDA_ARCH is exported correctly by the shipped
:: run_conda_forge_build_setup script, both into the environment and into
:: the conda-forge-ci-setup-activate.bat activation script.

set "SETUP_SCRIPT=%PREFIX%\Scripts\run_conda_forge_build_setup.bat"

if not exist "%SETUP_SCRIPT%" (
    echo FAIL: %SETUP_SCRIPT% does not exist
    exit /b 1
)

:: .ci_support\test_cuda_override*.yaml are shipped fixture files (see
:: meta.yaml test.files), already in place in the test working directory.
call :check_case test_cuda_override 9.0
if errorlevel 1 exit /b 1
call :check_case test_cuda_override_default 999.0
if errorlevel 1 exit /b 1

echo All CONDA_OVERRIDE_CUDA_ARCH tests passed.
exit /b 0

:: Arguments: CONFIG name, expected CONDA_OVERRIDE_CUDA_ARCH
:check_case
set "CONFIG=%~1"
set "EXPECTED=%~2"
set "CONDA_OVERRIDE_CUDA_ARCH="
set "CONDA_OVERRIDE_CUDA="

echo === Running case %CONFIG% ===
:: Not gating on the script's own exit code: it also does unrelated
:: environment/network setup (conda config, driver detection, etc.) that
:: is out of scope for this check.
call "%SETUP_SCRIPT%"

if not "%CONDA_OVERRIDE_CUDA_ARCH%" == "%EXPECTED%" (
    echo FAIL: expected CONDA_OVERRIDE_CUDA_ARCH=%EXPECTED% but got "%CONDA_OVERRIDE_CUDA_ARCH%"
    exit /b 1
)

set "ACTIVATE_SCRIPT=%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"
if not exist "%ACTIVATE_SCRIPT%" (
    echo FAIL: activate script "%ACTIVATE_SCRIPT%" was not created
    exit /b 1
)

findstr /C:"set \"CONDA_OVERRIDE_CUDA_ARCH=%EXPECTED%\"" "%ACTIVATE_SCRIPT%" > nul
if errorlevel 1 (
    echo FAIL: activate script does not contain CONDA_OVERRIDE_CUDA_ARCH=%EXPECTED%
    type "%ACTIVATE_SCRIPT%"
    exit /b 1
)

echo PASS: case %CONFIG%
exit /b 0
