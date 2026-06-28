# 状态持久化：重启后自动恢复功能状态

> 日期: 2026-06-28 | 状态: 待实施

## 1. 概述

应用重启后自动恢复用户上次关闭前的功能状态——悬浮时钟、悬浮压测、本地Web服务。使用 `AppUtil`（Preferences）作为持久化机制，与项目现有 `PRIVACY_AGREE` 模式一致。

## 2. 背景分析

### 2.1 已持久化（无需改动）

| 状态 | 位置 | 机制 |
|---|---|---|
| H265/H264 编码预设 | `RecordViewModel.recordingCache.preset` | `PersistenceV2` |
| 录制麦克风开关 | `RecordViewModel.recordingCache.recordMic` | `PersistenceV2` |
| 录屏记录列表 | `RecordViewModel.recordingCache.recordings` | `PersistenceV2` |
| 隐私协议同意 | `Preferences` key `privacy_agree` | `AppUtil` |
| 扫描解析开关 | `Preferences` key `enable_scan_parse` | `AppUtil` |

### 2.2 待新增持久化

| 状态 | 来源 | 文件:行号 |
|---|---|---|
| `floatingClockOn` | `CommonViewModel._floatingClockOn` | `viewmodel/CommonViewModel.ets:22-31` |
| `cpuStressOn` | `CommonViewModel._cpuStressOn` | `viewmodel/CommonViewModel.ets:12-20` |
| `isServerRunning` | `LocalWebPage` 局部状态 | `pages/LocalWebPage.ets:~308` |

## 3. 数据模型

在 `constant/SpKeys.ets` 新增 3 个键：

```typescript
public static readonly FLOAT_CLOCK_ON: string = 'float_clock_on';
public static readonly CPU_STRESS_ON: string = 'cpu_stress_on';
public static readonly WEB_SERVER_ON: string = 'web_server_on';
```

存储类型: boolean，默认值: false。

## 4. 写入逻辑

### 4.1 悬浮时钟 — `HomePage.ets:196-205`

在 `onChange` 回调中 `CommonViewModel.getInstance().floatingClockOn = isOn` 之后追加：
```typescript
AppUtil.putBoolean(SpKeys.FLOAT_CLOCK_ON, isOn);
```

### 4.2 悬浮压测 — `HomePage.ets:211-220`

在 `onChange` 回调中 `CommonViewModel.getInstance().cpuStressOn = isOn` 之后追加：
```typescript
AppUtil.putBoolean(SpKeys.CPU_STRESS_ON, isOn);
```

### 4.3 Web 服务 — `LocalWebPage.ets:308 toggleServer()`

在成功启动后写入 `true`，停止后写入 `false`：
```typescript
AppUtil.putBoolean(SpKeys.WEB_SERVER_ON, isRunning);
```

## 5. 恢复逻辑（启动时）

在 `MainAbility.onWindowStageCreate()` 末尾，页面加载完成后执行：

```
1. 读取 float_clock_on
   ├─ true → CommonViewModel.floatingClockOn = true → FloatClockManager.show(ctx)
   └─ 日志: "[StateRestore] float_clock_on = true, starting..."

2. 读取 cpu_stress_on
   ├─ true → CommonViewModel.cpuStressOn = true → StressFloatWindowManager.show(ctx)
   └─ 日志: "[StateRestore] cpu_stress_on = true, starting..."

3. 读取 web_server_on
   ├─ true → WebServerUtil.getInstance().init(ctx.filesDir + '/wwwroot', 8088)
   │         → WebServerUtil.getInstance().start()
   │         → FloatWindowUtil.showFloatWindow(ctx)
   │         → BackgroundServiceManager.startWebServer(info)
   └─ 日志: "[StateRestore] web_server_on = true, starting..."

每个功能独立 try/catch，单个失败不影响其他恢复。上下文为空时跳过并记日志。
Web 服务恢复完整复现 `LocalWebPage.toggleServer()` 的启动链（服务器 + FloatWindow + BackgroundService）。

## 6. 调试日志

所有改动处添加 `console.info` 日志，前缀 `[StateRestore]`：

- 保存时: `"[StateRestore] put FLOAT_CLOCK_ON = true"`
- 恢复时: `"[StateRestore] reading FLOAT_CLOCK_ON..."`, `"[StateRestore] FLOAT_CLOCK_ON = true, starting float clock..."`
- 跳过时: `"[StateRestore] FLOAT_CLOCK_ON = false, skip"`
- 异常时: `"[StateRestore] restore float clock failed: {message}"`

## 7. 涉及文件

| 文件 | 改动量 | 内容 |
|---|---|---|
| `constant/SpKeys.ets` | +3 行 | 新增 3 个键 |
| `mainability/MainAbility.ets` | +40 行 | 恢复逻辑 + 日志 |
| `pages/HomePage.ets` | +2 行 | 两处 onChange 追加 put |
| `pages/LocalWebPage.ets` | +2 行 | toggleServer 追加 put |

## 8. 测试验证

1. 开启悬浮时钟，杀进程重启，确认自动恢复
2. 开启悬浮压测，杀进程重启，确认自动恢复
3. 开启 Web 服务，杀进程重启，确认服务器自动启动
4. 全部关闭，重启确认无任何功能自动启动
5. 混合状态：部分开部分关，重启确认精确恢复
6. 通过 `hdc hilog` 实时查看 `[StateRestore]` 日志，确认执行流程

## 9. 边缘情况

- **无悬浮窗权限**: `FloatClockManager.show()` 内部会弹出引导对话框，无需额外处理
- **设备未连 WiFi**: Web 服务恢复时 IP 获取可能失败，仅影响 IP 展示不影响服务器启动
- **快速连续关闭重启**: `putBoolean` 异步写入无竞态风险
- **首次安装**: 所有键不存在，`AppUtil.getBooleanSync` 返回默认值 `false`，无任何功能启动
