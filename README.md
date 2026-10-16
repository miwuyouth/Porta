<p align="center">
  <img src="logo.png" width="130" height="130" alt="Porta Logo" style="border-radius: 24px;" />
</p>

<h1 align="center">Porta</h1>

<p align="center">
  <strong>基于 Swift 6 与 Apple Network.framework 实现的 macOS FRP 客户端应用</strong>
</p>

<p align="center">
  A native macOS FRP client application built with Swift 6 and Apple <code>Network.framework</code>.
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0-F05138.svg?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.0" /></a>
  <a href="https://developer.apple.com/macos"><img src="https://img.shields.io/badge/Platform-macOS%2014%2B-007AFF.svg?style=flat-square&logo=apple&logoColor=white" alt="Platform" /></a>
  <a href="https://github.com/fatedier/frp"><img src="https://img.shields.io/badge/Protocol-FRP%20v0.50%2B-5856D6.svg?style=flat-square" alt="Protocol" /></a>
  <img src="https://img.shields.io/badge/Tests-246%20Passed-34C759.svg?style=flat-square" alt="Tests" />
  <img src="https://img.shields.io/badge/Concurrency-Data--race%20Free-blue.svg?style=flat-square" alt="Concurrency" />
  <img src="https://img.shields.io/badge/Dependencies-0%20External-orange.svg?style=flat-square" alt="Zero Dependencies" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-gray.svg?style=flat-square" alt="License" /></a>
</p>

<p align="center">
  <a href="#核心特性">核心特性</a> •
  <a href="#对比分析">对比分析</a> •
  <a href="#下载与安装">下载安装</a> •
  <a href="#快速上手">快速上手</a> •
  <a href="#配置说明">配置说明</a>
</p>

<p align="center">
  <a href="README.md"><strong>简体中文</strong></a> | <a href="README_EN.md">English</a>
</p>

---

## 项目简介

