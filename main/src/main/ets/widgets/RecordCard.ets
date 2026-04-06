import { PhotoHelper } from "@pura/picker_utils";
import { RecordModel } from "../model/RecordModel";
import { formatVideoTime } from "../utils/TimeUtils";
import { photoAccessHelper } from "@kit.MediaLibraryKit";
import { DateUtil, DialogAction, DialogUtil, FileUtil, ToastUtil } from "@pura/harmony-utils";
import { BusinessError } from "@ohos.base";
import { fileIo } from "@kit.CoreFileKit";
import { Context } from "@kit.AbilityKit";
import { RecordViewModel } from "../viewmodel/RecordViewModel";
import { audio } from "@kit.AudioKit";

const TAG: string = 'RecordCard'

@ComponentV2
export struct RecordCard {
  @Param @Require repeatRecordItem: RepeatItem<RecordModel>;
  @Local isPlayFlag: boolean = false;
  @Local currentTime: number = 0
  @Local durationTime: number = 0
  @Local isStart: boolean = true;
  @Local displayName: string = '';
  private controller: VideoController = new VideoController();
  audioManager = audio.getAudioManager();
  // 创建音频会话管理器。
  audioSessionManager: audio.AudioSessionManager = this.audioManager.getSessionManager();
  // 设置音频并发模式。
  strategy: audio.AudioSessionStrategy = {
    concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_DUCK_OTHERS
  };

  aboutToAppear(): void {
    this.updateDisplayName();
  }

  @Monitor('repeatRecordItem.item.fineName')
  updateDisplayName() {
    let time: number = Number(this.repeatRecordItem.item.fineName.replace('.mp4', ''));
    let date: Date = new Date();
    date.setTime(time)
    this.displayName = DateUtil.getFormatDateStr(date);
  }

