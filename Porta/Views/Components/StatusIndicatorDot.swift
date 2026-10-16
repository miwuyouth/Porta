import SwiftUI

public struct StatusIndicatorDot: View {
    public var status: ConnectionStatus
    public var hasWarning: Bool = false
    public var size: CGFloat = 8

    public init(status: ConnectionStatus = .connected, hasWarning: Bool = false, size: CGFloat = 8) {
        self.status = status
        self.hasWarning = hasWarning
        self.size = size
    }

    public var color: Color {
        if hasWarning {
            return Color(red: 0.95, green: 0.60, blue: 0.08) // Amber
        }
        switch status {
        case .connected:
            return Color(red: 0.20, green: 0.78, blue: 0.35) // macOS green
        case .connecting:
            return Color(red: 0.95, green: 0.60, blue: 0.08) // Amber
        case .disconnected:
            return Color(nsColor: .tertiaryLabelColor)
        case .error:
            return Color.red
        }
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}
