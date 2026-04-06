import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

export class BackgroundTaskUtil {
  private static context: common.UIAbilityContext;
  private static isRunning: boolean = false;

  public static init(context: common.UIAbilityContext) {
    BackgroundTaskUtil.context = context;
  }

  /**
   * 开启后台保活 (Web服务 或 录屏 开始时调用)
   */
  public static startBackgroundKeepAlive() {
    if (BackgroundTaskUtil.isRunning) {
      console.info('[BackgroundTask] 服务已在运行中，无需重复申请');
      return;
    }

    if (!BackgroundTaskUtil.context) {
      console.error('[BackgroundTask] Context 未初始化');
      return;
    }

    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: BackgroundTaskUtil.context.abilityInfo.bundleName,
          abilityName: BackgroundTaskUtil.context.abilityInfo.name,
          parameters: {
            "targetPage": "LocalWebPage" // 点击通知跳转回页面
          }
        }
      ],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };

    wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
      // 【关键修复】：强制使用 DATA_TRANSFER
      // 这种模式最稳定，适合“录屏文件写入”和“Web服务器数据传输”
      // 系统不会因为你没用麦克风而杀掉你
      let mode = backgroundTaskManager.BackgroundMode.DATA_TRANSFER;

      backgroundTaskManager.startBackgroundRunning(
        BackgroundTaskUtil.context,
        mode,
        wantAgentObj
      ).then(() => {
        BackgroundTaskUtil.isRunning = true;
        console.info('[BackgroundTask] === 后台保活申请成功 (DATA_TRANSFER) ===');
      }).catch((err: BusinessError) => {
        console.error(`[BackgroundTask] 保活申请失败: Code=${err.code}, Msg=${err.message}`);
        // 可以在这里加一个 Toast 提示用户
      });
    });
  }

  /**
   * 停止后台保活 (只有当 Web服务 和 录屏 都停止时才调用)
   */
  public static stopBackgroundKeepAlive() {
    // 这里需要由外部逻辑判断是否真的要停，或者维护一个计数器
    // 为了简单，我们假设外部调用这个方法时，意味着所有业务都停了
    if (!BackgroundTaskUtil.context) return;

    backgroundTaskManager.stopBackgroundRunning(BackgroundTaskUtil.context).then(() => {
      BackgroundTaskUtil.isRunning = false;
      console.info('[BackgroundTask] === 后台保活已取消 ===');
    }).catch((err: BusinessError) => {
      console.error(`[BackgroundTask] 停止失败: ${err.message}`);
    });
  }
}