import AppKit
import SwiftUI

enum ResourcePane: String, CaseIterable, Identifiable {
    case memory = "内存"
    case disk = "磁盘"

    var id: String { rawValue }
}

private let paneAnimation = Animation.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.36)

private func switchPane(_ selectedPane: Binding<ResourcePane>, to pane: ResourcePane) {
    guard selectedPane.wrappedValue != pane else {
        return
    }

    withAnimation(paneAnimation) {
        selectedPane.wrappedValue = pane
    }
}

private extension View {
    func resourceSwipe(selectedPane: Binding<ResourcePane>) -> some View {
        modifier(ResourceSwipeModifier(selectedPane: selectedPane))
    }
}

private struct ResourceSwipeModifier: ViewModifier {
    @Binding var selectedPane: ResourcePane

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 28)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else {
                            return
                        }

                        if value.translation.width < 0 {
                            switchPane($selectedPane, to: .disk)
                        } else {
                            switchPane($selectedPane, to: .memory)
                        }
                    }
            )
            .background(
                TrackpadSwipeMonitor { direction in
                    switch direction {
                    case .left:
                        switchPane($selectedPane, to: .disk)
                    case .right:
                        switchPane($selectedPane, to: .memory)
                    }
                }
            )
    }
}

private enum TrackpadSwipeDirection {
    case left
    case right
}

private struct TrackpadSwipeMonitor: NSViewRepresentable {
    let onSwipe: (TrackpadSwipeDirection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipe: onSwipe)
    }

    func makeNSView(context: Context) -> SwipeMonitorView {
        let view = SwipeMonitorView()
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: SwipeMonitorView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.onSwipe = onSwipe
    }

    static func dismantleNSView(_ nsView: SwipeMonitorView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        weak var view: SwipeMonitorView?
        var onSwipe: (TrackpadSwipeDirection) -> Void
        private var monitor: Any?
        private var accumulatedX: CGFloat = 0
        private var accumulatedY: CGFloat = 0
        private var lastSwipeDate = Date.distantPast

        init(onSwipe: @escaping (TrackpadSwipeDirection) -> Void) {
            self.onSwipe = onSwipe
        }

        func install() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let view,
                  let window = view.window,
                  event.window === window
            else {
                reset()
                return event
            }

            let location = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(location) else {
                reset()
                return event
            }

            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY

            guard abs(deltaX) > abs(deltaY) * 1.35, abs(deltaX) > 1.5 else {
                if abs(deltaY) > abs(deltaX) {
                    reset()
                }
                return event
            }

            accumulatedX += deltaX
            accumulatedY += deltaY

            let now = Date()
            guard abs(accumulatedX) > 28,
                  abs(accumulatedX) > abs(accumulatedY) * 1.65,
                  now.timeIntervalSince(lastSwipeDate) > 0.4
            else {
                return event
            }

            lastSwipeDate = now
            let direction: TrackpadSwipeDirection = accumulatedX > 0 ? .left : .right
            reset()
            onSwipe(direction)
            return nil
        }

        private func reset() {
            accumulatedX = 0
            accumulatedY = 0
        }
    }
}

private final class SwipeMonitorView: NSView {}

