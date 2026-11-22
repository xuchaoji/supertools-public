# Markdown 笔记 HSP：设计与验证记录

> 状态：已实现，dev HAP + HSP 真机验证通过（2026-11-22）
> 目标：在应用内增加 Markdown 笔记；功能整体拆到 HSP；Markdown 渲染使用开源 SDK `@luvi/lv-markdown-in`；**不改动广告部分**。
> 设备：HUAWEI nova 15（PSN-AL00），OpenHarmony 7.0.0.111 / API 26。

---

## 一、结论

| 项 | 结果 |
|---|---|
| 功能位置 | `notes_hsp`（HSP，`type: "shared"`） |
| 宿主入口 | 首页「Markdown」卡片 → `pages/MarkdownNotesPage.ets`（HMRouter） |
| 宿主职责 | 路由壳、壁纸背景、底部安全区、返回 |
| HSP 职责 | 列表、编辑器、Markdown 预览、删除确认、自动保存、文件存储、SDK 门面 |
| 渲染 SDK | `@luvi/lv-markdown-in@3.4.6`（MIT，ohpm） |
| 存储 | 应用沙箱 `filesDir/markdown_notes/`（`index.json` + 每篇 `.md`） |
| 广告 | 未改动 `@hw-ads/ads`、`AdsKitPage`、`AdsHspPage`、`GameAdService` |
| 验证 | HAP + HSP 联合安装；新建/编辑/预览/搜索/删除/重启持久化均通过 |

**为什么不是“HSP 页面”**：本项目 HMRouter 跨 HSP 路由存在版本/路由表风险。这里采用更稳的 **HSP 导出完整 UI 组件**方案：HSP 导出 `NotesFeature`，宿主只放一个 HMRouter wrapper。功能 UI/逻辑仍然 100% 在 HSP 内，同时避开跨包页面栈、HSP `main_pages.json`、HSP 资源路径等不确定性。

---

## 二、结构

```
main/（Entry HAP）
  src/main/ets/pages/MarkdownNotesPage.ets     ← HMRouter 壳，仅 3 件事
  src/main/ets/pages/HomePage.ets              ← 新增「Markdown」工具卡
  src/main/ets/constant/PageNames.ets          ← MARKDOWN_NOTES_PAGE

notes_hsp/（HSP）
  Index.ets                                    ← 导出 NotesFeature / NotesSdk / 类型
  src/main/ets/
    api/NotesSdk.ets                           ← 宿主可用的 SDK 门面
    data/NotesRepository.ets                   ← 沙箱文件仓库
    model/Note.ets                             ← Note/NoteMeta + 标题/摘要/时间工具
    ui/NotesFeature.ets                        ← 列表/编辑器/预览/删除确认
    ui/EditorToolbar.ets                       ← 编辑/预览切换、字数、删除（独立 V2 组件）
    ui/NoteCard.ets                            ← 笔记卡片
    ui/NotesMarkdownPreview.ets                ← lv-markdown-in 封装
    ui/NotesTheme.ets                          ← 内容区兜底材质 + 轻量主题
  src/main/resources/base/media/back_arrow.png ← HSP 自己的返回图标
```

宿主 wrapper：

```typescript
@HMRouter({ pageUrl: PageNames.MARKDOWN_NOTES_PAGE })
@ComponentV2
export struct MarkdownNotesPage {
  @Local safeBottom: string = '0px';

  aboutToAppear(): void {
    this.safeBottom = SafeArea.bottom();
  }

  build() {
    WallpaperHost() {
      NotesFeature({
        safeBottom: this.safeBottom,
        onBack: (): void => {
          HMRouterMgr.pop();
        }
      })
    }
  }
}
```

HSP 的 `NotesFeature` 只接收两个宿主参数：`safeBottom`（底部安全区）和 `onBack`（列表页返回）。其余全部自包含，不 import HAP 的 `PageNames` / `SpKeys` / `$r('app.media.*')` / `TargetConstants` / `GlobalContextHolder`。

---

## 三、数据与存储

目录：

```
<filesDir>/markdown_notes/
  index.json      // NoteMeta[]：id/title/createdAt/updatedAt/chars/snippet
  <noteId>.md     // 原始 Markdown 正文
  .seeded         // 首次示例是否已写入，避免用户删空后被反复塞回
```

