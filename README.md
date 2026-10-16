<p align="center">
  <img src="logo.png" width="130" height="130" alt="Porta Logo" style="border-radius: 24px;" />
</p>

<h1 align="center">Porta</h1>

<p align="center">
  <strong>基于纯 Swift 6 与 Apple 原生技术栈打造的高性能、精致 macOS FRP 客户端应用</strong>
</p>

<p align="center">
  A high-performance, elegant macOS FRP client application built with pure Swift 6 and Apple <code>Network.framework</code>.
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0-F05138.svg?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.0" /></a>
  <a href="https://developer.apple.com/macos"><img src="https://img.shields.io/badge/Platform-macOS%2014%2B-007AFF.svg?style=flat-square&logo=apple&logoColor=white" alt="Platform" /></a>
  <a href="https://github.com/fatedier/frp"><img src="https://img.shields.io/badge/Protocol-FRP%20v0.50%2B-5856D6.svg?style=flat-square" alt="Protocol" /></a>
  <img src="https://img.shields.io/badge/Tests-246%20Passed-34C759.svg?style=flat-square" alt="Tests" />
  <img src="https://img.shields.io/badge/Concurrency-Data--race%20Free-blue.svg?style=flat-square" alt="Concurrency" />
  <img src="https://img.shields.io/badge/Memory-＜15MB-brightgreen.svg?style=flat-square" alt="Memory" />
  <img src="https://img.shields.io/badge/Dependencies-Zero%20External-orange.svg?style=flat-square" alt="Zero Dependencies" />
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

