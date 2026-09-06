import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import promptAction from '@ohos.promptAction';
import pasteboard from '@ohos.pasteboard';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { mediaquery } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { PreferencesUtil } from '@pura/harmony-utils';
import { URLParserUtil, ParsedQueryParam, ParsedURLResult } from '../utils/URLParserUtil';
import { GlobalContextHolder } from '../utils/GlobalContextHolder';
import { WallpaperHost } from '../components/WallpaperHost';
import { ScanQrOverlay } from '../components/ScanQrOverlay';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';
import { LinkHistoryUtil, LinkHistoryItem } from '../utils/UrlHistoryUtil';
import { SpKeys } from '../constant/SpKeys';

const TAG: string = 'H5Page';

/** bindMenu 菜单项（与 LocalWebPage 同款结构，ArkUI 按结构匹配） */
interface MenuElement {
  value: string;
  action: () => void;
}

/**
 * H5 页面打开：与「App Linking 解析」同一家族的 URL 工具，但聚焦 http/https H5 页面。
 * 功能对齐 AppLinkingTool（URLParserUtil 解析、扫码输入、复制、拉起浏览器），
 * 打开后在本页面内切换为「H5 容器页」布局（顶栏返回 + 居中标题 + 右上角「…」菜单 + Web 内容区），
 * 布局参照 hdc 抓取记录：docs/superpowers/specs/2026-09-06-h5-viewer-page.md。
 */
