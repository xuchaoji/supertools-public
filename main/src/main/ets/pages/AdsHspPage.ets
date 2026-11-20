import { HMRouter } from '@hadss/hmrouter';
import { common } from '@kit.AbilityKit';
import advertising, { AdComponent, AutoAdComponent } from '@hw-ads/ads';
import { PageNames } from '../constant/PageNames';
import { SpKeys } from '../constant/SpKeys';
import { WallpaperHost } from '../components/WallpaperHost';
import { PageHeader } from '../components/PageHeader';
import { SafeArea } from '../utils/SafeArea';
import { AdsKitPreferences, AdsKitIds } from '../utils/AdsKitPreferences';

@HMRouter({ pageUrl: PageNames.ADS_HSP_PAGE })
@Entry
@ComponentV2
export struct AdsHspPage {
  @Local splashId: string = '';
  @Local nativeId: string = '';
  @Local rewardId: string = '';
  @Local bannerId: string = '';
  @Local interstitialId: string = '';
  @Local rollId: string = '';
  @Local splashAds: advertising.Advertisement[] = [];
  @Local nativeAds: advertising.Advertisement[] = [];
  @Local rewardAds: advertising.Advertisement[] = [];
  @Local interstitialAds: advertising.Advertisement[] = [];
  @Local splashStatus: string = '未加载';
  @Local nativeStatus: string = '未加载';
  @Local rewardStatus: string = '未加载';
  @Local bannerStatus: string = '待加载';
  @Local interstitialStatus: string = '未加载';
  @Local rollStatus: string = '未加载';
  @Local safeBottom: string = '0px';

  aboutToAppear(): void {
    const ids: AdsKitIds = AdsKitPreferences.load();
    this.splashId = ids.splash;
    this.nativeId = ids.native;
    this.rewardId = ids.reward;
    this.bannerId = ids.banner;
    this.interstitialId = ids.interstitial;
    this.rollId = ids.roll;
    this.safeBottom = SafeArea.bottom();
  }

