import { HMRouter, HMRouterMgr } from "@hadss/hmrouter";
import { PageNames } from "../constant/PageNames";
import { SpKeys } from "../constant/SpKeys";
import { DragCardModel, ToolCardItem } from "../model/HomePageModel";
import hilog from "@ohos.hilog";
import { JSON } from "@kit.ArkTS";
import { AppUtil, PreferencesUtil } from "@pura/harmony-utils";
import promptAction from '@ohos.promptAction';
import { RecordViewModel } from "../viewmodel/RecordViewModel";
import { media } from "@kit.MediaKit";
import { SettingGroup } from "../components/SettingGroup";
import { SettingSwitchItem } from "../components/SettingSwitchItem";
import { CommonViewModel } from "../viewmodel/CommonViewModel"
import { GlobalContextHolder } from "../utils/GlobalContextHolder";
import { FloatClockManager } from "../capabilities/floatingclock/FloatClockManager";
import { StressFloatWindowManager } from "../capabilities/floatingstress/StressWindowManager";
import { TargetConstants } from "main/ets/TargetConstants";
import { WebServerUtil } from "../utils/WebServerUtil";
import { FloatWindowUtil } from "../utils/FloatWindowUtil";

const TAG: string = 'HOME_PAGE';

const TOOLS_TAB_INDEX = 0;
const SETTING_TAB_INDEX = 1;

@HMRouter({ pageUrl: PageNames.HOME_PAGE })
@ComponentV2
export struct HomePage {
  @Local currentIndex: number = 0;
  @Local settingsClickCount: number = 0;
  @Local isHdcVisible: boolean = false;
  private lastSettingsClickTime: number = 0;
  private readonly REQUIRED_CLICKS: number = 8;
  private readonly CLICK_WINDOW_MS: number = 5000;
  private msgNum: number = 9999;
  private tabsController: TabsController = new TabsController();
  @Local listData: ToolCardItem[] = [
    {
      name: 'App Linking 解析',
      desc: '元服务/App链接深度拆解与跳转测试',
      icon: $r('app.media.code'),
      onClick: (event: ClickEvent) => {
        HMRouterMgr.push({ pageUrl: PageNames.APP_LINKING_TOOL })
      }
    },
    {
      name: '录屏',
      desc: '高清无压缩录屏功能',
      icon: $r('app.media.recorder'),
      onClick: (event: ClickEvent) => {
        HMRouterMgr.push({ pageUrl: PageNames.SCREEN_RECORD })
      }
    },
    {
      name: '本地web服务',
      desc: '构建本地静态web服务器',
      icon: $r('app.media.redstone_repeater'),
      onClick: () => {
        HMRouterMgr.push({ pageUrl: PageNames.LOCAL_WEB_PAGE })
      }
    },
    {
      name: '字符串转换',
      desc: 'Base64、Url编解码',
      icon: $r('app.media.code'),
      onClick: (event) => {
        HMRouterMgr.push({ pageUrl: PageNames.STR_CONVERT })
      }
    }
    ,
    {
      name: 'HDC 调试',
      desc: '本地 HDC 终端，直连 hdcd 调试本机',
      icon: $r('app.media.crafting_table'),
      onClick: (event: ClickEvent) => {
        HMRouterMgr.push({ pageUrl: PageNames.HDC_DEBUG_PAGE })
      }
    }
  ];
  @Local itemData: DragCardModel = new DragCardModel();

  aboutToAppear(): void {
    if (TargetConstants.IS_AG_TARGET) {
      this.isHdcVisible = PreferencesUtil.getBooleanSync(SpKeys.ENABLE_HDC_VISIBLE, false);
    } else {
      this.isHdcVisible = true;
    }
    // 设备信息：default / dev 两个 target 均默认可见
    this.listData.push({
      name: '设备信息',
      desc: '系统、屏幕、电池等硬件参数',
      icon: $r('app.media.deviceinfo'),
      onClick: (event: ClickEvent) => {
        HMRouterMgr.push({ pageUrl: PageNames.DEVICE_INFO_PAGE })
      }
    })
    if (TargetConstants.IS_AG_TARGET) {
      this.listData.push({
        name: '压测工具',
        desc: '执行计算任务模拟设备高负载场景',
        icon: $r('app.media.bench'),
        onClick: (event: ClickEvent) => {
          HMRouterMgr.push({ pageUrl: PageNames.CALC_PAGE })
        }
      })
    }
    // 恢复拖拽排序后的位置记忆
    this.restoreToolOrder();
  }

