import { mediaquery } from '@kit.ArkUI';

@Component
export struct ImmersiveGlassCard {
  // --- 暴露给外部的属性 ---
  @Prop zHeight: number = 2;   // Z轴高度/厚度，推荐取值 1 ~ 10
  @Prop zRadius: number = 16;  // 边缘圆角半径
  @Prop theme: 'light' | 'dark' = 'light'; // 背景环境亮度主题（仅 followSystem=false 时生效）
  @Prop followSystem: boolean = true;      // 沉浸光感：默认跟随系统深/浅色模式

  // 允许外部传入内部 UI 内容
  @BuilderParam content: () => void;

  // --- 沉浸光感：系统深/浅色模式状态 ---
  @State isDark: boolean = false;
  private themeMq: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    if (this.followSystem) {
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
  }

  aboutToDisappear(): void {
    this.themeMq?.off('change');
    this.themeMq = null;
  }

  /** 当前生效的主题 */
  private getEffectiveTheme(): 'light' | 'dark' {
    return this.followSystem ? (this.isDark ? 'dark' : 'light') : this.theme;
  }

  // --- 针对亮暗背景动态计算光学参数 ---

  // 1. 毛玻璃基础底色 (浅色需泛白以产生实体感)
  private getBaseColor(): string {
    return this.getEffectiveTheme() === 'light' ? 'rgba(255, 255, 255, 0.3)' : 'rgba(255, 255, 255, 0.05)';
  }

  // 2. 边缘截面颜色 (修正纯白背景下死黑脏边问题，使用极淡灰/白)
  private getEdgeColor(): string {
    return this.getEffectiveTheme() === 'light' ? 'rgba(150, 150, 150, 0.1)' : 'rgba(255, 255, 255, 0.35)';
  }

  // 3. 物理阴影颜色 (浅色背景下阴影极度柔和)
  private getShadowColor(): string {
    return this.getEffectiveTheme() === 'light' ? 'rgba(0, 0, 0, 0.02)' : 'rgba(0, 0, 0, 0.2)';
  }

  // 4. 表面光感渐变
  private getSurfaceColors(): Array<[ResourceColor, number]> {
    if (this.getEffectiveTheme() === 'light') {
      return [
        ['rgba(255, 255, 255, 0.6)', 0.0],  // 左上角加强泛白
        ['rgba(255, 255, 255, 0.0)', 0.4],  // 中间通透
        ['rgba(0, 0, 0, 0.02)', 1.0]        // 右下角带入一点点暗灰增加立体感
      ]
    } else {
      return [
        ['rgba(255, 255, 255, 0.4)', 0.0],
        ['rgba(255, 255, 255, 0.0)', 0.3],
        ['rgba(255, 255, 255, 0.0)', 0.8],
        ['rgba(255, 255, 255, 0.1)', 1.0]
      ]
    }
  }

  // 5. 计算边缘厚度和模糊度
  private getEdgeWidth(): number {
    return Math.max(0.5, this.zHeight * 0.3);
  }

  private getBlurRadius(): number {
    return 8 + (this.zHeight * 2);
  }

  build() {
    Stack() {
      // 图层 1：底层毛玻璃
      Stack()
        .width('100%')
        .height('100%')
        .backdropBlur(this.getBlurRadius())
        .backgroundColor(this.getBaseColor())
        .borderRadius(this.zRadius)

      // 图层 2：边缘厚度与折射反光模拟
      Stack()
        .width('100%')
        .height('100%')
        .borderRadius(this.zRadius)
        .border({
          width: this.getEdgeWidth(),
          color: this.getEdgeColor(),
          style: BorderStyle.Solid
        })

      // 图层 3：表面光感动态渐变
      Stack()
        .width('100%')
        .height('100%')
        .borderRadius(this.zRadius)
        .linearGradient({
          angle: 135,
          colors: this.getSurfaceColors()
        })

      // 图层 4：外部传入的实际业务内容
      if (this.content) {
        this.content()
      }
    }
    // --- 核心修正区域：严格的修饰符调用顺序 ---

    // 1. 声明透明底色，避免系统渲染引擎降级为直角矩形
    .backgroundColor(Color.Transparent)

    // 2. 优先声明圆角，划定形状边界
    .borderRadius(this.zRadius)

    // 3. 裁剪可能溢出的毛刺
    .clip(true)

    // 4. 最后一步投射阴影，引擎会依据上面划定的圆角边界生成柔和阴影
    .shadow({
      radius: 12 + (this.zHeight * 3),
      color: this.getShadowColor(),
      offsetY: this.zHeight * 2,
      offsetX: 0
    })
  }
}
