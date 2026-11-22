import { NotesTheme } from './NotesTheme';

/**
 * 编辑器工具栏（编辑/预览切换、字数、删除）。
 *
 * 独立成 @ComponentV2 而不是 NotesFeature 内部的嵌套 @Builder：
 * V2 的嵌套 @Builder 不会建立父组件 @Local -> 子树的响应式依赖，
 * 曾出现“内容已经是预览、但高亮还停在编辑”的假状态。
 */
@ComponentV2
export struct EditorToolbar {
  @Param showPreview: boolean = false;
  @Param isDark: boolean = false;
  @Param lightSense: number = NotesTheme.LEVEL_EXQUISITE;
  @Param charCount: number = 0;
  @Event onTogglePreview: (preview: boolean) => void = (_preview: boolean) => {};
  @Event onDelete: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      Row({ space: 2 }) {
        Text('编辑')
          .fontSize(13)
          .fontWeight(!this.showPreview ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(!this.showPreview ? $r('sys.color.font_on_primary') : $r('sys.color.font_secondary'))
          .textAlign(TextAlign.Center)
          .height(30)
          .padding({ left: 16, right: 16 })
          .borderRadius(8)
          .backgroundColor(!this.showPreview ? NotesTheme.ACCENT : Color.Transparent)
          .onClick(() => {
            this.onTogglePreview(false);
          })

        Text('预览')
          .fontSize(13)
          .fontWeight(this.showPreview ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.showPreview ? $r('sys.color.font_on_primary') : $r('sys.color.font_secondary'))
          .textAlign(TextAlign.Center)
          .height(30)
          .padding({ left: 16, right: 16 })
          .borderRadius(8)
          .backgroundColor(this.showPreview ? NotesTheme.ACCENT : Color.Transparent)
          .onClick(() => {
            this.onTogglePreview(true);
          })
      }
      .padding(3)
      .borderRadius(10)
      .backgroundColor(NotesTheme.chipBase(this.isDark, this.lightSense))
      .backdropBlur(NotesTheme.inputBlur(this.lightSense))
      .border({
        width: 1,
        color: NotesTheme.inputBorder(this.isDark)
      })

      Blank()

      Text(`${this.charCount} 字`)
        .fontSize(11)
        .fontColor(NotesTheme.secondaryText(this.isDark))
        .textShadow(NotesTheme.textShadow(this.isDark))

      Text('删除')
        .fontSize(12)
        .fontColor(NotesTheme.DANGER)
        .textShadow(NotesTheme.textShadow(this.isDark))
        .padding({ left: 8, right: 4, top: 6, bottom: 6 })
        .onClick(() => {
          this.onDelete();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
