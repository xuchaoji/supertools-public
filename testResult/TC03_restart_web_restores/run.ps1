# TC03 执行脚本
# 重启 → Web 服务自动恢复

# 1. 强制停止
hdc shell aa force-stop com.xuchaoji.hmos.supertools.dev

# 2. 清日志 + 重新启动
hdc shell hilog -r
hdc shell aa start -a MainAbility -b com.xuchaoji.hmos.supertools.dev

# 3. 等待恢复 + 截图
Start-Sleep -Seconds 5
hdc shell "snapshot_display"
hdc file recv "/data/local/tmp/snapshot_*.jpeg" "testResult\TC03_restart_web_restores\screenshot.jpeg"

# 4. 验证恢复日志
hdc shell "hilog -x -e StateRestore"
# 期望输出：
# [StateRestore] reading FLOAT_CLOCK_ON = false → skip
# [StateRestore] reading CPU_STRESS_ON = false  → skip
# [StateRestore] reading WEB_SERVER_ON = true   → restored

# 5. 验证：8088 应监听
hdc shell "netstat -tlnp 2>/dev/null" | Select-String "8088"

# 6. 验证：FloatBallWindow 应存在
hdc shell "hidumper -s WindowManagerService -a '-a'" | Select-String "FloatBallWindow"
