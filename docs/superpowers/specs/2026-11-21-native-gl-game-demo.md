# 模拟游戏入口（整屏原生渲染的三消）设计与验证记录

> 状态：已实现并通过真机验证（2026-11-21，第二版：整屏单 Surface）
> 目标：在工具箱里加一个"模拟游戏类应用"入口，作为**游戏媒体广告变现**的测试宿主。
> 硬约束：
> 1. 棋盘**不能**是 ArkUI 布局（否则 `uitest dumpLayout` 能直接抓到 64 个格子）；
> 2. 不能是 ArkWeb（H5 游戏同样会被抓 DOM）；
> 3. **HUD、按钮、弹窗、调试面板也不能是 ArkUI 控件**——开启"显示布局边界"时，
>    整屏应当像一个完整的游戏 Surface，而不是一堆 App 控件（对齐开心消消乐等真实游戏）。
>
> 实现结论：页面里只保留一个全屏 `XComponent`；棋盘用 GL 画，其余所有 UI 用
> `OH_Drawing` 离屏画成透明纹理叠加；触摸命中测试在 ArkTS 里基于原生坐标完成。

---

## 一、为什么不用 Gemini 文档里的 Cocos 方案

`D:\download\鸿蒙消除类游戏开发指导.md` 描述的是 **Cocos Creator 3.8 原生导出 + `build-templates/harmonyos/`**
的独立宿主工程。它和本工程不兼容：

| 文档要求 | 本工程现实 | 结论 |
|---|---|---|
| Cocos 3.8 + `build-templates/harmonyos/` 覆盖产物 | 工程本身就是原生宿主，没有 Cocos 构建链 | 无法直接套用 |
| 独立 `entry` 模块（Cocos 生成的 Ability + 页面） | 已有 MainAbility/HMRouter/双 target + 签名 | 塞不进现有应用 |
| `JsBridge.ets` + `window.__onHarmonyAdEvent` JSON 协议 | Ads Kit 直接 ArkTS 调用，无 JS 线程 | 协议多余 |
| 事件 `onAdLoaded/onAdShow/onAdRewarded/onAdClosed` | 实测 Ads Kit 是 `onAdOpen/onAdClose/onAdReward/...` | 必须按真实 SDK 重写 |
| `tsc --noEmit` / `tsx --test` | 无 npm 工程 | 改为真机 uitest + 调试面板自检 |

保留文档的玩法与广告场景设计，工程与广告层全部重写。

## 二、总体架构（第二版：整屏单 Surface）

```
GameDemoPage.ets
└─ Stack（ArkUI 要求 @Entry 的 build 根必须是容器）
   └─ XComponent(SURFACE, 全屏)      ← 布局树里唯一的可见控件
        └─ libgame.so
             ├─ 棋盘层：EGL/GLES2 画背景、棋盘底板、64 个方块、动画
             ├─ UI 层：OH_Drawing 离屏画 HUD/按钮/弹窗/调试面板 → RGBA 纹理 → 叠加
             ├─ NAPI：setFrame / setUiRects / setUiTexts / pollTouch / getSurfaceSize
             └─ 触摸：DispatchTouchEvent → ArkTS 每帧 pollTouch

GameEngine.ets   三消状态机 + 动画时间线 + 棋盘帧装配（按归一化棋盘矩形布局）
BoardModel.ets   纯逻辑（8×8、无初始三连、有效步、下落补齐、死局洗牌）
GameUi.ets       UI 显示列表（矩形 + 文本）
GameAdService.ets 激励/插屏/开屏 + Mock 兜底
```

### 为什么 UI 也走原生

第一版只把棋盘放进 XComponent，HUD/按钮/弹窗仍是 ArkUI。开启"显示布局边界"后，
游戏中仍能看到一排排文本框和按钮边框，和真实游戏"整屏一个控件"的观感不一致。

