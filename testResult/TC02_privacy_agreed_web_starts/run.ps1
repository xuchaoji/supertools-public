# TC02 执行脚本
# 同意隐私 → Web 服务立即启动

# 1. 点击「同意」按钮（隐私页面底部）
# 按钮坐标从 uitest dumpLayout 提取：[542,2167][1084,2394] 区域右侧
hdc shell "uitest uiInput click 761 2347"

# 2. 等待页面跳转 + 截图
Start-Sleep -Seconds 3
hdc shell "snapshot_display"
hdc file recv "/data/local/tmp/snapshot_*.jpeg" "testResult\TC02_privacy_agreed_web_starts\screenshot.jpeg"

# 3. 验证：8088 应监听
hdc shell "netstat -tlnp 2>/dev/null" | Select-String "8088"
# 期望输出：tcp ... 0.0.0.0:8088 ... LISTEN

# 4. 验证：FloatBallWindow 应存在
hdc shell "hidumper -s WindowManagerService -a '-a'" | Select-String "FloatBallWindow"

# 5. 验证：privacy_agree 已写入
hdc shell "cat /data/app/el2/100/base/com.xuchaoji.hmos.supertools.dev/haps/main/preferences/SP_HARMONY_UTILS_PREFERENCES"
# 期望：<bool key="privacy_agree" value="true"/>
