import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import promptAction from '@ohos.promptAction';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { generateBarcode, scanCore } from '@kit.ScanKit';
import { mediaquery } from '@kit.ArkUI';
import { JSON } from '@kit.ArkTS';
import { PreferencesUtil } from '@pura/harmony-utils';
import { PageNames } from '../constant/PageNames';
import { SpKeys } from '../constant/SpKeys';
import { WallpaperHost } from '../components/WallpaperHost';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';
import { LightSense } from '../utils/LightSense';
import { QrCodeUtil } from '../utils/QrCodeUtil';

const TAG: string = 'QrCodePage';

/** 生成图尺寸（px），越大越清晰；ScanKit 建议范围 [200, 4096] */
const QR_PIXEL: number = 640;
/** 生成图边距（px），ScanKit 范围 [1, 10] */
const QR_MARGIN: number = 4;
/** 文本长度上限（ScanKit 建议最多 512 字符） */
const MAX_TEXT_LENGTH: number = 512;
/** 历史记录条数上限 */
const HISTORY_LIMIT: number = 30;

/** 历史记录项 */
interface QrHistoryItem {
  text: string;
  ts: number;
}

@HMRouter({ pageUrl: PageNames.QR_CODE_PAGE })
@ComponentV2
export struct QrCodePage {
  /** 输入文本 */
  @Local inputText: string = '';
  /** 当前二维码 PixelMap */
  @Local qrPm: image.PixelMap | undefined = undefined;
  /** 生成中（防重复点击） */
  @Local isGenerating: boolean = false;
  /** 保存中（防重复点击） */
  @Local isSaving: boolean = false;
  /** 历史记录（最新在前） */
  @Local historyList: Array<QrHistoryItem> = [];
  /** 沉浸光感：跟随系统深/浅色模式 */
  @Local isDark: boolean = false;
  private themeMq: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    this.initThemeListener();
    this.loadHistory();
  }

  aboutToDisappear(): void {
    this.themeMq?.off('change');
    this.themeMq = null;
  }

  /** 订阅系统深/浅色模式变化，驱动文字阴影等可读性参数 */
  private initThemeListener(): void {
    try {
      this.themeMq = this.getUIContext().getMediaQuery().matchMediaSync('(display-mode: dark)');
      this.isDark = this.themeMq.matches;
      this.themeMq.on('change', (event: mediaquery.MediaQueryResult) => {
        this.isDark = event.matches;
      });
    } catch (e) {
      this.isDark = false;
    }
  }

  // ===================== 历史记录 =====================

  private loadHistory(): void {
    try {
      const raw: string = PreferencesUtil.getStringSync(SpKeys.QR_HISTORY, '');
      if (!raw) {
        this.historyList = [];
        return;
      }
      const list: Array<QrHistoryItem> = JSON.parse(raw) as Array<QrHistoryItem>;
      this.historyList = Array.isArray(list) ? list : [];
    } catch (e) {
      console.error(`[${TAG}] loadHistory failed: ${JSON.stringify(e)}`);
      this.historyList = [];
    }
  }

  private persistHistory(): void {
    try {
      PreferencesUtil.putSync(SpKeys.QR_HISTORY, JSON.stringify(this.historyList));
    } catch (e) {
      console.error(`[${TAG}] persistHistory failed: ${JSON.stringify(e)}`);
    }
  }

  /** 记录一条历史：去重、最新在前、截断上限 */
  private addHistory(text: string): void {
    const trimmed: string = text.trim();
    if (trimmed.length === 0) {
      return;
    }
    const next: Array<QrHistoryItem> = [];
    next.push({ text: trimmed, ts: Date.now() });
    for (const item of this.historyList) {
      if (item.text !== trimmed) {
        next.push(item);
      }
    }
    this.historyList = next.length > HISTORY_LIMIT ? next.slice(0, HISTORY_LIMIT) : next;
    this.persistHistory();
  }

  private removeHistory(index: number): void {
    if (index < 0 || index >= this.historyList.length) {
      return;
    }
    const next: Array<QrHistoryItem> = [];
    for (let i = 0; i < this.historyList.length; i++) {
      if (i !== index) {
        next.push(this.historyList[i]);
      }
    }
    this.historyList = next;
    this.persistHistory();
  }

  private clearHistory(): void {
    this.historyList = [];
    try {
      PreferencesUtil.putSync(SpKeys.QR_HISTORY, '');
    } catch (e) {
      console.error(`[${TAG}] clearHistory failed: ${JSON.stringify(e)}`);
    }
  }

  private formatTime(ts: number): string {
    const d: Date = new Date(ts);
    const pad = (n: number): string => (n < 10 ? '0' + n.toString() : n.toString());
    return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  // ===================== 生成 / 保存 =====================

  /** 生成二维码（内容 = 传入文本，供「生成」按钮与历史点击复用） */
  private async generateQr(text: string): Promise<void> {
    const content: string = text.trim();
    if (content.length === 0) {
      promptAction.showToast({ message: '请先输入或粘贴文本', duration: 1500 });
      return;
    }
    if (content.length > MAX_TEXT_LENGTH) {
      promptAction.showToast({ message: `内容过长，最多 ${MAX_TEXT_LENGTH} 字符`, duration: 2000 });
      return;
    }
    if (this.isGenerating) {
      return;
    }
    this.isGenerating = true;
    try {
      const options: generateBarcode.CreateOptions = {
        scanType: scanCore.ScanType.QR_CODE,
        width: QR_PIXEL,
        height: QR_PIXEL,
        margin: QR_MARGIN,
        level: generateBarcode.ErrorCorrectionLevel.LEVEL_M
      };
      const pm: image.PixelMap = await generateBarcode.createBarcode(content, options);
      // 释放旧图，避免内存累积
      if (this.qrPm) {
        try {
          this.qrPm.release();
        } catch (e) {
          console.error(`[${TAG}] release old pm failed: ${JSON.stringify(e)}`);
        }
      }
      this.qrPm = pm;
      this.addHistory(content);
      promptAction.showToast({ message: '二维码已生成', duration: 1000 });
    } catch (e) {
      console.error(`[${TAG}] generateQr failed: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: '二维码生成失败', duration: 2000 });
    } finally {
      this.isGenerating = false;
    }
  }

  /** 保存二维码到相册：PNG 写入缓存 → 系统创建相册弹窗授权 */
  private async saveToAlbum(): Promise<void> {
    if (!this.qrPm || this.isSaving) {
      return;
    }
    this.isSaving = true;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const srcPath: string = await QrCodeUtil.savePngToCache(context, this.qrPm);
      const phAccessHelper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      const srcFileUris: Array<string> = [srcPath];
      const photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [{
        fileNameExtension: 'png',
        photoType: photoAccessHelper.PhotoType.IMAGE
      }];
      const desFileUris: Array<string> = await phAccessHelper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
      const desFile: fileIo.File = await fileIo.open(desFileUris[0], fileIo.OpenMode.WRITE_ONLY);
      const srcFile: fileIo.File = await fileIo.open(srcPath, fileIo.OpenMode.READ_ONLY);
      await fileIo.copyFile(srcFile.fd, desFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(desFile);
      promptAction.showToast({ message: '二维码已保存到相册', duration: 1500 });
    } catch (e) {
      console.error(`[${TAG}] saveToAlbum failed: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: '保存失败', duration: 1500 });
    } finally {
      this.isSaving = false;
    }
  }

  // ===================== UI =====================

  build() {
    // 全局壁纸宿主：背景透明，任意页面继承主页沉浸光感壁纸
    WallpaperHost() {
      Scroll() {
        Column({ space: 12 }) {
          // ---------- 标题栏 ----------
          Row() {
            Stack() {
              Image($r('app.media.back_arrow'))
                .width(20)
                .height(20)
                .objectFit(ImageFit.Contain)
                .fillColor($r('sys.color.font_primary'))
            }
            .width(38)
            .height(38)
            .borderRadius(19)
            // 返回按钮玻璃圆底：任意壁纸背景下都清晰可见
            .backgroundColor(this.isDark ? 'rgba(255, 255, 255, 0.16)' : 'rgba(255, 255, 255, 0.9)')
            .border({ width: 1, color: ImmersiveStyles.cardOuterRim(this.isDark) })
            .shadow({ radius: 8, color: ImmersiveStyles.cardShadow(this.isDark), offsetX: 0, offsetY: 2 })
            .onClick(() => {
              HMRouterMgr.pop();
            })

            Column({ space: 2 }) {
              Text('二维码生成')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.font_emphasize'))
                // 深色/浅色模式可读性：阴影颜色与文字相反
                .textShadow(ImmersiveStyles.textShadow(this.isDark))
              Text('粘贴文本，一键生成可保存的二维码')
                .fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
                .textShadow(ImmersiveStyles.textShadow(this.isDark))
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 })
          }
          .width('100%')

          // ---------- 输入卡片 ----------
          GlassCard() {
            Column({ space: 10 }) {
              Row() {
                Text('文本内容')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('sys.color.font_primary'))
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))
                Blank()
                Text(`${this.inputText.length}/${MAX_TEXT_LENGTH}`)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_secondary'))
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))
                  .fontFamily('monospace')
              }
              .width('100%')

              TextArea({ text: this.inputText, placeholder: '粘贴或输入文本，生成二维码…' })
                .height(104)
                .width('100%')
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
                .placeholderFont({ size: 13 })
                .placeholderColor($r('sys.color.font_secondary'))
                .backgroundColor('rgba(128, 128, 128, 0.12)')
                .borderRadius(10)
                .padding(10)
                .onChange((value: string) => {
                  this.inputText = value;
                })

              Row({ space: 8 }) {
                Button() {
                  Row({ space: 4 }) {
                    Text('清空')
                      .fontSize(14)
                  }
                }
                .height(40)
                .layoutWeight(1)
                .backgroundColor($r('sys.color.comp_background_gray'))
                .fontColor($r('sys.color.font_secondary'))
                .onClick(() => {
                  this.inputText = '';
                })

                Button() {
                  Row({ space: 4 }) {
                    Text(this.isGenerating ? '生成中…' : '生成二维码')
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                  }
                }
                .height(40)
                .layoutWeight(1.5)
                .enabled(!this.isGenerating)
                .onClick(() => this.generateQr(this.inputText))
              }
              .width('100%')
            }
            .width('100%')
            .padding(12)
          }

          // ---------- 二维码预览卡片 ----------
          if (this.qrPm) {
            GlassCard() {
              Column({ space: 12 }) {
                // 白色底承载二维码，保证任意背景下扫码清晰
                Stack() {
                  Image(this.qrPm)
                    .width(230)
                    .height(230)
                    .objectFit(ImageFit.Contain)
                    .borderRadius(8)
                }
                .width(246)
                .height(246)
                .backgroundColor('#FFFFFF')
                .borderRadius(12)
                .shadow({ radius: 12, color: 'rgba(0, 0, 0, 0.25)', offsetX: 0, offsetY: 3 })

                Text('扫一扫即可识别内容')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))

                Row({ space: 8 }) {
                  Button() {
                    Row({ space: 6 }) {
                      Image($r('app.media.export'))
                        .width(16)
                        .height(16)
                        .objectFit(ImageFit.Contain)
                      Text('保存到相册')
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                    }
                  }
                  .height(42)
                  .layoutWeight(1)
                  .enabled(!this.isSaving)
                  .onClick(() => this.saveToAlbum())

                  Button() {
                    Row({ space: 4 }) {
                      Text('重新生成')
                        .fontSize(14)
                    }
                  }
                  .height(42)
                  .layoutWeight(1)
                  .backgroundColor($r('sys.color.comp_background_gray'))
                  .fontColor($r('sys.color.font_secondary'))
                  .onClick(() => this.generateQr(this.inputText))
                }
                .width('100%')
              }
              .width('100%')
              .padding(12)
            }
          }

          // ---------- 历史记录卡片 ----------
          GlassCard() {
            Column({ space: 8 }) {
              Row() {
                Circle({ width: 8, height: 8 })
                  .fill($r('sys.color.comp_foreground_primary'))
                Text('历史记录')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('sys.color.font_emphasize'))
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))
                  .margin({ left: 6 })
                Text(`(${this.historyList.length})`)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_secondary'))
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))
                  .fontFamily('monospace')
                  .margin({ left: 4 })
                Blank()
                Text('清空')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .border({ width: 1, color: ImmersiveStyles.cardDivider(this.isDark) })
                  .borderRadius(6)
                  .visibility(this.historyList.length > 0 ? Visibility.Visible : Visibility.None)
                  .onClick(() => {
                    this.clearHistory();
                    promptAction.showToast({ message: '历史已清空', duration: 1000 });
                  })
              }
              .width('100%')
              .padding({ bottom: 4 })

              if (this.historyList.length === 0) {
                Text('暂无历史，生成过的文本会出现在这里，点击可快速切换')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 10, bottom: 10 })
                  .opacity(0.8)
              } else {
                ForEach(this.historyList, (item: QrHistoryItem, index: number) => {
                  Row() {
                    Text(this.formatTime(item.ts))
                      .fontSize(10)
                      .fontColor($r('sys.color.font_secondary'))
                      .textShadow(ImmersiveStyles.textShadow(this.isDark))
                      .fontFamily('monospace')
                      .constraintSize({ minWidth: 40 })
                    Text(item.text)
                      .fontSize(13)
                      .fontColor($r('sys.color.font_primary'))
                      .textShadow(ImmersiveStyles.textShadow(this.isDark))
                      .maxLines(1)
                      .ellipsisMode(EllipsisMode.END)
                      .layoutWeight(1)
                      .margin({ left: 8, right: 8 })
                    Text('✕')
                      .fontSize(12)
                      .fontColor($r('sys.color.font_secondary'))
                      .textShadow(ImmersiveStyles.textShadow(this.isDark))
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .borderRadius(4)
                      .backgroundColor('rgba(128, 128, 128, 0.15)')
                      .onClick(() => this.removeHistory(index))
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 9, bottom: 9 })
                  .borderRadius(8)
                  .backgroundColor('rgba(128, 128, 128, 0.10)')
                  // 点击历史：回填输入框并快速生成
                  .onClick(() => {
                    this.inputText = item.text;
                    this.generateQr(item.text);
                  })
                }, (item: QrHistoryItem, index: number) => item.ts.toString() + '_' + index.toString())
              }
            }
            .width('100%')
            .padding(12)
          }

          // 底部呼吸空间
          Row()
            .height(16)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        // [Pad大屏适配] 限制最大宽度
        .constraintSize({ maxWidth: 800 })
        .padding({ left: 16, right: 16, top: 8, bottom: 24 })
      }
      .scrollBar(BarState.Auto)
      .width('100%')
      .height('100%')
      // 内容不足一屏时 Scroll 默认垂直居中，改为顶部对齐
      .align(Alignment.Top)
    }
  }
}

