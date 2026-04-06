import { HMRouter } from "@hadss/hmrouter";
import { PreferencesUtil, ToastUtil } from "@pura/harmony-utils";
import { PageNames } from "../constant/PageNames";
import { SpKeys } from "../constant/SpKeys";
import { RecordModel } from "../model/RecordModel";
import { MyAVScreenCapture } from "../utils/MyAVScreenCapture";
import { RecordViewModel } from "../viewmodel/RecordViewModel";
import { RecordCard } from "../widgets/RecordCard";
import { abilityAccessCtrl, Permissions } from "@kit.AbilityKit";
import { BusinessError } from "@kit.BasicServicesKit";
import { audio } from "@kit.AudioKit";
import { BackgroundServiceManager } from "../utils/BackgroundServiceManager";

const TAG: string = 'ArkTSAVScreenCapture'
const START_RECORD_DELAY: number = 3;
const permissions: Array<Permissions> = ['ohos.permission.MICROPHONE', 'ohos.permission.KEEP_BACKGROUND_RUNNING'];

@HMRouter({ pageUrl: PageNames.SCREEN_RECORD })
@ComponentV2
export struct ScreenRecordPage {
  @Local viewModel: RecordViewModel = RecordViewModel.getInstance();
  private filesDir = this.getUIContext().getHostContext()?.filesDir;

  audioManager = audio.getAudioManager();
  audioSessionManager: audio.AudioSessionManager = this.audioManager.getSessionManager();
  strategy: audio.AudioSessionStrategy = { concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_DUCK_OTHERS };

  aboutToAppear(): void {
    if (PreferencesUtil.getBooleanSync(SpKeys.PRIVACY_AGREE)) {
      this.requestPermissions();
    }
  }

  build() {
    RelativeContainer() {
      // 视频列表区域
      RelativeContainer() {
        if (this.viewModel.recordings.length === 0) {
          this.EmptyView()
        } else {
          Grid() {
            Repeat<RecordModel>(this.viewModel.recordings)
              .each((ri: RepeatItem<RecordModel>) => { // 核心修正：参数类型为 RepeatItem
                GridItem() {
                  RecordCard({
                    repeatRecordItem: ri
                  })
                }
                .height('45%')
                .width('45%')
              })
              .key((item) => item.fineName + item.filePath)
              .virtualScroll()
          }
          .columnsGap('16vp')
          .rowsGap('16vp')
          .padding('8vp')
          .columnsTemplate('1fr 1fr')
          .width('100%')
          .height('100%')
        }
      }
      .alignRules({ top: { anchor: '__container__', align: VerticalAlign.Top } })
      .width('100%')
      .height('80%')
      .id('video_area')

      // 控制区域
      Column() {
        Image(this.viewModel.isInRecording ? $r('app.media.stopRecord') : $r('app.media.startRecord'))
          .width('48vp')
          .height('48vp')

        Text(this.viewModel.isInRecording ? $r('app.string.stop_recording_hint') : $r('app.string.start_recording_hint'))
          .fontColor($r('sys.color.font_secondary'))
          .margin({ top: '4vp' })
      }
      .onClick(() => this.toggleRecordAction())
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height('20%')
      .alignRules({ bottom: { anchor: '__container__', align: VerticalAlign.Bottom } })
    }
    .backgroundColor($r('sys.color.comp_background_gray'))
    .width('100%')
    .height('100%')
  }

  @Builder
  EmptyView() {
    Column() {
      Image($r('app.media.empty')).width('64vp').height('64vp')
      Text($r('app.string.empty_recording_list')).fontSize('20vp').margin({ top: '12vp' })
    }.justifyContent(FlexAlign.Center).width('100%').height('100%')
  }

  private async toggleRecordAction() {
    if (!this.viewModel.isInRecording) {
      ToastUtil.showToast(`${START_RECORD_DELAY} 秒后开始录制`);
      await this.audioSessionManager.activateAudioSession(this.strategy);
      BackgroundServiceManager.startRecordingTask();
      setTimeout(() => {
        MyAVScreenCapture.getInstance().startRecording(this.filesDir as string);
      }, START_RECORD_DELAY * 1000)
    } else {
      await this.viewModel.stopRecordingTask();
      await this.audioSessionManager.deactivateAudioSession();
      BackgroundServiceManager.stopRecordingTask()
    }
  }

  private requestPermissions() {
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionsFromUser(this.getUIContext().getHostContext(), permissions).catch((err: BusinessError) => {
      console.error(TAG, 'Permission error', JSON.stringify(err));
    });
  }
}