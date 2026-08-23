import { mediaquery } from '@kit.ArkUI';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';

@ComponentV2
export struct SettingSwitchItem {
  @Param @Require title: string;
  @Param @Require isOn: boolean;
  @Param vis: boolean = true;
  @Event onChange: (isOn: boolean) => void;
  // 沉浸光感：跟随系统深/浅色模式（决定文字阴影颜色）
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
    ListItem() {
      Row() {
        Text(this.title)
          .fontColor($r('sys.color.font_primary'))
          .fontSize('16vp')
          .fontWeight(FontWeight.Medium)
          // 深色/浅色模式可读性：阴影颜色与文字相反
          .textShadow(ImmersiveStyles.textShadow(this.isDark))

        Toggle({ type: ToggleType.Switch, isOn: this.isOn })
          .onChange((isOn) => {
            if (this.onChange) {
              this.onChange(isOn)
            }
          })
      }
      .width('100%')
      .height('56vp')
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ left: '16vp', right: '16vp' })
      .visibility(this.vis ? Visibility.Visible : Visibility.None)
      // 点击光感反馈：不再手写灰色按压层，
      // 由所在卡片材质的 interactive 触摸光效承担（手指接触时白色光晕跟随）
      .clip(true)
    }
  }
}
