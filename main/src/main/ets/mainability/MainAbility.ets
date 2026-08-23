import {
  AbilityConstant, ConfigurationConstant, UIAbility, Want,
  WantAgent,
  wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { HMRouterMgr } from '@hadss/hmrouter';
import { AppUtil, GlobalContext, PreferencesUtil } from '@pura/harmony-utils';
import { BusinessError } from '@kit.BasicServicesKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BackgroundTaskUtil } from '../utils/BackgroundTaskUtil';
import { FloatWindowUtil } from '../utils/FloatWindowUtil';
import { BackgroundServiceManager } from '../utils/BackgroundServiceManager';
import { GlobalContextHolder } from '../utils/GlobalContextHolder';
import { SpKeys } from '../constant/SpKeys';
import { CommonViewModel } from '../viewmodel/CommonViewModel';
import { FloatClockManager } from '../capabilities/floatingclock/FloatClockManager';
import { StressFloatWindowManager } from '../capabilities/floatingstress/StressWindowManager';
import { WebServerUtil } from '../utils/WebServerUtil';
import { TargetConstants } from 'main/ets/TargetConstants';
import { HdcService } from '../utils/HdcService';

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
    HMRouterMgr.init({ context: this.context })
    this.restoreSavedState();
    this.initHdcServer();
  }

  initHdcServer(): void {
    const hdc = new HdcService();
    try {
      hdc.startServer();
      setTimeout(() => {
        hdc.execCommand("list targets -v").then(r => {
          hilog.info(DOMAIN, TAG, 'HDC cmd exit=%{public}d out=%{public}s', r.exitCode, r.stdout.substring(0, 200));
        });
      }, 3000);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'HDC init failed');
    }
  }

  restoreSavedState(): void {
    const ctx = this.context;
    const TAG = '[StateRestore]';

    if (!PreferencesUtil.getBooleanSync(SpKeys.PRIVACY_AGREE, false)) {
      console.info(`${TAG} privacy not agreed, skip all restore`);
      return;
    }

    if (!PreferencesUtil.getBooleanSync(SpKeys.AUTO_START_ENABLED, true)) {
      console.info(`${TAG} auto-start disabled, using defaults`);
      this.restoreDefaults(TAG);
      return;
    }

    try {
      const clockOn = PreferencesUtil.getBooleanSync(SpKeys.FLOAT_CLOCK_ON, false);
      console.info(`${TAG} reading FLOAT_CLOCK_ON = ${clockOn}`);
      if (clockOn && ctx) {
        CommonViewModel.getInstance().floatingClockOn = true;
        FloatClockManager.show(ctx);
        console.info(`${TAG} float clock restored`);
      } else {
        console.info(`${TAG} float clock skip (on=${clockOn}, ctx=${!!ctx})`);
      }
    } catch (e) {
      console.error(`${TAG} restore float clock failed: ${JSON.stringify(e)}`);
    }

    try {
      const stressOn = PreferencesUtil.getBooleanSync(SpKeys.CPU_STRESS_ON, false);
      console.info(`${TAG} reading CPU_STRESS_ON = ${stressOn}`);
      if (stressOn && ctx) {
        CommonViewModel.getInstance().cpuStressOn = true;
        StressFloatWindowManager.getInstance().show(ctx);
        console.info(`${TAG} cpu stress restored`);
      } else {
        console.info(`${TAG} cpu stress skip (on=${stressOn}, ctx=${!!ctx})`);
      }
    } catch (e) {
      console.error(`${TAG} restore cpu stress failed: ${JSON.stringify(e)}`);
    }

    try {
      const wsOn = PreferencesUtil.getBooleanSync(SpKeys.WEB_SERVER_ON, true);
      console.info(`${TAG} reading WEB_SERVER_ON = ${wsOn}`);
      if (wsOn && ctx) {
        WebServerUtil.getInstance().init(ctx.filesDir + '/wwwroot', 8088);
        WebServerUtil.getInstance().start().then(() => {
          const ip = WebServerUtil.getInstance().getIpAddress();
          if (TargetConstants.HAS_FLOATING_PERM) {
            FloatWindowUtil.showFloatWindow();
          }
          console.info(`${TAG} web server restored`);
        }).catch((err: Object) => {
          console.error(`${TAG} web server start failed: ${JSON.stringify(err)}`);
        });
      } else {
        console.info(`${TAG} web server skip (on=${wsOn}, ctx=${!!ctx})`);
      }
    } catch (e) {
      console.error(`${TAG} restore web server failed: ${JSON.stringify(e)}`);
    }
  }

  restoreDefaults(TAG: string): void {
    try {
      WebServerUtil.getInstance().init(this.context.filesDir + '/wwwroot', 8088);
      WebServerUtil.getInstance().start().then(() => {
        if (TargetConstants.HAS_FLOATING_PERM) {
          FloatWindowUtil.showFloatWindow();
        }
        console.info(`${TAG} web server started (default)`);
      }).catch((err: Object) => {
        console.error(`${TAG} web server default start failed: ${JSON.stringify(err)}`);
      });
    } catch (e) {
      console.error(`${TAG} restoreDefaults failed: ${JSON.stringify(e)}`);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    const loadPage = (): void => {
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
          return;
        }
        hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      });
    };

    // 必须先让全屏布局真正生效，再加载页面：
    // setWindowLayoutFullScreen 是异步的，若页面在标志生效前完成首次布局，
    // expandSafeArea 等安全区延伸在冷启动时不会覆盖状态栏（状态栏露出灰白背景）。
    // 因此把 loadContent 放到全屏 Promise 成功回调中执行。
    try {
      windowStage.getMainWindowSync().setWindowLayoutFullScreen(true).then(() => {
        loadPage();
      }).catch((e: Object) => {
        hilog.error(DOMAIN, 'testTag', 'setWindowLayoutFullScreen failed: %{public}s', JSON.stringify(e));
        loadPage();
      });
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'getMainWindowSync failed: %{public}s', JSON.stringify(e));
      loadPage();
    }
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