/**
 * 沉浸光感视觉参数（参考 HarmonyOS 官方《沉浸光感》适配规范）。
 *
 * 核心思路：通过「毛玻璃基底 + 表面光感渐变 + 边缘高光 + 柔和投影」四层
 * 模拟光在材质表面的折射与漫反射，并按系统深/浅色模式提供两套参数，
 * 保证深色模式下不出现浅色玻璃发白发灰、浅色模式下不出现死黑脏边的问题。
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
      return isDark ? 'rgba(255, 255, 255, 0.05)' : 'rgba(255, 255, 255, 0.15)';
    }
    if (lv <= LightSense.LEVEL_SMOOTH) {
      return isDark ? 'rgba(255, 255, 255, 0.07)' : 'rgba(255, 255, 255, 0.20)';
    }
    return isDark ? 'rgba(255, 255, 255, 0.06)' : 'rgba(255, 255, 255, 0.16)';
  }

  /** 卡片表面光感渐变：左上角光源高光 -> 中间通透 -> 右下角微暗角（高光保持半透明，背景透出） */
  static cardSurfaceColors(isDark: boolean): Array<[ResourceColor, number]> {
    const lv = LightSense.getLevel();
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

  /** 卡片柔和投影：浅色模式阴影极淡（社区建议 rgba(0,0,0,0.12) 级别），深色模式加深保证悬浮感 */
  static cardShadow(isDark: boolean): string {
    return isDark ? 'rgba(0, 0, 0, 0.4)' : 'rgba(0, 0, 0, 0.1)';
  }

  /**
   * 卡片背景模糊半径（vp，按全局光感档位取值）：光感是"通透+边缘折射"而非磨砂，
   * 精致档系统材质承担玻璃感，故模糊降到 0；低档位保留极薄模糊兜底。
   */
  static cardBlurRadius(): number {
    const lv = LightSense.getLevel();
    if (lv <= LightSense.LEVEL_OFF) {
      return 0;
    }
    if (lv <= LightSense.LEVEL_GENTLE) {
      return 4;
    }
    if (lv <= LightSense.LEVEL_SMOOTH) {
      return 8;
    }
    return 0;
  }

  /** 卡片模糊档位（backgroundBlurStyle 用）：精致档为 NONE（玻璃感由点光源/亮边承担） */
  static cardBlurStyle(): BlurStyle {
    const lv = LightSense.getLevel();
    if (lv <= LightSense.LEVEL_OFF) {
      return BlurStyle.NONE;
    }
    if (lv <= LightSense.LEVEL_SMOOTH) {
      return BlurStyle.COMPONENT_THIN;
    }
    return BlurStyle.NONE;
  }

  /** 卡片边缘亮边宽度（vp）：精致档加粗，折射光感更明显 */
  static cardRimWidth(): number {
    return LightSense.getLevel() >= LightSense.LEVEL_EXQUISITE ? 1.5 : 1;
  }

  /** 卡片圆角 */
  static cardRadius(): number {
    return 14;
  }

  /** 外边缘受光（非对称 rim light）：上/左受光强、下/右衰减，模拟光源折射（单层，避免双描边） */
  static cardOuterRim(isDark: boolean): EdgeColors {
    const lv = LightSense.getLevel();
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

  // ===================== 底部 Tab 栏 =====================

  /** Tab 栏毛玻璃基底色：可读性优先，透明度比卡片更高 */
  static tabBarBase(isDark: boolean): string {
    return isDark ? 'rgba(24, 24, 27, 0.8)' : 'rgba(255, 255, 255, 0.88)';
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