**Porta** 是专为 macOS 打造的高性能、轻量级 FRP (Fast Reverse Proxy) 客户端桌面应用，基于纯 Swift 6 与 Apple 原生技术栈构建，与官方 [fatedier/frp](https://github.com/fatedier/frp) 服务端协议完全对齐。

传统方案通常依赖在终端运行 Go 官方客户端，或采用资源消耗高昂的 Electron 网页套壳工具，普遍面临内存占用大、无法参与 macOS 硬件级低功耗休眠调度以及缺乏原生交互等问题。

Porta 深度融合 macOS 生态，兼备原生级性能与细腻的桌面交互体验：
- **纯原生技术栈**：直接基于 Apple 原生 `Network.framework` 与 `CryptoKit`，无需 Go 运行时与额外动态库，常驻内存低于 15MB；
- **Swift 6 现代化并发**：全链路采用 Actor 状态隔离与结构化并发，零数据竞争（Data-race free）；
- **原生 Yamux 多路复用**：自主实现工业级纯 Swift Yamux 协议栈，单长连接复用海量虚拟数据流；
- **精致的原生桌面体验**：专为 macOS 设计的 SwiftUI 界面，提供状态栏常驻、多服务器热切换、智能端口冲突告警与实时日志流。

---

## 核心特性

- **Apple 原生架构与超低能耗**  
  基于系统级 `Network.framework` 与 `CryptoKit`，无任何外部动态链接库依赖。深度适配 macOS 电源管理与网络休眠唤醒机制，常驻内存仅需十余兆。

- **Swift 6 严格并发安全**  
  核心状态机采用 `Actor` 强隔离，异步逻辑遵循结构化并发规范，在高并发流量吞吐、多代理通道注册及网络重连时提供编译器级线程安全保证。

- **纯 Swift Yamux 多路复用协议栈**  
  独立实现标准 Yamux 协议（支持 Stream 动态分配、Window Update 流量控制、Ping 与 GoAway）。单条物理 TCP/TLS 链路并发复用多路虚拟通道，显著减少频繁握手开销。

- **菜单栏常驻与高效快捷操作**  
  原生 SwiftUI 构建，与 macOS Sonoma / Sequoia 视觉语言高度契合。支持系统菜单栏常驻、全局快捷键、多服务器预设秒级切换与连接状态指示。

- **智能端口冲突诊断与一键处理**  
  在代理端口被占用或远程冲突时，界面顶部自动弹出醒目的诊断横幅，直观展示错误详情并提供快速修改入口。

- **微秒级实时日志系统**  
  内置日志控制台，支持按 `DEBUG`、`INFO`、`WARN`、`ERROR` 多级别过滤，支持即时搜索与日志清空，方便本地调试与网络诊断。

- **完整协议兼容与安全加密**  
  兼容 FRP v0.50.0 ~ v0.71.0+ 官方服务端。支持 TCP、UDP、HTTP/HTTPS 虚拟主机反代（自定义域名、子域名、路径路由、Basic 鉴权与 Host 重写），以及基于 AES-CFB 128 位流对称加密的 STCP 点对点穿透。

---

## 对比分析

| 维度 | 官方 frpc (Go) | Electron / 网页打包工具 | **Porta (本项目)** |
| :--- | :---: | :---: | :---: |
| **底层实现** | Go Runtime + BSD Socket | Chromium + Node.js + Go 二进制 | **纯 Swift 6 + Network.framework** |
| **常驻内存** | ~40 MB - 80 MB | ~250 MB - 600 MB | **< 15 MB (超轻量)** |
| **冷启动耗时** | ~150 ms | ~2500 ms+ | **< 30 ms (秒启)** |
| **运行时依赖** | 包含 GC 线程与 Go 运行时 | 包含完整浏览器内核 | **零外部依赖 (系统动态链接)** |
| **界面与交互** | 仅终端命令，无图形界面 | 网页视图，无菜单栏与原生质感 | **原生 SwiftUI + 菜单栏常驻** |
| **端口冲突处理** | 仅控制台打印英文日志 | 无针对性提示 | **自动诊断冲突并在界面弹出解决方案** |
| **多服务器管理** | 手动修改或替换配置文件 | 操作繁琐 | **图形化管理，一键平滑热切换** |
| **系统能耗优化** | 无法参与系统低功耗调度 | 高 CPU 与电量占用 | **原生系统级电源管理与休眠恢复** |

---

## 下载与安装

### 预编译应用

前往 [GitHub Releases](https://github.com/miwuyouth/Porta/releases) 下载最新安装包：
- **`Porta-{version}.dmg`**：打开后将 `Porta.app` 拖入 `Applications` 目录即可开始使用；
- **`Porta-{version}-{sha}.zip`**：解压即可运行。

> 运行要求：macOS 14.0 (Sonoma) 或更高版本，原生支持 Apple Silicon (M1–M4) 与 Intel 架构。

---

### 从源码编译打包

如果你希望在本地构建并打包 DMG 镜像：

```bash
# 1. 安装工程生成工具
brew install xcodegen

# 2. 一键编译并生成 DMG 与 ZIP
chmod +x scripts/package.sh
./scripts/package.sh 0.1.0
```

打包完成后，产物将自动生成于 `dist/` 目录下（包含 `Porta.app` 与 `Porta-0.1.0.dmg`）。

---

## 快速上手

1. **启动应用**：运行 Porta 后，菜单栏将出现连接图标，点击即可展开主控制面板。
2. **管理服务器**：快捷键 `⌥⌘M` 或点击右上角齿轮图标打开服务器管理面板，填入 FRP 服务端地址、端口及鉴权 Token，支持预设任意多台节点。
3. **添加代理规则**：快捷键 `⌘N` 新建代理规则，选择代理类型（TCP、HTTP、UDP、STCP）并设置本地服务端口与远程端口/域名。
4. **一键开启穿透**：点击主面板开关连接服务器。如远程端口已被占用，界面顶部将提示冲突详情与快速处理方案。
5. **实时日志排错**：快捷键 `⌘L` 呼出实时日志查看器，支持按日志级别过滤与关键词快速检索。

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
- [x] 智能端口冲突诊断与实时日志系统
- [x] 246 项自动化测试用例覆盖
- [ ] XTCP 点对点 NAT 穿透实现
- [ ] QUIC / KCP 弱网加速模式
- [ ] Homebrew Cask 官方收录支持 (`brew install --cask porta`)

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
