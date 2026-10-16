import Cocoa
import SwiftUI

public struct WindowAccessor: NSViewRepresentable {
    private let onWindow: (NSWindow) -> Void

    public init(onWindow: @escaping (NSWindow) -> Void) {
        self.onWindow = onWindow
    }

    public func makeNSView(context: Context) -> NSView {
        let view = WindowAccessorView()
        view.onWindow = onWindow
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowAccessorView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    private var hasConfigured: Bool = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = self.window, !hasConfigured else { return }
        hasConfigured = true
        onWindow?(window)
    }
}
