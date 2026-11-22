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
import { mediaquery, display, router } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';
import { WallpaperUtil } from '../utils/WallpaperUtil';
import { LightSense } from '../utils/LightSense';
import { PhotoHelper } from '@pura/picker_utils';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { SettingGroup } from "../components/SettingGroup";
import { SettingSwitchItem } from "../components/SettingSwitchItem";
import { GlassButton } from "../components/GlassButton";
import { CommonViewModel } from "../viewmodel/CommonViewModel"
import { GlobalContextHolder } from "../utils/GlobalContextHolder";
import { FloatClockManager } from "../capabilities/floatingclock/FloatClockManager";
import { StressFloatWindowManager } from "../capabilities/floatingstress/StressWindowManager";
import { TargetConstants } from "main/ets/TargetConstants";
import { WebServerUtil } from "../utils/WebServerUtil";
import { FloatWindowUtil } from "../utils/FloatWindowUtil";
import { RouterEntryParams } from "../model/RouterDemoParams";
import { Toast } from "../utils/Toast";

const TAG: string = 'HOME_PAGE';

const TOOLS_TAB_INDEX = 0;
const SETTING_TAB_INDEX = 1;

/**
 * 底部悬浮 Tab 栏尺寸（vp）。
 * 设计目标：始终保持「单手可及」的短宽度，不随握持姿态变宽变窄；
 * 单手握持时整体平移到握持侧，双手/未知握持时居中。
 */
const TAB_BAR_WIDTH: number = 216;
const TAB_BAR_HEIGHT: number = 56;
/** Tab 栏容器高度（悬浮胶囊 + 上下留白） */
const TAB_BAR_AREA_HEIGHT: number = 64;
/** 胶囊离屏幕左右边缘的最小间距（vp） */
const TAB_BAR_SIDE_MARGIN: number = 16;
/** 握持姿态防抖时间（ms）：过滤双手握持时左右手状态来回跳变导致的抖动 */
const GRIP_DEBOUNCE_MS: number = 320;
/** Tab 栏避让高度（vp）：容器高度 + 呼吸间距，内容可滚动到悬浮栏上方 */
const TAB_BAR_CONTENT_INSET: number = 96;

