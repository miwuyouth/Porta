import SwiftUI
import AppKit

extension NSColor {
    /// 统一的应用背景色：浅色模式下始终为纯白 (#FFFFFF)，深色模式下为暗黑 (#1E1E1E)
    /// 彻底消除不同 macOS SDK 与 Liquid Glass 系统默认值差异
    public static let appBackground = NSColor(name: "appBackground", dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1.0)
        } else {
            return NSColor.white
        }
    })
}

extension Color {
    /// 统一的应用背景色（SwiftUI 版本）
    public static let appBackground = Color(nsColor: .appBackground)
}
