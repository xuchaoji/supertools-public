import { router, mediaquery } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppUtil } from '@pura/harmony-utils';
import { PageNames } from '../constant/PageNames';
import { RouterDetailResult } from '../model/RouterDemoParams';
import { RouterPageUtil } from '../utils/RouterPageUtil';
import { WallpaperHost } from '../components/WallpaperHost';
import { PageHeader } from '../components/PageHeader';
import { GlassCard } from '../components/GlassCard';
import { GlassButton } from '../components/GlassButton';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';
import { SafeArea } from '../utils/SafeArea';

const TAG: string = 'RouterDemoDetailPage';

/**
 * 系统 router 演示页（第二页）。
 *
 * 由 RouterDemoPage 通过 `router.pushUrl` 压栈进入，演示两件事：
 * 1. `router.getParams()` 读取上一页 push 过来的参数；
 * 2. `router.back({ url, params })` 出栈时把结果回传给目标页
 *    （目标页在 `onPageShow` 中重新 getParams 即可拿到）。
 *
 * 同时展示 router 的多种出栈方式：默认弹一层、指定 url 回传、`back(1)` 直接回栈底。
 */
@Entry
@ComponentV2
struct RouterDemoDetailPage {
  @Local isDark: boolean = false;
  @Local safeBottom: string = '0px';
  /** pushUrl 入参（aboutToAppear 时读取） */
  @Local paramsText: string = '(无参数)';
  @Local currentPath: string = '';
  @Local stackIndex: number = 0;
  @Local stackLength: number = 0;
  @Local stackChain: string = '';
  @Local showCount: number = 0;
  private themeMq: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    this.safeBottom = SafeArea.bottom();
    this.initTheme();
    this.paramsText = RouterPageUtil.paramsJson();
    this.refreshStack();
  }

  onPageShow(): void {
    this.showCount += 1;
    this.refreshStack();
    hilog.info(0x0000, TAG, 'onPageShow #%{public}d path=%{public}s', this.showCount, this.currentPath);
  }

  onPageHide(): void {
    hilog.info(0x0000, TAG, 'onPageHide');
  }

  private initTheme(): void {
    try {
      this.themeMq = this.getUIContext().getMediaQuery().matchMediaSync('(dark-mode: true)');
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

  private refreshStack(): void {
    const info = RouterPageUtil.stackInfo();
    this.currentPath = info.path;
    this.stackIndex = info.index;
    this.stackLength = info.length;
    this.stackChain = info.chain;
  }

  /** 出栈并把处理结果回传给演示页：目标页 onPageShow 中可重新 getParams 拿到 */
  private backWithResult(): void {
    const result: RouterDetailResult = new RouterDetailResult();
    result.result = 'ok';
    result.message = '详情页处理完成，这条结果由 router.back({ params }) 回传';
    result.ts = Date.now();
    router.back({ url: PageNames.ROUTER_DEMO_PAGE, params: result });
  }

  /** 默认出栈：回到上一页（演示页） */
  private backToPrev(): void {
    router.back();
  }

  /** 指定索引出栈：1 = 栈底 pages/Index（HMRouter 根页面） */
  private backToRoot(): void {
    router.back(1);
  }

  build() {
    Stack() {
      WallpaperHost() {
        Column() {
          Scroll() {
            Column({ space: 12 }) {
              PageHeader({
                title: 'Router 详情页',
                subtitle: 'pushUrl 入参 · back 回传结果',
                onBack: () => {
                  this.backToPrev();
                }
              })

              // ---------- 入参 ----------
              GlassCard() {
                Column({ space: 8 }) {
                  Text('pushUrl 传入的参数')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('sys.color.font_primary'))
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text(this.paramsText)
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

              // ---------- 页面栈 ----------
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

                  Text('当前页面：')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text(this.currentPath)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_primary'))
                    .width('100%')
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text('页面栈（底 → 顶）：')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')
                    .margin({ top: 4 })
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

              // ---------- 出栈方式 ----------
              Column({ space: 10 }) {
                GlassButton({
                  label: '带结果返回演示页（router.back）',
                  fillWidth: true,
                  bgColor: $r('sys.color.comp_background_emphasize'),
                  textColor: $r('sys.color.font_on_primary'),
                  strokeWidth: 0,
                  fontWeight: FontWeight.Medium,
                  onAction: () => {
                    this.backWithResult();
                  }
                })

                GlassButton({
                  label: 'back 返回上一页（不带结果）',
                  fillWidth: true,
                  onAction: () => {
                    this.backToPrev();
                  }
                })

                GlassButton({
                  label: '直接回栈底（router.back(1)）',
                  fillWidth: true,
                  onAction: () => {
                    this.backToRoot();
                  }
                })
              }
              .width('100%')

              // ---------- 说明 ----------
              GlassCard() {
                Column({ space: 6 }) {
                  Text('router 出栈的三种写法')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('sys.color.font_primary'))
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text('router.back()：弹出栈顶，回到上一页（演示页）')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')
                    .lineHeight(16)
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text('router.back({ url, params })：回到指定页面并回传结果，目标页在 onPageShow 里 getParams 接收')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')
                    .lineHeight(16)
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text('router.back(1)：直接弹到索引 1 的栈底页面（pages/Index），跳过中间页面')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')
                    .lineHeight(16)
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))
                }
                .width('100%')
                .padding(14)
              }

              Row()
                .height(8)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .constraintSize({ maxWidth: 800 })
            .padding({ left: 16, right: 16, top: 8, bottom: 24 })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .padding({ bottom: this.safeBottom })
        }
        .width('100%')
        .height('100%')
        // router 页面独立于 Index 的 HMNavigation，需要自己避让状态栏
        .padding({ top: `${AppUtil.getStatusBarHeight()}px` })
      }
    }
    .width('100%')
    .height('100%')
  }
}
