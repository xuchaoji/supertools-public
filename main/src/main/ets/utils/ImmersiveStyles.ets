/**
 * 沉浸光感视觉参数（参考 HarmonyOS 官方《沉浸光感》适配规范）。
 *
 * 核心思路：通过「毛玻璃基底 + 表面光感渐变 + 边缘高光 + 柔和投影」四层
 * 模拟光在材质表面的折射与漫反射，并按系统深/浅色模式提供两套参数，
 * 保证深色模式下不出现浅色玻璃发白发灰、浅色模式下不出现死黑脏边的问题。
 *
 * 官方 API 使用边界（重要）：
 * - `systemMaterial`（API 26）只对「Navigation/NavDestination 标题栏」或
 *   「横向 Tabs + BarPosition.End 的底部 TabBar」生效；页面内容区的卡片
 *   不在生效范围内，因此卡片继续使用官方推荐的兜底方案
 *   `backgroundBlurStyle` + backgroundColor/border/shadow，而不是硬套材质。
 * - `hdsEffect`（API 20）统一由 LightSense 做版本/能力保护，本文件不直接引用。
 */
import { LightSense } from './LightSense';

export class ImmersiveStyles {
  // ===================== 卡片（Card） =====================

  /**
   * 卡片基底色（按全局光感档位取值）：光感是"通透玻璃 + 边缘折射"，不是磨砂雾面。
   * 基底只做极淡着色，让背景/壁纸清晰透出；光感由点光源/亮边承担。
   * 关闭档才近乎纯色。
   */
  static cardBase(isDark: boolean): string {
    const lv = LightSense.getLevel();
    if (lv <= LightSense.LEVEL_OFF) {
      return isDark ? 'rgba(28, 28, 32, 0.94)' : 'rgba(255, 255, 255, 0.94)';
    }
    if (lv <= LightSense.LEVEL_GENTLE) {
      return isDark ? 'rgba(255, 255, 255, 0.05)' : 'rgba(255, 255, 255, 0.16)';
    }
    if (lv <= LightSense.LEVEL_SMOOTH) {
      return isDark ? 'rgba(255, 255, 255, 0.07)' : 'rgba(255, 255, 255, 0.20)';
    }
    // 精致档：玻璃最通透，靠 backgroundBlurStyle(COMPONENT_THIN) + rim + 点光源出效果；
    // 不能再降到 0.06 以下，否则在花哨壁纸上会变成"没有卡片"。
    return isDark ? 'rgba(255, 255, 255, 0.07)' : 'rgba(255, 255, 255, 0.16)';
  }

  /** 卡片表面光感渐变：左上角光源高光 -> 中间通透 -> 右下角微暗角（高光保持半透明，背景透出） */
  static cardSurfaceColors(isDark: boolean): Array<[ResourceColor, number]> {
    const lv = LightSense.getLevel();
    if (lv <= LightSense.LEVEL_OFF) {
      // 关闭档：不叠加任何光感渐变，保持纯色平面
      return [
        ['rgba(255, 255, 255, 0)', 0.0],
        ['rgba(255, 255, 255, 0)', 1.0]
      ]
    }
    if (lv <= LightSense.LEVEL_GENTLE) {
      if (isDark) {
        return [
          ['rgba(255, 255, 255, 0.10)', 0.0],
          ['rgba(255, 255, 255, 0.02)', 0.35],
          ['rgba(255, 255, 255, 0.0)', 0.75],
          ['rgba(0, 0, 0, 0.10)', 1.0]
        ]
      }
      return [
        ['rgba(255, 255, 255, 0.45)', 0.0],
        ['rgba(255, 255, 255, 0.15)', 0.4],
        ['rgba(255, 255, 255, 0.0)', 0.78],
        ['rgba(0, 0, 0, 0.03)', 1.0]
      ]
    }
    // 标准/精致档：高光更亮但保持半透明，光感可见且背景透出
    if (isDark) {
      return [
        ['rgba(255, 255, 255, 0.12)', 0.0],
        ['rgba(255, 255, 255, 0.03)', 0.35],
        ['rgba(255, 255, 255, 0.0)', 0.75],
        ['rgba(0, 0, 0, 0.16)', 1.0]
      ]
    }
    return [
      ['rgba(255, 255, 255, 0.32)', 0.0],
      ['rgba(255, 255, 255, 0.12)', 0.4],
      ['rgba(255, 255, 255, 0.0)', 0.78],
      ['rgba(0, 0, 0, 0.05)', 1.0]
    ]
  }

