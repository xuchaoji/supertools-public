import { router, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppUtil } from '@pura/harmony-utils';
import { PageNames } from '../constant/PageNames';
import { RouterLaunchParams } from '../model/RouterDemoParams';
import { SafeArea } from '../utils/SafeArea';
import { Toast } from '../utils/Toast';

const TAG: string = 'RouterSplashPage';
/** 开屏展示时长（秒）：当前是广告时长的占位，后续接入 AdsKit 开屏广告后以广告回调为准 */
const SPLASH_SECONDS: number = 5;

/**
 * 模拟应用启动流程：开屏页。
 *
 * 流程：
 *   RouterDemoPage（「模拟应用打开」入口）
 *     └─ router.pushUrl ──> RouterSplashPage（本页，停留 5 秒）
 *           └─ router.replaceUrl ──> RouterMainPage（模拟应用主页）
 *
 * 关键点：
 * - 用 `replaceUrl` 而不是 `pushUrl` 进主页：开屏页被主页**替换**，
 *   栈内不会留下 Splash，主页返回时直接回到 RouterDemoPage（不会又看到开屏页）；
 * - 后续接入广告：在 `aboutToAppear/onPageShow` 中加载开屏广告，
 *   广告加载/播放结束后调用 `goMain()`；当前用 5 秒倒计时占位。
 */
@Entry
@ComponentV2
struct RouterSplashPage {
  @Local remainSeconds: number = SPLASH_SECONDS;
  @Local safeTop: string = '0px';
  @Local safeBottom: string = '0px';
  private timerId: number = -1;
  /** 防止倒计时归零与「跳过」同时触发两次 replaceUrl */
  private jumped: boolean = false;
  private win: window.Window | undefined = undefined;
  /** 开屏前状态栏文字颜色：离开开屏页时恢复，避免影响主页 */
  private originalStatusBarContentColor: string = '';
  private pageGone: boolean = false;

  aboutToAppear(): void {
    this.safeTop = `${AppUtil.getStatusBarHeight()}px`;
    this.safeBottom = SafeArea.bottom();
    this.applyLightStatusBar();
  }

