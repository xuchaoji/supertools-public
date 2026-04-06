import { RecordModel } from "../model/RecordModel";
import { PersistenceV2, Type } from "@ohos.arkui.StateManagement";
import { media } from "@kit.MediaKit";
import { MyAVScreenCapture } from "../utils/MyAVScreenCapture";

const TAG: string = 'RecordViewModel';
const RECORDING_CACHE: string = 'recording_cache';

@ObservedV2
export class RecordingCache {
  @Type(RecordModel)
  @Trace recordings: Array<RecordModel> = new Array<RecordModel>();
  @Trace recordMic: boolean = false;
  @Trace preset: number = media.AVScreenCaptureRecordPreset.SCREEN_RECORD_PRESET_H265_AAC_MP4;
}

@ObservedV2
export class RecordViewModel {
  private static instance: RecordViewModel;
  @Trace currentRecordFileName: string = '';
  @Trace isInRecording: boolean = false;
  @Trace recordingCache: RecordingCache = PersistenceV2.connect(RecordingCache, RECORDING_CACHE, () => new RecordingCache())!;

  public static getInstance() {
    if (!RecordViewModel.instance) {
      RecordViewModel.instance = new RecordViewModel();
    }
    return RecordViewModel.instance;
  }

  // 手动点击按钮停止
  public async stopRecordingTask() {
    await MyAVScreenCapture.getInstance().stopRecording();
    const fileName = MyAVScreenCapture.getInstance().getFileName();
    const filePath = 'file://' + MyAVScreenCapture.getInstance().getPath();
    this.addRecordTask(fileName, filePath);
  }

  // 【核心方法】：统一添加记录
  public addRecordTask(fileName: string, filePath: string) {
    if (!fileName || this.recordings.some(r => r.fineName === fileName)) {
      return;
    }
    let recordModel = new RecordModel();
    recordModel.filePath = filePath;
    recordModel.fineName = fileName;

    this.recordings.unshift(recordModel);
    this.currentRecordFileName = fileName;
    this.isInRecording = false;

    PersistenceV2.save(RecordingCache); // 手动强制同步到磁盘
  }

  public set preset(v: number) { this.recordingCache.preset = v; }
  public get preset(): number { return this.recordingCache.preset; }
  public set recordings(v: Array<RecordModel>) { this.recordingCache.recordings = v; }
  public get recordings(): Array<RecordModel> { return this.recordingCache.recordings; }
  public get recordMic(): boolean { return this.recordingCache.recordMic; }
  public set recordMic(v: boolean) { this.recordingCache.recordMic = v; }
}