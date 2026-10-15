import Foundation
import FRPClient

@main
struct FRPClientCLI {
    static func main() async {
        print("=== FRP Swift Client (frpc-swift) ===")

        let args = CommandLine.arguments
        var configPath = "frpc.toml"

        var i = 1
        while i < args.count {
            if args[i] == "-c" || args[i] == "--config" {
                if i + 1 < args.count {
                    configPath = args[i + 1]
                    i += 1
                }
            } else if args[i] == "-h" || args[i] == "--help" {
                printUsage()
                return
            }
            i += 1
        }

        let fileManager = FileManager.default
        let expandedPath = NSString(string: configPath).expandingTildeInPath

        guard fileManager.fileExists(atPath: expandedPath) else {
            print("Error: Configuration file not found at \(configPath)")
            print("Use -c <path_to_config.toml> to specify a valid config file.")
            exit(1)
        }

        print("Loading configuration from \(configPath)...")

        guard let content = try? String(contentsOfFile: expandedPath, encoding: .utf8) else {
            print("Error: Failed to read configuration file.")
            exit(1)
        }

        let config: FRPClientConfig
        do {
            config = try SimpleTOMLParser.parse(content: content)
        } catch {
            print("Error parsing configuration: \(error)")
            exit(1)
        }

        print("Server: \(config.serverAddr):\(config.serverPort)")
        print("Loaded \(config.proxies.count) proxies:")
        for p in config.proxies {
            print("  - [\(p.name)] (\(p.type)) -> Local \(p.localIP):\(p.localPort)" + (p.remotePort != nil ? ", Remote Port: \(p.remotePort!)" : ""))
        }

        let service = FRPClientService(config: config)

        // Setup signal handling for graceful shutdown
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)

        sigintSource.setEventHandler {
            print("\nReceived SIGINT. Shutting down...")
            Task {
                await service.stop()
                exit(0)
            }
        }
        sigtermSource.setEventHandler {
            print("\nReceived SIGTERM. Shutting down...")
            Task {
                await service.stop()
                exit(0)
            }
        }

        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        sigintSource.resume()
        sigtermSource.resume()

        do {
            try await service.start()

            // Keep main loop alive
            while true {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        } catch {
            print("FRP Client exited with error: \(error)")
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        Usage:
          frpc-swift -c <config_path>
          frpc-swift --help

        Options:
          -c, --config <file>   Path to configuration TOML file (default: frpc.toml)
          -h, --help            Show this help information
        """)
    }
}
