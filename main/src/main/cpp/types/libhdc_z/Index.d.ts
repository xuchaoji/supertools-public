/**
 * libhdc_z.so — native HDC bridge (hdctools/napi.cpp)
 *
 * 这个文件必须放在 src/main/cpp/types/<库名>/Index.d.ts：
 * 该目录是 ArkTS 解析 `import ... from 'libxxx.so'` 的约定位置
 * （hvigor 里对应 BuildDirConst.CPP_TYPES，IDE 的 ArkTSCheck 也只看这里）。
 *
 * hdcServer(tempDir): starts the in-process hdcd server (idempotent).
 * hdcCmd(cmd, tempDir, callback): runs one hdc command on a worker thread,
 *   writes stdout/stderr to tempDir/run_<seq>/{hdc.out,hdc.err}, then invokes
 *   callback(ret). Returns the run directory synchronously so the caller can
 *   read the output files when the callback fires.
 */
export const hdcCmd: (cmd: string, tempDir: string, callback: (ret: number) => void) => string;
export const hdcServer: (tempDir: string) => void;
