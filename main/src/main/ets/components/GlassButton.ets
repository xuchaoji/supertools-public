import { mediaquery } from '@kit.ArkUI';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';
import { LightSense } from '../utils/LightSense';

/**
 * 沉浸光感玻璃按钮 —— 全项目**唯一**的按钮实现。
 *
 * 结构：内部一层**模糊层**（`backdropBlur` 高斯模糊背景后透上来）+ 一层内容层（图标 + 文字）。
 * 默认即"玻璃态"：底色跟随全局光感档位的玻璃基底，描边跟随光感 rim 亮边，
 * 背景（壁纸/卡片）模糊后透出，与 `GlassCard` 同一套视觉配方。
 *
 * 可配置项（都不传就是上面的默认玻璃态）：
 * | 参数 | 缺省 | 说明 |
 * |---|---|---|
 * | `bgColor` | `''` | 按钮底色。传颜色则**覆盖**玻璃基底（主按钮传 `comp_background_emphasize`） |
 * | `textColor` | `''` | 文字颜色。缺省 `sys.color.font_primary` |
 * | `strokeWidth` | `-1` | 描边宽度（vp）。`-1` = 跟随光感档位；`0` = 无描边 |
 * | `strokeColor` | `''` | 描边颜色。缺省跟随光感的 rim 亮边（上/左亮、下/右暗） |
 * | `blurRadius` | `8` | 高斯模糊半径（vp）。`0` = 不模糊；全局光感=关闭时自动降为 0 |
 *
 * > 成员名不能叫 `borderWidth` / `borderColor` / `enabled` / `height`：这些是 ArkUI
 * > 通用属性名，与 `CustomComponent` 基类冲突（`Property 'x' is not assignable to the
 * > same property in base type 'CustomComponent'`），故用 `strokeWidth` / `strokeColor` /
 * > `isEnabled` / `btnHeight`。
 *
 * 用法（**参数式组件，无尾随块**，因此可以在调用处继续链式挂属性如 `.layoutWeight(1)`）：
 *   // 次要按钮：默认玻璃态
 *   GlassButton({ label: '清空', onAction: () => { this.inputText = '' } })
 *
 *   // 主要按钮：覆盖底色与文字色，去掉描边
 *   GlassButton({
 *     label: '生成二维码',
 *     bgColor: $r('sys.color.comp_background_emphasize'),
 *     textColor: $r('sys.color.font_on_primary'),
 *     strokeWidth: 0,
 *     fontWeight: FontWeight.Medium,
 *     onAction: () => this.generateQr(this.inputText)
 *   })
 *     .layoutWeight(1.5)
 */
