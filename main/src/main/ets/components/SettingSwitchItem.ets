@ComponentV2
export struct SettingSwitchItem {
  @Param @Require title: string;
  @Param @Require isOn: boolean;
  @Param vis: boolean = true;
  @Event onChange: (isOn: boolean) => void;

  build() {
    ListItem() {
      Row() {
        Text(this.title)
          .fontColor($r('sys.color.font_primary'))
          .fontSize('16vp')
          .fontWeight(FontWeight.Medium)

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
      // 增加交互反馈，点击时背景微变
      .stateStyles({
        pressed: {
          .backgroundColor('rgba(0, 0, 0, 0.05)')
        },
        normal: {
          .backgroundColor(Color.Transparent)
        }
      })
      .clip(true)
    }
  }
}