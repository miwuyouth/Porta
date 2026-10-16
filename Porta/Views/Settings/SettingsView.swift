import SwiftUI
import ServiceManagement

public struct SettingsView: View {
    @ObservedObject var appState: AppState = .shared
    @State private var showingUpdateAlert: Bool = false

    let logLevels = ["Debug", "Info", "Warn", "Error"]
    let retentionPeriods = ["1 天", "3 天", "7 天", "30 天", "永久"]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header: <  设置
            WindowHeaderView(title: "设置", showBackButton: true, showGearButton: false)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Section 1: 通用
                    VStack(alignment: .leading, spacing: 8) {
                        Text("通用")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .padding(.horizontal, 28)

                        VStack(spacing: 0) {
                            settingsToggleRow(
                                title: "登录时启动",
                                isOn: $appState.settings.launchAtLogin
                            )

                            Divider().padding(.horizontal, 28)

                            settingsToggleRow(
                                title: "启动后隐藏窗口",
                                isOn: $appState.settings.hideWindowOnLaunch
                            )

                            Divider().padding(.horizontal, 28)

                            settingsToggleRow(
                                title: "关闭窗口后保持运行",
                                isOn: $appState.settings.keepRunningAfterWindowClose
                            )
                        }
                    }

                    // Section 2: 连接
                    VStack(alignment: .leading, spacing: 8) {
                        Text("连接")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .padding(.horizontal, 28)

                        VStack(spacing: 0) {
                            settingsToggleRow(
                                title: "断线自动重连",
                                isOn: $appState.settings.autoReconnect
                            )

                            Divider().padding(.horizontal, 28)

                            HStack {
                                Text("重试间隔")
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                Spacer()
                                StepperField(value: $appState.settings.retryIntervalSeconds, range: 1...60, unit: "秒")
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 8)
                            .onChange(of: appState.settings.retryIntervalSeconds) {
                                appState.saveData()
                            }

                            Divider().padding(.horizontal, 28)

                            HStack {
                                Text("连接超时")
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                Spacer()
                                StepperField(value: $appState.settings.connectTimeoutSeconds, range: 1...120, unit: "秒")
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 8)
                            .onChange(of: appState.settings.connectTimeoutSeconds) {
                                appState.saveData()
                            }
                        }
                    }

                    // Section 3: 日志
                    VStack(alignment: .leading, spacing: 8) {
                        Text("日志")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .padding(.horizontal, 28)

                        VStack(spacing: 0) {
                            HStack {
                                Text("记录级别")
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                Spacer()
                                Menu {
                                    ForEach(logLevels, id: \.self) { level in
                                        Button(level) {
                                            appState.settings.logLevel = level
                                            appState.saveData()
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(appState.settings.logLevel)
                                            .font(.system(size: 13))
                                            .foregroundColor(.primary)
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(width: 82, height: 26)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .menuIndicator(.hidden)
                                .fixedSize()
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 8)

                            Divider().padding(.horizontal, 28)

                            HStack {
                                Text("保留时间")
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                Spacer()
                                Menu {
                                    ForEach(retentionPeriods, id: \.self) { period in
                                        Button(period) {
                                            appState.settings.logRetention = period
                                            appState.saveData()
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(appState.settings.logRetention)
                                            .font(.system(size: 13))
                                            .foregroundColor(.primary)
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(width: 82, height: 26)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .menuIndicator(.hidden)
                                .fixedSize()
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 8)

                            Divider().padding(.horizontal, 28)

                            HStack {
                                Text("日志文件")
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                Spacer()
                                Button(action: {
                                    NSWorkspace.shared.activateFileViewerSelecting([StorageService.shared.logFilePath])
                                }) {
                                    HStack(spacing: 4) {
                                        Text("在 Finder 中显示")
                                            .font(.system(size: 13))
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 16)
            }

            Divider()

            // Footer: Porta 1.0.0 · frpc 0.65.0              检查更新
            HStack(alignment: .center) {
                Text("Porta \(AppSettings.appVersion) · frpc \(AppSettings.frpcVersion)")
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))

                Spacer()

                Button(action: {
                    showingUpdateAlert = true
                }) {
                    Text("检查更新")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Color.appBackground)
        }
        .background(Color.appBackground)
        .alert("已是最新版本", isPresented: $showingUpdateAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("Porta \(AppSettings.appVersion) 已是当前最新版本。")
        }
    }

    @ViewBuilder
    private func settingsToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.primary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(Color(red: 0.0, green: 0.48, blue: 1.0))
                .labelsHidden()
                .onChange(of: isOn.wrappedValue) { _, newValue in
                    appState.saveData()
                    if title == "登录时启动" {
                        updateLaunchAtLogin(enabled: newValue)
                    }
                }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("[Settings] Failed to update launchAtLogin: \(error)")
            }
        }
    }
}
