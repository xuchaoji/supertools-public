export class SpKeys {
  public static readonly PRIVACY_AGREE: string = 'privacy_agree';
  public static readonly ENABLE_SCAN_PARSE: string = 'enable_scan_parse';
  public static readonly ENABLE_HDC_VISIBLE: string = 'enable_hdc_visible';
  public static readonly FLOAT_CLOCK_ON: string = 'float_clock_on';
  public static readonly CPU_STRESS_ON: string = 'cpu_stress_on';
  public static readonly WEB_SERVER_ON: string = 'web_server_on';
  public static readonly AUTO_START_ENABLED: string = 'auto_start_enabled';
  public static readonly TOOL_ORDER: string = 'tool_order';
  public static readonly HDC_DEBUG_LOG: string = 'hdc_debug_log';
  public static readonly WALLPAPER_PATH: string = 'wallpaper_path';
  /** 壁纸模糊度（0~100，0=不模糊） */
  public static readonly WALLPAPER_BLUR: string = 'wallpaper_blur';
  /** 全局光感档位（0=关闭 1=柔和 2=标准 3=精致） */
  public static readonly LIGHT_SENSE: string = 'light_sense';
  /** 二维码生成历史（JSON 数组，[QrHistoryItem]） */
  public static readonly QR_HISTORY: string = 'qr_history';
  /** H5 页面打开历史（JSON 数组，[LinkHistoryItem]） */
  public static readonly H5_HISTORY: string = 'h5_history';
  /** App Linking 解析/拉起历史（JSON 数组，[LinkHistoryItem]） */
  public static readonly APP_LINKING_HISTORY: string = 'app_linking_history';
  /** App Linking 拉起方式：true=openLink（App Linking/深链官方入口），false=startAbility(viewData) */
  public static readonly APP_LINK_LAUNCH_MODE: string = 'app_link_launch_mode';
}