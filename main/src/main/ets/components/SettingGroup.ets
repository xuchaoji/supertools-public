@ComponentV2
export struct SettingGroup {
  // 接受子组件内容
  @BuilderParam content: () => void;
  @Param vis:boolean = true;

  build() {
    // 使用 List 的 ListItemGroup 样式来实现归类
    List() {
      ListItemGroup() {
        this.content()
      }
      // 使用半透明白色背景
      .backgroundColor('rgba(255, 255, 255, 0.8)')
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .borderRadius('16vp')
      .clip(true)
      // 核心功能：自动添加分割线
      .divider({
        strokeWidth: '1px',
        color: '#1A000000', // 半透明灰色分割线配合毛玻璃
        startMargin: '16vp',
        endMargin: '16vp'
      })
      .border({ width: 1, color: '#1A000000' })
    }
    .visibility(this.vis ? Visibility.Visible : Visibility.None)
    .width('100%')
    .height('auto') // 高度自适应内容
    .scrollBar(BarState.Off)
  }
}