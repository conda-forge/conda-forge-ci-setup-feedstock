set "CUDA_VERSION=%1"

:: We define a default subset of components to be installed for faster installation times
:: and reduced storage usage (CI is limited to 10GB). Full list of components is available at
:: https://docs.nvidia.com/cuda/archive/%CUDA_VERSION%/cuda-installation-guide-microsoft-windows/index.html
set "VAR=nvcc_%CUDA_VERSION% cuobjdump_%CUDA_VERSION% nvprune_%CUDA_VERSION% cupti_%CUDA_VERSION%"
set "VAR=%VAR% memcheck_%CUDA_VERSION% nvdisasm_%CUDA_VERSION% nvprof_%CUDA_VERSION% cublas_%CUDA_VERSION%"
set "VAR=%VAR% cublas_dev_%CUDA_VERSION% cudart_%CUDA_VERSION% cufft_%CUDA_VERSION% cufft_dev_%CUDA_VERSION%"
set "VAR=%VAR% curand_%CUDA_VERSION% curand_dev_%CUDA_VERSION% cusolver_%CUDA_VERSION% cusolver_dev_%CUDA_VERSION%"
set "VAR=%VAR% cusparse_%CUDA_VERSION% cusparse_dev_%CUDA_VERSION% npp_%CUDA_VERSION% npp_dev_%CUDA_VERSION%"
set "VAR=%VAR% nvrtc_%CUDA_VERSION% nvrtc_dev_%CUDA_VERSION% nvml_dev_%CUDA_VERSION%"
set "VAR=%VAR% visual_studio_integration_%CUDA_VERSION%"
set "CUDA_COMPONENTS=%VAR%"

if "%CUDA_VERSION%" == "9.2"  goto cuda92
if "%CUDA_VERSION%" == "10.0" goto cuda100
if "%CUDA_VERSION%" == "10.1" goto cuda101
if "%CUDA_VERSION%" == "10.2" goto cuda102
if "%CUDA_VERSION%" == "11.0" goto cuda110
if "%CUDA_VERSION%" == "11.1" goto cuda111
if "%CUDA_VERSION%" == "11.2" goto cuda1122
if "%CUDA_VERSION%" == "11.3" goto cuda1131
if "%CUDA_VERSION%" == "11.4" goto cuda1143
if "%CUDA_VERSION%" == "11.5" goto cuda1152
if "%CUDA_VERSION%" == "11.6" goto cuda1162
if "%CUDA_VERSION%" == "11.7" goto cuda1171
if "%CUDA_VERSION%" == "11.8" goto cuda118

echo CUDA '%CUDA_VERSION%' is not supported
exit /b 1

:: Define URLs per version
:cuda92
set "CUDA_NETWORK_INSTALLER_URL=https://developer.nvidia.com/compute/cuda/9.2/Prod2/network_installers2/cuda_9.2.148_win10_network"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=2bf9ae67016867b68f361bf50d2b9e7b"
set "CUDA_INSTALLER_URL=https://developer.nvidia.com/compute/cuda/9.2/Prod2/local_installers2/cuda_9.2.148_win10"
set "CUDA_INSTALLER_CHECKSUM=f6c170a7452098461070dbba3e6e58f1"
set "CUDA_PATCH_URL=https://developer.nvidia.com/compute/cuda/9.2/Prod2/patches/1/cuda_9.2.148.1_windows"
set "CUDA_PATCH_CHECKSUM=09e20653f1346d2461a9f8f1a7178ba2"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nvgraph_%CUDA_VERSION% nvgraph_dev_%CUDA_VERSION%"
goto cuda_common


:cuda100
set "CUDA_NETWORK_INSTALLER_URL=https://developer.nvidia.com/compute/cuda/10.0/Prod/network_installers/cuda_10.0.130_win10_network"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=3312deac9c939bd78d0e7555606c22fc"
set "CUDA_INSTALLER_URL=https://developer.nvidia.com/compute/cuda/10.0/Prod/local_installers/cuda_10.0.130_411.31_win10"
set "CUDA_INSTALLER_CHECKSUM=90fafdfe2167ac25432db95391ca954e"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nvgraph_%CUDA_VERSION% nvgraph_dev_%CUDA_VERSION%"
goto cuda_common


:cuda101
set "CUDA_NETWORK_INSTALLER_URL=http://developer.download.nvidia.com/compute/cuda/10.1/Prod/network_installers/cuda_10.1.243_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=fae0c958440511576691b825d4599e93"
set "CUDA_INSTALLER_URL=http://developer.download.nvidia.com/compute/cuda/10.1/Prod/local_installers/cuda_10.1.243_426.00_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=b54cf32683f93e787321dcc2e692ff69"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nvgraph_%CUDA_VERSION% nvgraph_dev_%CUDA_VERSION%"
goto cuda_common


