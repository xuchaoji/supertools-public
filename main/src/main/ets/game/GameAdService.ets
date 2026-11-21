/**
 * GameAdService.ets — 游戏侧广告调度（激励 / 插屏 / 开屏）。
 *
 * 与 AdsKitPage 的关系：
 *  - 广告位 ID 统一来自 AdsKitPreferences（默认华为官方测试 ID），不另建配置；
 *  - 这里只做「加载 -> 展示 -> 把回调翻译成游戏能用的结果」，
 *    具体弹窗、发奖、恢复游戏由页面与 GameEngine 决定。
 *
 * 关键差异（相比常见 Web/引擎广告协议）：
 *  华为 Ads Kit 没有 onAdRewarded 事件，发奖依据是关闭时的 `ad.rewarded` 字段，
 *  所以这里把 onAdClose + ad.rewarded 合成一个 AdOutcome 返回。
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import advertising from '@hw-ads/ads';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AdType } from '../constant/AdType';
import { AdsKitPreferences } from '../utils/AdsKitPreferences';

const TAG: string = 'GAME_AD';
/** 加载超时：避免广告请求把游戏卡在"加载中"。 */
const LOAD_TIMEOUT_MS: number = 8000;
/** 展示保护：正常关闭会先到；超时后强制返回，防止状态机永远挂起。 */
const SHOW_TIMEOUT_MS: number = 90000;
/** Mock 模式下模拟广告时长。 */
const MOCK_DURATION_MS: number = 1200;

export interface AdOutcome {
  /** 广告是否正常展示并关闭。 */
  ok: boolean;
  /** 是否应发放奖励（仅激励视频有意义）。 */
  rewarded: boolean;
  /** 是否走了 Mock（无真实广告位/加载失败时的兜底）。 */
  mock: boolean;
  /** 给调试面板看的一句话结果。 */
  message: string;
}

export class GameAdService {
  private static instance: GameAdService | null = null;
  private logs: string[] = [];
  /** 强制 Mock：调试面板可以打开，用于完全脱网验证游戏闭环。 */
  private forceMock: boolean = false;

  public static getInstance(): GameAdService {
    if (GameAdService.instance === null) {
      GameAdService.instance = new GameAdService();
    }
    return GameAdService.instance;
  }

  public setForceMock(value: boolean): void {
    this.forceMock = value;
    this.pushLog(`forceMock=${value}`);
  }

  public isForceMock(): boolean {
    return this.forceMock;
  }

  public getLogText(): string {
    if (this.logs.length === 0) {
      return '（暂无广告回调）';
    }
    return this.logs.join('\n');
  }

  public getLogs(): string[] {
    return this.logs.slice();
  }

  /** 供页面把 Banner 等外部回调也写进同一个日志台。 */
  public note(line: string): void {
    this.pushLog(line);
  }

  private pushLog(line: string): void {
    const now: Date = new Date();
    const time: string = `${GameAdService.pad(now.getHours())}:${GameAdService.pad(now.getMinutes())}:` +
      `${GameAdService.pad(now.getSeconds())}`;
    this.logs.unshift(`[${time}] ${line}`);
    if (this.logs.length > 30) {
      this.logs.pop();
    }
    hilog.info(0x0000, TAG, '%{public}s', line);
  }

  private static pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  // ===================== 激励视频 =====================

  /** 加载并展示激励视频；返回关闭时的发奖结果。 */
  public async showRewarded(context: common.UIAbilityContext): Promise<AdOutcome> {
    const adId: string = AdsKitPreferences.getId(AdType.REWARD);
    this.pushLog(`rewarded load id=${adId}`);
    if (this.forceMock) {
      return this.mockOutcome('rewarded', true);
    }
    const ad: advertising.Advertisement | null = await this.loadAd(context, AdType.REWARD, adId);
    if (ad === null) {
      this.pushLog('rewarded load failed -> mock');
      return this.mockOutcome('rewarded', true);
    }
    return new Promise<AdOutcome>((resolve) => {
      let settled: boolean = false;
      /** 实测：华为 Ads Kit 在看完时会发 onAdReward，而 ad.rewarded 在回调里一直是 false，
       *  所以发奖必须记 onAdReward，再在 onAdClose 时兑现（与文档里 onAdRewarded 的意图一致）。 */
      let earned: boolean = false;
      const finish = (outcome: AdOutcome): void => {
        if (settled) {
          return;
        }
        settled = true;
        resolve(outcome);
      };
      const guard: number = setTimeout(() => {
        this.pushLog('rewarded show timeout');
        finish({ ok: false, rewarded: false, mock: false, message: '广告展示超时' });
      }, SHOW_TIMEOUT_MS);

      try {
        advertising.showAd(ad, { mute: true }, context, {
          onStatusChanged: (status: string, shown: advertising.Advertisement, data: string): void => {
            this.pushLog(`rewarded ${status} ${data} rewarded=${shown.rewarded}`);
            if (status === 'onAdReward' || status === 'onAdRewardVerify') {
              earned = true;
            } else if (status === 'onAdClose') {
              clearTimeout(guard);
              const rewarded: boolean = earned || shown.rewarded;
              finish({
                ok: true,
                rewarded: rewarded,
                mock: false,
                message: rewarded ? '激励达成' : '未获得奖励'
              });
            } else if (status === 'onAdFail') {
              clearTimeout(guard);
              finish({ ok: false, rewarded: false, mock: false, message: `展示失败 ${data}` });
            }
          }
        }).catch((err: BusinessError) => {
          clearTimeout(guard);
          this.pushLog(`rewarded showAd reject code=${err.code}`);
          finish({ ok: false, rewarded: false, mock: false, message: `展示异常 ${err.code}` });
        });
      } catch (error) {
        clearTimeout(guard);
        this.pushLog('rewarded showAd throw');
        finish({ ok: false, rewarded: false, mock: false, message: '展示异常' });
      }
    });
  }

