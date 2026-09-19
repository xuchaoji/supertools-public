import advertising from '@hw-ads/ads';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { PreferencesUtil } from '@pura/harmony-utils';
import { TargetConstants } from 'main/ets/TargetConstants';
import { AdConstants } from '../constant/AdConstants';
import { SpKeys } from '../constant/SpKeys';
import { GlobalContextHolder } from './GlobalContextHolder';

const DOMAIN: number = 0x0000;
const TAG: string = 'AdManager';

/** 广告 SDK 展示全屏广告时创建的窗口名（实测固定为 showAd） */
const AD_WINDOW_NAME: string = 'showAd';

/**
 * 广告统一管理器（鲸鸿动能 Ads Kit，经 @hw-ads/ads 集成包接入）。
 *
 * 职责：
 * - SDK 初始化：**必须在用户同意隐私政策之后**才初始化（合规要求：同意前不得初始化广告 SDK、
 *   不得读取设备标识）；因此 init 放在 MainAbility 冷启动（已同意）或 PrivacyPage 点击“同意”之后。
 * - 开屏广告：冷启动（已同意隐私）进入首页前加载并展示，加载超过 SPLASH_LOAD_TIMEOUT_MS 放弃展示。
 * - 插屏广告：每次从工具页返回主页都会尝试展示（频控见 AdConstants，<=0 表示不限制）。
 * - 激励广告：按需加载展示，看完（ad.rewarded === true）后回调发放奖励。
 * - 广告窗口清理：全屏广告（showAd）结束后 SDK 会把全屏窗口留在窗口栈里并持有输入焦点，
 *   导致「主页所有点击无响应」，因此广告结束（或超时未结束）后按窗口名强制销毁该窗口。
 *
 * 开关：仅在 TargetConstants.AD_ENABLED 为 true 的产物中生效，
 * 关闭的产物完全不初始化 SDK、不发起广告请求。
 */
export class AdManager {
  private static instance: AdManager;

  /** SDK 是否已初始化成功 */
  private inited: boolean = false;
  /** 开屏广告本次运行是否已经尝试过（进程内只尝试一次） */
  private splashRequested: boolean = false;
  /** 插屏：是否从首页打开过工具页（用于判定“返回主页”而不是首次进入） */
  private toolPageOpened: boolean = false;
  /** 插屏：是否正在展示（避免重复触发） */
  private interstitialShowing: boolean = false;
  /** 插屏：本次运行已展示次数 */
  private interstitialShownCount: number = 0;
  /** 插屏：上次展示时间（ms） */
  private lastInterstitialTime: number = 0;
  /** 激励：是否正在加载/展示（避免重复点击） */
  private rewardedBusy: boolean = false;
  /** 广告窗口兜底清理定时器（-1 表示未启用） */
  private splashWindowTimer: number = -1;
  private interstitialWindowTimer: number = -1;
  private rewardedWindowTimer: number = -1;

  public static getInstance(): AdManager {
    if (!AdManager.instance) {
      AdManager.instance = new AdManager();
    }
    return AdManager.instance;
  }

  // ==================== 广告窗口清理 ====================

  /**
   * 销毁广告 SDK 遗留的全屏广告窗口。
   *
   * 背景（实测：HSP 版 8.4.90 + HarmonyOS 7 / API 26 真机）：
   * 开屏广告结束后（已收到 onAdClose: adShowEnded），SDK 创建的窗口（WindowName = 'showAd'，
   * 全屏、Z 序在应用主窗口之上）仍留在窗口栈中并持有输入焦点
   * （hidumper: Focus window / Highlighted windows 均为该窗口），
   * 表现为「进入主页后白屏且所有点击无响应」。
   * SDK 公开 API（init/showAd/getAdRequestBody/parseAdResponse/registerWebAdInterface/
   * deleteWebAdInterface/AdLoader）没有关闭广告窗口的方法，因此这里按窗口名查找并销毁。
   */
  private dismissAdWindow(reason: string): void {
    try {
      const adWindow: window.Window = window.findWindow(AD_WINDOW_NAME);
      adWindow.destroyWindow()
        .then(() => {
          hilog.info(DOMAIN, TAG, 'ad window dismissed (%{public}s)', reason);
        })
        .catch((err: Object) => {
          hilog.error(DOMAIN, TAG, 'ad window dismiss failed (%{public}s): %{public}s',
            reason, JSON.stringify(err));
        });
    } catch (e) {
      // 窗口不存在（Advertisement 未打开广告窗口/已被回收）属正常情况
      hilog.info(DOMAIN, TAG, 'ad window absent (%{public}s)', reason);
    }
  }

