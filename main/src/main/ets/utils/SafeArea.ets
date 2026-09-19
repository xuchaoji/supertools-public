import { AppUtil } from '@pura/harmony-utils';

/**
 * 沉浸式全屏下的安全区避让。
 *
 * `MainAbility` 调用 `setWindowLayoutFullScreen(true)` 让页面铺满整屏，
 * 页面内容会延伸到状态栏与底部系统手势条（导航条）下方，必须显式避让：
 *
 * - **顶部状态栏**：已由 `Index.ets` 根级 HMNavigation 容器统一避让
 *   （`padding({ top: getStatusBarHeight() })`）。页面自身**不要**再加，
 *   否则整页会下移一个状态栏高度（本机实测 108px）。
 * - **底部手势条**：`Index` 不处理，由各页面自行避让，用 `SafeArea.bottom()`。
 *
 * 返回值是 px 字符串，可直接用于 padding —— ArkUI 的数值型 Length 默认单位是 vp，
 * 而 `AppUtil` 返回的是 px，必须带上单位，否则会差 3 倍。
 */
export class SafeArea {
  /**
   * 底部系统手势条（导航条）占用区域的高度，形如 `"84px"`。
   * 设备没有手势条时返回 `"0px"`，即不额外避让。
   */
  static bottom(): string {
    return `${AppUtil.getNavigationIndicatorHeight()}px`;
  }
}
