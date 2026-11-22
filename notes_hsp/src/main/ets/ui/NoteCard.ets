import { NoteMeta, formatTime } from '../model/Note';
import { NotesTheme } from './NotesTheme';

/** 笔记列表卡片；只负责展示与点击，删除在编辑器里做，避免误触。 */
@ComponentV2
export struct NoteCard {
  @Param note: NoteMeta = new NoteMeta();
  @Param isDark: boolean = false;
  @Param lightSense: number = NotesTheme.LEVEL_EXQUISITE;
  @Event onOpen: () => void = () => {};

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.note.title.length > 0 ? this.note.title : '未命名笔记')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .textShadow(NotesTheme.textShadow(this.isDark))
          .maxLines(1)
          .ellipsisMode(EllipsisMode.END)
          .layoutWeight(1)

        Text(formatTime(this.note.updatedAt))
          .fontSize(11)
          .fontColor(NotesTheme.secondaryText(this.isDark))
          .textShadow(NotesTheme.textShadow(this.isDark))
          .flexShrink(0)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.note.snippet.length > 0 ? this.note.snippet : '空白笔记')
        .fontSize(13)
        .lineHeight(19)
        .fontColor(NotesTheme.secondaryText(this.isDark))
        .textShadow(NotesTheme.textShadow(this.isDark))
        .maxLines(2)
        .ellipsisMode(EllipsisMode.END)
        .width('100%')

      Row({ space: 6 }) {
        Text(`${this.note.chars} 字`)
          .fontSize(11)
          .fontColor(NotesTheme.secondaryText(this.isDark))
        Blank()
        Text('打开')
          .fontSize(11)
          .fontColor(NotesTheme.ACCENT)
        Text('›')
          .fontSize(16)
          .fontColor(NotesTheme.ACCENT)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(14)
    .borderRadius(NotesTheme.cardRadius())
    .clip(true)
    .backgroundColor(NotesTheme.cardBase(this.isDark, this.lightSense))
    .backgroundBlurStyle(NotesTheme.cardBlurStyle(this.lightSense), { colorMode: ThemeColorMode.SYSTEM })
    .border({
      width: 1,
      color: NotesTheme.cardBorder(this.isDark)
    })
    .shadow({
      radius: 14,
      color: NotesTheme.cardShadow(this.isDark, this.lightSense),
      offsetX: 0,
      offsetY: 4
    })
    .onClick(() => {
      this.onOpen();
    })
  }
}
