import SwiftUI

public struct WindowHeaderView: View {
    @ObservedObject var appState: AppState = .shared
    public var title: String
    public var showBackButton: Bool
    public var showGearButton: Bool
    public var onBack: (() -> Void)?

    @State private var isBackHovered: Bool = false
    @State private var isGearHovered: Bool = false

    public init(
        title: String,
        showBackButton: Bool = false,
        showGearButton: Bool = true,
        onBack: (() -> Void)? = nil
    ) {
        self.title = title
        self.showBackButton = showBackButton
        self.showGearButton = showGearButton
        self.onBack = onBack
    }

    public var body: some View {
        ZStack {
            // Center title
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(.primary)

            HStack(alignment: .center, spacing: 0) {
                // Left area: Back button (aligned with 28pt margin)
                if showBackButton {
                    Button(action: {
                        if let onBack = onBack {
                            onBack()
                        } else {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                appState.currentScreen = .main
                            }
                        }
                    }) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(isBackHovered ? .primary : Color.primary.opacity(0.68))
                            .frame(width: 28, height: 28)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                                )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isBackHovered = $0 }
                    .help("返回")
                } else {
                    Spacer()
                        .frame(width: 28)
                }

                Spacer()

                // Right area: Gear button (aligned with 28pt margin)
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
                            .foregroundColor(appState.currentScreen == .settings ? .accentColor : (isGearHovered ? .primary : .secondary))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isGearHovered = $0 }
                    .help("设置")
                } else {
                    Spacer()
                        .frame(width: 28)
                }
            }
            .padding(.horizontal, 28)
        }
        .frame(height: 38)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
