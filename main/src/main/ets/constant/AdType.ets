/** Ads Kit 支持的广告形式。数值与华为 Ads Kit adType 定义一致。 */
export enum AdType {
  SPLASH = 1,
  NATIVE = 3,
  REWARD = 7,
  BANNER = 8,
  INTERSTITIAL = 12,
  ROLL = 60
}

/** 华为 Ads Kit 官方测试广告位，仅用于调试，正式发布前请替换。 */
export class AdsKitDefaults {
  public static readonly SPLASH_AD_ID: string = 'g3tl51sqih';
  public static readonly NATIVE_AD_ID: string = 'h8asowxwhq';
  public static readonly REWARD_AD_ID: string = 'j14rx3xtac';
  public static readonly BANNER_AD_ID: string = 'h5xkz3mbr2';
  public static readonly INTERSTITIAL_AD_ID: string = 'p540739a8w';
  public static readonly ROLL_AD_ID: string = 'o2e960bnfz';

  public static getDefaultId(type: AdType): string {
    switch (type) {
      case AdType.SPLASH:
        return AdsKitDefaults.SPLASH_AD_ID;
      case AdType.NATIVE:
        return AdsKitDefaults.NATIVE_AD_ID;
      case AdType.REWARD:
        return AdsKitDefaults.REWARD_AD_ID;
      case AdType.BANNER:
        return AdsKitDefaults.BANNER_AD_ID;
      case AdType.INTERSTITIAL:
        return AdsKitDefaults.INTERSTITIAL_AD_ID;
      case AdType.ROLL:
        return AdsKitDefaults.ROLL_AD_ID;
      default:
        return '';
    }
  }
}