关键设计：

- **一篇一文件**：正文不塞进 Preferences，避免大文本限制，也方便后续导入/导出/全文检索。
- **index.json 只存元数据**：列表渲染不需要读全部正文；`snippet`/`chars` 在保存时计算。
- **首次启动 seed**：写入一篇“欢迎使用 Markdown 笔记”，同时作为渲染能力自检素材（标题、列表、任务列表、引用、代码块、表格、LaTeX）。
- **index 损坏恢复**：`index.json` 缺失/解析失败时，扫描目录中的 `.md` 文件重建元数据。
- **原子写入**：正文与 index 都先写 `.tmp`，再 `unlink + rename`；index 失败时兜底直接写目标文件。
- **自动保存**：编辑停止 1.2s 后保存；点保存、从编辑器返回列表、HSP 组件销毁时也会保存。
- **删除**：编辑器内删除，先弹自定义确认层；删除正文 + 元数据 + 刷新列表。
- **标题**：优先用户输入；留空时从一级标题推导，再退化为第一行可读文本，最后是“未命名笔记”。

---

## 四、Markdown 渲染接入

```typescript
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';

@ComponentV2
export struct NotesMarkdownPreview {
  @Param text: string = '';
  @Param isDark: boolean = false;
  private controller: MarkdownController = new MarkdownController();

  aboutToAppear(): void {
    this.controller
      .setThreadRenderEnable(false)   // 笔记量不大，避免 HSP 内 Worker 路径依赖
      .setMermaidEnable(false)        // 不启用 Mermaid，减少运行期分支
      .setLazyRender(false)
      .setTextColor(...)
      .setTitleColor(...)
      .setTextSize(15)
      .setTitleSize([24, 21, 18, 16, 15, 14])
      .setQuoteBackgroundColor(...)
      .setInlineCodeBackgroundColor(...)
      .setImageBorderRadius(12)
      .setCodeCopyListener((text: string) => { /* pasteboard */ });
  }

  build() {
    Column() {
      Markdown({ text: this.text, controller: this.controller }).width('100%')
    }
  }
}
```

几个有意选择：

- 用 **text 模式** 渲染内存中的正文，不走 `rawfile` / `sandbox` 模式，避免 HSP 内沙箱路径和 context 问题。
- `Markdown` 是 V1 组件，HSP 的 `NotesFeature` 是 V2；只在「预览」分支创建 `Markdown`，编辑期间不创建，因此不依赖 V1/V2 跨版本实时状态同步。
- 关闭子线程渲染，先保证 HSP 内的 Worker 路径稳定；后续如需大文本性能，可打开 `setThreadRenderEnable(true)` 并做对比。
- 关闭 Mermaid；LaTeX、代码高亮仍由 SDK 自带能力处理（会带入相应原生库）。
- v3.1.0 起 SDK 不再直接写剪贴板，代码块复制通过 `setCodeCopyListener` + `pasteboard` 实现。
- 预览标签切换会销毁/重建 `Markdown` 组件，确保拿到当前正文，不依赖 `@Prop` 的跨版本更新。

### 4.1 深色模式

之前笔记页有一处明显的深色模式异常：页面背景已经是深色，但卡片摘要/搜索占位文字仍是深色，几乎看不见。根因是 HSP 里用了错误的媒体特征：

```typescript
// 错误：display-mode 是 PWA 显示模式，不是系统深浅色
mediaQuery.matchMediaSync('(display-mode: dark)')
// 正确：HarmonyOS 系统深色模式
mediaQuery.matchMediaSync('(dark-mode: true)')
```

`NotesFeature` 已改为 `(dark-mode: true)`，并在 `on('change')` 中同步 `isDark`；`NotesMarkdownPreview` 通过 `@Monitor('isDark')` 重新应用 Markdown 样式。

Markdown 预览的深色适配不止文字颜色，以下都按 `isDark` 切换：

- 代码块主题：`setCodeBlockTheme('dark' | 'light')`；
- LaTeX 公式颜色：`setLatexMathTextColor(0xFFE8E8EA / 0xFF1A1A1A)`；
- 引用文字/边框/背景；
- 表格：背景、表头背景/文字、隔行背景、内外边框、操作区背景/图标；
- 行内代码背景。

