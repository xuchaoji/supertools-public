import advertising, { AutoAdComponent } from '@hw-ads/ads';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TargetConstants } from 'main/ets/TargetConstants';
import { AdConstants } from '../constant/AdConstants';

const DOMAIN: number = 0x0000;
const TAG: string = 'BannerAdView';

/** 横幅外框总高（vp）= 广告高 57 + 上下各 4 留白 */
const BANNER_BOX_HEIGHT: number = AdConstants.BANNER_HEIGHT + 8;

/**
 * 横幅广告（adType 8）。
 *
 * 使用 Ads Kit 的 AutoAdComponent：组件内部自行加载并轮播展示广告，
 * 只需传入广告请求参数 adParam（横幅广告 adWidth/adHeight 为必填）与展示参数。
 * 渲染在工具箱 Tab 内容底部、悬浮导航栏上方（由 HomePage 预留底部避让空间）。
 *
 * 尺寸约束（重要）：AutoAdComponent 自身不限制尺寸时会撑满父容器，
 * 表现为「横幅占满全屏、工具箱内容被挤掉」。因此这里对 AutoAdComponent 与外层容器
 * 都显式固定宽高（360x57vp + 留白），保证父容器只按该高度分配空间，
 * 剩余空间全部留给工具卡片网格。
 *
 * 备注：未启用广告的产物（TargetConstants.AD_ENABLED=false）不渲染任何内容，
 * 布局与接入广告前完全一致。
 */
@Component
export struct BannerAdView {
  private adParam: advertising.AdRequestParams = {
    adId: AdConstants.AD_ID_BANNER,
    adType: AdConstants.AD_TYPE_BANNER,
    adWidth: AdConstants.BANNER_WIDTH,
    adHeight: AdConstants.BANNER_HEIGHT
  };
  private adOptions: advertising.AdOptions = {};
  private displayOptions: advertising.AdDisplayOptions = {};
  private interactionListener: advertising.AdInteractionListener = {
    onStatusChanged: (status: string, adItem: advertising.Advertisement, data: string): void => {
      hilog.info(DOMAIN, TAG, 'banner status=%{public}s data=%{public}s', status, data);
    }
  };

  build() {
    if (TargetConstants.AD_ENABLED) {
      Column() {
        AutoAdComponent({
          adParam: this.adParam,
          adOptions: this.adOptions,
          displayOptions: this.displayOptions,
          interactionListener: this.interactionListener
        })
          // 必须显式固定尺寸：不限制时组件会撑满父容器（横幅占满全屏的根因）
          .width(AdConstants.BANNER_WIDTH)
          .height(AdConstants.BANNER_HEIGHT)
      }
      .width('100%')
      // 外层同样固定高度，父容器只按「57vp + 留白」为横幅分配空间
      .height(BANNER_BOX_HEIGHT)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      // 兜底：即使广告内部渲染超出固定尺寸，也不覆盖到工具卡片区域
      .clip(true)
      // 实测面积日志：用于确认横幅确实被限制在固定高度内（曾出现横幅撑满全屏的问题）
      .onAreaChange((oldValue: Area, newValue: Area) => {
        hilog.info(DOMAIN, TAG, 'banner area w=%{public}svp h=%{public}svp', `${newValue.width}`, `${newValue.height}`);
      })
      // [Pad大屏适配] 与工具箱网格保持同一最大宽度
      .constraintSize({ maxWidth: 800 })
    }
  }
}
