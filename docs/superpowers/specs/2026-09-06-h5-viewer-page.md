# H5 页面打开工具（应用内 H5 展示页）设计与布局记录

> 状态：已实现（2026-09-06）
> 日期：2026-09-06
> 背景：需要在工具箱内新增一个与「App Linking 解析」类似入口、用于**应用内打开并展示 H5 页面**
> 的工具。整体功能复用 AppLinkingTool（URL 输入 / URLParserUtil 解析 / 复制 / 拉起），打开后
> 使用 hdc 抓取的“当前页面布局”（H5 容器页：顶栏 + Web 内容 + 右上角菜单）展示 H5。
> 先按用户要求用 hdc 抓取设备当前页面并记录布局，再按记录实现。

---

## 一、布局抓取与素材

抓取命令（设备：无线 HDC `192.168.3.39:12345`）：

```powershell
hdc shell snapshot_display -f /data/local/tmp/cur_page.jpeg      # 截屏 1308×2880
hdc shell uitest dumpLayout -p /data/local/tmp/cur_layout.json -a # UI 层级 dump
```

参考素材（本仓库内）：

| 素材 | 路径 |
|---|---|
| 截屏原图 | `docs/superpowers/specs/assets/2026-09-06-h5-viewer-ref.png` |
| UI 层级 dump | `docs/superpowers/specs/assets/2026-09-06-h5-viewer-ref-layout.json` |

## 二、抓取到的“当前页面布局”记录（H5 容器页）

设备当前显示的是一类 **H5 容器页**（示例内容为“运动健康馆 / WATCH GT 系列”，运行在
某个浏览容器内）。其布局结构（坐标 px，屏幕 1308×2880）如下：

```
┌─ 状态栏区  [0,0][1308,136]（时钟等，由系统绘制）──────────────────────┐
├─ 应用内容起点 y≈137 ──────────────────────────────────────────────┤
│ ┌─ 顶栏 [0,150][1308,346] ─────────────────────────────────────┐ │
│ │ 返回按钮 [56,178][196,318]   居中标题「运动健康馆」            │ │
│ │                             [224,202][1084,295]             │ │
│ │                             「…」按钮 [1112,178][1252,318]    │ │
│ └──────────────────────────────────────────────────────────────┘ │
│ ┌─ Web 内容区 [0,346][1308,2880]（H5 页面正文）───────────────────┐ │
│ │   商品卡 / 轮播 / 视频等（Web 内 DOM，rootWebArea）              │ │
│ └──────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘

右上角「…」点开后菜单（Menu，锚定右缘）：
  Menu [724,346][1252,878]
  ├─ 刷新        [738,360][1238,528]
  ├─ 复制链接    [738,528][1238,696]
  └─ 用浏览器打开 [738,696][1238,864]
```

### 布局要点（转 vp 近似，屏宽 1308px、密度约 3）

| 区域 | 参考值 | 说明 |
|---|---|---|
| 顶栏高度 | ≈ 60vp（196px） | 返回 + 标题 + 「…」同一行 |
| 返回按钮 | 圆形 40×40，左侧约 20vp 边距 | 图标态即可，不需要文字 |
| 居中标题 | 标题文本居中，左右按钮区对称预留 | 长标题省略号截断 |
| 「…」按钮 | 圆形 40×40，右侧约 20vp 边距 | 点击弹出下拉菜单 |
| Web 区 | 顶栏以下铺满剩余空间 | 白底页面正文 |
| 菜单项 | 三项：刷新 / 复制链接 / 用浏览器打开 | 行高约 56vp，锚定右上 |

## 三、设计决策

1. **入口**：HomePage 工具箱新增卡片「H5 页面打开」，置于「App Linking 解析」之后；
   图标复用同批 24×24 线条风 SVG（紫 #7B68EE + 橙 #FF4500 点缀），新文件 `h5_page.svg`。
2. **页面**：`pages/H5Page.ets`，`@HMRouter({ pageUrl: 'h5Page' })` + `@ComponentV2`，
   复用 `URLParserUtil` 解析、剪贴板复制、`startAbility(viewData)` 拉起浏览器逻辑（对齐 AppLinkingTool）。
3. **两种形态（单页面内切换，打开时不另开路由）**：
   - 输入态：标题栏与输入卡片**固定顶部**（下方内容独立可滚动，避免 Scroll 对不足一屏
     内容默认居中导致标题悬空），输入支持 **扫码识别**（复用 AppLinkingTool 的扫码能力，
     抽取为 `components/ScanQrOverlay.ets`，受设置页彩蛋开关 `SpKeys.ENABLE_SCAN_PARSE` 控制）；
     无壁纸时背景沿用全局沉浸光感（WallpaperHost）。
   - 查看态（打开 H5 后）：按第二节记录复刻——顶栏（返回 + 居中标题 + 「…」）+ Web 铺满；
     右上角「…」bindMenu 支持：**刷新 / 复制链接 / 用浏览器打开**。
4. **返回行为**：查看态顶栏返回按钮 → 回到输入态（URL 保留）；输入态返回按钮 → `HMRouterMgr.pop()`。
5. **仅 http/https**：其它 scheme（App Linking 场景）提示不支持，避免与 AppLinkingTool 职责重叠。
6. **历史记录**：H5 页与 AppLinking 页共用 `utils/UrlHistoryUtil`（去重、最新在前、上限 30，
   按 `SpKeys.H5_HISTORY` / `SpKeys.APP_LINKING_HISTORY` 持久化）。
   - H5 页在成功「打开 H5」时记录；App Linking 页在「解析」成功与「测试拉起」成功时记录；
   - 两页输入区下方展示历史卡片（时间 + 链接 + 单条删除 + 清空），点条目回填输入框并解析。

## 四、涉及文件

| 文件 | 变更 |
|---|---|
| `AppScope/resources/base/media/h5_page.svg` | 新增：H5 入口图标 |
| `main/src/main/ets/constant/PageNames.ets` | 新增 `H5_PAGE = 'h5Page'` |
| `main/src/main/ets/pages/H5Page.ets` | 新增：H5 打开页（输入/扫码/解析/查看/菜单/历史） |
| `main/src/main/ets/components/ScanQrOverlay.ets` | 新增：全屏扫码浮层（相机+ScanKit），AppLinking 同款交互 |
| `main/src/main/ets/pages/AppLinkingTool.ets` | 改造：解析/拉起区改为可滚动，新增历史记录 |
| `main/src/main/ets/utils/UrlHistoryUtil.ets` | 新增：两页共享的历史记录存取工具 |
| `main/src/main/ets/pages/HomePage.ets` | 工具卡片新增「H5 页面打开」入口 |
| 本文档 + `specs/assets/2026-09-06-h5-viewer-ref*` | 布局记录 |

## 五、验收

- 首页出现「H5 页面打开」卡片，点击进入输入态，标题贴顶（不随 Scroll 居中）；
- 输入态布局：标题/输入卡固定顶部，解析信息在下方区域独立滚动；
- 输入 `https://` 链接点「打开 H5」，页面原地切换为“顶栏 + Web”查看态，居中标题显示网页标题；
- 右上角「…」→ 菜单出现 刷新 / 复制链接 / 用浏览器打开，三项均可生效；
- 「扫码解析」按钮与 AppLinkingTool 同一开关（`ENABLE_SCAN_PARSE`），开启后扫码即回填输入框；
- 返回按钮回输入态；输入态返回退出工具页。
