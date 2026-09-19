import advertising, { AdComponent } from '@hw-ads/ads';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TargetConstants } from 'main/ets/TargetConstants';
import { AdManager } from '../utils/AdManager';

const DOMAIN: number = 0x0000;
const TAG: string = 'NativeAdView';

/**
 * 原生广告（adType 3）。
 *
 * 先由 AdManager 通过 AdLoader 加载原生广告内容，加载成功后用 Ads Kit 的
 * AdComponent 渲染（AdComponent 使用 SDK 内置的原生广告样式）。
 * 展示位置：设置 Tab 页面底部。
 *
 * 加载失败或未填充时不渲染任何内容，不占位、不影响设置项。
 */
@Component
export struct NativeAdView {
  @State ads: Array<advertising.Advertisement> = [];
  private displayOptions: advertising.AdDisplayOptions = {};
  private interactionListener: advertising.AdInteractionListener = {
    onStatusChanged: (status: string, adItem: advertising.Advertisement, data: string): void => {
      hilog.info(DOMAIN, TAG, 'native status=%{public}s data=%{public}s', status, data);
    }
  };

  aboutToAppear(): void {
    if (!TargetConstants.AD_ENABLED) {
      return;
    }
    AdManager.getInstance().loadNativeAd((ads: Array<advertising.Advertisement>) => {
      this.ads = ads;
    });
  }

  build() {
    if (TargetConstants.AD_ENABLED && this.ads.length > 0) {
      Column() {
        AdComponent({
          ads: this.ads,
          displayOptions: this.displayOptions,
          interactionListener: this.interactionListener
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 12 })
      // 实测面积日志：用于确认原生广告的实际渲染高度（原生广告高度由素材决定，不做固定约束）
      .onAreaChange((oldValue: Area, newValue: Area) => {
        hilog.info(DOMAIN, TAG, 'native area w=%{public}svp h=%{public}svp', `${newValue.width}`, `${newValue.height}`);
      })
    }
  }
}
