import { image } from '@kit.ImageKit';
import { display } from '@kit.ArkUI';
import { AppUtil } from '@pura/harmony-utils';
import { WallpaperUtil } from '../utils/WallpaperUtil';

/**
 * 全局壁纸宿主：把主页壁纸渲染到任意页面内容之下，让工具箱等子页面
 * 也拥有与主页一致的沉浸光感背景（含模糊度、状态栏无缝衔接）。
 *
 * 用法：页面 build() 根节点替换为
 *   WallpaperHost() { <原页面内容> }
 * 并把原页面根容器的 backgroundColor 改为 Color.Transparent。
 *
 * 通过 @StorageProp 监听壁纸路径/模糊度变化（HomePage 设置时同步），
 * 与 Index 根级壁纸使用同一全屏几何 + 同一模糊映射，保证无缝衔接。
 */
@Component
export struct WallpaperHost {
  /** 页面内容（渲染在壁纸之上） */
  @BuilderParam content: () => void;
  @StorageProp('WallpaperPath') @Watch('onWallpaperChanged') wallpaperPath: string = '';
  @StorageProp('WallpaperBlur') wallpaperBlur: number = 0;
  @State wallpaperPm: image.PixelMap | undefined = undefined;
  /** 壁纸层高度（px，= 全屏高，与 Index 根级一致） */
  @State layerH: number = 2880;
  /** 壁纸层向上偏移（px，= 状态栏高，使 pm 原点与屏幕原点对齐） */
  @State layerY: number = 0;

  aboutToAppear(): void {
    this.loadWallpaper();
  }

  /** 壁纸路径/模糊度变化：重新解码（路径变化时） */
  onWallpaperChanged(): void {
    this.loadWallpaper();
  }

  private loadWallpaper(): void {
    const path = this.wallpaperPath;
    if (path === '') {
      this.wallpaperPm = undefined;
      return;
    }
    let w = 1084;
    let h = 2412;
    try {
      const d = display.getDefaultDisplaySync();
      w = d.width;
      h = d.height;
    } catch (e) {
      // 使用默认尺寸
    }
    this.layerH = h;
    this.layerY = AppUtil.getStatusBarHeight();
    WallpaperUtil.loadPixelMap(path, w, h).then((pm: image.PixelMap | undefined) => {
      // 路径可能已变化，丢弃过期解码结果
      if (this.wallpaperPath === path) {
        this.wallpaperPm = pm;
      }
    });
  }

  build() {
    Stack() {
      // 壁纸层：与 Index 根级相同的全屏几何（高度=全屏高，向上偏移=状态栏高），
      // 两层渲染同一画面、无缝衔接；模糊半径与根级同一映射
      if (this.wallpaperPm) {
        Image(this.wallpaperPm)
          .width('100%')
          .height(`${this.layerH}px`)
          .position({ y: `-${this.layerY}px` })
          .objectFit(ImageFit.Cover)
          .blur(WallpaperUtil.blurRadius(this.wallpaperBlur))
      }

      // 页面内容
      this.content()
    }
    .width('100%')
    .height('100%')
  }
}
