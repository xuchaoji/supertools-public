import { HMRouter } from '@hadss/hmrouter';
import { PageNames } from '../constant/PageNames';
import { deviceInfo } from '@kit.BasicServicesKit';
import { batteryInfo } from '@kit.BasicServicesKit';
import { display } from '@kit.ArkUI';
import { hidebug } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import statfs from '@ohos.file.statvfs';

const TAG: string = 'DeviceInfoPage';

interface InfoItem {
  label: string;
  value: string;
}

@HMRouter({ pageUrl: PageNames.DEVICE_INFO_PAGE })
@Entry
@ComponentV2
export struct DeviceInfoPage {
  @Local deviceItems: InfoItem[] = [];
  @Local displayItems: InfoItem[] = [];
  @Local memoryItems: InfoItem[] = [];
  @Local batteryItems: InfoItem[] = [];
  @Local storageItems: InfoItem[] = [];

  aboutToAppear(): void {
    this.collectDeviceInfo();
    this.collectDisplayInfo();
    this.collectMemoryInfo();
    this.collectBatteryInfo();
    this.collectStorageInfo();
  }

  collectDeviceInfo(): void {
    const items: InfoItem[] = [];
    try {
      items.push({ label: '设备型号', value: deviceInfo.productModel ?? '-' });
      items.push({ label: '品牌', value: deviceInfo.brand ?? '-' });
      items.push({ label: '制造商', value: deviceInfo.manufacture ?? '-' });
      items.push({ label: '市场名称', value: deviceInfo.marketName ?? '-' });
      items.push({ label: '设备类型', value: deviceInfo.deviceType ?? '-' });
      items.push({ label: '硬件型号', value: deviceInfo.hardwareModel ?? '-' });
      items.push({ label: '硬件配置', value: deviceInfo.hardwareProfile ?? '-' });
      items.push({ label: 'CPU 架构', value: deviceInfo.abiList ?? '-' });
      items.push({ label: '软件型号', value: deviceInfo.softwareModel ?? '-' });
      items.push({ label: 'OS 版本', value: deviceInfo.osFullName ?? '-' });
      items.push({ label: '显示版本', value: deviceInfo.displayVersion ?? '-' });
      items.push({ label: 'SDK API 级别', value: String(deviceInfo.sdkApiVersion) });
      items.push({ label: '首个 API 版本', value: String(deviceInfo.firstApiVersion) });
      items.push({ label: '构建版本', value: String(deviceInfo.buildVersion) ?? '-' });
    } catch (e) {
      console.error(`[${TAG}] collectDeviceInfo error: ${JSON.stringify(e)}`);
    }
    this.deviceItems = items;
  }

  collectDisplayInfo(): void {
    const items: InfoItem[] = [];
    try {
      const d = display.getDefaultDisplaySync();
      items.push({ label: '屏幕宽度', value: `${d.width} px` });
      items.push({ label: '屏幕高度', value: `${d.height} px` });
      items.push({ label: '像素密度', value: `${d.densityPixels} (${d.densityDPI} DPI)` });
      items.push({ label: '刷新率', value: `${d.refreshRate} Hz` });
      items.push({ label: '旋转角度', value: `${d.rotation}°` });
    } catch (e) {
      console.error(`[${TAG}] collectDisplayInfo error: ${JSON.stringify(e)}`);
    }
    this.displayItems = items;
  }

  collectMemoryInfo(): void {
    const items: InfoItem[] = [];
    try {
      const mem = hidebug.getSystemMemInfo();
      const totalKB = Number(mem.totalMem);
      const availableKB = Number(mem.availableMem);
      const freeKB = Number(mem.freeMem);
      const usedKB = totalKB - availableKB;
      const fmtMem = (kb: number): string => kb >= 1024 * 1024 ?
        `${(kb / 1024 / 1024).toFixed(1)} GB` : `${(kb / 1024).toFixed(0)} MB`;
      items.push({ label: '总内存', value: fmtMem(totalKB) });
      items.push({ label: '已用内存', value: fmtMem(usedKB) });
      items.push({ label: '可用内存', value: fmtMem(availableKB) });
      items.push({ label: '空闲内存', value: fmtMem(freeKB) });
    } catch (e) {
      console.error(`[${TAG}] collectMemoryInfo error: ${JSON.stringify(e)}`);
    }
    this.memoryItems = items;
  }

