/**
 * libhdc_z.so — native HDC bridge (hdctools/napi.cpp)
 *
 * hdcServer(tempDir): starts the in-process hdcd server (idempotent).
 * hdcCmd(cmd, tempDir, callback): runs one hdc command on a worker thread,
 *   writes stdout/stderr to tempDir/run_<seq>/{hdc.out,hdc.err}, then invokes
 *   callback(ret). Returns the run directory synchronously so the caller can
 *   read the output files when the callback fires.
 */
export const hdcCmd: (cmd: string, tempDir: string, callback: (ret: number) => void) => string;
export const hdcServer: (tempDir: string) => void;
