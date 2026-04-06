import { common } from '@kit.AbilityKit';
import { FloatWindowManager } from '../../utils/FloatWindowManager';
import { window } from '@kit.ArkUI';

export class StressFloatWindowManager {
  private static instance: StressFloatWindowManager;
  private manager: FloatWindowManager | null = null;

  private constructor() {}

  public static getInstance(): StressFloatWindowManager {
    if (!StressFloatWindowManager.instance) {
      StressFloatWindowManager.instance = new StressFloatWindowManager();
    }
    return StressFloatWindowManager.instance;
  }

  public async show(context: common.UIAbilityContext): Promise<void> {
    if (!this.manager) {
      this.manager = new FloatWindowManager(context, {
        name: 'stress_capsule_float',
        pagePath: 'capabilities/floatingstress/StressCapsulePage', // 确保路径对应你的路由配置
        widthVp: 240,
        heightVp: 64,
        initX: 100,
        initY: 300
      });
    }
    await this.manager.show();
  }

  public async hide(): Promise<void> {
    if (this.manager) {
      await this.manager.hide();
    }
  }

  public getWindowRect(): window.Rect {
    return this.manager ? this.manager.getWindowRect() : { left: 0, top: 0, width: 0, height: 0 };
  }
}