import hilog from '@ohos.hilog';
import nativeHdc from 'libhdc_z.so';
import fs from '@ohos.file.fs';
import { socket } from '@kit.NetworkKit';

const TAG = 'HDC_Z';

/** Port the in-process hdcd server listens on (see hdctools/main.cpp). */
const SERVER_HOST: string = '127.0.0.1';
const SERVER_PORT: number = 18710;

/** Native returns this when another hdc command still holds the process-level state. */
export const HDC_BUSY_EXIT_CODE: number = -2;

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

/** Per command bookkeeping. A late native callback can only settle its own command. */
class ExecState {
  settled: boolean = false;
  runDir: string = '';
  timer: number = -1;
  resolve: ((result: HdcShellResult) => void) | null = null;
}

/**
 * ArkTS wrapper over libhdc_z.so. This is the only owner of the native HDC
 * client: commands are serialized through one process-wide queue, because the
 * native `cmd()` mutates process-level state (stdout/stderr redirection, temp
 * dir, argv) and therefore cannot run concurrently.
 */
export class HdcService {
  private static instance: HdcService | undefined = undefined;

  private tempDir: string = '/data/storage/el2/base/hdcz/';
  private serverStarted: boolean = false;
  /** Tail of the command queue; always settles fulfilled so the queue never wedges. */
  private queueTail: Promise<void> = Promise.resolve();
  private running: ExecState | null = null;

  public static getInstance(): HdcService {
    if (!HdcService.instance) {
      HdcService.instance = new HdcService();
    }
    return HdcService.instance;
  }

  public get isServerStarted(): boolean {
    return this.serverStarted;
  }

  startServer(): void {
    if (this.serverStarted) {
      return;
    }
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
        if (done) {
          return;
        }
        done = true;
        try {
          tcp?.close();
        } catch (e) { /* ignore */ }
        resolve(ok);
      };
      try {
        tcp = socket.constructTCPSocketInstance();
        tcp.on('error', () => {
          finish(false);
        });
        tcp.connect({
          address: { address: SERVER_HOST, port: SERVER_PORT, family: 1 },
          timeout: timeoutMs
        }).then(() => {
          finish(true);
        }).catch(() => {
          finish(false);
        });
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
      if (await this.probeOnce(1000)) {
        return true;
      }
      await new Promise<void>((r) => setTimeout(r, intervalMs));
    }
    return false;
  }

  /**
   * Queue one hdc command. Commands run strictly one at a time; the returned
   * promise settles when that command finishes, exceeds timeoutMs, or is
   * cancelled — whichever comes first.
   */
  execCommand(cmd: string, timeoutMs: number = 30000): Promise<HdcShellResult> {
    const run = (): Promise<HdcShellResult> => this.execute(cmd, timeoutMs);
    const result: Promise<HdcShellResult> = this.queueTail.then(run, run);
    this.queueTail = result.then((): void => {}, (): void => {});
    return result;
  }

  private execute(cmd: string, timeoutMs: number): Promise<HdcShellResult> {
    const start: number = Date.now();
    const state = new ExecState();
    hilog.info(0x0000, TAG, 'execCommand: cmd=%{public}s', cmd);
    return new Promise<HdcShellResult>((resolve) => {
      state.resolve = resolve;
      this.running = state;
      try {
        state.runDir = nativeHdc.hdcCmd(cmd, this.tempDir, (ret: number) => {
          if (state.settled) {
            return;
          }
          state.settled = true;
          this.clearState(state);
          this.finishWithFiles(state.runDir, ret, Date.now() - start, resolve)
            .catch(() => {
              resolve({
                exitCode: ret, stdout: '', stderr: '', durationMs: Date.now() - start,
                timedOut: false, cancelled: false, error: 'failed to read command output'
              });
            });
        });
      } catch (e) {
        state.settled = true;
        this.clearState(state);
        resolve({
          exitCode: -1, stdout: '', stderr: '', durationMs: Date.now() - start,
          timedOut: false, cancelled: false, error: 'native hdcCmd threw: ' + JSON.stringify(e)
        });
        return;
      }
      state.timer = setTimeout(() => {
        if (state.settled) {
          return;
        }
        state.settled = true;
        this.clearState(state);
        if (state.runDir) {
          this.cleanupRunDir(state.runDir);
        }
        resolve({
          exitCode: -1, stdout: '', stderr: 'command timed out after ' + timeoutMs + 'ms',
          durationMs: Date.now() - start, timedOut: true, cancelled: false, error: ''
        });
      }, timeoutMs);
    });
  }

  /** Release the UI immediately when the user hits Cancel.
   *  对持续抓取（如 hilog -x）：把当前已写入输出文件的部分内容一并返回，
   *  供调用方保存为用户主动停止时抓到的日志。 */
  cancel(): void {
    const state = this.running;
    if (!state || state.settled || state.resolve === null) {
      return;
    }
    state.settled = true;
    this.clearState(state);
    let partial: string = '';
    if (state.runDir) {
      try {
        partial = fs.readTextSync(state.runDir + 'hdc.out');
      } catch (e) { /* 尚无输出 */ }
      this.cleanupRunDir(state.runDir);
    }
    state.resolve({
      exitCode: -1, stdout: partial, stderr: 'cancelled', durationMs: -1,
      timedOut: false, cancelled: true, error: ''
    });
  }

  destroy(): void {
    this.cancel();
  }

  private clearState(state: ExecState): void {
    if (state.timer >= 0) {
      clearTimeout(state.timer);
      state.timer = -1;
    }
    if (this.running === state) {
      this.running = null;
    }
  }

  private async finishWithFiles(runDir: string, ret: number, durationMs: number,
    resolve: (r: HdcShellResult) => void): Promise<void> {
    let stdout: string = '';
    let stderr: string = '';
    hilog.info(0x0000, TAG, 'finishWithFiles: reading runDir=%{public}s', runDir);
    try {
      stdout = await fs.readText(runDir + 'hdc.out');
    } catch (e) { /* no output */ }
    hilog.info(0x0000, TAG, 'finishWithFiles: out read len=%{public}d', stdout.length);
    try {
      stderr = await fs.readText(runDir + 'hdc.err');
    } catch (e) { /* no stderr */ }
    this.cleanupRunDir(runDir);
    resolve({
      exitCode: ret, stdout: stdout, stderr: stderr, durationMs: durationMs,
      timedOut: false, cancelled: false, error: ''
    });
  }

  private cleanupRunDir(runDir: string): void {
    if (!runDir) {
      return;
    }
    try {
      fs.unlinkSync(runDir + 'hdc.out');
    } catch (e) { /* ignore */ }
    try {
      fs.unlinkSync(runDir + 'hdc.err');
    } catch (e) { /* ignore */ }
    try {
      fs.rmdirSync(runDir);
    } catch (e) { /* ignore */ }
  }
}
