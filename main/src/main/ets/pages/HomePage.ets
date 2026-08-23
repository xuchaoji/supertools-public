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
import { mediaquery, display } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';
import { WallpaperUtil } from '../utils/WallpaperUtil';
import { PhotoHelper } from '@pura/picker_utils';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { HdsTabs, HdsTabsController, HdsTabsModifier, hdsMaterial } from '@kit.UIDesignKit';
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

/** 裁切画布尺寸（vp），避免 ArkTS 对象字面量类型限制 */
interface CropCanvasSize {
  cw: number;
  ch: number;
}

@HMRouter({ pageUrl: PageNames.HOME_PAGE })
@ComponentV2
export struct HomePage {
  @Local currentIndex: number = 0;
  @Local settingsClickCount: number = 0;
  @Local isHdcVisible: boolean = false;
  // 沉浸光感：跟随系统深/浅色模式
  @Local isDark: boolean = false;
  private themeMq: mediaquery.MediaQueryListener | null = null;
  // 主页壁纸（沉浸光感背景），空字符串表示未设置
  @Local wallpaperPath: string = '';
  // 官方 HDS 沉浸光感 Tab（HdsTabs + systemMaterialEffect）
  private hdsTabsController: HdsTabsController = new HdsTabsController();
  private hdsTabsModifier: HdsTabsModifier = new HdsTabsModifier();
  // 设备系统版本 >= 6.1.0(API 23) 才支持 HDS 沉浸材质，否则降级为手绘悬浮胶囊
  private supportImmersiveTabs: boolean = deviceInfo.distributionOSApiVersion >= 60100;
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
  // 内容区壁纸 PixelMap：盖住 NavDestination 的白底（Index 根级壁纸负责状态栏区域）
  @Local wallpaperPm: image.PixelMap | undefined = undefined;