第二版把 UI 也下沉：
- 矩形（卡片、按钮、遮罩）由 `OH_Drawing_CanvasDrawRoundRect` 画；
- 文本由 `OH_Drawing_Typography` 排版（系统字体，中文/数字/粗体都正常）；
- 整张 UI 画到与 Surface 等大的 RGBA 位图，上传为纹理，再叠加到棋盘上；
- UI 只在"显示列表变化"时重绘（分数、步数、弹窗、日志），不随 60fps 动画重排。

### 显示列表协议

| 数据 | 格式 |
|---|---|
| 棋盘矩形 `setFrame` | `Float32Array`：`[count,0,(x,y,w,h,r,g,b,a,radius,glow)*n]`，归一化 0..1 |
| UI 矩形 `setUiRects` | 同上（复用同一顶点/着色器格式） |
| UI 文本 `setUiTexts` | `string[]` + `Float32Array`：每项 9 个 float `x,y,size,r,g,b,a,align,bold` |

`x/y` 归一化；`size` 相对 Surface 高度；`align` 0 左 / 1 中 / 2 右；`bold` 0/1。

### 输入

**SURFACE 类型的 XComponent 收不到 ArkTS 的 `.onTouch`**（第一版实测：原生
`DispatchTouchEvent` 有事件、ArkTS 回调完全不触发）。因此：

1. 原生回调记录 DOWN/MOVE/UP 与归一化坐标；
2. ArkTS 每帧 `pollTouch()` 取走 `[down,dx,dy,move,mx,my,up,0]`；
3. ArkTS 先按显示列表里的按钮矩形做**命中测试**（返回按钮 id），
   没命中才把坐标交给 `GameEngine` 处理棋盘滑动/点选。

按钮命中测试也在 ArkTS：布局和文案、命中区域在同一处生成，改 UI 不会漏改点击区。

### 横幅广告：独立子窗口

Ads Kit 只提供 ArkUI 组件（`AutoAdComponent`），没有"画到 Surface 里"的原生接口。
为了不让广告容器出现在游戏页布局树里，横幅被放进**独立子窗口**：

```
MainAbility.onWindowStageCreate → WindowStageHolder.set(windowStage)
GameDemoPage → stage.createSubWindow('game_banner_win')
             → setUIContent('pages/GameBannerPage')（内含 AutoAdComponent）
             → 贴屏幕底部、非焦点、宽 1084 / 高 58vp + 安全区
```

- 广告加载成功（`onAdLoad/onAdOpen`）→ 游戏页保留 58vp 并显示窗口；
- 加载失败（`onAdFail`）→ 把子窗口移到屏幕外（`window.Window` 没有 hide API），
  游戏页把 banner 高度置 0，底部不留空白条。

### 状态栏与入口图标

- **状态栏**：游戏页进入时调用
  `window.getLastWindow().setWindowSystemBarProperties({ statusBarColor: '#07090F', statusBarContentColor: '#FFFFFF' })`，
  状态栏变成与游戏背景一致的深色 + 白色图标；退出页面时恢复透明背景 + 深色图标。
  这样不会出现"深色游戏顶着一根白条"的割裂感。
- **入口图标**：`AppScope/resources/base/media/game_match3.svg`，沿用工具箱统一的线性风格
  （`#7B68EE` 描边 + `#FF4500` 点缀，24×24 viewBox、1.8 描边），画成"三个方块 + 匹配加号"，
  与 App Linking / H5 / 设备信息等图标同一套视觉语言。

## 三、玩法与数值

- 8×8、5 色；初始棋盘逐格避开三连，并校验至少存在一步有效交换；
- 横/纵 3 连及以上消除；消除后整列下落、顶部补齐；死局自动洗牌；
- 目标 30 个 / 12 步（刻意偏紧，保证能高频触发"步数归零 → 激励复活"）；
- 动画：交换 160ms、消除 170ms、下落 260ms（`easeOutCubic`），由 ArkTS 计算插值后每帧推给 native；
- 得分：`消除数 × 10 × 连击倍数`；
- 常驻"看视频领金币"入口：看完激励视频 +50 分（真实游戏最常见的常驻激励位）。

## 四、广告接入

