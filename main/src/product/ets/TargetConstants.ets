export class TargetConstants {
  // 是否有悬浮窗权限
  public static readonly HAS_FLOATING_PERM: boolean = false;

  // 是否AG上架target
  public static readonly IS_AG_TARGET: boolean = true;

  // 本地 Web 服务是否默认自动启动（AG 上架版默认不启动，由用户手动开启；
  // 用户手动开关过本地 Web 服务后，以持久化的手动状态为准）
  public static readonly WEB_SERVER_AUTO_START: boolean = false;

  // HDC 调试能力开关（显式总闸，默认开启）。
  // AG 上架版并**不**靠这个常量隐藏入口：HomePage 里仍然沿用原有规则——
  // 入口默认隐藏，需要通过「设置页连点彩蛋」写入 ENABLE_HDC_VISIBLE 后显示。
  // 只有确实要在某个 target 上彻底移除该能力时，才把它改成 false。
  public static readonly HDC_DEBUG_ENABLED: boolean = true;
}