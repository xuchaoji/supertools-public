const TAG: string = 'StatusIndicator'

// StatusIndicator.ets
@ComponentV2
export struct StatusIndicator {
  // 进度百分比 (0-100)
  @Param value: number = 0;
  // 底部标签文本
  @Param label: string = '';
  // 圆环颜色
  @Param color: string = '#1890ff';

  @Monitor('value', 'label')
  onValueChange() {
    console.log(TAG, `onValueChange, label: ${this.label}, value: ${this.value}`)
  }

  build() {
    Column() {
      // 圆环和百分比容器
      Stack() {
        Progress({ value: this.value, total: 100, type: ProgressType.Ring }).width(100).height(100)
          .color(this.color)
          .style({ strokeWidth: 15})
          .alignRules({
            center: {anchor: '__container__', align: VerticalAlign.Center},
            middle: {anchor: '__container__', align: HorizontalAlign.Center}
          })
        // 中间百分比文本
        Column() {
          Row() {
            Text(`${Math.round(this.value)}`)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.color)
            Text(this.label === '温度' ? '℃' : '%')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.color)
          }

        }
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .width('auto')
        .height('auto')
      }
      .width('auto')
      .height('auto')

      // 底部标签
      if (this.label) {
        Text(this.label)
          .fontSize(16)
          .margin({ top: 12 })
          .fontColor('#666')
      }
    }
    .alignItems(HorizontalAlign.Center)
  }
}