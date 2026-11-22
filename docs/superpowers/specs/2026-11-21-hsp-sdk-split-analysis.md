# HSP 拆分与“SDK 接入模拟”架构分析

> 状态：分析建议，未改代码（2026-11-21）
> 目标：把当前工具箱应用演进为“全能媒体 + 模拟 SDK 接入”的宿主，并判断哪些模块适合拆成 HSP
> 结论先行：
> 1. 当前是**单 entry HAP**，不是媒体应用：没有 AVPlayer / AVSession / 投播 / 媒体库，只有 H5、录屏、局域网文件服务、GL 游戏等“媒体周边”。
> 2. 现有代码里最适合先拆 HSP 的是：**广告 SDK、局域网媒体服务、录屏采集**；其次是**原生 HDC（6.76MB `.so`，体积/懒加载演示价值最高）**与**GL 游戏**；悬浮窗最后。
> 3. 拆 HSP 之前必须先抽 **HAR 契约层 + 公共常量 + UI kit**，否则 HSP 会反向依赖 HAP，拆不动。
> 4. 第一个纵切建议做 **广告 HSP**：现有 `AdsHspPage` 其实还在 HAP 内，名字叫 HSP 但并不是 HSP，正好是最真实的“第三方 SDK 装进 HSP”演示。
> 5. HSP **不会减小应用总包体积**，也不会支持独立升级；它的价值是代码/资源隔离、进程内单例、按需加载、多 HAP 共享。不要为了“模块化好看”把所有页面都 HSP 化。

---

## 一、现状：一个 12MB 的单 HAP 工具箱

### 1.1 事实清单

| 维度 | 现状 | 依据 |
|---|---|---|
| 模块 | 只有 `main` 一个 **entry HAP**，根 `build-profile.json5` 的 `modules` 只登记了 `main` | `build-profile.json5:101-121` |
| 源码规模 | 84 个 `.ets`（约 592KB），22 个页面文件 | `main/src/main/ets` |
| 分层 | `pages / components / widgets / model / viewmodel / utils / capabilities / game / workers` | 目录结构 |
| 页面注册 | HMRouter 路由表 + `main_pages.json`（11 条：Index 根容器、4 个系统 router 演示页、2 个广告页、1 个游戏横幅页、3 个浮窗页） | `main/src/main/resources/base/profile/main_pages.json` |
| 路由 | 两套并存：`@hadss/hmrouter`（主）+ 系统 `router`（RouterDemo 演示） | `PageNames.ets:20-29` |
| 原生 | 一个 CMake 构建 `libhdc_z.so`（6.76MB）+ `libgame.so`（80KB）+ cJSON/openssl/lz4 等 | `main/build-profile.json5:10-15`；HAP 内容实测 |
| Worker | 2 个：`CalcWorker`、`StressWorker`，在模块级注册 | `main/build-profile.json5:5-8` |
| 第三方 | `@hadss/hmrouter`、`@pura/harmony-utils`、`@pura/picker_utils`、`@hw-ads/ads`（bytecode HAR） | `oh-package.json5` |
| 构建变体 | `default / dev / release`，`TargetConstants` 区分 AG 版与 dev 版；自定义 hvigor 插件在非 dev target 移除 `SYSTEM_FLOAT_WINDOW` | `build-profile.json5:44-99`、`main/hvigorfile.ts:20-35` |
| 权限 | 9 个，全部声明在 `main` HAP：悬浮窗、麦克风、相机、后台、网络、Wi-Fi、广告跟踪、手势检测 | `main/src/main/module.json5:55-125` |
| 产物 | dev signed HAP 12.4MB；其中 `libhdc_z.so` 6.76MB、`modules.abc` 1.66MB、`libc++_shared.so` 约 1.2MB×2 ABI | 构建产物实测 |

### 1.2 当前的真实依赖形态

```
MainAbility
 ├─ advertising.init(context)                 ← Ads Kit 在 HAP 里初始化
 ├─ AppUtil.init / BackgroundServiceManager.init
 ├─ GlobalContextHolder / FloatWindowUtil / WindowStageHolder
 ├─ HMRouterMgr.init
 └─ WebServerUtil.start()                     ← 恢复本地 Web 服务

HomePage
 ├─ HMRouterMgr.push(...) → 22 个页面
 ├─ RecordViewModel（录屏设置）
 ├─ WebServerUtil.stop()
 └─ TargetConstants（变体开关）

WebServerUtil ──AppStorage('RecentAccessFile')──> FloatBallPage
MyAVScreenCapture ──> RecordViewModel ──PersistenceV2──> ScreenRecordPage / RecordCard
GameDemoPage ──> libgame.so + WindowStageHolder + WebServerUtil + FloatWindowUtil + GameAdService
HdcDebugPage ──> HdcService ──> libhdc_z.so
```

关键事实：**页面直接 import `utils`、`GlobalContextHolder`、`AppUtil`、`TargetConstants`、`$r('app.media.*')`**。这意味着大部分页面与 HAP 的上下文、资源、变体是硬耦合的；这不是“模块化程度低”的审美问题，而是 HSP 迁移的硬阻塞。

### 1.3 对“SDK 接入模拟”不利的 6 个点

1. **全局上下文是隐式的**：`GlobalContextHolder` / `WindowStageHolder` / `AppUtil` 让任何代码都能拿到宿主上下文；HSP 里这些对象要么不存在，要么是另一份拷贝。
2. **跨包反向依赖**：HSP 页面不能 import HAP 的 `PageNames`、`SpKeys`、`$r('app.media.*')`、`TargetConstants`。现在页面里这些用得很多。
3. **宿主职责没有抽象**：后台长时任务、通知、悬浮窗权限、麦克风/相机权限、ExtensionAbility 都在 HAP；HSP 只能当“能力提供方”，不能当 owner。
4. **第三方 SDK 初始化归属不清**：Ads Kit 在 `MainAbility.onCreate` 初始化；拆 HSP 后到底由 HAP 还是 HSP 初始化、如何避免重复初始化，需要先定契约。
5. **两套路由 + 浮窗页面注册**：HMRouter 页面、系统 `router` 页面、`TYPE_FLOAT` 窗口页面都在 HAP 的 `main_pages.json`；HSP 页面路由是独立问题，必须先做技术验证。
6. **构建链只认识单模块**：`removePermissionPlugin`、`build-*.bat`、`tools/verify_build.ps1` 都按 `module=main` 写死；多模块后要逐个改。

