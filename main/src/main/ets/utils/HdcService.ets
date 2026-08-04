import hilog from '@ohos.hilog';
import nativeHdc from 'libhdc_z.so';
import fs from '@ohos.file.fs';

const TAG = 'HDC_Z';

export interface HdcShellResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

export class HdcService {
  private tempDir: string = '/data/storage/el2/base/hdcz/';
  private serverStarted: boolean = false;

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

  execCommand(cmd: string): Promise<HdcShellResult> {
    hilog.info(0x0000, TAG, 'execCommand: cmd=%{public}s', cmd);
    let outPath = this.tempDir + 'hdc.out';
    return new Promise<HdcShellResult>((resolve) => {
      try { fs.unlinkSync(outPath); } catch (e) {}
      nativeHdc.hdcCmd(cmd, this.tempDir, async (ret: number) => {
        try {
          let out = await fs.readText(outPath);
          hilog.info(0x0000, TAG, 'execCommand: outputLen=%{public}d', out.length);
          resolve({ exitCode: ret, stdout: out, stderr: '' });
        } catch (e) {
          hilog.info(0x0000, TAG, 'execCommand: no output file');
          resolve({ exitCode: ret, stdout: '', stderr: '' });
        }
      });
    });
  }

  destroy(): void { }
}