  // ===================== 插屏 =====================

  public async showInterstitial(context: common.UIAbilityContext): Promise<AdOutcome> {
    const adId: string = AdsKitPreferences.getId(AdType.INTERSTITIAL);
    this.pushLog(`interstitial load id=${adId}`);
    if (this.forceMock) {
      return this.mockOutcome('interstitial', false);
    }
    const ad: advertising.Advertisement | null = await this.loadAd(context, AdType.INTERSTITIAL, adId);
    if (ad === null) {
      this.pushLog('interstitial load failed -> mock');
      return this.mockOutcome('interstitial', false);
    }
    return this.showFullScreen(context, ad, 'interstitial');
  }

  // ===================== 开屏 =====================

  public async showSplash(context: common.UIAbilityContext): Promise<AdOutcome> {
    const adId: string = AdsKitPreferences.getId(AdType.SPLASH);
    this.pushLog(`splash load id=${adId}`);
    if (this.forceMock) {
      return this.mockOutcome('splash', false);
    }
    const ad: advertising.Advertisement | null = await this.loadAd(context, AdType.SPLASH, adId);
    if (ad === null) {
      this.pushLog('splash load failed -> mock');
      return this.mockOutcome('splash', false);
    }
    return this.showFullScreen(context, ad, 'splash');
  }

  // ===================== 内部实现 =====================

  private loadAd(context: common.UIAbilityContext, type: AdType,
    adId: string): Promise<advertising.Advertisement | null> {
    return new Promise<advertising.Advertisement | null>((resolve) => {
        let settled: boolean = false;
        const finish = (value: advertising.Advertisement | null): void => {
          if (settled) {
            return;
          }
          settled = true;
          resolve(value);
        };
        const guard: number = setTimeout(() => {
          this.pushLog(`load timeout type=${type}`);
          finish(null);
        }, LOAD_TIMEOUT_MS);
        try {
          const loader: advertising.AdLoader = new advertising.AdLoader(context);
          const listener: advertising.AdLoadListener = {
            onAdLoadFailure: (code: number, message: string): void => {
              clearTimeout(guard);
              this.pushLog(`load fail type=${type} code=${code} msg=${message}`);
              finish(null);
            },
            onAdLoadSuccess: (ads: Array<advertising.Advertisement>): void => {
              clearTimeout(guard);
              this.pushLog(`load ok type=${type} count=${ads.length}`);
              finish(ads.length > 0 ? ads[0] : null);
            }
          };
          loader.loadAd({ adId: adId, adType: type, adCount: 1 }, {}, listener);
        } catch (error) {
          clearTimeout(guard);
          this.pushLog(`load throw type=${type}`);
          finish(null);
        }
      });
  }

  private showFullScreen(context: common.UIAbilityContext, ad: advertising.Advertisement,
    label: string): Promise<AdOutcome> {
    return new Promise<AdOutcome>((resolve) => {
      let settled: boolean = false;
      const finish = (outcome: AdOutcome): void => {
        if (settled) {
          return;
        }
        settled = true;
        resolve(outcome);
      };
      const guard: number = setTimeout(() => {
        this.pushLog(`${label} show timeout`);
        finish({ ok: false, rewarded: false, mock: false, message: '广告展示超时' });
      }, SHOW_TIMEOUT_MS);
      try {
        advertising.showAd(ad, { mute: true }, context, {
          onStatusChanged: (status: string, _shown: advertising.Advertisement, data: string): void => {
            this.pushLog(`${label} ${status} ${data}`);
            if (status === 'onAdClose') {
              clearTimeout(guard);
              finish({ ok: true, rewarded: false, mock: false, message: '已关闭' });
            } else if (status === 'onAdFail') {
              clearTimeout(guard);
              finish({ ok: false, rewarded: false, mock: false, message: `展示失败 ${data}` });
            }
          }
        }).catch((err: BusinessError) => {
          clearTimeout(guard);
          this.pushLog(`${label} showAd reject code=${err.code}`);
          finish({ ok: false, rewarded: false, mock: false, message: `展示异常 ${err.code}` });
        });
      } catch (error) {
        clearTimeout(guard);
        this.pushLog(`${label} showAd throw`);
        finish({ ok: false, rewarded: false, mock: false, message: '展示异常' });
      }
    });
  }

  private async mockOutcome(label: string, reward: boolean): Promise<AdOutcome> {
    this.pushLog(`[MOCK] ${label} show start`);
    await this.delay(MOCK_DURATION_MS);
    this.pushLog(`[MOCK] ${label} close rewarded=${reward}`);
    return { ok: true, rewarded: reward, mock: true, message: `Mock ${label} 完成` };
  }
}
