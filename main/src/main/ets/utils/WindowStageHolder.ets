import { window } from '@kit.ArkUI';

/**
 * 主窗口 WindowStage 的进程内持有者。
 *
 * 游戏页需要把「横幅广告」放到一个独立子窗口里，避免它出现在游戏页的
 * ArkUI 布局树中（否则开启“显示布局边界”会看到一个广告容器）。
 * 子窗口只能由 WindowStage 创建，所以在 MainAbility.onWindowStageCreate 里存一份。
 */
export class WindowStageHolder {
  private static stage: window.WindowStage | null = null;

  public static set(stage: window.WindowStage): void {
    WindowStageHolder.stage = stage;
  }

  public static get(): window.WindowStage | null {
    return WindowStageHolder.stage;
  }
}
