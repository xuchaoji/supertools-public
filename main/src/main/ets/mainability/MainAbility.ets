import {
  AbilityConstant, ConfigurationConstant, UIAbility, Want,
  WantAgent,
  wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { HMRouterMgr } from '@hadss/hmrouter';
import { AppUtil, GlobalContext } from '@pura/harmony-utils';
import { BusinessError } from '@kit.BasicServicesKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BackgroundTaskUtil } from '../utils/BackgroundTaskUtil';
import { FloatWindowUtil } from '../utils/FloatWindowUtil';
import { BackgroundServiceManager } from '../utils/BackgroundServiceManager';
import { GlobalContextHolder } from '../utils/GlobalContextHolder';

const DOMAIN = 0x0000;

const TAG: string = 'MainAbility';

export default class MainAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    AppUtil.init(this.context);
    BackgroundTaskUtil.init(this.context);
    BackgroundServiceManager.init(this.context);
    FloatWindowUtil.init(this.context);
    GlobalContextHolder.getInstance().uiAbilityContext = this.context;
    HMRouterMgr.openLog("INFO")
    HMRouterMgr.init({
      context: this.context
    })
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    windowStage.getMainWindow((err: BusinessError, data) => {
      let windowClass = data;
      windowClass.setWindowLayoutFullScreen(true);
    })
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    this.stopContinuousTask();
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    // this.startContinuousTask() 切换到BackgroundServiceManager
  }

  startContinuousTask() {
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: "com.xuchaoji.hmos.supertools",
          abilityName: "MainAbility"
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };

    wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
      backgroundTaskManager.startBackgroundRunning(this.context,
        backgroundTaskManager.BackgroundMode.AUDIO_RECORDING, wantAgentObj).then(() => {
        hilog.info(DOMAIN, 'testTag', 'Succeeded in operation startBackgroundRunning.');
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to operation startBackgroundRunning. %{public}s', JSON.stringify(err));
      });
    });
  }

  stopContinuousTask() {
    backgroundTaskManager.stopBackgroundRunning(this.context).then(() => {
      hilog.info(DOMAIN, 'testTag', 'Succeeded in operation stopBackgroundRunning.');
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, 'testTag', 'Failed to operation stopBackgroundRunning. %{public}s', JSON.stringify(err));
    });
  }
}