  /** 保存当前工具卡片顺序（按 name） */
  private saveToolOrder(): void {
    try {
      const names: string[] = this.listData.map((item: ToolCardItem) => String(item.name));
      PreferencesUtil.putSync(SpKeys.TOOL_ORDER, JSON.stringify(names));
    } catch (e) {
      hilog.info(0x0000, TAG, 'saveToolOrder failed');
    }
  }

  /**
   * 按上次拖拽保存的顺序重排 listData：
   * 已保存的工具按保存顺序排列；保存列表中没有的新增工具按默认顺序追加在末尾。
   */
  private restoreToolOrder(): void {
    try {
      const raw = PreferencesUtil.getStringSync(SpKeys.TOOL_ORDER, '');
      if (!raw) { return; }
      const saved: string[] = JSON.parse(raw) as string[];
      if (!Array.isArray(saved) || saved.length === 0) { return; }
      const byName = new Map<string, ToolCardItem>();
      for (const item of this.listData) {
        byName.set(String(item.name), item);
      }
      const ordered: ToolCardItem[] = [];
      for (const name of saved) {
        const item = byName.get(name);
        if (item) {
          ordered.push(item);
          byName.delete(name);
        }
      }
      // 保存列表中不存在的工具（后续新增）按默认顺序追加
      for (const item of this.listData) {
        if (byName.has(String(item.name))) {
          ordered.push(item);
        }
      }
      if (ordered.length === this.listData.length) {
        this.listData = ordered;
      }
    } catch (e) {
      hilog.info(0x0000, TAG, 'restoreToolOrder failed');
    }
  }

