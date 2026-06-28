# TC05 执行脚本
# 启用自启 + WEB_SERVER=false → 重启不启动

# ========== 预处理：打开自启开关 ==========
# 1. 点击设置 Tab（如果不在设置页）
hdc shell "uitest uiInput click 813 2280"

# 2. 导出布局找 Toggle 坐标（如果位置不确定）
hdc shell "uitest dumpLayout -p /data/local/tmp/layout.xml -b com.xuchaoji.hmos.supertools.dev"
hdc file recv "/data/local/tmp/layout.xml" "layout_tc05.xml"
# 在 layout_tc05.xml 中搜索 "启用服务自启动" Toggle bounds
# 期望 bounds: [835,1712][943,1772]，中心 (889,1742)
# 注意：如果 checked="true" 则需要点击两次（先关再开）或跳过此步骤

# 3. 点击 Toggle 打开自启（当前 checked=false 时点击）
hdc shell "uitest uiInput click 889 1742"

# 4. 验证：Preferences 中 auto_start_enabled=true 且 web_server_on=false
hdc shell "cat /data/app/el2/100/base/com.xuchaoji.hmos.supertools.dev/haps/main/preferences/SP_HARMONY_UTILS_PREFERENCES"
# 期望：auto_start_enabled=true, web_server_on=false

# ========== TC05 执行 ==========
# 5. 强制停止 + 重启
hdc shell aa force-stop com.xuchaoji.hmos.supertools.dev
hdc shell hilog -r
hdc shell aa start -a MainAbility -b com.xuchaoji.hmos.supertools.dev

# 6. 等待 + 截图
Start-Sleep -Seconds 5
hdc shell "snapshot_display"
hdc file recv "/data/local/tmp/snapshot_*.jpeg" "testResult\TC05_disable_autostart_restart_defaults\screenshot.jpeg"

# 7. 验证恢复日志
hdc shell "hilog -x -e StateRestore"
# 期望输出：
# [StateRestore] reading WEB_SERVER_ON = false → skip

# 8. 验证：8088 不应监听
hdc shell "netstat -tlnp 2>/dev/null" | Select-String "8088"
# 期望输出：无

# 9. 验证：无 Float 窗口
hdc shell "hidumper -s WindowManagerService -a '-a'" | Select-String "FloatBallWindow"
# 期望输出：无
