import web_webview from '@ohos.web.webview';
import { CommonViewModel } from '../viewmodel/CommonViewModel';
import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import { PageNames } from '../constant/PageNames';
import { PreferencesUtil } from '@pura/harmony-utils';
import { SpKeys } from '../constant/SpKeys';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

const TAG: string = 'PrivacyPage';

@HMRouter({pageUrl: PageNames.PRIVACY_PAGE})
@ComponentV2
export struct PrivacyPage {
  private webController: web_webview.WebviewController = new web_webview.WebviewController();

  @Local viewModel: CommonViewModel = CommonViewModel.getInstance();
  // 状态管理
  @Local isLoading: boolean = true;

  @Local isControllerAttached:boolean = false;

  @Monitor('isControllerAttached')
  onControllerAttached() {
    if (this.isControllerAttached) {
      this.webController.loadUrl('https://echo.xuchaoji.com/supertools-privacy.html');
    }
  }

  aboutToAppear() {
  }

  // 保存用户选择
  private saveUserAgreement(agreed: boolean) {
    try {
      PreferencesUtil.put(SpKeys.PRIVACY_AGREE, agreed)
    } catch (err) {
      console.error('保存用户选择失败:', JSON.stringify(err));
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
        Button('拒绝', { type: ButtonType.Normal })
          .width('40%')
          .height(50)
          .backgroundColor('#F0F0F0')
          .fontColor('#333333')
          .borderRadius(25)
          .onClick(() => {
            this.saveUserAgreement(false);
            // 关闭当前页面（退出应用）
            HMRouterMgr.pop()
          })

        Button('同意', { type: ButtonType.Capsule })
          .width('40%')
          .height(50)
          .backgroundColor('#007DFF')
          .fontColor(Color.White)
          .margin({ left: 20 })
          .onClick(() => {
            this.saveUserAgreement(true);
            // 跳转到主页面
            HMRouterMgr.replace({
              pageUrl: PageNames.HOME_PAGE
            })
          })
      }
      .width('100%')
      .padding(20)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
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