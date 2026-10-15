import SwiftUI

public struct LogsView: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var logManager: LogManager = .shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header: <  日志  gear
            WindowHeaderView(title: "日志", showBackButton: true, showGearButton: true)

            // Filter and Action Bar
            HStack(spacing: 10) {
                // Proxy Filter Picker
                Menu {
                    Button("全部代理") {
                        logManager.selectedProxyFilter = "全部代理"
                    }
                    Divider()
                    ForEach(appState.currentProxies) { proxy in
                        Button(proxy.name) {
                            logManager.selectedProxyFilter = proxy.name
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(logManager.selectedProxyFilter)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()

                // Level Filter Picker
                Menu {
                    ForEach(FRPLogLevel.allCases) { level in
                        Button(level.rawValue) {
                            logManager.selectedLevelFilter = level
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(logManager.selectedLevelFilter.rawValue)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()

                Spacer()

                // Vertical divider before actions
                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 2)

                // Pause / Resume Button
                Button(action: {
                    logManager.isPaused.toggle()
                }) {
                    Image(systemName: logManager.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11.5))
                        .foregroundColor(logManager.isPaused ? .accentColor : .primary.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(logManager.isPaused ? "继续更新" : "暂停更新")

                // Copy Button
                Button(action: {
                    logManager.copyAllLogsToClipboard()
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12.5))
                        .foregroundColor(.primary.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("复制日志")

                // More Options Menu
                Menu {
                    Button("清空日志") {
                        logManager.clear()
                    }
                    Button("在 Finder 中显示日志文件") {
                        NSWorkspace.shared.activateFileViewerSelecting([StorageService.shared.logFilePath])
                    }
                    Divider()
                    Button("复制全部日志") {
                        logManager.copyAllLogsToClipboard()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12.5))
                        .foregroundColor(.primary.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 28)
            .padding(.top, 2)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 28)

            // Log Entries List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(logManager.filteredEntries) { entry in
                            LogRowView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
                .onChange(of: logManager.entries.count) { _ in
                    if logManager.autoScroll, let last = logManager.filteredEntries.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Bottom Bar: [● 实时更新]           [☑ 自动滚动]
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(logManager.isPaused ? Color.secondary : Color(red: 0.20, green: 0.78, blue: 0.35))
                        .frame(width: 8, height: 8)

                    Text(logManager.isPaused ? "已暂停更新" : "实时更新")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }

                Spacer()

                Toggle(isOn: $logManager.autoScroll) {
                    Text("自动滚动")
                        .font(.system(size: 12.5))
                        .foregroundColor(.primary)
                }
                .toggleStyle(.checkbox)
                .tint(Color(red: 0.0, green: 0.48, blue: 1.0))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
