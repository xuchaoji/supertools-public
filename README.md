target选择dev，登录账号签名并申请ACL权限，可以使用部分依赖悬浮窗权限的工具。

## Markdown 笔记

首页「Markdown」卡片进入的笔记功能：

- 列表、编辑器、预览、搜索、删除确认、自动保存、本地文件存储；
- 删除确认使用系统沉浸光感弹窗；内容区按官方建议使用半透明底色 + 背景模糊兜底；
- 笔记正文保存在应用沙箱 `filesDir/markdown_notes/`，不依赖数据库或云服务。

> 安装时 HAP 需要同时带上它的依赖模块；`build-dev.bat` / `build-ag-debug.bat` 已经处理两个包的推送和安装，需要显式传入设备 target：
>
> ```bat
> build-dev.bat 192.168.3.144:12345
> ```
>
> DevEco Studio 的 Run 会自动带上依赖模块，不需要手动处理。

## 首次拉取与构建说明

代码库已预置标准的 `build-profile.json5` 工程架构配置，**clone 下来即可被 DevEco Studio 直接识别为鸿蒙工程**。

为了避免后续配置本地调试签名时将本机绝对路径与密钥误提交至 Git，建议在首次拉取后执行一次保护命令（或运行初始化脚本）：

```bash
# 方式一：直接使用 Git 忽略本地对 build-profile.json5 的修改（推荐）
git update-index --skip-worktree build-profile.json5

# 方式二：使用跨平台辅助脚本（自动设置保护 / 迁移备份）
node tools/setup_signing.js
# 或 Windows PowerShell:
pwsh -File tools/setup_signing.ps1
```

> **签名说明**：
> - 在 DevEco Studio 打开工程后，进入 **File → Project Structure → Signing Configs** 勾选自动签名即可完成本机调试签名配置。
> - 配合 `git skip-worktree`，本地签名修改永远不会污染代码库。如需迁移换机，可使用 `node tools/setup_signing.js --from <备份路径>`。

构建脚本依赖 `DEVECO_HOME`（首次执行一次 `setx DEVECO_HOME "C:\Program Files\Huawei\DevEco Studio"`）：

```bash
build-dev.bat 192.168.3.144:12345   # dev 包（含悬浮工具）+ notes_hsp → 构建并安装
build-ag-debug.bat 192.168.3.144:12345  # AG 版本地验证
build-ag-release.bat               # 提审打包 .app（HSP 会一起进包）
```

改完代码建议跑一次自检（dev / default / release 三条构建链 + 发布卫生 + 可选真机冒烟）：

```powershell
pwsh -File tools/verify_build.ps1 -Device 192.168.3.144:12345
```

更多细节（架构、后台长时任务、Web 服务安全、HDC、构建系统）见 `docs/knowledge-base.md`。

## 第三方组件

- [`@luvi/lv-markdown-in`](https://ohpm.openharmony.cn/#/cn/detail/@luvi%2Flv-markdown-in)（MIT）：Markdown 解析与原生渲染，仅在 `notes_hsp` 中依赖；其 LaTeX / 代码高亮 / Mermaid 能力会带入相应原生库，HSP 体积较大。

## 目录结构

supertools/  
├── AppScope/ # 应用全局配置  
├── main/  
│ ├── src/main/ets/  
│ │ ├── capabilities/ # 能力模块  
│ │ │ ├── floatingclock/ # 悬浮时钟  
│ │ │ └── floatingstress/ # 压力测试悬浮窗  
│ │ ├── components/ # 可复用组件  
│ │ ├── model/ # 数据模型  
│ │ ├── pages/ # 页面组件  
│ │ ├── utils/ # 工具类  
│ │ ├── viewmodel/ # 视图模型  
│ │ ├── widgets/ # 微件  
│ │ └── workers/ # Worker 线程  
│ └── resources/ # 资源文件  
├── notes_hsp/ # Markdown 笔记 HSP（UI + 存储 + lv-markdown-in）
├── docs/ # 知识库与设计文档  
├── tools/ # 图标生成、构建自检脚本  
├── hvigor/ # 构建配置  
├── oh_modules/ # 依赖模块  
└── sign/ # 签名配置（不纳入版本控制）

