export class TargetConstants {
  // 是否有悬浮窗权限
  public static readonly HAS_FLOATING_PERM: boolean = false;

  // 是否AG上架target
  public static readonly IS_AG_TARGET: boolean = true;

  // 本地 Web 服务是否默认自动启动（AG 上架版默认不启动，由用户手动开启；
  // 用户手动开关过本地 Web 服务后，以持久化的手动状态为准）
  public static readonly WEB_SERVER_AUTO_START: boolean = false;
}