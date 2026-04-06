import { HMDefaultGlobalAnimator, HMNavigation } from '@hadss/hmrouter';
import { AttributeUpdater } from '@kit.ArkUI';
import { AppUtil } from '@pura/harmony-utils';
import { PageNames } from '../constant/PageNames';

@Entry
@Component
struct Index {
  @State message: string = 'Hello World';

  modifier: MyNavModifier = new MyNavModifier();

  build() {
    Column() {
      // 使用HMNavigation容器
      HMNavigation({
        navigationId: 'MainNavigation', homePageUrl: PageNames.GUIDE_PAGE,
        options: {
          standardAnimator: HMDefaultGlobalAnimator.STANDARD_ANIMATOR,
          dialogAnimator: HMDefaultGlobalAnimator.DIALOG_ANIMATOR,
          modifier: this.modifier
        }
      })
    }
    .height('100%')
    .width('100%')
    .padding({
      top: `${AppUtil.getStatusBarHeight()}px`
    })
    .backgroundColor($r('sys.color.comp_background_gray'))
  }
}

class MyNavModifier extends AttributeUpdater<NavigationAttribute> {
  initializeModifier(instance: NavigationAttribute): void {
    instance.hideNavBar(true);
  }
}