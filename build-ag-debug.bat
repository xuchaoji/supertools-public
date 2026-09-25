@echo off
rem Use DevEco Studio toolchain from DEVECO_HOME (portable, no hardcoded path)
if not defined DEVECO_HOME goto :noDevEco
set "DEVECO_SDK_HOME=%DEVECO_HOME%\sdk"
set "PATH=%DEVECO_HOME%\tools\node;%DEVECO_HOME%\tools\hvigor\bin;%DEVECO_HOME%\sdk\default\openharmony\toolchains;%PATH%"

hvigorw --mode module -p module=main@product -p product=default -p buildMode=debug -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon
if %ERRORLEVEL% EQU 0 hdc install "main\build\default\outputs\product\main-product-signed.hap"
@pause
exit /b 0

:noDevEco
echo [ERROR] DEVECO_HOME environment variable is not set.
echo Run this once first:  setx DEVECO_HOME "C:\Program Files\Huawei\DS-6.1.1.300"
@pause
exit /b 1
