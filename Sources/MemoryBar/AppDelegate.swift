import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = SystemMonitor()
    private var statusBarController: StatusBarController?
    private var detailWindowController: DetailWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        detailWindowController = DetailWindowController(monitor: monitor)
        statusBarController = StatusBarController(monitor: monitor) { [weak self] in
            self?.detailWindowController?.show()
        }

        monitor.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
