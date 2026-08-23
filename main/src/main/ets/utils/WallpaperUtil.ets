import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { PreferencesUtil } from '@pura/harmony-utils';
import { SpKeys } from '../constant/SpKeys';

/**
 * 主页壁纸管理。
 *
 * 相册选择器（PhotoViewPicker）返回的 uri 属于临时授权，进程重启后即失效，
 * 因此必须把选中的图片复制到应用沙箱持久化，才能作为沉浸光感的常驻背景。
 */
export class WallpaperUtil {
  /** 当前壁纸路径（空字符串表示未设置） */
  static getPath(): string {
    try {
      return PreferencesUtil.getStringSync(SpKeys.WALLPAPER_PATH, '');
    } catch (e) {
      return '';
    }
  }

  /** 壁纸模糊度（0~100，0=不模糊），持久化读取 */
  static getBlur(): number {
    try {
      return PreferencesUtil.getNumberSync(SpKeys.WALLPAPER_BLUR, 0);
    } catch (e) {
      return 0;
    }
  }

  /**
   * 模糊度等级 -> 实际模糊半径（vp）。
   * 等级 0~100 映射到 0~30vp：30vp 为重度模糊（近乎纯色毛玻璃）。
   * 两层壁纸（Index 根级 + HomePage 内容级）必须用同一映射，才能保持无缝衔接。
   */
  static blurRadius(level: number): number {
    return level * 0.3;
  }