:cuda102
set "CUDA_NETWORK_INSTALLER_URL=http://developer.download.nvidia.com/compute/cuda/10.2/Prod/network_installers/cuda_10.2.89_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=60e0f16845d731b690179606f385041e"
set "CUDA_INSTALLER_URL=http://developer.download.nvidia.com/compute/cuda/10.2/Prod/local_installers/cuda_10.2.89_441.22_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=d9f5b9f24c3d3fc456a3c789f9b43419"
set "CUDA_PATCH_URL=http://developer.download.nvidia.com/compute/cuda/10.2/Prod/patches/1/cuda_10.2.1_win10.exe"
set "CUDA_PATCH_CHECKSUM=9d751ae129963deb7202f1d85149c69d"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nvgraph_%CUDA_VERSION% nvgraph_dev_%CUDA_VERSION%"
goto cuda_common


:cuda110
set "CUDA_NETWORK_INSTALLER_URL=http://developer.download.nvidia.com/compute/cuda/11.0.3/network_installers/cuda_11.0.3_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=1b88bf7bb8e50207bbb53ed2033f93f3"
set "CUDA_INSTALLER_URL=http://developer.download.nvidia.com/compute/cuda/11.0.3/local_installers/cuda_11.0.3_451.82_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=80ae0fdbe04759123f3cab81f2aadabd"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION%"
goto cuda_common


:cuda111
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.1.1/network_installers/cuda_11.1.1_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=7e36e50ee486a84612adfd85500a9971"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.1.1/local_installers/cuda_11.1.1_456.81_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=a89dfad35fc1adf02a848a9c06cfff15"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION%"
goto cuda_common


:cuda112
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.2.0/network_installers/cuda_11.2.0_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=ab02a25eed1201cc3e414be943a242df"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.2.0/local_installers/cuda_11.2.0_460.89_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=92f38c37ce9c6c11d27c10701b040256"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION%"
goto cuda_common


:cuda1121
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.2.1/network_installers/cuda_11.2.1_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=de16fac595def6da33424e8bb5539bab"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.2.1/local_installers/cuda_11.2.1_461.09_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=c34b541d8706b5aa0d8ba7313fff78e7"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION%"
goto cuda_common


:cuda1122
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.2.2/network_installers/cuda_11.2.2_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=67257f6a471ffbd49068793a699cecb7"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.2.2/local_installers/cuda_11.2.2_461.33_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=f9da6687d8a4f137ff14f8389b496e0a"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION%"
goto cuda_common

:cuda113
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.3.0/network_installers/cuda_11.3.0_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=dddd7b22fcbb530b467db764eeb8439f"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.3.0/local_installers/cuda_11.3.0_465.89_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=564c6ecf0b82f481d291519387e71db5"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION%"
goto cuda_common

:cuda1131
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.3.1/network_installers/cuda_11.3.1_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=8e812588cd299fe6e8d1e85b55bddf28"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.3.1/local_installers/cuda_11.3.1_465.89_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=7bf61cf7b059ba08197c70035879c352"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION%"
goto cuda_common

:cuda114
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.4.0/network_installers/cuda_11.4.0_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=140811a2ca1a0993fcc8ee1a16d21a79"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.4.0/local_installers/cuda_11.4.0_471.11_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=423695ea246810200e210f07a0e0bd43"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION% thrust_%CUDA_VERSION%"
goto cuda_common

:cuda1143
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.4.3/network_installers/cuda_11.4.3_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=4f57e50ec238ac29d82e549dc00b7bdd"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.4.3/local_installers/cuda_11.4.3_472.50_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=602bf92bddd198375f8f5b2aef9ad3f0"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION% thrust_%CUDA_VERSION%"
goto cuda_common

:cuda115
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.5.0/network_installers/cuda_11.5.0_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=499fb5f0d25424a4a52f901a78beceef"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.5.0/local_installers/cuda_11.5.0_496.13_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=9ae3759817c87dc8ae6f0d38cb164361"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION% thrust_%CUDA_VERSION%"
goto cuda_common

:cuda1151
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.5.1/network_installers/cuda_11.5.1_windows_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=0e70240480f3d63bc17adcb046c01580"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.5.1/local_installers/cuda_11.5.1_496.13_windows.exe"
set "CUDA_INSTALLER_CHECKSUM=74d4a0723ca179f56f6877e72c9b1694"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION% thrust_%CUDA_VERSION%"
goto cuda_common

:cuda1152
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.5.2/network_installers/cuda_11.5.2_windows_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=6f70a0e4d798b63e2c19d8993d5806f4"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.5.2/local_installers/cuda_11.5.2_496.13_windows.exe"
set "CUDA_INSTALLER_CHECKSUM=7fd10dfd044ec3c11160468886d5b10d"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION% thrust_%CUDA_VERSION%"
goto cuda_common

