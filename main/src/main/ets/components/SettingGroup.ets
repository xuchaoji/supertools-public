import { mediaquery } from '@kit.ArkUI';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';
import { LightSense } from '../utils/LightSense';

@ComponentV2
export struct SettingGroup {
  // 接受子组件内容
  @BuilderParam content: () => void;
  @Param vis:boolean = true;
  // 沉浸光感：跟随系统深/浅色模式
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
    // 使用 List 的 ListItemGroup 样式来实现归类
    List() {
      ListItemGroup() {
        this.content()
      }
      // 沉浸光感：毛玻璃基底（档位驱动：精致档换官方 systemMaterial，其余为 backgroundBlurStyle）
      .backgroundColor(ImmersiveStyles.cardBase(this.isDark))
      .backgroundBlurStyle(
        LightSense.immersiveMaterial(LightSense.getLevel()) ? BlurStyle.NONE : ImmersiveStyles.cardBlurStyle())
      .systemMaterial(LightSense.immersiveMaterial(LightSense.getLevel()))
      // 点光源光效（官方视觉特效，标准/精致档生效）
      .visualEffect(LightSense.lightVisualEffect())
      // 表面光感渐变（左上光源 -> 右下微暗角）
      .linearGradient({
        angle: 135,
        colors: ImmersiveStyles.cardSurfaceColors(this.isDark)
      })
      .borderRadius('16vp')
      .clip(true)
      // 外边缘受光（非对称 rim light，模拟折射衰减）
      .border({ width: 1, color: ImmersiveStyles.cardOuterRim(this.isDark) })
      // 核心功能：自动添加分割线
      .divider({
        strokeWidth: '1px',
        color: ImmersiveStyles.cardDivider(this.isDark),
        startMargin: '16vp',
        endMargin: '16vp'
      })
    }
    .visibility(this.vis ? Visibility.Visible : Visibility.None)
    .width('100%')
    .height('auto') // 高度自适应内容
    .scrollBar(BarState.Off)
    // 柔和投影
    .borderRadius('16vp')
    .shadow({
      radius: 14,
      color: ImmersiveStyles.cardShadow(this.isDark),
      offsetX: 0,
      offsetY: 4
    })
  }
}
