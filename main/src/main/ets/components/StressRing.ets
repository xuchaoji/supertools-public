
@ComponentV2
export struct StressRing {
  // 接收父组件的动态数据
  @Param value: number = 0;       // 用于计算圆环进度 (0-100)
  @Param displayValue: string = ""; // 圆环中心显示的文字 (如 "45%")
  @Param label: string = "";      // 底部标签 (CPU / MEM)

  // 颜色阈值控制
  @Param isActive: boolean = false;

  // 根据数值获取颜色
  private getColor(): string {
    if (!this.isActive) return '#99333333'; // 未启动时呈深灰色
    if (this.value < 50) return '#994CAF50'; // 绿色
    if (this.value < 80) return '#99FFC107'; // 黄色
    return '#99F44336'; // 红色
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        // 1. 背景底环 (灰色)
        Progress({ value: 100, total: 100, type: ProgressType.Ring })
          .width(40)
          .height(40)
          .color('rgba(255,255,255,0.1)') // 半透明底色
          .style({ strokeWidth: 4 })

        // 2. 动态进度环
        Progress({ value: this.value, total: 100, type: ProgressType.Ring })
          .width(40)
          .height(40)
          .color(this.getColor()) // 动态颜色
          .style({ strokeWidth: 4 })
          .animation({ duration: 300 }) // 丝滑动画

        // 3. 中间数值显示
        Column() {
          Text(this.displayValue)
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor('#99FFFFFF')

          Text(this.label)
            .fontSize(8)
            .fontColor('#99AAAAAA')
            .margin({ top: 2 })
        }
      }
    }
    .justifyContent(FlexAlign.Center)
    .width(50) // 给定一个合适的容器宽度
  }
}