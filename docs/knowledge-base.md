# supertools-public 知识库

> 本文档供 AI 辅助开发时参考，涵盖项目架构、编码规范、关键 API 模式以及常见扩展任务的操作方法。

---

## 1. 项目概览

| 属性 | 值 |
|---|---|
| 项目名 | supertools-public |
| 应用 ID | `com.xuchaoji.hmos.supertools` |
| 版本 | 2.1.2 (versionCode: 2001002) |
| 平台 | HarmonyOS (OpenHarmony) 5.0 |
| SDK 版本 | API 12 (Stage 模型), SDK 5.0.5(17) |
| 目标设备 | phone, tablet, 2in1 |
| 语言 | ArkTS (strict mode: `caseSensitiveCheck` + `useNormalizedOHMUrl`) |
| 构建系统 | Hvigor 5.0.5 |
| 包管理器 | ohpm |
| 全局根页面 | `pages/Index` (HMNavigation 容器, `homePageUrl: PageNames.GUIDE_PAGE`) |

**主要功能模块：**
- 设备高负载模拟器 / 压测工具 (CPU 多 Worker 线程斐波那契计算 + StressWorker 百分比强度控制)
- 屏幕录制 (H.264/H.265 编码，可选麦克风，后台保活，自动保存到图库)
- 悬浮时钟 (`capabilities/floatingclock/`，毫秒级实时显示)
- 悬浮压测小窗 (`capabilities/floatingstress/`，CPU/MEM 实时圆环监控 + 强度滑动调节)
- 本地 Web 服务 (TCP Socket HTTP Server，目录列表、文件/文件夹拖拽上传、MIME 类型识别、频控限速)
- **服务自启动**：重启后自动恢复悬浮时钟、悬浮压测、Web 服务状态。（2.1.2 新增）
- **服务自启动总开关**：设置页「服务自启动设置」控制是否记录各服务开关状态。关闭后不记录，每次启动用默认值。（2.1.2 新增）
- 字符串编解码 (Base64 / URL)
- 设备信息实时监控 (CPU 型号/架构、屏幕、内存、电池电压/充电状态/健康度、存储分区)

---

## 2. 技术栈

| 类别 | 技术 / 库 |
|---|---|
| UI 框架 | ArkUI `@ComponentV2` 声明式框架（部分旧页面使用 `@Component` v1） |
| 路由 | `@hadss/hmrouter` (HMNavigation + `@HMRouter` 装饰器) + `@hadss/hmrouter-transitions` |
| 状态管理 | ArkUI V2 响应式 (`@ObservedV2`, `@Trace`, `@Local`, `@Param`, `@Require`, `@Event`, `@Monitor`, `@Builder`, `@BuilderParam`, `PersistenceV2`, `AppStorage`) |
| 工具库 | `@pura/harmony-utils` (AppUtil, PreferencesUtil, ToastUtil, DialogUtil, DateUtil, FileUtil) |
| 文件/图片选择 | `@pura/picker_utils` (PhotoHelper) |
| 路由转场 | `@hadss/hmrouter-transitions` |
| 测试 (声明但无测试) | `@ohos/hypium` (1.0.21), `@ohos/hamock` (1.0.0) |
| 运行时 | HarmonyOS only, 严格模式 |

**HarmonyOS SDK Kit 引用约定：**

```typescript
// System SDK kits 使用 @kit.* 前缀
import { display, window } from '@kit.ArkUI';
import { common, UIAbility, Want, wantAgent, WantAgent } from '@kit.AbilityKit';
import { hilog, hidebug } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { worker } from '@ohos.worker';
import { media } from '@kit.MediaKit';
import { socket } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { notificationManager } from '@kit.NotificationKit';
import { webview } from '@kit.ArkWeb';
import { wifiManager } from '@kit.ConnectivityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { audio } from '@kit.AudioKit';
import { batteryInfo, deviceInfo } from '@kit.BasicServicesKit';
import statfs from '@ohos.file.statvfs';
import { PersistenceV2, Type } from "@ohos.arkui.StateManagement";
import { pasteboard } from '@kit.BasicServicesKit';

// Third-party 库
import { AppUtil } from '@pura/harmony-utils';
import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import { PhotoHelper } from '@pura/picker_utils';
```

---

## 3. 目录结构

```
supertools-public/
├── AppScope/                       # 应用级全局配置
│   ├── app.json5                   # 应用清单 (bundleName, versionCode 2000002)
│   └── resources/                  # 全局 i18n 资源
├── hvigorfile.ts                   # 根构建入口 (appTasks + hmrouter appPlugin)
├── hvigor/hvigor-config.json5      # Hvigor 构建配置 (daemon/parallel/logging)
├── build-profile.json5             # 根构建配置 (产品、签名、模块映射)
├── oh-package.json5                # 根依赖声明
├── oh-package-lock.json5           # 依赖锁文件
├── code-linter.json5               # ESLint 检查规则
├── devRes/                         # 开发资源 (SVG/PNG 图标)
├── README.md                       # 简要说明
├── docs/
│   └── knowledge-base.md           # 本知识库
├── oh_modules/                     # ohpm 安装的依赖
└── main/                           # [唯一模块] 主入口模块
    ├── hvigorfile.ts               # 模块构建入口 (hapTasks + 自定义 removePermissionPlugin)
    ├── build-profile.json5         # 模块构建配置 (targets + workers 注册)
    ├── oh-package.json5            # 模块级依赖 (当前为空)
    ├── obfuscation-rules.txt       # 代码混淆规则 (暂未启用)
    └── src/
        ├── main/                   # 默认源集 (base)
        │   ├── module.json5        # 模块清单 (abilities, permissions, pages, extensions)
        │   ├── ets/                # 全部 ArkTS 源码
        │   │   ├── TargetConstants.ets          # 特性开关 (默认: HAS_FLOATING_PERM=true)
        │   │   ├── mainability/MainAbility.ets  # UIAbility 入口
        │   │   ├── mainbackupability/MainBackupAbility.ets  # 备份 Extension
        │   │   ├── pages/          # 10 个页面组件 (@Entry)
        │   │   ├── components/     # 5 个可复用 UI 组件
        │   │   ├── widgets/        # 4 个复合控件
        │   │   ├── utils/          # 9 个工具/服务类
        │   │   ├── model/          # 5 个数据模型 (2 个为空桩文件)
        │   │   ├── viewmodel/      # 2 个 ViewModel 单例
        │   │   ├── constant/       # 3 个常量文件
        │   │   ├── capabilities/   # 2 个独立功能模块
        │   │   └── workers/        # 2 个 ThreadWorker 脚本
        │   └── resources/          # 模块资源 (string, color, media, rawfile, profile)
        ├── dev/                    # dev 源集 (develop 构建变体)
        │   └── ets/
        │       └── TargetConstants.ets   # HAS_FLOATING_PERM=true, IS_AG_TARGET=false
        └── product/                # product 源集 (AppGallery 上线变体)
            └── ets/
                └── TargetConstants.ets   # HAS_FLOATING_PERM=false, IS_AG_TARGET=true
```

