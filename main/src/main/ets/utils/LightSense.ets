import { hdsEffect } from '@kit.UIDesignKit';
import { uiMaterial } from '@kit.ArkUI';
import { uiEffect } from '@kit.ArkGraphics2D';
import { deviceInfo } from '@kit.BasicServicesKit';
import { PreferencesUtil } from '@pura/harmony-utils';
import { SpKeys } from '../constant/SpKeys';

/**
 * 全局光感档位的可观察状态（V2）。
 *
 * `@ObservedV2 + @Trace` 是 ArkUI V2 推荐的跨组件刷新方式：
 * 任何在 build 期间读取 `lightSenseState.level` 的组件都会在档位变化时自动重渲染，
 * 从而让卡片/按钮/Tab 栏的手绘光感参数即时跟随设置页滑杆，不需要重启或切页。
 */
@ObservedV2
export class LightSenseState {
  @Trace level: number = 3;
}

/** 全局单例：所有沉浸光感表面共享同一档位 */
export const lightSenseState: LightSenseState = new LightSenseState();

/**
 * 全局光感档位（沉浸光感强度统一控制）。
 *
 * 档位：0=关闭 1=柔和 2=标准 3=精致
 * 各表面（卡片、Tab 栏、点光源光效）统一按档位取值。
 *
 * 兼容性（重要）：
 * - `hdsEffect` 自 API 20（HarmonyOS 6.0.0）才存在；API 20 以下只走
 *   `backgroundBlurStyle` + 透明度兜底。
 * - 本类所有新 API 的调用都先做 **版本 + 系统能力 + try/catch** 三重保护，
 *   在老设备（如 5.0.1）上**绝不执行**不存在的符号，避免
 *   `undefined is not a constructor` 之类的直接 crash。
 * - 不要在本文件的模块顶层（字段初始化 / import 副作用）里执行新 API，
 *   老系统导入时只会得到 undefined，真正调用时才会崩。
 *
 * 持久化：SpKeys.LIGHT_SENSE；内存同步：AppStorage['LightSense']。
 */
export class LightSense {
  static readonly LEVEL_OFF: number = 0;
  static readonly LEVEL_GENTLE: number = 1;
  static readonly LEVEL_SMOOTH: number = 2;
  static readonly LEVEL_EXQUISITE: number = 3;
  static readonly LEVEL_NAMES: Array<string> = ['关闭', '柔和', '标准', '精致'];

  /** 能力探测结果缓存：避免每次 build 都去访问系统接口 */
  private static hdsEffectChecked: boolean = false;
  private static hdsEffectSupported: boolean = false;
  private static uiMaterialChecked: boolean = false;
  private static uiMaterialSupported: boolean = false;
  /** 是否已从持久化恢复过档位 */
  private static restored: boolean = false;

  /** 当前系统 SDK API 版本（异常时返回 0，保证后续判断全部走兜底） */
  static sdkApiVersion(): number {
    try {
      return deviceInfo.sdkApiVersion;
    } catch (e) {
      return 0;
    }
  }

  /** 读取当前档位（首次调用时从持久化恢复；返回 @Trace 属性以建立响应式依赖） */
  static getLevel(): number {
    if (!LightSense.restored) {
      LightSense.restored = true;
      try {
        lightSenseState.level = PreferencesUtil.getNumberSync(SpKeys.LIGHT_SENSE, LightSense.LEVEL_EXQUISITE);
      } catch (e) {
        lightSenseState.level = LightSense.LEVEL_EXQUISITE;
      }
    }
    return lightSenseState.level;
  }

  /** 设置档位：持久化 + 可观察状态广播（卡片/按钮/Tab 栏自动重渲染） */
  static setLevel(value: number): void {
    const level = Math.min(Math.max(Math.round(value), 0), 3);
    LightSense.restored = true;
    try {
      PreferencesUtil.putSync(SpKeys.LIGHT_SENSE, level);
    } catch (e) {
      console.error(`[LightSense] put failed: ${JSON.stringify(e)}`);
    }
    lightSenseState.level = level;
    AppStorage.setOrCreate<number>('LightSense', level);
  }

  /** 档位名称 */
  static levelName(level: number): string {
    const i = Math.min(Math.max(Math.round(level), 0), 3);
    return LightSense.LEVEL_NAMES[i];
  }

  /**
   * 是否支持 HDS 视觉特效（点光源/流光）。
   * `hdsEffect` 自 API 20 起提供；API 20 以下直接返回 false，绝不触碰该命名空间。
   */
  static supportsHdsEffect(): boolean {
    if (LightSense.hdsEffectChecked) {
      return LightSense.hdsEffectSupported;
    }
    LightSense.hdsEffectChecked = true;
    if (LightSense.sdkApiVersion() < 20) {
      LightSense.hdsEffectSupported = false;
      return false;
    }
    try {
      LightSense.hdsEffectSupported = canIUse('SystemCapability.UIDesign.HDSComponent.Core');
    } catch (e) {
      LightSense.hdsEffectSupported = false;
    }
    return LightSense.hdsEffectSupported;
  }