:cuda116
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.6.0/network_installers/cuda_11.6.0_windows_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=99a5d04c00eeac430c7f34b013c5b7c6"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.6.0/local_installers/cuda_11.6.0_511.23_windows.exe"
set "CUDA_INSTALLER_CHECKSUM=7a91a7a7696e869ff8d90c52faf48f40"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION% thrust_%CUDA_VERSION%"
goto cuda_common

:cuda1162
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.6.2/network_installers/cuda_11.6.2_windows_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=0bc12c8d5b835681931be4b58c092699"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.6.2/local_installers/cuda_11.6.2_511.65_windows.exe"
set "CUDA_INSTALLER_CHECKSUM=b5ca553bcf7e702a6bc454979aa87e65"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION% thrust_%CUDA_VERSION%"
goto cuda_common

:cuda117
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.7.0/network_installers/cuda_11.7.0_windows_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=89397d589806387de679b97565a2e800"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.7.0/local_installers/cuda_11.7.0_516.01_windows.exe"
set "CUDA_INSTALLER_CHECKSUM=a2388d0044b2dd6a3469938eb6108c85"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION% thrust_%CUDA_VERSION%"
goto cuda_common

:cuda1171
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.7.1/network_installers/cuda_11.7.1_windows_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=f52378dc72666ae0d3ab3ee63df5aebf"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.7.1/local_installers/cuda_11.7.1_516.94_windows.exe"
set "CUDA_INSTALLER_CHECKSUM=2890ae7ba9b23591029ac24c8e2e805a"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION% thrust_%CUDA_VERSION%"
goto cuda_common

:cuda118
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.8.0/network_installers/cuda_11.8.0_windows_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=600ca859835a37395277a5f3a5b6037d"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.8.0/local_installers/cuda_11.8.0_522.06_windows.exe"
set "CUDA_INSTALLER_CHECKSUM=894c61ba173d26dc667e95ee734d3c5a"
set "CUDA_COMPONENTS=%CUDA_COMPONENTS% nsight_nvtx_%CUDA_VERSION% cuda_profiler_api_%CUDA_VERSION% thrust_%CUDA_VERSION%"
goto cuda_common


:: The actual installation logic
:cuda_common

::We expect this CUDA_PATH
set "CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v%CUDA_VERSION%"

echo Downloading CUDA version %CUDA_VERSION% installer from %CUDA_NETWORK_INSTALLER_URL%
echo Expected MD5: %CUDA_NETWORK_INSTALLER_CHECKSUM%

:: Download installer
set "CUDA_INSTALLER_EXE=C:\Program Files\cuda_installer.exe"
curl --retry 3 -k -L %CUDA_NETWORK_INSTALLER_URL% --output "%CUDA_INSTALLER_EXE%"
if errorlevel 1 (
    echo Problem downloading installer...
    exit /b 1
)
:: Check md5
openssl md5 "%CUDA_INSTALLER_EXE%" | findstr %CUDA_NETWORK_INSTALLER_CHECKSUM%
if errorlevel 1 (
    echo Checksum does not match!
    exit /b 1
)
:: Run installer
start "CUDA Toolkit Install" /wait "%CUDA_INSTALLER_EXE%" -n -s %CUDA_COMPONENTS%
if errorlevel 1 (
    echo Problem installing CUDA toolkit...
    exit /b 1
)
del "%CUDA_INSTALLER_EXE%"
set "CUDA_INSTALLER_EXE="

:: If patches are needed, download and apply
if not "%CUDA_PATCH_URL%"=="" (
    echo This version requires an additional patch
    set "CUDA_PATCH_EXE=C:\Program Files\cuda_patch.exe"
    curl --retry 3 -k -L %CUDA_PATCH_URL% --output "%CUDA_PATCH_EXE%"
    if errorlevel 1 (
        echo Problem downloading patch installer...
        exit /b 1
    )
    openssl md5 "%CUDA_PATCH_EXE%" | findstr %CUDA_PATCH_CHECKSUM%
    if errorlevel 1 (
        echo Checksum does not match!
        exit /b 1
    )
    start "CUDA Patch Install" /wait "%CUDA_PATCH_EXE%" -n -s
    if errorlevel 1 (
        echo Problem running patch installer...
        exit /b 1
    )
    del "%CUDA_PATCH_EXE%"
    set "CUDA_PATCH_EXE="
)

:: This should exist by now!
if not exist "%CUDA_PATH%\bin\nvcc.exe" (
    echo CUDA toolkit installation failed!
    exit /b 1
)

:: Notes about nvcuda.dll
:: ----------------------
:: We should also provide the drivers (nvcuda.dll), but the installer will not
:: proceed without a physical Nvidia card attached (not the case in the CI).
:: Expanding `<installer.exe>\Display.Driver\nvcuda.64.dl_` to `C:\Windows\System32`
:: does not work anymore (.dl_ files are not PE-COFF according to Dependencies.exe).
:: Forcing this results in a DLL error 193. Basically, there's no way to provide
:: ncvuda.dll in a GPU-less machine without breaking the EULA (aka zipping nvcuda.dll
:: from a working installation).
