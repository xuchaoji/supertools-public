import { PreferencesUtil } from '@pura/harmony-utils';
import { JSON } from '@kit.ArkTS';
import { AdType, AdsKitDefaults } from '../constant/AdType';
import { SpKeys } from '../constant/SpKeys';

/** 六类 Ads Kit 广告位 ID 的持久化数据。 */
export interface AdsKitIds {
  splash: string;
  native: string;
  reward: string;
  banner: string;
  interstitial: string;
  roll: string;
}

/** Ads Kit 广告位 ID 的默认值、读取及同步写入辅助。 */
export class AdsKitPreferences {
  /** 读取已保存的 ID；未保存或空值自动回退至官方测试 ID。 */
  public static load(): AdsKitIds {
    const ids: AdsKitIds = AdsKitPreferences.defaultIds();
    ids.splash = AdsKitPreferences.read(SpKeys.AD_SPLASH_ID, ids.splash);
    ids.native = AdsKitPreferences.read(SpKeys.AD_NATIVE_ID, ids.native);
    ids.reward = AdsKitPreferences.read(SpKeys.AD_REWARD_ID, ids.reward);
    ids.banner = AdsKitPreferences.read(SpKeys.AD_BANNER_ID, ids.banner);
    ids.interstitial = AdsKitPreferences.read(SpKeys.AD_INTERSTITIAL_ID, ids.interstitial);
    ids.roll = AdsKitPreferences.read(SpKeys.AD_ROLL_ID, ids.roll);

    // JSON 键可用于旧版本/导入数据；仅在对应单项尚未覆盖时读取。
    const jsonIds: AdsKitIds | null = AdsKitPreferences.readJson();
    if (jsonIds !== null) {
      if (!PreferencesUtil.getStringSync(SpKeys.AD_SPLASH_ID, '')) ids.splash = AdsKitPreferences.nonEmpty(jsonIds.splash, ids.splash);
      if (!PreferencesUtil.getStringSync(SpKeys.AD_NATIVE_ID, '')) ids.native = AdsKitPreferences.nonEmpty(jsonIds.native, ids.native);
      if (!PreferencesUtil.getStringSync(SpKeys.AD_REWARD_ID, '')) ids.reward = AdsKitPreferences.nonEmpty(jsonIds.reward, ids.reward);
      if (!PreferencesUtil.getStringSync(SpKeys.AD_BANNER_ID, '')) ids.banner = AdsKitPreferences.nonEmpty(jsonIds.banner, ids.banner);
      if (!PreferencesUtil.getStringSync(SpKeys.AD_INTERSTITIAL_ID, '')) ids.interstitial = AdsKitPreferences.nonEmpty(jsonIds.interstitial, ids.interstitial);
      if (!PreferencesUtil.getStringSync(SpKeys.AD_ROLL_ID, '')) ids.roll = AdsKitPreferences.nonEmpty(jsonIds.roll, ids.roll);
    }
    return ids;
  }

  /** 同步写入六个独立键，并写入 JSON 快照，供导入/迁移使用。 */
  public static save(ids: AdsKitIds): void {
    PreferencesUtil.putSync(SpKeys.AD_SPLASH_ID, ids.splash.trim());
    PreferencesUtil.putSync(SpKeys.AD_NATIVE_ID, ids.native.trim());
    PreferencesUtil.putSync(SpKeys.AD_REWARD_ID, ids.reward.trim());
    PreferencesUtil.putSync(SpKeys.AD_BANNER_ID, ids.banner.trim());
    PreferencesUtil.putSync(SpKeys.AD_INTERSTITIAL_ID, ids.interstitial.trim());
    PreferencesUtil.putSync(SpKeys.AD_ROLL_ID, ids.roll.trim());
    PreferencesUtil.putSync(SpKeys.ADS_KIT_IDS_JSON, JSON.stringify(ids));
  }

  /** 按广告类型读取单个广告位 ID。 */
  public static getId(type: AdType): string {
    const ids: AdsKitIds = AdsKitPreferences.load();
    switch (type) {
      case AdType.SPLASH: return ids.splash;
      case AdType.NATIVE: return ids.native;
      case AdType.REWARD: return ids.reward;
      case AdType.BANNER: return ids.banner;
      case AdType.INTERSTITIAL: return ids.interstitial;
      case AdType.ROLL: return ids.roll;
      default: return '';
    }
  }

  private static defaultIds(): AdsKitIds {
    return {
      splash: AdsKitDefaults.SPLASH_AD_ID,
      native: AdsKitDefaults.NATIVE_AD_ID,
      reward: AdsKitDefaults.REWARD_AD_ID,
      banner: AdsKitDefaults.BANNER_AD_ID,
      interstitial: AdsKitDefaults.INTERSTITIAL_AD_ID,
      roll: AdsKitDefaults.ROLL_AD_ID
    };
  }

  private static read(key: string, fallback: string): string {
    return AdsKitPreferences.nonEmpty(PreferencesUtil.getStringSync(key, ''), fallback);
  }

  private static nonEmpty(value: string, fallback: string): string {
    const normalized: string = value.trim();
    return normalized.length > 0 ? normalized : fallback;
  }

  private static readJson(): AdsKitIds | null {
    try {
      const raw: string = PreferencesUtil.getStringSync(SpKeys.ADS_KIT_IDS_JSON, '');
      if (raw.length === 0) return null;
      const parsed: AdsKitIds = JSON.parse(raw) as AdsKitIds;
      return parsed;
    } catch (error) {
      return null;
    }
  }
}
