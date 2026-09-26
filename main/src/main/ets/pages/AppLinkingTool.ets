import { HMRouter } from '@hadss/hmrouter';
import promptAction from '@ohos.promptAction';
import pasteboard from '@ohos.pasteboard';
import { URLParserUtil, ParsedQueryParam, ParsedURLResult } from '../utils/URLParserUtil';
import { GlobalContextHolder } from '../utils/GlobalContextHolder';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PreferencesUtil } from '@pura/harmony-utils';
import { SpKeys } from '../constant/SpKeys';
import { LinkHistoryUtil, LinkHistoryItem } from '../utils/UrlHistoryUtil';
import { WallpaperHost } from '../components/WallpaperHost';
import { PageHeader } from '../components/PageHeader';
import { GlassCard } from '../components/GlassCard';
import { GlassButton } from '../components/GlassButton';
import { SafeArea } from '../utils/SafeArea';
import { ScanQrOverlay } from '../components/ScanQrOverlay';
import { mediaquery } from '@kit.ArkUI';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';

const TAG: string = 'AppLinkingTool';

@HMRouter({ pageUrl: 'appLinkingTool' })
@ComponentV2
export struct AppLinkingTool {
  @Local inputUrl: string = '';
  @Local parsedResult: ParsedURLResult = URLParserUtil.parse('');
  @Local isScanning: boolean = false;
  @Local isScanVisible: boolean = false;
  /** 解析/拉起历史（最新在前，持久化于 SpKeys.APP_LINKING_HISTORY） */
  @Local historyList: LinkHistoryItem[] = [];
  /** 拉起方式：true=openLink（App Linking/深链官方入口）；false=startAbility(viewData 传统拉起） */
  @Local launchViaOpenLink: boolean = true;
  @Local safeBottom: string = '0px';
  /** 沉浸光感：跟随系统深/浅色模式（驱动输入框 rim 亮边与文字阴影） */
  @Local isDark: boolean = false;
  private themeMq: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    this.safeBottom = SafeArea.bottom();
    try {
      this.themeMq = this.getUIContext().getMediaQuery().matchMediaSync('(display-mode: dark)');
      this.isDark = this.themeMq.matches;
      this.themeMq.on('change', (event: mediaquery.MediaQueryResult) => {
        this.isDark = event.matches;
      });
    } catch (e) {
      this.isDark = false;
    }
    this.historyList = LinkHistoryUtil.load(SpKeys.APP_LINKING_HISTORY);
    this.launchViaOpenLink = PreferencesUtil.getBooleanSync(SpKeys.APP_LINK_LAUNCH_MODE, true);
    this.isScanVisible = PreferencesUtil.getBooleanSync(SpKeys.ENABLE_SCAN_PARSE, false);
    let storedResult: string | undefined = AppStorage.get<string>('appLinkingScannedUrl');
    if (storedResult && storedResult.length > 0) {
      this.inputUrl = storedResult;
      this.parsedResult = URLParserUtil.parse(storedResult);
      AppStorage.set('appLinkingScannedUrl', '');
    }
  }

  aboutToDisappear(): void {
    this.themeMq?.off('change');
    this.themeMq = null;
  }

  private doParse(): void {    this.parsedResult = URLParserUtil.parse(this.inputUrl);
    if (!this.parsedResult.valid && this.inputUrl.trim().length > 0) {
      promptAction.showToast({ message: this.parsedResult.errorMessage || '无效的链接格式', duration: 1500 });
    } else if (this.parsedResult.valid) {
      this.saveHistory(this.inputUrl.trim());
    }
  }

  private clearInput(): void {
    this.inputUrl = '';
    this.parsedResult = URLParserUtil.parse('');
  }

  /** 记录历史（最新在前、去重、上限 30） */
  private saveHistory(text: string): void {
    this.historyList = LinkHistoryUtil.add(this.historyList, text);
    LinkHistoryUtil.persist(SpKeys.APP_LINKING_HISTORY, this.historyList);
  }

  /** 历史：删除单条 */
  private removeHistory(index: number): void {
    if (index < 0 || index >= this.historyList.length) {
      return;
    }
    this.historyList = LinkHistoryUtil.remove(this.historyList, index);
    LinkHistoryUtil.persist(SpKeys.APP_LINKING_HISTORY, this.historyList);
  }

  /** 历史：清空 */
  private clearHistory(): void {
    this.historyList = [];
    LinkHistoryUtil.persist(SpKeys.APP_LINKING_HISTORY, []);
    promptAction.showToast({ message: '历史已清空', duration: 1000 });
  }

  /** 历史：点击回填输入框并解析 */
  private useHistoryItem(item: LinkHistoryItem): void {
    this.inputUrl = item.text;
    this.doParse();
  }

  private async launchDeepLink(): Promise<void> {
    let url: string = this.inputUrl.trim();
    if (url.length === 0) {
      promptAction.showToast({ message: '请输入链接', duration: 1500 });
      return;
    }

    if (!this.parsedResult.valid || this.parsedResult.rawUrl !== url) {
      this.doParse();
    }
    if (!this.parsedResult.valid) {
      return;
    }

    try {
      let context: common.UIAbilityContext | undefined = GlobalContextHolder.getInstance().uiAbilityContext;
      if (!context) {
        promptAction.showToast({ message: '无法获取应用上下文', duration: 1500 });
        return;
      }

      if (this.launchViaOpenLink) {
        // openLink：App Linking / DeepLink 官方入口，由系统按链接校验与分发
        await context.openLink(url);
        promptAction.showToast({ message: '已通过 openLink 发起跳转', duration: 1500 });
      } else {
        let want: Want = {
          action: 'ohos.want.action.viewData',
          uri: url
        };
        await context.startAbility(want);
        promptAction.showToast({ message: '已发起跳转', duration: 1500 });
      }
      this.saveHistory(url);
    } catch (err) {
      let error: BusinessError = err as BusinessError;
      let msg: string = error.message || '未知错误';
      if (this.launchViaOpenLink) {
        if (error.code === 16000019 || error.code === 16000001) {
          msg = '未找到可处理该链接的应用（无匹配 DeepLink / App Linking）';
        } else if (error.code === 16000136) {
          msg = '系统禁止通过 App Linking 拉起自身应用';
        }
      }
      promptAction.showToast({
        message: '跳转失败: ' + msg,
        duration: 2500
      });
    }
  }

  private startScan(): void {
    this.isScanning = true;
  }

  private handleScanResult(text: string): void {
    this.isScanning = false;
    this.inputUrl = text;
    this.parsedResult = URLParserUtil.parse(text);
    if (this.parsedResult.valid) {
      promptAction.showToast({ message: '扫码成功', duration: 1000 });
    } else {
      promptAction.showToast({ message: '未识别到有效链接', duration: 1500 });
    }
  }

  private copyText(value: string): void {
    try {
      let systemPasteboard = pasteboard.getSystemPasteboard();
      let pasteData = pasteboard.createData('text/plain', value);
      systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: '已复制', duration: 800 });
    } catch (err) {
      promptAction.showToast({ message: '复制失败', duration: 1000 });
    }
  }

  build() {
    if (this.isScanning) {
      ScanQrOverlay({
        title: '扫码识别 App Linking',
        onResult: (text: string) => {
          this.handleScanResult(text);
        },
        onCancel: () => {
          this.isScanning = false;
        }
      })
    } else {
      // 全局壁纸宿主：解析页继承主页壁纸背景（扫码页保持相机全屏不套用）
      WallpaperHost() {
        this.MainView();
      }
    }
  }

  @Builder
  MainView() {
    Column({ space: 0 }) {
      Column({ space: 12 }) {
        // ---------- 标题栏 ----------
        PageHeader({ title: 'App Linking 解析', subtitle: '深度拆解元服务 / App 链接并测试拉起' })
          .padding({ left: 16, right: 16, top: 8 })

        Column() {
          Row() {
            Text('输入链接')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
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
          .padding({ left: 4, right: 4, bottom: 8 })

          TextArea({ text: this.inputUrl, placeholder: '输入 App Linking / 元服务链接...' })
            .height(96)
            .width('100%')
            .fontSize(13)
            .fontFamily('monospace')
            .fontColor($r('sys.color.font_primary'))
            .placeholderFont({ size: 13 })
            .placeholderColor($r('sys.color.font_secondary'))
            .padding(12)
            // 沉浸光感输入框：半透明 + 背景高斯模糊透上来（不要用不透明的 comp_background_gray）
            .backgroundColor(ImmersiveStyles.inputBg())
            .backdropBlur(ImmersiveStyles.inputBlur())
            .borderRadius(ImmersiveStyles.inputRadius())
            .border({ width: 1, color: ImmersiveStyles.inputRim(this.isDark) })
            .onChange((value: string) => {
              this.inputUrl = value;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Row({ space: 12 }) {
          GlassButton({
            label: '扫码解析',
            btnHeight: 44,
            fillWidth: true,
            onAction: () => { this.startScan(); }
          })
            .layoutWeight(1)
            .visibility(this.isScanVisible ? Visibility.Visible : Visibility.None)

          GlassButton({
            label: '解析',
            btnHeight: 44,
            fillWidth: true,
            onAction: () => { this.doParse(); }
          })
            .layoutWeight(1)

          GlassButton({
            label: '测试拉起',
            btnHeight: 44,
            fillWidth: true,
            fontWeight: FontWeight.Medium,
            bgColor: $r('sys.color.comp_background_emphasize'),
            textColor: $r('sys.color.font_on_primary'),
            strokeWidth: 0,
            onAction: () => { this.launchDeepLink(); }
          })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .width('100%')

      // ---------- 拉起方式开关（openLink / startAbility） ----------
      Row() {
        Column({ space: 2 }) {
          Row() {
            Text('拉起方式')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
            Text(this.launchViaOpenLink ? 'openLink' : 'startAbility')
              .fontSize(11)
              .fontColor($r('sys.color.font_secondary'))
              .fontFamily('monospace')
              .margin({ left: 8 })
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .backgroundColor($r('sys.color.comp_background_gray'))
              .borderRadius(4)
          }

          Text(this.launchViaOpenLink
            ? 'App Linking/深链官方入口：按系统链接校验直达注册应用，无匹配时精准报错'
            : '传统 viewData 拉起：通用 URI 分发（自定义 scheme / 系统浏览器）')
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(2)
            .lineHeight(15)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ right: 12 })

        Toggle({ type: ToggleType.Switch, isOn: this.launchViaOpenLink })
          .onChange((isOn: boolean) => {
            this.launchViaOpenLink = isOn;
            try {
              PreferencesUtil.putSync(SpKeys.APP_LINK_LAUNCH_MODE, isOn);
            } catch (e) {
              console.error(`[${TAG}] save launch mode failed: ${JSON.stringify(e)}`);
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .color($r('sys.color.comp_background_emphasize'))
        .margin({ top: 12, left: 16, right: 16 })

      // 下部区域：解析结果 / 提示 + 历史记录，整体可滚动
      Scroll() {
        Column({ space: 12 }) {
          if (this.parsedResult.valid) {
            this.BasicInfoCard()
            this.QueryParamsCard()
            if (this.parsedResult.deepLink) {
              this.DeepLinkCard()
            }
          } else {
            Column() {
              if (this.inputUrl.trim().length > 0 && this.parsedResult.errorMessage.length > 0) {
                Text(this.parsedResult.errorMessage)
                  .fontSize(14)
                  .fontColor($r('sys.color.font_emphasize'))
                  .fontFamily('monospace')
              } else {
                Text('输入链接后点击「解析」查看拆解结果，或用「测试拉起」发起跳转')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
                  .opacity(0.5)
              }
            }
            .width('100%')
            .constraintSize({ minHeight: '200vp' })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }

          // ---------- 历史记录 ----------
          if (this.historyList.length > 0) {
            this.HistorySection()
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 24 })
      }
      .scrollBar(BarState.Auto)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    // 滚动到末尾时最后一张卡片会贴到屏幕底部，避让系统手势条
    .padding({ bottom: this.safeBottom })
  }

  @Builder
  HistorySection() {
    // 玻璃卡片：壁纸透出（原先是不透明的 background_secondary 纯色底）
    GlassCard() {
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
    }
  }

  @Builder
  BasicInfoCard() {
    // 玻璃卡片：壁纸透出（原先是不透明的 background_secondary 纯色底）
    GlassCard() {
    Column() {
      Row() {
        Circle({ width: 8, height: 8 })
          .fill($r('sys.color.comp_foreground_primary'))
        Text('基础信息')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_emphasize'))
          .margin({ left: 6 })
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
    }
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
    // 玻璃卡片：壁纸透出（原先是不透明的 background_secondary 纯色底）
    GlassCard() {
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

      if (this.parsedResult.queryParams.length === 0) {
        Text('-- 无查询参数 --')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .opacity(0.5)
          .fontFamily('monospace')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 6, bottom: 6 })
      } else {
        ForEach(this.parsedResult.queryParams, (param: ParsedQueryParam, index: number) => {
          this.QueryParamRow(param, index, this.parsedResult.queryParams.length)
        }, (param: ParsedQueryParam, index: number) => param.key + '_' + index.toString())
      }
    }
      .width('100%')
      .padding(14)
    }
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

  @Builder
  DeepLinkCard() {
    // 玻璃卡片：壁纸透出（原先是不透明的 background_secondary 纯色底）
    GlassCard() {
    Column() {
      Row() {
        Circle({ width: 8, height: 8 })
          .fill($r('sys.color.comp_foreground_primary'))
        Text('deepLink 深层解析')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_emphasize'))
          .margin({ left: 6 })
        Blank()
        if (this.parsedResult.deepLink && this.parsedResult.deepLink.valid) {
          Text('VALID')
            .fontSize(9)
            .fontColor($r('sys.color.font_on_primary'))
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .backgroundColor($r('sys.color.comp_foreground_primary'))
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        } else {
          Text('INVALID')
            .fontSize(9)
            .fontColor($r('sys.color.font_on_primary'))
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .backgroundColor($r('sys.color.font_secondary'))
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        }
      }
      .width('100%')
      .padding({ bottom: 10 })

      if (this.parsedResult.deepLink && this.parsedResult.deepLink.valid) {
        this.DeepLinkContent(this.parsedResult.deepLink)
      } else if (this.parsedResult.deepLink) {
        Column({ space: 6 }) {
          Text(this.parsedResult.deepLink.errorMessage || '解析失败')
            .fontSize(12)
            .fontColor($r('sys.color.font_emphasize'))
            .fontFamily('monospace')
            .width('100%')

          Text('  ' + this.parsedResult.deepLink.rawUrl)
            .fontSize(10)
            .fontColor($r('sys.color.font_secondary'))
            .fontFamily('monospace')
            .maxLines(4)
            .ellipsisMode(EllipsisMode.END)
            .width('100%')
            .opacity(0.8)
        }
        .width('100%')
      }
    }
      .width('100%')
      .padding(14)
    }
  }

  @Builder
  DeepLinkContent(dl: ParsedURLResult) {
    Column({ space: 0 }) {
      if (dl.scheme) {
        this.InfoRow('scheme', dl.scheme + '://')
      }
      if (dl.hostname) {
        this.InfoRow('host', dl.hostname)
      }
      if (dl.port) {
        this.InfoRow('port', dl.port)
      }
      if (dl.pathname) {
        this.InfoRow('path', dl.pathname)
      }

      if (dl.queryParams.length > 0) {
        Row() {
          Text('子参数')
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
            .fontWeight(FontWeight.Medium)
            .fontFamily('monospace')
            .margin({ top: 8, bottom: 8 })
        }
        .width('100%')

        ForEach(dl.queryParams,
          (param: ParsedQueryParam, subIdx: number) => {
          this.QueryParamRow(param, subIdx, dl.queryParams.length)
        }, (param: ParsedQueryParam, subIdx: number) => 'dl_' + param.key + '_' + subIdx.toString())
      }
    }
    .width('100%')
  }
}
