<p align="center">
  <img src="logo.png" width="130" height="130" alt="Porta Logo" style="border-radius: 24px;" />
</p>

<h1 align="center">Porta</h1>

<p align="center">
  <strong>High-performance, elegant macOS FRP client desktop application built with pure Swift 6 and Apple native stack</strong>
</p>

<p align="center">
  A native macOS desktop client for FRP (Fast Reverse Proxy), crafted in 100% pure Swift 6 with modern concurrency and Apple <code>Network.framework</code>.
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
  <a href="#features">Features</a> •
  <a href="#comparison">Comparison</a> •
  <a href="#installation">Installation</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#configuration">Configuration</a>
</p>

<p align="center">
  <a href="README.md">简体中文</a> | <a href="README_EN.md"><strong>English</strong></a>
</p>

---

## Introduction

**Porta** is a high-performance, lightweight FRP (Fast Reverse Proxy) client desktop application designed natively for macOS, built in pure Swift 6 and fully aligned with the official [fatedier/frp](https://github.com/fatedier/frp) server communication protocol.

Traditional solutions typically rely on running the Go-based official client inside the terminal or utilizing bloated Electron-wrapped web apps, which often carry high memory overhead, lack macOS low-power sleep coordination, and offer no native desktop interface.

Porta deeply integrates into the macOS ecosystem, combining native performance with a polished GUI experience:
- **Pure Native Stack**: Built directly on Apple's native `Network.framework` and `CryptoKit`, requiring no Go runtime or third-party dynamic libraries, idling at under 15MB RAM;
- **Swift 6 Strict Concurrency**: Full `Actor` state isolation and structured concurrency ensuring a zero-data-race guarantee;
- **In-house Yamux Multiplexing**: An industrial-grade pure Swift Yamux protocol engine multiplexing streams across a single long-lived connection;
- **Refined macOS Experience**: A SwiftUI application tailored for macOS Sonoma and Sequoia, offering persistent menu bar access, instant multi-server switching, smart port conflict diagnosis, and microsecond live logs.

---

## Features

- **Apple Native Architecture & Ultra-low Energy Consumption**  
  Built on system-level `Network.framework` and `CryptoKit` with zero external dependencies. Coordinated with macOS power management and sleep wake-up cycles, maintaining a resident footprint under 15MB.

- **Swift 6 Modern Concurrency Safety**  
  The core state machine is isolated within an `Actor` with strict `Sendable` validation. Guarantees compile-time thread safety under high-throughput traffic and dynamic reconnection events.

- **Pure Swift Yamux Multiplexing Protocol**  
  Independent implementation of standard Yamux flow control (window updates, dynamic stream ID allocation, Ping, and GoAway). Eliminates repeated connection handshakes over a single TCP/TLS socket.

- **Menu Bar Resident & Fast Access**  
  Built with SwiftUI matching the macOS design language. Supports persistent menu bar status, global keyboard shortcuts, instant server switching, and visual connectivity indicators.

- **Smart Port Conflict Diagnostics & Quick Resolution**  
  When an incoming port is occupied or rejected by the server, Porta presents an actionable banner detailing the collision and providing a 1-click edit prompt.

- **Microsecond Real-time Log Inspector**  
  Built-in log console supporting filtration across `DEBUG`, `INFO`, `WARN`, and `ERROR` levels, instant search, and one-click log clearing for effortless diagnostics.

- **Comprehensive Protocol Support & Encryption**  
  Compatible with FRP v0.50.0 ~ v0.71.0+ servers. Supports TCP, UDP, HTTP/HTTPS virtual hosts (domains, subdomains, path routing, basic auth, and host rewrites), and STCP private tunnels with AES-CFB 128-bit encryption.

---

## Comparison

| Dimension | Official frpc (Go) | Electron / Web Wrappers | **Porta (This Project)** |
| :--- | :---: | :---: | :---: |
| **Implementation** | Go Runtime + BSD Socket | Chromium + Node.js + Go Bin | **Pure Swift 6 + Network.framework** |
| **Resident Memory** | ~40 MB - 80 MB | ~250 MB - 600 MB | **< 15 MB (Ultra lightweight)** |
| **Cold Startup Time** | ~150 ms | ~2500 ms+ | **< 30 ms (Instantaneous)** |
| **Runtime Dependencies** | Embedded Go runtime & GC threads | Full browser engine bundled | **Zero external dependencies (System link)** |
| **UI & Desktop UX** | CLI only, no graphical interface | Web view, no native menu bar feel | **Native SwiftUI + Menu Bar Resident** |
| **Port Conflict Handling** | English logs in console only | Generic error messages | **Auto-diagnosed banner with quick fix** |
| **Server Management** | Manually editing config files | Cumbersome interface | **Visual presets & 1-click hot switching** |
| **Energy Optimization** | Incompatible with system sleep APIs | High CPU & battery drain | **Native macOS power management & sleep wake** |

---

## Installation

### Pre-built Application

Download the latest release from [GitHub Releases](https://github.com/miwuyouth/Porta/releases):
- **`Porta-{version}.dmg`**: Open and drag `Porta.app` into your `Applications` folder;
- **`Porta-{version}-{sha}.zip`**: Extract and run.

> Requirements: macOS 14.0 (Sonoma) or newer. Universal binary natively supporting both Apple Silicon (M1–M4) and Intel Macs.

---

### Building from Source

To package the application and DMG locally:

```bash
# 1. Install project generator
brew install xcodegen

# 2. Package release bundle
chmod +x scripts/package.sh
./scripts/package.sh 0.1.0
```

The compiled `Porta.app` and `Porta-0.1.0.dmg` will be generated in the `dist/` directory.

---

## Quick Start

1. **Launch**: Start Porta and click the menu bar status icon to open the main control panel.
2. **Configure Server**: Press `⌥⌘M` or click the gear icon to manage servers. Enter your server address, port, and auth token. Preset multiple server nodes as needed.
3. **Add Proxies**: Press `⌘N` to create proxy rules, selecting the proxy type (TCP, HTTP, UDP, STCP) along with local port and remote port/domain.
4. **Connect**: Click the toggle to connect. If a remote port conflict occurs, an alert banner immediately shows the cause and resolution.
5. **Inspect Logs**: Press `⌘L` to open the real-time log inspector with level filters and keyword search.

---

## Configuration

Porta's configuration format is fully compatible with official FRP. For detailed `frpc.toml` syntax, options, and advanced configuration guides, please refer to the official [fatedier/frp documentation](https://github.com/fatedier/frp).

---

## Protocol & Feature Matrix

| Category | Feature | Status | Details |
| :--- | :--- | :---: | :--- |
| **Control Signaling** | Login / LoginResp | Supported | Aligned with v0.50 ~ v0.71+, RunID session tracking |
| | NewProxy / NewProxyResp | Supported | Proxy registration workflow & remote port allocation |
| | ReqWorkConn / StartWorkConn | Supported | Dispatches incoming work connections to local ports |
| | Ping / Pong Heartbeats | Supported | Autonomous heartbeat probing with auto-reconnect |
| **Transport** | Yamux Multiplexing (`tcpMux = true`) | Supported | Pure Swift in-house implementation with flow control |
| | TCP Direct Mode (`tcpMux = false`) | Supported | Traditional mode with per-connection physical TCP |
| | TLS Transport Encryption | Supported | Built on Apple `Network.framework` native TLS with SNI |
| **Proxy Types** | TCP Proxy | Supported | High-speed bidirectional stream bridging |
| | UDP Proxy | Supported | Full packet slicing, fragmentation, and dispatch |
| | HTTP Proxy | Supported | Supports `customDomains`, `subdomain`, `locations`, `hostHeaderRewrite` |
| | HTTPS Proxy | Supported | Official HTTPS tunneling support |
| | STCP Private Tunnels | Supported | Protected by AES-CFB 128-bit stream symmetric cipher |
| **Reliability & UX** | Port Conflict Diagnostics | Supported | Detects port collision errors with instant actionable UI feedback |
| | Graceful Shutdown | Supported | Clean signal handling with socket teardown |
| | Multi-server Hot Switching | Supported | Switch between server presets in the GUI |
| | Automated Tests | Supported | 246 unit and integration test cases |

---

## Repository Structure

```
Porta/
├── Package.swift               # SPM package manifest
├── project.yml                 # XcodeGen configuration for Porta.xcodeproj
├── logo.png                    # Project logo
├── frpc.toml                   # Sample configuration
├── scripts/
│   └── package.sh              # Packaging script (DMG & ZIP)
├── Porta/                      # macOS SwiftUI app source code
│   ├── App/                    # App lifecycle & AppDelegate
│   ├── Views/                  # Main window, settings, proxy sheets, live logs
│   ├── Services/               # Process manager, log service, config generator
│   └── Assets.xcassets/        # AppIcon & visual assets
├── Sources/
│   └── FRPClient/              # Core Swift package (FRP protocol & network engine)
└── Tests/
    └── FRPClientTests/         # 246+ unit and integration test suite
```

---

## Roadmap

- [x] Pure Swift 6 protocol alignment and actor-isolated state machine
- [x] In-house Yamux multiplexer engine
- [x] Porta macOS menu bar & desktop app (SwiftUI)
- [x] Port conflict diagnostics and real-time log inspector
- [x] 246 automated test cases passing
- [ ] XTCP P2P direct hole punching (pure Swift NAT traversal)
- [ ] QUIC / KCP transport acceleration
- [ ] Homebrew Cask formula (`brew install --cask porta`)

---

## Contributing

Contributions are welcomed:

1. Fork the repository;
2. Create a feature branch: `git checkout -b feature/your-feature`;
3. Run test suite: `swift test`;
4. Commit and push your changes;
5. Open a Pull Request.

---

## License

This project is licensed under the [MIT License](LICENSE).
