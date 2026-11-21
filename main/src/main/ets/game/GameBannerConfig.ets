/** 横幅广告子窗口的配置与状态回调（游戏页 ↔ 子窗口页面）。 */
export class GameBannerConfig {
  public static adId: string = '';
  /** 子窗口页面把广告加载结果回传给游戏页：true=已加载/已展示，false=加载失败。 */
  public static onStatus: (loaded: boolean) => void = (_loaded: boolean): void => {};
}
