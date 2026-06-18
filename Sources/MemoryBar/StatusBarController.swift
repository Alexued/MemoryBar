import AppKit
import Combine
import SwiftUI

final class StatusBarController: NSObject, NSPopoverDelegate {
    private let monitor: MemoryMonitor
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    init(monitor: MemoryMonitor, openDetails: @escaping () -> Void) {
        self.monitor = monitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "内存")
            button.imagePosition = .imageLeading
            button.title = "内存 --%"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 640)
        popover.contentViewController = NSHostingController(
            rootView: StatusPopoverView(
                monitor: monitor,
                openDetails: { [weak self] in
                    self?.popover.performClose(nil)
                    openDetails()
                },
                quit: {
                    NSApp.terminate(nil)
                }
            )
        )

        cancellable = monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.statusItem.button?.title = "内存 \(Formatters.percent(snapshot.usedPercent))"
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            monitor.refresh()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            installDismissMonitors()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        removeDismissMonitors()
    }

    private func installDismissMonitors() {
        removeDismissMonitors()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.popover.performClose(nil)
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, self.popover.isShown else {
                return event
            }

            let popoverWindow = self.popover.contentViewController?.view.window
            let statusWindow = self.statusItem.button?.window
            if event.window != popoverWindow && event.window != statusWindow {
                self.popover.performClose(nil)
            }

            return event
        }
    }

    private func removeDismissMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }

        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }
}