**页面注册表** (`main/src/main/resources/base/profile/main_pages.json`):
```json
{
  "src": [
    "pages/Index",
    "pages/FloatBallPage",
    "capabilities/floatingclock/FloatClockPage",
    "capabilities/floatingstress/StressCapsulePage"
  ]
}
```
> **重要**: 通过 `@HMRouter` 注册的页面**不需要**在 `main_pages.json` 中额外注册。仅系统浮窗页面（TYPE_FLOAT window）必须在此注册。

**页面清单 (完整)：**

| 文件 | 入口类型 | 注册方式 | 功能 |
|---|---|---|---|
| `pages/Index.ets` | `@Entry` | main_pages.json | HMNavigation 根容器 |
| `pages/FloatBallPage.ets` | `@Entry` | main_pages.json | 浮窗小球 (Web 状态跑马灯) |
| `pages/GuidePage.ets` | `@Entry` + `@HMRouter` | 路由装饰器 | 隐私协议同意引导页 |
| `pages/PrivacyPage.ets` | `@Entry` + `@HMRouter` | 路由装饰器 | 隐私政策 WebView 展示 |
| `pages/HomePage.ets` | `@ComponentV2` + `@HMRouter` | 路由装饰器 | 主面板 (工具网格 + 设置页) |
| `pages/CalcPage.ets` | `@Entry` + `@HMRouter` | 路由装饰器 | CPU 压测工具页 |
| `pages/ScreenRecordPage.ets` | `@Entry` + `@HMRouter` | 路由装饰器 | 屏幕录制页 |
| `pages/LocalWebPage.ets` | `@Entry` + `@HMRouter` | 路由装饰器 | 本地 Web 服务管理 |
| `pages/StringConverter.ets` | `@Entry` + `@HMRouter` | 路由装饰器 | 字符串编解码 |
| `pages/DeviceInfoPage.ets` | `@Entry` + `@HMRouter` | 路由装饰器 | 设备信息监控 |
| `capabilities/floatingclock/FloatClockPage.ets` | `@Entry` | main_pages.json | 悬浮时钟 UI |
| `capabilities/floatingstress/StressCapsulePage.ets` | `@Entry` | main_pages.json | 悬浮压测 UI |

---

## 4. 核心架构模式

### 4.1 MVVM 分层

```
┌──────────────────────────────────────────┐
│  View (pages/ components/ widgets/)      │  ← ArkUI @ComponentV2, @Entry
├──────────────────────────────────────────┤
│  ViewModel (viewmodel/)                  │  ← Singleton, @ObservedV2, @Trace
├──────────────────────────────────────────┤
│  Model (model/)                          │  ← 纯数据类, @ObservedV2, @Trace
└──────────────────────────────────────────┘
```

**ViewModel 单例模式：**
```typescript
@ObservedV2
export class CommonViewModel {
  private static instance: CommonViewModel;
  @Trace private _cpuStressOn: boolean = false;

  public set cpuStressOn(value: boolean) { this._cpuStressOn = value; }
  public get cpuStressOn(): boolean { return this._cpuStressOn; }

  public static getInstance() {
    if (!CommonViewModel.instance) {
      CommonViewModel.instance = new CommonViewModel();
    }
    return CommonViewModel.instance;
  }
}
```

**已有 ViewModels:**

| ViewModel | 文件 | 管理状态 |
|---|---|---|
| `CommonViewModel` | `viewmodel/CommonViewModel.ets` | `floatingClockOn`, `cpuStressOn`, `maxCalcCount`, `isWorkerRunning`, Worker 频控 |
| `RecordViewModel` | `viewmodel/RecordViewModel.ets` | `isInRecording`, `currentRecordFileName`, `RecordingCache` (PersistenceV2) |

### 4.2 Capabilities（独立功能模块）

每个 `capabilities/` 子目录是一个自包含的功能模块，遵循 **Manager + Page** 模式：

```
capabilities/
├── floatingclock/
│   ├── FloatClockManager.ets    # 窗口生命周期管理 (静态方法, 类似 Singleton)
│   └── FloatClockPage.ets       # UI 页面 (@Entry, 旧 @Component v1)
└── floatingstress/
    ├── StressWindowManager.ets  # 窗口管理 (Singleton, 封装 FloatWindowManager)
    ├── StressKernel.ets         # Worker 池协调器 (Singleton, 8 线程)
    └── StressCapsulePage.ets    # UI 页面 (@Entry, 老 @Component v1)
```

**新增能力模块的标准步骤：**
1. 在 `capabilities/` 下创建子目录
2. 创建 Manager 类（Singleton 或静态方法，管理窗口/资源生命周期）
3. 创建 Page 组件（`@Entry @Component`）
4. 在 `main_pages.json` 注册页面路径
5. 在 `HomePage` 的 `settingPage()` 中添加开关入口（按需使用 `TargetConstants` 控制可见性）

### 4.3 工具/服务模式

| 文件 | 职责 | 模式 |
|---|---|---|
| `GlobalContextHolder.ets` | 全局 UIAbilityContext 持有者 | Singleton |
| `FloatWindowManager.ets` | 通用系统悬浮窗封装 (createWindow/UIContent/resize/move/destroy) | 构造 + 实例方法 |
| `FloatDragHandler.ets` | 悬浮窗触摸拖拽处理 (基于 TouchEvent，2px 防误触阈值) | 构造 + 实例方法 |
| `FloatWindowUtil.ets` | 悬浮球窗口助手 (封装 FloatBallPage 的 show/destroy) | 静态方法 |
| `MyAVScreenCapture.ets` | AV 屏幕录制封装 (H.264/H.265, 麦克风, 系统胶囊回调) | Singleton, `@ObservedV2` |
| `BackgroundServiceManager.ets` | 后台长时任务 + 通知管理 (录屏/Web服务, 自动切换 BackgroundMode) | 静态 init + 静态方法 |
| `BackgroundTaskUtil.ets` | 后台保活工具 (DATA_TRANSFER 模式, 旧版备用) | 静态 init + 静态方法 |
| `WebServerUtil.ets` | 嵌入式 HTTP 服务器 (TCP Socket, 目录列表, 拖拽上传, MIME, 频控) | Singleton |
| `TimeUtils.ets` | 时间格式化 (formatVideoTime → mm:ss) | 导出函数 |

