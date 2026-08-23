import { HMDefaultGlobalAnimator, HMNavigation } from '@hadss/hmrouter';
import { AttributeUpdater, display } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppUtil } from '@pura/harmony-utils';
import { PageNames } from '../constant/PageNames';
import { WallpaperUtil } from '../utils/WallpaperUtil';

@Entry
@Component
struct Index {
  @State message: string = 'Hello World';
  // 主页壁纸（沉浸光感背景）：通过 AppStorage 与设置页同步。
  // 壁纸解码为 PixelMap 后在根级全屏渲染，天然覆盖状态栏区域，
  // 冷启动也稳定生效（不依赖 Image 的沙箱路径解析，也不依赖安全区延伸）。
  @StorageProp('WallpaperPath') @Watch('reloadWallpaper') wallpaperPath: string = '';
  // 壁纸模糊度（0~100）：与 HomePage 设置页通过 AppStorage 同步，根级壁纸层应用相同模糊
  @StorageProp('WallpaperBlur') wallpaperBlur: number = 0;
  @State wallpaperPm: image.PixelMap | undefined = undefined;

  modifier: MyNavModifier = new MyNavModifier();

  aboutToAppear(): void {
    // 直接用持久化路径初始化 AppStorage：
    // 注意不能用 AppStorage.get() === undefined 判断——@StorageProp 创建时
    // 已把该键注册为默认值 ''，undefined 判断永远不成立，导致壁纸路径丢失
    AppStorage.setOrCreate<string>('WallpaperPath', WallpaperUtil.getPath());
    AppStorage.setOrCreate<number>('WallpaperBlur', WallpaperUtil.getBlur());
    this.reloadWallpaper();
  }

  /** 壁纸路径变化时重新解码 PixelMap（直接读持久化路径，避免 @StorageProp 异步时序） */
  reloadWallpaper(): void {
    const path: string = WallpaperUtil.getPath();
    hilog.info(0x0000, 'IndexWallpaper', 'reloadWallpaper path=%{public}s pm=%{public}s',
      path, this.wallpaperPm ? 'set' : 'none');
    if (path === '') {
      this.wallpaperPm = undefined;
      return;
    }
    let w = 1308;
    let h = 2880;
    try {
      const d = display.getDefaultDisplaySync();
      w = d.width;
      h = d.height;
    } catch (e) {
      // 使用默认尺寸
    }
    WallpaperUtil.loadPixelMap(path, w, h).then((pm: image.PixelMap | undefined) => {
      hilog.info(0x0000, 'IndexWallpaper', 'loadPixelMap done pm=%{public}s', pm ? 'set' : 'undefined');
      this.wallpaperPm = pm;
    });
  }

  build() {
    Stack() {
      // 壁纸层：全屏铺满（含状态栏区域），模糊半径与 HomePage 内容层一致
      if (this.wallpaperPm) {
        Image(this.wallpaperPm)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(WallpaperUtil.blurRadius(this.wallpaperBlur))
      }

      // 内容层：从状态栏下方开始；有壁纸时透明让壁纸透出，无壁纸时保持原灰底
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
      .backgroundColor(this.wallpaperPm ? Color.Transparent : $r('sys.color.comp_background_gray'))
    }
    .width('100%')
    .height('100%')
  }
}

class MyNavModifier extends AttributeUpdater<NavigationAttribute> {
  initializeModifier(instance: NavigationAttribute): void {
    instance.hideNavBar(true);
    // 导航容器透明，避免 NavDestination 的白底遮挡 Index 根级的沉浸光感壁纸
    instance.backgroundColor(Color.Transparent);
  }
}
