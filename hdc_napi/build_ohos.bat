@echo off
REM ============================================================
REM  Build hdc_napi for HarmonyOS (aarch64-unknown-linux-ohos)
REM  Prerequisites:
REM    1. rustup target add aarch64-unknown-linux-ohos
REM    2. OHOS_NDK_HOME env pointing to OHOS SDK native dir
REM       e.g. C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native
REM ============================================================

setlocal

if "%OHOS_NDK_HOME%"=="" (
    echo [ERROR] OHOS_NDK_HOME not set.
    echo   Run: set OHOS_NDK_HOME=C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native
    exit /b 1
)

REM --- Write cargo config for OHOS target ---
if not exist ".cargo" mkdir .cargo
(
echo [target.aarch64-unknown-linux-ohos]
echo linker = "%OHOS_NDK_HOME:\=/%/llvm/bin/clang++.exe"
echo rustflags = ["-C", "link-arg=--target=aarch64-linux-ohos", "-C", "link-arg=--sysroot=%OHOS_NDK_HOME:\=/%/sysroot", "-C", "link-arg=-fuse-ld=lld"]
) > .cargo\config.toml

echo [INFO] Building for aarch64-unknown-linux-ohos...
cargo build --release --target aarch64-unknown-linux-ohos

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Build failed.
    exit /b 1
)

echo.
echo [INFO] Build successful!
echo [INFO] Output: target\aarch64-unknown-linux-ohos\release\hdc_napi.so
echo.
echo [INFO] Copy .so to supertools main module:
echo   copy target\aarch64-unknown-linux-ohos\release\hdc_napi.so ..\main\src\main\libs\arm64-v8a\
echo.
echo [INFO] Then add the NAPI .d.ts file to your ArkTS project.

endlocal
