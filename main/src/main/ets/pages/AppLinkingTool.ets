import { HMRouter } from '@hadss/hmrouter';
import promptAction from '@ohos.promptAction';
import pasteboard from '@ohos.pasteboard';
import { URLParserUtil, ParsedQueryParam, ParsedURLResult } from '../utils/URLParserUtil';
import { GlobalContextHolder } from '../utils/GlobalContextHolder';
import { abilityAccessCtrl, common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { customScan, scanCore, scanBarcode } from '@kit.ScanKit';
import { camera } from '@kit.CameraKit';
import { display } from '@kit.ArkUI';
import { PreferencesUtil } from '@pura/harmony-utils';
import { SpKeys } from '../constant/SpKeys';

interface ScanViewControl {
  surfaceId: string;
  width: number;
  height: number;
}

const TAG: string = 'AppLinkingTool';

@HMRouter({ pageUrl: 'appLinkingTool' })
@Component
export struct AppLinkingTool {
  @State inputUrl: string = '';
  @State parsedResult: ParsedURLResult = URLParserUtil.parse('');
  @State isScanning: boolean = false;
  @State isScanVisible: boolean = false;

  private xCompController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private cameraInput: camera.CameraInput | null = null;
  private captureSession: camera.CaptureSession | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private isResourcesReady: boolean = false;

  aboutToAppear(): void {
    this.isScanVisible = PreferencesUtil.getBooleanSync(SpKeys.ENABLE_SCAN_PARSE, false);
    let storedResult: string | undefined = AppStorage.get<string>('appLinkingScannedUrl');
    if (storedResult && storedResult.length > 0) {
      this.inputUrl = storedResult;
      this.parsedResult = URLParserUtil.parse(storedResult);
      AppStorage.set('appLinkingScannedUrl', '');
    }
  }

  aboutToDisappear(): void {
    this.stopCamera();
  }

  private async onScanCancelled(): Promise<void> {
    this.isScanning = false;
    customScan.stop();
    await customScan.release();
    this.stopCamera();
  }

  private stopCamera(): void {
    if (!this.isResourcesReady) {
      return;
    }
    this.isResourcesReady = false;
    try {
      if (this.captureSession) {
        this.captureSession.stop();
        this.captureSession.release();
        this.captureSession = null;
      }
    } catch (err) {
      console.error(TAG, 'release session:', JSON.stringify(err));
    }
    try {
      if (this.cameraInput) {
        this.cameraInput.close();
        this.cameraInput = null;
      }
    } catch (err) {
      console.error(TAG, 'release cameraInput:', JSON.stringify(err));
    }
    try {
      if (this.previewOutput) {
        this.previewOutput.release();
        this.previewOutput = null;
      }
    } catch (err) {
      console.error(TAG, 'release previewOutput:', JSON.stringify(err));
    }
  }

  private doParse(): void {
    this.parsedResult = URLParserUtil.parse(this.inputUrl);
    if (!this.parsedResult.valid && this.inputUrl.trim().length > 0) {
      promptAction.showToast({ message: this.parsedResult.errorMessage || '无效的链接格式', duration: 1500 });
    }
  }

  private clearInput(): void {
    this.inputUrl = '';
    this.parsedResult = URLParserUtil.parse('');
  }

  private async launchDeepLink(): Promise<void> {
    let url: string = this.inputUrl.trim();
    if (url.length === 0) {
      promptAction.showToast({ message: '请输入链接', duration: 1500 });
      return;
    }

    if (!this.parsedResult.valid || this.parsedResult.rawUrl !== url) {
      this.doParse();
    }
    if (!this.parsedResult.valid) {
      return;
    }

    try {
      let context: common.UIAbilityContext | undefined = GlobalContextHolder.getInstance().uiAbilityContext;
      if (!context) {
        promptAction.showToast({ message: '无法获取应用上下文', duration: 1500 });
        return;
      }

      let want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url
      };

      await context.startAbility(want);
      promptAction.showToast({ message: '已发起跳转', duration: 1500 });
    } catch (err) {
      let error: BusinessError = err as BusinessError;
      promptAction.showToast({
        message: '跳转失败: ' + (error.message || '未知错误'),
        duration: 2500
      });
    }
  }

  private startScan(): void {
    this.isScanning = true;
  }

  private async initCameraAndScan(): Promise<void> {
    try {
      let context: common.UIAbilityContext | undefined = GlobalContextHolder.getInstance().uiAbilityContext;
      if (!context) {
        promptAction.showToast({ message: '无法获取上下文', duration: 1500 });
        this.isScanning = false;
        return;
      }

      let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      let appContext: common.ApplicationContext = context.getApplicationContext();
      let tokenId: number = appContext.applicationInfo.accessTokenId;
      let grantStatus: abilityAccessCtrl.GrantStatus = atManager.checkAccessTokenSync(tokenId,
        'ohos.permission.CAMERA');

      if (grantStatus !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        let result = await atManager.requestPermissionsFromUser(context, ['ohos.permission.CAMERA']);
        if (result.authResults[0] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          promptAction.showToast({ message: '需要相机权限', duration: 1500 });
          this.isScanning = false;
          return;
        }
      }

      let cameraManager: camera.CameraManager = camera.getCameraManager(context);
      let cameras: Array<camera.CameraDevice> = cameraManager.getSupportedCameras();
      if (!cameras || cameras.length === 0) {
        promptAction.showToast({ message: '未找到可用相机', duration: 1500 });
        this.isScanning = false;
        return;
      }

      let targetCamera: camera.CameraDevice = cameras[0];
      for (let i = 0; i < cameras.length; i++) {
        if (cameras[i].cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK) {
          targetCamera = cameras[i];
          break;
        }
      }

      this.cameraInput = cameraManager.createCameraInput(targetCamera);
      await this.cameraInput.open();

      let outputCapability: camera.CameraOutputCapability =
        cameraManager.getSupportedOutputCapability(targetCamera);

      if (!outputCapability.previewProfiles || outputCapability.previewProfiles.length === 0) {
        promptAction.showToast({ message: '无可用预览配置', duration: 1500 });
        this.isScanning = false;
        return;
      }
      let previewProfile: camera.Profile = outputCapability.previewProfiles[0];
      this.previewOutput = cameraManager.createPreviewOutput(previewProfile, this.surfaceId);

      this.captureSession = cameraManager.createCaptureSession();
      this.captureSession.beginConfig();
      this.captureSession.addInput(this.cameraInput);
      this.captureSession.addOutput(this.previewOutput);
      this.captureSession.commitConfig();
      await this.captureSession.start();
      this.isResourcesReady = true;

      let defaultDisplay: display.Display = display.getDefaultDisplaySync();
      let viewControl: ScanViewControl = {
        surfaceId: this.surfaceId,
        width: defaultDisplay.width,
        height: defaultDisplay.height
      };

      let scanOptions: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE]
      };
      customScan.init(scanOptions);

      customScan.start(viewControl, (err: BusinessError, results: Array<scanBarcode.ScanResult>) => {
        if (err) {
          console.error(TAG, 'Scan error:', JSON.stringify(err));
          promptAction.showToast({ message: '扫码失败', duration: 1500 });
        } else if (results && results.length > 0) {
          let scannedText: string = results[0].originalValue;
          this.inputUrl = scannedText;
          this.parsedResult = URLParserUtil.parse(scannedText);
          if (this.parsedResult.valid) {
            promptAction.showToast({ message: '扫码成功', duration: 1000 });
          }
        }
        this.onScanCancelled();
      });

    } catch (err) {
      let error: BusinessError = err as BusinessError;
      console.error(TAG, 'initCameraAndScan:', JSON.stringify(err));
      promptAction.showToast({ message: '初始化失败: ' + (error.message || ''), duration: 2000 });
      this.isScanning = false;
      this.stopCamera();
    }
  }

  private copyText(value: string): void {
    try {
      let systemPasteboard = pasteboard.getSystemPasteboard();
      let pasteData = pasteboard.createData('text/plain', value);
      systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: '已复制', duration: 800 });
    } catch (err) {
      promptAction.showToast({ message: '复制失败', duration: 1000 });
    }
  }

  build() {
    if (this.isScanning) {
      this.ScanView();
    } else {
      this.MainView();
    }
  }

  @Builder
  ScanView() {
    Stack() {
      XComponent({
        id: 'cameraScanSurface',
        type: 'surface',
        controller: this.xCompController
      })
        .width('100%')
        .height('100%')
        .onLoad(() => {
          this.surfaceId = this.xCompController.getXComponentSurfaceId();
          this.initCameraAndScan();
        })
        .onDestroy(() => {
          this.stopCamera();
        })

      Column() {
        Text('扫码识别 App Linking')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_on_primary'))
          .margin({ top: 48 })

        Blank()

        Column() {
          Stack() {
            Column()
              .width('70%')
              .height('40%')
              .border({ width: 2, color: '#00FF66', style: BorderStyle.Dashed })
              .borderRadius(16)
              .opacity(0.8)
          }
          .width('100%')
          .height('50%')
          .alignContent(Alignment.Center)
        }
        .width('100%')
        .layoutWeight(1)

        Text('将二维码置于框内自动识别')
          .fontSize(14)
          .fontColor($r('sys.color.font_on_primary'))
          .opacity(0.8)
          .margin({ bottom: 24 })

        Button('取消扫码')
          .fontSize(16)
          .fontColor($r('sys.color.font_on_primary'))
          .backgroundColor('rgba(128, 128, 128, 0.2)')
          .borderRadius(24)
          .height(48)
          .width('60%')
          .margin({ bottom: 56 })
          .onClick(() => {
            this.onScanCancelled();
          })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }

  @Builder
  MainView() {
    Column({ space: 0 }) {
      Column({ space: 12 }) {
        Text('App Linking 深度解析')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_emphasize'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 16 })

        Column() {
          Row() {
            Text('输入链接')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            Text('[清空]')
              .fontSize(11)
              .fontColor($r('sys.color.font_secondary'))
              .fontFamily('monospace')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .border({ width: 1, color: $r('sys.color.comp_background_emphasize'), style: BorderStyle.Dashed })
              .borderRadius(4)
              .onClick(() => this.clearInput())
          }
          .width('100%')
          .padding({ left: 4, right: 4, bottom: 8 })

          TextArea({ text: this.inputUrl, placeholder: '输入 App Linking / 元服务链接...' })
            .height(96)
            .width('100%')
            .fontSize(13)
            .fontFamily('monospace')
            .padding(12)
            .backgroundColor($r('sys.color.comp_background_gray'))
            .borderRadius(8)
            .border({ width: 1, color: $r('sys.color.comp_background_emphasize') })
            .onChange((value: string) => {
              this.inputUrl = value;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Row({ space: 12 }) {
          Button() {
            Text('扫码解析')
              .fontSize(14)
          }
          .height(44)
          .layoutWeight(1)
          .borderRadius(8)
          .visibility(this.isScanVisible ? Visibility.Visible : Visibility.None)
          .onClick(() => this.startScan())

          Button() {
            Text('解析')
              .fontSize(14)
          }
          .height(44)
          .layoutWeight(1)
          .borderRadius(8)
          .onClick(() => this.doParse())

          Button() {
            Text('测试拉起')
              .fontSize(14)
          }
          .height(44)
          .layoutWeight(1)
          .borderRadius(8)
          .onClick(() => this.launchDeepLink())
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .width('100%')

      Divider()
        .color($r('sys.color.comp_background_emphasize'))
        .margin({ top: 12, left: 16, right: 16 })

      if (this.parsedResult.valid) {
        Scroll() {
          Column({ space: 12 }) {
            this.BasicInfoCard()
            this.QueryParamsCard()
            if (this.parsedResult.deepLink) {
              this.DeepLinkCard()
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 24 })
        }
        .scrollBar(BarState.Auto)
        .layoutWeight(1)
        .width('100%')
      } else {
        Column() {
          if (this.inputUrl.trim().length > 0 && this.parsedResult.errorMessage.length > 0) {
            Text(this.parsedResult.errorMessage)
              .fontSize(14)
              .fontColor($r('sys.color.font_emphasize'))
              .fontFamily('monospace')
          } else {
            Text('输入链接后点击「解析」查看拆解结果')
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .opacity(0.5)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }

  @Builder
  BasicInfoCard() {
    Column() {
      Row() {
        Circle({ width: 8, height: 8 })
          .fill($r('sys.color.comp_foreground_primary'))
        Text('基础信息')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_emphasize'))
          .margin({ left: 6 })
      }
      .width('100%')
      .padding({ bottom: 4 })

      Text(this.parsedResult.rawUrl)
        .fontSize(10)
        .fontColor($r('sys.color.font_secondary'))
        .fontFamily('monospace')
        .width('100%')
        .opacity(0.55)
        .padding({ bottom: 8 })
        .wordBreak(WordBreak.BREAK_ALL)

      Column({ space: 0 }) {
        if (this.parsedResult.scheme) {
          this.InfoRow('scheme', this.parsedResult.scheme + '://')
        }
        if (this.parsedResult.hostname) {
          this.InfoRow('host', this.parsedResult.hostname)
        }
        if (this.parsedResult.port) {
          this.InfoRow('port', this.parsedResult.port)
        }
        if (this.parsedResult.pathname) {
          this.InfoRow('path', this.parsedResult.pathname)
        }
        if (this.parsedResult.fragment) {
          this.InfoRow('hash', '#' + this.parsedResult.fragment)
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.background_secondary'))
    .borderRadius(10)
    .border({ width: 1, color: $r('sys.color.comp_background_emphasize') })
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .fontFamily('monospace')
        .constraintSize({ minWidth: 52 })
        .padding({ right: 10 })

      Text(value)
        .fontSize(12)
        .fontColor($r('sys.color.font_primary'))
        .fontFamily('monospace')
        .layoutWeight(1)
        .ellipsisMode(EllipsisMode.END)
        .maxLines(2)

      Text('复制')
        .fontSize(9)
        .fontColor($r('sys.color.font_secondary'))
        .fontFamily('monospace')
        .margin({ left: 6 })
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .border({ width: 0.5, color: $r('sys.color.comp_background_emphasize') })
        .borderRadius(4)
        .onClick(() => this.copyText(value))
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
    .border({
      width: { bottom: 0.5 },
      color: $r('sys.color.comp_background_emphasize')
    })
  }

  @Builder
  QueryParamsCard() {
    Column() {
      Row() {
        Circle({ width: 8, height: 8 })
          .fill($r('sys.color.comp_foreground_primary'))
        Text('Query 参数')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_emphasize'))
          .margin({ left: 6 })
        Blank()
        Text('[' + this.parsedResult.queryParams.length.toString() + ']')
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .fontFamily('monospace')
          .backgroundColor($r('sys.color.comp_background_gray'))
          .borderRadius(10)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      }
      .width('100%')
      .padding({ bottom: 10 })

      if (this.parsedResult.queryParams.length === 0) {
        Text('-- 无查询参数 --')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .opacity(0.5)
          .fontFamily('monospace')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 6, bottom: 6 })
      } else {
        ForEach(this.parsedResult.queryParams, (param: ParsedQueryParam, index: number) => {
          this.QueryParamRow(param, index, this.parsedResult.queryParams.length)
        }, (param: ParsedQueryParam, index: number) => param.key + '_' + index.toString())
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.background_secondary'))
    .borderRadius(10)
    .border({ width: 1, color: $r('sys.color.comp_background_emphasize') })
  }

  @Builder
  QueryParamRow(param: ParsedQueryParam, index: number, total: number) {
    Column() {
      Row() {
        Text(param.key)
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .fontFamily('monospace')
          .fontWeight(FontWeight.Medium)
          .constraintSize({ minWidth: 70, maxWidth: 110 })
          .ellipsisMode(EllipsisMode.END)
          .maxLines(1)
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .backgroundColor($r('sys.color.comp_background_gray'))
          .borderRadius(4)

        Text(' = ')
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .fontFamily('monospace')
          .opacity(0.5)
          .margin({ left: 4, right: 4 })

        Text(param.decodedValue)
          .fontSize(11)
          .fontColor($r('sys.color.font_primary'))
          .fontFamily('monospace')
          .layoutWeight(1)
          .ellipsisMode(EllipsisMode.END)
          .maxLines(1)

        Text('C')
          .fontSize(9)
          .fontColor($r('sys.color.font_secondary'))
          .fontFamily('monospace')
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .backgroundColor($r('sys.color.comp_background_gray'))
          .borderRadius(3)
          .margin({ left: 6 })
          .onClick(() => this.copyText(param.value))
      }
      .width('100%')
      .padding({ top: 7, bottom: 7 })

      if (index < total - 1) {
        Divider()
          .color($r('sys.color.comp_background_emphasize'))
          .strokeWidth(0.5)
      }
    }
    .width('100%')
  }

  @Builder
  DeepLinkCard() {
    Column() {
      Row() {
        Circle({ width: 8, height: 8 })
          .fill($r('sys.color.comp_foreground_primary'))
        Text('deepLink 深层解析')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_emphasize'))
          .margin({ left: 6 })
        Blank()
        if (this.parsedResult.deepLink && this.parsedResult.deepLink.valid) {
          Text('VALID')
            .fontSize(9)
            .fontColor($r('sys.color.font_on_primary'))
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .backgroundColor($r('sys.color.comp_foreground_primary'))
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        } else {
          Text('INVALID')
            .fontSize(9)
            .fontColor($r('sys.color.font_on_primary'))
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .backgroundColor($r('sys.color.font_secondary'))
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        }
      }
      .width('100%')
      .padding({ bottom: 10 })

      if (this.parsedResult.deepLink && this.parsedResult.deepLink.valid) {
        this.DeepLinkContent(this.parsedResult.deepLink)
      } else if (this.parsedResult.deepLink) {
        Column({ space: 6 }) {
          Text(this.parsedResult.deepLink.errorMessage || '解析失败')
            .fontSize(12)
            .fontColor($r('sys.color.font_emphasize'))
            .fontFamily('monospace')
            .width('100%')

          Text('  ' + this.parsedResult.deepLink.rawUrl)
            .fontSize(10)
            .fontColor($r('sys.color.font_secondary'))
            .fontFamily('monospace')
            .maxLines(4)
            .ellipsisMode(EllipsisMode.END)
            .width('100%')
            .opacity(0.8)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.background_secondary'))
    .borderRadius(10)
    .border({ width: 1, color: $r('sys.color.comp_background_emphasize') })
  }

  @Builder
  DeepLinkContent(dl: ParsedURLResult) {
    Column({ space: 0 }) {
      if (dl.scheme) {
        this.InfoRow('scheme', dl.scheme + '://')
      }
      if (dl.hostname) {
        this.InfoRow('host', dl.hostname)
      }
      if (dl.port) {
        this.InfoRow('port', dl.port)
      }
      if (dl.pathname) {
        this.InfoRow('path', dl.pathname)
      }

      if (dl.queryParams.length > 0) {
        Row() {
          Text('子参数')
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
            .fontWeight(FontWeight.Medium)
            .fontFamily('monospace')
            .margin({ top: 8, bottom: 8 })
        }
        .width('100%')

        ForEach(dl.queryParams,
          (param: ParsedQueryParam, subIdx: number) => {
          this.QueryParamRow(param, subIdx, dl.queryParams.length)
        }, (param: ParsedQueryParam, subIdx: number) => 'dl_' + param.key + '_' + subIdx.toString())
      }
    }
    .width('100%')
  }
}