/**
 * 沉浸光感玻璃卡片：毛玻璃基底 + 光感渐变 + rim 亮边 + 柔和投影，
 * 与主页工具箱卡片使用同一套视觉配方，背景透出壁纸。
 */
@ComponentV2
struct GlassCard {
  /** 卡片内容（渲染在玻璃层之上） */
  @BuilderParam content: () => void;
  @Local isDark: boolean = false;
  private themeMq: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    try {
      this.themeMq = this.getUIContext().getMediaQuery().matchMediaSync('(display-mode: dark)');
      this.isDark = this.themeMq.matches;
      this.themeMq.on('change', (event: mediaquery.MediaQueryResult) => {
        this.isDark = event.matches;
      });
    } catch (e) {
      this.isDark = false;
    }
  }

  aboutToDisappear(): void {
    this.themeMq?.off('change');
    this.themeMq = null;
  }

  build() {
    // 玻璃样式直接作用于内容容器（同 SettingGroup 的单节点配方）：
    // 内容决定高度，毛玻璃基底 + 光感渐变 + rim 亮边 + 柔和投影叠加在同一节点，
    // 避免多层 Stack 的 height('100%') 在无高度约束的 Scroll 中撑满整个视口
    Column() {
      this.content()
    }
    .width('100%')
    .borderRadius(ImmersiveStyles.cardRadius())
    .clip(true)
    .backgroundColor(ImmersiveStyles.cardBase(this.isDark))
    .backdropBlur(ImmersiveStyles.cardBlurRadius())
    .linearGradient({
      angle: 135,
      colors: ImmersiveStyles.cardSurfaceColors(this.isDark)
    })
    .border({ width: ImmersiveStyles.cardRimWidth(), color: ImmersiveStyles.cardOuterRim(this.isDark) })
    // 点光源光效（与工具箱卡片一致）
    .visualEffect(LightSense.lightVisualEffect())
    // 柔和投影（依据圆角边界生成）
    .shadow({
      radius: 14,
      color: ImmersiveStyles.cardShadow(this.isDark),
      offsetX: 0,
      offsetY: 4
    })
  }
}