@HMRouter({ pageUrl: 'h5Page' })
@ComponentV2
export struct H5Page {
  /** 输入框链接 */
  @Local inputUrl: string = '';
  /** 解析结果（「解析」按钮或「打开 H5」时刷新） */
  @Local parsedResult: ParsedURLResult = URLParserUtil.parse('');
  /** 当前打开的 H5 地址（非空 = 查看态） */
  @Local openedUrl: string = '';
  /** 顶栏显示的网页标题（未取到前用 host） */
  @Local webTitle: string = '';
  /** 网页加载中（刷新/跳转时置 true） */
  @Local webLoading: boolean = false;
  /** 沉浸光感：跟随系统深/浅色模式 */
  @Local isDark: boolean = false;
  /** 扫码解析开关（与 AppLinkingTool 同一 SpKey，设置页彩蛋开启后显示按钮） */
  @Local isScanVisible: boolean = false;
  /** 是否正在扫码（全屏扫码浮层） */
  @Local isScanning: boolean = false;
  /** 打开历史（最新在前，持久化于 SpKeys.H5_HISTORY） */
  @Local historyList: LinkHistoryItem[] = [];
  private webController: webview.WebviewController = new webview.WebviewController();
  private themeMq: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    this.initThemeListener();
    this.isScanVisible = PreferencesUtil.getBooleanSync(SpKeys.ENABLE_SCAN_PARSE, false);
    this.historyList = LinkHistoryUtil.load(SpKeys.H5_HISTORY);
  }

  aboutToDisappear(): void {
    this.themeMq?.off('change');
    this.themeMq = null;
  }

  /** 订阅系统深/浅色模式变化，驱动文字阴影等可读性参数 */
  private initThemeListener(): void {
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

  /**
   * 链接规范化：补全缺失的 http(s) 协议。
   * 无协议时按 https 处理（域名 / IP / localhost），其它自定义 scheme 原样返回，由调用方拒绝。
   */
  private normalizeUrl(raw: string): string {
    const url: string = raw.trim();
    if (url.length === 0) {
      return '';
    }
    const lower: string = url.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return url;
    }
    if (url.indexOf('://') !== -1) {
      return url;
    }
    return 'https://' + url;
  }

  /** 仅 http/https 才允许应用内打开 */
  private isHttpScheme(parsed: ParsedURLResult): boolean {
    const scheme: string = (parsed.scheme || '').toLowerCase();
    return scheme === 'http' || scheme === 'https';
  }

  private clearInput(): void {
    this.inputUrl = '';
    this.parsedResult = URLParserUtil.parse('');
  }

  /** 「解析」：复用 URLParserUtil 拆解链接，在下方展示基础信息卡片 */
  private doParse(): void {
    const url: string = this.normalizeUrl(this.inputUrl);
    if (url.length === 0) {
      promptAction.showToast({ message: '请输入链接', duration: 1500 });
      return;
    }
    this.inputUrl = url;
    this.parsedResult = URLParserUtil.parse(url);
    if (!this.parsedResult.valid) {
      promptAction.showToast({ message: this.parsedResult.errorMessage || '链接格式无效', duration: 1500 });
    } else if (!this.isHttpScheme(this.parsedResult)) {
      promptAction.showToast({ message: '非 http/https 链接，应用内无法打开 H5', duration: 2000 });
    }
  }

  /** 「打开 H5」：校验后原地切到查看态（当前页面布局展示 H5） */
  private openH5(): void {
    const url: string = this.normalizeUrl(this.inputUrl);
    if (url.length === 0) {
      promptAction.showToast({ message: '请输入链接', duration: 1500 });
      return;
    }
    this.inputUrl = url;
    const parsed: ParsedURLResult = URLParserUtil.parse(url);
    this.parsedResult = parsed;
    if (!parsed.valid) {
      promptAction.showToast({ message: parsed.errorMessage || '链接格式无效', duration: 1500 });
      return;
    }
    if (!this.isHttpScheme(parsed)) {
      promptAction.showToast({ message: '仅支持 http/https 链接在应用内打开', duration: 2000 });
      return;
    }
    this.webTitle = parsed.hostname ? parsed.hostname : url;
    this.webLoading = true;
    this.openedUrl = url;
    // 记录历史（最新在前、去重、上限 30）
    this.historyList = LinkHistoryUtil.add(this.historyList, url);
    LinkHistoryUtil.persist(SpKeys.H5_HISTORY, this.historyList);
  }

  /** 历史：删除单条 */
  private removeHistory(index: number): void {
    if (index < 0 || index >= this.historyList.length) {
      return;
    }
    this.historyList = LinkHistoryUtil.remove(this.historyList, index);
    LinkHistoryUtil.persist(SpKeys.H5_HISTORY, this.historyList);
  }

  /** 历史：清空 */
  private clearHistory(): void {
    this.historyList = [];
    LinkHistoryUtil.persist(SpKeys.H5_HISTORY, []);
    promptAction.showToast({ message: '历史已清空', duration: 1000 });
  }

  /** 历史：点击回填输入框并解析（不自动打开） */
  private useHistoryItem(item: LinkHistoryItem): void {
    this.inputUrl = item.text;
    this.doParse();
  }

  /** 查看态顶栏返回：退出查看回到输入态（保留输入链接） */
  private exitViewer(): void {
    this.openedUrl = '';
    this.webTitle = '';
    this.webLoading = false;
  }

  /** 扫码回填：与 AppLinkingTool 一致，识别结果填入输入框并解析 */
  private handleScanResult(text: string): void {
    this.isScanning = false;
    const url: string = this.normalizeUrl(text);
    this.inputUrl = url;
    this.parsedResult = URLParserUtil.parse(url);
    if (this.parsedResult.valid && this.isHttpScheme(this.parsedResult)) {
      promptAction.showToast({ message: '扫码成功，可点击「打开 H5」', duration: 1500 });
    } else {
      promptAction.showToast({ message: '未识别到 http/https 链接', duration: 2000 });
    }
  }

  private copyText(value: string): void {
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      const pasteData = pasteboard.createData('text/plain', value);
      systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: '已复制', duration: 800 });
    } catch (err) {
      promptAction.showToast({ message: '复制失败', duration: 1000 });
    }
  }

  /** 右上角「…」→ 用系统浏览器打开当前 H5 */
  private async openInSystemBrowser(): Promise<void> {
    const url: string = this.openedUrl;
    if (url.length === 0) {
      return;
    }
    try {
      const context: common.UIAbilityContext | undefined = GlobalContextHolder.getInstance().uiAbilityContext;
      if (!context) {
        promptAction.showToast({ message: '无法获取应用上下文', duration: 1500 });
        return;
      }
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url
      };
      await context.startAbility(want);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      promptAction.showToast({
        message: '打开失败: ' + (error.message || '未知错误'),
        duration: 2500
      });
    }
  }

  /** 右上角「…」菜单：刷新 / 复制链接 / 用浏览器打开 */
  private viewerMenuItems(): MenuElement[] {
    const items: MenuElement[] = [
      {
        value: '刷新',
        action: (): void => {
          try {
            this.webLoading = true;
            this.webController.refresh();
          } catch (err) {
            console.error(`[${TAG}] refresh failed: ${JSON.stringify(err)}`);
            this.webLoading = false;
          }
        }
      },
      {
        value: '复制链接',
        action: (): void => {
          this.copyText(this.openedUrl);
        }
      },
      {
        value: '用浏览器打开',
        action: (): void => {
          this.openInSystemBrowser();
        }
      }
    ];
    return items;
  }

  /** 网页标题兜底刷新（onPageEnd 后 controller.getTitle() 才稳定可用） */
  private refreshWebTitle(): void {
    try {
      const title: string = this.webController.getTitle();
      if (title && title.trim().length > 0) {
        this.webTitle = title;
      }
    } catch (err) {
      console.error(`[${TAG}] getTitle failed: ${JSON.stringify(err)}`);
    }
  }

  build() {
    if (this.isScanning) {
      ScanQrOverlay({
        title: '扫码识别 H5 链接',
        onResult: (text: string) => {
          this.handleScanResult(text);
        },
        onCancel: () => {
          this.isScanning = false;
        }
      })
    } else {
      // 全局壁纸宿主：输入态继承主页沉浸光感壁纸；查看态顶栏透出壁纸毛玻璃
      WallpaperHost() {
        if (this.openedUrl.length > 0) {
          this.ViewerLayout();
        } else {
          this.InputLayout();
        }
      }
    }
  }

  // ===================== 输入态（标题/输入卡固定顶部，下部内容可滚动） =====================

  @Builder
  InputLayout() {
    Column() {
      // ---------- 顶部固定区：标题栏 + 输入卡片 ----------
      Column({ space: 12 }) {
        // 标题栏
        Row() {
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
          // 返回按钮玻璃圆底：任意壁纸背景下都清晰可见
          .backgroundColor(this.isDark ? 'rgba(255, 255, 255, 0.16)' : 'rgba(255, 255, 255, 0.9)')
          .border({ width: 1, color: ImmersiveStyles.cardOuterRim(this.isDark) })
          .shadow({ radius: 8, color: ImmersiveStyles.cardShadow(this.isDark), offsetX: 0, offsetY: 2 })
          .onClick(() => {
            HMRouterMgr.pop();
          })

          Column({ space: 2 }) {
            Text('H5 页面打开')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_emphasize'))
              .textShadow(ImmersiveStyles.textShadow(this.isDark))
            Text('输入链接，应用内打开 H5 网页')
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
              .textShadow(ImmersiveStyles.textShadow(this.isDark))
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12 })
        }
        .width('100%')

        // 输入卡片
        Column({ space: 10 }) {
          Row() {
            Text('链接地址')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Text('[清空]')
              .fontSize(11)
              .fontColor($r('sys.color.font_secondary'))
              .fontFamily('monospace')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .border({ width: 1, color: $r('sys.color.comp_background_emphasize'), style: BorderStyle.Dashed })
              .borderRadius(4)
              .onClick(() => this.clearInput())
          }
          .width('100%')

          TextArea({
            text: this.inputUrl,
            placeholder: '输入 https:// 链接（H5 页面），或扫码识别'
          })
            .height(88)
            .width('100%')
            .fontSize(14)
            .fontFamily('monospace')
            .fontColor($r('sys.color.font_primary'))
            .placeholderFont({ size: 13 })
            .placeholderColor($r('sys.color.font_secondary'))
            .padding(10)
            .backgroundColor('rgba(128, 128, 128, 0.12)')
            .borderRadius(10)
            .onChange((value: string) => {
              this.inputUrl = value;
            })

          // 与 AppLinkingTool 一致：扫码解析 / 解析 / 打开（扫码入口受 ENABLE_SCAN_PARSE 开关控制）
          Row({ space: 10 }) {
            Button() {
              Text('扫码解析')
                .fontSize(13)
            }
            .height(44)
            .layoutWeight(1)
            .borderRadius(8)
            .backgroundColor($r('sys.color.comp_background_gray'))
            .fontColor($r('sys.color.font_secondary'))
            .visibility(this.isScanVisible ? Visibility.Visible : Visibility.None)
            .onClick(() => {
              this.isScanning = true;
            })

            Button() {
              Text('解析')
                .fontSize(13)
            }
            .height(44)
            .layoutWeight(1)
            .borderRadius(8)
            .backgroundColor($r('sys.color.comp_background_gray'))
            .fontColor($r('sys.color.font_secondary'))
            .onClick(() => this.doParse())

            Button() {
              Text('打开 H5')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
            }
            .height(44)
            .layoutWeight(1)
            .borderRadius(8)
            .onClick(() => this.openH5())
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(ImmersiveStyles.cardBase(this.isDark))
        .backdropBlur(ImmersiveStyles.cardBlurRadius())
        .borderRadius(12)
        .border({ width: 1, color: ImmersiveStyles.cardOuterRim(this.isDark) })
        .clip(true)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })

      Divider()
        .color($r('sys.color.comp_background_emphasize'))
        .margin({ top: 12 })

      // ---------- 下部可滚动区：解析信息 / 提示 / 历史记录 ----------
      Scroll() {
        Column({ space: 12 }) {
          if (this.parsedResult.valid) {
            this.BasicInfoCard()
            if (this.parsedResult.queryParams.length > 0) {
              this.QueryParamsCard()
            }
          } else if (this.historyList.length === 0) {
            // 无历史：占满提示区并垂直居中（空态观感）
            Column() {
              if (this.inputUrl.trim().length > 0 && this.parsedResult.errorMessage.length > 0) {
                Text(this.parsedResult.errorMessage)
                  .fontSize(13)
                  .fontColor($r('sys.color.font_emphasize'))
                  .fontFamily('monospace')
                  .textAlign(TextAlign.Center)
                  .width('100%')
              } else {
                Text('输入或扫码 http(s) 链接后点「打开 H5」在应用内浏览\n点「解析」可先查看链接拆解')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
                  .opacity(0.6)
                  .textAlign(TextAlign.Center)
                  .width('100%')
              }
            }
            .width('100%')
            .constraintSize({ minHeight: '100%' })
            .justifyContent(FlexAlign.Center)
          } else {
            // 已有历史：紧凑提示，紧贴历史卡片，避免把历史挤到屏幕外
            Column() {
              if (this.inputUrl.trim().length > 0 && this.parsedResult.errorMessage.length > 0) {
                Text(this.parsedResult.errorMessage)
                  .fontSize(13)
                  .fontColor($r('sys.color.font_emphasize'))
                  .fontFamily('monospace')
                  .textAlign(TextAlign.Center)
                  .width('100%')
              } else {
                Text('输入或扫码 http(s) 链接后点「打开 H5」在应用内浏览')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
                  .opacity(0.6)
                  .textAlign(TextAlign.Center)
                  .width('100%')
              }
            }
            .width('100%')
            .padding({ top: 10, bottom: 4 })
          }

          // ---------- 历史记录 ----------
          if (this.historyList.length > 0) {
            this.HistorySection()
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 32 })
        .constraintSize({ minHeight: '100%' })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  HistorySection() {
    Column() {
      Row() {
        Circle({ width: 8, height: 8 })
          .fill($r('sys.color.comp_foreground_primary'))
        Text('历史记录')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_emphasize'))
          .margin({ left: 6 })
        Text(`(${this.historyList.length})`)
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .fontFamily('monospace')
          .margin({ left: 4 })
        Blank()
        Text('清空')
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .fontFamily('monospace')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .border({ width: 1, color: $r('sys.color.comp_background_emphasize'), style: BorderStyle.Dashed })
          .borderRadius(4)
          .onClick(() => this.clearHistory())
      }
      .width('100%')
      .padding({ bottom: 6 })

      ForEach(this.historyList, (item: LinkHistoryItem, index: number) => {
        Row() {
          Text(LinkHistoryUtil.formatTime(item.ts))
            .fontSize(10)
            .fontColor($r('sys.color.font_secondary'))
            .fontFamily('monospace')
            .constraintSize({ minWidth: 44 })
          Text(item.text)
            .fontSize(12)
            .fontColor($r('sys.color.font_primary'))
            .fontFamily('monospace')
            .maxLines(1)
            .ellipsisMode(EllipsisMode.END)
            .layoutWeight(1)
            .margin({ left: 8, right: 8 })
          Text('✕')
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor('rgba(128, 128, 128, 0.15)')
            .onClick(() => this.removeHistory(index))
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(8)
        .backgroundColor('rgba(128, 128, 128, 0.10)')
        // 点击历史：回填输入框并解析
        .onClick(() => this.useHistoryItem(item))
      }, (item: LinkHistoryItem, index: number) => item.ts.toString() + '_' + index.toString())
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.background_secondary'))
    .borderRadius(10)
    .border({ width: 1, color: $r('sys.color.comp_background_emphasize') })
  }

  @Builder
  BasicInfoCard() {
    Column() {
      Row() {
        Circle({ width: 8, height: 8 })
          .fill($r('sys.color.comp_foreground_primary'))
        Text('链接信息')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_emphasize'))
          .margin({ left: 6 })
        Blank()
        Text(this.isHttpScheme(this.parsedResult) ? 'H5' : '非H5')
          .fontSize(9)
          .fontColor($r('sys.color.font_secondary'))
          .fontFamily('monospace')
          .backgroundColor($r('sys.color.comp_background_gray'))
          .borderRadius(4)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      }
      .width('100%')
      .padding({ bottom: 4 })

      Text(this.parsedResult.rawUrl)
        .fontSize(10)
        .fontColor($r('sys.color.font_secondary'))
        .fontFamily('monospace')
        .width('100%')
        .opacity(0.55)
        .padding({ bottom: 8 })
        .wordBreak(WordBreak.BREAK_ALL)

      Column({ space: 0 }) {
        if (this.parsedResult.scheme) {
          this.InfoRow('scheme', this.parsedResult.scheme + '://')
        }
        if (this.parsedResult.hostname) {
          this.InfoRow('host', this.parsedResult.hostname)
        }
        if (this.parsedResult.port) {
          this.InfoRow('port', this.parsedResult.port)
        }
        if (this.parsedResult.pathname) {
          this.InfoRow('path', this.parsedResult.pathname)
        }
        if (this.parsedResult.fragment) {
          this.InfoRow('hash', '#' + this.parsedResult.fragment)
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.background_secondary'))
    .borderRadius(10)
    .border({ width: 1, color: $r('sys.color.comp_background_emphasize') })
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .fontFamily('monospace')
        .constraintSize({ minWidth: 52 })
        .padding({ right: 10 })

      Text(value)
        .fontSize(12)
        .fontColor($r('sys.color.font_primary'))
        .fontFamily('monospace')
        .layoutWeight(1)
        .ellipsisMode(EllipsisMode.END)
        .maxLines(2)

      Text('复制')
        .fontSize(9)
        .fontColor($r('sys.color.font_secondary'))
        .fontFamily('monospace')
        .margin({ left: 6 })
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .border({ width: 0.5, color: $r('sys.color.comp_background_emphasize') })
        .borderRadius(4)
        .onClick(() => this.copyText(value))
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
    .border({
      width: { bottom: 0.5 },
      color: $r('sys.color.comp_background_emphasize')
    })
  }

  @Builder
  QueryParamsCard() {
    Column() {
      Row() {
        Circle({ width: 8, height: 8 })
          .fill($r('sys.color.comp_foreground_primary'))
        Text('Query 参数')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_emphasize'))
          .margin({ left: 6 })
        Blank()
        Text('[' + this.parsedResult.queryParams.length.toString() + ']')
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .fontFamily('monospace')
          .backgroundColor($r('sys.color.comp_background_gray'))
          .borderRadius(10)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      }
      .width('100%')
      .padding({ bottom: 10 })

      ForEach(this.parsedResult.queryParams, (param: ParsedQueryParam, index: number) => {
        this.QueryParamRow(param, index, this.parsedResult.queryParams.length)
      }, (param: ParsedQueryParam, index: number) => param.key + '_' + index.toString())
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.background_secondary'))
    .borderRadius(10)
    .border({ width: 1, color: $r('sys.color.comp_background_emphasize') })
  }

  @Builder
  QueryParamRow(param: ParsedQueryParam, index: number, total: number) {
    Column() {
      Row() {
        Text(param.key)
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .fontFamily('monospace')
          .fontWeight(FontWeight.Medium)
          .constraintSize({ minWidth: 70, maxWidth: 110 })
          .ellipsisMode(EllipsisMode.END)
          .maxLines(1)
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .backgroundColor($r('sys.color.comp_background_gray'))
          .borderRadius(4)

        Text(' = ')
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .fontFamily('monospace')
          .opacity(0.5)
          .margin({ left: 4, right: 4 })

        Text(param.decodedValue)
          .fontSize(11)
          .fontColor($r('sys.color.font_primary'))
          .fontFamily('monospace')
          .layoutWeight(1)
          .ellipsisMode(EllipsisMode.END)
          .maxLines(1)

        Text('C')
          .fontSize(9)
          .fontColor($r('sys.color.font_secondary'))
          .fontFamily('monospace')
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .backgroundColor($r('sys.color.comp_background_gray'))
          .borderRadius(3)
          .margin({ left: 6 })
          .onClick(() => this.copyText(param.value))
      }
      .width('100%')
      .padding({ top: 7, bottom: 7 })

      if (index < total - 1) {
        Divider()
          .color($r('sys.color.comp_background_emphasize'))
          .strokeWidth(0.5)
      }
    }
    .width('100%')
  }

  // ===================== 查看态（H5 容器页布局） =====================

  @Builder
  ViewerLayout() {
    Column() {
      // ---------- 顶栏：返回 + 居中标题 + 「…」菜单（对应 hdc 抓取的 H5 容器页布局） ----------
      Row() {
        Row() {
          Stack() {
            Image($r('app.media.back_arrow'))
              .width(18)
              .height(18)
              .objectFit(ImageFit.Contain)
              .fillColor($r('sys.color.font_primary'))
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(this.isDark ? 'rgba(255, 255, 255, 0.16)' : 'rgba(255, 255, 255, 0.9)')
          .border({ width: 1, color: ImmersiveStyles.cardOuterRim(this.isDark) })
          .shadow({ radius: 6, color: ImmersiveStyles.cardShadow(this.isDark), offsetX: 0, offsetY: 2 })
          .onClick(() => this.exitViewer())
        }
        .width(64)
        .justifyContent(FlexAlign.Start)

        Text(this.webTitle.length > 0 ? this.webTitle : 'H5 页面')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_emphasize'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .layoutWeight(1)

        Row() {
          Stack() {
            Text('⋮')
              .fontSize(24)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(this.isDark ? 'rgba(255, 255, 255, 0.16)' : 'rgba(255, 255, 255, 0.9)')
          .border({ width: 1, color: ImmersiveStyles.cardOuterRim(this.isDark) })
          .shadow({ radius: 6, color: ImmersiveStyles.cardShadow(this.isDark), offsetX: 0, offsetY: 2 })
          .bindMenu(this.viewerMenuItems())
        }
        .width(64)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .height(60)
      .padding({ left: 8, right: 8 })
      .backgroundColor(this.isDark ? 'rgba(0, 0, 0, 0.25)' : 'rgba(255, 255, 255, 0.55)')
      .backdropBlur(24)

      Divider()
        .color($r('sys.color.comp_background_emphasize'))
        .strokeWidth(0.5)

      // ---------- Web 内容区：铺满剩余空间 ----------
      Web({ src: this.openedUrl, controller: this.webController })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onlineImageAccess(true)
        .onPageBegin(() => {
          this.webLoading = true;
        })
        .onPageEnd(() => {
          this.webLoading = false;
          this.refreshWebTitle();
        })
        .onTitleReceive((event) => {
          if (event && event.title && event.title.trim().length > 0) {
            this.webTitle = event.title;
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
