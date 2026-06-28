# TC01 执行脚本
# 首次安装 → 未同意隐私 → Web 服务不启动

# 1. 安装应用
hdc install "main\build\dev\outputs\dev\main-dev-signed.hap"

# 2. 清日志 + 启动
hdc shell hilog -r
hdc shell aa start -a MainAbility -b com.xuchaoji.hmos.supertools.dev

# 3. 等待加载 + 截图
Start-Sleep -Seconds 5
hdc shell "snapshot_display"
hdc file recv "/data/local/tmp/snapshot_*.jpeg" "testResult\TC01_first_launch_no_privacy\screenshot.jpeg"

# 4. 验证：8088 不应监听
hdc shell "netstat -tlnp 2>/dev/null" | Select-String "8088"
# 期望输出：无（未监听）

# 5. 验证：无 Float 窗口
hdc shell "hidumper -s WindowManagerService -a '-a'" | Select-String "Float"
# 期望输出：无
