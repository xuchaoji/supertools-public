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
import { LightSense } from '../utils/LightSense';
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
  // 沉浸光感：跟随系统深/浅色模式
  @Local isDark: boolean = false;
  private themeMq: mediaquery.MediaQueryListener | null = null;
  // 主页壁纸（沉浸光感背景），空字符串表示未设置
  @Local wallpaperPath: string = '';
  /** 壁纸模糊度（0~100，0=不模糊），通过 AppStorage 与 Index 根级壁纸层同步 */
  @Local wallpaperBlur: number = 0;
  /** 全局光感档位（0=关闭 1=柔和 2=标准 3=精致），驱动 Tab 材质/卡片毛玻璃/点光源 */
  @Local lightSense: number = LightSense.LEVEL_EXQUISITE;
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
      icon: $r('app.media.app_link'),
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
    this.wallpaperBlur = WallpaperUtil.getBlur();
    this.lightSense = LightSense.getLevel();
    this.loadWallpaperPm();
    // 配置官方 HDS 沉浸光感悬浮 Tab 栏
    if (this.supportImmersiveTabs) {
      try {
        this.configureHdsTabs();
      } catch (e) {
        hilog.info(0x0000, TAG, 'init HdsTabsModifier failed: ' + JSON.stringify(e));
        this.supportImmersiveTabs = false;
      }
    }
  }

  /** 配置 HDS 悬浮 Tab 栏（材质类型/级别按全局光感档位驱动） */
  private configureHdsTabs(): void {
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
          // 材质类型/级别按全局光感档位：关闭=无材质，柔和=GENTLE，标准=SMOOTH，精致=EXQUISITE
          materialType: LightSense.tabMaterialType(this.lightSense),
          materialLevel: LightSense.tabMaterialLevel(this.lightSense),
        },
      });
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

  /** 调整全局光感档位：本地状态 + 持久化 + 重新配置 Tab 材质（卡片毛玻璃按档位自动跟随） */
  private updateLightSense(value: number): void {
    const v = Math.min(Math.max(Math.round(value), 0), 3);
    this.lightSense = v;
    LightSense.setLevel(v);
    // Tab 栏材质类型/级别随档位变化，重新应用 modifier
    if (this.supportImmersiveTabs) {
      try {
        this.configureHdsTabs();
      } catch (e) {
        hilog.info(0x0000, TAG, 'update LightSense HdsTabs failed: ' + JSON.stringify(e));
      }
    }
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
          .visibility(TargetConstants.HAS_FLOATING_PERM ? Visibility.Visible:Visibility.None)
          // 深色/浅色模式可读性：阴影颜色与文字相反
          .textShadow(ImmersiveStyles.textShadow(this.isDark))

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
