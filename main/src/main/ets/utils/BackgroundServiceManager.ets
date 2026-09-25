import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * Web 服务与录屏共用的连续后台任务协调器。
 * 这是项目中唯一允许直接调用 start/stopBackgroundRunning 的 owner。
 */
export class BackgroundServiceManager {
  private static readonly NOTIFICATION_ID: number = 10001;

  /** 业务服务状态。 */
  private static isServerRunning: boolean = false;
  private static isRecording: boolean = false;
  private static currentServiceInfo: string = '';

  /** 系统连续任务的真实状态，仅在系统调用成功后更新。 */
  private static taskActive: boolean = false;
  private static currentMode: number = -1;
  private static context: common.UIAbilityContext | null = null;

  /** 串行化 start/stop，避免 Web 与录屏同时切换造成竞态。 */
  private static transitionQueue: Promise<void> = Promise.resolve();

  static init(context: common.UIAbilityContext): void {
    BackgroundServiceManager.context = context;
  }

  static async startWebServer(info: string): Promise<void> {
    BackgroundServiceManager.isServerRunning = true;
    BackgroundServiceManager.currentServiceInfo = info;
    await BackgroundServiceManager.enqueueRefresh();
  }

  static async stopWebServer(): Promise<void> {
    BackgroundServiceManager.isServerRunning = false;
    await BackgroundServiceManager.enqueueRefresh();
  }

  static async startRecordingTask(): Promise<void> {
    BackgroundServiceManager.isRecording = true;
    await BackgroundServiceManager.enqueueRefresh();
  }

  static async stopRecordingTask(): Promise<void> {
    BackgroundServiceManager.isRecording = false;
    await BackgroundServiceManager.enqueueRefresh();
  }

  private static enqueueRefresh(): Promise<void> {
    const operation: Promise<void> = BackgroundServiceManager.transitionQueue.then(async () => {
      await BackgroundServiceManager.refreshBackgroundState();
    });
    // 队列本身始终恢复为 fulfilled，避免一次失败阻塞后续状态切换。
    BackgroundServiceManager.transitionQueue = operation.catch((err: Object) => {
      console.error(`[BackgroundService] 状态切换失败: ${JSON.stringify(err)}`);
    });
    return BackgroundServiceManager.transitionQueue;
  }

  private static getTargetMode(): number {
    if (BackgroundServiceManager.isRecording) {
      return backgroundTaskManager.BackgroundMode.AUDIO_RECORDING;
    }
    if (BackgroundServiceManager.isServerRunning) {
      return backgroundTaskManager.BackgroundMode.DATA_TRANSFER;
    }
    return -1;
  }

  private static async refreshBackgroundState(): Promise<void> {
    const context: common.UIAbilityContext | null = BackgroundServiceManager.context;
    if (!context) {
      throw new Error('BackgroundServiceManager 未初始化 Context');
    }

    const targetMode: number = BackgroundServiceManager.getTargetMode();
    if (targetMode < 0) {
      await BackgroundServiceManager.stopTaskIfActive(context);
      await BackgroundServiceManager.cancelNotification();
      return;
    }

    await BackgroundServiceManager.ensureNotificationPermission(context);

    // 已有任务且模式发生变化：先停止旧模式，再申请新模式。
    if (BackgroundServiceManager.taskActive && BackgroundServiceManager.currentMode !== targetMode) {
      await backgroundTaskManager.stopBackgroundRunning(context);
      BackgroundServiceManager.taskActive = false;
      BackgroundServiceManager.currentMode = -1;
      console.info('[BackgroundService] 已停止旧后台模式，准备切换');
    }

    if (!BackgroundServiceManager.taskActive) {
      const wantAgentObj: WantAgent = await BackgroundServiceManager.createWantAgent(context);
      await backgroundTaskManager.startBackgroundRunning(context,
        targetMode as backgroundTaskManager.BackgroundMode, wantAgentObj);
      BackgroundServiceManager.taskActive = true;
      BackgroundServiceManager.currentMode = targetMode;
      console.info(`[BackgroundService] 后台任务启动成功，mode=${targetMode}`);
    }

    await BackgroundServiceManager.publishNotification();
  }

  private static async stopTaskIfActive(context: common.UIAbilityContext): Promise<void> {
    if (!BackgroundServiceManager.taskActive) {
      console.info('[BackgroundService] 无活动后台任务，跳过停止');
      return;
    }

    await backgroundTaskManager.stopBackgroundRunning(context);
    BackgroundServiceManager.taskActive = false;
    BackgroundServiceManager.currentMode = -1;
    console.info('[BackgroundService] 所有后台服务已停止');
  }

  private static async ensureNotificationPermission(context: common.UIAbilityContext): Promise<void> {
    try {
      const isEnabled: boolean = await notificationManager.isNotificationEnabled();
      if (!isEnabled) {
        console.info('[BackgroundService] 通知权限关闭，申请用户授权');
        await notificationManager.requestEnableNotification(context);
      }
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      // 通知权限异常不应阻止系统连续任务申请，但需要保留诊断信息。
      console.error(`[BackgroundService] 请求通知权限异常: ${error.code}, ${error.message}`);
    }
  }

  private static async cancelNotification(): Promise<void> {
    try {
      await notificationManager.cancel(BackgroundServiceManager.NOTIFICATION_ID);
    } catch (err) {
      console.error(`[BackgroundService] 取消通知失败: ${JSON.stringify(err)}`);
    }
  }

  private static async publishNotification(): Promise<void> {
    const context: common.UIAbilityContext | null = BackgroundServiceManager.context;
    if (!context) {
      return;
    }

    const title: string = BackgroundServiceManager.isRecording ?
      '超熵实验室：正在录屏' : '超熵实验室：服务运行中';
    const text: string = BackgroundServiceManager.isRecording ?
      (BackgroundServiceManager.isServerRunning ?
        `录屏服务运行中: ${BackgroundServiceManager.currentServiceInfo}` : '正在后台运行录制任务...') :
      `本地服务: ${BackgroundServiceManager.currentServiceInfo}`;

    try {
      const wantAgentObj: WantAgent = await BackgroundServiceManager.createWantAgent(context);
      const notificationRequest: notificationManager.NotificationRequest = {
        id: BackgroundServiceManager.NOTIFICATION_ID,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text,
            additionalText: BackgroundServiceManager.isRecording ? '录屏服务' : '数据传输服务'
          }
        },
        isOngoing: true,
        isUnremovable: true,
        tapDismissed: false,
        color: 0xFF0000,
        wantAgent: wantAgentObj
      };
      await notificationManager.publish(notificationRequest);
    } catch (err) {
      console.error(`[BackgroundService] 发布通知失败: ${JSON.stringify(err)}`);
    }
  }

  private static async createWantAgent(context: common.UIAbilityContext): Promise<WantAgent> {
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name
      }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return await wantAgent.getWantAgent(wantAgentInfo);
  }
}
