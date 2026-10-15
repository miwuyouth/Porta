import SwiftUI

@main
struct PortaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 Porta") {
                    AppDelegate.showAboutPanel()
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("添加代理...") {
                    appState.activeSheet = .addProxy
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("管理服务器...") {
                    appState.activeSheet = .serverManager
                }
                .keyboardShortcut("m", modifiers: [.command, .option])
            }

            CommandMenu("控制") {
                Button("主窗口") {
                    withAnimation {
                        appState.currentScreen = .main
                    }
                    appDelegate.showMainWindow()
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("查看实时日志") {
                    withAnimation {
                        appState.currentScreen = .logs
                    }
                    appDelegate.showMainWindow()
                }
                .keyboardShortcut("l", modifiers: .command)

                Divider()

                Button("重新连接") {
                    appState.processManager.start(
                        server: appState.currentServer,
                        proxies: appState.currentProxies,
                        settings: appState.settings
                    )
                }
                .keyboardShortcut("r", modifiers: .command)

                Button(appState.processManager.isRunning ? "断开连接" : "连接服务器") {
                    if appState.processManager.isRunning {
                        appState.processManager.stop()
                    } else {
                        appState.processManager.start(
                            server: appState.currentServer,
                            proxies: appState.currentProxies,
                            settings: appState.settings
                        )
                    }
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    withAnimation {
                        appState.currentScreen = .settings
                    }
                    appDelegate.showMainWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