### 4.2 沉浸光感（按官方文档）

官方《组件适配沉浸光感》的硬约束：

- `systemMaterial` / `uiMaterial.ImmersiveMaterial` 在**普通页面内容区不生效**，只支持 Navigation/NavDestination 标题栏、横向 Tabs 的底部 TabBar、Dialog/Toast 等容器；
- 内容区无法满足生效范围时，官方建议改用 `backgroundColor` / `backgroundBlurStyle` 等通用属性。

按这个约束实现：

1. **应用级开关**：`main/src/main/module.json5` 增加
   ```json5
   "metadata": [{ "name": "ohos.arkui.UIMaterial.state", "value": "enable" }]
   ```
   Dialog/Toast 等官方支持的组件会自动使用系统材质。

2. **删除确认改为官方 AlertDialog + systemMaterial**：
   ```typescript
   this.getUIContext().showAlertDialog({
     title: '删除这篇笔记？',
     message: '删除后无法恢复。',
     systemMaterial: new uiMaterial.ImmersiveMaterial({
       style: uiMaterial.ImmersiveStyle.THICK,
       colorInvert: true,
       applyShadow: true,
       interactive: true
     }),
     // ...
   });
   ```
   弹窗背景、阴影、反色由系统材质负责，不再自绘遮罩卡片。

3. **内容区按官方兜底**：列表卡片/输入框/预览容器不再伪造光感渐变、rim 亮边或 `hdsEffect` 点光源，只用：
   - 半透明 `backgroundColor`；
   - 官方 `backgroundBlurStyle`（卡片/预览）或 `backdropBlur`（输入框）；
   - 普通 `border` / `shadow`。

   `NotesTheme` 因此只剩「兜底浓度 / 模糊档位 / 圆角 / 文字色」，不再是一套手写材质引擎。全局光感档位 `lightSense` 仍由宿主传入，用于选择 0/1/2/3 档的兜底浓度与模糊档位。

4. **文字可读性**：保留与 `PageHeader` 一致的文字阴影，避免壁纸/浅色背景上标题和摘要发虚。

另外修复了一个与深色无关但影响观感的 V2 状态问题：`编辑/预览` 分段控件原来放在嵌套 `@Builder` 里，V2 下不会建立 `@Local` 响应式依赖，出现“内容已经切到预览、高亮还停在编辑”。现已拆成独立 `EditorToolbar` 组件，通过 `@Param showPreview` 接收状态。

---

## 五、构建与安装

HSP 不是独立安装包，**HAP 和 HSP 必须一起安装**（同一 bundle）。`build-dev.bat` / `build-ag-debug.bat` 已改为：

1. 先构建 `notes_hsp`（`assembleHsp`）；
2. 再构建 `main` HAP（`assembleHap`）；
3. 两个文件都 `hdc file send` 到 `/data/local/tmp/`；
4. 用 `bm install -r -p <hap> <hsp>` 一次安装。

`build-ag-release.bat` 走 `assembleApp`，HSP 会自动进入 `.app`（已实测 `.app` 内含 `notes_hsp-default.hsp`）。

手动命令：

```bash
# HSP
hvigorw --mode module -p module=notes_hsp@default -p product=dev -p buildMode=debug \
  assembleHsp --analyze=normal --parallel --incremental --daemon

# HAP
hvigorw --mode module -p module=main@dev -p product=dev -p buildMode=debug \
  -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon

# 联合安装
hdc -t <target> file send main/build/dev/outputs/dev/main-dev-signed.hap /data/local/tmp/main-dev-signed.hap
hdc -t <target> file send notes_hsp/build/dev/outputs/default/notes_hsp-default-signed.hsp /data/local/tmp/notes_hsp-default-signed.hsp
hdc -t <target> shell "bm install -r -p /data/local/tmp/main-dev-signed.hap /data/local/tmp/notes_hsp-default-signed.hsp"
```

> 只 `hdc install` HAP 会缺少 HSP；真机上功能入口可能打不开或运行期找不到模块。

---

## 六、体积与成本（需要正视）

本功能给应用带来一个明显增量：