### 4.4 事件驱动通信

```
页面  ──ViewModels── 组件
 │
 ├── ThreadWorker (postMessage/onmessage) → 后台计算
 │    ├── CalcWorker: 斐波那契数列计算 + 定时 16ms 上报
 │    └── StressWorker: 强度循环 (busy-wait + setTimeout 让路)
 ├── setInterval → 定时监控 (CPU/Memory 刷新每秒)
 ├── PersistenceV2.connect/save → 磁盘持久化 (录屏缓存)
 ├── AppStorage → 跨组件/跨窗口通信 (RecentAccessFile)
 └── BusinessError try/catch → 统一错误处理
```

### 4.5 `@Component` v1 vs `@ComponentV2` 混用

项目中同时存在两种组件风格：
- **v1 (`@Component`)**: `FloatClockPage`, `FloatBallPage`, `Index` 等较旧/浮窗页面，使用 `@State` / `@StorageProp`
- **v2 (`@ComponentV2`)**: `HomePage`, `StressCapsule`, `StressRing`, `SettingGroup`, `RecordCard` 等新组件，使用 `@Local` / `@Param` / `@Trace`

新建组件**必须**使用 `@ComponentV2`。

---

## 5. 编码规范

### 5.1 命名规范

| 类型 | 规范 | 示例 |
|---|---|---|
| 文件名 | PascalCase | `FloatClockManager.ets`, `HomePage.ets` |
| 类/结构体 | PascalCase | `MainAbility`, `RecordViewModel`, `DragCardModel` |
| 接口 | PascalCase | `FloatWindowConfig`, `CalcMsgData` |
| 类型别名 | PascalCase | `ToolClickAction`, `SwitchCardClickAction` |
| 常量 (编译时) | UPPER_SNAKE_CASE | `MAX_WK_CNT`, `POST_MAIN_INTERVAL`, `RECORDING_CACHE` |
| 静态只读属性 | camelCase (类前缀) | `PageNames.HOME_PAGE`, `SpKeys.PRIVACY_AGREE` |
| 变量/函数 | camelCase | `startRecording`, `floatClockOn` |
| 私有成员 | camelCase + `_` 前缀 | `private _isRunning: boolean = false` |
| TAG 常量 | `const TAG: string = 'ComponentName'` | `const TAG: string = 'HOME_PAGE'` |

### 5.2 文件组织

- 每个文件只包含一个主类/结构体（子组件、Builder 函数可以共存）
- **不导出 barrel**：直接从源文件导入
- 导入顺序：HarmonyOS SDK Kit → 第三方库 → 本地相对路径 → 跨源集路径 (`"main/ets/TargetConstants"`)
- 全局 Builder 函数导出：`export function pixelMapBuilder(...)` — 用于拖拽预览

### 5.3 装饰器使用准则

| 装饰器 | 用途 | 使用位置 |
|---|---|---|
| `@Entry` | 标记页面入口 | 页面级 struct |
| `@Component` | 声明式组件 (v1, 旧版) | 旧组件 (逐步迁移至 V2) |
| `@ComponentV2` | 声明式组件 (V2, 新版) | **所有新组件必须使用** |
| `@ObservedV2` | 可观察类 | Model / ViewModel |
| `@Trace` | 被追踪响应式属性 | ObservedV2 类内 |
| `@Local` | 组件本地状态 | ComponentV2 组件内 |
| `@Param` | 父传子参数 | 子组件 |
| `@Require` | 必需参数标记 | 配合 `@Param` |
| `@Event` | 事件回调 | 子组件标签参数 |
| `@Builder` | 声明式构建函数 | 组件内或全局 |
| `@BuilderParam` | 插槽内容入口 | 子组件 |
| `@HMRouter({ pageUrl })` | 路由注册 | 页面级 struct |
| `@Monitor('propName')` | 属性变更监听 | V2 组件方法 |
| `@StorageProp('key')` | 读 AppStorage | `FloatBallPage` (v1 组件) |
| `@State` | 组件状态 (v1) | 旧组件 |
| `@Prop` | 父传子 (v1) | 旧组件 |

### 5.4 日志规范

```typescript
import { hilog } from '@kit.PerformanceAnalysisKit';
const DOMAIN = 0x0000;
const TAG: string = 'ComponentName';

hilog.info(DOMAIN, TAG, '%{public}s', 'message');
hilog.error(DOMAIN, TAG, 'Failed: %{public}s', JSON.stringify(err));
```

对于 utils/capabilities/components，使用 `console.info` / `console.error` 配合 TAG 前缀：
```typescript
console.info(`[StressKernel] 暴力模式启动: ${this.CORE_COUNT} 线程`);
```

### 5.5 错误处理

```typescript
import { BusinessError } from '@kit.BasicServicesKit';

try {
  await someAsyncOperation();
} catch (exception) {
  const err = exception as BusinessError;
  console.error(`${TAG} Error: Code=${err.code}, Msg=${err.message}`);
}
```

### 5.6 样式约定

- 优先使用系统资源引用：`$r('sys.color.background_primary')`，`$r('sys.float.corner_radius_level4')`
- 自定义颜色使用 hex/RGBA：`'#FF6B6B'`，`'rgba(255, 255, 255, 0.8)'`
- 间距使用 `'vp'` 单位：`'16vp'`，`'8vp'`
- 毛玻璃效果组合：`.backgroundColor('rgba(255,255,255,0.8)').backgroundBlurStyle(BlurStyle.COMPONENT_THICK)`
- **禁止使用 `gridSpan`**（已弃用），改用 `constraintSize`
- **禁止在 `Row` 上使用 `minHeight`**，改用 `.constraintSize({ minHeight: '100vp' })`

---

## 6. 关键组件 / API 模式

### 6.1 路由跳转

```typescript
// 页面注册 (在目标页面上)
@HMRouter({ pageUrl: PageNames.CALC_PAGE })
@Entry
@Entry
@ComponentV2
export struct CalcPage { ... }

// 导航跳转
import { HMRouterMgr } from '@hadss/hmrouter';

HMRouterMgr.push({ pageUrl: PageNames.CALC_PAGE });
HMRouterMgr.push({ pageUrl: PageNames.SCREEN_RECORD, param: { key: 'value' } });
HMRouterMgr.pop(); // 返回
HMRouterMgr.replace({ pageUrl: PageNames.HOME_PAGE }); // 替换当前页
```

