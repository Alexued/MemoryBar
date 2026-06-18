import AppKit
import SwiftUI

final class DetailWindowController: NSObject, NSWindowDelegate {
    private let monitor: SystemMonitor
    private var window: NSWindow?

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        super.init()
    }

    func show() {
        if window == nil {
            let view = DetailWindowView(monitor: monitor)
            let hostingController = NSHostingController(rootView: view)
            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = "系统资源管理工具"
            newWindow.setContentSize(NSSize(width: 1080, height: 720))
            newWindow.minSize = NSSize(width: 900, height: 600)
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            newWindow.delegate = self
            window = newWindow
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
