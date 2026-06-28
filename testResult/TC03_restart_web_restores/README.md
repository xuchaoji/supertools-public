# TC03: 重启 → Web服务自动恢复

**用例描述**: 同意隐私并启动 Web 服务后，杀进程重启，Web 服务应自动恢复。

**前置条件**: 已完成 TC02，Web 服务运行中，隐私已同意。

**测试步骤**:
1. 强制停止应用 (`aa force-stop`)
2. 清除日志
3. 重新启动应用
4. 等待恢复完成
5. 截图记录
6. 检查 Port 8088
7. 检查浮窗状态
8. 检查 StateRestore 日志

**预期结果**:
- Port 8088 LISTEN
- FloatBallWindow 可见
- 悬浮时钟/压测 不启动
- 日志显示 `web server restored`

**实际结果**: ✅ 通过
- Port 8088: LISTEN
- FloatBallWindow: WindowId 561
- FLOAT_CLOCK_ON = false → skip
- CPU_STRESS_ON = false → skip
- WEB_SERVER_ON = true → restored
- 截图: 见 screenshot.jpeg

```
[StateRestore] reading FLOAT_CLOCK_ON = false → skip
[StateRestore] reading CPU_STRESS_ON  = false → skip
[StateRestore] reading WEB_SERVER_ON  = true  → restored
```

![重启后主页截图](screenshot.jpeg)