**页面 URL 常量** 定义在 `constant/PageNames.ets`：
```typescript
export class PageNames {
  public static readonly GUIDE_PAGE: string = 'guidePage';
  public static readonly PRIVACY_PAGE: string = 'privacyPage';
  public static readonly SPLASH_PAGE: string = 'splashPage';
  public static readonly HOME_PAGE: string = 'HomePage';
  public static readonly SCREEN_RECORD: string = 'ScreenRecordPage';
  public static readonly CALC_PAGE = 'calcPage';
  public static readonly STR_CONVERT = 'stringConvertPage';
  public static readonly LOCAL_WEB_PAGE = 'localWebPage';
  public static readonly DEVICE_INFO_PAGE = 'deviceInfoPage';
}
```

### 6.2 悬浮窗创建

使用 `FloatWindowManager` 封装类：

```typescript
import { FloatWindowManager, FloatWindowConfig } from '../../utils/FloatWindowManager';

const config: FloatWindowConfig = {
  name: 'unique_window_name',      // 唯一标识 (API 12 window.findWindow 同步查找)
  pagePath: 'capabilities/myfeature/MyPage', // 必须与 main_pages.json 一致
  widthVp: 240,
  heightVp: 64,
  initX: 100,                      // 可选, 默认屏幕右侧
  initY: 300,                      // 可选
  focusable: false                 // 可选, 默认 false
};

const manager = new FloatWindowManager(context, config);
await manager.show();   // 首次 display→createWindow; 后续仅 showWindow
await manager.hide();   // destroyWindow (完全销毁)
manager.getWindowRect(); // { left, top, width, height }
```

**Capability 层的封装模式：**

- `FloatClockManager`：使用**静态方法** + 内部静态 `windowClass`（直接调用 `window.createWindow` 而非 `FloatWindowManager`）
- `StressFloatWindowManager`：**Singleton 封装** `FloatWindowManager` 实例
- `FloatWindowUtil`：**静态方法封装**（管理 FloatBallPage 浮窗）

**注意：**
- `FloatWindowManager` 内部处理 `801` 权限错误并弹出"去设置"引导对话框。
- 每个浮窗必须有唯一的 `name`，用于 `FloatDragHandler` 定位窗口。
- API 12 下 `window.findWindow(name)` 为同步调用。
- `showPermissionGuideDialog()` 会跳转至系统设置。

### 6.3 拖拽处理

```typescript
import { FloatDragHandler } from '../../utils/FloatDragHandler';

// FloatDragHandler 构造时同步调用 window.findWindow(name)
this.dragHandler = new FloatDragHandler('unique_window_name');

// 在 build() 中绑定
.onTouch((event: TouchEvent) => {
  this.dragHandler.handleTouch(event);
})
```

**`FloatDragHandler` 内部逻辑：**
- `init()` 时获取屏幕密度 (`display.getDefaultDisplaySync().densityPixels`)
- `TouchType.Down`: 记录起始触摸位置和窗口位置
- `TouchType.Move`: 超过 **2px 阈值**后启动拖拽（防误触），delta 坐标乘以 density 转为物理像素后调用 `moveWindowTo`
- 注意：`FloatBallPage` 内联实现了自己的拖拽逻辑（不使用 FloatDragHandler），且有 bug：`targetY` 写成了 `this.startWinY + deltaY_px` 但实际代码写成了 `deltaX_px`（第 81 行）

### 6.4 ThreadWorker 使用

**注册**: Worker 脚本必须在 `main/build-profile.json5` 中注册：
```json5
"buildOption": { "sourceOption": { "workers": [
  "./src/main/ets/workers/CalcWorker.ets",
  "./src/main/ets/workers/StressWorker.ets"
]}}
```

**CalcWorker.ets** — 高负载计算 Worker:
```typescript
import worker, { ErrorEvent, MessageEvents, ThreadWorkerGlobalScope } from '@kit.ArkTS';

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

workerPort.onmessage = (event: MessageEvents) => {
  if (event.data.action === 'start') {
    // 每 16ms 执行一次斐波那契计算
    setInterval(() => {
      const result = heavyCalculation(); // fibonacci(10~maxCalcCount)
      if (CommonViewModel.getInstance().canPostToMain()) {
        workerPort.postMessage({ type: 'log', message: `...` });
      }
    }, 16);
  }
  if(event.data.action === 'stop') {
    CommonViewModel.getInstance().isWorkerRunning = false;
  }
};
```

**StressWorker.ets** — 压测强度 Worker:
```typescript
// 50ms 基准周期, busyTime = (intensity/100) * 50ms
// 每帧执行 Math.random + sqrt + sin 计算
// setTimeout(restTime, 1) 给 Event Loop "呼吸孔"
workerPort.onmessage = (e) => {
  if (action === 'START') { isRunning = true; currentIntensity = data.intensity; runStressLoop(); }
  else if (action === 'UPDATE') { currentIntensity = data.intensity; }
  else if (action === 'STOP') { isRunning = false; currentIntensity = 0; }
};
```

**StressKernel** (`capabilities/floatingstress/StressKernel.ets`) — Worker 池管理：
```typescript
const kernel = StressKernel.getInstance();
kernel.start(intensity);    // 创建 8 个 StressWorker, postMessage START
kernel.updateIntensity(50); // 运行时调整所有 Worker 强度
kernel.stop();              // 遍历 terminate() 所有 Worker
```
- `CORE_COUNT = 8`（根据手机核心数可调整）
- `start()` 先 `terminateAll()` 清理旧资源再创建新池
- 所有 Worker 注册了 `onerror` 回调防止静默崩溃

### 6.5 PersistenceV2 持久化

```typescript
import { PersistenceV2, Type } from "@ohos.arkui.StateManagement";

const STORAGE_KEY = 'recording_cache';

@ObservedV2
export class RecordingCache {
  @Type(RecordModel)
  @Trace recordings: Array<RecordModel> = new Array<RecordModel>();
  @Trace recordMic: boolean = false;
  @Trace preset: number = media.AVScreenCaptureRecordPreset.SCREEN_RECORD_PRESET_H265_AAC_MP4;
}

// 在 ViewModel 中连接持久化
this.cache = PersistenceV2.connect(RecordingCache, STORAGE_KEY, 
  () => new RecordingCache())!;

// 手动强制同步到磁盘 (在关键数据变更后调用)
PersistenceV2.save(RecordingCache);
```

