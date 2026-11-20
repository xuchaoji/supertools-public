import { router, mediaquery } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { JSON } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppUtil } from '@pura/harmony-utils';
import { PageNames } from '../constant/PageNames';
import { RouterDetailParams, RouterLaunchParams } from '../model/RouterDemoParams';
import { RouterPageUtil } from '../utils/RouterPageUtil';
import { WallpaperHost } from '../components/WallpaperHost';
import { PageHeader } from '../components/PageHeader';
import { GlassCard } from '../components/GlassCard';
import { GlassButton } from '../components/GlassButton';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';
import { SafeArea } from '../utils/SafeArea';
import { Toast } from '../utils/Toast';

const TAG: string = 'RouterDemoPage';

/**
 * 系统 router 演示页（第一页）。
 *
 * 定位：应用主体由 HMRouter（Navigation + NavDestination）管理，本页**刻意**
 * 使用系统 `@ohos.router` 的页面栈来管理，用来模拟"另一套 router 应用"的跳转：
 *
 *   pages/Index（HMRouter 容器）
 *        └─ HomePage 工具箱「Router 页面跳转」入口
 *              └─ router.pushUrl ──> pages/RouterDemoPage（本页，router 管理）
 *                    ├─ router.pushUrl ──> pages/RouterDemoDetailPage（详情页）
 *                    │     └─ router.back({ url, params }) 回传结果
 *                    └─ router.pushUrl ──> pages/RouterSplashPage（模拟开屏，5 秒）
 *                          └─ router.replaceUrl ──> pages/RouterMainPage（模拟主页）
 *
 * router 页面与 HMRouter 页面是两套独立的页面栈：
 * - router 入栈/出栈只会让下方的 HMRouter 根页面走 onPageHide/onPageShow，
 *   不会破坏 HMNavigation 内部的 NavPathStack；
 * - 因此返回工具箱时 HomePage 的状态会原样保留。
 *
 * 注意：router 是页面级路由，本页必须在 main_pages.json 中注册路径，
 * 并且页面生命周期（onPageShow/onPageHide）只在 @Entry 页面组件上生效。
 *
 * 兼容性：`@ohos.router` 从 API 18 起标记为 deprecated（本应用 targetSdk 17 仍可用），
 * 其能力等价于 `this.getUIContext().getRouter()`；新项目推荐直接使用 Navigation。
 */
@Entry
@ComponentV2
struct RouterDemoPage {
  @Local isDark: boolean = false;
  @Local safeBottom: string = '0px';
  /** 首次进入时的入口参数（缓存，避免返回后 router.getParams 被回传参数覆盖） */
  @Local entryParams: string = '(无参数)';
  /** 当前页 router.getParams() 的实时内容（每次 onPageShow 刷新） */
  @Local currentParams: string = '(无参数)';
  /** 当前页面路径 */
  @Local currentPath: string = '';
  /** 当前页在 router 页面栈中的索引（从 1 开始） */
  @Local stackIndex: number = 0;
  /** router 页面栈深度 */
  @Local stackLength: number = 0;
  /** 页面栈快照：'1. pages/Index' 逐行拼接 */
  @Local stackChain: string = '';
  /** onPageShow 次数，用来观察 router 页面生命周期 */
  @Local showCount: number = 0;
  @Local lastShowTime: string = '--:--:--';
  private themeMq: mediaquery.MediaQueryListener | null = null;
  /** 开屏页跳转中：防止快速连点把 RouterSplashPage 压入多次 */
  private splashPushInProgress: boolean = false;

  aboutToAppear(): void {
    this.safeBottom = SafeArea.bottom();
    this.initTheme();
    this.entryParams = RouterPageUtil.paramsJson();
    this.currentParams = this.entryParams;
    this.refreshStack();
  }

  onPageShow(): void {
    this.showCount += 1;
    this.lastShowTime = this.nowText();
    // 从详情页 router.back({ params }) 返回时，
    // 回传参数会在目标页 onPageShow 阶段生效
    this.currentParams = RouterPageUtil.paramsJson();
    this.refreshStack();
    hilog.info(0x0000, TAG, 'onPageShow #%{public}d path=%{public}s', this.showCount, this.currentPath);
  }

