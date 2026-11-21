export class PageNames {
  public static readonly GUIDE_PAGE: string = 'guidePage';
  public static readonly PRIVACY_PAGE: string = 'privacyPage';
  public static readonly SPLASH_PAGE: string = 'splashPage';
  public static readonly HOME_PAGE: string = 'HomePage';
  public static readonly SCREEN_RECORD: string = 'ScreenRecordPage';
  public static readonly CALC_PAGE = 'calcPage';
  public static readonly STR_CONVERT = 'stringConvertPage';
  public static readonly LOCAL_WEB_PAGE = 'localWebPage';
  public static readonly DEVICE_INFO_PAGE = 'deviceInfoPage';
  public static readonly APP_LINKING_TOOL = 'appLinkingTool';
  public static readonly H5_PAGE = 'h5Page';
  public static readonly HDC_DEBUG_PAGE = 'hdcDebugPage';
  public static readonly QR_CODE_PAGE = 'qrCodePage';
  public static readonly ADS_KIT_PAGE: string = 'adsKitPage';
  public static readonly ADS_HSP_PAGE: string = 'adsHspPage';
  /** 模拟游戏（原生 GL 渲染的三消），用于游戏广告变现场景测试 */
  public static readonly GAME_DEMO_PAGE: string = 'gameDemoPage';

  // ===================== 系统 router 页面 =====================
  // 与上面的 HMRouter pageUrl 不同：这里必须是真正注册在
  // `resources/base/profile/main_pages.json` 里的页面路径（带 pages/ 前缀），
  // 供 router.pushUrl / router.back 按路径跳转使用。
  public static readonly ROUTER_DEMO_PAGE: string = 'pages/RouterDemoPage';
  public static readonly ROUTER_DEMO_DETAIL_PAGE: string = 'pages/RouterDemoDetailPage';
  /** 模拟应用启动：开屏页（5 秒，后续接入开屏广告） */
  public static readonly ROUTER_SPLASH_PAGE: string = 'pages/RouterSplashPage';
  /** 模拟应用启动：启动完成后的应用主页 */
  public static readonly ROUTER_MAIN_PAGE: string = 'pages/RouterMainPage';
}
