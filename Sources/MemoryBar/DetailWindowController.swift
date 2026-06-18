import AppKit
import SwiftUI

final class DetailWindowController: NSObject, NSWindowDelegate {
    private let monitor: MemoryMonitor
    private var window: NSWindow?

    init(monitor: MemoryMonitor) {
        self.monitor = monitor
        super.init()
    }

    func show() {
        if window == nil {
            let view = DetailWindowView(monitor: monitor)
            let hostingController = NSHostingController(rootView: view)
            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = "内存管理工具"
            newWindow.setContentSize(NSSize(width: 980, height: 680))
            newWindow.minSize = NSSize(width: 820, height: 560)
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