  @Builder
  tabBuilder(title: Resource, index: number, selectedImg: Resource, normalImg: Resource) {
    Column() {
      Image(this.currentIndex === index ? selectedImg : normalImg)
        .width(this.currentIndex === index ? 32 : 24)
        .height(this.currentIndex === index ? 32 : 24)
        .objectFit(ImageFit.Contain)
        .animation({ duration: 200, curve: Curve.EaseInOut })

      Text(title)
        .margin({ top: this.currentIndex === index ? 8 : 4 })
        .fontSize(10)
        .fontColor(this.currentIndex === index ? $r('sys.color.font_emphasize') : $r('sys.color.font_primary'))
        .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Normal)
        .animation({ duration: 200 })
    }
    .justifyContent(FlexAlign.Center)
    .padding({
      top: '8vp',
      bottom: `${AppUtil.getNavigationIndicatorHeight()}px`
    })
    .height('auto')
    .width('100%')
    .onClick(() => {
      this.currentIndex = index;
      this.tabsController.changeIndex(this.currentIndex);
      if (index === SETTING_TAB_INDEX) {
        let now: number = Date.now();
        if (now - this.lastSettingsClickTime > this.CLICK_WINDOW_MS) {
          this.settingsClickCount = 0;
        }
        this.lastSettingsClickTime = now;
        this.settingsClickCount++;
        if (this.settingsClickCount >= this.REQUIRED_CLICKS) {
          PreferencesUtil.put(SpKeys.ENABLE_SCAN_PARSE, true);
          PreferencesUtil.put(SpKeys.ENABLE_HDC_VISIBLE, true);
          this.isHdcVisible = true;
          promptAction.showToast({ message: '扫码解析 + HDC调试功能已启用', duration: 1500 });
          this.settingsClickCount = 0;
        }
      }
    })
  }

  @Builder
  tabContentBuilder(text: Resource, index: number, selectedImg: Resource, normalImg: Resource) {
    TabContent() {
      // 提取外层容器用于Pad大屏适配居中
      Column() {
        if (index === TOOLS_TAB_INDEX) {
          this.toolList();
        } else {
          this.settingPage();
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('sys.color.background_secondary'))
    .tabBar(this.tabBuilder(text, index, selectedImg, normalImg))
  }

  @Builder
  settingPage() {
    Scroll() {
      Column({ space: '12vp' }) {
        Text('工具箱设置项:')
          .margin({ left: '8vp', top: '16vp' })
          .fontSize($r('sys.float.Body_L'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_secondary'))

        SettingGroup() {
          SettingSwitchItem({
            title: '录屏是否启用H265',
            isOn: RecordViewModel.getInstance().preset === media.AVScreenCaptureRecordPreset.SCREEN_RECORD_PRESET_H265_AAC_MP4,
            onChange: (isOn: boolean) => {
              RecordViewModel.getInstance().preset = isOn ?
                media.AVScreenCaptureRecordPreset.SCREEN_RECORD_PRESET_H265_AAC_MP4 : media.AVScreenCaptureRecordPreset.SCREEN_RECORD_PRESET_H264_AAC_MP4
            }
          })
          SettingSwitchItem({
            title: '是否录制麦克风声音',
            isOn: RecordViewModel.getInstance().recordMic,
            onChange: (isOn: boolean) => {
              RecordViewModel.getInstance().recordMic = isOn
            }
          })
        }

        Text('独立小工具:')
          .margin({ left: '8vp', top: '8vp' })
          .fontSize($r('sys.float.Body_L'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_secondary'))
          .visibility(TargetConstants.HAS_FLOATING_PERM ? Visibility.Visible:Visibility.None)

        SettingGroup({
          vis: TargetConstants.HAS_FLOATING_PERM
        }) {
          SettingSwitchItem({
            title: '启用悬浮时钟',
            isOn: CommonViewModel.getInstance().floatingClockOn,
            vis: TargetConstants.HAS_FLOATING_PERM,
            onChange: (isOn: boolean) => {
              CommonViewModel.getInstance().floatingClockOn = isOn;
              if (PreferencesUtil.getBooleanSync(SpKeys.AUTO_START_ENABLED, true)) {
                PreferencesUtil.put(SpKeys.FLOAT_CLOCK_ON, isOn);
                console.info(`[StateRestore] put FLOAT_CLOCK_ON = ${isOn}`);
              }
              const context = GlobalContextHolder.getInstance().uiAbilityContext;
              if (isOn && context) {
                FloatClockManager.show(context);
              } else {
                FloatClockManager.destroy();
                CommonViewModel.getInstance().floatingClockOn = false;
              }
            }
          })
          SettingSwitchItem({
            title: '启用悬浮压测',
            isOn: CommonViewModel.getInstance().cpuStressOn,
            vis: TargetConstants.HAS_FLOATING_PERM,
            onChange: (isOn: boolean) => {
              CommonViewModel.getInstance().cpuStressOn = isOn;
              if (PreferencesUtil.getBooleanSync(SpKeys.AUTO_START_ENABLED, true)) {
                PreferencesUtil.put(SpKeys.CPU_STRESS_ON, isOn);
                console.info(`[StateRestore] put CPU_STRESS_ON = ${isOn}`);
              }
              const context = GlobalContextHolder.getInstance().uiAbilityContext;
              if (isOn && context) {
                StressFloatWindowManager.getInstance().show(context);
              } else {
                StressFloatWindowManager.getInstance().hide();
                CommonViewModel.getInstance().cpuStressOn = false;
              }
            }
          })
        }

        Text('服务自启动设置:')
          .margin({ left: '8vp', top: '16vp' })
          .fontSize($r('sys.float.Body_L'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_secondary'))

        SettingGroup() {
          SettingSwitchItem({
            title: '启用服务自启动',
            isOn: PreferencesUtil.getBooleanSync(SpKeys.AUTO_START_ENABLED, true),
            onChange: (isOn: boolean) => {
              PreferencesUtil.put(SpKeys.AUTO_START_ENABLED, isOn);
              console.info(`[StateRestore] put AUTO_START_ENABLED = ${isOn}`);
              if (!isOn) {
                WebServerUtil.getInstance().stop();
                FloatWindowUtil.destroyFloatWindow();
                FloatClockManager.destroy();
                StressFloatWindowManager.getInstance().hide();
                CommonViewModel.getInstance().floatingClockOn = false;
                CommonViewModel.getInstance().cpuStressOn = false;
                console.info('[StateRestore] auto-start disabled, all services stopped');
              }
            }
          })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      // [Pad大屏适配] 限制最大宽度
      .constraintSize({ maxWidth: 800 })
    }
    .scrollBar(BarState.Auto)
    .padding({
      top: AppUtil.getStatusBarHeight(),
      bottom: AppUtil.getNavigationIndicatorHeight(),
      left: '16vp',
      right: '16vp'
    })
    .width('100%')
    .height('100%')
  }

  build() {
    Tabs({
      barPosition: BarPosition.End,
      controller: this.tabsController
    }) {
      this.tabContentBuilder($r('app.string.tools_tab'),
        TOOLS_TAB_INDEX, $r('app.media.settings'), $r('app.media.settings'))
      this.tabContentBuilder($r('app.string.setting_tab'),
        SETTING_TAB_INDEX, $r('app.media.globalSetting'), $r('app.media.globalSetting'))
    }
    .width('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .barHeight('auto')
    .barMode(BarMode.Fixed)
    .backgroundBlurStyle(BlurStyle.Thin)
    .onAnimationStart((index: number, targetIndex: number) => {
      hilog.info(0x0000, 'index', index.toString());
      this.currentIndex = targetIndex;
    })
  }

  @Builder
  toolList() {
    Column() {
      Grid(new Scroller()) {
        ForEach(this.listData, (item: ToolCardItem) => {
          // HDC 调试在上架版默认隐藏：条件渲染避免 Grid 占位空洞
          if (!(item.name === 'HDC 调试' && !this.isHdcVisible)) {
            GridItem() {
              Column({ space: 4 }) {
                Image(item.icon)
                  .width('44vp')
                  .height('44vp')
                  .interpolation(ImageInterpolation.None)
                  .draggable(false)

                Text(item.name)
                  .fontSize(14)
                  .fontColor($r('sys.color.font_primary'))
                  .fontWeight(FontWeight.Medium)
                  .maxLines(1)
                  .ellipsisMode(EllipsisMode.END)
                  .textAlign(TextAlign.Center)
                  .width('100%')

                Text(item.desc)
                  .fontSize(10)
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(2)
                  .ellipsisMode(EllipsisMode.END)
                  .textAlign(TextAlign.Center)
                  .width('100%')
              }
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .width('100%')
              .height('100%')
              .padding({ left: 6, right: 6, top: 10, bottom: 10 })
            }
            .onClick((event) => {
              item.onClick(event);
            })
            // 参考 ComprehensiveTool 网格卡片：淡蓝底 + 圆角 + 固定高度（避免行被拉伸填满屏幕）
            .backgroundColor('rgba(10, 89, 247, 0.05)')
            .borderRadius(12)
            .border({ width: 1, color: 'rgba(10, 89, 247, 0.10)' })
            .height(112)
            .onAreaChange((oldValue: Area, newValue: Area) => {
              this.itemData.width = (newValue.width as number) * 1.1;
              this.itemData.height = (newValue.height as number) * 1.1;
            })
          }
        }, (item: ToolCardItem) => JSON.stringify(item))
      }
      .scrollBar(BarState.Off)
      .editMode(true)
      .onItemDragStart((_event: ItemDragInfo, itemIndex: number) => {
        this.itemData.toolCardItem = this.listData[itemIndex];
        return pixelMapBuilder(this.itemData);
      })
      .onItemDrop((_event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean): void => {
        if (!isSuccess || insertIndex >= this.listData.length) {
          return;
        }
        animateTo(
          { duration: 200, curve: Curve.Friction },
          () => {
            const temp: ToolCardItem = this.listData[itemIndex];
            this.listData[itemIndex] = this.listData[insertIndex];
            this.listData[insertIndex] = temp;
          })
        // 持久化拖拽后的顺序，重启后保持
        this.saveToolOrder();
      })
      .columnsGap(8)
      .rowsGap(8)
      .columnsTemplate('1fr 1fr 1fr')
      .padding(12)
      .edgeEffect(EdgeEffect.Spring)
      // [Pad大屏适配]
      .constraintSize({ maxWidth: 800 })
    }
    .height('100%')
    .width('100%')
    .align(Alignment.Center)
  }
}

@Builder
export function pixelMapBuilder(dragModel: DragCardModel) {
  Text(dragModel.toolCardItem.name)
    .fontSize($r('sys.float.Body_L'))
    .fontWeight(FontWeight.Bold)
    .size({ width: dragModel.width, height: dragModel.height })
    .fontColor($r('sys.color.icon_emphasize'))
    .textAlign(TextAlign.Center)
    // 拖拽浮窗同样使用半透明+毛玻璃
    .backgroundColor('rgba(255, 255, 255, 0.9)')
    .backgroundBlurStyle(BlurStyle.Thick)
    .shadow({ radius: 30, color: 'rgba(0,0,0,0.15)', offsetX: 0, offsetY: 10 })
    .borderRadius($r('sys.float.corner_radius_level4'))
    .border({ width: 1.5, color: $r('sys.color.comp_background_emphasize') })
}
