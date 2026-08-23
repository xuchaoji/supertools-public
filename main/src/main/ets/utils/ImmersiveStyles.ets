/**
 * 沉浸光感视觉参数（参考 HarmonyOS 官方《沉浸光感》适配规范）。
 *
 * 核心思路：通过「毛玻璃基底 + 表面光感渐变 + 边缘高光 + 柔和投影」四层
 * 模拟光在材质表面的折射与漫反射，并按系统深/浅色模式提供两套参数，
 * 保证深色模式下不出现浅色玻璃发白发灰、浅色模式下不出现死黑脏边的问题。
 */
export class ImmersiveStyles {
  // ===================== 卡片（Card） =====================

  /** 卡片毛玻璃基底色：浅色模式泛白产生实体感（社区建议 ≈90% 白，此处保留一定通透度），深色模式压低亮度 */
  static cardBase(isDark: boolean): string {
    return isDark ? 'rgba(255, 255, 255, 0.09)' : 'rgba(255, 255, 255, 0.7)';
  }

  /** 卡片表面光感渐变：左上角光源高光 -> 中间通透 -> 右下角微暗角增加立体感 */
  static cardSurfaceColors(isDark: boolean): Array<[ResourceColor, number]> {
    if (isDark) {
      return [
        ['rgba(255, 255, 255, 0.16)', 0.0],
        ['rgba(255, 255, 255, 0.02)', 0.35],
        ['rgba(255, 255, 255, 0.0)', 0.75],
        ['rgba(0, 0, 0, 0.14)', 1.0]
      ]
    }
    return [
      ['rgba(255, 255, 255, 0.85)', 0.0],
      ['rgba(255, 255, 255, 0.25)', 0.4],
      ['rgba(255, 255, 255, 0.0)', 0.78],
      ['rgba(0, 0, 0, 0.04)', 1.0]
    ]
  }

  /** 卡片柔和投影：浅色模式阴影极淡（社区建议 rgba(0,0,0,0.12) 级别），深色模式加深保证悬浮感 */
  static cardShadow(isDark: boolean): string {
    return isDark ? 'rgba(0, 0, 0, 0.4)' : 'rgba(0, 0, 0, 0.1)';
  }

  /** 卡片背景模糊半径（vp）：官方/社区建议卡片 24~32，小尺寸网格卡片取折中 */
  static cardBlurRadius(): number {
    return 20;
  }

  /** 卡片圆角 */
  static cardRadius(): number {
    return 14;
  }

  /** 外边缘受光（非对称 rim light）：上/左受光强、下/右衰减，模拟光源方向与折射衰减（单层，避免双描边） */
  static cardOuterRim(isDark: boolean): EdgeColors {
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
