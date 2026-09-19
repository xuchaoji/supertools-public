/**
 * 广告常量（鲸鸿动能 Ads Kit，通过 @hw-ads/ads 集成包接入）。
 *
 * 说明：
 * - 当前使用华为官方文档提供的「测试广告位ID」，正式上线前把下面的 adId
 *   替换为 AGC（AppGallery Connect）申请到的真实广告位ID即可，其余代码无需改动。
 * - adType 取值与 Ads Kit 定义一致：1=开屏 3=原生 7=激励 8=横幅 12=插屏。
 */
export class AdConstants {
  // ===== 广告类型 =====
  /** 开屏广告 */
  public static readonly AD_TYPE_SPLASH: number = 1;
  /** 原生广告 */
  public static readonly AD_TYPE_NATIVE: number = 3;
  /** 激励广告 */
  public static readonly AD_TYPE_REWARDED: number = 7;
  /** 横幅广告 */
  public static readonly AD_TYPE_BANNER: number = 8;
  /** 插屏广告 */
  public static readonly AD_TYPE_INTERSTITIAL: number = 12;

  // ===== 广告位ID（官方测试广告位，上线前替换为真实广告位ID）=====
  /** 开屏广告位 */
  public static readonly AD_ID_SPLASH: string = 'f068vmywiu';
  /** 原生广告位 */
  public static readonly AD_ID_NATIVE: string = 'h8asowxwhq';
  /** 激励广告位 */
  public static readonly AD_ID_REWARDED: string = 'j14rx3xtac';
  /** 横幅广告位 */
  public static readonly AD_ID_BANNER: string = 'h5xkz3mbr2';
  /** 插屏广告位 */
  public static readonly AD_ID_INTERSTITIAL: string = 'v1rknehtfa';

  /** 横幅广告请求尺寸（vp，横幅广告 adWidth/adHeight 为必填项） */
  public static readonly BANNER_WIDTH: number = 360;
  public static readonly BANNER_HEIGHT: number = 57;

  /**
   * 开屏广告加载超时（ms）。
   * 冷启动时开屏广告只在加载成功后立即展示：超过该时间仍未加载成功则放弃本次展示，
   * 避免用户已经进入首页操作后才弹出全屏广告。
   */
  public static readonly SPLASH_LOAD_TIMEOUT_MS: number = 5000;

  /**
   * 插屏广告频控：单次运行（进程生命周期）内最多展示次数。
   * <= 0 表示不限制次数（当前配置 0：不限制，每次从工具页返回主页都会展示）。
   */
  public static readonly INTERSTITIAL_MAX_PER_SESSION: number = 0;
  /**
   * 插屏广告频控：两次展示之间的最小间隔（ms）。
   * <= 0 表示不限制间隔（当前配置 0：不限制）。
   */
  public static readonly INTERSTITIAL_MIN_INTERVAL_MS: number = 0;

  /**
   * 开屏广告「广告窗口兜底清理」延时（ms）：
   * 广告打开后超过该时间仍未收到 onAdClose，强制销毁 SDK 遗留的全屏广告窗口。
   * 实测该 SDK 在广告结束后会把全屏窗口留在窗口栈并持有输入焦点（白屏 + 所有点击无响应），
   * 因此必须有此兜底（开屏广告时长通常 5s 左右）。
   */
  public static readonly SPLASH_AD_WINDOW_WATCHDOG_MS: number = 12000;
  /** 插屏/激励等全屏广告的「广告窗口兜底清理」延时（ms）——用户主动关闭的广告，留更长时间 */
  public static readonly FULLSCREEN_AD_WINDOW_WATCHDOG_MS: number = 60000;
}
