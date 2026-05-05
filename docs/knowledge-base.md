# supertools-public 知识库

> 本文档供 AI 辅助开发时参考，涵盖项目架构、编码规范、关键 API 模式以及常见扩展任务的操作方法。

---

## 1. 项目概览

| 属性 | 值 |
|---|---|
| 项目名 | supertools-public |
| 应用 ID | `com.xuchaoji.hmos.supertools` |
| 版本 | 2.0.2 (versionCode: 2000002) |
| 平台 | HarmonyOS (OpenHarmony) 5.0 |
| SDK 版本 | API 12 (Stage 模型), SDK 5.0.5(17) |
| 目标设备 | phone, tablet, 2in1 |
| 语言 | ArkTS (strict mode) |
| 构建系统 | Hvigor 5.0.5 |
| 包管理器 | ohpm |

**主要功能模块：**
- 设备高负载模拟器 (CPU/Memory 压测，多 Worker 线程)
- 屏幕录制 (H.264/H.265 编码，可选麦克风)
- 悬浮时钟 / 悬浮压测小窗
- 本地 Web 服务 (TCP Socket HTTP Server)
- 字符串编解码 (Base64 / URL)
- 设备信息 (硬件规格、屏幕、内存、电池、存储实时监控)

---

## 2. 技术栈

| 类别 | 技术 / 库 |
|---|---|
| UI 框架 | ArkUI `@ComponentV2` 声明式框架 |
| 路由 | `@hadss/hmrouter` (HMNavigation + `@HMRouter` 装饰器) |
| 状态管理 | ArkUI V2 响应式 (`@ObservedV2`, `@Trace`, `@Local`, `@Param`, `@Monitor`, `PersistenceV2`) |
| 工具库 | `@pura/harmony-utils` (AppUtil, PreferencesUtil, ToastUtil, DialogUtil, DateUtil, FileUtil) |
| 文件选择 | `@pura/picker_utils` (PhotoHelper) |
| 运行时 | HarmonyOS only, 严格模式 (caseSensitiveCheck + useNormalizedOHMUrl) |

**HarmonyOS SDK Kit 引用约定：**

```typescript
// System SDK kits 使用 @kit.* 前缀
import { display, window } from '@kit.ArkUI';
import { common, UIAbility } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { worker } from '@ohos.worker';
import { media } from '@kit.MediaKit';
import { socket } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { notificationManager } from '@kit.NotificationKit';
import { webview } from '@kit.ArkWeb';

// Third-party 库使用 npm 包名
import { AppUtil } from '@pura/harmony-utils';
import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
```

---

## 3. 目录结构

```
supertools-public/
├── AppScope/                       # 应用级全局配置
│   ├── app.json5                   # 应用清单 (bundleName, versionCode)
│   └── resources/                  # 全局 i18n 资源
├── hvigorfile.ts                   # 根构建入口 (appTasks + hmrouter appPlugin)
├── hvigor/hvigor-config.json5      # Hvigor 构建配置
├── build-profile.json5             # 根构建配置 (产品、签名、模块映射)
├── oh-package.json5                # 依赖声明
├── code-linter.json5               # ESLint 检查规则
├── sign/                           # 签名证书
├── main/                           # [唯一模块] 主入口模块
│   ├── hvigorfile.ts               # 模块构建入口 (hapTasks + 自定义 removePermissionPlugin)
│   ├── build-profile.json5         # 模块构建配置 (targets + workers)
│   ├── oh-package.json5            # 模块级依赖 (当前为空)
│   ├── obfuscation-rules.txt       # 代码混淆规则 (暂未启用)
│   └── src/
│       ├── main/                   # 默认源集
│       │   ├── module.json5        # 模块清单 (abilities, permissions, pages)
│       │   ├── ets/                # 全部 ArkTS 源码
│       │   │   ├── TargetConstants.ets
│       │   │   ├── mainability/    # UIAbility 入口
│       │   │   ├── mainbackupability/
│       │   │   ├── pages/          # 页面组件 (@Entry)
│       │   │   ├── components/     # 可复用 UI 组件
│       │   │   ├── widgets/        # 复合控件
│       │   │   ├── utils/          # 工具类 / 服务
│       │   │   ├── model/          # 数据模型
│       │   │   ├── viewmodel/      # 状态管理 (MVVM)
│       │   │   ├── constant/       # 常量
│       │   │   ├── capabilities/   # 独立功能模块
│       │   │   └── workers/        # ThreadWorker 脚本
│       │   └── resources/          # 模块资源 (string, color, media, rawfile, profile)
│       ├── dev/                    # dev 源集 (develop 构建变体)
│       │   └── ets/
│       │       └── TargetConstants.ets
│       └── product/                # product 源集 (AppGallery 上线变体)
│           └── ets/
│               └── TargetConstants.ets
└── devRes/                         # 开发资源 (SVG/PNG 图标)
└── docs/                           # 文档 (本知识库所在目录)
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
> 新增页面/能力窗口必须在 `main_pages.json` 中注册。

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
  @Trace cpuStressOn: boolean = false;

  public static getInstance() {
    if (!CommonViewModel.instance) {
      CommonViewModel.instance = new CommonViewModel();
    }
    return CommonViewModel.instance;
  }
}
```

