import advertising, { AutoAdComponent } from '@hw-ads/ads';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AdType } from '../constant/AdType';
import { GameBannerConfig } from '../game/GameBannerConfig';

/**
 * 横幅广告子窗口页面。
 *
 * 它被游戏页通过 WindowStage.createSubWindow 加载到独立窗口里，
 * 因此游戏主窗口的 ArkUI 布局树只有 XComponent，广告不会混进游戏布局。
 * 广告加载失败时通知游戏页收起窗口，避免底部留下空白条。
 */
@Entry
@ComponentV2
export struct GameBannerPage {
  @Local adId: string = '';
  private reported: boolean = false;

  aboutToAppear(): void {
    this.adId = GameBannerConfig.adId;
    hilog.info(0x0000, 'GAME_BANNER', 'banner window adId=%{public}s', this.adId);
  }

  private report(loaded: boolean): void {
    if (this.reported) {
      return;
    }
    this.reported = true;
    GameBannerConfig.onStatus(loaded);
  }

  build() {
    Stack() {
      if (this.adId.length > 0) {
        AutoAdComponent({
          adParam: {
            adId: this.adId,
            adType: AdType.BANNER,
            adWidth: 360,
            adHeight: 57
          },
          adOptions: {},
          displayOptions: { mute: true, refreshTime: 30000 },
          interactionListener: {
            onStatusChanged: (status: string, _ad: advertising.Advertisement, _data: string): void => {
              hilog.info(0x0000, 'GAME_BANNER', 'status=%{public}s', status);
              if (status === 'onAdLoad' || status === 'onAdOpen') {
                this.report(true);
              } else if (status === 'onAdFail') {
                this.report(false);
              }
            }
          }
        })
          .width('100%')
          .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0A0D14')
  }
}