  /** 深色开屏背景下把状态栏文字/图标切成白色，离开时恢复原值 */
  private applyLightStatusBar(): void {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (!ctx) {
        return;
      }
      window.getLastWindow(ctx).then((win: window.Window) => {
        if (this.pageGone) {
          return;
        }
        this.win = win;
        try {
          this.originalStatusBarContentColor = win.getWindowSystemBarProperties().statusBarContentColor ?? '';
          win.setWindowSystemBarProperties({ statusBarContentColor: '#FFFFFF' }).catch(() => {
          });
        } catch (e) {
          console.warn(`[${TAG}] set light status bar failed: ${JSON.stringify(e)}`);
        }
      }).catch((e: Object) => {
        console.warn(`[${TAG}] getLastWindow failed: ${JSON.stringify(e)}`);
      });
    } catch (e) {
      console.warn(`[${TAG}] applyLightStatusBar failed: ${JSON.stringify(e)}`);
    }
  }

  private restoreStatusBar(): void {
    if (!this.win || this.originalStatusBarContentColor === '') {
      return;
    }
    try {
      this.win.setWindowSystemBarProperties({ statusBarContentColor: this.originalStatusBarContentColor }).catch(() => {
      });
    } catch (e) {
      console.warn(`[${TAG}] restore status bar failed: ${JSON.stringify(e)}`);
    }
  }

  onPageShow(): void {
    // 从后台回到前台时继续走完倒计时（timer 已在 onPageHide 中停掉）
    this.startCountdown();
  }

  onPageHide(): void {
    this.stopCountdown();
  }

  aboutToDisappear(): void {
    this.pageGone = true;
    this.stopCountdown();
    this.restoreStatusBar();
  }

  private startCountdown(): void {
    // TODO(广告)：后续接入 AdsKit 开屏广告后，跳转时机应改由广告曝光/播放结束回调驱动，
    // 当前固定 5 秒仅用于模拟开屏广告的展示时长。
    if (this.jumped || this.timerId >= 0) {
      return;
    }
    this.timerId = setInterval(() => {
      if (this.remainSeconds <= 1) {
        this.remainSeconds = 0;
        this.goMain();
      } else {
        this.remainSeconds -= 1;
      }
    }, 1000);
  }

  private stopCountdown(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  /** 开屏结束：用主页替换当前开屏页（栈内不保留 Splash） */
  private goMain(): void {
    if (this.jumped) {
      return;
    }
    this.jumped = true;
    this.stopCountdown();
    const params: RouterLaunchParams = new RouterLaunchParams();
    params.from = PageNames.ROUTER_SPLASH_PAGE;
    params.ts = Date.now();
    params.waitedSeconds = SPLASH_SECONDS - this.remainSeconds;
    router.replaceUrl({ url: PageNames.ROUTER_MAIN_PAGE, params: params })
      .then(() => {
        console.info(`[${TAG}] replaceUrl -> ${PageNames.ROUTER_MAIN_PAGE}, waited=${params.waitedSeconds}s`);
      })
      .catch((err: BusinessError) => {
        console.error(`[${TAG}] replaceUrl failed: ${JSON.stringify(err)}`);
        Toast.show(`进入模拟主页失败：${err.code}`);
      });
  }

  /** 深色开屏背景：左上品牌紫 -> 右下深紫，避免系统浅色模式下页面发白 */
  private splashColors(): Array<[ResourceColor, number]> {
    return [
      ['#1B1B2F', 0.0],
      ['#2D2A55', 0.55],
      ['#4B3F72', 1.0]
    ];
  }

  build() {
    Stack() {
      Column() {
        // 顶部跳过按钮：等不到 5 秒时可直接进入主页
        Row() {
          Blank()
          Text('跳过')
            .fontSize(13)
            .fontColor('rgba(255, 255, 255, 0.86)')
            .padding({ left: 16, right: 16, top: 7, bottom: 7 })
            .borderRadius(16)
            .backgroundColor('rgba(255, 255, 255, 0.12)')
            .border({ width: 1, color: 'rgba(255, 255, 255, 0.22)' })
            .onClick(() => {
              this.goMain();
            })
        }
        .width('100%')
        .padding({ top: this.safeTop, left: 20, right: 20 })

        Column({ space: 16 }) {
          // 应用图标（复用启动窗口图标，模拟真实 App 的开屏品牌位）
          Image($r('app.media.chaoji_bust_style'))
            .width(96)
            .height(96)
            .borderRadius(24)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 24, color: 'rgba(0, 0, 0, 0.35)', offsetX: 0, offsetY: 10 })

          Column({ space: 6 }) {
            Text($r('app.string.app_name'))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text('模拟应用启动中…')
              .fontSize(13)
              .fontColor('rgba(255, 255, 255, 0.62)')
          }
          .alignItems(HorizontalAlign.Center)

          // ---------- 开屏广告位（后续接入 AdsKit） ----------
          // 广告接入点：把下面占位替换为广告组件/图片，并在广告展示完成后调用 goMain()。
          Column({ space: 6 }) {
            Text('开屏广告位')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('rgba(255, 255, 255, 0.82)')
            Text('后续接入 AdsKit 开屏广告，当前以 5 秒倒计时占位')
              .fontSize(11)
              .fontColor('rgba(255, 255, 255, 0.48)')
              .textAlign(TextAlign.Center)
              .padding({ left: 12, right: 12 })
          }
          .width('86%')
          .height(104)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(255, 255, 255, 0.06)')
          .borderRadius(14)
          .border({ width: 1, color: 'rgba(255, 255, 255, 0.22)', style: BorderStyle.Dashed })
          .margin({ top: 6 })

          // 倒计时进度 + 文案
          Progress({
            value: SPLASH_SECONDS - this.remainSeconds,
            total: SPLASH_SECONDS,
            type: ProgressType.Linear
          })
            .width('62%')
            .height(4)
            .color('#FF4500')
            .backgroundColor('rgba(255, 255, 255, 0.18)')
            .margin({ top: 4 })

          Text(`${this.remainSeconds} 秒后进入应用主页`)
            .fontSize(12)
            .fontColor('rgba(255, 255, 255, 0.7)')
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 24, right: 24 })

        Text('RouterSplashPage · 5 秒后 router.replaceUrl → RouterMainPage')
          .fontSize(10)
          .fontColor('rgba(255, 255, 255, 0.4)')
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 14 })
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.safeBottom })
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 160,
      colors: this.splashColors()
    })
    // 关掉点击穿透：开屏页整屏覆盖，避免点到下层 HMRouter 页面
    .hitTestBehavior(HitTestMode.Block)
  }
}
