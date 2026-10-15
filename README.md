# Swift FRP Client (frpc-swift)

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B%20%7C%20iOS%2016%2B-blue.svg)](https://developer.apple.com)

纯 Swift 实现的 FRP (Fast Reverse Proxy) 客户端。与官方 `frps` 协议完全兼容，移除了服务端 (frps) 相关依赖，专为移动端（iOS / iPadOS / macOS）和 Swift 命令行环境设计。

---

## 特性

- **协议对齐**：完整支持 FRP 官方客户端通讯协议（Login、NewProxy、ReqWorkConn、StartWorkConn、Ping/Pong 心跳等），兼容 FRP v0.50.0 ~ v0.71.0+ 服务端。
- **现代并发模型**：基于 Swift 6 Modern Concurrency（`async`/`await`、`Actor`、`Sendable`），高并发下零数据竞争。
- **系统原生传输**：基于 Apple 原生 `Network.framework` 与 `CryptoKit`，无需庞大的第三方 C/C++ 依赖，原生支持 TCP 与 TLS。
- **多路复用支持 (Yamux)**：内置轻量原生 Yamux 多路复用实现（`tcpMux = true`，FRP 默认模式），同时支持普通 TCP 直连模式（`tcpMux = false`）。
- **多种代理类型**：
  - **TCP 代理**：将远程端口转发至本地指定 IP 与端口（如 SSH、数据库等）。
  - **HTTP / HTTPS 代理**：支持自定义域名（`customDomains`）、子域名（`subdomain`）、路径路由（`locations`）及 HTTP 鉴权。
  - **STCP 代理**：基于 `secretKey` 的安全点对点穿透代理。
- **双模态交付**：
  - **`FRPClient` 模块**：可直接在 iOS、macOS 应用中作为 Swift Package 引用。
  - **`frpc-swift` CLI**：可独立运行的命令行二进制程序，支持读取标准 `frpc.toml` 文件。

---

## 项目结构

```
swift-frp/
├── Package.swift
├── Sources/
│   ├── FRPClient/                     # 核心库模块
│   │   ├── Model/
│   │   │   ├── FRPConfig.swift        # 配置模型 (服务端地址、鉴权、代理列表等)
│   │   │   └── FRPMessage.swift       # 协议消息定义 (Login, NewProxy, WorkConn 等)
│   │   ├── Protocol/
│   │   │   ├── FRPFrameCodec.swift    # 1B Type + 8B Length + JSON 帧编解码
│   │   │   └── FRPAuth.swift          # Token 鉴权 MD5 计算
│   │   ├── Transport/
│   │   │   ├── AsyncConnection.swift  # 统一异步连接抽象
│   │   │   ├── NWAsyncConnection.swift# Network.framework 实现 (TCP/TLS)
│   │   │   ├── Connector.swift        # 物理连接与多路复用调度器
│   │   │   └── Yamux/                 # 纯 Swift Yamux 多路复用实现
│   │   ├── Proxy/
│   │   │   ├── ProxyHandler.swift     # 代理工作流处理器
│   │   │   └── StreamBridge.swift     # 本地服务与工作连接高速双向流量泵
│   │   ├── Config/
│   │   │   └── SimpleTOMLParser.swift # 标准 frpc.toml 配置文件解析器
│   │   └── FRPClientService.swift     # 客户端核心服务管理器 (Actor)
│   └── FRPClientCLI/
│       └── main.swift                 # 命令行可执行入口
└── Tests/
    └── FRPClientTests/                # 单元测试与集成测试
```

---

## 快速上手

### 1. 运行命令行工具

```bash
# 查看帮助
swift run frpc-swift --help

# 通过配置文件启动客户端
swift run frpc-swift -c frpc.toml
```

### 2. 配置文件示例 (`frpc.toml`)

```toml
serverAddr = "x.x.x.x"
serverPort = 7000
user = "my_user"

[auth]
token = "your_frp_token"

[transport]
tcpMux = true
tls.enable = false

# 示例 1: TCP 代理 (将远程 6000 端口映射到本地 SSH 22 端口)
[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6000

# 示例 2: HTTP 代理
[[proxies]]
name = "web"
type = "http"
localIP = "127.0.0.1"
localPort = 8080
customDomains = ["web.yourdomain.com"]
```

### 3. 在 Swift 代码 / App 中集成

在您的 `Package.swift` 中添加依赖：
```swift
dependencies: [
    .package(path: "../swift-frp")
]
```

在 Swift 代码中直接启动 FRP 客户端服务：

```swift
import FRPClient

let config = FRPClientConfig(
    serverAddr: "1.2.3.4",
    serverPort: 7000,
    auth: FRPAuthConfig(token: "your_token"),
    transport: FRPTransportConfig(tcpMux: true),
    proxies: [
        FRPProxyConfig(
            name: "local_web",
            type: .tcp,
            localIP: "127.0.0.1",
            localPort: 8080,
            remotePort: 8080
        )
    ]
)

let service = FRPClientService(config: config)

// 启动客户端
Task {
    do {
        try await service.start()
    } catch {
        print("FRP Client failed: \(error)")
    }
}

// 停止客户端
// await service.stop()
```

---

## 运行测试

```bash
swift test
```
包含：
- Token MD5 签名校验测试
- 官方网络协议报文（1+8+N）编解码测试
- Yamux 帧打包与多路复用测试
- TOML 配置文件解析测试
- 端到端连接、注册与心跳集成测试