全部复用现有广告位配置（`AdsKitPreferences`，默认华为官方测试 ID），不新建配置页。

| 场景 | 广告类型 | 入口 |
|---|---|---|
| 进入游戏 | 开屏（1） | 首次进页面自动 + DEBUG 面板 |
| 步数用完 | 激励视频（7） | 复活弹窗 / DEBUG 面板 |
| 领金币 | 激励视频（7） | 常驻"看视频领金币 +50 分" |
| 过关 | 插屏（12） | "下一关" / DEBUG 面板 |
| 游戏进行中 | 横幅（8） | 独立子窗口，贴底 |

### 实测发现：发奖字段与文档不一致

华为 Ads Kit 的 `AdInteractionListener` 注释里只列了 `onAdOpen/onAdClick/onAdClose/...`，
`advertisement.rewarded` 在整条回调链里**始终为 false**；真正表示"已发奖"的是**实际会下发的
`onAdReward` 状态**（`data` 里带 `uniqueId/rewardAmount`）。

```
onStatusChanged(status):
  status === 'onAdReward' → earned = true        // 只标记，不立即发奖
  status === 'onAdClose'  → resolve(earned)      // 关闭时才兑现
```

如果按文档或按 `ad.rewarded` 写，会出现"广告显示领取成功、游戏提示未获得奖励"（已实测复现并修复）。

### Mock 兜底

- 广告位为空 / 加载失败 / 手动打开 Mock → 用 1.2s 定时器模拟完整回调；
- 验证期间测试位多次请求后出现 `code=21800003 Failed to load the ad request`
  （激励/开屏/横幅都命中过），链路自动降级 Mock，游戏闭环仍可验证；
  真实激励视频此前已完整跑通（`onAdOpen → onAdReward → onAdClose → +5 步`）。

## 五、生命周期与挂起

- 展示全屏广告前 `engine.pause()`，关闭后 `engine.resume()`（金币奖励走 resume，复活走 revive）；
- 挂起时记录 `pausedAt`，`buildFrame` 用挂起时刻的画面，动画不会在广告后面继续跑；
- 恢复时把 `anim.start/end` 与 `waitEnd` 平移暂停时长；
- 广告加载 8s、展示 90s 超时保护，避免状态机死锁；
- 退出页面：销毁横幅子窗口、恢复 Web 悬浮球、停止帧循环。

## 六、验证记录（真机 nova 15 / API 26，`192.168.3.144:12345`）

构建：

```powershell
hvigorw --mode module -p module=main@dev     -p product=dev     -p buildMode=debug   ... assembleHap
hvigorw --mode module -p module=main@product -p product=default -p buildMode=debug   ... assembleHap
hvigorw --mode module -p module=main@product -p product=release -p buildMode=release ... assembleHap
# 三条链均 BUILD SUCCESSFUL
```

| 验证项 | 方法 | 结果 |
|---|---|---|
| 页面只剩一个控件 | `uitest dumpLayout` 统计节点类型 | 实测 `Stack=2, Column=1, XComponent=1`；**无 Text/Button/Image/Grid**；只剩 Navigation 容器 |
| 布局边界不可见 | 开发者选项"显示布局边界"保持开启，截图 | 游戏区域只有一个满屏 Surface；HUD/按钮/弹窗/金币入口**没有任何控件边框**（只有状态栏、Toast、横幅子窗口这类系统/广告窗口） |
| HUD/按钮原生绘制 | 截图 | 标题、三个 HUD 胶囊、关卡卡、金币入口、底部"洗牌/重玩"均为 Surface 内绘制 |
| 中文文本 | 截图 | `OH_Drawing_Typography` 渲染正常（标题/说明/按钮文案） |
| 原生按钮 | 点"洗牌" | Toast 提示"已手动洗牌"，棋盘立即重排 |
| 棋盘输入 | 点选两格相邻方块 | 无效交换滑回并提示"这一步不能消除"，不扣步数 |
| 金币激励 | 点"看视频领金币" | 广告调用 → Mock 回调 → 得分 `0→50`、提示"奖励 +50 分" |
| 复活 | DEBUG "步数归零" → 弹窗 → 看广告 | 原生弹窗/按钮；Mock 发奖后 `0/12→5/12`，提示"复活成功，+5 步" |
| 返回 | 点左上角原生返回 | 回到工具箱；`OnSurfaceDestroyed` 正常释放 EGL/纹理 |
| 横幅子窗口 | 进入游戏 | `game_banner_win` 创建成功并贴底；测试位 `onAdFail` 时自动移出屏幕、底部无空白条 |
| AG 版默认隐藏 | 安装 AG 包后 dump 工具箱 | 模拟游戏/AdsKit/HDC 均不出现，设备信息/压测工具正常 |
| 无崩溃 | hilog | 全程无 `jscrash` |
| 状态栏 | 进入/退出游戏页截图 | 游戏页状态栏深色 `#07090F` + 白色图标；返回工具箱后恢复白底深色图标 |
| 入口图标 | 工具箱截图 | 与其他图标同为紫色描边 + 橙色点缀的线性风格 |

