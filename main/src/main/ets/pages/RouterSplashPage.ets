import { router, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppUtil } from '@pura/harmony-utils';
import advertising, { AdComponent } from '@hw-ads/ads';
import { AdType } from '../constant/AdType';
import { PageNames } from '../constant/PageNames';
import { RouterLaunchParams } from '../model/RouterDemoParams';
import { SafeArea } from '../utils/SafeArea';
import { Toast } from '../utils/Toast';

const TAG: string = 'RouterSplashPage';
/**
 * 开屏广告位（按顺序尝试）：
 * 1. u7w58nlimb：主开屏广告位；
 * 2. f068vmywiu：主广告位无填充/加载失败时的备用广告位。
 * 两个都拿不到广告时退回默认开屏，避免模拟启动流程卡死。
 */
const SPLASH_AD_IDS: string[] = ['u7w58nlimb', 'f068vmywiu'];
/** 单个广告位的请求超时：超时后尝试下一个广告位 */
const AD_LOAD_TIMEOUT_MS: number = 4000;
/** 广告渲染保护：AdComponent 挂载后迟迟没有 onAdOpen/onAdClose 时兜底进主页 */
const AD_RENDER_GUARD_MS: number = 15000;
/** 拿不到广告时的默认开屏时长（秒），仅用于兜底，不是广告时长 */
const SPLASH_SECONDS: number = 5;

const PHASE_LOADING: string = 'loading';
const PHASE_AD: string = 'ad';
const PHASE_FALLBACK: string = 'fallback';

/**
 * 模拟应用启动流程：开屏页（真实开屏广告）。
 *
 * 流程：
 *   RouterDemoPage（「模拟应用打开」入口）
 *     └─ router.pushUrl ──> RouterSplashPage（本页，请求并展示 @hw-ads/ads 开屏广告）
 *           └─ onAdClose 回调 ──> router.replaceUrl ──> RouterMainPage（模拟应用主页）
 *
 * 关键点：
 * - 开屏广告用 `AdComponent` 渲染（与官方 Ads Kit 示例一致，这里只是把
 *   `@kit.AdsKit` 的导包换成项目集成的 `@hw-ads/ads`）：
 *   全屏广告铺满整页，半屏广告占页面上方，媒体品牌位放在下方；
 * - 跳转时机由广告 `onStatusChanged` 的 `onAdClose` 驱动，不再用固定倒计时；
 * - 广告位：按顺序尝试 `u7w58nlimb`、`f068vmywiu`，两个都没有广告时退回默认开屏；
 * - 兜底：广告请求失败/超时/展示失败时回到原来的 5 秒默认开屏，保证演示流程
 *   在没有广告填充（模拟器、无网）时也能走完；
 * - 用 `replaceUrl` 而不是 `pushUrl` 进主页：开屏页被主页**替换**，
 *   栈内不会留下 Splash，主页返回时直接回到 RouterDemoPage。
 */
@Entry
@ComponentV2
struct RouterSplashPage {
  @Local remainSeconds: number = SPLASH_SECONDS;
  @Local safeTop: string = '0px';
  @Local safeBottom: string = '0px';
  /** 当前阶段：loading（请求广告）/ ad（广告展示）/ fallback（默认开屏兜底） */
  @Local phase: string = PHASE_LOADING;
  /** 请求到的开屏广告；AdComponent 只展示数组第一个 */
  @Local splashAds: advertising.Advertisement[] = [];
  /** 广告是否为全屏（来自广告响应的 isFullScreen，缺失时按全屏处理） */
  @Local adFullScreen: boolean = true;
  /** 兜底默认开屏时展示的原因，便于在页面上看出广告为什么没展示 */
  @Local fallbackReason: string = '';