### 6.6 hidebug 性能监控

```typescript
import { hidebug } from '@kit.PerformanceAnalysisKit';

const cpuUsage = hidebug.getSystemCpuUsage(); // 返回 0.0~1.0
const memInfo = hidebug.getSystemMemInfo();    // { totalMem: number(KB), freeMem: number(KB), availableMem: number(KB) }

// 实际使用 (StressCapsule)
const rawCpu = hidebug.getSystemCpuUsage();
this.realCpu = rawCpu * 100; // 转为百分比
const usedMem = memInfo.totalMem - memInfo.availableMem;
this.realMem = usedMem / 1024; // KB → MB
```

### 6.7 屏幕录制 (MyAVScreenCapture)

```typescript
import { MyAVScreenCapture } from '../utils/MyAVScreenCapture';

const capture = MyAVScreenCapture.getInstance();

// 开始录制
await capture.startRecording(filesDir); // 自动创建日期命名的 .mp4 文件

// 手动停止
await capture.stopRecording();

// 系统胶囊停止 → 监听 stateChange 事件自动触发 addRecordTask
// SCREENCAPTURE_STATE_STOPPED_BY_USER → addRecordTask → PersistenceV2.save
// SCREENCAPTURE_STATE_CANCELED → cleanUp
```

**关键细节：**
- 动态获取 `RecordViewModel.getInstance()` 避免循环依赖
- `setMicEnabled(vm.recordMic)` 控制麦克风
- 编码预设：`SCREEN_RECORD_PRESET_H265_AAC_MP4` 或 `SCREEN_RECORD_PRESET_H264_AAC_MP4`
- 录制参数: `videoBitrate: 30000000`, `audioSampleRate: 48000`, `audioBitrate: 96000`

### 6.8 后台服务管理 (BackgroundServiceManager)

```typescript
import { BackgroundServiceManager } from '../utils/BackgroundServiceManager';

// MainAbility.onCreate 中初始化
BackgroundServiceManager.init(this.context);

// Web 服务启动/停止时通知
BackgroundServiceManager.startWebServer(info);
BackgroundServiceManager.stopWebServer();

// 录屏启动/停止时通知
BackgroundServiceManager.startRecordingTask();
BackgroundServiceManager.stopRecordingTask();
```

**核心逻辑：**
- `refreshBackgroundState()` 自动判断：啥都没跑→取消后台任务+移除通知；仅录屏→AUDIO_RECORDING 模式；仅 Web→DATA_TRANSFER 模式
- 优先级: **录音 > 数据传输**
- 自动请求通知权限 (`notificationManager.requestEnableNotification`)
- 发布常驻通知 (`isOngoing: true`, `isUnremovable: true`)
- 通知 ID: `10001`

### 6.9 WebServerUtil (本地 HTTP 服务器)

```typescript
import { WebServerUtil } from '../utils/WebServerUtil';

const server = WebServerUtil.getInstance();
server.init(filesDir + '/webroot', 8088);  // 根目录 + 端口
server.start();   // 启动 TCP Socket Server 监听
server.stop();    // 关闭
server.getIpAddress();  // WiFi IP (wifiManager.getIpInfo())
server.isRunning;       // 运行状态

// 频控
server.setRateLimit('/api/data', 1); // 限制每分钟 1 次
server.getRateLimitMinutes('/api/data'); // 获取频控分钟数
```

**功能细节：**
- 目录列表页面 (含拖拽上传区域 + 文件选择 + 文件夹选择)
- `/api/upload` POST 接口 (通过 `X-File-Path` 头指定目标路径，批量上传)
- MIME 类型识别 (html/js/css/json/txt/png/jpg)
- 路径遍历防护 (`..` 检测 → 403)
- 文件频控限速 (path → lastAccess 检查，超限返回 429)
- `AppStorage.setOrCreate('RecentAccessFile', fileName)` 推送最近访问
- TCP 粘包处理: `tryProcessRequest` 通过 `Content-Length` 头判断是否接收完整

### 6.10 共享偏好与上下文

```typescript
// SharedPreferences / AppUtil
import { AppUtil } from '@pura/harmony-utils';

AppUtil.getBoolean('key', false);    // 读取
AppUtil.putBoolean('key', true);     // 写入

// 全局 UIAbilityContext
import { GlobalContextHolder } from '../utils/GlobalContextHolder';
const ctx = GlobalContextHolder.getInstance().uiAbilityContext;

// 状态栏高度 (用于顶部安全区)
AppUtil.getStatusBarHeight();
```

### 6.11 设备信息 API

```typescript
import { deviceInfo, batteryInfo } from '@kit.BasicServicesKit';
import { display, hidebug } from '@kit.ArkUI';
import statfs from '@ohos.file.statvfs';

// CPU 硬件: deviceInfo.productModel, brand, manufacture, hardwareProfile, abiList
// OS 信息: deviceInfo.osFullName, sdkApiVersion
// 屏幕: display.getDefaultDisplaySync() → width/height(px), densityPixels, densityDPI, refreshRate
// 内存: hidebug.getSystemMemInfo() → totalMem(KB), availableMem(KB), freeMem(KB)
// 电池: batteryInfo.batterySOC(%), chargingStatus(0=NONE/1=AC/2=USB/3=WIRELESS), healthStatus, technology, voltage(µV→需/1000000转V)
// 存储: statfs.getTotalSizeSync(root), getFreeSizeSync(root)
```

### 6.12 录制保存到图库

```typescript
// 使用 @pura/picker_utils 的 PhotoHelper
// 或直接使用 photoAccessHelper (RecordCard 中的 saveRecord 函数)
import { photoAccessHelper } from '@kit.MediaLibraryKit';

let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
let desFileUris = await phAccessHelper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
await fileIo.copyFile(srcFile.fd, desFile.fd);
```

### 6.13 ArkUI V2 实时刷新模式 (核心原则)

在 `@ComponentV2` 中实现定时刷新 UI 的正确方式：

```
setInterval → 更新 @ObservedV2.@Trace 属性 → build() 中直接读取 Text(this.xxx) → UI 自动更新
```

