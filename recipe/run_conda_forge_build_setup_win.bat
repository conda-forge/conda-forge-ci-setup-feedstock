
:: 2 cores available on Appveyor workers: https://www.appveyor.com/docs/build-environment/#build-vm-configurations
:: CPU_COUNT is passed through conda build: https://github.com/conda/conda-build/pull/1149
set CPU_COUNT=2

set PYTHONUNBUFFERED=1

conda.exe config --set show_channel_urls true
conda.exe config --set auto_update_conda false
conda.exe config --set add_pip_as_python_dependency false
:: Otherwise packages that don't explicitly pin openssl in their requirements
:: are forced to the newest OpenSSL version, even if their dependencies don't
:: support it.
conda.exe config --env --append aggressive_update_packages ca-certificates
conda.exe config --env --remove-key aggressive_update_packages
conda.exe config --env --append aggressive_update_packages ca-certificates
conda.exe config --env --append aggressive_update_packages certifi

(type conda-forge.yml | shyaml get-value channel_priority strict || echo strict) > tmpFile
set /p channel_priority= < tmpFile
del tmpFile
conda.exe config --set channel_priority %channel_priority%

:: Set the conda-build working directory to a smaller path
if "%CONDA_BLD_PATH%" == "" (
    set "CONDA_BLD_PATH=C:\\bld\\"
)

:: Increase pagefile size, cf. https://github.com/conda-forge/conda-forge-ci-setup-feedstock/issues/155
:: Both in the recipe and in the final package, this script is co-located with SetPageFileSize.ps1, see meta.yaml
set ThisScriptsDirectory=%~dp0
set EntryPointPath=%ThisScriptsDirectory%SetPageFileSize.ps1
:: Only run if SET_PAGEFILE is set; EntryPointPath needs to be set outside if-condition when not using EnableDelayedExpansion.
if "%SET_PAGEFILE%" NEQ "" (
    if "%CI%" == "azure" (
        REM use different drive than CONDA_BLD_PATH-location for pagefile
        if "%CONDA_BLD_PATH%" == "C:\\bld\\" (
            echo CONDA_BLD_PATH=%CONDA_BLD_PATH%; Setting pagefile size to 16GB on D:
            REM Inspired by:
            REM https://blog.danskingdom.com/allow-others-to-run-your-powershell-scripts-from-a-batch-file-they-will-love-you-for-it/
            REM Drive-letter needs to be escaped in quotes
            PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& '%EntryPointPath%' -MinimumSize 8GB -MaximumSize 16GB -DiskRoot \"D:\""
        )
        if "%CONDA_BLD_PATH%" == "D:\\bld\\" (
            echo CONDA_BLD_PATH=%CONDA_BLD_PATH%; Setting pagefile size to 16GB on C:
            PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& '%EntryPointPath%' -MinimumSize 8GB -MaximumSize 16GB -DiskRoot \"C:\""
        )
    )
)

call conda activate base

if "%CI%" == "" (
    echo "Not running on CI"
) else (
    echo CI:    >> .ci_support\%CONFIG%.yaml
    echo - %CI% >> .ci_support\%CONFIG%.yaml
)

:: Remove some directories from PATH
set "PATH=%PATH:C:\ProgramData\Chocolatey\bin;=%"
set "PATH=%PATH:C:\Program Files (x86)\sbt\bin;=%"
set "PATH=%PATH:C:\Rust\.cargo\bin;=%"
set "PATH=%PATH:C:\Program Files\Git\usr\bin;=%"
set "PATH=%PATH:C:\Program Files\Git\cmd;=%"
set "PATH=%PATH:C:\Program Files\Git\mingw64\bin;=%"
set "PATH=%PATH:C:\Program Files (x86)\Subversion\bin;=%"
set "PATH=%PATH:C:\Program Files\CMake\bin;=%"
set "PATH=%PATH:C:\Program Files\OpenSSL\bin;=%"
set "PATH=%PATH:C:\Strawberry\c\bin;=%"
set "PATH=%PATH:C:\Strawberry\perl\bin;=%"
set "PATH=%PATH:C:\Strawberry\perl\site\bin;=%"
set "PATH=%PATH:C:\mingw64\bin;=%"
set "PATH=%PATH:c:\tools\php;=%"