### 4.2 Capabilities（独立功能模块）

每个 `capabilities/` 子目录是一个自包含的功能模块，遵循 **Manager + Page** 模式：

```
capabilities/
├── floatingclock/
│   ├── FloatClockManager.ets    # 窗口生命周期管理 (Singleton)
│   └── FloatClockPage.ets       # UI 页面 (@Entry)
└── floatingstress/
    ├── StressWindowManager.ets  # 窗口管理 (Singleton, 封装 FloatWindowManager)
    ├── StressKernel.ets         # Worker 池协调器 (Singleton)
    └── StressCapsulePage.ets    # UI 页面 (@Entry)
```

**新增能力模块的标准步骤：**
1. 在 `capabilities/` 下创建子目录
2. 创建 Manager 类（Singleton，管理窗口/资源生命周期）
3. 创建 Page 组件（`@Entry @Component`）
4. 在 `main_pages.json` 注册页面路径
5. 在 `HomePage` 的 `SettingPage` 中添加开关入口（按需使用 `TargetConstants` 控制可见性）

### 4.3 工具/服务模式

所有工具类在 `utils/` 目录下，大部分使用 Singleton 或公开静态方法：

| 文件 | 职责 | 模式 |
|---|---|---|
| `GlobalContextHolder.ets` | 全局 UIAbilityContext 持有者 | Singleton |
| `FloatWindowManager.ets` | 通用系统悬浮窗封装 | 构造 + 实例方法 |
| `FloatDragHandler.ets` | 悬浮窗触摸拖拽处理 | 构造 + 实例方法 |
| `MyAVScreenCapture.ets` | AV 屏幕录制封装 | Singleton |
| `BackgroundServiceManager.ets` | 后台长时任务管理 | 静态 init + 实例方法 |
| `WebServerUtil.ets` | 嵌入式 HTTP 服务器 | Singleton |
| `FloatWindowUtil.ets` | 悬浮球窗口助手 | 混合 |
| `TimeUtils.ets` | 时间格式化工具 | 静态方法 |

### 4.4 事件驱动通信

```
页面  ──ViewModels── 组件
 │
 ├── ThreadWorker (postMessage/onmessage) → 后台计算
 ├── setInterval → 定时监控 (CPU/Memory)
 └── PersistenceV2.connect/save → 磁盘持久化
```

---

## 5. 编码规范

### 5.1 命名规范

| 类型 | 规范 | 示例 |
|---|---|---|
| 文件名 | PascalCase | `FloatClockManager.ets`, `HomePage.ets` |
| 类/结构体 | PascalCase | `MainAbility`, `RecordViewModel` |
| 接口 | PascalCase | `FloatWindowConfig`, `CalcMsgData` |
| 类型别名 | PascalCase | `ToolClickAction` |
| 常量 (编译时) | UPPER_SNAKE_CASE | `MAX_WK_CNT`, `POST_MAIN_INTERVAL` |
| 静态只读属性 | camelCase (类前缀) | `PageNames.HOME_PAGE`, `SpKeys.PRIVACY_AGREE` |
| 变量/函数 | camelCase | `startRecording`, `floatClockOn` |
| 私有成员 | camelCase + `_` 前缀 | `private _isRunning: boolean = false` |
| TAG 常量 | `const TAG: string = 'ComponentName'` | `const TAG: string = 'HOME_PAGE'` |

### 5.2 文件组织