**关键原则：**
- 动态数据必须用 `@ObservedV2` 类 + `@Trace` 属性包装，`@ComponentV2` 中用 `@Local` 持有该对象实例
- `build()` 中直接 `Text(this.state.property)` 读取 `@Trace` 属性，**不要通过嵌套 `@Builder` 传参**
- 嵌套 `@Builder` 在 V2 中不建立 `@Local` → UI 的响应式依赖链，会导致数据变更不刷新
- `@Builder` 仅用于静态模板（一次性渲染数据如设备型号、屏幕参数等）
- `setInterval` 中的箭头函数保持 `this` 绑定，可直接修改 `@Local` / `@Trace`
- `@Local` 对数组仅检测引用变更，数组内元素属性变更不会触发 UI 更新。如需元素级刷新，元素类须用 `@ObservedV2` + `@Trace`

**示例 — StressCapsule CPU 实时刷新：**
```typescript
@ObservedV2
class StressState {
  @Trace realCpu: number = 0;
}

@ComponentV2
struct StressCapsule {
  @Local state: StressState = new StressState();
  private timerId: number = -1;

  aboutToAppear(): void {
    this.timerId = setInterval(() => {
      const rawCpu = hidebug.getSystemCpuUsage();
      this.state.realCpu = rawCpu * 100; // 直接修改 @Trace 属性触发 UI 更新
    }, 1000);
  }

  build() {
    Text(`${this.state.realCpu.toFixed(0)}%`) // 直接读取
  }
}
```

---

## 7. 构建系统

### 7.1 产品配置

两个产品变体 (`build-profile.json5`)：

| 产品名 | bundleName | 目标源集 | 用途 |
|---|---|---|---|
| `default` | `com.xuchaoji.hmos.supertools` | `product` | AppGallery 上线 |
| `dev` | `com.xuchaoji.hmos.supertools.dev` | `dev` | 本地开发 |

### 7.2 源集覆盖

```
构建 dev 产品  → main/ets/... + src/dev/ets/TargetConstants.ets
构建 default   → main/ets/... + src/product/ets/TargetConstants.ets
```

源集只在 `TargetConstants.ets` 上有差异，通过该文件控制功能开关。

### 7.3 自定义 Hvigor 插件

`main/hvigorfile.ts` 中的 `removePermissionPlugin()`：
- 对 **非 dev 目标**（即 `default` / `product`）构建后，自动从 `module.json` 中移除 `ohos.permission.SYSTEM_FLOAT_WINDOW` 权限。
- 原理：在 `GeneratePkgModuleJson` 任务后、`PackageHap` 前修改中间产物 `module.json`。

### 7.4 常用构建命令

```bash
hvigor assembleHap --mode module -p product=default -p buildMode=release
hvigor assembleHap --mode module -p product=dev -p buildMode=debug
```

---

## 8. 特性标志 (Feature Flags)

通过 `TargetConstants.ets` 的源集覆盖实现条件编译：

```typescript
// main 默认值 (开发环境)
export class TargetConstants {
  public static readonly HAS_FLOATING_PERM: boolean = true;
  public static readonly IS_AG_TARGET: boolean = false;
}

// product 源集 (AG 上线版本)
export class TargetConstants {
  public static readonly HAS_FLOATING_PERM: boolean = false;
  public static readonly IS_AG_TARGET: boolean = true;
}
```

**使用方式：**
```typescript
import { TargetConstants } from "main/ets/TargetConstants";

// 控制 UI 部分可见性
.visibility(TargetConstants.HAS_FLOATING_PERM ? Visibility.Visible : Visibility.None)

// 传入组件控制
SettingGroup({ vis: TargetConstants.HAS_FLOATING_PERM }) { ... }
SettingSwitchItem({ ..., vis: TargetConstants.HAS_FLOATING_PERM, ... })

// 控制逻辑分支
if (TargetConstants.IS_AG_TARGET) { /* AG 版本逻辑 */ }
```

> 导入路径使用**不带源集前缀**的 `"main/ets/TargetConstants"`，构建系统根据当前目标自动解析到正确的源集文件。

---

## 9. 权限模型

`main/src/main/module.json5` 声明的权限：

| 权限 | 用途 |
|---|---|
| `ohos.permission.INTERNET` | Web 服务器、网络通信 |
| `ohos.permission.GET_WIFI_INFO` | 获取 WiFi 信息 (用于 Web 服务器 IP 展示) |
| `ohos.permission.MICROPHONE` | 屏幕录制时录制麦克风 (运行时请求) |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | 后台长时任务 (录制/Web服务保活) |
| `ohos.permission.SYSTEM_FLOAT_WINDOW` | 悬浮窗 (AppGallery 版本自动移除) |

**后台模式:**
- `dataTransfer` — Web 服务数据传输
- `audioRecording` — 录屏音频

---

## 10. 扩展指南

### 10.1 新增一个工具页

1. **创建页面文件**: `main/src/main/ets/pages/NewToolPage.ets`
   ```typescript
   import { HMRouter } from '@hadss/hmrouter';
   import { PageNames } from '../constant/PageNames';

   @HMRouter({ pageUrl: PageNames.NEW_TOOL_PAGE })
   @Entry
   @ComponentV2
   export struct NewToolPage {
     build() {
       Column() {
         Text('New Tool')
       }
       .width('100%')
       .height('100%')
       .backgroundColor($r('sys.color.background_primary'))
     }
   }
   ```

2. **注册路由常量**: 在 `constant/PageNames.ets` 中添加
   ```typescript
   public static readonly NEW_TOOL_PAGE = 'newToolPage';
   ```

3. **在 HomePage 工具列表中添加入口**: 编辑 `pages/HomePage.ets` 中的 `listData` 数组
   ```typescript
   {
     name: '新工具',
     desc: '工具描述',
     icon: $r('app.media.new_icon'),
     onClick: (event: ClickEvent) => { HMRouterMgr.push({ pageUrl: PageNames.NEW_TOOL_PAGE }) }
   },
   ```

> 注意：通过 `@HMRouter` 注册的页面**不需要**在 `main_pages.json` 中额外注册。

### 10.2 新增一个 Capability 模块

1. 在 `capabilities/` 下创建目录，例 `capabilities/myfeature/`
2. 创建 Manager（Singleton / 静态方法模式管理窗口/资源）
3. 创建 Page（`@Entry @Component`）
4. 在 `main_pages.json` 中注册页面路径
5. 在 `HomePage.settingPage()` 中添加开关，使用 `TargetConstants.HAS_FLOATING_PERM` 控制可见性

### 10.3 新增一个 Worker 线程

1. 创建 Worker 脚本: `main/src/main/ets/workers/MyWorker.ets`
   ```typescript
   import worker from '@ohos.worker';
   const workerPort = worker.workerPort;
   workerPort.onmessage = (e) => { /* ... */ };
   ```