  /**
   * 是否支持官方沉浸式系统材质（uiMaterial / systemMaterial，API 26+）。
   * 低版本返回 false，调用方必须回退到手绘玻璃配方。
   */
  static supportsSystemMaterial(): boolean {
    if (LightSense.uiMaterialChecked) {
      return LightSense.uiMaterialSupported;
    }
    LightSense.uiMaterialChecked = true;
    if (LightSense.sdkApiVersion() < 26) {
      LightSense.uiMaterialSupported = false;
      return false;
    }
    try {
      // API 26 才存在该命名空间；低版本在上一行已经短路返回
      LightSense.uiMaterialSupported = uiMaterial.isImmersiveMaterialSupported();
    } catch (e) {
      LightSense.uiMaterialSupported = false;
    }
    return LightSense.uiMaterialSupported;
  }

  /**
   * 官方沉浸式系统材质（底部 TabBar 背板）。
   * 仅在 API 26+ 且系统支持时返回对象；否则返回 undefined，由调用方走手绘玻璃兜底。
   * 必须在 Tabs 的底部 TabBar（barPosition=End 的横向 Tabs）子树中调用才生效。
   */
  static tabSystemMaterial(level: number): uiMaterial.ImmersiveMaterial | undefined {
    if (level <= LightSense.LEVEL_OFF || !LightSense.supportsSystemMaterial()) {
      return undefined;
    }
    try {
      // 官方建议：底部页签用较薄的材质（THIN / ULTRA_THIN），保持背景通透
      const style: uiMaterial.ImmersiveStyle =
        level <= LightSense.LEVEL_GENTLE ? uiMaterial.ImmersiveStyle.ULTRA_THIN : uiMaterial.ImmersiveStyle.THIN;
      return new uiMaterial.ImmersiveMaterial({
        style: style,
        // 文字使用系统可反色资源时，薄材质可自动反色，避免浅色壁纸上看不清
        colorInvert: true,
        // 系统材质自带阴影在悬浮栏容器里是按矩形裁剪的，会在圆角胶囊外
        // 露出一块直角灰边；关掉后由容器/页面自行控制阴影。
        applyShadow: false,
        interactive: true,
        // 精致档开启光感交互反馈（手指触摸时有流光跟随）
        lightEffect: level >= LightSense.LEVEL_EXQUISITE ? {} : undefined
      });
    } catch (e) {
      console.error(`[LightSense] tabSystemMaterial failed: ${JSON.stringify(e)}`);
      return undefined;
    }
  }

  /** 卡片/按钮毛玻璃档位（backgroundBlurStyle 用）：0=无模糊 1=薄 2=常规 3=薄（更通透） */
  static cardBlurStyle(level: number): BlurStyle {
    if (level <= LightSense.LEVEL_OFF) {
      return BlurStyle.NONE;
    }
    if (level <= LightSense.LEVEL_GENTLE) {
      return BlurStyle.COMPONENT_THIN;
    }
    if (level <= LightSense.LEVEL_SMOOTH) {
      return BlurStyle.COMPONENT_REGULAR;
    }
    // 精致档：玻璃要“通透 + 边缘折射”，模糊反而不能太重，
    // 由 ImmersiveStyles 的 rim 亮边 + 点光源承担光感（此前这里返回 NONE 是 bug：
    // 精致档卡片会完全没有毛玻璃，背景一花就变成一块半透明贴片）。
    return BlurStyle.COMPONENT_THIN;
  }

  /** 点光源光效（官方视觉特效）：标准档柔和、精致档明亮；低版本/关闭档返回 undefined */
  static pointLightEffect(level: number): hdsEffect.PointLightEffect | undefined {
    if (level < LightSense.LEVEL_SMOOTH || !LightSense.supportsHdsEffect()) {
      return undefined;
    }
    if (level >= LightSense.LEVEL_EXQUISITE) {
      // 精致：明亮光源照亮卡片边缘（折射感），光感明显
      return {
        sourceType: hdsEffect.PointLightSourceType.BRIGHT,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
        options: {
          color: '#FFFFFF',
          intensity: 1.0,
          height: 80,
          bloom: 1.0
        }
      };
    }
    return {
      sourceType: hdsEffect.PointLightSourceType.SOFT,
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
      options: {
        color: '#FFFFFF',
        intensity: 0.5,
        height: 60,
        bloom: 0.5
      }
    };
  }

  /**
   * 按当前档位构建官方点光源 visualEffect。
   * **老系统必须返回空效果而不是抛异常**：空效果用 API 12 就有的
   * `uiEffect.createEffect()` 构造，不需要 hdsEffect 命名空间。
   */
  static lightVisualEffect(): VisualEffect {
    if (!LightSense.supportsHdsEffect()) {
      return uiEffect.createEffect();
    }
    try {
      const builder = new hdsEffect.HdsEffectBuilder();
      const pl = LightSense.pointLightEffect(LightSense.getLevel());
      if (pl) {
        builder.pointLight(pl);
      }
      return builder.buildEffect();
    } catch (e) {
      // 某些设备声明了 syscap 但实现缺失，同样安全降级为空效果
      console.error(`[LightSense] lightVisualEffect failed: ${JSON.stringify(e)}`);
      return uiEffect.createEffect();
    }
  }
}
