/**
 * 系统 router 演示页使用的参数模型。
 *
 * router 的 params 只支持可序列化数据，这里用普通类承载，
 * 页面侧统一用 `router.getParams()` 取参、`JSON.stringify` 展示，
 * 避免手写索引访问导致 ArkTS 类型告警。
 */

/** 工具箱入口 -> RouterDemoPage 的入参 */
export class RouterEntryParams {
  /** 入口来源，例如 'pages/Index (HomePage)' */
  from: string = '';
  /** 点击的工具卡片名称 */
  tool: string = '';
  /** 跳转时间戳 */
  ts: number = 0;
}

/** RouterDemoPage -> RouterDemoDetailPage 的入参 */
export class RouterDetailParams {
  /** 模拟的业务单号，验证参数确实随页面传递 */
  orderId: string = '';
  /** 来源页面路径 */
  from: string = '';
  /** 跳转时间戳 */
  ts: number = 0;
}

/** RouterDemoDetailPage -> RouterDemoPage 的 router.back 回传结果 */
export class RouterDetailResult {
  /** 处理结果：ok / cancel */
  result: string = '';
  /** 展示文案 */
  message: string = '';
  /** 回传时间戳 */
  ts: number = 0;
}

/** 模拟启动流程参数：RouterDemoPage -> RouterSplashPage -> RouterMainPage */
export class RouterLaunchParams {
  /** 来源页面路径 */
  from: string = '';
  /** 触发时间戳 */
  ts: number = 0;
  /** 开屏页实际停留秒数（广告展示时长或兜底倒计时） */
  waitedSeconds: number = 0;
  /**
   * 开屏结束方式，便于主页直观看到跳转时机：
   * - `onAdClose:<关闭原因>`：开屏广告关闭回调（正常入口）
   * - `skip`：用户点了「跳过」
   * - `fallback`：没有广告填充，走默认开屏倒计时
   * - `adTimeout`：广告组件长时间没有展示回调的兜底
   */
  closeReason: string = '';
  /** 实际展示的开屏广告位 ID（u7w58nlimb / f068vmywiu；无广告时为空） */
  adSlot: string = '';
}
