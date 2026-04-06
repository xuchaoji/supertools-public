import { HMRouter, HMRouterMgr } from "@hadss/hmrouter";
import { PageNames } from "../constant/PageNames";
import { DragCardModel, ToolCardItem } from "../model/HomePageModel";
import hilog from "@ohos.hilog";
import { JSON } from "@kit.ArkTS";
import { AppUtil } from "@pura/harmony-utils";
import { RecordViewModel } from "../viewmodel/RecordViewModel";
import { media } from "@kit.MediaKit";
import { SettingGroup } from "../components/SettingGroup";
import { SettingSwitchItem } from "../components/SettingSwitchItem";
import { CommonViewModel } from "../viewmodel/CommonViewModel"
import { GlobalContextHolder } from "../utils/GlobalContextHolder";
import { FloatClockManager } from "../capabilities/floatingclock/FloatClockManager";
import { StressFloatWindowManager } from "../capabilities/floatingstress/StressWindowManager";
import { TargetConstants } from "main/ets/TargetConstants";

const TAG: string = 'HOME_PAGE';

const TOOLS_TAB_INDEX = 0;
const SETTING_TAB_INDEX = 1;

@HMRouter({ pageUrl: PageNames.HOME_PAGE })
@ComponentV2
export struct HomePage {
  @Local currentIndex: number = 0;
  private msgNum: number = 9999;
  private tabsController: TabsController = new TabsController();
  @Local listData: ToolCardItem[] = [
    {
      name: '压测工具',
      desc: '执行计算任务模拟设备高负载场景',
      icon: $r('app.media.bench'),
      onClick: (event: ClickEvent) => {
        HMRouterMgr.push({ pageUrl: PageNames.CALC_PAGE })
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
  ];
  @Local itemData: DragCardModel = new DragCardModel();

  aboutToAppear(): void {
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
          GridItem() {
            Row({ space: '16vp' }) {
              Image(item.icon)
                .width('64vp')
                .height('64vp')
                .interpolation(ImageInterpolation.None)

              Column({ space: '8vp' }) {
                Text(item.name)
                  .fontSize($r('sys.float.Body_L'))
                  .fontColor($r('sys.color.icon_emphasize'))
                  .fontWeight(FontWeight.Medium)
                  .textAlign(TextAlign.Start)
                  .margin({ right: $r('sys.float.padding_level2') })
                  .ellipsisMode(EllipsisMode.END)
                  .width('100%')
                Text(item.desc)
                  .fontSize($r('sys.float.Body_M'))
                  .fontColor($r('sys.color.icon'))
                  .textAlign(TextAlign.Start)
                  .margin({ right: $r('sys.float.padding_level2') })
                  .maxLines(2)
                  .ellipsisMode(EllipsisMode.END)
                  .width('100%')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .padding('16vp')
            .alignItems(VerticalAlign.Center)
            .width('100%')
            .height('auto')
            // 修复 Row 的 minHeight 报错，使用 constraintSize
            .constraintSize({ minHeight: '100vp' })
          }
          .onClick((event) => {
            item.onClick(event);
          })
          // 使用半透明白色背景，防止在纯色背景下隐形，同时保留毛玻璃支持
          .backgroundColor('rgba(255, 255, 255, 0.8)')
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .width('100%')
          .onAreaChange((oldValue: Area, newValue: Area) => {
            this.itemData.width = (newValue.width as number) * 1.1;
            this.itemData.height = (newValue.height as number) * 1.1;
          })
          .borderRadius($r('sys.float.corner_radius_level4'))
          .border({ width: 1, color: '#1A000000' })
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
      })
      .columnsGap(16)
      .rowsGap(16)
      .columnsTemplate('1fr')
      // [Pad大屏适配]
      .constraintSize({ maxWidth: 800 })
    }
    .height('100%')
    .width('100%')
    .padding({ left: '16vp', right: '16vp', top: '16vp' })
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