@echo off
setlocal
rem Use DevEco Studio toolchain from DEVECO_HOME (portable, no hardcoded path)
if not defined DEVECO_HOME goto :noDevEco

rem 必须显式指定设备，避免多设备/默认设备误装（仓库约定）
if not "%~1"=="" set "HDC_TARGET=%~1"
if not defined HDC_TARGET goto :noTarget

set "DEVECO_SDK_HOME=%DEVECO_HOME%\sdk"
set "PATH=%DEVECO_HOME%\tools\node;%DEVECO_HOME%\tools\hvigor\bin;%DEVECO_HOME%\sdk\default\openharmony\toolchains;%PATH%"

echo [1/4] build notes_hsp (product=default)
call hvigorw --mode module -p module=notes_hsp@default -p product=default -p buildMode=debug assembleHsp --analyze=normal --parallel --incremental --daemon
if %ERRORLEVEL% NEQ 0 goto :failed

echo [2/4] build main HAP (product=default)
call hvigorw --mode module -p module=main@product -p product=default -p buildMode=debug -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon
if %ERRORLEVEL% NEQ 0 goto :failed

set "HAP=main\build\default\outputs\product\main-product-signed.hap"
set "HSP=notes_hsp\build\default\outputs\default\notes_hsp-default-signed.hsp"
if not exist "%HAP%" goto :missing
if not exist "%HSP%" goto :missing

echo [3/4] push HAP + HSP to %HDC_TARGET%
hdc -t %HDC_TARGET% file send "%HAP%" /data/local/tmp/main-product-signed.hap
if %ERRORLEVEL% NEQ 0 goto :failed
hdc -t %HDC_TARGET% file send "%HSP%" /data/local/tmp/notes_hsp-default-signed.hsp
if %ERRORLEVEL% NEQ 0 goto :failed

echo [4/4] install HAP + HSP
hdc -t %HDC_TARGET% shell "bm install -r -p /data/local/tmp/main-product-signed.hap /data/local/tmp/notes_hsp-default-signed.hsp"
if %ERRORLEVEL% NEQ 0 goto :failed

echo [OK] installed default HAP + notes_hsp
@pause
exit /b 0

:missing
echo [ERROR] build output missing: expected %HAP% and %HSP%
@goto :failed

:noDevEco
echo [ERROR] DEVECO_HOME environment variable is not set.
echo Run this once first:  setx DEVECO_HOME "C:\Program Files\Huawei\DS-6.1.1.300"
@pause
exit /b 1

:noTarget
echo [ERROR] HDC_TARGET is not set.
echo Usage: build-ag-debug.bat ^<target^>    e.g. build-ag-debug.bat 192.168.3.144:12345
@pause
exit /b 1

:failed
echo [ERROR] build or install failed.
@pause
exit /b 1
