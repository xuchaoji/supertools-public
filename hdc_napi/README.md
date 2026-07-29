# hdc_napi

HDC protocol NAPI bindings for HarmonyOS supertools.

## Prerequisites

1. Install Rust: https://rustup.rs
2. Add OHOS target:
   ```
   rustup target add aarch64-unknown-linux-ohos
   ```
3. Set `OHOS_NDK_HOME`:
   ```bat
   set OHOS_NDK_HOME=C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native
   ```

## Build

```bat
cd hdc_napi
build_ohos.bat
```

## Output

`target/aarch64-unknown-linux-ohos/release/libhdc_napi.so`
→ copy to `main/src/main/libs/arm64-v8a/`

## Architecture

```
ArkTS (HdcNativeService.ets)
  │  requireNapi('libhdc_napi.so')
  ▼
NAPI bridge (lib.rs)
  │  #[napi] fn hdc_check_connection() -> HdcStatus
  │  #[napi] fn hdc_execute_shell(cmd: String) -> HdcOutput
  │  #[napi] fn hdc_ping() -> bool
  ▼
std::net::TcpStream → 127.0.0.1:8710 (hdcd)
```

## API Mapping

| NAPI function | hdc equivalent | Returns |
|---|---|---|
| `hdcCheckConnection()` | `hdc list targets -v` | `HdcStatus { connected, deviceCount, error }` |
| `hdcExecuteShell(cmd)` | `hdc shell <cmd>` | `HdcOutput { exitCode, stdout, stderr }` |
| `hdcPing()` | `hdc checkserver` (fast) | `bool` |
| `hdcServerVersion()` | `hdc checkserver` | `HdcOutput { exitCode, stdout }` |
