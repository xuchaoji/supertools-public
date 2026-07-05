# AppLinkingTool 改造：快捷启动收藏面板

> 日期: 2026-07-05 | 状态: 待实施

## 1. 概述

在现有 AppLinkingTool 页面内嵌入 URL 收藏管理能力，支持解析后的链接一键保存、持久化列表管理、批量回归测试。不再新开独立页面，直接在 AppLinkingTool 上以区块形式扩展，形成"探索 → 保存 → 批量重跑"的闭环。

## 2. 与现有 AppLinkingTool 的关系

| 维度 | 现有 AppLinkingTool | 改造后新增 |
|---|---|---|
| 定位 | 临时链接的一次性解析 + 唤起 | 常用链接持久化 + 批量回归 |
| 数据生命周期 | 页面退出即丢失 | PersistenceV2 持久化，重启保留 |
| URL 数量 | 单条输入 | 可管理列表，理论无上限 |
| 启动方式 | 点"启动"唤起一次 | 单条唤起 / 勾选批量依次唤起 |
| 复用成本 | 每次手动输入/扫码 | 存一次，反复用 |

两者不冲突——AppLinkingTool 负责**探索未知链接**，收藏区块负责**回归已知链接**。解析完成后追加"保存"按钮，打通两个阶段。

## 3. 数据模型

### 3.1 SavedUrlModel

新文件 `model/SavedUrlModel.ets`：

```typescript
import { Type } from '@kit.ArkData';

@ObservedV2
export class SavedUrlModel {
  @Trace id: string = '';          // uuid 唯一标识
  @Trace url: string = '';         // 原始 URL
  @Trace label: string = '';       // 用户自定义名称
  @Trace scheme: string = '';      // 解析后 scheme，用于列表预览摘要
  @Trace hostname: string = '';    // 解析后 hostname
  @Trace createdAt: number = 0;    // 创建时间戳 (Date.now())

  constructor(
    id: string = '',
    url: string = '',
    label: string = '',
    scheme: string = '',
    hostname: string = '',
    createdAt: number = 0
  ) {
    this.id = id;
    this.url = url;
    this.label = label;
    this.scheme = scheme;
    this.hostname = hostname;
    this.createdAt = createdAt;
  }
}
```

### 3.2 SavedUrlCache（持久化容器）

新文件 `viewmodel/SavedUrlCache.ets`：

```typescript
import { Type } from '@kit.ArkData';
import { SavedUrlModel } from '../model/SavedUrlModel';

@ObservedV2
export class SavedUrlCache {
  @Type(SavedUrlModel)
  @Trace urls: Array<SavedUrlModel> = new Array<SavedUrlModel>();
}
```

持久化方式：`PersistenceV2.connect(SavedUrlCache, 'saved_url_cache', () => new SavedUrlCache())`，与 `RecordViewModel` 模式一致。新增/删除后调用 `PersistenceV2.save(SavedUrlCache)` 手动落盘。

### 3.3 SpKeys 新增键

在 `constant/SpKeys.ets` 追加：

```typescript
public static readonly QUICK_LAUNCH_BATCH_DELAY: string = 'quick_launch_batch_delay';
```

用于保存批量启动间隔设置（number，单位 ms，默认 500）。

## 4. UI 改造方案

### 4.1 布局对比

**改造前**：
```
┌──────────────────────────┐
│  [TextArea URL 输入区]   │
│  [解析] [清空] [启动]    │
│  [扫码] (条件显示)        │
├──────────────────────────┤
│  解析结果卡片区           │
│  · BasicInfoCard         │
│  · QueryParamsCard       │
│  · DeepLinkCard          │
└──────────────────────────┘
```

**改造后**：
```
┌──────────────────────────┐
│  [TextArea URL 输入区]   │
│  [解析] [保存] [清空] [启动] │  ← "保存"按钮在有效解析后亮起
│  [扫码] (条件显示)        │
├──────────────────────────┤
│  解析结果卡片区 （不变）   │
│  · BasicInfoCard         │
│  · QueryParamsCard       │
│  · DeepLinkCard          │
├──────────────────────────┤
│  已保存链接 (N)  [全选]   │  ← 新增区块
│  ┌──────────────────────┐│
│  │ ☑ ｜ 电商原子服务     ││  ← 行布局: checkbox + label + scheme 预览
│  │    ｜ store://xxx...  ││             整行点击: 单条唤起
│  │    ｜           [✎] [🗑]│  ← 编辑 / 删除按钮
│  ├──────────────────────┤│
│  │ ☐ ｜ 支付 Demo       ││
│  │    ｜ hms://yyy...   ││
│  └──────────────────────┘│
│  [批量测试 (N个)]        │  ← 勾选 ≥1 个时浮现
└──────────────────────────┘
```

### 4.2 交互定义

