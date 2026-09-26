target选择dev，登录账号签名并申请ACL权限，可以使用部分依赖悬浮窗权限的工具。

## 首次拉取后如何构建

`build-profile.json5` **不在版本控制内**（含本机签名绝对路径与机器绑定口令），需要本地生成：

```bash
# 方式一：用 DevEco Studio 打开工程，Project Structure → Signing Configs 勾选自动签名
# 方式二：复制模板后填入本机签名路径与口令
copy build-profile.template.json5 build-profile.json5
```

构建脚本依赖 `DEVECO_HOME`（首次执行一次 `setx DEVECO_HOME "C:\Program Files\Huawei\DevEco Studio"`）：

```bash
build-dev.bat           # dev 包（含悬浮工具）→ 构建并安装
build-ag-debug.bat      # AG 版本地验证
build-ag-release.bat    # 提审打包 .app
```

改完代码建议跑一次自检（编译两个变体 + 发布卫生 + 可选真机冒烟）：

```powershell
pwsh -File tools/verify_build.ps1 -Device 192.168.3.144:12345
```

更多细节（架构、后台长时任务、Web 服务安全、HDC、构建系统）见 `docs/knowledge-base.md`。

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
├── docs/ # 知识库与设计文档  
├── tools/ # 图标生成、构建自检脚本  
├── hvigor/ # 构建配置  
├── oh_modules/ # 依赖模块  
└── sign/ # 签名配置（不纳入版本控制）