  /** 卡片柔和投影：浅色模式阴影极淡，深色模式加深保证悬浮感；关闭档再收敛 */
  static cardShadow(isDark: boolean): string {
    if (LightSense.getLevel() <= LightSense.LEVEL_OFF) {
      return isDark ? 'rgba(0, 0, 0, 0.28)' : 'rgba(0, 0, 0, 0.06)';
    }
    return isDark ? 'rgba(0, 0, 0, 0.4)' : 'rgba(0, 0, 0, 0.1)';
  }

  /**
   * 卡片模糊档位（backgroundBlurStyle 用）。
   * 这是官方推荐的、低版本也可用的材质兜底；0 档为 NONE，其余档位始终有模糊。
   */
  static cardBlurStyle(): BlurStyle {
    return LightSense.cardBlurStyle(LightSense.getLevel());
  }

  /** 卡片边缘亮边宽度（vp）：精致档加粗，折射光感更明显；关闭档仅保留发丝边 */
  static cardRimWidth(): number {
    const lv = LightSense.getLevel();
    if (lv <= LightSense.LEVEL_OFF) {
      return 1;
    }
    return lv >= LightSense.LEVEL_EXQUISITE ? 1.5 : 1;
  }

  /** 卡片圆角 */
  static cardRadius(): number {
    return 14;
  }

  /** 外边缘受光（非对称 rim light）：上/左受光强、下/右衰减，模拟光源折射（单层，避免双描边） */
  static cardOuterRim(isDark: boolean): EdgeColors {
    const lv = LightSense.getLevel();
    if (lv <= LightSense.LEVEL_OFF) {
      // 关闭档：不要白色亮边，用一层极淡的分隔色即可
      return isDark
        ? { top: 'rgba(255, 255, 255, 0.08)', left: 'rgba(255, 255, 255, 0.06)', right: 'rgba(255, 255, 255, 0.05)', bottom: 'rgba(255, 255, 255, 0.04)' }
        : { top: 'rgba(0, 0, 0, 0.06)', left: 'rgba(0, 0, 0, 0.05)', right: 'rgba(0, 0, 0, 0.04)', bottom: 'rgba(0, 0, 0, 0.03)' };
    }
    if (lv >= LightSense.LEVEL_EXQUISITE) {
      // 精致：强折射亮边
      if (isDark) {
        return {
          top: 'rgba(255, 255, 255, 0.7)',
          left: 'rgba(255, 255, 255, 0.55)',
          right: 'rgba(255, 255, 255, 0.28)',
          bottom: 'rgba(255, 255, 255, 0.14)'
        }
      }
      return {
        top: 'rgba(255, 255, 255, 0.75)',
        left: 'rgba(255, 255, 255, 0.65)',
        right: 'rgba(255, 255, 255, 0.35)',
        bottom: 'rgba(255, 255, 255, 0.2)'
      }
    }
    if (lv >= LightSense.LEVEL_SMOOTH) {
      if (isDark) {
        return {
          top: 'rgba(255, 255, 255, 0.55)',
          left: 'rgba(255, 255, 255, 0.4)',
          right: 'rgba(255, 255, 255, 0.18)',
          bottom: 'rgba(255, 255, 255, 0.1)'
        }
      }
      return {
        top: 'rgba(255, 255, 255, 0.95)',
        left: 'rgba(255, 255, 255, 0.8)',
        right: 'rgba(255, 255, 255, 0.4)',
        bottom: 'rgba(255, 255, 255, 0.22)'
      }
    }
    if (isDark) {
      return {
        top: 'rgba(255, 255, 255, 0.45)',
        left: 'rgba(255, 255, 255, 0.32)',
        right: 'rgba(255, 255, 255, 0.14)',
        bottom: 'rgba(255, 255, 255, 0.08)'
      }
    }
    return {
      top: 'rgba(255, 255, 255, 0.9)',
      left: 'rgba(255, 255, 255, 0.7)',
      right: 'rgba(255, 255, 255, 0.35)',
      bottom: 'rgba(255, 255, 255, 0.18)'
    }
  }

