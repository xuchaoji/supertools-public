@echo off
rem Use DevEco Studio toolchain from DEVECO_HOME (portable, no hardcoded path)
if not defined DEVECO_HOME goto :noDevEco
set "DEVECO_SDK_HOME=%DEVECO_HOME%\sdk"
set "PATH=%DEVECO_HOME%\tools\node;%DEVECO_HOME%\tools\hvigor\bin;%DEVECO_HOME%\sdk\default\openharmony\toolchains;%PATH%"

hvigorw --mode project -p product=release -p buildMode=release -p requiredDeviceType=phone assembleApp --analyze=normal --parallel --incremental --daemon
@pause
exit /b 0

:noDevEco
echo [ERROR] DEVECO_HOME environment variable is not set.
echo Run this once first:  setx DEVECO_HOME "C:\Program Files\Huawei\DS-6.1.1.300"
@pause
exit /b 1