  build() {
    // Video area
    Column() {
      if (this.isPlayFlag) {
        Stack() {
          Video({ src: this.repeatRecordItem.item.filePath, controller: this.controller })
            .width('100%')
            .height('100%')
            .autoPlay(true)
            .controls(false)
            .objectFit(1)
            .zIndex(0)
            .onPrepared((event) => {
              if (!event) {
                return;
              }
              this.audioSessionManager.activateAudioSession(this.strategy).then(() => {
                console.info(TAG, 'activateAudioSession SUCCESS');
                this.durationTime = event.duration
                console.info(TAG, this.durationTime.toString());
              }).catch((err: BusinessError) => {
                console.error(TAG, `ERROR: ${err}`);
              });

            })
            .onUpdate((event) => {
              if (event) {
                this.currentTime = event.time
              }
            })
            .onFinish(() => {
              this.isStart = !this.isStart;
            })
            .transition(TransitionEffect.OPACITY.animation({ duration: 1000, curve: Curve.Sharp }))

          Column({ space: 4 }) {
            Row({ space: 8 }) {
              Text(formatVideoTime(this.currentTime))
                .fontColor(Color.White)
                .fontSize(8)
                .margin({ left: '12vp' })
              Text(formatVideoTime(this.durationTime))
                .fontColor(Color.White)
                .fontSize(8)
            }

            Slider({
              value: this.currentTime,
              min: 0,
              max: this.durationTime
            })
              .onChange((value: number, mode: SliderChangeMode) => {
                // Set the video playback progress to jump to the value
                this.controller.setCurrentTime(value);
              })
              .layoutWeight(1)
          }

          .padding({ left: '16vp', right: '16vp' })
          .zIndex(1)
          .height(43)
          .width('100%')
        }
        .alignContent(Alignment.Bottom)
        .width('100%')
        .layoutWeight(1)

      } else {
        if (this.repeatRecordItem.item.filePath != '') {
          Column() {
            Image($r('app.media.image'))
              .width(48)
              .height(48)
            Text(this.displayName)
              .width('100%')
              .height(22)
              .fontSize(12)
              .margin({ top: '6vp' })
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .layoutWeight(1)
        }
      }

      Row({ space: 24 }) {
        // 删除
        Image($r('app.media.delete'))
          .width('24vp')
          .height('24vp')
        .onClick((event) => {
          DialogUtil.showPrimaryDialog({
            message: '是否要删除该文件\n(已保存到图库的文件不会被删除)',
            primaryButton: "取消",
            secondaryButton: "确定",
            onAction: (action) => {
              if (action == DialogAction.ONE) {
                ToastUtil.showToast("取消删除")
              } else if (action == DialogAction.TWO) {
                deleteFile(this.repeatRecordItem.item.filePath)
                  .then((result) => {
                    if (result) {
                      ToastUtil.showToast('删除成功');
                      let index: number = RecordViewModel.getInstance().recordings.findIndex((recordModel) => {
                        recordModel.filePath === this.repeatRecordItem.item.filePath
                      })
                      RecordViewModel.getInstance().recordings.splice(index, 1);
                    }
                  })
              }
            }
          });

        })

        // 保存
        Image($r('app.media.export'))
          .width('24vp')
          .height('24vp')
          .onClick((event) => {
            console.log(TAG, `onSaveIcon click`)
            saveRecord(this.getUIContext().getHostContext() as Context, this.repeatRecordItem.item.filePath)
              .then(() => {
                ToastUtil.showToast('保存成功')
              })
          })

        // 播放
        Image(this.isPlayFlag ? $r('app.media.pauseIcon') : $r('app.media.playIcon'))
          .width('24vp')
          .height('24vp')
        .onClick((event) => {
          this.isPlayFlag = !this.isPlayFlag;
        })
      }
      .height('32vp')
      .alignItems(VerticalAlign.Center)
    }
    .backgroundColor($r('sys.color.ohos_fa_list_card_bg_blur'))
    .borderRadius('8vp')
    .padding('8vp')
    .width('100%')
    .layoutWeight(1)
  }
}

async function saveRecord(context: Context, srcFileUri: string) {
  try {
    srcFileUri = srcFileUri.replace('file://', '');
    console.log(TAG, `save record: uri: ${srcFileUri}`)
    let phAccessHelper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
    // 指定待保存到媒体库的位于应用沙箱的图片uri。
    let srcFileUris: Array<string> = [
      srcFileUri
    ];
    // 指定待保存照片的创建选项，包括文件后缀和照片类型，标题和照片子类型可选。
    let photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [
      {
        fileNameExtension: 'mp4',
        photoType: photoAccessHelper.PhotoType.VIDEO,
      }
    ];
    // 基于弹窗授权的方式获取媒体库的目标uri。
    let desFileUris: Array<string> = await phAccessHelper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
    // 将来源于应用沙箱的照片内容写入媒体库的目标uri。
    let desFile: fileIo.File = await fileIo.open(desFileUris[0], fileIo.OpenMode.WRITE_ONLY);
    let srcFile: fileIo.File = await fileIo.open(srcFileUri, fileIo.OpenMode.READ_ONLY);
    await fileIo.copyFile(srcFile.fd, desFile.fd);
    fileIo.closeSync(srcFile);
    fileIo.closeSync(desFile);
    console.log(TAG, 'create asset by dialog successfully');
  } catch (err) {
    console.log(TAG, `failed to create asset by dialog successfully errCode is: ${err.code}, ${err.message}`);
  }
}

async function deleteFile(path: string): Promise<boolean> {
  try {
    path = path.replace('file://', '');
    // 检查文件是否存在
    let isExist: boolean = await fileIo.access(path);
    if (!isExist) {
      console.error('File does not exist');
      return true;
    }

    // 删除文件
    await fileIo.unlink(path);
    console.log('File deleted successfully');
    return true;
  } catch (error) {
    console.error(`Delete failed, code: ${error.code}, message: ${error.message}`);
    return false;
  }
}