**Porta** 是一个为 macOS 开发的 FRP (Fast Reverse Proxy) 客户端桌面应用，基于 Swift 6 与 Apple 系统原生网络框架构建，兼容官方 [fatedier/frp](https://github.com/fatedier/frp) 服务端通信协议。

相比直接在终端运行命令行程序或使用基于 Web/Electron 的封装应用，Porta 提供原生 macOS 界面与系统级功能整合：
- **原生网络与加密库**：使用 Apple 原生 `Network.framework` 与 `CryptoKit`，无需 Go 运行时与第三方动态链接库；
- **Swift 6 并发模型**：核心状态使用 Actor 隔离，结合结构化并发（`async`/`await`）消除数据竞争；
- **Yamux 多路复用**：包含纯 Swift 实现的 Yamux 协议栈，支持在单条 TCP/TLS 物理连接上复用多路虚拟流；
- **桌面功能集成**：提供菜单栏常驻、多服务器配置切换、端口冲突状态提示与日志查看面板。

---

## 核心特性

- **原生网络栈**  
  使用系统级 `Network.framework` 与 `CryptoKit`，无外部动态库依赖，支持系统电源管理与网络状态变更事件。

- **并发安全保证**  
  核心状态机基于 Swift 6 `Actor` 实现，利用结构化并发与 `Sendable` 检查，在编译期保证无数据竞争。

- **Yamux 多路复用**  
  内置纯 Swift 实现的标准 Yamux 协议（包含 Stream 分配、Window Update 流量控制、Ping 与 GoAway），可在单条物理 TCP/TLS 连接上并发复用多路虚拟流。

- **菜单栏常驻与快捷键**  
  基于 SwiftUI 构建，支持常驻系统状态栏、快捷键操作（如 `⌘N` 添加代理、`⌥⌘M` 服务器管理、`⌘L` 查看日志）与连接状态指示。

- **端口冲突排查**  
  在代理注册遇到端口占用或服务端冲突时，界面自动提示具体错误信息与受影响代理。

- **日志查看**  
  内置日志面板，支持按 `DEBUG`、`INFO`、`WARN`、`ERROR` 级别筛选与关键字搜索。

- **协议支持**  
  兼容官方 FRP v0.50.0 ~ v0.71.0+ 服务端协议。支持 TCP、UDP、HTTP/HTTPS（自定义域名、子域名、路由路径、Basic 鉴权与 Host 请求头重写），以及基于 AES-CFB 的 STCP 加密代理。

---

## 对比分析

| 维度 | 官方 frpc (Go) | 基于 Electron 客户端 | **Porta (本项目)** |
| :--- | :---: | :---: | :---: |
| **底层实现** | Go 运行时 + BSD Socket | Chromium + Node.js + Go 二进制 | **Swift 6 + Network.framework** |
| **典型内存占用** | 约 40 ~ 80 MB | 约 250 ~ 600 MB | **约 10 ~ 15 MB** |
| **冷启动耗时** | 约 150 ms | 约 2000 ms 以上 | **约 30 ms 以内** |
| **第三方运行时** | 依赖 Go Runtime 与 GC | 包含完整浏览器内核 | **仅依赖系统动态库** |
| **图形界面** | 无（仅命令行） | Web 页面 | **原生 SwiftUI + 状态栏常驻** |
| **端口冲突提示** | 终端文本输出 | 基础错误提示 | **界面横幅标示具体冲突端口** |
| **多服务器切换** | 需手动修改配置文件 | 视具体软件实现 | **界面预设直接切换** |
| **系统能耗机制** | 无法直接响应系统低功耗事件 | 依赖 Chromium 能耗调度 | **支持原生电源管理与网络恢复** |

---

## 下载与安装

前往 [GitHub Releases](https://github.com/miwuyouth/Porta/releases) 下载最新安装包：
- **`Porta-{version}.dmg`**：打开后将 `Porta.app` 拖入 `Applications` 目录即可开始使用；
- **`Porta-{version}-{sha}.zip`**：解压即可运行。

> 运行要求：macOS 14.0 (Sonoma) 或更高版本，原生支持 Apple Silicon (M1–M4) 与 Intel 架构。

---

## 快速上手

1. **启动应用**：运行 Porta 后，点击菜单栏图标打开主窗口。
2. **配置服务器**：使用快捷键 `⌥⌘M` 或点击齿轮图标打开服务器管理，输入 FRP 服务端地址、端口与鉴权 Token。
3. **添加代理**：使用快捷键 `⌘N` 新建代理规则，选择代理类型（TCP、HTTP、UDP、STCP），配置本地端口与远程映射端口或域名。
4. **连接与状态**：点击主界面开关启动连接。如存在远程端口冲突等异常，界面顶部将显示具体提示。
5. **查看日志**：使用快捷键 `⌘L` 打开日志窗口，可根据日志级别筛选与搜索。

---

## 配置说明

Porta 的配置文件规范与官方 FRP 保持完全兼容。关于 `frpc.toml` 的详细语法、参数选项及高级配置说明，请直接参考 [fatedier/frp 官方项目文档](https://github.com/fatedier/frp)。

---

## 协议与特性支持

| 模块分类 | 特性项 | 支持情况 | 说明 |
| :--- | :--- | :---: | :--- |
| **基础控制协议** | Login / LoginResp | 支持 | 对齐 v0.50 ~ v0.71+ 协议规范，支持 RunID 会话绑定 |
| | NewProxy / NewProxyResp | 支持 | 代理注册流程与端口分配处理 |
| | ReqWorkConn / StartWorkConn | 支持 | 动态调度工作连接至目标代理 |
| | Ping / Pong 心跳机制 | 支持 | 周期性心跳探测与自动重连 |
| **传输层特性** | Yamux 会话复用 (`tcpMux = true`) | 支持 | 纯 Swift 原生实现，支持流量控制与多流调度 |
| | 普通 TCP 直连 (`tcpMux = false`) | 支持 | 为各工作连接建立独立物理 TCP 链路 |
| | TLS 加密传输 | 支持 | 基于 Apple `Network.framework` 原生 TLS，支持 SNI |
| **代理类型** | TCP 代理 | 支持 | 双向流量透传 |
| | UDP 代理 | 支持 | 包含完整数据包切片与封装处理 |
| | HTTP 虚拟主机代理 | 支持 | 支持 `customDomains`、`subdomain`、`locations` 与 Host 重写 |
| | HTTPS 代理 | 支持 | 原生 HTTPS 穿透支持 |
| | STCP 安全代理 | 支持 | 基于 AES-CFB 128 位对称加密 |
| **质量与交互** | 端口冲突诊断 | 支持 | 自动识别冲突端口并在界面给出操作提示 |
| | 优雅关机 | 支持 | 捕获系统终止信号并安全清理虚拟链路 |
| | 多服务器切换 | 支持 | 桌面端支持多套服务端配置快速切换 |
| | 自动化测试 | 支持 | 包含 246 项单元与集成测试用例 |

---

## 目录结构

```
Porta/
├── Package.swift               # SPM 包描述文件
├── project.yml                 # XcodeGen 工程配置文件 (生成 Porta.xcodeproj)
├── logo.png                    # 项目 Logo
├── frpc.toml                   # 参考配置文件
├── scripts/
│   └── package.sh              # 自动化编译打包脚本 (生成 DMG/ZIP)
├── Porta/                      # macOS SwiftUI 应用源码
│   ├── App/                    # 应用入口与生命周期 (AppDelegate / PortaApp)
│   ├── Views/                  # 界面视图 (主窗口 / 代理设置 / 实时日志)
│   ├── Services/               # 进程与日志管理、配置生成
│   └── Assets.xcassets/        # 原生图标与色彩资源
├── Sources/
│   └── FRPClient/              # FRP 核心协议与网络引擎 (纯 Swift 实现)
└── Tests/
    └── FRPClientTests/         # 246+ 单元与集成测试
```

---

## 路线图

- [x] 纯 Swift 6 协议对齐与 Actor 状态机实现
- [x] 原生纯 Swift Yamux 多路复用引擎
- [x] Porta macOS 状态栏与桌面客户端 (SwiftUI)
- [x] 端口冲突检测与实时日志系统
- [x] 246 项自动化测试用例覆盖
- [ ] XTCP 点对点 NAT 穿透实现
- [ ] QUIC / KCP 传输模式扩展
- [ ] Homebrew Cask 收录支持 (`brew install --cask porta`)

---

## 参与贡献

欢迎提交 Issue 反馈问题或发起 Pull Request：

1. Fork 本仓库；
2. 创建特性分支：`git checkout -b feature/your-feature`；
3. 运行本地测试：`swift test`；
4. 提交修改并推送分支；
5. 发起 Pull Request。

---

## 许可证

本项目基于 [MIT License](LICENSE) 开源发布。
