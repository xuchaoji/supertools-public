import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class BackgroundServiceManager {
  private static readonly NOTIFICATION_ID = 10001;

  // 内部状态标志
  private static isServerRunning: boolean = false;
  private static isRecording: boolean = false;
  private static context: Context | null = null;
  private static currentServiceInfo: string = "";

  /**
   * 初始化上下文
   */
  static init(context: Context) {
    BackgroundServiceManager.context = context;
  }

  // ===================== Web 服务接口 =====================

  static async startWebServer(info: string) {
    BackgroundServiceManager.isServerRunning = true;
    BackgroundServiceManager.currentServiceInfo = info;
    await BackgroundServiceManager.refreshBackgroundState();
  }

  static async stopWebServer() {
    BackgroundServiceManager.isServerRunning = false;
    await BackgroundServiceManager.refreshBackgroundState();
  }

  // ===================== 录音服务接口 =====================

  static async startRecordingTask() {
    BackgroundServiceManager.isRecording = true;
    await BackgroundServiceManager.refreshBackgroundState();
  }

  static async stopRecordingTask() {
    BackgroundServiceManager.isRecording = false;
    await BackgroundServiceManager.refreshBackgroundState();
  }

  // ===================== 核心状态管理逻辑 =====================

  private static async refreshBackgroundState() {
    if (!BackgroundServiceManager.context) {
      console.error("BackgroundServiceManager 未初始化 Context");
      return;
    }

    // 1. 【新增】核心逻辑：检查并申请通知权限
    try {
      // 检查当前开关状态
      const isEnabled = await notificationManager.isNotificationEnabled();

      if (!isEnabled) {
        console.info("检测到通知权限关闭，正在请求用户授权...");
        // 弹窗请求权限。注意：这需要 UIAbilityContext，确保 init() 传入的是 UI 上下文
        await notificationManager.requestEnableNotification(BackgroundServiceManager.context as common.UIAbilityContext);

        // 可选：再次检查，如果用户刚才点了“拒绝”，这里可以决定是否终止服务
        // const reCheck = await notificationManager.isNotificationEnabled();
        // if (!reCheck) { console.warn("用户拒绝了通知权限，长时任务可能无法保活"); }
      }
    } catch (err) {
      let error = err as BusinessError;
      // 捕获错误但不阻断流程，万一系统判断逻辑有变，后续代码仍有机会执行
      console.error(`请求通知权限异常: ${error.code}, ${error.message}`);
    }

    // 1. 如果什么都没跑，取消后台任务并移除通知
    if (!BackgroundServiceManager.isServerRunning && !BackgroundServiceManager.isRecording) {
      try {
        await backgroundTaskManager.stopBackgroundRunning(BackgroundServiceManager.context);
        await notificationManager.cancel(BackgroundServiceManager.NOTIFICATION_ID);
        console.info("所有后台服务已停止");
      } catch (err) {
        console.error(`停止后台任务失败: ${JSON.stringify(err)}`);
      }
      return;
    }

    // 2. 确定优先级：录音 > 数据传输
    let targetMode: backgroundTaskManager.BackgroundMode;
    let notificationTitle: string;
    let notificationText: string;

    if (BackgroundServiceManager.isRecording) {
      targetMode = backgroundTaskManager.BackgroundMode.AUDIO_RECORDING;
      notificationTitle = "超熵实验室：正在录屏";
      notificationText = BackgroundServiceManager.isServerRunning ?
        `录屏服务运行中: ${BackgroundServiceManager.currentServiceInfo}` :
        "正在后台运行录制任务...";
    } else {
      targetMode = backgroundTaskManager.BackgroundMode.DATA_TRANSFER;
      notificationTitle = "超熵实验室：服务运行中";
      notificationText = `本地服务: ${BackgroundServiceManager.currentServiceInfo}`;
    }

    // 3. 执行申请
    try {
      let wantAgentObj = await BackgroundServiceManager.createWantAgent(BackgroundServiceManager.context);

      // 申请/更新模式
      await backgroundTaskManager.startBackgroundRunning(BackgroundServiceManager.context, targetMode, wantAgentObj);

      // 更新通知栏
      await BackgroundServiceManager.publishNotification(notificationTitle, notificationText);

      console.info(`后台模式更新成功: ${BackgroundServiceManager.isRecording ? '录音模式' : '传输模式'}`);

    } catch (err) {
      let error = err as BusinessError;
      console.error(`后台任务申请失败: ${error.code}, ${error.message}`);
    }
  }

  // ===================== 辅助私有方法 =====================

  private static async publishNotification(title: string, text: string) {
    // 再次判空，确保 Strict 模式下类型安全
    if (!BackgroundServiceManager.context) {
      return;
    }

    try {
      let wantAgentObj = await BackgroundServiceManager.createWantAgent(BackgroundServiceManager.context);

      let notificationRequest: notificationManager.NotificationRequest = {
        id: BackgroundServiceManager.NOTIFICATION_ID,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text,
            additionalText: BackgroundServiceManager.isRecording ? "录屏服务" : "数据传输服务"
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
      console.error(`发布通知失败: ${JSON.stringify(err)}`);
    }
  }

  private static async createWantAgent(context: Context): Promise<WantAgent> {
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: context.applicationInfo.name,
        abilityName: "EntryAbility"
      }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return await wantAgent.getWantAgent(wantAgentInfo);
  }
}