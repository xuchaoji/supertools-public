import { HMRouterMgr } from '@hadss/hmrouter';
import { mediaquery } from '@kit.ArkUI';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';

/**
 * 子页面统一标题栏 —— 全项目**唯一**的页面头部实现。
 *
 * 组成：玻璃圆底返回按钮（38×38）+ 主标题（22 加粗）+ 副标题（12 次要色）。
 * 文字统一带「与文字相反色」的可读性阴影，保证在壁纸/玻璃背景下深浅色模式都能看清。
 *
 * 为什么必须有返回按钮：`Index.ets` 的导航容器设了 `hideNavBar(true)`，
 * 系统不提供标题栏与返回键，页面自己不加就只能靠手势返回。
 *
 * 用法：
 *   PageHeader({ title: '字符串转换', subtitle: 'Base64、URL 编解码' })
 *   // 需要自定义返回行为时：
 *   PageHeader({ title: 'H5 查看', onBack: () => { this.backToInput() } })
 */
@ComponentV2
export struct PageHeader {
  /** 主标题 */
  @Param title: string = '';
  /** 副标题（留空则不占位） */
  @Param subtitle: string = '';
  /** 是否显示返回按钮 */
  @Param showBack: boolean = true;
  /** 返回回调，默认 HMRouterMgr.pop() */
  @Event onBack: () => void = () => {
    HMRouterMgr.pop();
  };
  @Local isDark: boolean = false;
  private themeMq: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    try {
      this.themeMq = this.getUIContext().getMediaQuery().matchMediaSync('(display-mode: dark)');
      this.isDark = this.themeMq.matches;
      this.themeMq.on('change', (event: mediaquery.MediaQueryResult) => {
        this.isDark = event.matches;
      });
    } catch (e) {
      this.isDark = false;
    }
  }

  aboutToDisappear(): void {
    this.themeMq?.off('change');
    this.themeMq = null;
  }

  build() {
    Row() {
      if (this.showBack) {
        Stack() {
          Image($r('app.media.back_arrow'))
            .width(20)
            .height(20)
            .objectFit(ImageFit.Contain)
            .fillColor($r('sys.color.font_primary'))
        }
        .width(38)
        .height(38)
        .borderRadius(19)
        // 返回按钮玻璃圆底：任意壁纸背景下都清晰可见
        .backgroundColor(this.isDark ? 'rgba(255, 255, 255, 0.16)' : 'rgba(255, 255, 255, 0.9)')
        .border({ width: 1, color: ImmersiveStyles.cardOuterRim(this.isDark) })
        .shadow({ radius: 8, color: ImmersiveStyles.cardShadow(this.isDark), offsetX: 0, offsetY: 2 })
        .onClick(() => {
          this.onBack();
        })
      }

      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_emphasize'))
          // 深色/浅色模式可读性：阴影颜色与文字相反
          .textShadow(ImmersiveStyles.textShadow(this.isDark))
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .textShadow(ImmersiveStyles.textShadow(this.isDark))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: this.showBack ? 12 : 0 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
