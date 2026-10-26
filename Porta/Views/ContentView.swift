import SwiftUI

public struct ContentView: View {
    @ObservedObject var appState: AppState = .shared

    public init() {}

    public var body: some View {
        ZStack {
            switch appState.currentScreen {
            case .main:
                MainView()
                    .transition(.opacity)
            case .logs:
                LogsView()
                    .transition(.opacity)
            case .settings:
                SettingsView()
                    .transition(.opacity)
            }
        }
        .background(
            WindowAccessor { window in
                AppDelegate.shared?.configureWindow(window)
            }
        )
        .portaWindowBackground()
        .frame(
            minWidth: 500,
            idealWidth: 540,
            maxWidth: .infinity,
            minHeight: 360,
            idealHeight: 410,
            maxHeight: .infinity
        )
        .sheet(item: $appState.activeSheet) { sheet in
            switch sheet {
            case .addProxy:
                AddProxySheet()
            case .editProxy(let proxy):
                AddProxySheet(editingProxy: proxy)
            case .serverManager, .addServer, .editServer:
                ServerManagerSheet()
            }
        }
    }
}
