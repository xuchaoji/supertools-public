import hilog from '@ohos.hilog';
import nativeHdc from 'libhdc_z.so';
import fs from '@ohos.file.fs';
import { socket } from '@kit.NetworkKit';

const TAG = 'HDC_Z';

/** Port the in-process hdcd server listens on (see hdctools/main.cpp). */
const SERVER_HOST: string = '127.0.0.1';
const SERVER_PORT: number = 18710;

export interface HdcShellResult {
  exitCode: number;
  stdout: string;
  stderr: string;
  /** Wall-clock duration of the command, -1 when cancelled. */
  durationMs: number;
  timedOut: boolean;
  cancelled: boolean;
  /** Native-level failure description (e.g. hdcCmd threw); empty when OK. */
  error: string;
}

/**
 * ArkTS wrapper over libhdc_z.so. Each command runs on a native worker thread
 * and writes stdout/stderr into its own run_<seq> directory; the ArkTS side
 * supports a per-command timeout and explicit cancel so the terminal UI can
 * never be locked forever by a hung command.
 */
export class HdcService {
  private tempDir: string = '/data/storage/el2/base/hdcz/';
  private serverStarted: boolean = false;
  private pendingSettled: boolean = false;
  private pendingResolve: ((r: HdcShellResult) => void) | null = null;
  private pendingTimer: number = -1;
  private pendingRunDir: string = '';

  startServer(): void {
    if (this.serverStarted) { return; }
    try {
      hilog.info(0x0000, TAG, 'hdcServer called from ArkTS');
      nativeHdc.hdcServer(this.tempDir);
      this.serverStarted = true;
      hilog.info(0x0000, TAG, 'startServer: native hdcServer returned OK');
    } catch (e) {
      hilog.error(0x0000, TAG, 'startServer exception');
    }
  }

  /**
   * True probe of server readiness: try to open a TCP connection to the
   * in-process hdcd listener. Called repeatedly by waitForServerReady().
   */
  private probeOnce(timeoutMs: number): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      let tcp: socket.TCPSocket | null = null;
      let done = false;
      const finish = (ok: boolean): void => {
        if (done) { return; }
        done = true;
        try { tcp?.close(); } catch (e) { /* ignore */ }
        resolve(ok);
      };
      try {
        tcp = socket.constructTCPSocketInstance();
        tcp.on('error', () => { finish(false); });
        tcp.connect({
          address: { address: SERVER_HOST, port: SERVER_PORT, family: 1 },
          timeout: timeoutMs
        }).then(() => { finish(true); }).catch(() => { finish(false); });
      } catch (e) {
        finish(false);
      }
    });
  }

  /**
   * Poll probeOnce() until the server is reachable or timeoutMs elapses.
   * Used by the page to replace the previous hard-coded startup delay.
   */
  async waitForServerReady(timeoutMs: number = 6000, intervalMs: number = 250): Promise<boolean> {
    const deadline: number = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (await this.probeOnce(1000)) { return true; }
      await new Promise<void>((r) => setTimeout(r, intervalMs));
    }
    return false;
  }

  /**
   * Run one hdc command. The promise settles when the native command finishes,
   * when it exceeds timeoutMs, or when cancel() is called — whichever comes
   * first. A timed-out/cancelled native worker may still finish in the
   * background, but its output goes to its own run_<seq> directory, so it can
   * never corrupt a later command's output.
   */
  execCommand(cmd: string, timeoutMs: number = 30000): Promise<HdcShellResult> {
    const start: number = Date.now();
    hilog.info(0x0000, TAG, 'execCommand: cmd=%{public}s', cmd);
    return new Promise<HdcShellResult>((resolve) => {
      this.pendingSettled = false;
      this.pendingResolve = resolve;
      this.pendingRunDir = '';
      let runDir: string = '';
      try {
        runDir = nativeHdc.hdcCmd(cmd, this.tempDir, (ret: number) => {
          if (this.pendingSettled) { return; }
          this.pendingSettled = true;
          this.pendingResolve = null;
          this.pendingRunDir = '';
          if (this.pendingTimer >= 0) { clearTimeout(this.pendingTimer); this.pendingTimer = -1; }
          this.finishWithFiles(runDir, ret, Date.now() - start, resolve);
        });
        this.pendingRunDir = runDir;
      } catch (e) {
        this.pendingSettled = true;
        this.pendingResolve = null;
        resolve({
          exitCode: -1, stdout: '', stderr: '', durationMs: Date.now() - start,
          timedOut: false, cancelled: false, error: 'native hdcCmd threw: ' + JSON.stringify(e)
        });
        return;
      }
      this.pendingTimer = setTimeout(() => {
        if (this.pendingSettled) { return; }
        this.pendingSettled = true;
        this.pendingResolve = null;
        this.pendingTimer = -1;
        if (runDir) { this.cleanupRunDir(runDir); }
        resolve({
          exitCode: -1, stdout: '', stderr: 'command timed out after ' + timeoutMs + 'ms',
          durationMs: Date.now() - start, timedOut: true, cancelled: false, error: ''
        });
      }, timeoutMs);
    });
  }

  /** Release the UI immediately when the user hits Cancel. */
  cancel(): void {
    if (this.pendingSettled || this.pendingResolve === null) { return; }
    this.pendingSettled = true;
    const resolve = this.pendingResolve;
    this.pendingResolve = null;
    if (this.pendingTimer >= 0) { clearTimeout(this.pendingTimer); this.pendingTimer = -1; }
    this.cleanupRunDir(this.pendingRunDir);
    this.pendingRunDir = '';
    resolve({
      exitCode: -1, stdout: '', stderr: 'cancelled', durationMs: -1,
      timedOut: false, cancelled: true, error: ''
    });
  }

  destroy(): void {
    this.cancel();
  }

  private async finishWithFiles(runDir: string, ret: number, durationMs: number,
    resolve: (r: HdcShellResult) => void): Promise<void> {
    let stdout: string = '';
    let stderr: string = '';
    try { stdout = await fs.readText(runDir + 'hdc.out'); } catch (e) { /* no output */ }
    try { stderr = await fs.readText(runDir + 'hdc.err'); } catch (e) { /* no stderr */ }
    this.cleanupRunDir(runDir);
    resolve({
      exitCode: ret, stdout: stdout, stderr: stderr, durationMs: durationMs,
      timedOut: false, cancelled: false, error: ''
    });
  }

  private cleanupRunDir(runDir: string): void {
    if (!runDir) { return; }
    try { fs.unlinkSync(runDir + 'hdc.out'); } catch (e) { /* ignore */ }
    try { fs.unlinkSync(runDir + 'hdc.err'); } catch (e) { /* ignore */ }
    try { fs.rmdirSync(runDir); } catch (e) { /* ignore */ }
  }
}