  // ===== 壁纸裁切浮层状态 =====
  @Local showCrop: boolean = false;
  /** 待裁切的图片 uri（相册选择器返回，临时授权） */
  @Local cropUri: string = '';
  /** 当前缩放倍数（相对基准缩放，1~5） */
  @Local cropScale: number = 1;
  /** 图片左上角相对画布的偏移（vp） */
  @Local cropOffsetX: number = 0;
  @Local cropOffsetY: number = 0;
  /** 基准缩放：图片 Cover 铺满画布所需的放大倍数（@Local：getImageSize 异步返回后需刷新 UI） */
  @Local cropBaseScale: number = 1;
  /** 基准缩放后的图片宽高（vp） */
  @Local cropBaseW: number = 0;
  @Local cropBaseH: number = 0;
  /** 原图尺寸（px，onComplete 回调） */
  private origW: number = 0;
  private origH: number = 0;
  /** 画布尺寸（px，onAreaChange 实测，= 内容区实际大小） */
  private cropW: number = 1308;
  private cropH: number = 2880;
  /** 画布尺寸是否已实测确认（onAreaChange 到达） */
  private canvasConfirmed: boolean = false;
  /** 图片尺寸回调完成、可交互 */
  private cropReady: boolean = false;
  /** 裁切确认中（防止重复点击） */
  private cropBusy: boolean = false;
  private pinchStartZoom: number = 1;
  private panStartX: number = 0;
  private panStartY: number = 0;

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
    // 沉浸光感：订阅系统深/浅色模式
    this.initThemeListener();
    // 恢复已设置的壁纸
    this.wallpaperPath = WallpaperUtil.getPath();
    this.loadWallpaperPm();
    // 配置官方 HDS 沉浸光感悬浮 Tab 栏
    if (this.supportImmersiveTabs) {
      try {
        this.hdsTabsModifier
          .vertical(false)
          .barPosition(BarPosition.End)
          .barHeight(56)
          .barFloatingStyle({
            // 不跟随手持方向：跟随会把悬浮栏向惯用手一侧锚定，导致胶囊偏右/伸出屏幕
            adaptToHandedness: false,
            // 悬浮 Tab 栏宽度 = 屏幕 75%（436vp × 75% ≈ 327vp，用数值避免百分比解析错位）
            barWidth: {
              smallWidth: 327,
              mediumWidth: 327,
              largeWidth: 327
            },
            // 悬浮栏距底部间距（vp 单位；系统手势条约 33vp，这里留 40vp 避开）
            barBottomMargin: 40,
            systemMaterialEffect: {
              materialType: hdsMaterial.MaterialType.IMMERSIVE,
              materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
            },
          });
      } catch (e) {
        hilog.info(0x0000, TAG, 'init HdsTabsModifier failed: ' + JSON.stringify(e));
        this.supportImmersiveTabs = false;
      }
    }
  }

  aboutToDisappear(): void {
    this.themeMq?.off('change');
    this.themeMq = null;
  }

  /** 订阅系统深/浅色模式变化，驱动沉浸光感参数切换 */
  private initThemeListener(): void {
    try {
      this.themeMq = this.getUIContext().getMediaQuery().matchMediaSync('(display-mode: dark)');
      this.isDark = this.themeMq.matches;
      this.themeMq.on('change', (event: mediaquery.MediaQueryResult) => {
        this.isDark = event.matches;
      });
    } catch (e) {
      hilog.info(0x0000, TAG, 'initThemeListener failed: ' + JSON.stringify(e));
      this.isDark = false;
    }
  }

  /** 壁纸可显示的图片地址：直接使用存储路径（媒体 URI 或沙箱路径，沙箱路径不加 file:// 前缀） */
  private wallpaperSrc(): string {
    return this.wallpaperPath;
  }

  /** 加载内容区壁纸 PixelMap（盖住 NavDestination 白底） */
  private loadWallpaperPm(): void {
    const path = WallpaperUtil.getPath();
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
      this.wallpaperPm = pm;
    });
  }

  /** 拉起相册选择图片作为主页壁纸：选图后先进入裁切浮层，确认后应用 */
  private async pickWallpaper(): Promise<void> {
    try {
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      options.isPhotoTakingSupported = true;
      options.isSearchSupported = true;
      options.isEditSupported = false;
      options.isOriginalSupported = false;
      const uris: Array<string> = await PhotoHelper.selectEasy(options);
      if (uris.length === 0) {
        return;
      }
      // 先打开裁切浮层：用户调整位置/缩放，确认后才生成壁纸
      this.cropUri = uris[0];
      this.cropScale = 1;
      this.cropOffsetX = 0;
      this.cropOffsetY = 0;
      this.cropReady = false;
      this.canvasConfirmed = false;
      this.origW = 0;
      this.origH = 0;
      this.showCrop = true;
      // 主动读取原图尺寸（fd 级，兼容媒体 uri）：
      // 不能依赖 Image.onComplete —— 图片初始尺寸为 0 时 onComplete 可能不触发，
      // 导致 cropReady 永远为 false、确定按钮禁用、手势全部被吞
      WallpaperUtil.getImageSize(this.cropUri).then((size: image.Size | undefined) => {
        if (size && size.width > 0 && size.height > 0) {
          this.initCropBase(size.width, size.height);
        }
      });
    } catch (e) {
      hilog.info(0x0000, TAG, 'pickWallpaper failed: ' + JSON.stringify(e));
      promptAction.showToast({ message: '选择图片失败', duration: 1500 });
    }
  }

  /** 关闭裁切浮层（不应用变更，保留原壁纸） */
  private closeCrop(): void {
    this.showCrop = false;
    this.cropUri = '';
    this.cropReady = false;
    this.cropBusy = false;
    this.canvasConfirmed = false;
    this.origW = 0;
    this.origH = 0;
  }

  /** 屏幕像素密度（px per vp） */
  private densityPxPerVp(): number {
    try {
      return display.getDefaultDisplaySync().densityDPI / 160;
    } catch (e) {
      return 3;
    }
  }

  /** 画布尺寸（vp） */
  private canvasVp(): CropCanvasSize {
    const d = this.densityPxPerVp();
    const canvas: CropCanvasSize = { cw: this.cropW / d, ch: this.cropH / d };
    return canvas;
  }

  /**
   * 图片解码完成回调：记录原图尺寸，待画布尺寸就绪后统一计算基准缩放。
   * @param ow 原图宽度（px）
   * @param oh 原图高度（px）
   */
  private initCropBase(ow: number, oh: number): void {
    if (ow <= 0 || oh <= 0) {
      return;
    }
    this.origW = ow;
    this.origH = oh;
    this.computeCropBase();
  }

  /**
   * 计算基准缩放（图片 Cover 铺满画布，取宽高方向放大倍数的较大值，
   * 任意比例图片都不会拉伸变形，超出画布的部分被裁掉）。
   * 画布与图片尺寸两个异步回调都就绪后才计算；首次就绪时居中，
   * 之后画布变化只做偏移约束，不重置用户操作。
   */
  private computeCropBase(): void {
    if (this.origW <= 0 || this.origH <= 0 || !this.canvasConfirmed) {
      return;
    }
    const d = this.densityPxPerVp();
    const canvas = this.canvasVp();
    const cw = canvas.cw;
    const ch = canvas.ch;
    const iw = this.origW / d; // 原图尺寸（vp）
    const ih = this.origH / d;
    this.cropBaseScale = Math.max(cw / iw, ch / ih);
    this.cropBaseW = iw * this.cropBaseScale;
    this.cropBaseH = ih * this.cropBaseScale;
    if (!this.cropReady) {
      // 首次就绪：居中显示
      this.cropOffsetX = Math.max(0, (this.cropBaseW - cw) / 2);
      this.cropOffsetY = Math.max(0, (this.cropBaseH - ch) / 2);
      this.cropScale = 1;
      this.cropReady = true;
    } else {
      this.reclampOffset();
    }
  }

  /** 偏移约束在合法范围内 */
  private reclampOffset(): void {
    if (!this.cropReady) {
      return;
    }
    const canvas = this.canvasVp();
    const cw = canvas.cw;
    const ch = canvas.ch;
    const maxX = Math.max(0, this.cropBaseW * this.cropScale - cw);
    const maxY = Math.max(0, this.cropBaseH * this.cropScale - ch);
    this.cropOffsetX = Math.min(Math.max(this.cropOffsetX, 0), maxX);
    this.cropOffsetY = Math.min(Math.max(this.cropOffsetY, 0), maxY);
  }

  /** 画布尺寸变化（onAreaChange）后记录实测尺寸并重算基准 */
  private onCropAreaChange(w: number, h: number): void {
    this.cropW = w;
    this.cropH = h;
    this.canvasConfirmed = true;
    this.computeCropBase();
  }

  /** 确认裁切：按当前可视区域生成壁纸并应用 */
  private async confirmCrop(): Promise<void> {
    if (!this.cropReady || this.cropUri === '' || this.cropBusy) {
      return;
    }
    this.cropBusy = true;
    try {
      const d = this.densityPxPerVp();
      // 显示比例 = 基准缩放 × 用户缩放（无量纲，同时作用于 vp 画布与原始像素）
      const scale = this.cropBaseScale * this.cropScale;
      // 可视区域映射回原图坐标系（原图像素）
      const region: image.Region = {
        x: (this.cropOffsetX * d) / scale,
        y: (this.cropOffsetY * d) / scale,
        size: {
          width: this.cropW / scale,
          height: this.cropH / scale
        }
      };
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const path = await WallpaperUtil.cropAndSave(context, this.cropUri, region,
        { width: this.cropW, height: this.cropH });
      this.closeCrop();
      this.wallpaperPath = path;
      // 同步给 Index 根级壁纸层（覆盖状态栏区域）
      AppStorage.setOrCreate<string>('WallpaperPath', path);
      this.loadWallpaperPm();
      promptAction.showToast({ message: '壁纸已设置，沉浸光感效果已开启', duration: 1500 });
    } catch (e) {
      hilog.info(0x0000, TAG, 'confirmCrop failed: ' + JSON.stringify(e));
      this.cropBusy = false;
      promptAction.showToast({ message: '裁切壁纸失败', duration: 1500 });
    }
  }

  /** 恢复默认背景 */
  private removeWallpaper(): void {
    WallpaperUtil.remove();
    this.wallpaperPath = '';
    // 同步给 Index 根级壁纸层
    AppStorage.setOrCreate<string>('WallpaperPath', '');
    this.wallpaperPm = undefined;
    promptAction.showToast({ message: '已恢复默认背景', duration: 1500 });
  }

  /** 内容底部呼吸间距（vp） */
  private getContentBottomInset(): number {
    if (!this.supportImmersiveTabs) {
      // 手绘悬浮胶囊分支：内容延伸到悬浮胶囊下方，需要较大避让
      return 88;
    }
    // 官方 HDS 分支：避让由页面内部的底部 spacer 完成（见 settingPage/toolList），
    // 这里只留少量呼吸间距
    return 16;
  }

  /** Tab 点击统一处理：切换 + 设置页连点彩蛋 */
  private handleTabClick(index: number): void {
    this.currentIndex = index;
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
  emptyTabBar() {
    Row()
      .width(0)
      .height(0)
  }

  /** 沉浸光感悬浮导航胶囊：不贴底、左右留白、圆角毛玻璃材质 */
  @Builder
  floatingNavBar() {
    Row() {
      this.floatingTabItem(TOOLS_TAB_INDEX, $r('app.string.tools_tab'), $r('app.media.settings'), $r('app.media.settings'))
      this.floatingTabItem(SETTING_TAB_INDEX, $r('app.string.setting_tab'), $r('app.media.globalSetting'), $r('app.media.globalSetting'))
    }
    .width('100%')
    .padding(6)
    .borderRadius(32)
    // 毛玻璃材质层
    .backgroundColor(ImmersiveStyles.tabBarBase(this.isDark))
    .backdropBlur(24)
    // 外边缘受光（非对称 rim light，模拟折射衰减）
    .border({ width: 1, color: ImmersiveStyles.cardOuterRim(this.isDark) })
    // 悬浮投影
    .shadow({
      radius: 20,
      color: ImmersiveStyles.cardShadow(this.isDark),
      offsetX: 0,
      offsetY: 8
    })
    .margin({ left: 16, right: 16, bottom: '12vp' })
  }

  @Builder
  floatingTabItem(index: number, title: Resource, selectedImg: Resource, normalImg: Resource) {
    Column({ space: 2 }) {
      Image(this.currentIndex === index ? selectedImg : normalImg)
        .width(this.currentIndex === index ? 24 : 22)
        .height(this.currentIndex === index ? 24 : 22)
        .objectFit(ImageFit.Contain)
        .animation({ duration: 200, curve: Curve.EaseInOut })

      Text(title)
        .fontSize(10)
        .fontColor(this.currentIndex === index ? $r('sys.color.font_emphasize') : $r('sys.color.font_primary'))
        .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Normal)
        .animation({ duration: 200 })
    }
    .layoutWeight(1)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .borderRadius(26)
    // 选中态：胶囊高亮 + 光晕
    .backgroundColor(this.currentIndex === index ? ImmersiveStyles.tabSelectedBg(this.isDark) : Color.Transparent)
    .shadow(this.currentIndex === index ?
      { radius: 12, color: ImmersiveStyles.tabSelectedGlow(this.isDark), offsetX: 0, offsetY: 0 } :
      { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .onClick(() => {
      this.handleTabClick(index);
      this.tabsController.changeIndex(this.currentIndex);
    })
  }

  /** Tab 内容体（两个分支共用）：内容 + 壁纸透明背景 */
  @Builder
  tabContentBody(index: number) {
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
    .padding({ left: 12, right: 12 })
    // 设置壁纸后背景透明，让壁纸从卡片毛玻璃下透出
    .backgroundColor(this.wallpaperPath === '' ? $r('sys.color.background_secondary') : Color.Transparent)
  }

  /** 官方 HDS 沉浸光感悬浮 Tab（系统版本 >= 6.1.0 / API 23） */
  @Builder
  hdsTabsContent() {
    HdsTabs({
      controller: this.hdsTabsController,
      index: this.currentIndex
    }) {
      TabContent() {
        this.tabContentBody(TOOLS_TAB_INDEX)
      }
      .tabBar(BottomTabBarStyle.of($r('app.media.settings'), $r('app.string.tools_tab')))

      TabContent() {
        this.tabContentBody(SETTING_TAB_INDEX)
      }
      .tabBar(BottomTabBarStyle.of($r('app.media.globalSetting'), $r('app.string.setting_tab')))
    }
    .width('100%')
    .height('100%')
    // 悬浮样式（barWidth 数值、沉浸材质）需要 barOverlap(true) 才生效；
    // 内容避让由各页面内部的底部 spacer 完成，保证最后一行可滚出悬浮栏
    .barOverlap(true)
    // 透明化 Tab 栏背景，避免悬浮栏容器在胶囊下方/周围渲染出白色底带
    .barBackgroundColor(Color.Transparent)
    .attributeModifier(this.hdsTabsModifier)
    .onTabBarClick((index: number) => {
      this.handleTabClick(index);
    })
    .onChange((index: number) => {
      this.currentIndex = index;
    })
  }

  /** 降级方案：手绘悬浮胶囊（旧系统版本） */
  @Builder
  legacyTabsContent() {
    Stack({ alignContent: Alignment.Bottom }) {
      Tabs({
        barPosition: BarPosition.End,
        controller: this.tabsController
      }) {
        TabContent() {
          this.tabContentBody(TOOLS_TAB_INDEX)
        }
        .tabBar(this.emptyTabBar())

        TabContent() {
          this.tabContentBody(SETTING_TAB_INDEX)
        }
        .tabBar(this.emptyTabBar())
      }
      .width('100%')
      .height('100%')
      // 隐藏系统 Tab 栏（悬浮导航覆盖其上）
      .barHeight(0)
      .barMode(BarMode.Fixed)
      .onAnimationStart((index: number, targetIndex: number) => {
        hilog.info(0x0000, 'index', index.toString());
        this.currentIndex = targetIndex;
      })

      // 沉浸光感悬浮导航胶囊
      this.floatingNavBar()
    }
    .width('100%')
    .height('100%')
    // 给系统手势条留出区域，悬浮胶囊悬浮在其上方
    .padding({ bottom: `${AppUtil.getNavigationIndicatorHeight()}px` })
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

        Text('主页背景:')
          .margin({ left: '8vp', top: '16vp' })
          .fontSize($r('sys.float.Body_L'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_secondary'))

        SettingGroup() {
          ListItem() {
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text('设置壁纸')
                  .fontColor($r('sys.color.font_primary'))
                  .fontSize('16vp')
                  .fontWeight(FontWeight.Medium)

                Text('选择图片作为主页背景，毛玻璃卡片与悬浮导航将实时呈现光感效果')
                  .fontSize('12vp')
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              if (this.wallpaperPath !== '') {
                Image(this.wallpaperSrc())
                  .width('44vp')
                  .height('44vp')
                  .borderRadius('8vp')
                  .objectFit(ImageFit.Cover)
                  .margin({ right: '8vp' })

                Button('恢复默认')
                  .height(32)
                  .fontSize(12)
                  .onClick(() => this.removeWallpaper())
              } else {
                Button('选择图片')
                  .height(32)
                  .fontSize(12)
                  .onClick(() => this.pickWallpaper())
              }
            }
            .width('100%')
            .height('64vp')
            .justifyContent(FlexAlign.SpaceBetween)
            .padding({ left: '16vp', right: '16vp' })
          }
        }

        // 悬浮 Tab 栏避让 spacer：让最后一组内容可滚动到悬浮栏上方
        if (this.supportImmersiveTabs) {
          Row()
            .height(140)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      // [Pad大屏适配] 限制最大宽度
      .constraintSize({ maxWidth: 800 })
    }
    .scrollBar(BarState.Auto)
    .padding({
      bottom: this.getContentBottomInset(), // 悬浮 Tab 栏避让，避免列表被遮挡
      left: '16vp',
      right: '16vp'
    })
    .width('100%')
    .height('100%')
  }

  /** 壁纸裁切浮层：拖动平移、双指缩放，可视区域即最终壁纸区域 */
  @Builder
  cropOverlay() {
    Stack() {
      // 可平移/缩放的图片（尺寸与偏移均用 vp，与画布一致）
      Image(this.cropUri)
        .width(this.cropBaseW * this.cropScale)
        .height(this.cropBaseH * this.cropScale)
        .translate({ x: -this.cropOffsetX, y: -this.cropOffsetY })
        .onComplete((event) => {
          // 回调参数类型由 onComplete 签名推断（匿名对象类型，不能显式标注；参数可选）
          if (!event) {
            return;
          }
          this.initCropBase(event.width, event.height);
        })
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            PanGesture({ fingers: 1, distance: 5 })
              .onActionStart(() => {
                this.panStartX = this.cropOffsetX;
                this.panStartY = this.cropOffsetY;
              })
              .onActionUpdate((event: GestureEvent) => {
                if (!this.cropReady) {
                  return;
                }
                const canvas = this.canvasVp();
                const cw = canvas.cw;
                const ch = canvas.ch;
                const maxX = Math.max(0, this.cropBaseW * this.cropScale - cw);
                const maxY = Math.max(0, this.cropBaseH * this.cropScale - ch);
                this.cropOffsetX = Math.min(Math.max(this.panStartX - event.offsetX, 0), maxX);
                this.cropOffsetY = Math.min(Math.max(this.panStartY - event.offsetY, 0), maxY);
              }),
            PinchGesture({ fingers: 2 })
              .onActionStart(() => {
                this.pinchStartZoom = this.cropScale;
              })
              .onActionUpdate((event: GestureEvent) => {
                if (!this.cropReady) {
                  return;
                }
                const newScale = Math.min(Math.max(this.pinchStartZoom * event.scale, 1), 5);
                const k = newScale / this.cropScale;
                const canvas = this.canvasVp();
                const cw = canvas.cw;
                const ch = canvas.ch;
                // 以画布中心为锚点缩放，偏移同步缩放避免内容跳变
                const cx = this.cropOffsetX + cw / 2;
                const cy = this.cropOffsetY + ch / 2;
                this.cropScale = newScale;
                const maxX = Math.max(0, this.cropBaseW * newScale - cw);
                const maxY = Math.max(0, this.cropBaseH * newScale - ch);
                this.cropOffsetX = Math.min(Math.max(cx * k - cw / 2, 0), maxX);
                this.cropOffsetY = Math.min(Math.max(cy * k - ch / 2, 0), maxY);
              })
          )
        )

      // 底部提示（HitTestMode.None：自身不参与触摸测试，确保手势与按钮不被覆盖层拦截）
      Column() {
        Blank()
        Text('拖动调整位置，双指缩放大小')
          .fontSize(13)
          .fontColor('rgba(255, 255, 255, 0.85)')
          .padding({ bottom: 24 })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)

      // 顶部操作条（放最后=最上层，按钮始终可点）
      Row() {
        Button('取消')
          .height(36)
          .fontSize(14)
          .backgroundColor('rgba(255, 255, 255, 0.18)')
          .fontColor(Color.White)
          .onClick(() => this.closeCrop())

        Blank()

        Button('确定')
          .height(36)
          .fontSize(14)
          .backgroundColor('rgba(255, 255, 255, 0.92)')
          .fontColor(Color.Black)
          .enabled(this.cropReady)
          .onClick(() => this.confirmCrop())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .clip(true)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const w = newValue.width as number;
      const h = newValue.height as number;
      if (w > 0 && h > 0) {
        this.onCropAreaChange(w, h);
      }
    })
  }

  build() {
    Stack() {
      // 内容区壁纸：盖住 NavDestination 的白底（Index 根级壁纸只覆盖状态栏区域）
      if (this.wallpaperPm) {
        Image(this.wallpaperPm)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      }
      // 官方 HDS 沉浸光感 Tab（系统 6.1.0+），否则降级为手绘悬浮胶囊
      if (this.supportImmersiveTabs) {
        this.hdsTabsContent()
      } else {
        this.legacyTabsContent()
      }
      // 壁纸裁切浮层：置于最顶层
      if (this.showCrop) {
        this.cropOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  toolList() {
    Column() {
      Grid(new Scroller()) {
        ForEach(this.listData, (item: ToolCardItem) => {
          // HDC 调试在上架版默认隐藏：条件渲染避免 Grid 占位空洞
          if (!(item.name === 'HDC 调试' && !this.isHdcVisible)) {
            GridItem() {
              // 沉浸光感多层结构：毛玻璃基底 -> 光感渐变 -> 内容
              Stack() {
                // 图层1：毛玻璃基底
                Stack()
                  .width('100%')
                  .height('100%')
                  .borderRadius(ImmersiveStyles.cardRadius())
                  .backgroundColor(ImmersiveStyles.cardBase(this.isDark))
                  .backdropBlur(ImmersiveStyles.cardBlurRadius())

                // 图层2：表面光感渐变（左上光源 -> 右下微暗角）
                Stack()
                  .width('100%')
                  .height('100%')
                  .borderRadius(ImmersiveStyles.cardRadius())
                  .linearGradient({
                    angle: 135,
                    colors: ImmersiveStyles.cardSurfaceColors(this.isDark)
                  })

                // 图层3：实际内容
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
              .width('100%')
              .height('100%')
              .clip(true)
              .borderRadius(ImmersiveStyles.cardRadius())
              // 外边缘受光（非对称 rim light，模拟折射衰减）
              .border({ width: 1, color: ImmersiveStyles.cardOuterRim(this.isDark) })
              // 柔和投影（依据圆角边界生成）
              .shadow({
                radius: 14,
                color: ImmersiveStyles.cardShadow(this.isDark),
                offsetX: 0,
                offsetY: 4
              })
            }
            .onClick((event) => {
              item.onClick(event);
            })
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
        return pixelMapBuilder(this.itemData, this.isDark);
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
      // 底部预留悬浮 Tab 栏避让空间（HDS 分支），最后一排卡片可滚动到悬浮栏上方
      .padding({
        left: 12,
        right: 12,
        top: 12,
        bottom: this.supportImmersiveTabs ? 116 : 12
      })
      .edgeEffect(EdgeEffect.Spring)
      // [Pad大屏适配]
      .constraintSize({ maxWidth: 800 })
    }
    .height('100%')
    .width('100%')
    // 悬浮 Tab 栏避让，保证最后一排卡片可滚动到悬浮栏上方
    .padding({ bottom: this.getContentBottomInset() })
    .align(Alignment.Center)
  }
}

@Builder
export function pixelMapBuilder(dragModel: DragCardModel, isDark: boolean) {
  // 沉浸光感四层结构：与网格卡片一致的毛玻璃 + 光感渐变 + 边缘高光
  Stack() {
    // 图层1：毛玻璃基底
    Stack()
      .width('100%')
      .height('100%')
      .borderRadius(ImmersiveStyles.cardRadius())
      .backgroundColor(ImmersiveStyles.cardBase(isDark))
      .backdropBlur(ImmersiveStyles.cardBlurRadius())

    // 图层2：表面光感渐变（左上光源 -> 右下微暗角）
    Stack()
      .width('100%')
      .height('100%')
      .borderRadius(ImmersiveStyles.cardRadius())
      .linearGradient({
        angle: 135,
        colors: ImmersiveStyles.cardSurfaceColors(isDark)
      })

    // 图层3：图标 + 名称
    Column({ space: 4 }) {
      Image(dragModel.toolCardItem.icon)
        .width(32)
        .height(32)
        .objectFit(ImageFit.Contain)

      Text(dragModel.toolCardItem.name)
        .fontSize($r('sys.float.Body_L'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.icon_emphasize'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .ellipsisMode(EllipsisMode.END)
        .width('90%')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .padding({ left: 8, right: 8, top: 12, bottom: 12 })
  }
  .size({ width: dragModel.width, height: dragModel.height })
  .clip(true)
  .borderRadius(ImmersiveStyles.cardRadius())
  // 外边缘受光（非对称 rim light，模拟折射衰减）
  .border({ width: 1, color: ImmersiveStyles.cardOuterRim(isDark) })
  // 拖拽抬升态：悬浮越高阴影越深越扩散
  .shadow({
    radius: 24,
    color: isDark ? 'rgba(0, 0, 0, 0.5)' : 'rgba(0, 0, 0, 0.18)',
    offsetX: 0,
    offsetY: 10
  })
}