  private context(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private save(key: string, value: string): void {
    const ids: AdsKitIds = {
      splash: this.splashId,
      native: this.nativeId,
      reward: this.rewardId,
      banner: this.bannerId,
      interstitial: this.interstitialId,
      roll: this.rollId
    };
    if (key === SpKeys.AD_SPLASH_ID) ids.splash = value;
    if (key === SpKeys.AD_NATIVE_ID) ids.native = value;
    if (key === SpKeys.AD_REWARD_ID) ids.reward = value;
    if (key === SpKeys.AD_BANNER_ID) ids.banner = value;
    if (key === SpKeys.AD_INTERSTITIAL_ID) ids.interstitial = value;
    if (key === SpKeys.AD_ROLL_ID) ids.roll = value;
    AdsKitPreferences.save(ids);
  }

  private load(type: number, id: string): void {
    if (id.trim().length === 0) return;
    const loader: advertising.AdLoader = new advertising.AdLoader(this.context());
    const listener: advertising.AdLoadListener = {
      onAdLoadFailure: (_code: number, _message: string): void => {
        this.setStatus(type, '加载失败');
      },
      onAdLoadSuccess: (ads: Array<advertising.Advertisement>): void => {
        if (type === 1) this.splashAds = ads;
        if (type === 3) this.nativeAds = ads;
        if (type === 7) this.rewardAds = ads;
        if (type === 12) this.interstitialAds = ads;
        this.setStatus(type, `已加载 ${ads.length} 条`);
        if (type === 1 || type === 7 || type === 12) {
          this.show(ads, type);
        }
      }
    };
    try {
      loader.loadAd({ adId: id.trim(), adType: type, adCount: 1 }, {}, listener);
    } catch (e) {
      this.setStatus(type, '请求异常');
    }
  }

  private setStatus(type: number, status: string): void {
    if (type === 1) this.splashStatus = status;
    else if (type === 3) this.nativeStatus = status;
    else if (type === 7) this.rewardStatus = status;
    else if (type === 8) this.bannerStatus = status;
    else if (type === 12) this.interstitialStatus = status;
    else this.rollStatus = status;
  }

  private show(ads: advertising.Advertisement[], type: number): void {
    if (ads.length === 0) return;
    try {
      advertising.showAd(ads[0], { mute: true }, this.context(), {
        onStatusChanged: (status: string, _ad: advertising.Advertisement, _data: string): void => {
          this.setStatus(type, status);
        }
      });
      this.setStatus(type, '已调用展示');
    } catch (e) {
      this.setStatus(type, '展示失败');
    }
  }

  @Builder
  private field(label: string, value: string, key: string, change: (v: string) => void): void {
    Column({ space: 6 }) {
      Text(label).fontSize(16).fontWeight(FontWeight.Bold);
      TextInput({ text: value, placeholder: '请输入广告位 ID' })
        .width('100%').height(44)
        .onChange((v: string): void => { change(v); this.save(key, v); });
    }.width('100%');
  }

  private statusFor(type: number): string {
    if (type === 1) return this.splashStatus;
    if (type === 3) return this.nativeStatus;
    if (type === 7) return this.rewardStatus;
    if (type === 8) return this.bannerStatus;
    if (type === 12) return this.interstitialStatus;
    return this.rollStatus;
  }

  private currentAds(type: number): advertising.Advertisement[] {
    if (type === 1) return this.splashAds;
    if (type === 3) return this.nativeAds;
    if (type === 7) return this.rewardAds;
    if (type === 12) return this.interstitialAds;
    return [];
  }

  private currentId(type: number): string {
    if (type === 1) return this.splashId;
    if (type === 3) return this.nativeId;
    if (type === 7) return this.rewardId;
    if (type === 8) return this.bannerId;
    if (type === 12) return this.interstitialId;
    return this.rollId;
  }

  @Builder
  private row(type: number): void {
    Row({ space: 8 }) {
      Button('加载').onClick((): void => this.load(type, this.currentId(type))).layoutWeight(1);
      Button('展示').enabled(this.currentAds(type).length > 0)
        .onClick((): void => this.show(this.currentAds(type), type)).layoutWeight(1);
      Text(this.statusFor(type)).fontSize(12).layoutWeight(1);
    }.width('100%');
  }

  @Builder
  private banner(): void {
    if (this.bannerId.trim().length > 0) {
      AutoAdComponent({
        adParam: {
          adId: this.bannerId,
          adType: 8,
          adWidth: 360,
          adHeight: 57
        },
        adOptions: {},
        displayOptions: { mute: true, refreshTime: 30000 },
        interactionListener: {
          onStatusChanged: (status: string, _ad: advertising.Advertisement, _data: string): void => {
            this.bannerStatus = status;
          }
        }
      }).width('100%').height(100);
    }
  }

  build(): void {
    Stack() {
      WallpaperHost() {
        Scroll() {
          Column({ space: 14 }) {
            PageHeader({ title: 'Ads Hsp广告', subtitle: 'HSP 广告接入测试与广告位配置' }).margin({ top: 12 });
            Column({ space: 16 }) {
              this.field('开屏广告', this.splashId, SpKeys.AD_SPLASH_ID, (v: string): void => { this.splashId = v; });
              this.row(1);
              this.field('原生广告', this.nativeId, SpKeys.AD_NATIVE_ID, (v: string): void => { this.nativeId = v; });
              this.row(3);
              if (this.nativeAds.length > 0) {
                AdComponent({
                  ads: [this.nativeAds[0]],
                  displayOptions: { mute: true },
                  interactionListener: {
                    onStatusChanged: (_status: string, _ad: advertising.Advertisement, _data: string): void => {}
                  }
                }).width('100%').height(220);
              }
              this.field('激励广告', this.rewardId, SpKeys.AD_REWARD_ID, (v: string): void => { this.rewardId = v; });
              this.row(7);
              this.field('横幅广告', this.bannerId, SpKeys.AD_BANNER_ID, (v: string): void => { this.bannerId = v; });
              this.banner();
              Text(this.bannerStatus).fontSize(12);
              this.field('插屏广告', this.interstitialId, SpKeys.AD_INTERSTITIAL_ID, (v: string): void => { this.interstitialId = v; });
              this.row(12);
              this.field('贴片广告', this.rollId, SpKeys.AD_ROLL_ID, (v: string): void => { this.rollId = v; });
              this.row(60);
            }.padding(16).backgroundColor('rgba(255,255,255,0.78)').borderRadius(18)
              .margin({ left: 12, right: 12, bottom: this.safeBottom });
          }.width('100%').padding({ bottom: 20 });
        }.scrollBar(BarState.Auto);
      }
    }.width('100%').height('100%');
  }
}