抓图见 `docs/superpowers/specs/assets/2026-11-21-game-demo/`：
`01` 入口卡片、`02` 整屏游戏、`03` 原生调试面板、`04` 原生复活弹窗、
`05` 金币激励结果、`07` 无效交换提示、`10` 布局边界下的整屏效果。

## 七、踩过的坑（均已修复）

1. **`@Entry` 的 build 根必须是容器**：`build() { XComponent(...) }` 直接编译报错，
   必须包一层 `Stack`。这层 Stack 与 XComponent 同尺寸，布局边界上仍是一个满屏区域。
2. **`LOG_DOMAIN` / `LOG_TAG` 是 hilog 头文件的宏**：自定义同名 `constexpr` 编译失败，改名 `GAME_LOG_DOMAIN/GAME_LOG_TAG`。
3. **OH_Drawing 需要显式链接 `libnative_drawing.so`**，否则全是 undefined symbol。
4. **ArkTS `.onTouch` 在 SURFACE 上不触发**：改为原生触摸 + `pollTouch` 轮询。
5. **UI 纹理懒创建的鸡生蛋问题**：`DrawUiLocked` 一开始判断 `uiTexture_ == 0` 就 return，
   导致 `RenderUiLocked` 永远不执行；必须先创建再绘制。
6. **矩形/文本是两遍绘制**：同一帧内先画所有矩形再画所有文本，半透明遮罩盖不住底层的文本。
   处理：弹窗/调试面板打开时**不再绘制底层 HUD**，只画遮罩 + 面板本身。
7. **`window.Window` 没有 hide API**：子窗口"隐藏"用 `moveWindowTo` 移到屏幕外实现。
8. **`@Builder` 按值参数不刷新、`@Trace` 在嵌套 builder 里不建立依赖**：第一版 HUD 踩过；
   第二版 UI 不依赖 ArkUI 响应式，改为每帧比较 UI key、变化时重建显示列表。
9. **XComponent 尺寸**：`OH_NativeXComponent_GetXComponentSize` 给出 px（本机 1084×2304）；
   ArkTS 用 `getSurfaceSize()` 拿到实际像素再换算 vp，避免状态栏/导航栏导致布局错位。

## 八、已知限制 / 下一步

- 没有音效（工程暂无音频框架）；需要时接 `AVPlayer` 或 `audio`。
- 横幅广告依赖 Ads Kit 的 ArkUI 组件，只能放独立子窗口；测试位当前会 `onAdFail`，
  正式位申请后可直接验证"加载成功 → 子窗口贴底显示"的路径。
- 关卡只有一关（目标 30 / 12 步），没有难度曲线与道具；作为广告宿主已够用。
- 系统返回键在 HMRouter 页面整体不生效（既有行为，页面内原生返回键可用）。
- 原生库 `libgame.so` 约 90KB（arm64-v8a，含 OH_Drawing 调用），包体增量可忽略。