- 每个文件只包含一个主类/结构体（子组件、Builder 函数可以共存）
- 不导出 barrel（直接从源文件导入）
- 导入顺序：HarmonyOS SDK Kit → 第三方库 → 本地相对路径 → 跨源集路径

### 5.3 装饰器使用准则

| 装饰器 | 用途 | 使用位置 |
|---|---|---|
| `@Entry` | 标记页面入口 | 页面级 struct |
| `@ComponentV2` | 声明式组件 (V2) | 所有新组件 |
| `@ObservedV2` | 可观察类 | Model / ViewModel |
| `@Trace` | 被追踪响应式属性 | ObservedV2 类内 |
| `@Local` | 组件本地状态 | ComponentV2 组件内 |
| `@Param` | 父传子参数 | 子组件 |
| `@Require` | 必需参数 | 配合 @Param |
| `@Event` | 事件回调 | 子组件标签参数 |
| `@Builder` | 声明式构建函数 | 组件内或全局 |
| `@BuilderParam` | 插槽内容 | 子组件 |
| `@HMRouter({ pageUrl })` | 路由注册 | 页面级 struct |
| `@Monitor('propName')` | 属性变更监听 | 方法 |

### 5.4 日志规范

```typescript
import { hilog } from '@kit.PerformanceAnalysisKit';
const DOMAIN = 0x0000;
const TAG: string = 'ComponentName';

hilog.info(DOMAIN, TAG, '%{public}s', 'message');
hilog.error(DOMAIN, TAG, 'Failed: %{public}s', JSON.stringify(err));
```

对于 utils/capabilities，使用 `console.info` / `console.error` 配合 TAG 前缀：
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
- 自定义颜色使用 hex 字符串：`'#FF6B6B'`，`'rgba(255, 255, 255, 0.8)'`
- 间距使用 `'vp'` 单位：`'16vp'`，`'8vp'`
- 毛玻璃效果组合：`.backgroundColor('rgba(255,255,255,0.8)').backgroundBlurStyle(BlurStyle.COMPONENT_THICK)`
- 禁止使用 `gridSpan` 等已弃用 API，改用 `constraintSize`

---

## 6. 关键组件 / API 模式

### 6.1 路由跳转

```typescript
// 页面注册 (在目标页面上)
@HMRouter({ pageUrl: PageNames.CALC_PAGE })
@Entry
@ComponentV2
export struct CalcPage { ... }

// 导航跳转
import { HMRouterMgr } from '@hadss/hmrouter';

HMRouterMgr.push({ pageUrl: PageNames.CALC_PAGE });
// 或带参数
HMRouterMgr.push({
  pageUrl: PageNames.SOME_PAGE,
  param: { key: 'value' }
});
```

**页面 URL 常量** 定义在 `constant/PageNames.ets`：
```typescript
export class PageNames {
  public static readonly HOME_PAGE: string = 'HomePage';
  public static readonly SCREEN_RECORD: string = 'ScreenRecordPage';
  public static readonly CALC_PAGE = 'calcPage';
  public static readonly STR_CONVERT = 'stringConvertPage';
  public static readonly LOCAL_WEB_PAGE = 'localWebPage';
  public static readonly DEVICE_INFO_PAGE = 'deviceInfoPage';
  // ... 新增页面在此添加
}
```

### 6.2 悬浮窗创建

使用 `FloatWindowManager` 封装类：

```typescript
import { FloatWindowManager, FloatWindowConfig } from '../../utils/FloatWindowManager';

const config: FloatWindowConfig = {
  name: 'unique_window_name',
  pagePath: 'capabilities/myfeature/MyPage', // 必须与 main_pages.json 一致
  widthVp: 240,
  heightVp: 64,
  initX: 100,
  initY: 300,
};

const manager = new FloatWindowManager(context, config);
await manager.show();   // 显示
await manager.hide();   // 隐藏（销毁窗口）
```

**注意：**
- `FloatWindowManager` 内部处理 `801` 权限错误并弹出引导对话框。
- 每个浮窗必须有唯一的 `name`，用于 `FloatDragHandler` 定位窗口。
- API 12 下 `window.findWindow(name)` 为同步调用。

### 6.3 拖拽处理

```typescript
import { FloatDragHandler } from '../../utils/FloatDragHandler';

this.dragHandler = new FloatDragHandler('unique_window_name');

// 在 build() 中绑定
.onTouch((event: TouchEvent) => {
  this.dragHandler.handleTouch(event);
})
```

