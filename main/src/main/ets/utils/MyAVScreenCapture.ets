import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RecordViewModel } from '../viewmodel/RecordViewModel';
import { BackgroundServiceManager } from './BackgroundServiceManager';

const TAG: string = 'MyAVScreenCapture'

@ObservedV2
export class MyAVScreenCapture {
  private static instance: MyAVScreenCapture;
  private screenCapture?: media.AVScreenCaptureRecorder;
  private path: string = '';
  private fileName: string = '';
  private file: fs.File | null = null;

  private constructor() {}

  public static getInstance(): MyAVScreenCapture {
    if (!MyAVScreenCapture.instance) {
      MyAVScreenCapture.instance = new MyAVScreenCapture();
    }
    return MyAVScreenCapture.instance;
  }

  public async startRecording(filesDir: string) {
    this.updateFileFd(filesDir);
    this.screenCapture = await media.createAVScreenCaptureRecorder();
    if (!this.screenCapture) return;

    // 动态获取，防止循环依赖导致堆栈溢出
    const vm = RecordViewModel.getInstance();
    this.screenCapture.setMicEnabled(vm.recordMic);

    this.screenCapture.on('stateChange', async (infoType: media.AVScreenCaptureStateCode) => {
      const currentVm = RecordViewModel.getInstance();
      switch (infoType) {
        case media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_STARTED:
          currentVm.isInRecording = true;
          break;
        case media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_STOPPED_BY_USER:
          // 【核心修复】：用户点击系统胶囊停止时，主动触发 ViewModel 的保存逻辑
          hilog.info(0xFF00, TAG, 'Stopped by system capsule');
          currentVm.addRecordTask(this.fileName, 'file://' + this.path);
          this.cleanUp();
          break;
        case media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_CANCELED:
          this.cleanUp();
          break;
      }
    })

    let displayInfo = display.getDefaultDisplaySync();
    let captureConfig: media.AVScreenCaptureRecordConfig = {
      frameWidth: displayInfo.width,
      frameHeight: displayInfo.height,
      fd: (this.file as fs.File).fd,
      videoBitrate: 30000000,
      audioSampleRate: 48000,
      audioChannelCount: 2,
      audioBitrate: 96000,
      displayId: 0,
      preset: vm.preset
    };

    await this.screenCapture.init(captureConfig);
    await this.screenCapture.startRecording();
  }

  public async stopRecording() {
    if (this.screenCapture) {
      await this.screenCapture.stopRecording();
      this.cleanUp();
    }
  }

  // 抽离清理逻辑
  private async cleanUp() {
    if (this.screenCapture) {
      await this.screenCapture.release();
      this.screenCapture = undefined;
    }
    if (this.file) {
      fs.closeSync(this.file.fd);
      this.file = null;
    }
    RecordViewModel.getInstance().isInRecording = false;
    BackgroundServiceManager.stopRecordingTask();
  }

  public updateFileFd(filesDir: string) {
    this.fileName = Date.now() + '.mp4';
    this.path = filesDir + '/' + this.fileName;
    this.file = fs.openSync(this.path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
  }

  public getPath(): string { return this.path; }
  public getFileName(): string { return this.fileName; }
}