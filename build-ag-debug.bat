hvigorw --mode module -p module=main@product -p product=default -p buildMode=debug -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon
if %ERRORLEVEL% EQU 0 hdc install "main\build\default\outputs\product\main-product-signed.hap"
@pause