| 操作 | 触发方式 | 行为 |
|---|---|---|
| **保存** | 解析有效 URL 后点"保存" | 弹出 `TextInputDialog`，预填标签名（默认取 hostname 或 scheme），确认后构造 `SavedUrlModel` 写入 PersistenceV2 |
| **单条唤起** | 点击收藏条目 | 直接 `startAbility(viewData)` 拉起目标应用，Toast 反馈 |
| **全选/取消** | 点"全选"文本按钮 | 切换全部条目的勾选状态 |
| **批量测试** | 勾选 ≥1 条后点底部"批量测试 (N)" | 依次 `startAbility` → sleep(batchDelay) → 下一个，顶部显示进度条 `(2/5)`，完成后展示 {成功}x {失败}y 的 summary toast |
| **编辑标签** | 点击条目右侧 ✎ 按钮 | 弹出编辑对话框，修改 `label` 后更新模型并持久化 |
| **删除** | 点击条目右侧 🗑 按钮 | 弹窗确认，确认后 splice 数组并持久化 |
| **去重** | 保存时自动 | 与已有列表比对 URL 相等 → Toast "链接已存在" 放弃保存 |
| **空状态** | 列表无数据 | 收藏区块整块隐藏，不占空间 |

### 4.3 新增组件

| 组件 | 用途 | 复用度 |
|---|---|---|
| `BuildSaveDialog` (builder) | 保存时输入标签名 | 新写 ~20 行 |
| `BuildBatchProgress` (builder) | 批量测试进度条 | 新写 ~15 行 |
| `SettingGroup` | 包裹收藏列表区块（含标题行） | 已有 |
| `ImmersiveGlassCard` | 单个收藏条目的卡片容器 | 已有 |

## 5. 批量启动逻辑

```typescript
private async batchLaunch(urls: SavedUrlModel[]): Promise<void> {
  let successCount: number = 0;
  let failCount: number = 0;
  const context = GlobalContextHolder.getInstance().uiAbilityContext;

  for (let i = 0; i < urls.length; i++) {
    this.batchProgress = `${i + 1}/${urls.length}`;       // 更新进度
    try {
      let want: Want = { action: 'ohos.want.action.viewData', uri: urls[i].url };
      await context!.startAbility(want);
      successCount++;
    } catch (err) {
      failCount++;
    }
    await this.sleep(PreferencesUtil.getNumberSync(SpKeys.QUICK_LAUNCH_BATCH_DELAY, 500));
  }

  this.batchProgress = '';
  promptAction.showToast({
    message: `批量测试完成: ${successCount} 成功, ${failCount} 失败`,
    duration: 2000
  });
}
```

每个 URL 独立 try/catch，单条失败不中断后续。间隔时间可配，默认 500ms。

## 6. 涉及文件

| 文件 | 改动量 | 内容 |
|---|---|---|
| `model/SavedUrlModel.ets` | **新增** | 数据模型（~20 行） |
| `viewmodel/SavedUrlCache.ets` | **新增** | PersistenceV2 持久化容器（~15 行） |
| `constant/SpKeys.ets` | +1 行 | 新增 `QUICK_LAUNCH_BATCH_DELAY` 键 |
| `pages/AppLinkingTool.ets` | +120 行 | 保存逻辑 + 收藏列表 UI + 批量测试 |

无额外依赖，无权限变更，`product` 和 `dev` 目标均可使用。

## 7. 测试验证

| # | 场景 | 预期 |
|---|---|---|
| 1 | 输入有效 URL → 解析 → 点"保存" → 输入标签 → 确认 | 列表新增一条，重启后仍在 |
| 2 | 点已保存条目 | startAbility 唤起目标应用 |
| 3 | 勾选 2 条 → 批量测试 | 依次唤起，间隔 >500ms，结束后 toast 成功/失败计数 |
| 4 | 保存已存在的 URL | toast "链接已存在" |
| 5 | 修改标签 | label 更新，PersistenceV2 落盘 |
| 6 | 删除条目 → 确认 | 列表中移除，持久化生效 |
| 7 | 列表为空 | 收藏区块隐藏 |
| 8 | 输入无效 URL → 点"保存" | "保存"按钮置灰不可点击 |
| 9 | 批量测试中某条失败 | 继续执行后续 URL，最终统计失败数 |

## 8. 边缘情况

- **重复 URL**: 保存时比对 `url` 字段，发现重复拒绝保存，提示"链接已存在"
- **空标签**: 保存对话框默认填充 scheme 或 hostname，允许用户留空时自动回退到 hostname
- **快速连续保存**: PersistenceV2 每次保存会刷新整个数组，无竞态风险
- **批量测试中途退出应用**: `startAbility` 是异步 Promise，应用进入后台后系统仍会处理。列表勾选状态建议不持久化，重新进入重置为全未选
- **设备熄屏**: 批量测试中熄屏不会中断 for 循环，但 startAbility 唤起的目标应用可能无法正常展示
- **收藏列表过长**: 使用 `Scroll` + `Column` 滚动，不设上限限制。后续可考虑搜索/筛选
