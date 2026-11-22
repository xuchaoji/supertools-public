/**
 * notes_hsp 的材质兜底。
 *
 * 官方约束（《组件适配沉浸光感》）：
 * - `systemMaterial` / `uiMaterial.ImmersiveMaterial` 在普通页面内容区不生效；
 *   只支持 Navigation/NavDestination 标题栏、底部 TabBar、Dialog/Toast 等容器。
 * - 内容区组件无法满足生效范围时，官方建议改用 backgroundColor / backgroundBlurStyle 等通用属性。
 *
 * 所以这里不再自绘「光感渐变 + 点光源 + rim 光边」：
 * - 删除确认使用官方 AlertDialog + systemMaterial（见 NotesFeature）；
 * - 列表卡片、输入框、预览容器用官方的 backgroundBlurStyle / backdropBlur + 半透明底色做兜底；
 * - 光感档位只影响兜底材质的浓度与模糊档位，不再伪造系统材质。
 */
export class NotesTheme {
  static readonly LEVEL_OFF: number = 0;
  static readonly LEVEL_GENTLE: number = 1;
  static readonly LEVEL_SMOOTH: number = 2;
  static readonly LEVEL_EXQUISITE: number = 3;

  static readonly ACCENT: string = '#0A59F7';
  static readonly DANGER: string = '#E84026';

  private static normalized(level: number): number {
    return Math.min(Math.max(Math.round(level), NotesTheme.LEVEL_OFF), NotesTheme.LEVEL_EXQUISITE);
  }

  static secondaryText(isDark: boolean): string {
    return isDark ? 'rgba(255, 255, 255, 0.62)' : 'rgba(0, 0, 0, 0.55)';
  }

  /** 文字可读性阴影：与主应用 PageHeader / GlassCard 保持一致。 */
  static textShadow(isDark: boolean): ShadowOptions {
    return isDark
      ? { radius: 3, color: 'rgba(0, 0, 0, 0.85)', offsetX: 0, offsetY: 1 }
      : { radius: 3, color: 'rgba(255, 255, 255, 0.85)', offsetX: 0, offsetY: 1 };
  }

  // ===================== 内容区兜底材质 =====================

  static cardBase(isDark: boolean, level: number): string {
    const lv: number = NotesTheme.normalized(level);
    if (lv <= NotesTheme.LEVEL_OFF) {
      return isDark ? 'rgba(28, 28, 32, 0.94)' : 'rgba(255, 255, 255, 0.94)';
    }
    // 系统材质在内容区不生效，用半透明底色 + 模糊让背景透出。
    return isDark ? 'rgba(42, 42, 48, 0.72)' : 'rgba(255, 255, 255, 0.72)';
  }

  static cardShadow(isDark: boolean, level: number): string {
    if (NotesTheme.normalized(level) <= NotesTheme.LEVEL_OFF) {
      return isDark ? 'rgba(0, 0, 0, 0.28)' : 'rgba(0, 0, 0, 0.06)';
    }
    return isDark ? 'rgba(0, 0, 0, 0.4)' : 'rgba(0, 0, 0, 0.1)';
  }

  static cardBlurStyle(level: number): BlurStyle {
    const lv: number = NotesTheme.normalized(level);
    if (lv <= NotesTheme.LEVEL_OFF) {
      return BlurStyle.NONE;
    }
    if (lv <= NotesTheme.LEVEL_GENTLE) {
      return BlurStyle.COMPONENT_THIN;
    }
    if (lv <= NotesTheme.LEVEL_SMOOTH) {
      return BlurStyle.COMPONENT_REGULAR;
    }
    return BlurStyle.COMPONENT_THIN;
  }

  static cardRadius(): number {
    return 16;
  }

  static cardBorder(isDark: boolean): string {
    return isDark ? 'rgba(255, 255, 255, 0.14)' : 'rgba(0, 0, 0, 0.08)';
  }

  static inputBorder(isDark: boolean): string {
    return isDark ? 'rgba(255, 255, 255, 0.16)' : 'rgba(0, 0, 0, 0.10)';
  }

  static chipBase(isDark: boolean, level: number): string {
    const lv: number = NotesTheme.normalized(level);
    if (lv <= NotesTheme.LEVEL_OFF) {
      return isDark ? 'rgba(255, 255, 255, 0.12)' : 'rgba(0, 0, 0, 0.06)';
    }
    return isDark ? 'rgba(255, 255, 255, 0.10)' : 'rgba(0, 0, 0, 0.05)';
  }

  static previewBase(isDark: boolean, level: number): string {
    const lv: number = NotesTheme.normalized(level);
    if (lv <= NotesTheme.LEVEL_OFF) {
      return isDark ? 'rgba(24, 24, 28, 0.94)' : 'rgba(255, 255, 255, 0.94)';
    }
    return isDark ? 'rgba(30, 30, 36, 0.68)' : 'rgba(255, 255, 255, 0.68)';
  }

  // ===================== 输入框 =====================

  static inputBg(isDark: boolean): string {
    return isDark ? 'rgba(255, 255, 255, 0.10)' : 'rgba(128, 128, 128, 0.12)';
  }

  static inputBlur(level: number): number {
    return NotesTheme.normalized(level) <= NotesTheme.LEVEL_OFF ? 0 : 8;
  }

  static inputRadius(): number {
    return 12;
  }
}