  private timerId: number = -1;
  private loadGuardId: number = -1;
  private renderGuardId: number = -1;
  /** 当前正在请求的广告位下标（SPLASH_AD_IDS） */
  private slotIndex: number = -1;
  /** 每个广告位的失败原因，全部失败时合并展示 */
  private slotFailures: string[] = [];
  /** 实际拿到广告的广告位 ID，随启动参数带到主页便于核对 */
  private loadedAdId: string = '';
  /** 防止倒计时归零、跳过按钮、广告关闭回调同时触发多次 replaceUrl */
  private jumped: boolean = false;
  private pageGone: boolean = false;
  private adRequested: boolean = false;
  /** 进入开屏页的时间戳，用于统计实际停留时长 */
  private startTs: number = 0;

  private win: window.Window | undefined = undefined;
  /** 开屏前状态栏文字颜色：离开开屏页时恢复，避免影响主页 */
  private originalStatusBarContentColor: string = '';
  private adDisplayOptions: advertising.AdDisplayOptions = { mute: true };

  aboutToAppear(): void {
    this.startTs = Date.now();
    this.safeTop = `${AppUtil.getStatusBarHeight()}px`;
    this.safeBottom = SafeArea.bottom();
    this.applyLightStatusBar();
    this.loadSplashAd();
  }

  onPageShow(): void {
    // 从后台回到前台时继续走完兜底倒计时（timer 已在 onPageHide 中停掉）
    if (this.phase === PHASE_FALLBACK) {
      this.startFallbackCountdown();
    }
  }

  onPageHide(): void {
    this.stopFallbackCountdown();
  }

  aboutToDisappear(): void {
    this.pageGone = true;
    this.stopFallbackCountdown();
    this.clearLoadGuard();
    this.clearRenderGuard();
    this.restoreStatusBar();
  }

  // ===================== 开屏广告 =====================

  /** 请求开屏广告：按 SPLASH_AD_IDS 顺序尝试，只有第一次进入页面会发起请求 */
  private loadSplashAd(): void {
    if (this.adRequested || this.pageGone) {
      return;
    }
    this.adRequested = true;
    this.tryLoadSlot(0);
  }