  collectBatteryInfo(): void {
    const items: InfoItem[] = [];
    try {
      const soc = batteryInfo.batterySOC;
      items.push({ label: '电量', value: `${soc}%` });

      const charging = batteryInfo.chargingStatus;
      const chargingText = charging === 1 ? '正在充电' : '未充电';
      items.push({ label: '充电状态', value: chargingText });

      const health = batteryInfo.healthStatus;
      const healthMap: Record<number, string> = { 1: '正常', 2: '未知', 3: '良好', 4: '过热', 5: '过压', 6: '过冷' };
      items.push({ label: '电池健康', value: healthMap[health] ?? '未知' });

      if (batteryInfo.technology != null) {
        items.push({ label: '电池技术', value: batteryInfo.technology });
      }
      if (batteryInfo.voltage != null) {
        items.push({ label: '电压', value: `${(batteryInfo.voltage / 1000000).toFixed(2)} V` });
      }
    } catch (e) {
      console.error(`[${TAG}] collectBatteryInfo error: ${JSON.stringify(e)}`);
    }
    this.batteryItems = items;
  }

  collectStorageInfo(): void {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const root = context.filesDir.substring(0, context.filesDir.indexOf('/files'));
      const totalSize = statfs.getTotalSizeSync(root);
      const freeSize = statfs.getFreeSizeSync(root);
      if (totalSize > 0) {
        const totalGB = totalSize / 1024 / 1024 / 1024;
        const freeGB = freeSize / 1024 / 1024 / 1024;
        const usedGB = totalGB - freeGB;
        this.storageItems = [
          { label: '存储总量', value: `${totalGB.toFixed(1)} GB` },
          { label: '已用空间', value: `${usedGB.toFixed(1)} GB` },
          { label: '可用空间', value: `${freeGB.toFixed(1)} GB` }
        ];
      }
    } catch (e) {
      console.error(`[${TAG}] collectStorageInfo error: ${JSON.stringify(e)}`);
      this.storageItems = [{ label: '获取失败', value: '请检查权限' }];
    }
  }

  @Builder
  sectionCard(title: string, items: InfoItem[]) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_emphasize'))
        .alignSelf(ItemAlign.Start)
        .margin({ left: '16vp', bottom: '8vp' })

      Column() {
        ForEach(items, (item: InfoItem) => {
          Row() {
            Text(item.label)
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .layoutWeight(0.4)
            Text(item.value)
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Medium)
              .layoutWeight(0.6)
              .textAlign(TextAlign.End)
              .copyOption(CopyOptions.InApp)
          }
          .width('100%')
          .padding({ top: '10vp', bottom: '10vp', left: '16vp', right: '16vp' })
          .border({
            width: { bottom: 0.5 },
            color: $r('sys.color.comp_background_gray')
          })
        })
      }
      .width('100%')
      .borderRadius('12vp')
      .backgroundColor($r('sys.color.ohos_fa_list_card_bg_blur'))
    }
    .width('100%')
    .margin({ top: '12vp' })
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: '4vp' }) {
          this.sectionCard('设备信息', this.deviceItems)
          this.sectionCard('屏幕信息', this.displayItems)
          this.sectionCard('内存信息', this.memoryItems)
          this.sectionCard('电池信息', this.batteryItems)
          this.sectionCard('存储信息', this.storageItems)
        }
        .width('100%')
        .padding({ left: '16vp', right: '16vp', bottom: '32vp' })
      }
      .scrollBar(BarState.Auto)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }
}