  onPageHide(): void {
    hilog.info(0x0000, TAG, 'onPageHide');
  }

  private initTheme(): void {
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

  aboutToDisappear(): void {
    this.themeMq?.off('change');
    this.themeMq = null;
  }

  private nowText(): string {
    const d = new Date();
    return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}:` +
      `${d.getSeconds().toString().padStart(2, '0')}`;
  }

  /** 读取 router 页面栈（索引从 1 开始，1 = 栈底 pages/Index） */
  private refreshStack(): void {
    const info = RouterPageUtil.stackInfo();
    this.currentPath = info.path;
    this.stackIndex = info.index;
    this.stackLength = info.length;
    this.stackChain = info.chain;
  }

  /** 入栈详情页：router.pushUrl 携带参数 */
  private openDetail(): void {
    const params: RouterDetailParams = new RouterDetailParams();
    params.orderId = `ORDER-${Date.now()}`;
    params.from = PageNames.ROUTER_DEMO_PAGE;
    params.ts = Date.now();
    router.pushUrl({ url: PageNames.ROUTER_DEMO_DETAIL_PAGE, params: params })
      .then(() => {
        hilog.info(0x0000, TAG, 'pushUrl -> %{public}s ok', PageNames.ROUTER_DEMO_DETAIL_PAGE);
      })
      .catch((err: BusinessError) => {
        hilog.error(0x0000, TAG, 'pushUrl failed: %{public}s', JSON.stringify(err));
        Toast.show(`router.pushUrl 失败：${err.code}`);
      });
  }

  /** 出栈：返回 HMRouter 管理的工具箱 */
  private backToHome(): void {
    router.back();
  }

  /**
   * 模拟应用启动流程：push 开屏页。
   *
   * RouterSplashPage 停留 5 秒（广告时长占位）后会 replaceUrl 到 RouterMainPage，
   * 因此本页只需负责把开屏页压栈，跳主页的逻辑由开屏页自己完成。
   */
  private openSplash(): void {
    if (this.splashPushInProgress) {
      return;
    }
    this.splashPushInProgress = true;
    setTimeout(() => {
      this.splashPushInProgress = false;
    }, 500);
    const params: RouterLaunchParams = new RouterLaunchParams();
    params.from = PageNames.ROUTER_DEMO_PAGE;
    params.ts = Date.now();
    params.waitedSeconds = 0;
    router.pushUrl({ url: PageNames.ROUTER_SPLASH_PAGE, params: params })
      .then(() => {
        hilog.info(0x0000, TAG, 'pushUrl -> %{public}s ok', PageNames.ROUTER_SPLASH_PAGE);
      })
      .catch((err: BusinessError) => {
        hilog.error(0x0000, TAG, 'open splash failed: %{public}s', JSON.stringify(err));
        Toast.show(`打开开屏页失败：${err.code}`);
      });
  }

  build() {
    Stack() {
      WallpaperHost() {
        Column() {
          Scroll() {
            Column({ space: 12 }) {
              PageHeader({
                title: 'Router 页面跳转',
                subtitle: '系统 router 页面栈演示（非 HMRouter）',
                onBack: () => {
                  this.backToHome();
                }
              })

              // ---------- 页面栈信息 ----------
              GlassCard() {
                Column({ space: 8 }) {
                  Row() {
                    Text('router 页面栈')
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('sys.color.font_primary'))
                      .textShadow(ImmersiveStyles.textShadow(this.isDark))
                    Blank()
                    Text(`索引 ${this.stackIndex} / 深度 ${this.stackLength}`)
                      .fontSize(11)
                      .fontColor($r('sys.color.font_secondary'))
                      .textShadow(ImmersiveStyles.textShadow(this.isDark))
                  }
                  .width('100%')

                  this.infoRow('当前页面', this.currentPath)
                  this.infoRow('onPageShow', `第 ${this.showCount} 次 · ${this.lastShowTime}`)

                  Text('页面栈（底 → 顶）：')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text(this.stackChain)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_primary'))
                    .width('100%')
                    .lineHeight(18)
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))
                }
                .width('100%')
                .padding(14)
              }

              // ---------- 参数 ----------
              GlassCard() {
                Column({ space: 8 }) {
                  Text('页面参数（router.getParams）')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('sys.color.font_primary'))
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text('首次进入的入口入参')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text(this.entryParams)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_primary'))
                    .width('100%')
                    .lineHeight(18)
                    .wordBreak(WordBreak.BREAK_ALL)
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text('当前参数（每次 onPageShow 刷新，详情页回传后会变化）')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')
                    .margin({ top: 4 })
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text(this.currentParams)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_primary'))
                    .width('100%')
                    .lineHeight(18)
                    .wordBreak(WordBreak.BREAK_ALL)
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))
                }
                .width('100%')
                .padding(14)
              }

              // ---------- 模拟应用启动流程 ----------
              Column({ space: 8 }) {
                Text('模拟应用启动流程')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('sys.color.font_secondary'))
                  .width('100%')
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))

                GlassButton({
                  label: '模拟应用打开',
                  fillWidth: true,
                  bgColor: $r('sys.color.comp_background_emphasize'),
                  textColor: $r('sys.color.font_on_primary'),
                  strokeWidth: 0,
                  fontWeight: FontWeight.Medium,
                  onAction: () => {
                    this.openSplash();
                  }
                })

                Text('RouterSplashPage 停留 5 秒（后续接入开屏广告）→ RouterMainPage')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_secondary'))
                  .width('100%')
                  .lineHeight(16)
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))
              }
              .width('100%')

              // ---------- 页面跳转 ----------
              Column({ space: 8 }) {
                Text('页面跳转')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('sys.color.font_secondary'))
                  .width('100%')
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))

                GlassButton({
                  label: 'pushUrl 打开详情页（携带参数）',
                  fillWidth: true,
                  onAction: () => {
                    this.openDetail();
                  }
                })

                GlassButton({
                  label: 'router.back 返回工具箱',
                  fillWidth: true,
                  onAction: () => {
                    this.backToHome();
                  }
                })
              }
              .width('100%')

              // ---------- 说明 ----------
              GlassCard() {
                Column({ space: 6 }) {
                  Text('这个页面是怎么跳过来的')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('sys.color.font_primary'))
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  this.tipRow('入口', '工具箱卡片 → router.pushUrl({ url: pages/RouterDemoPage, params })')
                  this.tipRow('入栈', 'router.pushUrl 把页面压入 router 页面栈，并携带可序列化参数')
                  this.tipRow('取参', '目标页 aboutToAppear / onPageShow 中调用 router.getParams()')
                  this.tipRow('出栈', 'router.back() 返回上一页；router.back({ url, params }) 可回传结果')
                  this.tipRow('启动', '模拟应用打开 → 开屏页 5 秒后 replaceUrl 主页（栈内不留开屏页）')
                  this.tipRow('注册', 'router 页面必须写进 main_pages.json，HMRouter 页面则不需要')
                }
                .width('100%')
                .padding(14)
              }

              // 底部留白（与卡片间距一致）
              Row()
                .height(8)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            // [Pad 大屏适配] 限制最大宽度
            .constraintSize({ maxWidth: 800 })
            .padding({ left: 16, right: 16, top: 8, bottom: 24 })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          // 内容不足一屏时 Scroll 默认垂直居中，改为顶部对齐
          .align(Alignment.Top)
          // 滚动到末尾时最后一张卡片会贴到屏幕底部，避让系统手势条
          .padding({ bottom: this.safeBottom })
        }
        .width('100%')
        .height('100%')
        // router 页面不在 Index 的 HMNavigation 容器里，没有 Index 的统一状态栏避让，
        // 这里必须自己加顶部状态栏 padding，否则标题会压到状态栏下面
        .padding({ top: `${AppUtil.getStatusBarHeight()}px` })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  infoRow(label: string, value: string) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .textShadow(ImmersiveStyles.textShadow(this.isDark))
      Blank()
      Text(value)
        .fontSize(12)
        .fontColor($r('sys.color.font_primary'))
        .textAlign(TextAlign.End)
        .textShadow(ImmersiveStyles.textShadow(this.isDark))
    }
    .width('100%')
  }

  @Builder
  tipRow(label: string, value: string) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .width(32)
        .textShadow(ImmersiveStyles.textShadow(this.isDark))
      Text(value)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .layoutWeight(1)
        .lineHeight(16)
        .textShadow(ImmersiveStyles.textShadow(this.isDark))
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
