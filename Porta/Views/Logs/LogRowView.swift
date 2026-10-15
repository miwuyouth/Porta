import SwiftUI

public struct LogRowView: View {
    public var entry: FRPLogEntry

    public init(entry: FRPLogEntry) {
        self.entry = entry
    }

    private var isWarning: Bool {
        entry.level == .warn
    }

    private var isError: Bool {
        entry.level == .error
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Timestamp (e.g. 11:38:39)
            Text(entry.timeString)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .frame(width: 65, alignment: .leading)

            // Level (e.g. INFO, WARN)
            Text(entry.level.rawValue)
                .font(.system(size: 11, weight: isWarning || isError ? .bold : .medium, design: .monospaced))
                .foregroundColor(entry.level.displayColor)
                .frame(width: 42, alignment: .leading)

            // Message (supports full multiline wrap & text selection)
            Text(entry.fullDisplayMessage)
                .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if isWarning {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 1.0, green: 0.965, blue: 0.89))
                } else if isError {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red.opacity(0.12))
                } else {
                    Color.clear
                }
            }
        )
    }
}