  /** 卡片内容分割线：浅色半透明黑 / 深色半透明白 */
  static cardDivider(isDark: boolean): string {
    return isDark ? 'rgba(255, 255, 255, 0.12)' : 'rgba(0, 0, 0, 0.10)';
  }

  /**
   * 文字可读性阴影：颜色与文字相反（深色模式=白字配深影，浅色模式=黑字配浅影），
   * 保证文字在通透玻璃卡片/壁纸背景下深色浅色模式都能看清。
   */
  static textShadow(isDark: boolean): ShadowOptions {
    return isDark
      ? { radius: 3, color: 'rgba(0, 0, 0, 0.85)', offsetX: 0, offsetY: 1 }
      : { radius: 3, color: 'rgba(255, 255, 255, 0.85)', offsetX: 0, offsetY: 1 };
  }

  // ===================== 输入框（TextArea / TextInput） =====================

  /**
   * 输入框底色：**半透明**，让卡片/壁纸透上来。
   * 禁止再用不透明的 `sys.color.comp_background_gray` / `sys.color.background_primary`
   * ——那样输入框会变成一块纯色贴片，与沉浸光感背景割裂（AppLinkingTool 踩过）。
   */
  static inputBg(): string {
    return 'rgba(128, 128, 128, 0.12)';
  }

  /** 输入框背景高斯模糊半径（vp）：与按钮同款"背景模糊后透上来"；全局光感=关闭时不模糊 */
  static inputBlur(): number {
    return LightSense.getLevel() <= LightSense.LEVEL_OFF ? 0 : 8;
  }

  /** 输入框描边：跟随光感的 rim 亮边（上/左亮、下/右暗） */
  static inputRim(isDark: boolean): EdgeColors {
    return ImmersiveStyles.cardOuterRim(isDark);
  }

  /** 输入框圆角（vp） */
  static inputRadius(): number {
    return 8;
  }

  // ===================== 底部 Tab 栏 =====================

  /** Tab 栏毛玻璃兜底基底色（API < 26 或全局光感关闭时使用） */
  static tabBarBase(isDark: boolean): string {
    const lv = LightSense.getLevel();
    if (lv <= LightSense.LEVEL_OFF) {
      return isDark ? 'rgba(28, 28, 32, 0.96)' : 'rgba(255, 255, 255, 0.96)';
    }
    // 悬浮胶囊保持半透明：背景内容透出才是"沉浸光感"；可读性由毛玻璃 + 文字阴影兜底
    return isDark ? 'rgba(24, 24, 27, 0.55)' : 'rgba(255, 255, 255, 0.55)';
  }

  /** Tab 栏兜底毛玻璃档位：官方建议底部页签用较薄的材质 */
  static tabBarBlurStyle(): BlurStyle {
    const lv = LightSense.getLevel();
    if (lv <= LightSense.LEVEL_OFF) {
      return BlurStyle.NONE;
    }
    return BlurStyle.COMPONENT_THIN;
  }

  /** Tab 选中项光晕颜色 */
  static tabSelectedGlow(isDark: boolean): string {
    return isDark ? 'rgba(96, 165, 250, 0.95)' : 'rgba(10, 89, 247, 0.5)';
  }

  /** Tab 选中项胶囊底色（浅色淡蓝底 / 深色半透明白） */
  static tabSelectedBg(isDark: boolean): string {
    return isDark ? 'rgba(255, 255, 255, 0.14)' : 'rgba(10, 89, 247, 0.1)';
  }
}
