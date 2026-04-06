target选择dev，登录账号签名并申请ACL权限，可以使用部分依赖悬浮窗权限的工具。

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
├── hvigor/ # 构建配置
├── oh_modules/ # 依赖模块
└── sign/ # 签名配置
