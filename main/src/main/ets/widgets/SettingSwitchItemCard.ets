@ComponentV2
export struct SettingSwitchItemCard {
  @Param @Require title: string;
  @Param @Require isOn: boolean;

  @Event onChange: (isOn: boolean) => void;

  build() {
    Row() {
      Text(this.title)
        .fontColor($r('sys.color.font_primary'))
        .fontSize('16vp')
      Toggle({
        type: ToggleType.Switch,
        isOn: this.isOn,
      }).onChange((isOn) => {
        if (this.onChange) {
          this.onChange(isOn)
        }
      })
    }
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius('8vp')
    .padding({
      top: '8vp',
      bottom: '8vp',
      left: '12vp',
      right: '12vp'
    })
    .height('auto')
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
  }
}