`FloatDragHandler` 内部：
- 自动获取屏幕密度，将逻辑坐标转为物理像素
- TouchType.Down 记录起始位置，TouchType.Move 调用 `moveWindowTo`
- 使用 2px 阈值防止误触

### 6.4 ThreadWorker 使用

```typescript
import worker from '@ohos.worker';

// 创建 Worker (路径相对于模块根)
const wk = new worker.ThreadWorker('main/ets/workers/CalcWorker');

// 发送消息
wk.postMessage({ action: 'start', maxCalcCount: 30, id: i });

// 接收消息
wk.onmessage = (e: MessageEvents) => {
  const data = e.data;
  // 处理结果
};

// 错误处理
wk.onerror = (e) => {
  console.error(`Worker Error: ${e.message}`);
};

// 终止
wk.terminate();
```

**Worker 脚本** 必须在 `main/build-profile.json5` 中注册：
```json5
"buildOption": {
  "sourceOption": {
    "workers": [
      './src/main/ets/workers/CalcWorker.ets',
      './src/main/ets/workers/StressWorker.ets'
    ]
  }
}
```

### 6.5 PersistenceV2 持久化

```typescript
import { PersistenceV2, Type } from "@ohos.arkui.StateManagement";

const STORAGE_KEY = 'recording_cache';

@ObservedV2
export class RecordingCache {
  @Type(RecordModel)
  @Trace recordings: Array<RecordModel> = new Array<RecordModel>();
  @Trace recordMic: boolean = false;
}

// 连接持久化
this.cache = PersistenceV2.connect(RecordingCache, STORAGE_KEY, 
  () => new RecordingCache())!;

// 手动同步到磁盘
PersistenceV2.save(RecordingCache);
```

### 6.6 hidebug 性能监控

```typescript
import { hidebug } from '@kit.PerformanceAnalysisKit';

const cpuUsage = hidebug.getSystemCpuUsage(); // 返回 0.x
const memInfo = hidebug.getSystemMemInfo();    // { totalMem, freeMem, availableMem }
```

### 6.7 屏幕录制

```typescript
import { MyAVScreenCapture } from '../utils/MyAVScreenCapture';
import { media } from '@kit.MediaKit';

// 检查编码器预设
const preset = RecordViewModel.getInstance().preset; 
// SCREEN_RECORD_PRESET_H265_AAC_MP4 或 SCREEN_RECORD_PRESET_H264_AAC_MP4

// 开始录制
await MyAVScreenCapture.getInstance().startRecording();

// 停止录制
await MyAVScreenCapture.getInstance().stopRecording();
```

### 6.8 共享偏好设置

```typescript
import { AppUtil } from '@pura/harmony-utils';

AppUtil.getBoolean('key', false);    // 读取
AppUtil.putBoolean('key', true);     // 写入
```

### 6.9 设备信息 API

```typescript
import { deviceInfo } from '@kit.BasicServicesKit';
import { batteryInfo } from '@kit.BasicServicesKit';
import { display } from '@kit.ArkUI';
import { hidebug } from '@kit.PerformanceAnalysisKit';
import statfs from '@ohos.file.statvfs';

// 设备硬件
deviceInfo.productModel   // 设备型号
deviceInfo.brand          // 品牌
deviceInfo.manufacture    // 制造商
deviceInfo.hardwareProfile // 硬件配置 (如 "arm64-v8a 2.8GHz*4+1.9GHz*4")
deviceInfo.abiList        // CPU 架构 (如 "arm64-v8a")
deviceInfo.osFullName     // OS 完整版本号
deviceInfo.sdkApiVersion  // SDK API 级别

// 屏幕
const d = display.getDefaultDisplaySync();
d.width / d.height         // 屏幕宽高 (px)
d.densityPixels / d.densityDPI // 像素密度
d.refreshRate              // 刷新率 (Hz)

// 内存 - hidebug.getSystemMemInfo() 返回单位是 KB
const mem = hidebug.getSystemMemInfo();
mem.totalMem     // 总内存 (KB)
mem.availableMem // 可用内存 (KB)
mem.freeMem      // 空闲内存 (KB)

// 电池 - batteryInfo.voltage 单位是 µV, chargingStatus 是 BatteryPluggedType 枚举
batteryInfo.batterySOC      // 电量百分比 (number)
batteryInfo.chargingStatus  // 0=NONE, 1=AC, 2=USB, 3=WIRELESS (非0即充电)
batteryInfo.healthStatus    // 健康状态枚举
batteryInfo.technology      // 电池技术 (如 "Li-poly")
batteryInfo.voltage         // 电压 (µV, 需 /1000000 转 V)

// 存储 - 用应用沙箱根路径查询分区信息
const context = getContext(this) as common.UIAbilityContext;
const root = context.filesDir.substring(0, context.filesDir.indexOf('/files'));
statfs.getTotalSizeSync(root)  // 分区总大小 (bytes)
statfs.getFreeSizeSync(root)   // 分区剩余大小 (bytes)
```

