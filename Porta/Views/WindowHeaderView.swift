import SwiftUI

public struct WindowHeaderView: View {
    @ObservedObject var appState: AppState = .shared
    public var title: String
    public var showBackButton: Bool
    public var showGearButton: Bool

    public init(
        title: String,
        showBackButton: Bool = false,
        showGearButton: Bool = true
    ) {
        self.title = title
        self.showBackButton = showBackButton
        self.showGearButton = showGearButton
    }

    public var body: some View {
        ZStack {
            // Center title
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(.primary)

            HStack(alignment: .center, spacing: 0) {
                // Left area: spacing for macOS traffic lights (~74pt) + back button
                HStack(spacing: 8) {
                    Spacer()
                        .frame(width: 74)

                    if showBackButton {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                appState.currentScreen = .main
                            }
                        }) {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("返回")
                    } else {
                        Spacer()
                            .frame(width: 20)
                    }
                }

                Spacer()

                // Right area: Gear button
                if showGearButton {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if appState.currentScreen == .settings {
                                appState.currentScreen = .main
                            } else {
                                appState.currentScreen = .settings
                            }
                        }
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundColor(appState.currentScreen == .settings ? .accentColor : .secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("设置")
                } else {
                    Spacer()
                        .frame(width: 24)
                }
            }
            .padding(.trailing, 18)
        }
        .frame(height: 38)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
