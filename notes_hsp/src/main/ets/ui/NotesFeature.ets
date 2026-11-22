import { common } from '@kit.AbilityKit';
import { mediaquery, uiMaterial } from '@kit.ArkUI';
import { NotesSdk } from '../api/NotesSdk';
import { Note, NoteMeta, countChars, formatTime } from '../model/Note';
import { NoteCard } from './NoteCard';
import { EditorToolbar } from './EditorToolbar';
import { NotesMarkdownPreview } from './NotesMarkdownPreview';
import { NotesTheme } from './NotesTheme';

/**
 * Markdown 笔记的完整功能组件。
 *
 * 宿主 HAP 只负责：路由壳、壁纸、顶部状态栏/底部安全区；
 * 列表、编辑器、预览、删除确认、自动保存、本地仓库全部在这里（HSP 内）。
 */
@ComponentV2
export struct NotesFeature {
  /** 列表页返回宿主（编辑器内部返回列表，不调用它）。 */
  @Event onBack: () => void = () => {};
  /** 宿主底部安全区（px 字符串），由 HAP 的 SafeArea 计算后传入。 */
  @Param safeBottom: string = '0px';
  /** 宿主当前全局光感档位（0=关闭 1=柔和 2=标准 3=精致），由 HAP 传入。 */
  @Param lightSense: number = NotesTheme.LEVEL_EXQUISITE;

  @Local isDark: boolean = false;
  @Local mode: string = 'list';
  @Local notes: NoteMeta[] = [];
  @Local query: string = '';
  @Local loadError: string = '';
  @Local initialized: boolean = false;

  @Local editingId: string = '';
  @Local editingCreatedAt: number = 0;
  @Local isNewNote: boolean = false;
  @Local draftTitle: string = '';
  @Local draftContent: string = '';
  @Local savedTitle: string = '';
  @Local savedContent: string = '';
  @Local showPreview: boolean = false;
  @Local lastSavedAt: number = 0;

  private themeMq: mediaquery.MediaQueryListener | null = null;
  private autoSaveTimer: number = -1;

  aboutToAppear(): void {
    this.initTheme();
    this.initSdk();
  }

  aboutToDisappear(): void {
    this.themeMq?.off('change');
    this.themeMq = null;
    if (this.autoSaveTimer >= 0) {
      clearTimeout(this.autoSaveTimer);
      this.autoSaveTimer = -1;
    }
    if (this.mode === 'editor') {
      this.saveDraft(true);
    }
  }

  private initTheme(): void {
    try {
      // HarmonyOS 的深色模式媒体特征是 (dark-mode: true)；
      // 旧的 (display-mode: dark) 是 PWA 显示模式，不能用于判断深浅色。
      this.themeMq = this.getUIContext().getMediaQuery().matchMediaSync('(dark-mode: true)');
      this.isDark = this.themeMq.matches;
      this.themeMq.on('change', (event: mediaquery.MediaQueryResult) => {
        this.isDark = event.matches;
      });
    } catch (e) {
      this.isDark = false;
    }
  }

