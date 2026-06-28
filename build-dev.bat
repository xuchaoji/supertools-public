hvigorw --mode module -p module=main@dev -p product=dev -p buildMode=debug -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon
if %ERRORLEVEL% EQU 0 hdc install "main\build\dev\outputs\dev\main-dev-signed.hap"
@pause
