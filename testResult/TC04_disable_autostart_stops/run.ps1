# TC04 执行脚本
# 关闭服务自启 → 服务停止 + 状态不记录

# ========== 预处理：确保自启为 ON ==========
# 1. 点击设置 Tab
hdc shell "uitest uiInput click 813 2280"

# 2. 导出布局找 Toggle 坐标
hdc shell "uitest dumpLayout -p /data/local/tmp/layout.xml -b com.xuchaoji.hmos.supertools.dev"
hdc file recv "/data/local/tmp/layout.xml" "layout_tc04.xml"
# 在 layout_tc04.xml 中搜索 "启用服务自启动" 对应的 Toggle
# 期望 bounds: [835,1712][943,1772]，中心 (889,1742)

# ========== TC04 执行 ==========
# 3. 点击 Toggle 关闭自启
hdc shell "uitest uiInput click 889 1742"
# 如果 Toggle 位置变化（滚动偏移），重新执行步骤2获取最新坐标

# 4. 截图
hdc shell "snapshot_display"
hdc file recv "/data/local/tmp/snapshot_*.jpeg" "testResult\TC04_disable_autostart_stops\screenshot.jpeg"

# 5. 验证：Preferences 写入
hdc shell "cat /data/app/el2/100/base/com.xuchaoji.hmos.supertools.dev/haps/main/preferences/SP_HARMONY_UTILS_PREFERENCES"
# 期望：auto_start_enabled = false

# 6. 验证：服务停止
hdc shell "netstat -tlnp 2>/dev/null" | Select-String "8088"
# 期望：无输出（端口关闭）

hdc shell "hidumper -s WindowManagerService -a '-a'" | Select-String "Float"
# 期望：无输出（FloatBallWindow 销毁）