| 产物 | 大小 |
|---|---|
| `notes_hsp-default-signed.hsp` | 约 **33.5MB**（unsigned 约 30MB） |
| release `.app`（压缩后，含 HAP+HSP） | 约 **15.8MB** |
| HAP 自身 | 约 12.3MB（release）/ 16.8MB（debug） |

HSP 体积主要来自 Markdown SDK 的依赖：

- `rawfile/mermaid/mermaid.main.js` 约 3.2MB；
- LaTeX / 代码高亮的仓颉原生库（`liblatex.so`、`libformula.*`、`libprism4cj.*`、`libcangjie-runtime`、`libohos.ark_interop` 等）同时包含 arm64-v8a 与 x86_64；
- HSP 的 `modules.abc` 约 0.8MB。

可选优化（按收益排序）：

1. 换用不带 LaTeX/Prism/Mermaid 原生依赖的 Markdown 库，或 `@luvi/lv-markdown-in` 的早期轻量版本；代价是公式/代码高亮/Mermaid 能力缩水。
2. 只保留 arm64-v8a；当前 HSP 的 `nativeLib.abiFilters` 在共享包构建里不被接受，需要在打包产物层面裁剪 ABI。
3. 把 Mermaid 资源从 HSP 中剔除（当前 `setMermaidEnable(false)` 只是运行时不启用，资源仍会打包）。
4. 将 Markdown 渲染拆成可选 feature HAP，让不需要笔记的用户不下载；这不是 HSP 能解决的。

本次按“保留 SDK 完整能力”的优先级实现，未做体积裁剪。

---

## 七、验证记录

真机（API 26，1084×2412）实测：

- HAP + HSP 联合安装成功；首页「Markdown」卡片出现，描述两行内完整展示。
- 首次进入：自动创建欢迎笔记；列表显示标题、摘要、字数、相对时间。
- 编辑器：标题/正文输入、字数统计、`编辑/预览` 切换。
- 预览：标题、段落、粗体/斜体、行内代码、任务列表、引用、代码块高亮、LaTeX 公式、表格均正常渲染。
- 深色模式：系统深色下卡片/搜索/输入框/弹窗可读；Markdown 代码块为深色主题、LaTeX 为浅色公式、引用/表格颜色正确；不再出现“深色背景 + 深色文字”。
- 浅色模式：卡片/输入框/预览容器保持半透明与背景模糊，文字可读。
- 深/浅色切换：笔记页开着时从系统设置切换深色，返回后列表/预览实时切换，无需重启页面。
- 沉浸光感：删除确认使用官方 AlertDialog + systemMaterial；内容区按官方 FAQ 用 `backgroundColor` + `backgroundBlurStyle` 兜底，不再自绘渐变/rim/点光源。
- 编辑/预览切换：内容与高亮状态一致（修复了 V2 嵌套 `@Builder` 的假状态）。
- 搜索：输入 `Test` 后只保留匹配项。
- 自动保存：输入停止约 1.2s 后，`<id>.md` 与 `index.json` 落盘；返回列表后仍可见。
- 删除：官方 AlertDialog 确认 → 确认后正文与索引删除，列表刷新。
- 重启：`aa force-stop` 后重新启动，笔记仍在（1 篇欢迎笔记）。
- 大版本构建：dev / default / release 均编译通过；release `.app` 内含 HAP + HSP。

未覆盖：

- 沉浸光感 0/1/2 档的逐档截图（内容区兜底逻辑已按官方建议实现，3 档与浅色/深色已实测）；
- 系统材质在低算力设备上的降级效果；
- 代码块复制的剪贴板回读；
- 超大笔记（数 MB）/大量笔记（数百篇）性能；
- 多设备/平板/2in1 布局；
- release 签名包的真机安装（只验证了构建与 `.app` 内容）。

---

## 八、后续可做

- 笔记导入/导出（`.md` 文件选择器）、分享。
- 图片插入（相册/相机）与本地图片缓存。
- 标签、置顶、归档、按更新时间/标题排序。
- 全文检索高亮、搜索历史。
- 加密笔记（TEE/密钥库）与生物识别解锁。
- 与媒体能力联动：例如把播放器时间点、媒体服务地址、录屏文件一键写入笔记。
- 体积优化：见第六节。
