import { router, mediaquery } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppUtil } from '@pura/harmony-utils';
import { PageNames } from '../constant/PageNames';
import { RouterPageUtil } from '../utils/RouterPageUtil';
import { WallpaperHost } from '../components/WallpaperHost';
import { PageHeader } from '../components/PageHeader';
import { GlassCard } from '../components/GlassCard';
import { GlassButton } from '../components/GlassButton';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';
import { SafeArea } from '../utils/SafeArea';
import { Toast } from '../utils/Toast';

const TAG: string = 'RouterMainPage';

/**
 * 模拟应用启动流程：启动完成后的「应用主页」。
 *
 * 由 RouterSplashPage 在 5 秒（广告占位时长）后通过 `router.replaceUrl` 进入。
 * 使用 replaceUrl 的意义：主页会替换掉栈内的开屏页，所以在这个页面返回时
 * 直接回到 RouterDemoPage，而不会倒退回开屏页。
 *
 * 页面内的「页面栈」卡片可以直观看到：
 *   pages/Index / pages/RouterDemoPage / pages/RouterMainPage
 * 其中已经不存在 pages/RouterSplashPage —— 这就是 replaceUrl 与 pushUrl 的差别。
 */
@Entry
@ComponentV2
struct RouterMainPage {
  @Local isDark: boolean = false;
  @Local safeBottom: string = '0px';
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
    this.paramsText = RouterPageUtil.paramsJson();
    this.refreshStack();
    hilog.info(0x0000, TAG, 'onPageShow #%{public}d path=%{public}s', this.showCount, this.currentPath);
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

  private refreshStack(): void {
    const info = RouterPageUtil.stackInfo();
    this.currentPath = info.path;
    this.stackIndex = info.index;
    this.stackLength = info.length;
    this.stackChain = info.chain;
  }

  /** 返回 Router 演示页：因为开屏页已被替换，这里 back 直接回到演示页 */
  private backToDemo(): void {
    router.back();
  }

  /** 重新演示启动流程：用开屏页替换当前主页，再由开屏页 replaceUrl 回来 */
  private restartSplash(): void {
    router.replaceUrl({ url: PageNames.ROUTER_SPLASH_PAGE })
      .catch((err: BusinessError) => {
        hilog.error(0x0000, TAG, 'replaceUrl splash failed: %{public}s', JSON.stringify(err));
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
                title: '模拟应用主页',
                subtitle: 'Splash 停留 5 秒后自动进入本页',
                onBack: () => {
                  this.backToDemo();
                }
              })

              // ---------- 启动完成提示 ----------
              GlassCard() {
                Column({ space: 10 }) {
                  Row({ space: 8 }) {
                    Text('Splash')
                      .fontSize(12)
                      .fontColor($r('sys.color.font_secondary'))
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .borderRadius(10)
                      .backgroundColor(ImmersiveStyles.cardBase(this.isDark))
                      .border({ width: 1, color: ImmersiveStyles.cardOuterRim(this.isDark) })

                    Text('→')
                      .fontSize(12)
                      .fontColor($r('sys.color.font_secondary'))

                    Text('模拟主页')
                      .fontSize(12)
                      .fontColor($r('sys.color.font_primary'))
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .borderRadius(10)
                      .backgroundColor(ImmersiveStyles.cardBase(this.isDark))
                      .border({ width: 1, color: ImmersiveStyles.cardOuterRim(this.isDark) })
                  }
                  .width('100%')

                  Text('应用已启动')
                    .fontSize(20)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('sys.color.font_emphasize'))
                    .width('100%')
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text('RouterSplashPage 在 5 秒后调用 router.replaceUrl 进入本页；开屏页已被替换，返回时会直接回到 Router 演示页。')
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .lineHeight(18)
                    .width('100%')
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))
                }
                .width('100%')
                .padding(14)
              }

              // ---------- 启动页入参 ----------
              GlassCard() {
                Column({ space: 8 }) {
                  Text('启动页传入的参数')
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

                  Text(`当前页面：${this.currentPath}`)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_primary'))
                    .width('100%')
                    .wordBreak(WordBreak.BREAK_ALL)
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

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

                  Text('注意：栈内没有 pages/RouterSplashPage，它是被本页 replaceUrl 替换掉的。')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .lineHeight(16)
                    .width('100%')
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))
                }
                .width('100%')
                .padding(14)
              }

              // ---------- 操作 ----------
              Column({ space: 10 }) {
                GlassButton({
                  label: '返回 Router 演示页',
                  fillWidth: true,
                  bgColor: $r('sys.color.comp_background_emphasize'),
                  textColor: $r('sys.color.font_on_primary'),
                  strokeWidth: 0,
                  fontWeight: FontWeight.Medium,
                  onAction: () => {
                    this.backToDemo();
                  }
                })

                GlassButton({
                  label: '重新演示启动流程',
                  fillWidth: true,
                  onAction: () => {
                    this.restartSplash();
                  }
                })
              }
              .width('100%')

              // ---------- 说明 ----------
              GlassCard() {
                Column({ space: 6 }) {
                  Text('为什么返回时看不到开屏页')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('sys.color.font_primary'))
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text('router.pushUrl 会保留当前页（开屏页），router.replaceUrl 则会用新页面替换当前页。')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .lineHeight(16)
                    .width('100%')
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text('启动流程使用 replaceUrl 进入主页，因此页面栈里只剩“演示页 → 主页”，返回不会重新经历开屏。')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .lineHeight(16)
                    .width('100%')
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