  /** 广告打开后启动兜底清理定时器：超时仍未收到 onAdClose 也强制清理遗留窗口 */
  private armAdWindowWatchdog(delayMs: number, reason: string): number {
    return setTimeout(() => {
      hilog.info(DOMAIN, TAG, 'ad window watchdog fired (%{public}s)', reason);
      this.dismissAdWindow(`${reason} watchdog`);
    }, delayMs);
  }

  private clearAdWindowWatchdog(timer: number): void {
    if (timer >= 0) {
      clearTimeout(timer);
    }
  }

  // ==================== 初始化 ====================

  /** 用户是否已同意隐私政策 */
  private hasPrivacyConsent(): boolean {
    try {
      return PreferencesUtil.getBooleanSync(SpKeys.PRIVACY_AGREE, false);
    } catch (e) {
      return false;
    }
  }

  /** 广告能力是否可用（产物开关 + 已同意隐私 + SDK 已初始化） */
  public isAdReady(): boolean {
    return TargetConstants.AD_ENABLED && this.inited && this.hasPrivacyConsent();
  }

  /**
   * 同意隐私政策后初始化 SDK（幂等）。
   * 未开启广告的产物 / 未同意隐私政策时直接跳过。
   */
  public initIfConsented(ctx: common.UIAbilityContext | undefined): void {
    if (!TargetConstants.AD_ENABLED) {
      hilog.info(DOMAIN, TAG, 'ad disabled in this target, skip init');
      return;
    }
    if (!ctx) {
      hilog.error(DOMAIN, TAG, 'init skipped: uiAbilityContext is undefined');
      return;
    }
    if (!this.hasPrivacyConsent()) {
      hilog.info(DOMAIN, TAG, 'init skipped: privacy policy not agreed');
      return;
    }
    if (this.inited) {
      return;
    }
    try {
      advertising.init(ctx);
      this.inited = true;
      hilog.info(DOMAIN, TAG, 'ads sdk init success');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'ads sdk init failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 冷启动 / 首次同意隐私后的统一入口：初始化 + 尝试展示开屏 */
  public initAndShowSplashIfNeeded(ctx: common.UIAbilityContext | undefined): void {
    this.initIfConsented(ctx);
    if (!ctx) {
      return;
    }
    this.showSplashIfNeeded(ctx);
  }

  // ==================== 开屏广告 ====================

  /**
   * 开屏广告：本次运行只尝试一次；
   * 加载成功且未超时才展示（超时后放弃，避免用户已进入首页操作后才弹出全屏广告）。
   */
  public showSplashIfNeeded(ctx: common.UIAbilityContext): void {
    if (!TargetConstants.AD_ENABLED || this.splashRequested) {
      return;
    }
    if (!this.isAdReady()) {
      hilog.info(DOMAIN, TAG, 'splash skipped: ad not ready');
      return;
    }
    this.splashRequested = true;

    let finished: boolean = false;
    const timer: number = setTimeout(() => {
      if (!finished) {
        finished = true;
        hilog.info(DOMAIN, TAG, 'splash skipped: load timeout(%{public}dms)', AdConstants.SPLASH_LOAD_TIMEOUT_MS);
      }
    }, AdConstants.SPLASH_LOAD_TIMEOUT_MS);

    try {
      const adParam: advertising.AdRequestParams = {
        adId: AdConstants.AD_ID_SPLASH,
        adType: AdConstants.AD_TYPE_SPLASH,
        adCount: 1
      };
      const adOptions: advertising.AdOptions = {};
      const loadListener: advertising.AdLoadListener = {
        onAdLoadFailure: (errorCode: number, errorMsg: string): void => {
          finished = true;
          clearTimeout(timer);
          hilog.error(DOMAIN, TAG, 'splash load failed: code=%{public}d msg=%{public}s', errorCode, errorMsg);
        },
        onAdLoadSuccess: (ads: Array<advertising.Advertisement>): void => {
          clearTimeout(timer);
          if (finished || ads.length === 0) {
            hilog.info(DOMAIN, TAG, 'splash skipped: timeout=%{public}s count=%{public}d',
              finished ? 'true' : 'false', ads.length);
            return;
          }
          finished = true;
          this.showSplashAd(ads[0], ctx);
        }
      };
      const loader: advertising.AdLoader = new advertising.AdLoader(ctx);
      loader.loadAd(adParam, adOptions, loadListener);
      hilog.info(DOMAIN, TAG, 'splash load started');
    } catch (e) {
      clearTimeout(timer);
      hilog.error(DOMAIN, TAG, 'splash load exception: %{public}s', JSON.stringify(e));
    }
  }

  private showSplashAd(ad: advertising.Advertisement, ctx: common.UIAbilityContext): void {
    const displayOptions: advertising.AdDisplayOptions = { mute: true };
    const interactionListener: advertising.AdInteractionListener = {
      onStatusChanged: (status: string, adItem: advertising.Advertisement, data: string): void => {
        hilog.info(DOMAIN, TAG, 'splash status=%{public}s data=%{public}s', status, data);
        if (status === 'onAdOpen') {
          // 广告窗口打开：启动兜底清理（避免广告结束后窗口残留导致应用无法交互）
          this.clearAdWindowWatchdog(this.splashWindowTimer);
          this.splashWindowTimer =
            this.armAdWindowWatchdog(AdConstants.SPLASH_AD_WINDOW_WATCHDOG_MS, 'splash');
        } else if (status === 'onAdClose') {
          this.clearAdWindowWatchdog(this.splashWindowTimer);
          this.splashWindowTimer = -1;
          this.dismissAdWindow(`splash onAdClose(${data})`);
        }
      }
    };
    advertising.showAd(ad, displayOptions, ctx, interactionListener)
      .then(() => {
        hilog.info(DOMAIN, TAG, 'splash show finished');
      })
      .catch((err: Object) => {
        hilog.error(DOMAIN, TAG, 'splash show failed: %{public}s', JSON.stringify(err));
      });
  }

  // ==================== 插屏广告 ====================

  /** 首页点击任一工具卡片（即将跳转工具页）时调用，标记“稍后返回主页” */
  public notifyToolPageOpened(): void {
    if (!TargetConstants.AD_ENABLED) {
      return;
    }
    this.toolPageOpened = true;
  }

  /**
   * 从工具页返回主页时调用：加载并展示插屏广告（每次返回都会尝试，见 AdConstants 频控配置）。
   * 同一次返回只会触发一次（toolPageOpened 标记被消费，配合 interstitialShowing 去重）；
   * 未展示（加载失败/暂无填充）不影响任何页面逻辑。
   */
  public tryShowReturnInterstitial(ctx: common.UIAbilityContext | undefined): void {
    if (!TargetConstants.AD_ENABLED || !this.toolPageOpened) {
      return;
    }
    // 本次“返回”只消费一次，避免同一次返回被多个生命周期回调重复触发
    this.toolPageOpened = false;

    if (this.interstitialShowing) {
      return;
    }
    if (!ctx || !this.isAdReady()) {
      hilog.info(DOMAIN, TAG, 'interstitial skipped: ad not ready');
      return;
    }
    // 频控：常量 <= 0 表示不限制（当前为不限制，每次返回都展示）
    if (AdConstants.INTERSTITIAL_MAX_PER_SESSION > 0
      && this.interstitialShownCount >= AdConstants.INTERSTITIAL_MAX_PER_SESSION) {
      hilog.info(DOMAIN, TAG, 'interstitial skipped: session limit reached');
      return;
    }
    const now: number = Date.now();
    if (AdConstants.INTERSTITIAL_MIN_INTERVAL_MS > 0 && this.lastInterstitialTime > 0
      && now - this.lastInterstitialTime < AdConstants.INTERSTITIAL_MIN_INTERVAL_MS) {
      hilog.info(DOMAIN, TAG, 'interstitial skipped: frequency control');
      return;
    }

    this.interstitialShowing = true;
    try {
      const adParam: advertising.AdRequestParams = {
        adId: AdConstants.AD_ID_INTERSTITIAL,
        adType: AdConstants.AD_TYPE_INTERSTITIAL,
        adCount: 1
      };
      const adOptions: advertising.AdOptions = {};
      const loadListener: advertising.AdLoadListener = {
        onAdLoadFailure: (errorCode: number, errorMsg: string): void => {
          this.interstitialShowing = false;
          hilog.error(DOMAIN, TAG, 'interstitial load failed: code=%{public}d msg=%{public}s', errorCode, errorMsg);
        },
        onAdLoadSuccess: (ads: Array<advertising.Advertisement>): void => {
          if (ads.length === 0) {
            this.interstitialShowing = false;
            return;
          }
          this.interstitialShownCount++;
          this.lastInterstitialTime = Date.now();
          const displayOptions: advertising.AdDisplayOptions = {};
          const interactionListener: advertising.AdInteractionListener = {
            onStatusChanged: (status: string, adItem: advertising.Advertisement, data: string): void => {
              hilog.info(DOMAIN, TAG, 'interstitial status=%{public}s data=%{public}s', status, data);
              if (status === 'onAdOpen') {
                this.clearAdWindowWatchdog(this.interstitialWindowTimer);
                this.interstitialWindowTimer =
                  this.armAdWindowWatchdog(AdConstants.FULLSCREEN_AD_WINDOW_WATCHDOG_MS, 'interstitial');
              } else if (status === 'onAdClose') {
                this.clearAdWindowWatchdog(this.interstitialWindowTimer);
                this.interstitialWindowTimer = -1;
                this.dismissAdWindow(`interstitial onAdClose(${data})`);
                // 「正在展示」标记必须等广告真正关闭（onAdClose）才复位：
                // showAd 的 Promise 在广告“打开”时就 resolve，若在 then 里复位，
                // 广告还挂在屏幕上时就能被再次触发，导致叠出第二个插屏窗口。
                this.interstitialShowing = false;
              }
            }
          };
          advertising.showAd(ads[0], displayOptions, ctx, interactionListener)
            .then(() => {
              // 注意：这里只表示广告已打开（SDK 在打开时即 resolve），复位标记见 onAdClose
              hilog.info(DOMAIN, TAG, 'interstitial show started');
            })
            .catch((err: Object) => {
              this.interstitialShowing = false;
              hilog.error(DOMAIN, TAG, 'interstitial show failed: %{public}s', JSON.stringify(err));
            });
        }
      };
      const loader: advertising.AdLoader = new advertising.AdLoader(ctx);
      loader.loadAd(adParam, adOptions, loadListener);
      hilog.info(DOMAIN, TAG, 'interstitial load started');
    } catch (e) {
      this.interstitialShowing = false;
      hilog.error(DOMAIN, TAG, 'interstitial load exception: %{public}s', JSON.stringify(e));
    }
  }

  // ==================== 激励广告 ====================

  /**
   * 加载并展示激励广告。
   * @param ctx UIAbilityContext
   * @param onRewarded 用户完整观看（ad.rewarded === true）后回调，用于发放奖励/解锁
   * @param onFailed 加载或展示失败回调（用于界面提示），可选
   */
  public loadAndShowRewarded(ctx: common.UIAbilityContext | undefined,
    onRewarded: () => void,
    onFailed?: (message: string) => void): void {
    if (!TargetConstants.AD_ENABLED) {
      hilog.info(DOMAIN, TAG, 'rewarded skipped: ad disabled in this target');
      this.notifyFailed(onFailed, '当前版本未启用广告');
      return;
    }
    if (!ctx || !this.isAdReady()) {
      hilog.info(DOMAIN, TAG, 'rewarded skipped: ad not ready');
      this.notifyFailed(onFailed, '广告暂不可用，请稍后再试');
      return;
    }
    if (this.rewardedBusy) {
      return;
    }
    this.rewardedBusy = true;

    try {
      const adParam: advertising.AdRequestParams = {
        adId: AdConstants.AD_ID_REWARDED,
        adType: AdConstants.AD_TYPE_REWARDED,
        adCount: 1
      };
      const adOptions: advertising.AdOptions = {};
      const loadListener: advertising.AdLoadListener = {
        onAdLoadFailure: (errorCode: number, errorMsg: string): void => {
          this.rewardedBusy = false;
          hilog.error(DOMAIN, TAG, 'rewarded load failed: code=%{public}d msg=%{public}s', errorCode, errorMsg);
          this.notifyFailed(onFailed, '广告加载失败，请稍后再试');
        },
        onAdLoadSuccess: (ads: Array<advertising.Advertisement>): void => {
          if (ads.length === 0) {
            this.rewardedBusy = false;
            this.notifyFailed(onFailed, '暂无可用广告');
            return;
          }
          const displayOptions: advertising.AdDisplayOptions = { mute: false };
          // 本次展示是否已发放奖励（保证只发一次）
          let rewardGranted: boolean = false;
          const grantReward = (): void => {
            if (rewardGranted) {
              return;
            }
            rewardGranted = true;
            hilog.info(DOMAIN, TAG, 'rewarded granted');
            onRewarded();
          };
          const interactionListener: advertising.AdInteractionListener = {
            onStatusChanged: (status: string, adItem: advertising.Advertisement, data: string): void => {
              hilog.info(DOMAIN, TAG, 'rewarded status=%{public}s data=%{public}s', status, data);
              if (status === 'onAdOpen') {
                this.clearAdWindowWatchdog(this.rewardedWindowTimer);
                this.rewardedWindowTimer =
                  this.armAdWindowWatchdog(AdConstants.FULLSCREEN_AD_WINDOW_WATCHDOG_MS, 'rewarded');
              }
              // 发奖一律以 InteractionListener 的状态回调为准（本 SDK 的实际回调通道）：
              // 该 HSP 版 SDK 在视频播完时回调 onAdReward（data 为 JSON：
              // {"rewardType":"","rewardAmount":0,"uniqueId":"..."}），此时才认为奖励达成。
              // 不依赖 @kit.AdsKit 文档描述的事件流。
              if (status === 'onAdReward') {
                hilog.info(DOMAIN, TAG, 'rewarded reward event from listener: %{public}s', data);
                grantReward();
              }
              if (status === 'onAdClose') {
                this.clearAdWindowWatchdog(this.rewardedWindowTimer);
                this.rewardedWindowTimer = -1;
                this.dismissAdWindow(`rewarded onAdClose(${data})`);
                this.rewardedBusy = false;
                // 兜底：若某些广告变体只在关闭时通过 ad.rewarded 标记奖励达成，也一并认掉
                if (adItem && adItem.rewarded === true) {
                  grantReward();
                } else if (!rewardGranted) {
                  // 未收到 onAdReward：用户提前关闭（data 为关闭原因，如 adCloseBtnClicked）
                  hilog.info(DOMAIN, TAG, 'rewarded not granted, close reason=%{public}s', data);
                  this.notifyFailed(onFailed, '需完整观看视频后才能解锁');
                }
              }
            }
          };
          advertising.showAd(ads[0], displayOptions, ctx, interactionListener)
            .then(() => {
              this.rewardedBusy = false;
              hilog.info(DOMAIN, TAG, 'rewarded show finished');
            })
            .catch((err: Object) => {
              this.rewardedBusy = false;
              hilog.error(DOMAIN, TAG, 'rewarded show failed: %{public}s', JSON.stringify(err));
              this.notifyFailed(onFailed, '广告展示失败，请稍后再试');
            });
        }
      };
      const loader: advertising.AdLoader = new advertising.AdLoader(ctx);
      loader.loadAd(adParam, adOptions, loadListener);
      hilog.info(DOMAIN, TAG, 'rewarded load started');
    } catch (e) {
      this.rewardedBusy = false;
      hilog.error(DOMAIN, TAG, 'rewarded load exception: %{public}s', JSON.stringify(e));
      this.notifyFailed(onFailed, '广告加载异常，请稍后再试');
    }
  }

  private notifyFailed(onFailed: ((message: string) => void) | undefined, message: string): void {
    if (onFailed) {
      onFailed(message);
    }
  }

  // ==================== 原生广告 ====================

  /** 加载原生广告（设置页底部展示），成功后由调用方用 AdComponent 渲染 */
  public loadNativeAd(onSuccess: (ads: Array<advertising.Advertisement>) => void): void {
    if (!this.isAdReady()) {
      hilog.info(DOMAIN, TAG, 'native skipped: ad not ready');
      return;
    }
    const ctx: common.UIAbilityContext | undefined = GlobalContextHolder.getInstance().uiAbilityContext;
    if (!ctx) {
      hilog.error(DOMAIN, TAG, 'native skipped: uiAbilityContext is undefined');
      return;
    }
    try {
      const adParam: advertising.AdRequestParams = {
        adId: AdConstants.AD_ID_NATIVE,
        adType: AdConstants.AD_TYPE_NATIVE,
        adCount: 1
      };
      const adOptions: advertising.AdOptions = {};
      const loadListener: advertising.AdLoadListener = {
        onAdLoadFailure: (errorCode: number, errorMsg: string): void => {
          hilog.error(DOMAIN, TAG, 'native load failed: code=%{public}d msg=%{public}s', errorCode, errorMsg);
        },
        onAdLoadSuccess: (ads: Array<advertising.Advertisement>): void => {
          if (ads.length > 0) {
            onSuccess(ads);
          }
        }
      };
      const loader: advertising.AdLoader = new advertising.AdLoader(ctx);
      loader.loadAd(adParam, adOptions, loadListener);
      hilog.info(DOMAIN, TAG, 'native load started');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'native load exception: %{public}s', JSON.stringify(e));
    }
  }
}