### 6.10 ArkUI V2 实时刷新模式

在 `@ComponentV2` 中实现定时刷新 UI 的正确方式：

```
setInterval → 更新 @ObservedV2.@Trace 属性 → build() 中直接读取 Text(this.xxx) → UI 自动更新
```

**关键原则：**
- 动态数据必须用 `@ObservedV2` 类 + `@Trace` 属性包装，`@ComponentV2` 中用 `@Local` 持有该对象实例
- `build()` 中直接 `Text(this.state.property)` 读取 `@Trace` 属性，不要通过嵌套 `@Builder` 传参
- 嵌套 `@Builder` 在 V2 中不建立 `@Local` → UI 的响应式依赖链，会导致数据变更不刷新
- `@Builder` 仅用于静态模板（一次性渲染数据如设备型号、屏幕参数等）
- `setInterval` 中的箭头函数保持 `this` 绑定，可直接修改 `@Local` / `@Trace`

**示例 — 电池充电状态实时刷新：**
```typescript
@ObservedV2
class BatteryState {
  @Trace charging: string = '-';
}

@ComponentV2
struct MyPage {
  @Local battery: BatteryState = new BatteryState();

  aboutToAppear(): void {
    this.refreshTimer = setInterval(() => {
      this.battery.charging = batteryInfo.chargingStatus > 0 ? '正在充电' : '未充电';
    }, 2000);
  }

  build() {
    // 直接读取 @Trace 属性，不经过 @Builder 传参
    Text(this.battery.charging)
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

每个产品对应一个源集，都会编译 `main` 作为基础 + 对应源集覆盖：

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
# hvigor 构建 (需在 DevEco Studio 或命令行中运行)
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

// 控制 UI 可见性
.visibility(TargetConstants.HAS_FLOATING_PERM ? Visibility.Visible : Visibility.None)

// 控制逻辑分支
if (TargetConstants.IS_AG_TARGET) {
  // AG 版本逻辑
}
```

> 注意导入路径使用不带源集前缀的 `"main/ets/TargetConstants"`，构建系统会根据当前目标解析到正确的源集文件。

---

## 9. 权限模型

`main/src/main/module.json5` 声明的权限：

| 权限 | 用途 |
|---|---|
| `ohos.permission.INTERNET` | Web 服务器、网络通信 |
| `ohos.permission.GET_WIFI_INFO` | 获取 WiFi 信息 (用于 Web 服务器 IP 展示) |
| `ohos.permission.MICROPHONE` | 屏幕录制时录制麦克风 |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | 后台长时任务 (录制保持) |
| `ohos.permission.SYSTEM_FLOAT_WINDOW` | 悬浮窗 (产品版本自动移除) |

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

2. **创建 / 引用图标资源**: 在 `devRes/` 下放置对应 SVG 图标（24×24 尺寸），然后在代码中以 `$r('app.media.xxx')` 引用（文件名去掉扩展名）。

3. **注册路由常量**: 在 `constant/PageNames.ets` 中添加
   ```typescript
   public static readonly NEW_TOOL_PAGE = 'newToolPage';
   ```

4. **在 HomePage 工具列表中添加入口**: 编辑 `pages/HomePage.ets` 中的 `listData` 数组
   ```typescript
   {
     name: '新工具',
     desc: '工具描述',
     icon: $r('app.media.new_icon'),
     onClick: () => { HMRouterMgr.push({ pageUrl: PageNames.NEW_TOOL_PAGE }) }
   }
   ```

> 注意：通过 `@HMRouter` 注册的页面不需要在 `main_pages.json` 中额外注册。

### 10.2 新增一个 Capability 模块