  private initSdk(): void {
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) {
        throw new Error('UIAbilityContext is unavailable');
      }
      NotesSdk.init(context as common.UIAbilityContext);
      this.initialized = true;
      this.loadError = '';
      this.refreshNotes();
    } catch (e) {
      this.initialized = false;
      this.loadError = '笔记仓库初始化失败';
      console.error(`NotesFeature init failed: ${JSON.stringify(e)}`);
    }
  }

  private refreshNotes(): void {
    if (!this.initialized) {
      return;
    }
    try {
      this.notes = NotesSdk.list();
    } catch (e) {
      console.error(`NotesFeature refresh failed: ${JSON.stringify(e)}`);
      this.loadError = '读取笔记失败';
    }
  }

  private filteredNotes(): NoteMeta[] {
    const keyword: string = this.query.trim().toLowerCase();
    if (keyword.length === 0) {
      return this.notes;
    }
    return this.notes.filter((note: NoteMeta) =>
      note.title.toLowerCase().includes(keyword) || note.snippet.toLowerCase().includes(keyword));
  }

  private isDirty(): boolean {
    return this.draftTitle !== this.savedTitle || this.draftContent !== this.savedContent;
  }

  private saveStateText(): string {
    if (this.isDirty()) {
      return '有未保存修改';
    }
    if (this.lastSavedAt > 0) {
      return `已保存 · ${formatTime(this.lastSavedAt)}`;
    }
    return '自动保存到应用沙箱';
  }

  private handleBack(): void {
    if (this.mode === 'editor') {
      this.backToList();
      return;
    }
    this.onBack();
  }

  private backToList(): void {
    this.saveDraft(true);
    this.mode = 'list';
    this.showPreview = false;
    this.refreshNotes();
  }

  private newNote(): void {
    if (!this.initialized) {
      this.initSdk();
    }
    if (!this.initialized) {
      this.toast(this.loadError.length > 0 ? this.loadError : '笔记仓库未初始化');
      return;
    }
    const draft: Note = NotesSdk.createDraft();
    this.editingId = draft.id;
    this.editingCreatedAt = draft.createdAt;
    this.isNewNote = true;
    this.draftTitle = '';
    this.draftContent = '';
    this.savedTitle = '';
    this.savedContent = '';
    this.lastSavedAt = 0;
    this.showPreview = false;
    this.mode = 'editor';
  }

  private openNote(id: string): void {
    if (!this.initialized) {
      this.toast(this.loadError.length > 0 ? this.loadError : '笔记仓库未初始化');
      return;
    }
    try {
      const note: Note | null = NotesSdk.load(id);
      if (note === null) {
        this.toast('笔记不存在或已被删除');
        this.refreshNotes();
        return;
      }
      this.editingId = note.id;
      this.editingCreatedAt = note.createdAt;
      this.isNewNote = false;
      this.draftTitle = note.title;
      this.draftContent = note.content;
      this.savedTitle = note.title;
      this.savedContent = note.content;
      this.lastSavedAt = note.updatedAt;
      this.showPreview = false;
      this.mode = 'editor';
    } catch (e) {
      console.error(`NotesFeature open failed: ${JSON.stringify(e)}`);
      this.toast('打开笔记失败');
    }
  }

  private saveDraft(silent: boolean = true): void {
    if (!this.initialized) {
      return;
    }
    if (this.isNewNote && this.draftTitle.trim().length === 0 && this.draftContent.trim().length === 0) {
      return;
    }
    try {
      const note: Note = new Note();
      note.id = this.editingId;
      note.createdAt = this.editingCreatedAt;
      note.title = this.draftTitle;
      note.content = this.draftContent;
      const saved: Note = NotesSdk.save(note);
      this.editingId = saved.id;
      this.editingCreatedAt = saved.createdAt;
      this.savedTitle = this.draftTitle;
      this.savedContent = this.draftContent;
      this.lastSavedAt = saved.updatedAt;
      this.isNewNote = false;
      this.refreshNotes();
      if (!silent) {
        this.toast('已保存');
      }
    } catch (e) {
      console.error(`NotesFeature save failed: ${JSON.stringify(e)}`);
      this.toast('保存失败，请重试');
    }
  }

  private scheduleAutoSave(): void {
    if (this.autoSaveTimer >= 0) {
      clearTimeout(this.autoSaveTimer);
    }
    this.autoSaveTimer = setTimeout(() => {
      this.autoSaveTimer = -1;
      this.saveDraft(true);
    }, 1200);
  }

  private requestDelete(): void {
    if (this.isNewNote) {
      this.mode = 'list';
      this.showPreview = false;
      this.refreshNotes();
      return;
    }
    this.showDeleteDialog();
  }

  /**
   * 删除确认使用官方 AlertDialog + systemMaterial。
   * 弹窗是官方支持沉浸光感的容器；内容区自绘控件不能直接用 systemMaterial。
   */
  private showDeleteDialog(): void {
    let material: uiMaterial.ImmersiveMaterial | undefined = undefined;
    try {
      if (uiMaterial.isImmersiveMaterialSupported()) {
        material = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THICK,
          colorInvert: true,
          applyShadow: true,
          interactive: true
        });
      }
    } catch (e) {
      material = undefined;
    }
    try {
      this.getUIContext().showAlertDialog({
        title: '删除这篇笔记？',
        message: '删除后无法恢复。',
        autoCancel: true,
        systemMaterial: material,
        primaryButton: {
          value: '取消',
          action: (): void => {}
        },
        secondaryButton: {
          value: '删除',
          fontColor: NotesTheme.DANGER,
          action: (): void => {
            this.confirmDeleteAction();
          }
        }
      });
    } catch (e) {
      console.error(`NotesFeature showAlertDialog failed: ${JSON.stringify(e)}`);
      this.toast('删除确认弹窗打开失败');
    }
  }

  private confirmDeleteAction(): void {
    try {
      NotesSdk.delete(this.editingId);
      this.mode = 'list';
      this.showPreview = false;
      this.refreshNotes();
      this.toast('已删除');
    } catch (e) {
      console.error(`NotesFeature delete failed: ${JSON.stringify(e)}`);
      this.toast('删除失败，请重试');
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1600
      });
    } catch (e) {
      console.error(`NotesFeature toast failed: ${JSON.stringify(e)}`);
    }
  }

  @Builder
  private backButton(): void {
    Stack() {
      Image($r('app.media.back_arrow'))
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
        .fillColor($r('sys.color.font_primary'))
    }
    .width(38)
    .height(38)
    .borderRadius(19)
    .clip(true)
    .backgroundColor(NotesTheme.cardBase(this.isDark, this.lightSense))
    .backgroundBlurStyle(NotesTheme.cardBlurStyle(this.lightSense), { colorMode: ThemeColorMode.SYSTEM })
    .border({
      width: 1,
      color: NotesTheme.cardBorder(this.isDark)
    })
    .shadow({
      radius: 8,
      color: NotesTheme.cardShadow(this.isDark, this.lightSense),
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => {
      this.handleBack();
    })
  }

  @Builder
  private addButton(): void {
    Stack() {
      Text('+')
        .fontSize(26)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_on_primary'))
    }
    .width(38)
    .height(38)
    .borderRadius(19)
    .backgroundColor(NotesTheme.ACCENT)
    .shadow({ radius: 10, color: 'rgba(10,89,247,0.35)', offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.newNote();
    })
  }

  @Builder
  private saveButton(): void {
    Button('保存')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(Color.White)
      .height(34)
      .padding({ left: 16, right: 16 })
      .borderRadius(17)
      .backgroundColor(NotesTheme.ACCENT)
      .onClick(() => {
        this.saveDraft(false);
      })
  }

  @Builder
  private header(): void {
    Row({ space: 12 }) {
      this.backButton()
      Column({ space: 2 }) {
        Text(this.mode === 'list' ? 'Markdown 笔记' : '编辑笔记')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_emphasize'))
          .textShadow(NotesTheme.textShadow(this.isDark))
          .maxLines(1)
          .ellipsisMode(EllipsisMode.END)
        Text(this.mode === 'list' ? `共 ${this.notes.length} 篇 · 本地保存`
          : this.saveStateText())
          .fontSize(12)
          .fontColor(NotesTheme.secondaryText(this.isDark))
          .textShadow(NotesTheme.textShadow(this.isDark))
          .maxLines(1)
          .ellipsisMode(EllipsisMode.END)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.mode === 'list') {
        this.addButton()
      } else {
        this.saveButton()
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 8, bottom: 4 })
  }

  @Builder
  private searchRow(): void {
    TextInput({ text: this.query, placeholder: '搜索标题或内容' })
      .width('100%')
      .height(42)
      .fontSize(14)
      .fontColor($r('sys.color.font_primary'))
      .placeholderColor(NotesTheme.secondaryText(this.isDark))
      .caretColor(NotesTheme.ACCENT)
      .backgroundColor(NotesTheme.inputBg(this.isDark))
      .backdropBlur(NotesTheme.inputBlur(this.lightSense))
      .border({
        width: 1,
        color: NotesTheme.inputBorder(this.isDark)
      })
      .borderRadius(NotesTheme.inputRadius())
      .padding({ left: 14, right: 14 })
      .onChange((value: string): void => {
        this.query = value;
      })
  }

  @Builder
  private emptyState(): void {
    Column({ space: 12 }) {
      Stack() {
        Text('M↓')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(NotesTheme.ACCENT)
      }
      .width(72)
      .height(72)
      .borderRadius(22)
      .backgroundColor(NotesTheme.chipBase(this.isDark, this.lightSense))
      .backdropBlur(NotesTheme.inputBlur(this.lightSense))
      .border({
        width: 1,
        color: NotesTheme.inputBorder(this.isDark)
      })

      Text(this.loadError.length > 0 ? this.loadError
        : (this.query.trim().length > 0 ? '没有匹配的笔记' : '还没有笔记'))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))

      Text(this.loadError.length > 0 ? '请检查应用存储权限后重试'
        : (this.query.trim().length > 0 ? '换个关键词试试' : '用 Markdown 记下第一个想法'))
        .fontSize(13)
        .fontColor(NotesTheme.secondaryText(this.isDark))
        .textAlign(TextAlign.Center)

      Button(this.loadError.length > 0 ? '重试' : (this.query.trim().length > 0 ? '清空搜索' : '新建笔记'))
        .fontSize(14)
        .fontColor(Color.White)
        .height(38)
        .padding({ left: 20, right: 20 })
        .borderRadius(19)
        .backgroundColor(NotesTheme.ACCENT)
        .onClick(() => {
          if (this.loadError.length > 0) {
            this.initSdk();
          } else if (this.query.trim().length > 0) {
            this.query = '';
          } else {
            this.newNote();
          }
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: 60 })
  }

  @Builder
  private listView(): void {
    Column({ space: 12 }) {
      this.searchRow()
      if (this.filteredNotes().length === 0) {
        this.emptyState()
      } else {
        List({ space: 10 }) {
          ForEach(this.filteredNotes(), (item: NoteMeta) => {
            ListItem() {
              NoteCard({
                note: item,
                isDark: this.isDark,
                lightSense: this.lightSense,
                onOpen: (): void => {
                  this.openNote(item.id);
                }
              })
            }
          }, (item: NoteMeta) => `${item.id}_${item.updatedAt}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private editorView(): void {
    Column({ space: 10 }) {
      EditorToolbar({
        showPreview: this.showPreview,
        isDark: this.isDark,
        lightSense: this.lightSense,
        charCount: countChars(this.draftContent),
        onTogglePreview: (preview: boolean): void => {
          if (preview) {
            this.saveDraft(true);
          }
          this.showPreview = preview;
        },
        onDelete: (): void => {
          this.requestDelete();
        }
      })

      TextInput({ text: this.draftTitle, placeholder: '笔记标题（留空则自动取一级标题）' })
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor(NotesTheme.secondaryText(this.isDark))
        .caretColor(NotesTheme.ACCENT)
        .backgroundColor(NotesTheme.inputBg(this.isDark))
        .backdropBlur(NotesTheme.inputBlur(this.lightSense))
        .border({
          width: 1,
          color: NotesTheme.inputBorder(this.isDark)
        })
        .borderRadius(NotesTheme.inputRadius())
        .padding({ left: 14, right: 14 })
        .onChange((value: string): void => {
          this.draftTitle = value;
          this.scheduleAutoSave();
        })

      if (this.showPreview) {
        Scroll() {
          NotesMarkdownPreview({
            text: this.draftContent,
            isDark: this.isDark
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .clip(true)
        .backgroundColor(NotesTheme.previewBase(this.isDark, this.lightSense))
        .backgroundBlurStyle(NotesTheme.cardBlurStyle(this.lightSense), { colorMode: ThemeColorMode.SYSTEM })
        .border({
          width: 1,
          color: NotesTheme.cardBorder(this.isDark)
        })
        .borderRadius(NotesTheme.cardRadius())
        .shadow({
          radius: 12,
          color: NotesTheme.cardShadow(this.isDark, this.lightSense),
          offsetX: 0,
          offsetY: 4
        })
        .padding(14)
      } else {
        TextArea({ text: this.draftContent, placeholder: '用 Markdown 写下你的想法…' })
          .width('100%')
          .layoutWeight(1)
          .fontSize(15)
          .lineHeight(23)
          .fontColor($r('sys.color.font_primary'))
          .placeholderColor(NotesTheme.secondaryText(this.isDark))
          .caretColor(NotesTheme.ACCENT)
          .backgroundColor(NotesTheme.inputBg(this.isDark))
          .backdropBlur(NotesTheme.inputBlur(this.lightSense))
          .border({
            width: 1,
            color: NotesTheme.inputBorder(this.isDark)
          })
          .borderRadius(NotesTheme.cardRadius())
          .padding(14)
          .onChange((value: string): void => {
            this.draftContent = value;
            this.scheduleAutoSave();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    Stack() {
      Column({ space: 10 }) {
        this.header()
        if (this.mode === 'list') {
          this.listView()
        } else {
          this.editorView()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: this.safeBottom })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
    .backgroundColor(Color.Transparent)
  }
}
