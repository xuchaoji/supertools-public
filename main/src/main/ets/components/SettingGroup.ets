import { mediaquery } from '@kit.ArkUI';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';

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
      // 沉浸光感：毛玻璃基底
      .backgroundColor(ImmersiveStyles.cardBase(this.isDark))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
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
