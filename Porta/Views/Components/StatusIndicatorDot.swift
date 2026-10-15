import SwiftUI

public struct StatusIndicatorDot: View {
    public var status: ConnectionStatus
    public var size: CGFloat = 8

    public init(status: ConnectionStatus = .connected, size: CGFloat = 8) {
        self.status = status
        self.size = size
    }

    public var color: Color {
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
