---
name: hmos-device-unlock
description: 鸿蒙真机锁屏导致调试中断时，用 hdc 远程恢复设备可调试状态：亮屏、上划、注入锁屏密码解锁，并基于电源/窗口状态验证结果。包含 hdc 多设备 -t 规则、未知设备先问密码、亮屏≠解锁等硬约定。
whenToUse: 当 DevEco/hdc 调试因设备锁屏（SLEEP、DIM、停留在锁屏界面）而断点、日志、热重载失效，需要远程唤醒并解锁鸿蒙真机时使用；也用于排查"亮屏了但没解锁"的问题。
---

# 鸿蒙真机解锁（hdc）

## 硬约定

- 所有 hdc 命令必须带 `-t <target>`，不依赖默认设备；不确定先 `hdc list targets -v`。
- 台账里没有的设备，先向用户要锁屏密码，拿到之前不尝试解锁、不注入输入事件。
- **亮屏 ≠ 解锁**：`power-shell wakeup` 只点亮屏幕，锁屏界面还在。解锁必须额外注入密码。
- 不靠截图判断状态（截图慢且会被 DIM 打断），靠系统状态：`PowerManagerService` 的 `Current State`、`WindowManagerService` 里的 `SCBScreenLock` 窗口。

## 三步解锁

```powershell
hdc -t <target> shell power-shell wakeup
hdc -t <target> shell uitest uiInput swipe 542 2300 542 500 3000   # 从底部上划，进密码盘
hdc -t <target> shell uitest uiInput text <密码>                    # 逐个注入数字，6 位自提交
```

坐标以 1084x2412 屏幕为准；换分辨率时按比例调整，或先从截图取一次坐标。

## 最大的坑：DIM 只有 10 秒

`hidumper -s PowerManagerService -a '-a'` 里 `OverrideTimeout=10000ms`：亮屏后约 10 秒进入 `DIM`，**DIM 状态下触摸只负责提亮屏幕，不产生滑动事件**，表现为"上划没反应"。

因此：三步必须串成一条命令一口气跑完，中间不要插入截图、拉文件、看日志。验证放到解锁完成之后。

## 验证解锁（替代看图）

- `hidumper -s PowerManagerService -a '-a'` → `Current State: AWAKE`
- `hidumper -s WindowManagerService -a '-a'` → `SCBScreenLock*` 行的 zOrder 为 `-1` 表示已隐藏（已解锁）；为正数表示锁屏仍在
- `aa dump -l` → 目标应用 `state #FOREGROUND` 即为调试态恢复

## 现成脚本

```powershell
pwsh -File tools/unlock.ps1 -Status                                  # 只看状态
pwsh -File tools/unlock.ps1 -Target 192.168.3.144:12345              # 台账取密码
pwsh -File tools/unlock.ps1 -Target 1.2.3.4:12345 -Password 123456   # 显式指定
```

密码来源：`-Password` > `HDC_UNLOCK_PASSWORD` > `.dsh/devices.json`（本地台账，已 gitignore）。
脚本自带一次重试与失败退出码，失败时明确报"仍处于锁屏状态"，不会静默成功。

## 调试建议

- 灭屏期间应用进程通常还活着（锁屏通知可见），断点失效是锁屏/冻结造成的，不必重启应用。
- 解锁后如果长时间对着设备看日志，10 秒后又会灭屏；需要长亮时在应用侧 `window.setWindowKeepScreenOn(true)`，或临时用 `power-shell timeout` 覆盖灭屏时间（记得恢复）。
