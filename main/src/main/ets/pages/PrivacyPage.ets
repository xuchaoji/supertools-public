import web_webview from '@ohos.web.webview';
import { CommonViewModel } from '../viewmodel/CommonViewModel';
import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import { PageNames } from '../constant/PageNames';
import { PreferencesUtil } from '@pura/harmony-utils';
import { SpKeys } from '../constant/SpKeys';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { WebServerUtil } from '../utils/WebServerUtil';
import { FloatWindowUtil } from '../utils/FloatWindowUtil';
import { BackgroundServiceManager } from '../utils/BackgroundServiceManager';
import { GlobalContextHolder } from '../utils/GlobalContextHolder';
import { TargetConstants } from 'main/ets/TargetConstants';
import { SafeArea } from '../utils/SafeArea';
import { GlassButton } from '../components/GlassButton';

const TAG: string = 'PrivacyPage';

@HMRouter({pageUrl: PageNames.PRIVACY_PAGE})
@ComponentV2
export struct PrivacyPage {
  private webController: web_webview.WebviewController = new web_webview.WebviewController();

  @Local viewModel: CommonViewModel = CommonViewModel.getInstance();
  // 状态管理
  @Local isLoading: boolean = true;
  @Local safeBottom: string = '0px';

  @Local isControllerAttached:boolean = false;

  @Monitor('isControllerAttached')
  onControllerAttached() {
    if (this.isControllerAttached) {
      this.webController.loadUrl('https://echo.xuchaoji.com/supertools-privacy.html');
    }
  }

  aboutToAppear() {
    this.safeBottom = SafeArea.bottom();
  }

  // 保存用户选择
  private saveUserAgreement(agreed: boolean) {
    try {
      PreferencesUtil.put(SpKeys.PRIVACY_AGREE, agreed)
      if (agreed) {
        this.startDefaultServices();
      }
    } catch (err) {
      console.error('保存用户选择失败:', JSON.stringify(err));
    }
  }

  private startDefaultServices() {
    // AG 上架版默认不自动启动本地 Web 服务（由用户在「本地web服务」页手动开启），
    // dev 版仍保持同意隐私后自动启动
    if (!TargetConstants.WEB_SERVER_AUTO_START) {
      console.info('[PrivacyPage] web server auto-start disabled for this target, skip');
      return;
    }
    try {
      const ctx = GlobalContextHolder.getInstance().uiAbilityContext;
      if (!ctx) {
        console.error('[PrivacyPage] context unavailable, skip default services');
        return;
      }
      WebServerUtil.getInstance().init(ctx.filesDir + '/wwwroot', 8088);
      WebServerUtil.getInstance().start().then(() => {
        const ip: string = WebServerUtil.getInstance().getIpAddress();
        if (TargetConstants.HAS_FLOATING_PERM) {
          FloatWindowUtil.showFloatWindow();
        }
        BackgroundServiceManager.startWebServer(ip);
        console.info('[PrivacyPage] web server started on privacy agreed');
      }).catch((err: Object) => {
        console.error('[PrivacyPage] web server start failed:', JSON.stringify(err));
      });
    } catch (e) {
      console.error('[PrivacyPage] startDefaultServices failed:', JSON.stringify(e));
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('隐私政策')
          .fontSize(20)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .height(60)
      .padding(10)
      .backgroundColor('#007DFF')
      .justifyContent(FlexAlign.Center)

      // WebView内容区域
      Stack() {
        Web({
          src: 'https://echo.xuchaoji.com/supertools-privacy.html',
          controller: this.webController
        })
          .onControllerAttached(() => {
            this.isControllerAttached = true;
          })
          .onProgressChange((event) => {
            CommonViewModel.getInstance().privacyLoadingProgress = event.newProgress;
          })
          .onPageEnd((event) => {
            this.isLoading = false;
          })
          .onLoadIntercept((event) => {
            console.log(TAG, 'url:' + event.data.getRequestUrl());
            console.log(TAG, 'isMainFrame:' + event.data.isMainFrame());
            console.log(TAG, 'isRedirect:' + event.data.isRedirect());
            console.log(TAG, 'isRequestGesture:' + event.data.isRequestGesture());
            if (event.data.getRequestUrl().startsWith('mailto:')) {
              console.log(TAG, `main to, skip loading`)
              this.handleMailto(event.data.getRequestUrl())
              return true;
            }
            return false;
          })
          .onErrorReceive((event) => {
            this.isLoading = false;
            console.error('WebView加载错误:', event);
          })
          .width('100%')
          .height('100%')
          .margin(10)

        // 加载指示器
        if (this.isLoading) {
          Progress({
            value: this.viewModel.privacyLoadingProgress,
            style: ProgressStyle.Ring
          })
            .width(60)
            .height(60)
            .color(Color.Blue)
            .position({ x: '50%', y: '50%' })
            .align(Alignment.Center)
        }
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1) // 占据剩余空间

      // 底部按钮区域
      Row() {
        GlassButton({
          label: '拒绝',
          fillWidth: true,
          bgColor: '#F0F0F0',
          textColor: '#333333',
          strokeWidth: 0,
          blurRadius: 0,
          btnHeight: 50,
          radius: 25,
          fontSize: 16,
          onAction: () => {
            this.saveUserAgreement(false);
            // 关闭当前页面（退出应用）
            HMRouterMgr.pop()
          }
        })
          .width('40%')

        GlassButton({
          label: '同意',
          fillWidth: true,
          bgColor: '#007DFF',
          textColor: Color.White,
          strokeWidth: 0,
          blurRadius: 0,
          btnHeight: 50,
          radius: 25,
          fontSize: 16,
          fontWeight: FontWeight.Medium,
          onAction: () => {
            this.saveUserAgreement(true);
            // 跳转到主页面
            HMRouterMgr.replace({
              pageUrl: PageNames.HOME_PAGE
            })
          }
        })
          .width('40%')
          .margin({ left: 20 })
      }
      .width('100%')
      .padding(20)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
    // 底部「拒绝/同意」按钮贴屏底，需避让系统手势条
    .padding({ bottom: this.safeBottom })
  }

  private handleMailto(url: string) {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      context.startAbility({
        action: 'ohos.want.action.sendToData', // 鸿蒙邮件协议专属 Action
        uri: url // 示例：mailto:admin@xuchaoji.com?subject=咨询
      });
    } catch (error) {
      console.error("拉起邮件应用失败", error);
      promptAction.showToast({ message: "未找到邮件应用，请安装后重试" });
    }
  }
}