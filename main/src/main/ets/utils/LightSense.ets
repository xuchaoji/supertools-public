import { uiMaterial } from '@kit.ArkUI';
import { hdsEffect, hdsMaterial } from '@kit.UIDesignKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { PreferencesUtil } from '@pura/harmony-utils';
import { SpKeys } from '../constant/SpKeys';

/**
 * 全局光感档位（沉浸光感强度统一控制）。
 *
 * 档位：0=关闭 1=柔和 2=标准 3=精致
 * 各表面（卡片毛玻璃、Tab 栏材质、点光源光效）统一按档位取值，
 * 全部使用官方 API（backgroundBlurStyle / systemMaterial / hdsEffect / hdsMaterial），非自绘模拟。
 *
 * 持久化：SpKeys.LIGHT_SENSE；内存同步：AppStorage['LightSense']。
 * 能力降级：HarmonyOS 7.0(API 26) 起支持 systemMaterial；6.0(API 20) 起支持 hdsEffect；
 * 更低版本自动回退为 backgroundBlurStyle + 透明度（现状兜底）。
 */
export class LightSense {
  static readonly LEVEL_OFF: number = 0;
  static readonly LEVEL_GENTLE: number = 1;
  static readonly LEVEL_SMOOTH: number = 2;
  static readonly LEVEL_EXQUISITE: number = 3;
  static readonly LEVEL_NAMES: Array<string> = ['关闭', '柔和', '标准', '精致'];

  /** 读取当前档位（持久化，默认精致） */
  static getLevel(): number {
    try {
      return PreferencesUtil.getNumberSync(SpKeys.LIGHT_SENSE, LightSense.LEVEL_EXQUISITE);
    } catch (e) {
      return LightSense.LEVEL_EXQUISITE;
    }
  }

  /** 设置档位：持久化 + AppStorage 广播（Index/WallpaperHost 等 V1 组件可响应） */
  static setLevel(value: number): void {
    const level = Math.min(Math.max(Math.round(value), 0), 3);
    try {
      PreferencesUtil.putSync(SpKeys.LIGHT_SENSE, level);
    } catch (e) {
      console.error(`[LightSense] put failed: ${JSON.stringify(e)}`);
    }
    AppStorage.setOrCreate<number>('LightSense', level);
  }

  /** 档位名称 */
  static levelName(level: number): string {
    const i = Math.min(Math.max(Math.round(level), 0), 3);
    return LightSense.LEVEL_NAMES[i];
  }

  /** 是否支持官方沉浸材质 systemMaterial（HarmonyOS 7.0 / API 26+） */
  static supportsSystemMaterial(): boolean {
    try {
      return deviceInfo.distributionOSApiVersion >= 70000;
    } catch (e) {
      return false;
    }
  }

  /** 是否支持 HDS 视觉特效（点光源/流光，HarmonyOS 6.0 / API 20+） */
  static supportsHdsEffect(): boolean {
    try {
      return deviceInfo.distributionOSApiVersion >= 60000;
    } catch (e) {
      return false;
    }
  }

  /** Tab 栏材质类型：关闭档为 NONE（无材质），其余为 IMMERSIVE 沉浸材质 */
  static tabMaterialType(level: number): hdsMaterial.MaterialType {
    return level <= LightSense.LEVEL_OFF ? hdsMaterial.MaterialType.NONE : hdsMaterial.MaterialType.IMMERSIVE;
  }

  /** Tab 栏材质级别：1=柔和 2=顺滑 3=精致（固定档位，跨设备一致） */
  static tabMaterialLevel(level: number): hdsMaterial.MaterialLevel {
    if (level <= LightSense.LEVEL_GENTLE) {
      return hdsMaterial.MaterialLevel.GENTLE;
    }
    if (level <= LightSense.LEVEL_SMOOTH) {
      return hdsMaterial.MaterialLevel.SMOOTH;
    }
    return hdsMaterial.MaterialLevel.EXQUISITE;
  }

  /** 卡片毛玻璃档位：0=无模糊 1=薄 2=厚 3=极厚 */
  static cardBlurStyle(level: number): BlurStyle {
    if (level <= LightSense.LEVEL_OFF) {
      return BlurStyle.NONE;
    }
    if (level <= LightSense.LEVEL_GENTLE) {
      return BlurStyle.COMPONENT_THIN;
    }
    if (level <= LightSense.LEVEL_SMOOTH) {
      return BlurStyle.COMPONENT_THICK;
    }
    return BlurStyle.COMPONENT_ULTRA_THICK;
  }

  /**
   * 官方沉浸材质（systemMaterial）：仅精致档且支持 API 26 时返回；
   * 否则 undefined（表面回退为 backgroundBlurStyle 毛玻璃）。
   * 低算力设备由系统自动降级为边框/阴影。
   */
  static immersiveMaterial(level: number): uiMaterial.ImmersiveMaterial | undefined {
    if (level < LightSense.LEVEL_EXQUISITE || !LightSense.supportsSystemMaterial()) {
      return undefined;
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: Color.Transparent,
      applyShadow: false,
      lightEffect: { color: Color.White }
    });
  }

  /** 点光源光效（官方视觉特效）：标准档柔和、精致档明亮；低版本/关闭档返回 undefined */
  static pointLightEffect(level: number): hdsEffect.PointLightEffect | undefined {
    if (level < LightSense.LEVEL_SMOOTH || !LightSense.supportsHdsEffect()) {
      return undefined;
    }
    return {
      sourceType: level >= LightSense.LEVEL_EXQUISITE
        ? hdsEffect.PointLightSourceType.BRIGHT
        : hdsEffect.PointLightSourceType.SOFT,
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
      options: {
        color: '#FFFFFF',
        intensity: level >= LightSense.LEVEL_EXQUISITE ? 0.6 : 0.35,
        height: 48,
        bloom: level >= LightSense.LEVEL_EXQUISITE ? 0.5 : 0.3
      }
    };
  }

  /** 按当前档位构建官方点光源 visualEffect（无光效时为空效果） */
  static lightVisualEffect(): VisualEffect {
    const builder = new hdsEffect.HdsEffectBuilder();
    const pl = LightSense.pointLightEffect(LightSense.getLevel());
    if (pl) {
      builder.pointLight(pl);
    }
    return builder.buildEffect();
  }
}