struct StatusPopoverView: View {
    @ObservedObject var monitor: SystemMonitor
    let openDetails: () -> Void
    let quit: () -> Void
    @State private var selectedPane: ResourcePane = .memory

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("资源类型", selection: $selectedPane) {
                ForEach(ResourcePane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)

            ZStack {
                if selectedPane == .memory {
                    MemoryPopoverContent(monitor: monitor)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    DiskPopoverContent(monitor: monitor)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .animation(paneAnimation, value: selectedPane)
            .clipped()

            Divider()

            HStack(spacing: 10) {
                Button {
                    monitor.refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }

                Button {
                    openDetails()
                } label: {
                    Label("进入应用查看", systemImage: "macwindow")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button {
                    quit()
                } label: {
                    Label("退出", systemImage: "power")
                }
            }

            Text("更新于 \(Formatters.time(monitor.lastUpdated))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 420)
        .resourceSwipe(selectedPane: $selectedPane)
    }
}

struct DetailWindowView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var searchText = ""
    @State private var selectedPane: ResourcePane = .memory

    private var filteredProcesses: [MemoryProcess] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return monitor.processes }

        return monitor.processes.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || String($0.pid).contains(keyword)
                || $0.command.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var filteredDiskApps: [DiskAppUsage] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return monitor.diskApps }

        return monitor.diskApps.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.path.localizedCaseInsensitiveContains(keyword)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(keyword)
                || $0.version.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("资源类型", selection: $selectedPane) {
                ForEach(ResourcePane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            ZStack {
                if selectedPane == .memory {
                    MemoryDetailHeader(snapshot: monitor.snapshot, lastUpdated: monitor.lastUpdated) {
                        monitor.refresh()
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                } else {
                    DiskDetailHeader(snapshot: monitor.diskSnapshot, appCount: monitor.diskApps.count, lastUpdated: monitor.lastUpdated) {
                        monitor.refresh()
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                }
            }
            .animation(paneAnimation, value: selectedPane)
            .clipped()

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(selectedPane == .memory ? "搜索进程名称、PID 或路径" : "搜索 App 名称、Bundle ID、版本或路径", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if selectedPane == .memory {
                ProcessTable(processes: filteredProcesses)
            } else {
                DiskAppTable(apps: filteredDiskApps)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .resourceSwipe(selectedPane: $selectedPane)
    }
}

private struct MemoryPopoverContent: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前内存占用")
                            .font(.headline)
                        Text("\(Formatters.memory(monitor.snapshot.usedBytes)) / \(Formatters.memory(monitor.snapshot.totalBytes))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(Formatters.percent(monitor.snapshot.usedPercent))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                ProgressView(value: monitor.snapshot.usedRatio)
                    .progressViewStyle(.linear)

                HStack(spacing: 8) {
                    MetricCard(title: "活跃", value: monitor.snapshot.activeBytes)
                    MetricCard(title: "系统", value: monitor.snapshot.wiredBytes)
                    MetricCard(title: "压缩", value: monitor.snapshot.compressedBytes)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("内存占用榜")
                        .font(.headline)
                    Spacer()
                    Text("共 \(monitor.processes.count) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(monitor.processes) { process in
                            CompactProcessRow(process: process)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 300)
            }
        }
    }
}

private struct DiskPopoverContent: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前磁盘占用")
                            .font(.headline)
                        Text("\(monitor.diskSnapshot.name) · \(monitor.diskSnapshot.mountPath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Text(Formatters.percent(monitor.diskSnapshot.usedPercent))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                Text("\(Formatters.memory(monitor.diskSnapshot.usedBytes)) / \(Formatters.memory(monitor.diskSnapshot.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ProgressView(value: monitor.diskSnapshot.usedRatio)
                    .progressViewStyle(.linear)

                HStack(spacing: 8) {
                    MetricCard(title: "已用", value: monitor.diskSnapshot.usedBytes)
                    MetricCard(title: "可用", value: monitor.diskSnapshot.availableBytes)
                    MetricCard(title: "总量", value: monitor.diskSnapshot.totalBytes)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("磁盘占用榜")
                        .font(.headline)
                    Spacer()
                    Text("共 \(monitor.diskApps.count) 个 App")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(monitor.diskApps) { app in
                            CompactDiskAppRow(app: app)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 300)
            }
        }
    }
}

private struct MemoryDetailHeader: View {
    let snapshot: MemorySnapshot
    let lastUpdated: Date
    let refresh: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("内存管理")
                        .font(.system(size: 26, weight: .semibold))
                    Text("更新于 \(Formatters.time(lastUpdated))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(Formatters.percent(snapshot.usedPercent))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("\(Formatters.memory(snapshot.usedBytes)) / \(Formatters.memory(snapshot.totalBytes))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button {
                    refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }

            ProgressView(value: snapshot.usedRatio)

            HStack(spacing: 12) {
                StatCard(title: "活跃内存", value: snapshot.activeBytes, systemImage: "bolt.fill")
                StatCard(title: "系统占用", value: snapshot.wiredBytes, systemImage: "lock.fill")
                StatCard(title: "压缩内存", value: snapshot.compressedBytes, systemImage: "archivebox.fill")
                StatCard(title: "缓存内存", value: snapshot.cachedBytes, systemImage: "tray.full.fill")
                StatCard(title: "空闲内存", value: snapshot.freeBytes, systemImage: "circle.dotted")
            }
        }
        .padding(20)
    }
}

private struct DiskDetailHeader: View {
    let snapshot: DiskSnapshot
    let appCount: Int
    let lastUpdated: Date
    let refresh: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("磁盘管理")
                        .font(.system(size: 26, weight: .semibold))
                    Text("启动磁盘：\(snapshot.name) · \(snapshot.mountPath)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("更新于 \(Formatters.time(lastUpdated))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(Formatters.percent(snapshot.usedPercent))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("\(Formatters.memory(snapshot.usedBytes)) / \(Formatters.memory(snapshot.totalBytes))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button {
                    refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }

            ProgressView(value: snapshot.usedRatio)

            HStack(spacing: 12) {
                StatCard(title: "已用空间", value: snapshot.usedBytes, systemImage: "internaldrive.fill")
                StatCard(title: "可用空间", value: snapshot.availableBytes, systemImage: "externaldrive.badge.checkmark")
                StatCard(title: "总容量", value: snapshot.totalBytes, systemImage: "square.stack.3d.up.fill")
                CountStatCard(title: "应用数量", value: appCount, systemImage: "app.badge")
            }
        }
        .padding(20)
    }
}

private struct MetricCard: View {
    let title: String
    let value: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Formatters.memory(value))
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatCard: View {
    let title: String
    let value: UInt64
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Formatters.memory(value))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CountStatCard: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.headline)
                .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CompactProcessRow: View {
    let process: MemoryProcess

    var body: some View {
        HStack(spacing: 10) {
            Text("\(process.rank)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            Image(nsImage: process.icon)
                .resizable()
                .frame(width: 22, height: 22)
                .cornerRadius(5)

            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                    .font(.callout)
                    .lineLimit(1)
                Text("PID \(process.pid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.memory(process.rssBytes))
                    .font(.callout)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(Formatters.percent(process.memoryPercent, digits: 1))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CompactDiskAppRow: View {
    let app: DiskAppUsage

    var body: some View {
        HStack(spacing: 10) {
            Text("\(app.rank)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 22, height: 22)
                .cornerRadius(5)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.callout)
                    .lineLimit(1)
                Text(app.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.memory(app.sizeBytes))
                    .font(.callout)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(Formatters.percent(app.diskPercent, digits: 2))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProcessTable: View {
    let processes: [MemoryProcess]

    var body: some View {
        VStack(spacing: 0) {
            ProcessTableHeader()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(processes) { process in
                        ProcessTableRow(process: process)
                        Divider()
                            .padding(.leading, 20)
                    }
                }
            }
        }
    }
}

private struct ProcessTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("排名")
                .frame(width: 44, alignment: .trailing)
            Text("进程")
                .frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)
            Text("PID")
                .frame(width: 70, alignment: .trailing)
            Text("内存")
                .frame(width: 120, alignment: .trailing)
            Text("占比")
                .frame(width: 70, alignment: .trailing)
            Text("CPU")
                .frame(width: 70, alignment: .trailing)
            Text("可执行路径")
                .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ProcessTableRow: View {
    let process: MemoryProcess

    var body: some View {
        HStack(spacing: 12) {
            Text("\(process.rank)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            HStack(spacing: 10) {
                Image(nsImage: process.icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 3) {
                    Text(process.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text("进程号 \(process.pid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)

            Text("\(process.pid)")
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)

            Text(Formatters.memory(process.rssBytes))
                .monospacedDigit()
                .frame(width: 120, alignment: .trailing)

            Text(Formatters.percent(process.memoryPercent, digits: 1))
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)

            Text(Formatters.percent(process.cpuPercent, digits: 1))
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)

            Text(process.command)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

private struct DiskAppTable: View {
    let apps: [DiskAppUsage]

    var body: some View {
        VStack(spacing: 0) {
            DiskAppTableHeader()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(apps) { app in
                        DiskAppTableRow(app: app)
                        Divider()
                            .padding(.leading, 20)
                    }
                }
            }
        }
    }
}

private struct DiskAppTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("排名")
                .frame(width: 44, alignment: .trailing)
            Text("App")
                .frame(minWidth: 210, maxWidth: .infinity, alignment: .leading)
            Text("占用空间")
                .frame(width: 120, alignment: .trailing)
            Text("占比")
                .frame(width: 70, alignment: .trailing)
            Text("版本")
                .frame(width: 130, alignment: .leading)
            Text("Bundle ID")
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
            Text("路径")
                .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct DiskAppTableRow: View {
    let app: DiskAppUsage

    var body: some View {
        HStack(spacing: 12) {
            Text("\(app.rank)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(app.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(minWidth: 210, maxWidth: .infinity, alignment: .leading)

            Text(Formatters.memory(app.sizeBytes))
                .monospacedDigit()
                .frame(width: 120, alignment: .trailing)

            Text(Formatters.percent(app.diskPercent, digits: 2))
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)

            Text(app.version)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)

            Text(app.bundleIdentifier)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            Text(app.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
