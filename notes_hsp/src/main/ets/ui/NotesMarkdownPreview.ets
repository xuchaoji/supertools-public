import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';
import { pasteboard } from '@kit.BasicServicesKit';

/**
 * Markdown 预览。
 *
 * 用 text 模式渲染：正文来自编辑器内存，不经过 rawfile/sandbox 加载，避免路径问题。
 * 关闭子线程渲染与 Mermaid：笔记场景内容不大，关闭后少一个 HSP 内 Worker 路径依赖；
 * 需要时可以在这里打开 setThreadRenderEnable(true) 做性能对比。
 */
@ComponentV2
export struct NotesMarkdownPreview {
  @Param text: string = '';
  @Param isDark: boolean = false;
  private controller: MarkdownController = new MarkdownController();

  aboutToAppear(): void {
    this.applyStyle();
  }

  @Monitor('isDark')
  onThemeChanged(): void {
    this.applyStyle();
  }

  private applyStyle(): void {
    try {
      const codeTheme: 'light' | 'dark' = this.isDark ? 'dark' : 'light';
      const textColor: string = this.isDark ? '#E8E8EA' : '#1A1A1A';
      const titleColor: string = this.isDark ? '#FFFFFF' : '#111111';
      const mutedBorder: string = this.isDark ? 'rgba(255, 255, 255, 0.18)' : 'rgba(0, 0, 0, 0.12)';

      this.controller
        .setThreadRenderEnable(false)
        .setMermaidEnable(false)
        .setLazyRender(false)
        .setTextColor(textColor)
        .setTitleColor(titleColor)
        .setTextSize(15)
        .setTitleSize([24, 21, 18, 16, 15, 14])
        .setQuoteTextColor(textColor)
        .setQuoteBackgroundColor(this.isDark ? 'rgba(255, 255, 255, 0.06)' : 'rgba(0, 0, 0, 0.04)')
        .setQuoteBorderColor(this.isDark ? 'rgba(10, 89, 247, 0.65)' : 'rgba(10, 89, 247, 0.45)')
        .setQuoteBorderWidth(3)
        .setInlineCodeBackgroundColor(this.isDark ? 'rgba(255, 255, 255, 0.10)' : 'rgba(0, 0, 0, 0.06)')
        .setCodeBlockTheme(codeTheme)
        .setCodeBlockBorderRadius(10)
        .setLatexMathTextColor(this.isDark ? 0xFFE8E8EA : 0xFF1A1A1A)
        .setTableBackgroundColor(this.isDark ? 'rgba(255, 255, 255, 0.03)' : 'rgba(0, 0, 0, 0.02)')
        .setTableTitleBackgroundColor(this.isDark ? 'rgba(255, 255, 255, 0.10)' : 'rgba(0, 0, 0, 0.06)')
        .setTableTitleTextColor(titleColor)
        .setTableInterleaveBackgroundColor(this.isDark ? 'rgba(255, 255, 255, 0.04)' : 'rgba(0, 0, 0, 0.03)')
        .setTableOuterBorderColor(mutedBorder)
        .setTableInnerBorderColor(this.isDark ? 'rgba(255, 255, 255, 0.12)' : 'rgba(0, 0, 0, 0.08)')
        .setTableActionBackgroundColor(this.isDark ? 'rgba(255, 255, 255, 0.10)' : 'rgba(0, 0, 0, 0.06)')
        .setTableActionIconColor(textColor)
        .setTableBorderRadius(12)
        .setImageBorderRadius(12)
        .setCodeCopyListener((text: string): void => {
          // SDK 从 v3.1.0 起不再直接写剪贴板，由宿主通过监听器自行实现。
          try {
            const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
            pasteboard.getSystemPasteboard().setData(data);
          } catch (e) {
            console.error(`NotesMarkdownPreview copy failed: ${JSON.stringify(e)}`);
          }
        });

      // 这两个接口返回 void，不能串进上面的链式调用。
      this.controller.setTableNormalTextColor(textColor);
      this.controller.setTableInterleaveTextColor(textColor);
    } catch (e) {
      console.error(`NotesMarkdownPreview applyStyle failed: ${JSON.stringify(e)}`);
    }
  }

  build() {
    Column() {
      Markdown({ text: this.text, controller: this.controller })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 2, right: 2, bottom: 20 })
  }
}
