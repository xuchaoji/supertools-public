export class TargetConstants {
  // 是否有悬浮窗权限
  public static readonly HAS_FLOATING_PERM: boolean = true;

  // 是否AG上架target
  public static readonly IS_AG_TARGET: boolean = false;

  // 本地 Web 服务是否默认自动启动（仅在没有手动设置过时生效；
  // 用户手动开关过本地 Web 服务后，以持久化的手动状态为准）
  public static readonly WEB_SERVER_AUTO_START: boolean = true;

  // HDC 调试能力仅供开发 target 使用。
  public static readonly HDC_DEBUG_ENABLED: boolean = true;
}