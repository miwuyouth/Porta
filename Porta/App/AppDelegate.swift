import Cocoa
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupAboutPanelSwizzling()
        setupStatusItem()

        if let icon = Self.resolveAppIcon() {
            NSApplication.shared.applicationIconImage = icon
        }

        // Find and configure main window
        DispatchQueue.main.async { [weak self] in
            if let window = NSApplication.shared.windows.first {
                self?.configureWindow(window)
                if AppState.shared.settings.hideWindowOnLaunch {
                    window.orderOut(nil)
                }
            }
        }
    }

    public func configureWindow(_ window: NSWindow) {
        self.mainWindow = window
        window.delegate = self

        // Window styling matching the design
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.fullSizeContentView, .resizable])
        window.isMovableByWindowBackground = true

        // Window sizing
        window.minSize = NSSize(width: 500, height: 360)
        window.setContentSize(NSSize(width: 540, height: 380))
        window.center()
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if AppState.shared.settings.keepRunningAfterWindowClose {
            sender.orderOut(nil)
            return false
        }
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return !AppState.shared.settings.keepRunningAfterWindowClose
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return false
    }

    public func showMainWindow() {
        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else if let window = NSApplication.shared.windows.first {
            configureWindow(window)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Porta")
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked() {
        let menu = NSMenu()

        let appState = AppState.shared

        // Status header
        let statusTitle = "Porta - \(appState.currentServer.name) (\(appState.processManager.status.displayText))"
        let statusItemMenu = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItemMenu.isEnabled = false
        menu.addItem(statusItemMenu)
        menu.addItem(NSMenuItem.separator())

        // Proxies quick list
        for proxy in appState.currentProxies {
            let item = NSMenuItem(
                title: "\(proxy.name) (\(proxy.subtitle))",
                action: #selector(toggleProxyFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = proxy.id
            item.state = proxy.isEnabled ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Navigation items
        let openItem = NSMenuItem(title: "打开主窗口", action: #selector(openMainWindowAction), keyEquivalent: "1")
        openItem.target = self
        menu.addItem(openItem)

        let logsItem = NSMenuItem(title: "查看实时日志", action: #selector(openLogsAction), keyEquivalent: "l")
        logsItem.target = self
        menu.addItem(logsItem)

        let settingsItem = NSMenuItem(title: "偏好设置...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "关于 Porta", action: #selector(openAboutAction), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "退出 Porta", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // Reset so clicking triggers menu creation dynamically
    }

    @objc private func toggleProxyFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        if let proxy = AppState.shared.proxies.first(where: { $0.id == id }) {
            AppState.shared.toggleProxy(proxy)
        }
    }

    @objc private func openMainWindowAction() {
        AppState.shared.currentScreen = .main
        showMainWindow()
    }

    @objc private func openLogsAction() {
        AppState.shared.currentScreen = .logs
        showMainWindow()
    }

    @objc private func openSettingsAction() {
        AppState.shared.currentScreen = .settings
        showMainWindow()
    }

    @objc private func openAboutAction() {
        Self.showAboutPanel()
    }

    public static func resolveAppIcon() -> NSImage? {
        let bundle = Bundle(for: AppDelegate.self)
        if let image = bundle.image(forResource: "AppLogo") {
            return image
        }
        if let image = NSImage(named: "AppLogo") {
            return image
        }
        if let image = bundle.image(forResource: "AppIcon") {
            return image
        }
        if let image = NSImage(named: "AppIcon") {
            return image
        }
        if let icnsPath = bundle.path(forResource: "AppIcon", ofType: "icns") {
            return NSImage(contentsOfFile: icnsPath)
        }
        return NSApplication.shared.applicationIconImage
    }

    @objc public static func showAboutPanel() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let icon = resolveAppIcon() {
            options[.applicationIcon] = icon
        }
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func setupAboutPanelSwizzling() {
        _ = AppDelegate.swizzleAboutPanelOnce
    }

    private static let swizzleAboutPanelOnce: Void = {
        let originalSelector = #selector(NSApplication.orderFrontStandardAboutPanel(options:))
        let swizzledSelector = #selector(NSApplication.porta_orderFrontStandardAboutPanel(options:))

        guard let originalMethod = class_getInstanceMethod(NSApplication.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(NSApplication.self, swizzledSelector) else {
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}

extension NSApplication {
    @objc fileprivate func porta_orderFrontStandardAboutPanel(options: [NSApplication.AboutPanelOptionKey: Any] = [:]) {
        var opts = options
        if opts[.applicationIcon] == nil {
            if let icon = AppDelegate.resolveAppIcon() {
                opts[.applicationIcon] = icon
            }
        }
        porta_orderFrontStandardAboutPanel(options: opts)
    }
}
