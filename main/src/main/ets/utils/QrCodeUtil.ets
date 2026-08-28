import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

const TAG: string = 'QrCodeUtil';

/**
 * 二维码工具：把生成的二维码 PixelMap 编码为 PNG 文件（应用缓存目录），
 * 供「保存到相册」弹窗使用。
 */
export class QrCodeUtil {
  /**
   * 将 PixelMap 打包为 PNG 并写入应用缓存目录。
   * @param context UIAbility 上下文（取 cacheDir）
   * @param pm 待保存的二维码 PixelMap
   * @returns PNG 文件路径（沙箱路径，不带 file:// 前缀）
   */
  static async savePngToCache(context: common.UIAbilityContext, pm: image.PixelMap): Promise<string> {
    const packer: image.ImagePacker = image.createImagePacker();
    try {
      const buf: ArrayBuffer = await packer.packing(pm, { format: 'image/png', quality: 100 });
      const path: string = `${context.cacheDir}/qr_${Date.now()}.png`;
      const file: fileIo.File = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, buf);
      } finally {
        fileIo.closeSync(file);
      }
      console.info(`[${TAG}] png saved: ${path}, bytes=${buf.byteLength}`);
      return path;
    } finally {
      packer.release();
    }
  }
}