  /** 请求第 index 个开屏广告位；失败/超时自动尝试下一个 */
  private tryLoadSlot(index: number): void {
    if (this.pageGone || this.jumped || this.phase !== PHASE_LOADING) {
      return;
    }
    if (index >= SPLASH_AD_IDS.length) {
      this.fallback('开屏广告位均无填充');
      return;
    }
    const adId: string = SPLASH_AD_IDS[index];
    this.slotIndex = index;
    console.info(`[${TAG}] load splash ad[${index}]=${adId}`);
    this.armLoadGuard(index);
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) {
        this.clearLoadGuard();
        this.fallback('无法获取应用上下文');
        return;
      }
      const loader: advertising.AdLoader = new advertising.AdLoader(context);
      const listener: advertising.AdLoadListener = {
        onAdLoadFailure: (code: number, message: string): void => {
          this.clearLoadGuard();
          if (this.pageGone || this.jumped || this.phase !== PHASE_LOADING || this.slotIndex !== index) {
            return;
          }
          console.warn(`[${TAG}] splash load failed id=${adId} code=${code} msg=${message}`);
          this.advanceSlot(index, `加载失败（${code}）`);
        },
        onAdLoadSuccess: (ads: advertising.Advertisement[]): void => {
          this.clearLoadGuard();
          // 已超时切到下一个广告位/已跳转时，迟到的结果直接丢弃
          if (this.pageGone || this.jumped || this.phase !== PHASE_LOADING || this.slotIndex !== index) {
            return;
          }
          if (ads.length === 0) {
            this.advanceSlot(index, '返回为空');
            return;
          }
          const ad: advertising.Advertisement = ads[0];
          if (ad.adType !== AdType.SPLASH) {
            console.warn(`[${TAG}] unexpected adType=${ad.adType}, still render as splash`);
          }
          this.loadedAdId = adId;
          this.splashAds = [ad];
          this.adFullScreen = this.readFullScreen(ad);
          this.phase = PHASE_AD;
          this.armRenderGuard();
          console.info(`[${TAG}] splash load ok id=${adId}, fullScreen=${this.adFullScreen}`);
        }
      };
      loader.loadAd({ adId: adId, adType: AdType.SPLASH, adCount: 1 }, {}, listener);
    } catch (e) {
      this.clearLoadGuard();
      console.warn(`[${TAG}] loadAd throw id=${adId}: ${JSON.stringify(e)}`);
      this.advanceSlot(index, '请求异常');
    }
  }

  /** 当前广告位不可用：还有备用位就继续，全部失败才退回默认开屏 */
  private advanceSlot(index: number, reason: string): void {
    if (this.pageGone || this.jumped || this.phase !== PHASE_LOADING) {
      return;
    }
    const failure: string = `广告位 ${SPLASH_AD_IDS[index]} ${reason}`;
    this.slotFailures.push(failure);
    console.warn(`[${TAG}] ${failure}`);
    if (index + 1 < SPLASH_AD_IDS.length) {
      this.tryLoadSlot(index + 1);
      return;
    }
    this.fallback(`开屏广告位均不可用：${this.slotFailures.join('；')}`);
  }

  /**
   * 读取广告响应里的 isFullScreen。
   *
   * Advertisement 用索引签名承载自定义字段（`[key: string]: Object`），
   * 这里显式收窄成 boolean；个别测试广告位不返回该字段，按全屏处理。
   */
  private readFullScreen(ad: advertising.Advertisement): boolean {
    const flag: Object | undefined = ad['isFullScreen'];
    if (flag === undefined) {
      return true;
    }
    return flag as boolean;
  }

  /** AdComponent 的广告状态回调：跳主页的唯一真实入口是 onAdClose */
  private adInteractionListener(): advertising.AdInteractionListener {
    return {
      onStatusChanged: (status: string, _ad: advertising.Advertisement, data: string): void => {
        this.onAdStatus(status, data);
      }
    };
  }

  private onAdStatus(status: string, data: string): void {
    if (this.pageGone || this.jumped) {
      return;
    }
    console.info(`[${TAG}] ad status=${status} data=${data}`);
    if (status === 'onAdClose') {
      const reason: string = data.length > 0 ? data : 'closed';
      this.goMain(`onAdClose:${reason}`);
    } else if (status === 'onAdOpen') {
      // 广告已真正展示，撤销“渲染超时”兜底
      this.clearRenderGuard();
    } else if (status === 'onAdFail') {
      this.fallback(data.length > 0 ? `广告展示失败：${data}` : '广告展示失败');
    }
  }

  /** 单个广告位的请求超时：没等到回调时切到下一个广告位 */
  private armLoadGuard(index: number): void {
    this.clearLoadGuard();
    this.loadGuardId = setTimeout(() => {
      this.loadGuardId = -1;
      if (this.pageGone || this.jumped || this.phase !== PHASE_LOADING || this.slotIndex !== index) {
        return;
      }
      console.warn(`[${TAG}] splash load timeout id=${SPLASH_AD_IDS[index]}`);
      this.advanceSlot(index, '请求超时');
    }, AD_LOAD_TIMEOUT_MS);
  }

  /** 广告渲染保护：AdComponent 挂载后连 onAdOpen 都没有时，别让开屏页永久卡住 */
  private armRenderGuard(): void {
    this.clearRenderGuard();
    this.renderGuardId = setTimeout(() => {
      this.renderGuardId = -1;
      if (this.pageGone || this.jumped) {
        return;
      }
      if (this.phase === PHASE_AD) {
        console.warn(`[${TAG}] splash ad did not open in time`);
        this.goMain('adTimeout');
      }
    }, AD_RENDER_GUARD_MS);
  }

  private clearLoadGuard(): void {
    if (this.loadGuardId >= 0) {
      clearTimeout(this.loadGuardId);
      this.loadGuardId = -1;
    }
  }

  private clearRenderGuard(): void {
    if (this.renderGuardId >= 0) {
      clearTimeout(this.renderGuardId);
      this.renderGuardId = -1;
    }
  }

  // ===================== 兜底默认开屏 =====================

  /** 广告不可用时切回默认开屏（5 秒倒计时后进主页） */
  private fallback(reason: string): void {
    if (this.pageGone || this.jumped || this.phase === PHASE_FALLBACK) {
      return;
    }
    console.warn(`[${TAG}] fallback to default splash: ${reason}`);
    this.clearLoadGuard();
    this.clearRenderGuard();
    this.phase = PHASE_FALLBACK;
    this.splashAds = [];
    this.fallbackReason = reason;
    this.remainSeconds = SPLASH_SECONDS;
    this.startFallbackCountdown();
  }

  private startFallbackCountdown(): void {
    if (this.timerId >= 0 || this.jumped) {
      return;
    }
    this.timerId = setInterval(() => {
      if (this.pageGone || this.jumped) {
        this.stopFallbackCountdown();
        return;
      }
      if (this.remainSeconds <= 1) {
        this.remainSeconds = 0;
        this.goMain('fallback');
      } else {
        this.remainSeconds -= 1;
      }
    }, 1000);
  }

  private stopFallbackCountdown(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  // ===================== 跳转 =====================

  /** 开屏结束：用主页替换当前开屏页（栈内不保留 Splash） */
  private goMain(reason: string): void {
    if (this.jumped || this.pageGone) {
      return;
    }
    this.jumped = true;
    this.stopFallbackCountdown();
    this.clearLoadGuard();
    this.clearRenderGuard();

    const waited: number = Math.max(0, Math.round((Date.now() - this.startTs) / 1000));
    const params: RouterLaunchParams = new RouterLaunchParams();
    params.from = PageNames.ROUTER_SPLASH_PAGE;
    params.ts = Date.now();
    params.waitedSeconds = waited;
    params.closeReason = reason;
    params.adSlot = this.loadedAdId;
    router.replaceUrl({ url: PageNames.ROUTER_MAIN_PAGE, params: params })
      .then(() => {
        console.info(`[${TAG}] replaceUrl -> ${PageNames.ROUTER_MAIN_PAGE}, reason=${reason}, waited=${waited}s`);
      })
      .catch((err: BusinessError) => {
        console.error(`[${TAG}] replaceUrl failed: ${JSON.stringify(err)}`);
        // 跳转失败：收起广告、退回默认开屏，用户可点「跳过」重试
        this.jumped = false;
        if (!this.pageGone) {
          this.phase = PHASE_FALLBACK;
          this.splashAds = [];
          this.fallbackReason = `进入应用主页失败（${err.code}），点击“跳过”重试`;
        }
        Toast.show(`进入模拟主页失败：${err.code}`);
      });
  }

  /** 用户跳过开屏（广告未展示或半屏广告下方仍可见时） */
  private skipSplash(): void {
    this.goMain('skip');
  }

  // ===================== 状态栏 =====================

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

  // ===================== UI =====================

  /** 深色开屏背景：左上品牌紫 -> 右下深紫，避免系统浅色模式下页面发白 */
  private splashColors(): Array<[ResourceColor, number]> {
    return [
      ['#1B1B2F', 0.0],
      ['#2D2A55', 0.55],
      ['#4B3F72', 1.0]
    ];
  }

  /** 默认开屏（广告加载中 / 加载失败兜底都展示这一层） */
  @Builder
  private defaultSplash(): void {
    Column() {
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
            this.skipSplash();
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

        if (this.phase === PHASE_LOADING) {
          this.loadingCard()
        } else {
          this.fallbackCard()
        }
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 24, right: 24 })

      Text('RouterSplashPage · 开屏广告 onAdClose → router.replaceUrl → RouterMainPage')
        .fontSize(10)
        .fontColor('rgba(255, 255, 255, 0.4)')
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 14 })
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: this.safeBottom })
    .linearGradient({
      angle: 160,
      colors: this.splashColors()
    })
  }

  /** 广告请求中的默认 Slogan 卡片 */
  @Builder
  private loadingCard(): void {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(28)
        .height(28)
        .color('rgba(255, 255, 255, 0.82)')
      Text('正在请求开屏广告…')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('rgba(255, 255, 255, 0.82)')
      Text('广告展示关闭后自动进入应用主页')
        .fontSize(11)
        .fontColor('rgba(255, 255, 255, 0.48)')
        .textAlign(TextAlign.Center)
    }
    .width('86%')
    .height(118)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(255, 255, 255, 0.06)')
    .borderRadius(14)
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.22)', style: BorderStyle.Dashed })
  }

  /** 广告不可用时的默认开屏卡片：保留原来的 5 秒倒计时 */
  @Builder
  private fallbackCard(): void {
    Column({ space: 8 }) {
      Text('未获取到开屏广告')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('rgba(255, 255, 255, 0.86)')
      if (this.fallbackReason.length > 0) {
        Text(this.fallbackReason)
          .fontSize(11)
          .fontColor('rgba(255, 255, 255, 0.52)')
          .textAlign(TextAlign.Center)
          .padding({ left: 12, right: 12 })
      }
      Text('已切换为默认开屏')
        .fontSize(11)
        .fontColor('rgba(255, 255, 255, 0.48)')

      Progress({
        value: SPLASH_SECONDS - this.remainSeconds,
        total: SPLASH_SECONDS,
        type: ProgressType.Linear
      })
        .width('72%')
        .height(4)
        .color('#FF4500')
        .backgroundColor('rgba(255, 255, 255, 0.18)')
        .margin({ top: 2 })

      Text(`${this.remainSeconds} 秒后进入应用主页`)
        .fontSize(12)
        .fontColor('rgba(255, 255, 255, 0.7)')
    }
    .width('86%')
    .padding(14)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(255, 255, 255, 0.06)')
    .borderRadius(14)
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.22)', style: BorderStyle.Dashed })
  }

  /** 全屏开屏广告：铺满整页，关闭回调由 AdComponent 的 onStatusChanged 给出 */
  @Builder
  private fullScreenAd(): void {
    AdComponent({
      ads: this.splashAds,
      displayOptions: this.adDisplayOptions,
      interactionListener: this.adInteractionListener()
    })
      .width('100%')
      .height('100%')
  }

  /**
   * 半屏开屏广告：广告占上方，媒体品牌位（图标/应用名/“广告”标识）放在下方，
   * 与官方半屏示例的布局一致。
   */
  @Builder
  private halfScreenAdLayout(): void {
    Column() {
      AdComponent({
        ads: this.splashAds,
        displayOptions: this.adDisplayOptions,
        interactionListener: this.adInteractionListener()
      })
        .width('100%')
        // 官方半屏示例：广告占 87%，下方 13% 留给媒体品牌位
        .height('87%')

      Row({ space: 8 }) {
        Image($r('app.media.chaoji_bust_style'))
          .width(28)
          .height(28)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)

        Column({ space: 2 }) {
          Text($r('app.string.app_name'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
          Text('模拟应用开屏')
            .fontSize(10)
            .fontColor('#999999')
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Text('广告')
          .fontSize(10)
          .fontColor('#8A8A8A')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .border({ width: 1, color: 'rgba(0, 0, 0, 0.16)' })
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16 })
      .backgroundColor(Color.White)
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: this.safeBottom })
    .backgroundColor(Color.White)
  }

  build() {
    Stack() {
      // 默认开屏始终作为底层：广告加载前是用户看到的 Slogan，全屏广告会把它完全盖住
      this.defaultSplash()

      if (this.phase === PHASE_AD && this.splashAds.length > 0) {
        if (this.adFullScreen) {
          this.fullScreenAd()
        } else {
          this.halfScreenAdLayout()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1B1B2F')
    // 关掉点击穿透：开屏页整屏覆盖，避免点到下层 HMRouter 页面
    .hitTestBehavior(HitTestMode.Block)
  }
}