---

## 二、HSP 的能力边界（先定规则，再谈拆分）

### 2.1 HSP 能做什么

- 包含 ArkTS 代码、资源、`rawfile`、原生 `.so`；可被 HAP 或其他 HSP 依赖。
- 支持页面；跨包跳转可用 `@bundle:bundleName/moduleName/ets/pages/Page`，或 `routerMap` / 命名路由。
- 从 API 14 起支持在配置中声明**非入口 UIAbility**；从 API 18 起支持非入口 ExtensionAbility。
- 支持 Worker：加载路径规则为 `{moduleName}/ets/{relativePath}`。
- 进程内一份实例：多个 HAP/HSP 引用同一 HSP 时，代码和资源共享，适合做“SDK 单例”。注意 Worker 线程是独立 VM，跨线程共享需要 `use shared`/Sendable，不能假设 HSP 的普通单例在 Worker 里也是同一对象。
- 可按需加载：`oh-package.json5` 的 `dynamicDependencies` + 动态 `import()`，避免冷启动就把 SDK 拉起来。

参考：[HSP 官方说明](https://developer.huawei.com/consumer/cn/doc/harmonyOS-guides/in-app-hsp)、[跨包路由 FAQ](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1077)、[HSP Worker 加载](https://developer.huawei.com/consumer/cn/doc/harmonyOS-faqs/faqs-arkts-threading-model-9)。

### 2.2 HSP 不能做什么 / 容易误解的点

| 限制 | 对本项目的影响 |
|---|---|
| 不能单独安装/运行，版本必须与 HAP 一致 | 不能模拟“独立升级的 SDK”；HSP 只是包内动态共享 |
| 不能跨应用复用（同一 bundleName 内） | 不能把 HSP 当“对外发布的 SDK”；对外仍是 HAR/服务 |
| 不支持入口 UIAbility | 入口 Ability、桌面入口、备份 Extension 必须留在 HAP |
| 本项目 `compatibleSdkVersion=5.0.5(17)` | API 17 基线不支持 HSP ExtensionAbility（API 18 才有），`MainBackupAbility` 只能留 HAP；非入口 UIAbility（API 14+）可用 |
| 不支持循环依赖、不支持依赖传递 | HAP 必须直接依赖每个要用的 HSP；HSP-A→HSP-B 不能让 HAP 只依赖 A |
| HAR 不能依赖 HSP | 设计系统/契约如果做成 HAR，就不能反向依赖 HSP；状态要显式传递 |
| 权限是应用级，优先级 entry HAP > feature HAP > HSP | 权限继续在 entry HAP 声明和申请；HSP 不要自己申请敏感权限 |
| 总包体积不减少 | 拆 HSP 只降低单 HAP 体积，HSP 仍随应用分发；收益是隔离/共享/懒加载 |

### 2.3 判断“该不该拆 HSP”的 5 条标准

一个模块同时满足 3 条以上，才值得 HSP：

1. **有运行期共享状态**：播放器引擎、会话、连接、缓存、下载队列、广告 loader。
2. **有明确 SDK 边界**：`init(context, config)` / 能力查询 / 事件回调 / `release()`，宿主 UI 不依赖其内部实现。
3. **负载重或可选**：第三方 SDK、原生 `.so`、大资源、只有部分用户会用的功能（按需加载有收益）。
4. **不依赖宿主隐式能力**：不直接拿 `GlobalContextHolder`、`WindowStageHolder`、`AppStorage`、`TargetConstants`；权限/后台/Ability 由宿主负责。
5. **属于媒体主链路或原生负载**：播放、采集、转码、投播、流媒体服务、渲染引擎。

只满足 1–2 条的“薄页面/工具函数”，做 HAR 或留在 HAP 更划算。

---

## 三、候选模块评估

### 3.1 总表

| 候选 | 现有代码 | 媒体/SDK 角色 | 运行期共享价值 | 主要改造/风险 | 建议 |
|---|---|---|---|---|---|
| `hsp_ads` | `AdType`、`AdsKitPreferences`、`GameAdService`、`AdsKitPage`、`AdsHspPage`、`GameBannerPage` | 广告变现 SDK；真实第三方 SDK 接入 | 高：loader、广告位配置、初始化单例 | `SpKeys/PageNames` 抽 HAR；`GameDemoPage` 改调 SDK；banner 子窗口归属；避免 HAP/HSP 各一份 Ads Kit | **P0** |
| `hsp_media_server` | `WebServerUtil`（27KB），后续 `LocalWebPage` | 局域网媒体/文件服务 SDK | 高：TCP server、限速、目录索引 | `AppStorage` 改回调；`BackgroundServiceManager/FloatWindowUtil/TargetConstants` 改 HostBridge；补 HTTP Range/206 才能视频拖动 | **P0/P1** |
| `hsp_recorder` | `MyAVScreenCapture`、`RecordViewModel`、`RecordModel`、`RecordCard`、`ScreenRecordPage` | 录屏/采集中枢，H.264/H.265 + 麦克风 | 高：录制引擎、录制缓存 | 直接调 `BackgroundServiceManager` 要反转；HomePage 设置改 SDK API；权限/图库/后台留宿主；`PersistenceV2` key 归属 | **P1** |
| `hsp_hdc` | `HdcService`、`HdcDebugPage`、`cpp/hdctools*`、`libhdc_z.so` | 原生调试 SDK；6.76MB native 负载 | 高：native 库 + 命令队列 | CMake/so 迁移、`oh-package` 文件依赖、HSP native 打包验证；不是媒体，但“原生 SDK”演示价值最高 | **P2（做原生演示可提 P1）** |
| `hsp_game` | `game/*`、`GameDemoPage`、`cpp/game`、`libgame.so` | 原生 GL 内容/渲染 SDK | 中：引擎、帧缓冲、Surface | 依赖 `WindowStageHolder`（横幅子窗口）、`WebServerUtil`（隐藏浮球）、`GameAdService`；HSP 页面 + 子窗口路径要验证 | **P2** |
| `hsp_floating` | `FloatWindowManager`、`FloatDragHandler`、`FloatWindowUtil`、`floatingclock/*`、`floatingstress/*`、`StressWorker` | 悬浮窗/性能监控 SDK | 中高：窗口控制器、Worker 池 | `SYSTEM_FLOAT_WINDOW` 只能在 HAP；浮窗页面注册在 HAP `main_pages.json`；跨包 `setUIContent` 风险；`TargetConstants` 变体 | **P2（最后做）** |
| `hsp_h5` | `H5Page`、`URLParserUtil`、`UrlHistoryUtil`、`ScanQrOverlay` | H5/Web 媒体容器 | 低：每页一个 Web controller | 页面型、无强单例；`GlobalContextHolder`、相机/扫码权限 | 不建议 HSP；HAR 或留 HAP |
| `hsp_qr_scan` | `QrCodePage`、`QrCodeUtil`、`ScanQrOverlay` | 扫码/二维码能力 | 低 | ScanKit + 相机权限；页面小 | 不建议 HSP；留 HAP/HAR |
| `ui_kit` | `GlassCard/GlassButton/PageHeader/SettingGroup/SettingSwitchItem/WallpaperHost`、`ImmersiveStyles/LightSense/SafeArea/Toast` | 设计系统 | 主题状态有共享需求，但组件基本无状态 | HAR 不能依赖 HSP；`LightSense` 单例跨包会分裂；`AppUtil/PreferencesUtil` 拷贝不共享 | **HAR 优先**；只有主题实时共享确有需要才拆 `hsp_theme` |
| `sdk_contract` | 新增：接口、HostBridge、版本、事件名 | SDK 契约 | 无运行期状态 | 无 | **HAR（P0 前置）** |
| `common` | `PageNames`、`SpKeys`（以及必要的 `AdType`） | 共享常量 | 无 | 页面/HSP 都要用，必须抽走 | **HAR（P0 前置）** |

### 3.2 P0：`hsp_ads`（广告 SDK）

**为什么是第一个**

- 已有完整的“SDK 接入”链路：初始化、广告位配置、加载、展示、回调、Mock 兜底。
- `AdsHspPage` 名字叫 HSP，实际是 HAP 里的普通页面；把它变成真正的 HSP 页面/组件，演示效果最直接。
- 代码量小（3 个核心文件 + 2 个页面 + 1 个 banner 页），边界相对清楚。
- 广告是媒体应用最常见的第三方 SDK，拆完可以复用到播放器暂停、开屏、激励、游戏。

**建议目标结构**

```
hsp_ads/
  src/main/ets/
    api/AdsSdk.ets            // init/ensureInit/showRewarded/showInterstitial/showSplash/getConfig
    api/AdsTypes.ets          // AdOutcome、AdSlot、AdsConfig（或放 sdk_contract）
    internal/AdsKitPreferences.ets
    internal/GameAdService.ets // 重命名为 AdsServiceImpl
    pages/AdsKitPage.ets
    pages/AdsHspPage.ets
    components/BannerAdView.ets
    components/NativeAdView.ets
```

**宿主保留**

- `APP_TRACKING_CONSENT` 权限、隐私同意流程、`advertising.init` 的调用时机决策。
- `GameBannerPage` 的子窗口创建（`WindowStageHolder` 是宿主能力）；页面里只放 HSP 导出的 `BannerAdView`。
- 首页入口、HMRouter 根容器、主题/壁纸。

**必须改的耦合**

| 现状 | 改法 |
|---|---|
| `MainAbility.onCreate` 里 `advertising.init(this.context)` | HAP 调 `AdsSdk.init(context, config)`；HSP 内部只初始化一次，重复调用幂等 |
| `GameDemoPage` 直接 import `GameAdService` | HAP 调 `AdsSdk.showRewarded(context, slot)`；如果游戏也进 HSP，则 HSP→HSP 依赖 |
| `AdsKitPage/AdsHspPage` import `PageNames`、`SpKeys` | 抽到 HAR `common`；或 HSP 自带 `AdsRoutes` 常量 |
| `GameBannerPage` 直接用 `AutoAdComponent` | HAP 不再依赖 `@hw-ads/ads`；改 import HSP 的 `BannerAdView` |
| 页面资源 `$r('app.media.*')` | 用到的图片/字符串搬进 HSP 的 `resources`，HAP 用 `$r('[hsp_ads].media.*')` |
| 广告位偏好读写 | 由 HSP 内部用平台 `preferences` + 自己的文件名；不要依赖 `AppUtil` 的全局初始化 |

**验收**

- HAP 的 `oh-package.json5` 不再出现 `@hw-ads/ads`；`unzip -l` 确认广告资源只在 HSP 中。
- `default` / `dev` 两个 product 都能构建；广告位配置、加载、展示、激励回调正常。
- 冷启动不打开广告页时，HSP 是否加载可观测（静态 import vs `dynamicDependencies` + `import()`）。
- `GameDemoPage` 的激励/插屏/开屏仍能走通；`GameBannerPage` 子窗口无白屏。

### 3.3 P0/P1：`hsp_media_server`（局域网媒体服务）

**为什么适合 HSP**

- `WebServerUtil` 是纯 ArkTS + NetworkKit，无 UI、无 Ability，天然是“headless SDK”。
- 单例、长期运行、有连接/限速状态，放 HSP 才有“进程内一份”的意义。
- 对“全能媒体”最有价值：手机上的视频/音频/图片通过局域网给 TV/PC/浏览器播放，是最直观的媒体能力。

**建议分两步**

1. **先 headless**：只把 `WebServerUtil` 搬进 HSP，导出 `MediaServerSdk`；`LocalWebPage` 继续留 HAP 调 SDK。这是最干净的 SDK 边界，也最容易验证。
2. **再页面**：路由/资源验证通过后，再把 `LocalWebPage` 搬进 HSP；`FloatBallPage` 继续留 HAP（系统浮窗页面）。

**SDK 接口建议**

```ts
export interface MediaServerConfig {
  rootDir: string;          // 宿主传 filesDir + '/wwwroot'
  port: number;             // 默认 8088
  maxTransferMb: number;
}

export interface MediaServerSdk {
  init(context: common.UIAbilityContext, config: MediaServerConfig): Promise<void>;
  start(): Promise<string>;     // 返回访问 URL
  stop(): Promise<void>;
  isRunning(): boolean;
  getAccessUrl(): string;
  onFileAccess(cb: (fileName: string) => void): void; // 替代 AppStorage('RecentAccessFile')
  setRateLimit(path: string, minutes: number): void;
}
```

**必须改的耦合**

- `AppStorage.setOrCreate('RecentAccessFile', ...)`（`WebServerUtil.ets:94,125`）→ 回调/事件；悬浮球由 HAP 订阅。
- `BackgroundServiceManager.startWebServer/stopWebServer`（`LocalWebPage.ets:347-362`）→ `HostBridge.requestBackgroundTask('web')`；宿主仍是唯一 owner。
- `FloatWindowUtil.show/destroy`、`TargetConstants.HAS_FLOATING_PERM` → 宿主能力回调；HSP 不判断变体。
- `WebServerUtil.init(filesDir + '/wwwroot', 8088)` 由宿主传入，不要在 HSP 里读全局上下文。

**媒体化增强（拆的时候顺手做）**

当前 Web 服务只返回整文件，**没有 HTTP Range/206**（只在 `WebServerUtil.ets:675` 有 `video/mp4` MIME）。浏览器里视频不能拖动进度条。既然要叫“媒体服务”，建议加：

- `Range: bytes=...` 解析 + `206 Partial Content` + `Content-Range` + `Accept-Ranges: bytes`；
- 大文件流式发送（已有 64KB 分片，可复用）；
- 简单的媒体索引/缩略图（可选）。

**验收**

- 手机起服务，PC 浏览器打开 `http://<ip>:8088/` 能列目录、播放 mp4、拖动进度。
- 上传 200MB 文件、下载、限速 429、路径越界 403 不回归。
- 后台长时任务仍由 HAP 发起；退出页面后服务状态与通知正确。
- HAP 不再 import `WebServerUtil` 内部实现，只 import `MediaServerSdk`。

### 3.4 P1：`hsp_recorder`（录屏/采集）

**为什么适合 HSP**

- `AVScreenCaptureRecorder` 是标准媒体管线：采集 → 编码（H.264/H.265）→ 写文件；有明确的 start/stop/stateChange 生命周期。
- `RecordViewModel` 是单例 + `PersistenceV2`，适合 SDK 内部管理录制会话与缓存。
- 宿主职责清晰：权限申请、后台长时任务、通知、图库保存确认。

**建议目标结构**

```
hsp_recorder/
  api/RecorderSdk.ets          // start/stop/isRecording/getRecordings/setMic/setPreset
  api/RecorderTypes.ets
  internal/MyAVScreenCapture.ets
  internal/RecordViewModel.ets
  model/RecordModel.ets
  components/RecordCard.ets
  pages/ScreenRecordPage.ets
```

**必须改的耦合**

- `MyAVScreenCapture.ets:6,89` 直接调 `BackgroundServiceManager.start/stopRecordingTask` → `HostBridge` 回调，宿主决定长时任务。
- `HomePage.ets:1209-1219` 直接读写 `RecordViewModel` 的 preset/mic → `RecorderSdk.getConfig()/setConfig()`。
- `ScreenRecordPage` 的 `PageHeader/GlassCard/GlassButton/SafeArea/Toast` → HAR `ui_kit`。
- `RecordCard` 的图库保存（`photoAccessHelper`、`@pura/picker_utils`）→ 用宿主传入的 context；不要依赖 HSP 里未初始化的 `AppUtil`。
- 权限 `MICROPHONE`、`KEEP_BACKGROUND_RUNNING` 继续在 HAP 声明和申请。

**验收**

- H.264/H.265 录制、麦克风开关、系统胶囊停止、自动保存记录、保存到图库全链路。
- 录制中退到后台，长时任务/通知正常；停止后无 `9800005`。
- HAP 的 `RecordViewModel` 引用清理干净（HomePage 只依赖 SDK API）。

### 3.5 P2：`hsp_hdc`（原生 HDC SDK）

**为什么值得做（即使它不是媒体）**

- HAP 里 `libhdc_z.so` 是 **6.76MB**，是单包最大单体；把它搬进 HSP，HAP 单包体积下降最明显。
- 它是“带 native 负载的 SDK”最真实的演示：ArkTS API + `.so` + CMake + 文件/网络依赖。
- 自包含页面 `HdcDebugPage`，适合做“SDK 自带 UI”的第二种形态。

**迁移要点**

- 把 `src/main/cpp/hdctools*`、`src/main/cpp/hdctools_src`、`src/main/cpp/third_party/{cJSON,lz4,openssl,libusb}`、`types/libhdc_z` 搬进 HSP；HSP 的 `build-profile.json5` 配 `externalNativeOptions` 与 `abiFilters`。
- `main/oh-package.json5` 的 `"libhdc_z.so": "file:./src/main/cpp/types/libhdc_z"` 迁到 HSP 的 `oh-package.json5`。
- `HdcDebugPage` 依赖的 `SpKeys`、`ImmersiveStyles`、`GlassButton`、`SafeArea` 抽 HAR。
- HAP 只 import `HdcSdk`；`MainAbility` 不再需要 HDC 相关初始化。
- 注意 `hdctools` 里的 cJSON/openssl 与未来其他 native HSP 的符号/静态库重复；**短期只做一个 native HSP**，避免 `libcjson`、`libssl` 冲突。

**验收**

- HAP 内不再有 `libs/arm64-v8a/libhdc_z.so`；HSP 内有。
- HDC 终端连接、shell 命令、文件收发、超时/并发保护正常。
- 两个 product 的 `abiFilters` 一致；模拟器 x86_64 不回归（如果仍支持）。

### 3.6 P2：`hsp_game`（原生 GL 内容 SDK）

**现状**

`GameDemoPage` 是“整屏一个 XComponent + `libgame.so` 画棋盘/UI”的重度页面，依赖面很广：

- `libgame.so`、`GameEngine/GameBoard/GameRenderer/GameUi`；
- `WindowStageHolder`（横幅子窗口 `GameBannerPage`）；
- `WebServerUtil`（判断 Web 服务运行时隐藏浮球）；
- `FloatWindowUtil`（隐藏/恢复浮球）；
- `GameAdService`、`AdsKitPreferences`；
- 状态栏/安全区/窗口全屏。

**建议**

- 先只把 `game/*` + `libgame.so` + 原生 cpp 抽成 HSP，页面壳（`GameDemoPage`）留 HAP；HSP 导出 `GameEngineApi`，HAP 负责 XComponent、窗口、广告、浮球。
- 或者整页搬 HSP，但 `GameSdk.start(context, windowStage)` 显式接收宿主窗口；`GameBannerPage` 的子窗口仍由 HAP 创建，HSP 只提供 `BannerAdView`。
- 不建议和 `hsp_hdc` 同时做：两个 native HSP 的构建/符号/ABI 问题会叠在一起。

**验收**

- XComponent Surface 正常、棋盘/UI 渲染、触摸命中、广告激励/插屏/开屏、横幅子窗口、浮球隐藏恢复。
- 冷启动不进入游戏页时，`libgame.so` 不被加载（如果使用动态 import）。

### 3.7 P2：`hsp_floating`（悬浮窗/性能监控）

**适合的部分**

- `FloatWindowManager`、`FloatDragHandler`、`FloatClockManager`、`StressFloatWindowManager`、`StressKernel`、`StressWorker` 都是“窗口/Worker 控制逻辑”，可以共享。
- `StressCapsule`、`StressRing` 是纯 UI 组件，可以导出给宿主浮窗页使用。

**高风险点**

- `SYSTEM_FLOAT_WINDOW` 是敏感权限，当前由 HAP 的 `removePermissionPlugin` 在非 dev target 移除；HSP 不能接管这个逻辑。
- 浮窗页面（`FloatClockPage`、`StressCapsulePage`、`FloatBallPage`）注册在 HAP 的 `main_pages.json`；`TYPE_FLOAT` 窗口的 `setUIContent('pages/...')` 是否能加载 HSP 页面需要实测。
- 建议：**HSP 只放 Manager/Worker/组件，HAP 保留 3 个浮窗 wrapper 页面**；不要一开始就追求“浮窗 UI 也在 HSP”。
- `TargetConstants.HAS_FLOATING_PERM` 通过 `HostBridge.canUseFloatingWindow()` 传入，HSP 不感知构建变体。

### 3.8 不建议拆 HSP 的模块

| 模块 | 原因 | 更合适的位置 |
|---|---|---|
| `HomePage`、`Index`、`GuidePage`、`PrivacyPage` | 宿主壳：导航容器、隐私同意、设置、壁纸、工具入口；必须拥有 HAP 上下文与路由栈 | HAP |
| `RouterDemo*`、`RouterSplashPage`、`RouterMainPage` | 系统 `router` 栈演示，属于宿主路由能力 | HAP |
| `MainAbility`、`MainBackupAbility` | 入口 Ability / ExtensionAbility；HSP 不支持入口 Ability，API17 基线不支持 ExtensionAbility | HAP |
| `TargetConstants`（`src/dev`/`src/product` 覆盖） | 构建变体开关；HSP 应通过配置/HostBridge 获取能力，而不是复制变体文件 | HAP + HostBridge |
| `WallpaperUtil`、壁纸裁剪、主题设置 | 宿主视觉/存储；`WallpaperHost` 是 HAR 组件即可 | HAP + HAR |
| `StringConverter`、`DeviceInfoPage`、`CalcPage` | 薄页面/系统 API 包装，无运行期共享价值；HSP 化只会增加跨包资源/路由成本 | HAP 或 HAR |
| `AppLinkingTool`、`QrCodePage`、`H5Page` | 页面型工具；没有引擎/会话/缓存需要共享；相机/扫码权限在宿主 | HAP（组件可进 HAR） |
| `CommonViewModel`、`GlobalContextHolder`、`WindowStageHolder` | 宿主全局状态；HSP 不应直接依赖 | HAP；通过契约传递 |

### 3.9 HAR 与 HSP 的分工

| 层 | 类型 | 内容 | 原因 |
|---|---|---|---|
| `sdk_contract` | **HAR** | `MediaSdk`/`AdsSdk`/`RecorderSdk` 接口、`HostBridge`、`SdkError`、`SdkVersion`、事件名 | 所有 HSP 和 HAP 都依赖；不能有实现，避免循环 |
| `common` | **HAR** | `PageNames`、`SpKeys`、路由/偏好 key | HSP 页面和 HAP 都要用；放 HAP 会导致 HSP 反向依赖 |
| `ui_kit` | **HAR（优先）** | `GlassCard`、`GlassButton`、`PageHeader`、`SettingGroup`、`WallpaperHost`、`ImmersiveStyles`、`SafeArea`、`Toast` | 无状态 UI；HSP 页面可直接用 |
| `hsp_theme`（可选） | **HSP** | `LightSense` 单例 + 主题状态 | 只有确认“HSP 页面必须实时跟随 HAP 主题”才拆；HAR 副本的 `lightSenseState` 会各自一份 |
| 各 SDK | **HSP** | 引擎/服务/原生负载 | 单例、懒加载、隔离 |

**一个必须注意的坑**：`@pura/harmony-utils` 的 `AppUtil`/`PreferencesUtil` 是模块级静态状态。HAP 调过 `AppUtil.init(context)`，不代表 HSP 里的那份拷贝也初始化了；HSP 里的 `Toast`（`AppUtil.getUIContext()`）、`SafeArea`（`getNavigationIndicatorHeight()`）、`PreferencesUtil` 可能拿到空上下文或 0。**HSP 内要么在 `init(context)` 里重新初始化自己那份，要么直接用平台 API + 显式 context。**

---

## 四、面向“全能媒体”的目标架构

### 4.1 目标分层

```
┌─────────────────────────────────────────────────────────────┐
│ Entry HAP（宿主 / Host Shell）                                │
│  MainAbility · Index · HomePage · Guide/Privacy · Settings   │
│  权限申请 · 后台长时任务 · 通知 · 悬浮窗 · 壁纸/主题 · 路由栈     │
│  只做编排：调用 SDK、提供 HostBridge、展示 UI                   │
└───────────────┬─────────────────────────────────────────────┘
                │ 依赖（HAP → HAR/HSP）
┌───────────────▼─────────────────────────────────────────────┐
│ HAR：sdk_contract（接口/HostBridge/版本）                     │
│ HAR：common（PageNames/SpKeys/路由 key）                      │
│ HAR：ui_kit（Glass* / PageHeader / WallpaperHost / Toast）    │
└───────────────┬─────────────────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────────────────┐
│ HSP：media_core（播放器/AVSession/播放列表/解码/DRM）          │
│ HSP：media_ui（播放页/控制条/手势/弹幕，可选）                  │
│ HSP：media_ads（广告 SDK：开屏/激励/插屏/横幅/原生）            │
│ HSP：media_server（局域网媒体服务/目录/上传/Range）             │
│ HSP：media_recorder（录屏/采集/转码/保存）                     │
│ HSP：media_cast（投播/AVCast，可选）                           │
│ HSP：media_analytics（播放/广告事件，可选）                    │
│ HSP：hdc_sdk / game_sdk（原生负载演示，可选）                  │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 SDK 契约（HAR）建议

```ts
// sdk_contract/HostBridge.ets
export interface HostBridge {
  getContext(): common.UIAbilityContext;
  requestBackgroundTask(kind: 'playback' | 'record' | 'server'): Promise<void>;
  releaseBackgroundTask(kind: 'playback' | 'record' | 'server'): Promise<void>;
  canUseFloatingWindow(): boolean;
  showFloatingBall(): Promise<void>;
  hideFloatingBall(): Promise<void>;
  toast(message: string): void;
  getSafeAreaBottom(): string;
  log(level: 'info' | 'warn' | 'error', tag: string, message: string): void;
}

export interface SdkModule {
  readonly version: string;
  init(context: common.UIAbilityContext, host: HostBridge, config: object): Promise<void>;
  release(): Promise<void>;
}
```

原则：

- **HostBridge 是唯一反向通道**；HSP 不 import HAP 的任何东西。
- HSP 不直接读写 `AppStorage`；需要跨页共享时用 SDK 自己的可观察状态 + 事件。
- 所有回调/事件在契约里定义；HSP 内部类不暴露给 HAP。
- `init` 必须幂等；`release` 必须可重复调用；错误码统一。

### 4.3 当前缺失的媒体能力（比拆旧模块更重要）

如果“全能媒体”是产品目标，当前应用缺的是**媒体主链路**，不是模块化：

| 能力 | 现状 | 建议 |
|---|---|---|
| 本地/网络视频播放 | 只有 H5 `Web`，没有 AVPlayer | 新建 `hsp_media_core`：AVPlayer + XComponent/Surface + 状态机 + 进度/缓冲/错误 |
| 后台音频/媒体会话 | 无 AVSession | `media_core` 内接 AVSession；后台长时任务由 HAP 持有 |
| 投播 | 无 AVCast | `hsp_media_cast`，或先做投播 UI + AVSession 占位 |
| 媒体库/缩略图 | 无 | HAP 媒体选择器 + HSP 索引/缩略图服务 |
| 下载/缓存 | 无 | `hsp_media_download`：队列、断点、限速 |
| 播放广告 | 只有游戏广告 | `hsp_ads` 接到播放器暂停/开局/激励场景 |
| 媒体服务 | 有 WebServer，但无 Range | `hsp_media_server` 补 Range/206，变成真正的流媒体服务 |
| 采集/录制 | 有 AVScreenCapture | `hsp_recorder` 抽出；后续可加剪辑/转码 |
| 分析/埋点 | 无 | `hsp_analytics`：播放、广告、错误事件 |

**建议顺序**：先做 `sdk_contract` + `hsp_ads`（验证 HSP 工程链路）→ `hsp_media_core`（媒体主角）→ `hsp_media_server` / `hsp_recorder` → 原生演示（`hsp_hdc`/`hsp_game`）→ `hsp_cast`/`hsp_analytics`。

---

## 五、迁移路线（按可验证的纵切，而不是一次性大爆炸）

### Phase 0：抽 HAR（1–2 天，不改行为）

1. 新建 `sdk_contract` HAR：接口、HostBridge、版本、错误码；先不实现。
2. 新建 `common` HAR：`PageNames`、`SpKeys`；全仓改 import。
3. 新建 `ui_kit` HAR：`Glass*`、`PageHeader`、`SettingGroup`、`SettingSwitchItem`、`WallpaperHost`、`ImmersiveStyles`、`SafeArea`、`Toast`；处理 `LightSense` 的跨包状态问题（先保持 HAP 使用，HSP 页面暂不依赖主题实时同步）。
4. 基线：`pwsh -File tools/verify_build.ps1` 通过；HAP 行为不变。

> 注意：HAR 不能依赖 HSP；所以 `ui_kit` 不能 import 任何未来的 HSP。`ui_kit` 里的 `LightSense` 如果保留单例，HSP 页面读到的是自己那份拷贝——要么改成读 `AppStorage`，要么把主题放 HSP。

### Phase 1：`hsp_ads` 纵切（2–4 天）

1. 新建 `hsp_ads` 模块（`type: "shared"`），把广告相关代码搬入。
2. HAP `oh-package.json5` 加依赖；`module.json5` 加 `dependencies`（`bundleName` + `moduleName`）。
3. HAP 删掉 `@hw-ads/ads` 直接依赖与 `MainAbility` 的 `advertising.init`；改调 `AdsSdk.init`。
4. 路由验证：先让 `AdsKitPage` 继续留 HAP（只调 SDK API），再试把页面搬进 HSP（HMRouter 跨包路由；失败则用 `@bundle` 或系统 `routerMap`）。
5. 验收：两个 product 构建、广告加载/展示/回调、HAP 无广告资源、冷启动不崩。

### Phase 2：`hsp_media_server` headless（2–3 天）

1. 搬 `WebServerUtil`，定义 `MediaServerSdk`。
2. `AppStorage('RecentAccessFile')` 改 `onFileAccess`；HAP 的 `FloatBallPage` 订阅。
3. `LocalWebPage` 改调 SDK；后台/浮球/变体判断留在 HAP。
4. 补 Range/206 与视频拖动；验收局域网播放/上传/限速/越界。
5. 可选：页面搬 HSP（需要路由/资源验证）。

### Phase 3：`hsp_recorder`（3–5 天）

1. 搬采集 + VM + 页面 + RecordCard；`BackgroundServiceManager` 改 HostBridge。
2. HomePage 设置改 `RecorderSdk` API；权限/图库保存留宿主。
3. 验收 H.264/H.265、麦克风、胶囊停止、后台、图库。

### Phase 4：原生演示（5–8 天，二选一先做）

- `hsp_hdc`：搬 cpp + `libhdc_z.so` + 页面；验证 HAP 不再含 6.76MB `.so`、HSP native 正常。
- 或 `hsp_game`：搬 `game/*` + `libgame.so`；页面壳留 HAP，HSP 只提供引擎；验证 XComponent/广告/子窗口。

### Phase 5：可选/收尾

- `hsp_floating`（Manager/Worker/组件先搬，页面留 HAP）。
- `hsp_cast`、`hsp_analytics`、`hsp_media_core` 迭代。
- 更新 `build-*.bat`、`tools/verify_build.ps1`：多模块构建、HSP 产物检查、包体积对比、真机冒烟。

### 每阶段统一验收

```powershell
# 1. 两个 product 构建
pwsh -File tools/verify_build.ps1

# 2. 检查 HAP/HSP 归属（HAP 不应再有被搬走的代码/so/资源）
#    .hap/.hsp 本质是 zip，可用 Expand-Archive 或 System.IO.Compression 列内容

# 3. 真机安装 + 冷启动 + 目标功能 + 崩溃日志
hdc -t <target> install <hap>
hdc -t <target> shell hilog -x -e 'jscrash|HSP|Ads|MediaServer|Recorder' -L E
```

> 构建脚本目前写死 `module=main@dev`（`build-dev.bat`）。多模块后要补 HSP 的构建/打包检查，否则“HSP 没进包”会在真机上才暴露。

---

## 六、本项目专属风险清单

### 6.1 路由（最高风险）

- HMRouter 声称支持 HAR/HSP，但插件路由表生成/合并在 HSP 下需要实测；社区反馈有“HSP 打包后跳转失败”的版本问题。
- 备选方案：
  1. HSP 只做 headless API，不搬页面（最稳，推荐先这样）。
  2. HSP 页面用系统 `router.pushUrl('@bundle:bundleName/moduleName/ets/pages/Page')`。
  3. HSP `module.json5` 配 `routerMap`，用 `NavPathStack.pushPathByName`；HAP 的 `HMNavigation` 与系统 `Navigation` 混用要评估。
- 浮窗页面（`TYPE_FLOAT`）不要放 HSP；保留 HAP wrapper 页。

### 6.2 资源

- HSP 有自己的 `resources`；HSP 页面里的 `$r('app.media.x')` 解析到 HSP 自己的资源，不是 HAP 的。
- 宿主访问 HSP 资源：`$r('[hsp_ads].media.banner')` / `$rawfile('[hsp_ads].xxx')`；没有编译期校验，改名/漏搬只会在运行时暴露。
- 页面用到的图标、字符串、颜色要随页面一起搬；不要假设 HAP 资源还能用。
- `main_pages.json` 只属于 HAP；HSP 页面要自己的 `main_pages.json` 或 HMRouter 路由表。

### 6.3 全局单例 / 第三方库

- `AppUtil`、`PreferencesUtil`、`ToastUtil`、`PickerUtil` 是 HAR 拷贝，HAP 初始化不会传递给 HSP；HSP 里可能拿到空 context / 0 安全区。
- 解决：HSP `init(context)` 内重新初始化自己那份，或直接使用 `@kit.*` + 显式 context；不要在 HSP 里用 `AppUtil.getUIContext()`。
- `PersistenceV2`/`AppStorage` 是应用级，跨 HSP 通常可见，但**不要把它当 SDK API**；用回调/可观察状态，避免 key 冲突。
- `LightSense` 单例：HAR 副本各一份；HSP 页面不会跟随 HAP 设置滑杆实时变化，除非改成 `AppStorage` 读取或把主题放 HSP。

### 6.4 权限 / Ability / 后台任务

- 权限继续在 entry HAP 声明和申请；HSP 只使用已授予的权限。
- `MainBackupAbility` 留 HAP（API17 基线不支持 HSP ExtensionAbility）。
- 后台长时任务 owner 继续是 `BackgroundServiceManager`；HSP 通过 HostBridge 请求/释放，禁止 HSP 自己 `startBackgroundRunning`。
- `SYSTEM_FLOAT_WINDOW` 的 target 差异由 HAP 的 `removePermissionPlugin` 处理；HSP 不要声明它。

### 6.5 悬浮窗

- `window.createWindow` + `setUIContent` 的页面路径跨包是否可用要实测；最稳的是 HAP 保留 wrapper 页面，HSP 提供 Manager + 组件。
- 拖拽/尺寸/密度逻辑可以搬，但窗口名、权限、屏幕信息由宿主传。

### 6.6 Worker / Native

- HSP Worker 加载路径为 `{moduleName}/ets/{relativePath}`；在 `build-profile.json5` 的 `sourceOption.workers` 注册；`useNormalizedOHMUrl: true` 下要验证路径解析。
- 原生 `.so`：HSP 的 `build-profile.json5` 配 `externalNativeOptions`；`abiFilters` 与 HAP 一致；types 的 `oh-package` 文件依赖跟着搬。
- 多个 native HSP 容易在 cJSON/openssl/lz4 上符号冲突；**先只做一个 native HSP**。
- 搬完后检查 HAP 内不再有旧 `.so`（当前 `libhdc_z.so` 6.76MB）。

### 6.7 构建变体 / 包体积

- 本项目有 `default` / `dev` / `release` 三个 product，HSP 模块也要有对应 target；否则某个 product 构建会找不到 HSP。
- HAP `module.json5` 的 `dependencies` 里 `bundleName` 在两个 product 下不同（`com.xuchaoji.hmos.supertools` vs `.dev`）；需要 target 级覆盖或统一策略，先在 dev 验证。
- HSP 不会减小总包；如果目标是“下载体积”，要配合 feature HAP/动态交付，而不是单纯 HSP。
- HSP 版本必须与 HAP 一致；不能靠 HSP 做热更新。

### 6.8 测试

- 每个阶段都要过：冷启动、进入/退出页面、后台/前台、进程被杀后恢复、两个 product、目标设备。
- 广告/HSP 加载失败要有降级（Mock/隐藏入口），不要让 SDK 拖垮宿主。
- 关注 `hilog` 中 HSP 加载失败、`hap_path_error`、`resolveBufferCallback`、`jscrash`。

---

## 七、建议的“SDK 实验台”演示场景

把首页从“工具箱”扩成“SDK 实验室”，每个 HSP 一个实验卡：

| 场景 | 宿主动作 | HSP 动作 | 验证点 |
|---|---|---|---|
| 广告 SDK | 启动/暂停时调 `AdsSdk` | 加载/展示开屏、激励、插屏、横幅 | 初始化归属、回调、HAP 无广告资源 |
| 媒体服务 SDK | 选目录、起服务、请求后台任务 | TCP server、目录、Range、上传 | 浏览器播放/拖动、后台/通知/浮球 |
| 录屏 SDK | 申请麦克风/后台权限 | AVScreenCapture 录制/停止 | 胶囊停止、图库保存、长时任务 |
| 原生 HDC SDK | 打开终端页 | `libhdc_z.so` 命令执行 | HAP 体积下降、HSP native 加载 |
| GL 游戏 SDK | 提供 WindowStage/XComponent | 引擎/渲染/帧缓冲 | Surface、触摸、广告子窗口 |
| 播放器 SDK（新建） | 提供 Surface/生命周期 | AVPlayer/AVSession/状态机 | 播放/暂停/seek/后台/音频焦点 |
| 投播 SDK（新建） | 发现设备/UI | AVCast/会话 | 投播连接/断开/回切 |

每个实验卡建议显示：SDK 版本、是否已加载、加载耗时、init 结果、能力列表、错误码、日志。这样“模拟 SDK 接入”才不只是模块拆分，而是可观测的接入验证。

---

## 八、参考

- [HSP 官方说明（能力/限制/UIAbility/ExtensionAbility）](https://developer.huawei.com/consumer/cn/doc/harmonyOS-guides/in-app-hsp)
- [HAP 与 HAR/HSP 页面跳转（@bundle 协议）](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1077)
- [声明权限（多 HAP 场景与优先级）](https://developer.huawei.com/consumer/cn/doc/harmonyOS-guides/declare-permissions)
- [HSP 中 Worker 加载路径](https://developer.huawei.com/consumer/cn/doc/harmonyOS-faqs/faqs-arkts-threading-model-9)
- [Native 侧跨 HAR/HSP 接口调用](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/native-cross-har-hsp-interface-call)
- [跨模块资源访问（`$r('[hsp].media.x')`）](https://developer.huawei.com/consumer/cn/doc/best-practices-V5/bpta-cross-module-resource-access-V5)
- [HAR/HSP 依赖约束（HAR 不能依赖 HSP、无循环/传递）](https://developer.huawei.com/consumer/cn/doc/harmonyOS-guides/har-package)
