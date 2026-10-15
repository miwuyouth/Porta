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
        HStack(alignment: .top, spacing: 8) {
            // Timestamp (e.g. 11:38:39) - 保持灰色
            Text(entry.timeString)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .tracking(-0.2)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .frame(width: 58, alignment: .leading)

            // Level (e.g. INFO, WARN) - 正常灰色，WARN 橙色，ERROR 红色
            Text(entry.level.rawValue)
                .font(.system(size: 10.5, weight: isWarning || isError ? .bold : .medium, design: .monospaced))
                .tracking(-0.2)
                .foregroundColor(entry.level.displayColor)
                .frame(width: 40, alignment: .leading)

            // Message - 紧凑等宽字体，深灰正文
            Text(entry.fullDisplayMessage)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .tracking(-0.2)
                .lineSpacing(2)
                .foregroundColor(Color.primary.opacity(0.82))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if isWarning {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.orange.opacity(0.08))
                } else if isError {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red.opacity(0.10))
                } else {
                    Color.clear
                }
            }
        )
    }
}
