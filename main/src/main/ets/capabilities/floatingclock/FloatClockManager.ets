import { window, display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 悬浮时钟管理器 (Singleton)
 * 适配 API 12, Strict ArkTS
 * 修复了窗口尺寸过小的问题
 */
interface ClockParams {
  widthVp: number;
  heightVp: number;
  posX: number;
  posY: number;

  // ⚠️ 请确保此路径与 main_pages.json 中注册的一致！
  pagePath: string;
}

export class FloatClockManager {
  private static windowClass: window.Window | null = null;
  private static readonly WINDOW_NAME = 'HyperEntropy_Float_Clock';
  private static readonly TAG = '[FloatClock_Manager]';

  // 基础配置（单位：vp），稍后会自动转为 px
  private static readonly BASE_CONFIG: ClockParams = {
    widthVp: 200,    // 足够容纳 HH:mm:ss.SSS
    heightVp: 50,
    posX: 100,
    posY: 200,
    // ⚠️ 请确保此路径与 main_pages.json 中注册的一致！
    pagePath: 'capabilities/floatingclock/FloatClockPage'
  };

  /**
   * 显示系统悬浮窗
   */
  static async show(context: common.UIAbilityContext): Promise<void> {
    console.info(`${FloatClockManager.TAG} show() called.`);

    // 1. 防止重复创建
    if (FloatClockManager.windowClass) {
      try {
        await FloatClockManager.windowClass.showWindow();
        return;
      } catch (err) {
        FloatClockManager.windowClass = null;
      }
    }

    // 2. 配置窗口参数
    let windowConfig: window.Configuration = {
      name: FloatClockManager.WINDOW_NAME,
      windowType: window.WindowType.TYPE_FLOAT,
      ctx: context
    };

    try {
      // 3. 创建窗口
      FloatClockManager.windowClass = await window.createWindow(windowConfig);
      const win = FloatClockManager.windowClass;

      // 4. 计算正确的物理像素尺寸 (Fix: 解决窗口过小问题)
      // 获取默认屏幕的显示属性
      let density = 1.5; // 保底默认值
      try {
        const d = display.getDefaultDisplaySync();
        density = d.densityPixels;
      } catch (e) {
        console.error(`${FloatClockManager.TAG} Get display failed, using default density.`);
      }

      const widthPx = FloatClockManager.BASE_CONFIG.widthVp * density;
      const heightPx = FloatClockManager.BASE_CONFIG.heightVp * density;

      // 5. 设置窗口大小和位置
      await win.resize(widthPx, heightPx);
      await win.moveWindowTo(FloatClockManager.BASE_CONFIG.posX, FloatClockManager.BASE_CONFIG.posY);

      // 6. 加载 UI
      await win.setUIContent(FloatClockManager.BASE_CONFIG.pagePath);

      // 7. 设置窗口属性
      await win.setWindowBackgroundColor('#00000000'); // 背景全透明
      await win.setWindowFocusable(false); // 不抢焦点
      await win.setWindowTouchable(true);  // 允许触摸

      // 8. 显示
      await win.showWindow();
      console.info(`${FloatClockManager.TAG} Window created successfully.`);

    } catch (exception) {
      const err = exception as BusinessError;
      console.error(`${FloatClockManager.TAG} ❌ FATAL ERROR. Code: ${err.code}, Message: ${err.message}`);
    }
  }

  /**
   * 销毁悬浮窗
   */
  static async destroy(): Promise<void> {
    if (FloatClockManager.windowClass) {
      try {
        await FloatClockManager.windowClass.destroyWindow();
        FloatClockManager.windowClass = null;
      } catch (err) {
        console.error(`${FloatClockManager.TAG} Failed to destroy window.`);
      }
    }
  }
}