@ComponentV2
export struct GlassButton {
  /** 按钮文字 */
  @Param label: string = '';
  /** 可选前置图标 */
  @Param iconRes: Resource | undefined = undefined;
  /** 按钮底色；`''` = 跟随光感玻璃基底 */
  @Param bgColor: ResourceColor = '';
  /** 文字颜色；`''` = `sys.color.font_primary` */
  @Param textColor: ResourceColor = '';
  /** 描边宽度（vp）；`-1` = 跟随光感档位 */
  @Param strokeWidth: number = -1;
  /** 描边颜色；`''` = 跟随光感 rim 亮边 */
  @Param strokeColor: ResourceColor = '';
  /** 高斯模糊半径（vp） */
  @Param blurRadius: number = 8;
  /** 按钮高度（vp） */
  @Param btnHeight: number = 40;
  /** 字号（vp） */
  @Param fontSize: number = 14;
  /** 字重 */
  @Param fontWeight: FontWeight = FontWeight.Normal;
  /** 圆角（vp） */
  @Param radius: number = 10;
  /** 内容左右内边距（vp，0 = 由父容器宽度决定） */
  @Param padX: number = 0;
  /**
   * 是否撑满父容器分配给按钮的宽度。
   *
   * **父容器用 `.layoutWeight()` / `.width()` 给按钮定宽时必须传 true**，否则：
   * 父容器把宽度分配给了自定义组件的包装节点，而按钮内层可见的玻璃节点是
   * wrap-content，不会撑满——表现为"胶囊粗细不齐 + 大片看不见的空白"。
   * 反之，父容器按内容宽度排列（Row + Blank/ SpaceBetween，不设宽度）时必须保持 false，
   * 否则会撑满可用宽度、把后面的兄弟节点挤出屏幕。
   */
  @Param fillWidth: boolean = false;
  /** 是否可点（不可点时降到 45% 透明度并吞掉点击） */
  @Param isEnabled: boolean = true;
  /** 点击回调 */
  @Event onAction: () => void = () => {
  };
  /** 沉浸光感：跟随系统深/浅色模式 */
  @Local isDark: boolean = false;
  private themeMq: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    try {
      this.themeMq = this.getUIContext().getMediaQuery().matchMediaSync('(display-mode: dark)');
      this.isDark = this.themeMq.matches;
      this.themeMq.on('change', (event: mediaquery.MediaQueryResult) => {
        this.isDark = event.matches;
      });
    } catch (e) {
      this.isDark = false;
    }
  }

  aboutToDisappear(): void {
    this.themeMq?.off('change');
    this.themeMq = null;
  }

  /** 是否使用默认玻璃态（未指定底色） */
  private useGlass(): boolean {
    return this.bgColor === '';
  }

  private effectiveBg(): ResourceColor {
    return this.useGlass() ? ImmersiveStyles.cardBase(this.isDark) : this.bgColor;
  }

  private effectiveTextColor(): ResourceColor {
    return this.textColor === '' ? $r('sys.color.font_primary') : this.textColor;
  }

  private effectiveBorderWidth(): number {
    return this.strokeWidth >= 0 ? this.strokeWidth : ImmersiveStyles.cardRimWidth();
  }

  /** 描边颜色：未指定时用光感 rim 亮边（四边不同色，模拟折射） */
  private effectiveBorderColor(): ResourceColor | EdgeColors {
    return this.strokeColor === '' ? ImmersiveStyles.cardOuterRim(this.isDark) : this.strokeColor;
  }

  /** 全局光感设为「关闭」时不做模糊，省电且观感一致 */
  private effectiveBlur(): number {
    return LightSense.getLevel() <= LightSense.LEVEL_OFF ? 0 : this.blurRadius;
  }

  /** 光感渐变：玻璃态用光感配方；指定了底色则不叠渐变（全透明占位） */
  private effectiveGradient(): Array<[ResourceColor, number]> {
    if (this.useGlass()) {
      return ImmersiveStyles.cardSurfaceColors(this.isDark);
    }
    return [['rgba(0, 0, 0, 0)', 0.0], ['rgba(0, 0, 0, 0)', 1.0]];
  }

  build() {
    // 单节点配方（与 GlassCard 一致）：背景高斯模糊/底色/光感渐变/rim 亮边/投影
    // 全部挂在这个内容容器上。
    // ⚠️ 不要改成 "Stack { 百分比尺寸的模糊层 + 内容层 }"：百分比子节点会反过来把
    // Stack 撑满父容器的可用宽度——调用方没给宽度时（如 LocalWebPage 的操作行）
    // 按钮会被拉宽并把后面的按钮挤出屏幕。
    // ⚠️ 下面两个分支只差一个 width，配方必须保持逐行一致（见 fillWidth 的说明）。
    if (this.fillWidth) {
      Row({ space: 6 }) {
        this.ButtonContent()
      }
      .width('100%')
      .padding({ left: this.padX, right: this.padX })
      .justifyContent(FlexAlign.Center)
      .height(this.btnHeight)
      .borderRadius(this.radius)
      .clip(true)
      // 模糊层：背景高斯模糊后透上来
      .backdropBlur(this.effectiveBlur())
      .backgroundColor(this.effectiveBg())
      .linearGradient({
        angle: 135,
        colors: this.effectiveGradient()
      })
      .border({ width: this.effectiveBorderWidth(), color: this.effectiveBorderColor() })
      .visualEffect(LightSense.lightVisualEffect())
      .shadow({
        radius: 10,
        color: ImmersiveStyles.cardShadow(this.isDark),
        offsetX: 0,
        offsetY: 2
      })
      .opacity(this.isEnabled ? 1 : 0.45)
      .onClick(() => {
        if (this.isEnabled) {
          this.onAction();
        }
      })
    } else {
      Row({ space: 6 }) {
        this.ButtonContent()
      }
      .padding({ left: this.padX, right: this.padX })
      .justifyContent(FlexAlign.Center)
      .height(this.btnHeight)
      .borderRadius(this.radius)
      .clip(true)
      // 模糊层：背景高斯模糊后透上来
      .backdropBlur(this.effectiveBlur())
      .backgroundColor(this.effectiveBg())
      .linearGradient({
        angle: 135,
        colors: this.effectiveGradient()
      })
      .border({ width: this.effectiveBorderWidth(), color: this.effectiveBorderColor() })
      .visualEffect(LightSense.lightVisualEffect())
      .shadow({
        radius: 10,
        color: ImmersiveStyles.cardShadow(this.isDark),
        offsetX: 0,
        offsetY: 2
      })
      .opacity(this.isEnabled ? 1 : 0.45)
      .onClick(() => {
        if (this.isEnabled) {
          this.onAction();
        }
      })
    }
  }

  /** 按钮内容（图标 + 文字）：两个宽度分支共用，保证内容只有一份 */
  @Builder
  ButtonContent() {
    if (this.iconRes !== undefined) {
      Image(this.iconRes)
        .width(this.fontSize + 2)
        .height(this.fontSize + 2)
        .objectFit(ImageFit.Contain)
    }
    Text(this.label)
      .fontSize(this.fontSize)
      .fontWeight(this.fontWeight)
      .fontColor(this.effectiveTextColor())
      // 可读性阴影：玻璃态下背景可能很花，保证文字看得清
      .textShadow(ImmersiveStyles.textShadow(this.isDark))
  }
}