1. 在 `capabilities/` 下创建目录，例 `capabilities/myfeature/`
2. 创建 Manager（Singleton 模式管理窗口/资源）
3. 创建 Page（`@Entry`）
4. 在 `main_pages.json` 中注册页面路径
5. 在 `HomePage` 设置中根据需要添加开关，使用 `TargetConstants` 控制可见性

### 10.3 新增一个 Worker 线程

1. 创建 Worker 脚本: `main/src/main/ets/workers/MyWorker.ets`
2. 在 `main/build-profile.json5` 的 `workers` 数组中注册
3. 使用: `new worker.ThreadWorker('main/ets/workers/MyWorker')`

### 10.4 新增持久化数据

1. 创建 `@ObservedV2` 类，添加 `@Trace` 属性，使用 `@Type` 标注复杂类型
2. 调用 `PersistenceV2.connect(MyClass, 'storage_key', () => new MyClass())`
3. 需要手动同步时调用 `PersistenceV2.save(MyClass)`

### 10.5 引用应用级资源

```typescript
// 系统资源
$r('sys.color.background_primary')
$r('sys.float.corner_radius_level4')
$r('sys.float.Body_L')
$r('sys.color.font_primary')
$r('sys.color.comp_background_gray')

// 应用资源
$r('app.media.bench')
$r('app.string.app_name')

// 原始文件
const fd = getContext().resourceManager.getRawFd('rawfile/myfile.txt');
```

### 10.6 调试技巧

```typescript
// 日志
hilog.info(0x0000, 'TAG', '%{public}s', 'message');

// 全局上下文获取
import { GlobalContextHolder } from '../utils/GlobalContextHolder';
const ctx = GlobalContextHolder.getInstance().uiAbilityContext;

// 屏幕信息
import { display } from '@kit.ArkUI';
const d = display.getDefaultDisplaySync();
console.log(`width=${d.width}, height=${d.height}, density=${d.densityPixels}`);
```

---

## 11. 安全与检查清单

- **Linter**: 对 `*.ets` 文件运行 `@performance/recommended` + `@typescript-eslint/recommended` + 安全规则
- **安全规则**: `no-unsafe-aes`, `no-unsafe-hash`, `no-unsafe-dh`, `no-unsafe-dsa`, `no-unsafe-ecdsa`, `no-unsafe-rsa-*`, `no-unsafe-3des`
- **忽略路径**: `ohosTest`, `test`, `mock`, `node_modules`, `oh_modules`, `build`, `.preview`
- **构建严格模式**: `caseSensitiveCheck: true`, `useNormalizedOHMUrl: true`
- **无测试文件**: 项目中无现有测试，但依赖 `@ohos/hypium` (测试框架) 和 `@ohos/hamock` (mock 框架) 可用于未来的测试编写

---

## 12. 被废弃 / 禁止使用的 API 与已知陷阱

通过代码审查发现的规则：
- 不使用 `gridSpan` (已弃用)，改用 `constraintSize`
- 不使用 `@Builder` 中的 `Text` 子组件在 `Column` 内添加点击事件（某些场景限制）
- `Row` 组件不使用 `minHeight` 属性，改用 `.constraintSize({ minHeight: '100vp' })`
- `backgroundBlurStyle` 已弃用，替代为 `backgroundBlurStyle`（注意拼写，已迁移）

### ArkUI V2 响应式陷阱

- **嵌套 `@Builder` 传参不建立响应式链**：在 `@ComponentV2` 的 `build()` 中，如果 `@Local` 变量通过参数传递给嵌套的 `@Builder`（如 `this.liveRow(label, this.batSOC)`），该嵌套 `@Builder` 不会随 `@Local` 变化重新执行。正确做法是将 `this.batSOC` 直接写在 `build()` 层的 `Text()` 中，或者使用 `@ComponentV2` 子组件 + `@Param` 传递。
- **动态数据须用 `@ObservedV2` + `@Trace`**：需要定时刷新的数据应封装在 `@ObservedV2` 类内，属性用 `@Trace` 装饰，组件用 `@Local` 持有对象实例。
- **`@Local` 对数组仅检测引用变更**：`@Local items = [...]` 会触发重渲染，但数组内对象属性变更不会。如需数组内元素属性级刷新，元素类须用 `@ObservedV2` + `@Trace`。
- **`batteryInfo.voltage` 单位是 µV**：需除以 1000000 转换为 V。
- **`hidebug.getSystemMemInfo()` 返回单位是 KB**：需除以 1024 转换为 MB。