2. 在 `main/build-profile.json5` 的 `workers` 数组中注册路径
3. 使用: `new worker.ThreadWorker('main/ets/workers/MyWorker')`

### 10.4 新增持久化数据

1. 创建 `@ObservedV2` 类，添加 `@Trace` 属性，使用 `@Type` 标注复杂类型
2. 调用 `PersistenceV2.connect(MyClass, 'storage_key', () => new MyClass())`
3. 需要手动同步时调用 `PersistenceV2.save(MyClass)`

### 10.5 引用应用/系统资源

```typescript
// 系统资源
$r('sys.color.background_primary')
$r('sys.color.background_secondary')
$r('sys.color.font_primary')
$r('sys.color.font_secondary')
$r('sys.color.font_emphasize')
$r('sys.color.icon_emphasize')
$r('sys.color.icon')
$r('sys.color.comp_background_gray')
$r('sys.color.comp_background_emphasize')
$r('sys.color.ohos_fa_list_card_bg_blur')
$r('sys.float.corner_radius_level4')
$r('sys.float.Body_L')
$r('sys.float.Body_M')
$r('sys.float.padding_level2')

// 应用资源
$r('app.media.bench')
$r('app.media.recorder')
$r('app.media.redstone_repeater')
$r('app.media.code')
$r('app.media.deviceinfo')
$r('app.media.settings')
$r('app.media.globalSetting')
$r('app.media.playIcon')
$r('app.media.pauseIcon')
$r('app.media.delete')
$r('app.media.export')
$r('app.media.image')
$r('app.media.layered_icon')
$r('app.media.chaoji_bust_style')
$r('app.string.app_name')
$r('app.string.tools_tab')
$r('app.string.setting_tab')
```

---

## 11. 组件/模型细节对照表

### 11.1 Model 清单

| 文件 | 内容 | 说明 |
|---|---|---|
| `HomePageModel.ets` | `ToolCardItem`, `DragCardModel`, `ToolCardModel`, `ToolClickAction` | `ToolCardModel` 为空定义; `ToolCardItem` 含 `@Trace name/desc/icon` |
| `RecordModel.ets` | `RecordModel` | 含 `@Trace filePath` + `@Trace fineName` (注意: 拼写为 `fineName` 非 `fileName`) |
| `CalcMsgData.ets` | `CalcMsgData` | Worker 消息格式 `{ type, message }` |
| `ScreenRecordModel.ets` | (空文件) | 占位桩 |
| `ChatModel.ets` | (空文件) | 占位桩 |

### 11.2 Component 清单

| 文件 | 组件 | 模式 | 说明 |
|---|---|---|---|
| `ImmersiveGlassCard.ets` | `ImmersiveGlassCard` | v1 | 毛玻璃卡片 (zHeight/zRadius/theme/content 插槽) |
| `SettingGroup.ets` | `SettingGroup` | V2 | 设置项分组容器 (自动分割线, `@BuilderParam` 插槽) |
| `SettingSwitchItem.ets` | `SettingSwitchItem` | V2 | 开关设置行 (title + Toggle + onChange 事件) |
| `StressCapsule.ets` | `StressCapsule` | V2 | 悬浮压测面板 (拖拽 + 圆环 + 启停 + PanGesture 强度调节) |
| `StressRing.ets` | `StressRing` | V2 | CPU/MEM 圆环指示器 (value/displayValue/label/isActive) |

### 11.3 Widget 清单

| 文件 | 组件 | 说明 |
|---|---|---|
| `ListSetting.ets` | `ListSetting` + `SettingItemModel` | 设置列表 (基于 `ForEach` + `@Monitor` 可见性) |
| `RecordCard.ets` | `RecordCard` | 录像卡片 (播放/暂停 Video, 删除, 保存到图库) |
| `SettingSwitchItemCard.ets` | `SettingSwitchItemCard` | 简洁开关卡片 (title + Toggle, 无分割线) |
| `StatusIndicator.ets` | `StatusIndicator` | 圆环进度指示器 (value/label/color, `@Monitor` 监听) |

---

## 12. 安全与检查清单

- **Linter**: 对 `*.ets` 文件运行 `@performance/recommended` + `@typescript-eslint/recommended` + 安全规则
- **安全规则**: `no-unsafe-aes`, `no-unsafe-hash`, `no-unsafe-dh`, `no-unsafe-dsa`, `no-unsafe-ecdsa`, `no-unsafe-rsa-*`, `no-unsafe-3des`
- **忽略路径**: `ohosTest`, `test`, `mock`, `node_modules`, `oh_modules`, `build`, `.preview`
- **构建严格模式**: `caseSensitiveCheck: true`, `useNormalizedOHMUrl: true`
- **无测试文件**: 项目中无现有测试，但依赖 `@ohos/hypium` (测试框架) 和 `@ohos/hamock` (mock 框架) 可用于未来的测试编写

---

## 13. 状态持久化分析 (2026-06-28)

### 13.1 持久化现状

**已持久化 (无需改动):**

| 状态 | 所在位置 | 持久化方式 | 键名 |
|---|---|---|---|
| H265/H264 编码预设 | `RecordViewModel.recordingCache.preset` | `PersistenceV2` | `recording_cache` |
| 录制麦克风开关 | `RecordViewModel.recordingCache.recordMic` | `PersistenceV2` | `recording_cache` |
| 录屏记录列表 | `RecordViewModel.recordingCache.recordings` | `PersistenceV2` | `recording_cache` |
| 隐私协议同意 | `PrivacyPage.ets` → `PreferencesUtil` | `Preferences` | `privacy_agree` |
| 扫描解析开关 | `HomePage.ets` → `PreferencesUtil` | `Preferences` | `enable_scan_parse` |

**已实现持久化 (2.1.2 新增):**

| 状态 | 写入位置 | 读取/恢复位置 | 键名 | 默认值 |
|---|---|---|---|---|
| `floatingClockOn` | `HomePage.ets:~198` | `MainAbility.ets:~52` | `float_clock_on` | `false` |
| `cpuStressOn` | `HomePage.ets:~217` | `MainAbility.ets:~66` | `cpu_stress_on` | `false` |
| `isServerRunning` | `LocalWebPage.ets:~315` | `MainAbility.ets:~80` | `web_server_on` | `true` |

### 13.2 服务自启动总开关 (2.1.2 新增)

| 键名 | 默认值 | 位置 | 说明 |
|---|---|---|---|
| `auto_start_enabled` | `true` | `SpKeys.ets` | 总开关，控制是否记录各服务状态 |

