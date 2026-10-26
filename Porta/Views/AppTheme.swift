import SwiftUI
import AppKit

/// macOS 26 (Tahoe) 起启用 Liquid Glass；更早的系统保持原有的纯色外观
enum PortaGlass {
    static var isAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}

extension NSColor {
    /// 统一的应用背景色：浅色模式下始终为纯白 (#FFFFFF)，深色模式下为暗黑 (#1E1E1E)
    /// macOS 26+ 下为透明，由窗口的毛玻璃材质与 Liquid Glass 提供底色
    public static let appBackground = NSColor(name: "appBackground", dynamicProvider: { appearance in
        if PortaGlass.isAvailable {
            return NSColor.clear
        }
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

extension View {
    /// 控件底板：macOS 26+ 使用 Liquid Glass，旧系统退回描边的 controlBackground
    @ViewBuilder
    func portaGlass<S: Shape>(in shape: S, interactive: Bool = true) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay(shape.stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        }
    }

    /// 输入框：macOS 26+ 为玻璃底板，旧系统沿用 roundedBorder
    @ViewBuilder
    func portaTextField() -> some View {
        if #available(macOS 26, *) {
            self
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
        } else {
            self.textFieldStyle(.roundedBorder)
        }
    }

    /// 侧栏面板：macOS 26+ 为悬浮的大圆角玻璃，旧系统沿用 controlBackground
    @ViewBuilder
    func portaSidebarBackground() -> some View {
        if #available(macOS 26, *) {
            self
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
                .padding(8)
        } else {
            self.background(Color(nsColor: .controlBackgroundColor))
        }
    }

    /// 侧栏选中项：macOS 26+ 为强调色玻璃，旧系统为淡色填充
    @ViewBuilder
    func portaSelectionBackground(_ isSelected: Bool) -> some View {
        if #available(macOS 26, *) {
            if isSelected {
                self.glassEffect(.regular.tint(Color.accentColor.opacity(0.35)).interactive(),
                                 in: RoundedRectangle(cornerRadius: 12))
            } else {
                self
            }
        } else {
            self.background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
    }

    /// 窗口底材：macOS 26+ 使用半透明材质透出桌面，旧系统保持不变
    @ViewBuilder
    func portaWindowBackground() -> some View {
        if #available(macOS 26, *) {
            self.containerBackground(.ultraThinMaterial, for: .window)
        } else {
            self
        }
    }
}
