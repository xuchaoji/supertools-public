# 状态持久化功能 — 测试报告

**测试日期**: 2026-06-28  
**测试设备**: HarmonyOS 设备 (1084×2412)  
**应用版本**: 2.1.1 (buildMode=debug, dev target)

## 用例执行总览

| 用例 | 名称 | 结果 | 截图 |
|---|---|---|---|
| [TC01](./TC01_first_launch_no_privacy/README.md) | 首次安装-未同意隐私-Web服务不启动 | ✅ 通过 | ✅ |
| [TC02](./TC02_privacy_agreed_web_starts/README.md) | 同意隐私-Web服务立即启动 | ✅ 通过 | ✅ |
| [TC03](./TC03_restart_web_restores/README.md) | 重启-Web服务自动恢复 | ✅ 通过 | ✅ |
| [TC04](./TC04_disable_autostart_stops/README.md) | 关闭服务自启-使用默认值恢复 | ✅ 通过 | ✅ |
| [TC05](./TC05_disable_autostart_restart_defaults/README.md) | 启用自启+关闭Web-不启动 | ✅ 通过 | ✅ |

## 自动化方法

- **页面操作**: `hdc uitest uiInput click <x> <y>` — 精确定位点击
- **布局定位**: `uitest dumpLayout -p <path> -b <bundle>` — 导出 UI 层级 JSON，提取每个元素的精确 `bounds`
- **截图**: `hdc shell snapshot_display` + `hdc file recv`
- **日志验证**: `hdc shell hilog -x -e StateRestore`
- **端口验证**: `hdc shell netstat -tlnp`
- **窗口验证**: `hdc shell hidumper -s WindowManagerService`

## 已知限制

- 无。`uitest dumpLayout` + `uiInput` 组合已验证可在深嵌套组件（Scroll > List > Toggle）中精确点击
