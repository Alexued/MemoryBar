import AppKit
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var monitor: MemoryMonitor
    let openDetails: () -> Void
    let quit: () -> Void

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
                    MemoryMiniMetric(title: "活跃", value: monitor.snapshot.activeBytes)
                    MemoryMiniMetric(title: "系统", value: monitor.snapshot.wiredBytes)
                    MemoryMiniMetric(title: "压缩", value: monitor.snapshot.compressedBytes)
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
        .frame(width: 380)
    }
}

struct DetailWindowView: View {
    @ObservedObject var monitor: MemoryMonitor
    @State private var searchText = ""

    private var filteredProcesses: [MemoryProcess] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return monitor.processes
        }

        return monitor.processes.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || String($0.pid).contains(searchText)
                || $0.command.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(snapshot: monitor.snapshot, lastUpdated: monitor.lastUpdated) {
                monitor.refresh()
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜索进程名称、PID 或路径", text: $searchText)
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

            ProcessTable(processes: filteredProcesses)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DetailHeader: View {
    let snapshot: MemorySnapshot
    let lastUpdated: Date
    let refresh: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("内存管理工具")
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
                MemoryStatCard(title: "活跃内存", value: snapshot.activeBytes, systemImage: "bolt.fill")
                MemoryStatCard(title: "系统占用", value: snapshot.wiredBytes, systemImage: "lock.fill")
                MemoryStatCard(title: "压缩内存", value: snapshot.compressedBytes, systemImage: "archivebox.fill")
                MemoryStatCard(title: "缓存内存", value: snapshot.cachedBytes, systemImage: "tray.full.fill")
                MemoryStatCard(title: "空闲内存", value: snapshot.freeBytes, systemImage: "circle.dotted")
            }
        }
        .padding(20)
    }
}

private struct MemoryMiniMetric: View {
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

private struct MemoryStatCard: View {
    let title: String
    let value: UInt64
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                Spacer()
            }

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
