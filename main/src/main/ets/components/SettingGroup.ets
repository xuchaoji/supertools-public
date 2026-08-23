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
      .borderRadius(ImmersiveStyles.cardRadius())
      .clip(true)
      // 与工具箱卡片背景保持一致的沉浸光感配方：
      // 基底色 -> 毛玻璃模糊 -> 光感渐变 -> rim 亮边 -> 点光源，不叠加 systemMaterial 染色
      .backgroundColor(ImmersiveStyles.cardBase(this.isDark))
      .backdropBlur(ImmersiveStyles.cardBlurRadius())
      .linearGradient({
        angle: 135,
        colors: ImmersiveStyles.cardSurfaceColors(this.isDark)
      })
      .border({ width: ImmersiveStyles.cardRimWidth(), color: ImmersiveStyles.cardOuterRim(this.isDark) })
      .visualEffect(LightSense.lightVisualEffect())
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
    // 柔和投影（与工具箱卡片一致，依据圆角边界生成）
    .borderRadius(ImmersiveStyles.cardRadius())
    .shadow({
      radius: 14,
      color: ImmersiveStyles.cardShadow(this.isDark),
      offsetX: 0,
      offsetY: 4
    })
  }
}