  /**
   * 将相册选中的图片复制到应用沙箱并持久化路径。
   *
   * 注意：相册选择器返回的 uri 属于临时授权，进程重启后即失效，
   * 必须真正把图片内容写入沙箱文件（fd 级 open + copyFile），
   * 否则冷启动后壁纸加载失败、界面露出白底。
   *
   * @param context 应用上下文，用于获取 filesDir
   * @param uri 相册选择器返回的图片 uri
   * @returns 持久化后的沙箱路径（复制失败时兜底为原 uri，仅本次进程内有效）
   */
  static async apply(context: common.UIAbilityContext, uri: string): Promise<string> {
    const fileName = `wallpaper_${Date.now()}.jpg`;
    const destPath = `${context.filesDir}/${fileName}`;
    let srcFile: fileIo.File | null = null;
    let destFile: fileIo.File | null = null;
    try {
      // fd 级复制：与 RecordCard 保存录像到相册的已验证写法一致，
      // 比 fileIo.copy(uri, path) 对媒体库 uri 的兼容性更好
      srcFile = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      destFile = await fileIo.open(destPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      await fileIo.copyFile(srcFile.fd, destFile.fd);
      PreferencesUtil.putSync(SpKeys.WALLPAPER_PATH, destPath);
      return destPath;
    } catch (e) {
      // 兜底：个别格式/受限资源无法落盘时，进程存活期间直接引用原 uri
      console.error(`[WallpaperUtil] copy failed, fallback to uri: ${JSON.stringify(e)}`);
      PreferencesUtil.putSync(SpKeys.WALLPAPER_PATH, uri);
      return uri;
    } finally {
      if (srcFile) {
        try {
          fileIo.closeSync(srcFile);
        } catch (e) {
          console.error(`[WallpaperUtil] close src failed: ${JSON.stringify(e)}`);
        }
      }
      if (destFile) {
        try {
          fileIo.closeSync(destFile);
        } catch (e) {
          console.error(`[WallpaperUtil] close dest failed: ${JSON.stringify(e)}`);
        }
      }
    }
  }

  /** 移除壁纸并删除沙箱中的图片文件 */
  static remove(): void {
    const path = WallpaperUtil.getPath();
    if (path !== '' && !path.includes('://')) {
      try {
        fileIo.unlinkSync(path);
      } catch (e) {
        console.error(`[WallpaperUtil] unlink failed: ${JSON.stringify(e)}`);
      }
    }
    try {
      PreferencesUtil.putSync(SpKeys.WALLPAPER_PATH, '');
    } catch (e) {
      console.error(`[WallpaperUtil] clear pref failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 将壁纸解码为 PixelMap（按目标尺寸等比缩放，保持原图比例，避免拉伸；
   * 超出目标的部分由 Image 的 objectFit(Cover) 自动裁切）。
   *
   * 注意：Image 组件直接加载沙箱路径（原始路径或 file:// 前缀）在本环境不可靠，
   * 统一先通过文件描述符解码为 PixelMap 再交给 Image 渲染。
   *
   * @param path 沙箱路径或相册媒体 uri
   * @param width 目标宽度（px）
   * @param height 目标高度（px）
   * @returns 解码后的 PixelMap；失败返回 undefined
   */
  static async loadPixelMap(path: string, width: number, height: number): Promise<image.PixelMap | undefined> {
    let srcFile: fileIo.File | null = null;
    let source: image.ImageSource | undefined = undefined;
    try {
      srcFile = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      source = image.createImageSource(srcFile.fd);
      // 等比缩放：保持原图宽高比，避免 desiredSize 直接拉伸
      const info: image.ImageInfo = await source.getImageInfo();
      const sw = info.size.width;
      const sh = info.size.height;
      const scale = Math.max(width / sw, height / sh);
      const desiredW = Math.round(sw * scale);
      const desiredH = Math.round(sh * scale);
      const pixelMap: image.PixelMap = await source.createPixelMap({
        desiredSize: { width: desiredW, height: desiredH },
        editable: false
      });
      return pixelMap;
    } catch (e) {
      console.error(`[WallpaperUtil] loadPixelMap failed: ${JSON.stringify(e)}`);
      return undefined;
    } finally {
      if (source) {
        try {
          await source.release();
        } catch (e) {
          console.error(`[WallpaperUtil] release source failed: ${JSON.stringify(e)}`);
        }
      }
      if (srcFile) {
        try {
          fileIo.closeSync(srcFile);
        } catch (e) {
          console.error(`[WallpaperUtil] close src failed: ${JSON.stringify(e)}`);
        }
      }
    }
  }

  /**
   * 获取图片原始尺寸（fd 级解码，兼容相册媒体 uri）。
   * @param uri 图片 uri（相册媒体 uri 或沙箱路径）
   * @returns {width, height}；失败返回 undefined
   */
  static async getImageSize(uri: string): Promise<image.Size | undefined> {
    let srcFile: fileIo.File | null = null;
    let source: image.ImageSource | undefined = undefined;
    try {
      srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      source = image.createImageSource(srcFile.fd);
      const info: image.ImageInfo = await source.getImageInfo();
      return info.size;
    } catch (e) {
      console.error(`[WallpaperUtil] getImageSize failed: ${JSON.stringify(e)}`);
      return undefined;
    } finally {
      if (source) {
        try {
          await source.release();
        } catch (e) {
          console.error(`[WallpaperUtil] release source failed: ${JSON.stringify(e)}`);
        }
      }
      if (srcFile) {
        try {
          fileIo.closeSync(srcFile);
        } catch (e) {
          console.error(`[WallpaperUtil] close src failed: ${JSON.stringify(e)}`);
        }
      }
    }
  }

  /**
   * 按用户裁切区域从原图生成壁纸并保存到沙箱。
   * @param context 应用上下文
   * @param uri 原图 uri（相册选择器返回的媒体 uri，临时授权）
   * @param region 裁切区域（原图坐标系）
   * @param size 输出尺寸（与 region 同比例，不拉伸）
   * @returns 沙箱路径；失败返回原 uri 兜底
   */
  static async cropAndSave(context: common.UIAbilityContext, uri: string,
    region: image.Region, size: image.Size): Promise<string> {
    let srcFile: fileIo.File | null = null;
    let source: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      // fd 级解码：与 apply/loadPixelMap 相同的已验证路径，兼容媒体 uri
      srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      source = image.createImageSource(srcFile.fd);
      pixelMap = await source.createPixelMap({
        // 注意：ImageSource.createPixelMap 的裁剪字段是 desiredRegion（DecodingOptions），
        // 不是 region（region 属于像素缓冲版 InitializationOptions）
        desiredRegion: region,
        desiredSize: size,
        editable: false
      });
      const packer = image.createImagePacker();
      const data: ArrayBuffer = await packer.packing(pixelMap, { format: 'image/jpeg', quality: 92 });
      packer.release();
      const fileName = `wallpaper_${Date.now()}.jpg`;
      const destPath = `${context.filesDir}/${fileName}`;
      const file = fileIo.openSync(destPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, data);
      fileIo.closeSync(file);
      // 持久化路径：与 apply() 一致，否则确认后壁纸无法生效、重启后丢失
      PreferencesUtil.putSync(SpKeys.WALLPAPER_PATH, destPath);
      return destPath;
    } catch (e) {
      console.error(`[WallpaperUtil] cropAndSave failed, fallback to uri: ${JSON.stringify(e)}`);
      // 兜底：裁切失败时直接引用原 uri（进程存活期间可用），同样需要持久化
      PreferencesUtil.putSync(SpKeys.WALLPAPER_PATH, uri);
      return uri;
    } finally {
      if (pixelMap) {
        try {
          pixelMap.release();
        } catch (e) {
          console.error(`[WallpaperUtil] release pixelMap failed: ${JSON.stringify(e)}`);
        }
      }
      if (source) {
        try {
          await source.release();
        } catch (e) {
          console.error(`[WallpaperUtil] release source failed: ${JSON.stringify(e)}`);
        }
      }
      if (srcFile) {
        try {
          fileIo.closeSync(srcFile);
        } catch (e) {
          console.error(`[WallpaperUtil] close src failed: ${JSON.stringify(e)}`);
        }
      }
    }
  }
}
