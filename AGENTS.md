# 项目约定

## hdc 真机调试

- 所有 hdc 命令必须用 `-t <target>` 明确指定设备，禁止依赖默认设备；多设备并存时先 `hdc list targets -v` 确认。
- 维护已知设备台账（target、机型、系统版本）；遇到台账里没有的设备，先说明情况并主动询问该设备的解锁密码，未拿到密码前不得尝试解锁/注入输入。
- 锁屏状态下调试先区分两件事：亮屏（`power-shell wakeup`）≠ 解锁；解锁到桌面需要额外的凭据或手段。
- 临时截图、拉取文件统一放 `.tmp/`，用完即弃，不提交。

## 解锁与保持可调试

- 完整流程、坑位与验证方法见技能 `hmos-device-unlock`；一条命令版：`pwsh -File tools/unlock.ps1 -Target <target>`。
- 设备—密码台账在 `.dsh/devices.json`（已 gitignore，不提交）；脚本按 `-Password` > `HDC_UNLOCK_PASSWORD` > 台账 的顺序取密码。
- 亮屏后约 10 秒进 DIM，DIM 下触摸只提亮不产生事件：上划 + 输密码必须一口气跑完，中间不要截图或拉文件。