**总开关行为:**
- **开启 (默认)**: 各服务开关变更时写入 Preferences，重启时从 Preferences 恢复
- **关闭**: 不记录各服务开关状态，重启时全部使用默认值（Web服务=开，时钟/压测=关），关闭瞬间立即停止所有运行中服务

**受控的写入点（通过 `auto_start_enabled` 守卫）:**
```typescript
// HomePage.ets - 悬浮时钟/压测 onChange
if (PreferencesUtil.getBooleanSync(SpKeys.AUTO_START_ENABLED, true)) {
  PreferencesUtil.put(SpKeys.FLOAT_CLOCK_ON, isOn);
}

// LocalWebPage.ets - toggleServer()
if (PreferencesUtil.getBooleanSync(SpKeys.AUTO_START_ENABLED, true)) {
  PreferencesUtil.put(SpKeys.WEB_SERVER_ON, isRunning);
}
```

**恢复逻辑（MainAbility.restoreSavedState）:**
```typescript
// 1. 隐私未同意 → 跳过全部
// 2. auto_start_enabled = false → restoreDefaults() (web服务默认启动)
// 3. auto_start_enabled = true  → 从 Preferences 读取各键恢复
```

### 13.3 隐私同意后 Web 服务立即启动

`PrivacyPage.startDefaultServices()`: 用户点击「同意」后立即启动 Web 服务器（不包含 BackgroundService，避免通知弹窗）。

### 13.4 SpKeys 枚举

```typescript
export class SpKeys {
  public static readonly PRIVACY_AGREE: string = 'privacy_agree';
  public static readonly ENABLE_SCAN_PARSE: string = 'enable_scan_parse';
  public static readonly FLOAT_CLOCK_ON: string = 'float_clock_on';
  public static readonly CPU_STRESS_ON: string = 'cpu_stress_on';
  public static readonly WEB_SERVER_ON: string = 'web_server_on';
  public static readonly AUTO_START_ENABLED: string = 'auto_start_enabled';
}
```

## 14. 自动化测试

### 14.1 工具链

| 工具 | 用途 | 命令示例 |
|---|---|---|
| `uitest dumpLayout` | 导出当前 UI 层级 JSON，含每个元素的 bounds/text/type | `uitest dumpLayout -p /data/local/tmp/layout.xml -b <bundleName>` |
| `uitest uiInput click <x> <y>` | 在指定坐标点击 | `uitest uiInput click 889 1742` |
| `uitest uiInput swipe <x1> <y1> <x2> <y2>` | 滑动操作 | `uitest uiInput swipe 540 1500 540 500 1000` |
| `aa start/force-stop` | 启动/停止应用 | `aa start -a MainAbility -b <bundleName>` |
| `snapshot_display` | 设备截图 | `snapshot_display` |
| `netstat -tlnp` | 端口监听检查 | `netstat -tlnp` |
| `hidumper -s WindowManagerService` | 窗口状态查询 | `hidumper -s WindowManagerService -a '-a'` |
| `hilog -x -e <regex>` | 应用日志过滤 | `hilog -x -e StateRestore` |
| `bm dump -n <bundleName>` | 应用信息查询 | `bm dump -n com.xuchaoji.hmos.supertools.dev` |
| `cat <prefsPath>` | 读取 Preferences 文件 | `cat /data/app/el2/.../preferences/SP_HARMONY_UTILS_PREFERENCES` |

### 14.2 UI 自动化工作流

```
1. hdc shell "uitest dumpLayout -p /data/local/tmp/layout.xml -b <bundle>"
2. hdc file recv /data/local/tmp/layout.xml local_layout.xml
3. 解析 JSON，找到目标元素的 bounds
4. 计算中心坐标: x = (left+right)/2, y = (top+bottom)/2
5. hdc shell "uitest uiInput click <x> <y>"
6. 验证: Preferences / netstat / hidumper / hilog
```

### 14.3 Preferences 文件路径

```
/data/app/el2/100/base/<bundleName>/haps/main/preferences/SP_HARMONY_UTILS_PREFERENCES
```

格式: XML，根元素 `<preferences>`, 子元素 `<bool key="..." value="true/false"/>`。

## 15. 已知陷阱与注意事项

### 13.1 已弃用 API
- `gridSpan` → 改用 `constraintSize`
- `Row.minHeight` → 改用 `.constraintSize({ minHeight: '100vp' })`
- `backgroundBlurStyle` 拼写注意，已统一使用正确拼写

### 13.2 ArkUI V2 响应式陷阱
- **嵌套 `@Builder` 传参不建立响应式链**：动态数据直接写在 `build()` 层的组件中
- **`@Local` 对数组仅检测引用变更**：数组元素属性变更需 `@ObservedV2` + `@Trace`
- **`@Component` (v1) vs `@ComponentV2` (V2) 不可混用**：v1 用 `@State`/`@Prop`/`@StorageProp`，V2 用 `@Local`/`@Param`/`@Trace`
- **`@Monitor` 只能监听当前组件的 `@Param` / `@Local` 等属性**

### 13.3 单位转换陷阱
- `batteryInfo.voltage` 单位是 **µV** → 需 `/1000000` 转 V
- `hidebug.getSystemMemInfo()` 返回值单位是 **KB** → 需 `/1024` 转 MB / `/1024/1024` 转 GB
- `display.densityPixels` → vp 转 px 需乘法

### 13.4 已知 Bug
- `pages/FloatBallPage.ets` 第 81 行: `let targetY = this.startWinY + deltaY_px;` 应为 `deltaY_px`（变量名错误，导致 Y 轴拖拽偏移异常）
- `model/RecordModel.ets`: 属性名 `fineName` 应统一为 `fileName`（多处引用中使用 `.fineName` 而非 `.fileName`）

### 13.5 路径安全
- WebServerUtil 中检查 `..` 防路径遍历，但仅在 POST `/api/upload` 中做了检查；GET 请求中也需检查
- 所有文件路径操作需处理 `file://` 前缀的添加/剥离

### 13.6 循环依赖
- `MyAVScreenCapture` 通过**方法内动态获取** `RecordViewModel.getInstance()` 避免循环导入
- `BackgroundServiceManager` 须在 `MainAbility.onCreate` 中 `init(context)`，确保在使用前初始化

### 13.7 FloatBallPage 拖拽坐标问题
- 第 81 行 `let targetY = this.startWinY + deltaY_px;` 存在明显错误：第四个参数应该是 `deltaY_px` 而非 `deltaY_px`。实际上当前写法导致 Y 轴偏移使用了 X 轴的位移增量，而非 Y 轴的位移增量。
