import { window, display, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface FloatWindowConfig {
  name: string;
  pagePath: string;
  widthVp: number;
  heightVp: number;
  initX?: number;
  initY?: number;
  focusable?: boolean;
}

export class FloatWindowManager {
  private windowStage: window.Window | null = null;
  private context: common.UIAbilityContext;
  private config: FloatWindowConfig;

  constructor(context: common.UIAbilityContext, config: FloatWindowConfig) {
    this.context = context;
    this.config = config;
  }

  public static getPxFromVp(vp: number): number {
    try {
      const displayClass = display.getDefaultDisplaySync();
      return Math.floor(vp * displayClass.densityPixels);
    } catch (err) {
      return Math.floor(vp * 3);
    }
  }

  public async show(): Promise<void> {
    if (this.windowStage) {
      await this.windowStage.showWindow();
      return;
    }

    try {
      this.windowStage = await window.createWindow({
        name: this.config.name,
        windowType: window.WindowType.TYPE_FLOAT,
        ctx: this.context
      });

      await this.windowStage.setUIContent(this.config.pagePath);
      await this.windowStage.setWindowBackgroundColor('#00000000');
      await this.windowStage.setWindowFocusable(this.config.focusable ?? false);
      await this.windowStage.setWindowTouchable(true);

      const widthPx = FloatWindowManager.getPxFromVp(this.config.widthVp);
      const heightPx = FloatWindowManager.getPxFromVp(this.config.heightVp);
      await this.windowStage.resize(widthPx, heightPx);

      const displayClass = display.getDefaultDisplaySync();
      const finalX = this.config.initX ?? (displayClass.width - widthPx - 50);
      const finalY = this.config.initY ?? (displayClass.height / 2);
      await this.windowStage.moveWindowTo(finalX, finalY);

      await this.windowStage.showWindow();

    } catch (exception) {
      const err = exception as BusinessError;
      console.error(`[FloatWindowManager] Init failed: ${JSON.stringify(err)}`);
      if (err.code === 801) {
        this.showPermissionGuideDialog();
      }
    }
  }

  public async hide(): Promise<void> {
    if (this.windowStage) {
      try {
        await this.windowStage.destroyWindow();
        this.windowStage = null;
      } catch (e) {}
    }
  }

  public getWindowRect(): window.Rect {
    return this.windowStage ? this.windowStage.getWindowProperties().windowRect : { left: 0, top: 0, width: 0, height: 0 };
  }

  private showPermissionGuideDialog(): void {
    promptAction.showDialog({
      title: '需要悬浮窗权限',
      message: '请在设置中开启“悬浮窗”权限以保持服务运行。',
      buttons: [{ text: '取消', color: '#666666' }, { text: '去设置', color: '#007DFF' }]
    }).then((resp) => {
      if (resp.index === 1) {
        this.context.startAbility({
          bundleName: 'com.huawei.hmos.settings',
          abilityName: 'com.huawei.hmos.settings.MainAbility',
          uri: 'application_info_entry',
          parameters: { pushParams: this.context.abilityInfo.bundleName }
        });
      }
    });
  }
}