:: On azure, there are libcrypto*.dll & libssl*.dll under
:: C:\Windows\System32, which should not be there (no vendor dlls in windows folder).
:: They would be found before the openssl libs of the conda environment, so we delete them.
if defined CI (
    DEL C:\Windows\System32\libcrypto-1_1-x64.dll || (Echo Ignoring failure to delete C:\Windows\System32\libcrypto-1_1-x64.dll)
    DEL C:\Windows\System32\libssl-1_1-x64.dll || (Echo Ignoring failure to delete C:\Windows\System32\libssl-1_1-x64.dll)
    DEL C:\Windows\System32\msmpi.dll || (Echo Ignoring failure to delete C:\Windows\System32\msmpi.dll)
    DEL C:\Windows\System32\msmpires.dll || (Echo Ignoring failure to delete C:\Windows\System32\msmpires.dll)
)

:: Make paths like C:\hostedtoolcache\windows\Ruby\2.5.7\x64\bin garbage
set "PATH=%PATH:ostedtoolcache=%"
set "PATH=%PATH:xternals\git\mingw=%"

:: Install CUDA drivers if needed
for %%i in ("%~dp0.") do set "SCRIPT_DIR=%%~fi"
<.ci_support\%CONFIG%.yaml shyaml get-value cuda_compiler_version.0 None > cuda.version
<cuda.version set /p CUDA_VERSION=
del cuda.version
if not "%CUDA_VERSION%" == "None" (
    if "%CUDA_VERSION:~0,2%" == "12" (
        :: Don't call install_cuda, as we'll get CUDA packages from CF
        set "CUDA_PATH="
        set "CONDA_OVERRIDE_CUDA=%CUDA_VERSION%"
        :: Export CONDA_OVERRIDE_CUDA to allow __cuda to be detected on CI systems without GPUs
        echo set "CONDA_OVERRIDE_CUDA=%CONDA_OVERRIDE_CUDA%" >> "%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"
    ) else (
        call "%SCRIPT_DIR%\install_cuda.bat" %CUDA_VERSION%
        if errorlevel 1 (
            echo Could not install CUDA
            exit 1
        )
        :: We succeeded! Export paths
        set "CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v%CUDA_VERSION%"
        set "PATH=%PATH%;%CUDA_PATH%\bin"
        set "CONDA_OVERRIDE_CUDA=%CUDA_VERSION%"
    )
)
:: /CUDA

conda.exe info --json | shyaml get-value platform > build_platform.txt
set /p BUILD_PLATFORM=<build_platform.txt
del build_platform.txt

cat .ci_support\%CONFIG%.yaml | shyaml get-value target_platform.0 %BUILD_PLATFORM% > host_platform.txt
set /p HOST_PLATFORM=<host_platform.txt
del host_platform.txt

type .ci_support\%CONFIG%.yaml

mkdir "%CONDA_PREFIX%\etc\conda\activate.d"

echo set "CONDA_BLD_PATH=%CONDA_BLD_PATH%"         > "%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"
echo set "CPU_COUNT=%CPU_COUNT%"                  >> "%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"
echo set "PYTHONUNBUFFERED=%PYTHONUNBUFFERED%"    >> "%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"
echo set "PATH=%PATH%"                            >> "%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"
if not "%CUDA_PATH%" == "" (
    echo set "CUDA_PATH=%CUDA_PATH%"              >> "%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"
    echo set "CUDA_HOME=%CUDA_PATH%"              >> "%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"
    :: Export CONDA_OVERRIDE_CUDA to allow __cuda to be detected on CI systems without GPUs
    echo set "CONDA_OVERRIDE_CUDA=%CONDA_OVERRIDE_CUDA%" >> "%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"
)
echo set "BUILD_PLATFORM=%BUILD_PLATFORM%"        >> "%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"
echo set "HOST_PLATFORM=%HOST_PLATFORM%"          >> "%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"

if "%HOST_PLATFORM%-%BUILD_PLATFORM%-%PROCESSOR_ARCHITECTURE%" == "win-arm64-win-64-ARM64" (
    echo set "CROSSCOMPILING_EMULATOR=1"          >> "%CONDA_PREFIX%\etc\conda\activate.d\conda-forge-ci-setup-activate.bat"
    echo CROSSCOMPILING_EMULATOR:                 >> ".ci_support\%CONFIG%.yaml"
    echo - 1                                      >> ".ci_support\%CONFIG%.yaml"
)

call activate base

conda.exe info
conda.exe config --show-sources
conda.exe list --show-channel-urls
