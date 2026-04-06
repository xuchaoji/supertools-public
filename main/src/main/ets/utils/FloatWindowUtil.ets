import { common } from '@kit.AbilityKit';
import { FloatWindowManager } from '../utils/FloatWindowManager'; // 替换为实际路径

export class FloatWindowUtil {
  private static manager: FloatWindowManager | null = null;
  private static context: common.UIAbilityContext;

  public static init(context: common.UIAbilityContext): void {
    FloatWindowUtil.context = context;
  }

  public static async showFloatWindow(): Promise<void> {
    if (!FloatWindowUtil.context) return;

    if (!FloatWindowUtil.manager) {
      FloatWindowUtil.manager = new FloatWindowManager(FloatWindowUtil.context, {
        name: "FloatBallWindow",
        pagePath: "pages/FloatBallPage", // 确保路径对应你的路由配置
        widthVp: 60,
        heightVp: 30
      });
    }
    await FloatWindowUtil.manager.show();
  }

  public static async destroyFloatWindow(): Promise<void> {
    if (FloatWindowUtil.manager) {
      await FloatWindowUtil.manager.hide();
      FloatWindowUtil.manager = null;
    }
  }
}