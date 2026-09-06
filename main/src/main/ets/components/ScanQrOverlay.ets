import promptAction from '@ohos.promptAction';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera } from '@kit.CameraKit';
import { display } from '@kit.ArkUI';
import { customScan, scanCore, scanBarcode } from '@kit.ScanKit';
import { GlobalContextHolder } from '../utils/GlobalContextHolder';

const TAG: string = 'ScanQrOverlay';

/** 扫码预览窗口参数（surfaceId + 窗口尺寸） */
interface ScanViewControl {
  surfaceId: string;
  width: number;
  height: number;
}

/**
 * 全屏扫码浮层：与 AppLinkingTool 的扫码交互一致（相机权限申请 → XComponent 预览 →
 * customScan 识别二维码），扫到后把文本回传父页面。
 * 供「App Linking 解析」同类工具复用（H5Page 等）。
 */
@ComponentV2
export struct ScanQrOverlay {
  /** 顶部标题 */
  @Param title: string = '扫码识别链接';
  /** 扫码成功：回传识别文本（已停止并释放相机） */
  @Event onResult: (text: string) => void = (text: string) => {
  };
  /** 用户取消 / 初始化失败 */
  @Event onCancel: () => void = () => {
  };

  private xCompController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private cameraInput: camera.CameraInput | null = null;
  private captureSession: camera.CaptureSession | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private resourcesReady: boolean = false;
  /** 资源是否已释放（防止取消/成功/销毁路径重复释放） */
  private released: boolean = false;

  aboutToDisappear(): void {
    this.releaseAll();
  }

  /** 统一释放扫描与相机资源（幂等） */
  private releaseAll(): void {
    if (this.released) {
      return;
    }
    this.released = true;
    try {
      customScan.stop();
    } catch (err) {
      console.error(`[${TAG}] stop customScan: ${JSON.stringify(err)}`);
    }
    try {
      customScan.release();
    } catch (err) {
      console.error(`[${TAG}] release customScan: ${JSON.stringify(err)}`);
    }
    if (this.resourcesReady) {
      this.resourcesReady = false;
      try {
        if (this.captureSession) {
          this.captureSession.stop();
          this.captureSession.release();
          this.captureSession = null;
        }
      } catch (err) {
        console.error(`[${TAG}] release session: ${JSON.stringify(err)}`);
      }
      try {
        if (this.cameraInput) {
          this.cameraInput.close();
          this.cameraInput = null;
        }
      } catch (err) {
        console.error(`[${TAG}] close cameraInput: ${JSON.stringify(err)}`);
      }
      try {
        if (this.previewOutput) {
          this.previewOutput.release();
          this.previewOutput = null;
        }
      } catch (err) {
        console.error(`[${TAG}] release previewOutput: ${JSON.stringify(err)}`);
      }
    }
  }

  private async initCameraAndScan(): Promise<void> {
    try {
      const context: common.UIAbilityContext | undefined = GlobalContextHolder.getInstance().uiAbilityContext;
      if (!context) {
        promptAction.showToast({ message: '无法获取应用上下文', duration: 1500 });
        this.onCancel();
        return;
      }

      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const appContext: common.ApplicationContext = context.getApplicationContext();
      const tokenId: number = appContext.applicationInfo.accessTokenId;
      const grantStatus: abilityAccessCtrl.GrantStatus = atManager.checkAccessTokenSync(tokenId,
        'ohos.permission.CAMERA');

      if (grantStatus !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        const result = await atManager.requestPermissionsFromUser(context, ['ohos.permission.CAMERA']);
        if (result.authResults[0] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          promptAction.showToast({ message: '需要相机权限', duration: 1500 });
          this.onCancel();
          return;
        }
      }

      const cameraManager: camera.CameraManager = camera.getCameraManager(context);
      const cameras: Array<camera.CameraDevice> = cameraManager.getSupportedCameras();
      if (!cameras || cameras.length === 0) {
        promptAction.showToast({ message: '未找到可用相机', duration: 1500 });
        this.onCancel();
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

      const outputCapability: camera.CameraOutputCapability =
        cameraManager.getSupportedOutputCapability(targetCamera);
      if (!outputCapability.previewProfiles || outputCapability.previewProfiles.length === 0) {
        promptAction.showToast({ message: '无可用预览配置', duration: 1500 });
        this.onCancel();
        return;
      }
      const previewProfile: camera.Profile = outputCapability.previewProfiles[0];
      this.previewOutput = cameraManager.createPreviewOutput(previewProfile, this.surfaceId);

      this.captureSession = cameraManager.createCaptureSession();
      this.captureSession.beginConfig();
      this.captureSession.addInput(this.cameraInput);
      this.captureSession.addOutput(this.previewOutput);
      this.captureSession.commitConfig();
      await this.captureSession.start();
      this.resourcesReady = true;

      const defaultDisplay: display.Display = display.getDefaultDisplaySync();
      const viewControl: ScanViewControl = {
        surfaceId: this.surfaceId,
        width: defaultDisplay.width,
        height: defaultDisplay.height
      };

      const scanOptions: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE]
      };
      customScan.init(scanOptions);

      customScan.start(viewControl, (err: BusinessError, results: Array<scanBarcode.ScanResult>) => {
        if (err) {
          console.error(`[${TAG}] Scan error: ${JSON.stringify(err)}`);
          promptAction.showToast({ message: '扫码失败', duration: 1500 });
          this.releaseAll();
          this.onCancel();
        } else if (results && results.length > 0) {
          const scannedText: string = results[0].originalValue;
          this.releaseAll();
          this.onResult(scannedText);
        }
      });
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error(`[${TAG}] initCameraAndScan: ${JSON.stringify(err)}`);
      promptAction.showToast({ message: '初始化失败: ' + (error.message || ''), duration: 2000 });
      this.releaseAll();
      this.onCancel();
    }
  }

  private cancelScan(): void {
    this.releaseAll();
    this.onCancel();
  }

  build() {
    Stack() {
      XComponent({
        id: 'scanQrOverlaySurface',
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
          this.releaseAll();
        })

      Column() {
        Text(this.title)
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
            this.cancelScan();
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
}