/** 裁切浮层顶部操作条的高度（vp）：按钮点击会冒泡到浮层 onTouch，按此排除按钮区域 */
const TOP_BAR_STRIP_VP: number = 90;

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
  /** AdsKit 广告测试入口：设置页连点彩蛋解锁后持久显示 */
  @Local isAdsKitVisible: boolean = false;
  /** Router 测试入口：默认隐藏，设置页连点彩蛋解锁后持久显示 */
  @Local isRouterDemoVisible: boolean = false;
  /** 模拟游戏入口：默认隐藏，设置页连点彩蛋解锁后持久显示 */
  @Local isGameVisible: boolean = false;
  private adsKitPushInProgress: boolean = false;
  /** 模拟游戏页跳转中：防止快速连点把同一个页面压入多次 */
  private gamePushInProgress: boolean = false;
  /** Router 演示页跳转中：防止快速连点把同一个 router 页面压入多次 */
  private routerDemoPushInProgress: boolean = false;
  // 沉浸光感：跟随系统深/浅色模式
  @Local isDark: boolean = false;
  private themeMq: mediaquery.MediaQueryListener | null = null;
  // 主页壁纸（沉浸光感背景），空字符串表示未设置
  @Local wallpaperPath: string = '';
  /** 壁纸模糊度（0~100，0=不模糊），通过 AppStorage 与 Index 根级壁纸层同步 */
  @Local wallpaperBlur: number = 0;
  /** 全局光感档位（0=关闭 1=柔和 2=标准 3=精致），驱动 Tab 材质/卡片毛玻璃/点光源 */
  @Local lightSense: number = LightSense.LEVEL_EXQUISITE;
  /** 智感握姿：握持侧（0=未知/未握持/双手 1=左手 2=右手），驱动悬浮栏水平位置 */
  @Local gripSide: number = 0;
  /** Tab 栏容器实测宽度（vp）：用于计算胶囊居中/贴边时的精确偏移 */
  @Local barAreaWidth: number = 0;
  private gripSupported: boolean = false;
  private gripCallback: (status: motion.HoldingHandStatus) => void = () => {};
  /** 握持姿态防抖：等姿态稳定后再移动胶囊，避免双手切换时左右跳变 */
  private gripDebounceTimer: number = -1;
  private pendingGripSide: number = 0;
  private lastSettingsClickTime: number = 0;
  private readonly REQUIRED_CLICKS: number = 8;
  private readonly CLICK_WINDOW_MS: number = 5000;
  private msgNum: number = 9999;
  private tabsController: TabsController = new TabsController();
  /** 仅用于底部官方悬浮栏的 Tabs（只显示 TabBar，内容为空） */
  private barTabsController: TabsController = new TabsController();
  @Local listData: ToolCardItem[] = [
    {
      name: 'App Linking 解析',
      desc: '元服务/App链接深度拆解与跳转测试',
      icon: $r('app.media.app_link'),
      onClick: (event: ClickEvent) => {
        HMRouterMgr.push({ pageUrl: PageNames.APP_LINKING_TOOL })
      }
    },
    {
      name: 'H5 页面打开',
      desc: '应用内打开 H5 / https 链接',
      icon: $r('app.media.h5_page'),
      onClick: (event: ClickEvent) => {
        HMRouterMgr.push({ pageUrl: PageNames.H5_PAGE })
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
      icon: $r('app.media.web_server'),
      onClick: () => {
        HMRouterMgr.push({ pageUrl: PageNames.LOCAL_WEB_PAGE })
      }
    },
    {
      name: '字符串转换',
      desc: 'Base64、Url编解码',
      icon: $r('app.media.string_convert'),
      onClick: (event) => {
        HMRouterMgr.push({ pageUrl: PageNames.STR_CONVERT })
      }
    }
    ,
    {
      name: 'Markdown',
      desc: 'Markdown 编辑、预览与本地保存',
      icon: $r('app.media.markdown_notes'),
      onClick: () => {
        HMRouterMgr.push({ pageUrl: PageNames.MARKDOWN_NOTES_PAGE })
      }
    }
    ,
    {
      name: '二维码生成',
      desc: '文本生成二维码，支持保存相册',
      icon: $r('app.media.qr_code'),
      onClick: (event: ClickEvent) => {
        HMRouterMgr.push({ pageUrl: PageNames.QR_CODE_PAGE })
      }
    }
    ,
    {
      name: 'HDC 调试',
      desc: '本地 HDC 终端，直连 hdcd 调试本机',
      icon: $r('app.media.hdc_debug'),
      onClick: (event: ClickEvent) => {
        HMRouterMgr.push({ pageUrl: PageNames.HDC_DEBUG_PAGE })
      }
    }
  ,
  {
    name: 'Router 页面跳转',
    desc: '系统 router 页面栈跳转演示',
    icon: $r('app.media.router_demo'),
    onClick: () => {
      this.openRouterDemo();
    }
  }
  ,
  {
    name: 'AdsKit广告测试',
    desc: '测试开屏、横幅、插屏、激励与原生广告',
    icon: $r('app.media.hdc_debug'),
    onClick: () => {
      if (this.adsKitPushInProgress) {
        return;
      }
      this.adsKitPushInProgress = true;
      HMRouterMgr.push({ pageUrl: PageNames.ADS_KIT_PAGE });
      setTimeout(() => {
        this.adsKitPushInProgress = false;
      }, 500);
    }
  }
,
  {
    name: 'Ads Hsp广告',
    desc: 'HSP 广告接入测试，复用广告位配置与加载展示',
    icon: $r('app.media.hdc_debug'),
    onClick: () => {
      if (this.adsKitPushInProgress) { return; }
      this.adsKitPushInProgress = true;
      HMRouterMgr.push({ pageUrl: PageNames.ADS_HSP_PAGE });
      setTimeout(() => { this.adsKitPushInProgress = false; }, 500);
    }
  }
,
  {
    name: '模拟游戏',
    desc: '原生 GL 三消，验证游戏广告变现',
    icon: $r('app.media.game_match3'),
    onClick: () => {
      if (this.gamePushInProgress) { return; }
      this.gamePushInProgress = true;
      HMRouterMgr.push({ pageUrl: PageNames.GAME_DEMO_PAGE });
      setTimeout(() => { this.gamePushInProgress = false; }, 500);
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
  /** 图片尺寸回调完成、可交互（@Local：异步就绪后需刷新确定按钮的 enabled 状态） */
  @Local cropReady: boolean = false;
  /** 裁切确认中（防止重复点击） */
  private cropBusy: boolean = false;
  // ===== 手动触摸手势状态（不用 PanGesture/PinchGesture 识别器） =====
  /** 0=无手势 1=单指平移 2=双指缩放 */
  private touchMode: number = 0;
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  private panBaseOffsetX: number = 0;
  private panBaseOffsetY: number = 0;
  private pinchStartDist: number = 0;
  private pinchBaseScale: number = 1;
  // ===== 内容区壁纸全屏对齐（与 Index 根级壁纸共用同一画面，消除状态栏接缝） =====
  /** 壁纸层高度（px，= 全屏高） */
  private wallpaperLayerH: number = 2880;
  /** 壁纸层向上偏移（px，= 状态栏高，使 pm 原点与屏幕原点对齐） */
  private wallpaperLayerY: number = 0;

  aboutToAppear(): void {
    // 开发者入口显隐策略版本 2：Router / AdsKit / Ads Hsp / 模拟游戏默认隐藏。
    // 一次性清理历史版本遗留的解锁标记，避免老用户升级后仍然看到这些入口；
    // 清理后用户仍可通过「设置页 5 秒内连点 8 次」重新解锁，解锁状态会继续持久化。
    if (PreferencesUtil.getNumberSync(SpKeys.DEV_ENTRY_VISIBILITY_VERSION, 0) < 2) {
      PreferencesUtil.putSync(SpKeys.ENABLE_ADS_KIT_VISIBLE, false);
      PreferencesUtil.putSync(SpKeys.ENABLE_ROUTER_DEMO_VISIBLE, false);
      PreferencesUtil.putSync(SpKeys.ENABLE_GAME_DEMO_VISIBLE, false);
      PreferencesUtil.putSync(SpKeys.DEV_ENTRY_VISIBILITY_VERSION, 2);
    }
    // HDC 调试入口可见性：
    //   dev  —— 默认可见
    //   AG   —— 默认隐藏，需「设置页连点彩蛋」写入 ENABLE_HDC_VISIBLE 后出现
    // HDC_DEBUG_ENABLED 只作为显式总闸（默认 true），不参与 AG 的隐藏规则。
    this.isHdcVisible = TargetConstants.HDC_DEBUG_ENABLED &&
      (!TargetConstants.IS_AG_TARGET ||
        PreferencesUtil.getBooleanSync(SpKeys.ENABLE_HDC_VISIBLE, false));
    this.isAdsKitVisible = PreferencesUtil.getBooleanSync(SpKeys.ENABLE_ADS_KIT_VISIBLE, false);
    // Router 测试入口同样默认隐藏，需要通过设置页连点彩蛋手动解锁
    this.isRouterDemoVisible = PreferencesUtil.getBooleanSync(SpKeys.ENABLE_ROUTER_DEMO_VISIBLE, false);
    // 模拟游戏入口：所有 target 默认隐藏，靠设置页连点彩蛋解锁
    this.isGameVisible = PreferencesUtil.getBooleanSync(SpKeys.ENABLE_GAME_DEMO_VISIBLE, false);
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
    // Tab 栏宽度初值（vp）：首帧 onAreaChange 之前也能按“居中”正确摆放
    this.barAreaWidth = this.screenWidthVp();
    // 智感握姿：订阅握持姿态变化（宽度固定，仅左右位置跟随握持侧）
    this.initGripListener();
    // 恢复已设置的壁纸
    this.wallpaperPath = WallpaperUtil.getPath();
    this.wallpaperBlur = WallpaperUtil.getBlur();
    this.lightSense = LightSense.getLevel();
    this.loadWallpaperPm();
  }

  /** 当前屏幕宽度（vp，异常时按 360 兜底） */
  private screenWidthVp(): number {
    try {
      const d = display.getDefaultDisplaySync();
      const density = d.densityDPI / 160;
      return density > 0 ? d.width / density : 360;
    } catch (e) {
      return 360;
    }
  }

  /**
   * 工具箱入口：从 HMRouter 页面跳到一个由系统 router 管理的页面。
   *
   * 这里刻意用 router.pushUrl 而不是 HMRouterMgr.push，用来演示
   * router 页面栈与 HMNavigation 的 NavPathStack 是两套独立栈：
   * router 页面进出只会让 Index 走 onPageHide/onPageShow，
   * 不会破坏 HMNavigation 内部状态，返回后 HomePage 原样保留。
   */
  private openRouterDemo(): void {
    if (this.routerDemoPushInProgress) {
      return;
    }
    this.routerDemoPushInProgress = true;
    setTimeout(() => {
      this.routerDemoPushInProgress = false;
    }, 500);
    const params: RouterEntryParams = new RouterEntryParams();
    params.from = 'pages/Index (HomePage)';
    params.tool = 'Router 页面跳转';
    params.ts = Date.now();
    router.pushUrl({ url: PageNames.ROUTER_DEMO_PAGE, params: params })
      .then(() => {
        hilog.info(0x0000, TAG, 'router.pushUrl -> %{public}s ok', PageNames.ROUTER_DEMO_PAGE);
      })
      .catch((err: BusinessError) => {
        hilog.error(0x0000, TAG, 'router.pushUrl failed: %{public}s', JSON.stringify(err));
        Toast.show(`router 跳转失败：${err.code}`);
      });
  }

  /**
   * Tab 栏胶囊的左偏移（vp）。
   * 宽度永远固定为 TAB_BAR_WIDTH：不会随握持姿态变宽变窄；
   * 单手握持只改变水平位置（左手贴左、右手贴右），双手/未知居中。
   */
  private tabBarLeftMargin(): number {
    const areaW = this.barAreaWidth;
    if (areaW <= 0) {
      return TAB_BAR_SIDE_MARGIN;
    }
    const minLeft = TAB_BAR_SIDE_MARGIN;
    const maxLeft = Math.max(minLeft, areaW - TAB_BAR_WIDTH - TAB_BAR_SIDE_MARGIN);
    if (this.gripSide === 1) {
      return minLeft;
    }
    if (this.gripSide === 2) {
      return maxLeft;
    }
    const centered = (areaW - TAB_BAR_WIDTH) / 2;
    return Math.min(Math.max(centered, 0), maxLeft);
  }

  /**
   * 订阅智感握姿（握持姿态变化）。
   *
   * - `HoldingHandStatus` / `holdingHandChanged` 自 API 20 才有，低版本直接不订阅，
   *   悬浮栏保持居中（也不会访问不存在的枚举导致 crash）。
   * - 宽度固定，只有水平位置跟随握持侧；单手 → 贴握持侧，双手/未知 → 居中。
   * - 握姿事件在双手切换时可能来回跳（左/右手状态交替），用 320ms 防抖 +
   *   “与当前值相同则忽略”避免胶囊左右抖动。
   */
  private initGripListener(): void {
    try {
      // API 20 以下没有 HoldingHandStatus，直接保持居中
      if (LightSense.sdkApiVersion() < 20) {
        hilog.info(0x0000, TAG, 'grip: sdk < 20, keep tab bar centered');
        return;
      }
      if (!canIUse('SystemCapability.MultimodalAwareness.Motion')) {
        hilog.info(0x0000, TAG, 'grip: Motion capability not supported, keep tab bar centered');
        return;
      }
      this.gripCallback = (status: motion.HoldingHandStatus) => {
        let side: number = 0;
        if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
          side = 1;
        } else if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
          side = 2;
        }
        // BOTH_HANDS_HELD / 未知状态统一按 0 处理：居中
        this.scheduleGripSide(side);
      };
      motion.on('holdingHandChanged', this.gripCallback);
      this.gripSupported = true;
      hilog.info(0x0000, TAG, 'grip listener subscribed');
    } catch (e) {
      hilog.info(0x0000, TAG, 'initGripListener failed: ' + JSON.stringify(e));
      this.gripSupported = false;
    }
  }

  /** 握姿防抖：姿态稳定 GRIP_DEBOUNCE_MS 后才移动胶囊 */
  private scheduleGripSide(side: number): void {
    if (side === this.pendingGripSide) {
      return;
    }
    this.pendingGripSide = side;
    if (this.gripDebounceTimer !== -1) {
      clearTimeout(this.gripDebounceTimer);
    }
    this.gripDebounceTimer = setTimeout(() => {
      this.gripDebounceTimer = -1;
      this.applyGripSide(this.pendingGripSide);
    }, GRIP_DEBOUNCE_MS);
    hilog.info(0x0000, TAG, 'grip pending -> side=%{public}d', side);
  }

  /** 应用握持侧：只改水平位置，不改宽度；用动画平滑滑过去 */
  private applyGripSide(side: number): void {
    if (side === this.gripSide) {
      return;
    }
    animateTo({ duration: 260, curve: Curve.EaseInOut }, () => {
      this.gripSide = side;
    });
    hilog.info(0x0000, TAG, 'grip applied -> side=%{public}d', side);
  }

  /** 退订智感握姿（页面销毁时释放） */
  private releaseGripListener(): void {
    if (this.gripDebounceTimer !== -1) {
      clearTimeout(this.gripDebounceTimer);
      this.gripDebounceTimer = -1;
    }
    if (!this.gripSupported) {
      return;
    }
    try {
      motion.off('holdingHandChanged', this.gripCallback);
    } catch (e) {
      hilog.info(0x0000, TAG, 'releaseGripListener failed: ' + JSON.stringify(e));
    }
    this.gripSupported = false;
  }

  aboutToDisappear(): void {
    this.themeMq?.off('change');
    this.themeMq = null;
    this.releaseGripListener();
  }

  /** 订阅系统深/浅色模式变化，驱动沉浸光感参数切换 */
  private initThemeListener(): void {
    try {
      this.themeMq = this.getUIContext().getMediaQuery().matchMediaSync('(dark-mode: true)');
      this.isDark = this.themeMq.matches;
      this.themeMq.on('change', (event: mediaquery.MediaQueryResult) => {
        this.isDark = event.matches;
      });
    } catch (e) {
      hilog.info(0x0000, TAG, 'initThemeListener failed: ' + JSON.stringify(e));
      this.isDark = false;
    }
  }

  /** 加载内容区壁纸 PixelMap（盖住 NavDestination 白底，与 Index 根级壁纸同画面无缝衔接） */
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
    // 与 Index 根级壁纸相同的全屏几何：高度=全屏高，向上偏移=状态栏高，
    // 使本层渲染的画面与根级逐像素一致，状态栏与内容区不再出现两张错位的壁纸
    this.wallpaperLayerH = h;
    this.wallpaperLayerY = AppUtil.getStatusBarHeight();
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
          hilog.info(0x0000, TAG, 'getImageSize ok (%{public}d×%{public}d)', size.width, size.height);
          this.initCropBase(size.width, size.height);
        } else {
          hilog.info(0x0000, TAG, 'getImageSize failed, rely on onComplete fallback');
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
    this.touchMode = 0;
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
      hilog.info(0x0000, TAG,
        'crop ready d=%{public}s canvas=(%{public}s,%{public}s) orig=(%{public}d,%{public}d) base=(%{public}s,%{public}s) scale=%{public}s',
        d.toFixed(1), cw.toFixed(1), ch.toFixed(1), this.origW, this.origH,
        this.cropBaseW.toFixed(1), this.cropBaseH.toFixed(1), this.cropBaseScale.toFixed(2));
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
    // onAreaChange 的宽高单位是 vp，而 cropW/cropH 全链路按 px 语义使用（canvasVp 再除以密度），
    // 必须在此处乘以密度转成 px，否则画布会被当作真实尺寸的 1/d，基准缩放和裁切区域全部偏小
    const d = this.densityPxPerVp();
    this.cropW = w * d;
    this.cropH = h * d;
    this.canvasConfirmed = true;
    hilog.info(0x0000, TAG, 'crop area vp=(%{public}s,%{public}s) px=(%{public}s,%{public}s)',
      w.toFixed(1), h.toFixed(1), this.cropW.toFixed(1), this.cropH.toFixed(1));
    this.computeCropBase();
  }

  /** 两指之间的直线距离（vp，用窗口坐标，与组件位移/变换无关） */
  private fingerDist(a: TouchObject, b: TouchObject): number {
    const dx = a.windowX - b.windowX;
    const dy = a.windowY - b.windowY;
    return Math.sqrt(dx * dx + dy * dy);
  }

  /**
   * 手动实现裁切图片的平移/缩放（替代 PanGesture/PinchGesture）：
   * 单指拖动平移，双指以画布中心为锚点缩放（1~5 倍）。
   * onTouch 直接收到原始触摸流，不依赖手势识别器，稳定可靠。
   */
  private handleCropTouch(event: TouchEvent): void {
    if (!this.cropReady) {
      return;
    }
    const touches = event.touches;
    if (event.type === TouchType.Down) {
      // 顶部操作条（取消/确定按钮）区域：按钮点击会冒泡到这里，跳过避免误启动手势
      if (touches.length > 0 && touches[0].windowY < TOP_BAR_STRIP_VP) {
        return;
      }
      if (touches.length >= 2) {
        // 双指：进入缩放模式
        this.touchMode = 2;
        this.pinchStartDist = this.fingerDist(touches[0], touches[1]);
        this.pinchBaseScale = this.cropScale;
        hilog.info(0x0000, TAG, 'crop touch pinch begin dist=%{public}s scale=%{public}s',
          this.pinchStartDist.toFixed(1), this.cropScale.toFixed(2));
      } else if (touches.length === 1) {
        // 单指：进入平移模式
        this.touchMode = 1;
        this.touchStartX = touches[0].windowX;
        this.touchStartY = touches[0].windowY;
        this.panBaseOffsetX = this.cropOffsetX;
        this.panBaseOffsetY = this.cropOffsetY;
        hilog.info(0x0000, TAG, 'crop touch pan begin at=(%{public}s,%{public}s)',
          this.touchStartX.toFixed(1), this.touchStartY.toFixed(1));
      }
    } else if (event.type === TouchType.Move) {
      if (this.touchMode === 1 && touches.length === 1) {
        // 单指平移：内容跟随手指移动（拖右 -> 内容右移）
        const dx = touches[0].windowX - this.touchStartX;
        const dy = touches[0].windowY - this.touchStartY;
        const canvas = this.canvasVp();
        const maxX = Math.max(0, this.cropBaseW * this.cropScale - canvas.cw);
        const maxY = Math.max(0, this.cropBaseH * this.cropScale - canvas.ch);
        this.cropOffsetX = Math.min(Math.max(this.panBaseOffsetX - dx, 0), maxX);
        this.cropOffsetY = Math.min(Math.max(this.panBaseOffsetY - dy, 0), maxY);
      } else if (this.touchMode === 2 && touches.length >= 2) {
        // 双指缩放：以画布中心为锚点，偏移同步缩放避免内容跳变
        const dist = this.fingerDist(touches[0], touches[1]);
        if (this.pinchStartDist > 0) {
          const newScale = Math.min(Math.max(this.pinchBaseScale * dist / this.pinchStartDist, 1), 5);
          const k = newScale / this.cropScale;
          const canvas = this.canvasVp();
          const cw = canvas.cw;
          const ch = canvas.ch;
          const cx = this.cropOffsetX + cw / 2;
          const cy = this.cropOffsetY + ch / 2;
          this.cropScale = newScale;
          const maxX = Math.max(0, this.cropBaseW * newScale - cw);
          const maxY = Math.max(0, this.cropBaseH * newScale - ch);
          this.cropOffsetX = Math.min(Math.max(cx * k - cw / 2, 0), maxX);
          this.cropOffsetY = Math.min(Math.max(cy * k - ch / 2, 0), maxY);
        }
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.touchMode = 0;
    }
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
      hilog.info(0x0000, TAG,
        'crop confirm scale=%{public}s region=(%{public}s,%{public}s %{public}s×%{public}s) out=(%{public}s×%{public}s)',
        scale.toFixed(2), region.x.toFixed(1), region.y.toFixed(1),
        region.size.width.toFixed(1), region.size.height.toFixed(1),
        this.cropW.toFixed(1), this.cropH.toFixed(1));
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

  /** 调整壁纸模糊度：本地状态 + 持久化 + 同步 Index 根级壁纸层 */
  private updateWallpaperBlur(value: number): void {
    const v = Math.min(Math.max(Math.round(value), 0), 100);
    this.wallpaperBlur = v;
    try {
      PreferencesUtil.putSync(SpKeys.WALLPAPER_BLUR, v);
    } catch (e) {
      console.error(`[WallpaperUtil] put blur failed: ${JSON.stringify(e)}`);
    }
    AppStorage.setOrCreate<number>('WallpaperBlur', v);
  }

  /** 调整全局光感档位：本地状态 + 持久化（Tab 材质/卡片毛玻璃按档位自动跟随） */
  private updateLightSense(value: number): void {
    const v = Math.min(Math.max(Math.round(value), 0), 3);
    this.lightSense = v;
    LightSense.setLevel(v);
  }

  /** 内容底部避让（vp）：盖住悬浮 Tab 栏 + 呼吸间距，保证最后一行能滚到胶囊上方 */
  private getContentBottomInset(): number {
    return TAB_BAR_CONTENT_INSET;
  }

  /** Tab 点击统一处理：切换 + 设置页连点彩蛋（用于手绘兜底胶囊；官方 Tabs 分支由 onChange 同步） */
  private handleTabClick(index: number): void {
    this.currentIndex = index;
    this.handleSettingsEasterEgg(index);
  }

  /** 设置页连点彩蛋：不修改 currentIndex（供 HDS 分支的 onTabBarClick 单独调用，避免映射竞态） */
  private handleSettingsEasterEgg(index: number): void {
    if (index !== SETTING_TAB_INDEX) {
      return;
    }
    let now: number = Date.now();
    if (now - this.lastSettingsClickTime > this.CLICK_WINDOW_MS) {
      this.settingsClickCount = 0;
    }
    this.lastSettingsClickTime = now;
    this.settingsClickCount++;
    if (this.settingsClickCount >= this.REQUIRED_CLICKS) {
      PreferencesUtil.put(SpKeys.ENABLE_SCAN_PARSE, true);
      PreferencesUtil.put(SpKeys.ENABLE_HDC_VISIBLE, true);
      PreferencesUtil.put(SpKeys.ENABLE_ADS_KIT_VISIBLE, true);
      PreferencesUtil.put(SpKeys.ENABLE_ROUTER_DEMO_VISIBLE, true);
      PreferencesUtil.put(SpKeys.ENABLE_GAME_DEMO_VISIBLE, true);
      this.isHdcVisible = true;
      this.isAdsKitVisible = true;
      this.isRouterDemoVisible = true;
      this.isGameVisible = true;
      promptAction.showToast({ message: '扫码解析 + HDC调试 + AdsKit + Router + 模拟游戏已启用', duration: 1500 });
      this.settingsClickCount = 0;
    }
  }

  /** 当前实际渲染的工具列表；拖拽索引必须与此列表保持一致。 */
  private visibleTools(): ToolCardItem[] {
    return this.listData.filter((item: ToolCardItem) =>
      !(item.name === 'HDC 调试' && !this.isHdcVisible) &&
      !(item.name === 'Router 页面跳转' && !this.isRouterDemoVisible) &&
      !(item.name === '模拟游戏' && !this.isGameVisible) &&
      !((item.name === 'AdsKit广告测试' || item.name === 'Ads Hsp广告') && !this.isAdsKitVisible));
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

  /**
   * 底部 Tab 栏容器：固定高度、整宽，内部胶囊按握持侧水平摆放。
   *
   * 这里不再把整宽自定义栏塞进 Tabs 的 tabBar（那样整条标签区域都会响应
   * “点击切页”，点胶囊外面也会跳回工具箱），而是：
   * - 内容用一条隐藏 TabBar 的 Tabs 负责滑动/页面切换；
   * - 底部单独放一条 216vp 宽的“只为材质而生”的 Tabs（官方 barFloatingStyle +
   *   systemMaterial），它只占胶囊本身的范围，点外面不会误触。
   */
  @Builder
  tabBarArea() {
    Row() {
      if (this.useOfficialBar()) {
        this.officialBarTabs()
      } else {
        this.glassBar()
      }
    }
    .width('100%')
    .height(TAB_BAR_AREA_HEIGHT)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const w = newValue.width as number;
      if (w > 0 && Math.abs(w - this.barAreaWidth) > 1) {
        this.barAreaWidth = w;
      }
    })
    // 胶囊之外的区域不拦截内容区触摸
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /** 是否使用官方沉浸光感悬浮栏（API 26+、设备支持、且光感未关闭） */
  private useOfficialBar(): boolean {
    return this.lightSense > LightSense.LEVEL_OFF && LightSense.supportsSystemMaterial();
  }

  /**
   * 官方沉浸光感悬浮栏：底层 Tabs 只负责官方 systemMaterial 背板；
   * 上层 overlay 负责「滑动玻璃胶囊 + 图标文字 + 点击」。
   *
   * 这样选中态不是两个独立背景的淡入淡出，而是一整块玻璃胶囊
   * 从左侧入口平滑滑到右侧入口。
   */
  @Builder
  officialBarTabs() {
    Stack() {
      Tabs({
        barPosition: BarPosition.End,
        controller: this.barTabsController
      }) {
        TabContent() {
          Row().width(0).height(0).backgroundColor(Color.Transparent)
        }
        .backgroundColor(Color.Transparent)
        .tabBar(this.emptyTabBar())

        TabContent() {
          Row().width(0).height(0).backgroundColor(Color.Transparent)
        }
        .backgroundColor(Color.Transparent)
        .tabBar(this.emptyTabBar())
      }
      .width(TAB_BAR_WIDTH)
      .height(TAB_BAR_AREA_HEIGHT)
      .barMode(BarMode.Fixed)
      .barHeight(TAB_BAR_HEIGHT)
      // 透明化 Tabs 自身背景与 TabBar 背板，否则 216×64 的 Tabs 盒子会在胶囊
      // 周围露出一块直角白底（右侧/底部看起来像“直角边”）
      .backgroundColor(Color.Transparent)
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)
      // 悬浮样式要求：横向 + BarPosition.End + barOverlap(true)
      .barOverlap(true)
      .barFloatingStyle({
        barWidth: {
          smallBarWidth: TAB_BAR_WIDTH,
          mediumBarWidth: TAB_BAR_WIDTH,
          largeBarWidth: TAB_BAR_WIDTH
        },
        barSideMargin: 0,
        barBottomMargin: 4,
        // 关掉官方悬浮栏自带的底部渐变遮罩：它是一块直角矩形，
        // 会在胶囊周围露出白色/灰色直角边（尤其设置壁纸后非常明显）
        maskColor: Color.Transparent,
        maskHeight: 0,
        adaptToHandedness: false,
        systemMaterial: LightSense.tabSystemMaterial(this.lightSense)
      })

      // 与官方 bar 的标签内容区对齐：胶囊 216 宽，左右各 12，两个入口各 96
      Stack({ alignContent: Alignment.TopStart }) {
        this.selectedGlassPill(92, 2, 96)

        Row() {
          this.officialBarItem(TOOLS_TAB_INDEX, $r('app.string.tools_tab'), $r('app.media.settings'))
          this.officialBarItem(SETTING_TAB_INDEX, $r('app.string.setting_tab'), $r('app.media.globalSetting'))
        }
        .width(192)
        .height(48)
      }
      .width(192)
      .height(48)
      .position({ x: 12, y: 8 })
    }
    .width(TAB_BAR_WIDTH)
    .height(TAB_BAR_AREA_HEIGHT)
    .margin({ left: this.tabBarLeftMargin() })
  }

  /**
   * 滑动选中胶囊：蓝玻璃 + 白 rim + 光晕，位置随 currentIndex 平移。
   * @param pillWidth 胶囊宽度（官方栏 92，手绘兜底栏 100）
   * @param leftInset 左侧内缩（2vp）
   * @param step 两个入口之间的位移（官方栏 96，手绘兜底栏 104）
   */
  @Builder
  selectedGlassPill(pillWidth: number, leftInset: number, step: number) {
    Row()
      .width(pillWidth)
      .height(48)
      .borderRadius(24)
      // 小面积蓝色玻璃：backdropBlur 不带系统白色材质染色，
      // 蓝色底 + 左上高光 + 白 rim，选中态才是“蓝玻璃”而不是白贴片
      .backdropBlur(this.lightSense > LightSense.LEVEL_OFF ? 8 : 0)
      .backgroundColor(ImmersiveStyles.tabSelectedBg(this.isDark))
      .linearGradient({
        angle: 135,
        colors: this.lightSense > LightSense.LEVEL_OFF ? (this.isDark ? [
          ['rgba(255, 255, 255, 0.22)', 0.0],
          ['rgba(96, 165, 250, 0.06)', 0.5],
          ['rgba(96, 165, 250, 0.14)', 1.0]
        ] : [
          ['rgba(255, 255, 255, 0.55)', 0.0],
          ['rgba(10, 89, 247, 0.04)', 0.5],
          ['rgba(10, 89, 247, 0.12)', 1.0]
        ]) : [
          ['rgba(0, 0, 0, 0)', 0.0],
          ['rgba(0, 0, 0, 0)', 1.0]
        ]
      })
      .border({
        width: 1,
        color: this.lightSense > LightSense.LEVEL_OFF ?
          (this.isDark ? 'rgba(255, 255, 255, 0.45)' : 'rgba(255, 255, 255, 0.9)') : Color.Transparent
      })
      .shadow({
        radius: 10,
        color: this.lightSense > LightSense.LEVEL_OFF ?
          ImmersiveStyles.tabSelectedGlow(this.isDark) : Color.Transparent,
        offsetX: 0,
        offsetY: 0
      })
      // 300ms 摩擦曲线：胶囊从左侧入口平滑滑到右侧入口
      .translate({ x: this.currentIndex === SETTING_TAB_INDEX ? leftInset + step : leftInset, y: 0 })
      .animation({ duration: 300, curve: Curve.Friction })
  }

  /** 官方栏里的单个透明入口：点击切换内容，视觉由下面的滑动胶囊承担 */
  @Builder
  officialBarItem(index: number, title: Resource, icon: Resource) {
    Column({ space: 2 }) {
      this.barItemContent(index, title, icon)
    }
    .width(96)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.handleTabClick(index);
      this.tabsController.changeIndex(index);
    })
  }

  /** 图标 + 文字的公共内容（官方栏/手绘兜底栏共用） */
  @Builder
  barItemContent(index: number, title: Resource, icon: Resource) {
    Image(icon)
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

  /**
   * 低版本 / 光感关闭时的兜底悬浮胶囊：
   * 手绘玻璃配方（backgroundBlurStyle + 光感渐变 + rim + 点光源）。
   */
  @Builder
  glassBar() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 手绘栏同样用一块滑动胶囊，两个入口只是透明点击区
      this.selectedGlassPill(100, 2, 104)

      Row() {
        this.glassTabItem(TOOLS_TAB_INDEX, $r('app.string.tools_tab'), $r('app.media.settings'))
        this.glassTabItem(SETTING_TAB_INDEX, $r('app.string.setting_tab'), $r('app.media.globalSetting'))
      }
      .width(208)
      .height(48)
    }
    .width(TAB_BAR_WIDTH)
    .height(TAB_BAR_HEIGHT)
    .padding(4)
    .borderRadius(TAB_BAR_HEIGHT / 2)
    .clip(true)
    .backgroundBlurStyle(ImmersiveStyles.tabBarBlurStyle())
    .backgroundColor(ImmersiveStyles.tabBarBase(this.isDark))
    .linearGradient({
      angle: 135,
      colors: ImmersiveStyles.cardSurfaceColors(this.isDark)
    })
    .visualEffect(LightSense.lightVisualEffect())
    .border({ width: 1, color: ImmersiveStyles.cardOuterRim(this.isDark) })
    .shadow({
      radius: 20,
      color: ImmersiveStyles.cardShadow(this.isDark),
      offsetX: 0,
      offsetY: 8
    })
    .margin({ left: this.tabBarLeftMargin(), top: (TAB_BAR_AREA_HEIGHT - TAB_BAR_HEIGHT) / 2 })
    .animation({ duration: 260, curve: Curve.EaseInOut })
  }

  @Builder
  glassTabItem(index: number, title: Resource, icon: Resource) {
    Column({ space: 2 }) {
      this.barItemContent(index, title, icon)
    }
    .width(104)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.handleTabClick(index);
      this.tabsController.changeIndex(index);
    })
  }

  /** Tab 内容体（两个页签共用）：内容 + 壁纸透明背景 */
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

  /**
   * 主 Tab 容器：
   * - 内容 Tabs 隐藏系统 TabBar，负责页面内容与左右滑动；
   * - 底部叠加一条独立的小宽度 Tabs/胶囊，负责沉浸光感与点击；
   * - 内容底部留 96vp，最后一行可以滚到胶囊上方。
   */
  @Builder
  mainTabs() {
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
      .barHeight(0)
      .barMode(BarMode.Fixed)
      // 手势滑动一开始就切换胶囊选中态，让“页面滑动”和“胶囊滑动”同时发生
      .onAnimationStart((_index: number, targetIndex: number) => {
        if (targetIndex !== this.currentIndex) {
          this.currentIndex = targetIndex;
        }
      })
      .onChange((index: number) => {
        if (index !== this.currentIndex) {
          // 内容滑动/点击切换后，overlay 的滑动胶囊会自动平移到新位置
          this.currentIndex = index;
        }
      })

      this.tabBarArea()
    }
    .width('100%')
    .height('100%')
    // 页面底色必须一直铺到系统手势条上沿：否则 Stack 的底部 padding 区域会
    // 露出 NavDestination 的白色底，形成一条“底部没有沉浸”的白条。
    // 有壁纸时透明让壁纸透出，无壁纸时与内容区同一灰底。
    .backgroundColor(this.wallpaperPath === '' ? $r('sys.color.background_secondary') : Color.Transparent)
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
          // 深色/浅色模式可读性：阴影颜色与文字相反
          .textShadow(ImmersiveStyles.textShadow(this.isDark))

        // 工具箱设置项：与工具箱卡片背景保持一致的沉浸光感配方
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
          .visibility(!TargetConstants.IS_AG_TARGET ? Visibility.Visible:Visibility.None)
          // 深色/浅色模式可读性：阴影颜色与文字相反
          .textShadow(ImmersiveStyles.textShadow(this.isDark))

        SettingGroup({
          vis: !TargetConstants.IS_AG_TARGET
        }) {
          SettingSwitchItem({
            title: '启用悬浮时钟',
            isOn: CommonViewModel.getInstance().floatingClockOn,
            vis: !TargetConstants.IS_AG_TARGET,
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
            vis: !TargetConstants.IS_AG_TARGET,
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
          // 深色/浅色模式可读性：阴影颜色与文字相反
          .textShadow(ImmersiveStyles.textShadow(this.isDark))

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
          // 深色/浅色模式可读性：阴影颜色与文字相反
          .textShadow(ImmersiveStyles.textShadow(this.isDark))

        SettingGroup() {
          ListItem() {
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text('设置壁纸')
                  .fontColor($r('sys.color.font_primary'))
                  .fontSize('16vp')
                  .fontWeight(FontWeight.Medium)
                  // 深色/浅色模式可读性：阴影颜色与文字相反
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))

                Text('选择图片作为主页背景，毛玻璃卡片与悬浮导航将实时呈现光感效果')
                  .fontSize('12vp')
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              if (this.wallpaperPath !== '') {
                // 直接用 PixelMap 做缩略图：Image 直接加载沙箱路径（含 file:// 前缀）在本环境不可靠，
                // 与壁纸背景共用已解码的 wallpaperPm，避免空白缩略图；模糊效果与主壁纸一致
                Image(this.wallpaperPm)
                  .width('44vp')
                  .height('44vp')
                  .borderRadius('8vp')
                  .objectFit(ImageFit.Cover)
                  .blur(WallpaperUtil.blurRadius(this.wallpaperBlur))
                  .margin({ right: '8vp' })

                GlassButton({
                  label: '恢复默认',
                  btnHeight: 32,
                  fontSize: 12,
                  padX: 16,
                  onAction: () => { this.removeWallpaper(); }
                })
              } else {
                GlassButton({
                  label: '选择图片',
                  btnHeight: 32,
                  fontSize: 12,
                  padX: 16,
                  onAction: () => { this.pickWallpaper(); }
                })
              }
            }
            .width('100%')
            .height('64vp')
            .justifyContent(FlexAlign.SpaceBetween)
            .padding({ left: '16vp', right: '16vp' })
          }
          ListItem() {
            Row({ space: 12 }) {
              Text('模糊度')
                .fontColor($r('sys.color.font_primary'))
                .fontSize('16vp')
                .fontWeight(FontWeight.Medium)
                .layoutWeight(1)
                // 深色/浅色模式可读性：阴影颜色与文字相反
                .textShadow(ImmersiveStyles.textShadow(this.isDark))

              Text(this.wallpaperBlur <= 0 ? '无' : `${Math.round(this.wallpaperBlur)}%`)
                .fontSize('13vp')
                .fontColor($r('sys.color.font_secondary'))
                .textShadow(ImmersiveStyles.textShadow(this.isDark))

              Slider({
                value: this.wallpaperBlur,
                min: 0,
                max: 100,
                step: 5,
                style: SliderStyle.OutSet
              })
                .width('160vp')
                .onChange((value: number, mode: SliderChangeMode) => {
                  this.updateWallpaperBlur(value);
                })
            }
            .width('100%')
            .height('64vp')
            .padding({ left: '16vp', right: '16vp' })
          }
          .visibility(this.wallpaperPath !== '' ? Visibility.Visible : Visibility.None)
          ListItem() {
            Row({ space: 12 }) {
              Text('光感')
                .fontColor($r('sys.color.font_primary'))
                .fontSize('16vp')
                .fontWeight(FontWeight.Medium)
                .layoutWeight(1)
                // 深色/浅色模式可读性：阴影颜色与文字相反
                .textShadow(ImmersiveStyles.textShadow(this.isDark))

              Text(LightSense.levelName(this.lightSense))
                .fontSize('13vp')
                .fontColor($r('sys.color.font_secondary'))
                .textShadow(ImmersiveStyles.textShadow(this.isDark))

              Slider({
                value: this.lightSense,
                min: 0,
                max: 3,
                step: 1,
                style: SliderStyle.OutSet
              })
                .width('160vp')
                .onChange((value: number, mode: SliderChangeMode) => {
                  this.updateLightSense(value);
                })
            }
            .width('100%')
            .height('64vp')
            .padding({ left: '16vp', right: '16vp' })
          }
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
      // 可平移/缩放的图片（尺寸与偏移均用 vp，与画布一致）。
      // position(0,0) 固定布局原点：Stack 默认居中会把大图放到负坐标原点，
      // 叠加 translate 后可视区域会偏到图片最右端（与确认裁切区域错位），
      // 且负坐标原点的子组件命中测试为空（手势/触摸全部失效）。
      Image(this.cropUri)
        .position({ x: 0, y: 0 })
        .width(this.cropBaseW * this.cropScale)
        .height(this.cropBaseH * this.cropScale)
        .translate({ x: -this.cropOffsetX, y: -this.cropOffsetY })
        .onComplete((event) => {
          // 回调参数类型由 onComplete 签名推断（匿名对象类型，不能显式标注；参数可选）
          if (!event) {
            return;
          }
          // getImageSize 已拿到原图尺寸时忽略 onComplete（它只是兜底，
          // 且其 width/height 单位可能与原图像素不一致，重复计算无意义）
          if (this.origW > 0) {
            return;
          }
          this.initCropBase(event.width, event.height);
        })
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

      // 顶部操作条（放最后=最上层，按钮始终可点）。
      // Stack 默认居中布局，若不加 position 该行会被放到画布正中央，
      // 既挡在用户捏合/拖拽的必经之路上（拦截手势），视觉上也是悬浮在中间。
      // position({x:0,y:0}) 固定到浮层左上角，恢复“顶部操作条”的本意。
      Row() {
        GlassButton({
          label: '取消',
          bgColor: 'rgba(255, 255, 255, 0.18)',
          textColor: Color.White,
          strokeWidth: 0,
          blurRadius: 0,
          btnHeight: 36,
          fontSize: 14,
          padX: 16,
          onAction: () => { this.closeCrop(); }
        })

        Blank()

        GlassButton({
          label: '确定',
          bgColor: 'rgba(255, 255, 255, 0.92)',
          textColor: Color.Black,
          strokeWidth: 0,
          blurRadius: 0,
          btnHeight: 36,
          fontSize: 14,
          padX: 16,
          isEnabled: this.cropReady,
          onAction: () => { this.confirmCrop(); }
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .position({ x: 0, y: 0 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .clip(true)
    // 平移/缩放直接消费 TouchEvent 手写实现：本环境 PanGesture/PinchGesture 识别器
    // 始终不触发，且图片组件因尺寸/位移原因命中测试为空（触摸到不了图片），
    // 因此把 onTouch 挂在浮层根 Stack 上：单指 = 拖动平移，双指 = 缩放。
    // 注意：按钮点击也会冒泡到这里，需用顶部条带区域排除按钮按下误启动手势。
    .onTouch((event: TouchEvent) => {
      this.handleCropTouch(event);
    })
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
      // 内容区壁纸：盖住 NavDestination 的白底（Index 根级壁纸只负责状态栏区域）。
      // 以全屏尺寸 + 状态栏偏移对齐根级壁纸，保证两层渲染同一画面、无缝衔接；
      // 模糊半径与 Index 根级一致（同一映射），避免模糊后的边缘在状态栏边界出现差异
      if (this.wallpaperPm) {
        Image(this.wallpaperPm)
          .width('100%')
          .height(`${this.wallpaperLayerH}px`)
          .position({ y: `-${this.wallpaperLayerY}px` })
          .objectFit(ImageFit.Cover)
          .blur(WallpaperUtil.blurRadius(this.wallpaperBlur))
      }
      // 底部悬浮 Tab 栏：固定短宽度 + 单手握持贴边（宽度不随握姿变化）
      this.mainTabs()
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
        ForEach(this.visibleTools(), (item: ToolCardItem) => {
          GridItem() {
              // 沉浸光感多层结构：毛玻璃基底 -> 光感渐变 -> 内容
              Stack() {
                // 图层1：毛玻璃基底（官方 backgroundBlurStyle 兜底，低版本可用）
                Stack()
                  .width('100%')
                  .height('100%')
                  .borderRadius(ImmersiveStyles.cardRadius())
                  .backgroundColor(ImmersiveStyles.cardBase(this.isDark))
                  .backgroundBlurStyle(ImmersiveStyles.cardBlurStyle(), { colorMode: ThemeColorMode.SYSTEM })

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
                    // 深色/浅色模式可读性：阴影颜色与文字相反
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))

                  Text(item.desc)
                    .fontSize(10)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(2)
                    .ellipsisMode(EllipsisMode.END)
                    .textAlign(TextAlign.Center)
                    .width('100%')
                    // 深色/浅色模式可读性：阴影颜色与文字相反
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))
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
              .border({ width: ImmersiveStyles.cardRimWidth(), color: ImmersiveStyles.cardOuterRim(this.isDark) })
              // 点光源光效（官方视觉特效，照亮卡片边缘）
              .visualEffect(LightSense.lightVisualEffect())
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
        }, (item: ToolCardItem) => JSON.stringify(item))
      }
      .scrollBar(BarState.Off)
      .editMode(true)
      .onItemDragStart((_event: ItemDragInfo, itemIndex: number) => {
        const visible: ToolCardItem[] = this.visibleTools();
        if (itemIndex < 0 || itemIndex >= visible.length) {
          return pixelMapBuilder(this.itemData, this.isDark);
        }
        this.itemData.toolCardItem = visible[itemIndex];
        return pixelMapBuilder(this.itemData, this.isDark);
      })
      .onItemDrop((_event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean): void => {
        const visible: ToolCardItem[] = this.visibleTools();
        if (!isSuccess || itemIndex < 0 || insertIndex < 0 ||
          itemIndex >= visible.length || insertIndex >= visible.length || itemIndex === insertIndex) {
          return;
        }
        const sourceIndex: number = this.listData.indexOf(visible[itemIndex]);
        const targetIndex: number = this.listData.indexOf(visible[insertIndex]);
        if (sourceIndex < 0 || targetIndex < 0) {
          return;
        }
        animateTo(
          { duration: 200, curve: Curve.Friction },
          () => {
            const temp: ToolCardItem = this.listData[sourceIndex];
            this.listData[sourceIndex] = this.listData[targetIndex];
            this.listData[targetIndex] = temp;
          })
        // 持久化拖拽后的顺序，重启后保持
        this.saveToolOrder();
      })
      .columnsGap(8)
      .rowsGap(8)
      .columnsTemplate('1fr 1fr 1fr')
      // 底部预留悬浮 Tab 栏避让空间，最后一排卡片可滚动到悬浮栏上方
      .padding({
        left: 12,
        right: 12,
        top: 12,
        bottom: 12
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
    // 图层1：毛玻璃基底（官方 backgroundBlurStyle 兜底，低版本可用）
    Stack()
      .width('100%')
      .height('100%')
      .borderRadius(ImmersiveStyles.cardRadius())
      .backgroundColor(ImmersiveStyles.cardBase(isDark))
      .backgroundBlurStyle(ImmersiveStyles.cardBlurStyle(), { colorMode: ThemeColorMode.SYSTEM })

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
