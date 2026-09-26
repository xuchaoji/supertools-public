import { mediaquery } from '@kit.ArkUI';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';
import { LightSense } from '../utils/LightSense';

/**
 * 沉浸光感玻璃卡片 —— 全项目**唯一**的卡片实现。
 *
 * 配方（顺序不可改，与工具箱卡片/设置分组完全一致）：
 *   基底色 → 毛玻璃 backdropBlur → 光感渐变 → rim 亮边 → 点光源 → 柔和投影
 *
 * 设计约束：
 * - 玻璃样式直接作用于**内容容器**（单节点）：内容决定高度，
 *   避免多层 Stack + height('100%') 在无高度约束的 Scroll 中撑满整个视口。
 * - 内边距不在此处写死，由调用方在 content 内部自行 `.padding(...)`，
 *   便于"带标题的卡片""纯列表卡片"共用同一组件。
 *
 * 用法：
 *   GlassCard() {
 *     Column({ space: 10 }) { ... }.padding(12)
 *   }
 */
@ComponentV2
export struct GlassCard {
  /** 卡片内容（渲染在玻璃层之上） */
  @BuilderParam content: () => void;
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

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .borderRadius(ImmersiveStyles.cardRadius())
    .clip(true)
    .backgroundColor(ImmersiveStyles.cardBase(this.isDark))
    .backdropBlur(ImmersiveStyles.cardBlurRadius())
    .linearGradient({
      angle: 135,
      colors: ImmersiveStyles.cardSurfaceColors(this.isDark)
    })
    .border({ width: ImmersiveStyles.cardRimWidth(), color: ImmersiveStyles.cardOuterRim(this.isDark) })
    // 点光源光效（与工具箱卡片一致）
    .visualEffect(LightSense.lightVisualEffect())
    // 柔和投影（依据圆角边界生成）
    .shadow({
      radius: 14,
      color: ImmersiveStyles.cardShadow(this.isDark),
      offsetX: 0,
      offsetY: 4
    })
  }
}
