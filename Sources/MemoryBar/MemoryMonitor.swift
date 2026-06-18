import AppKit
import Combine
import Darwin
import Foundation
import UniformTypeIdentifiers

struct MemorySnapshot {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let activeBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64
    let freeBytes: UInt64

    var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(usedBytes) / Double(totalBytes))
    }

    var usedPercent: Double {
        usedRatio * 100
    }
}

struct MemoryProcess: Identifiable {
    let id: Int32
    let rank: Int
    let pid: Int32
    let name: String
    let rssBytes: UInt64
    let memoryPercent: Double
    let cpuPercent: Double
    let command: String
    let icon: NSImage
}

final class MemoryMonitor: ObservableObject {
    @Published private(set) var snapshot = MemorySnapshot(
        totalBytes: 0,
        usedBytes: 0,
        activeBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        cachedBytes: 0,
        freeBytes: 0
    )
    @Published private(set) var processes: [MemoryProcess] = []
    @Published private(set) var lastUpdated = Date()

    private var timer: Timer?
    private let queue = DispatchQueue(label: "MemoryBar.MemoryMonitor", qos: .utility)

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let snapshot = Self.readMemorySnapshot()
            let processes = Self.readProcesses()
            let now = Date()

            DispatchQueue.main.async {
                self.snapshot = snapshot
                self.processes = processes
                self.lastUpdated = now
            }
        }
    }

    private static func readMemorySnapshot() -> MemorySnapshot {
        let total = totalMemoryBytes()
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemorySnapshot(
                totalBytes: total,
                usedBytes: 0,
                activeBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0,
                cachedBytes: 0,
                freeBytes: 0
            )
        }

        let page = UInt64(pageSize)
        let active = UInt64(stats.active_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let cached = (UInt64(stats.inactive_count) + UInt64(stats.speculative_count)) * page
        let free = UInt64(stats.free_count) * page
        let used = min(total, active + wired + compressed)

        return MemorySnapshot(
            totalBytes: total,
            usedBytes: used,
            activeBytes: active,
            wiredBytes: wired,
            compressedBytes: compressed,
            cachedBytes: cached,
            freeBytes: free
        )
    }

    private static func totalMemoryBytes() -> UInt64 {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &value, &size, nil, 0)
        return value
    }

    private static func readProcesses() -> [MemoryProcess] {
        let output = runPS()
        let appsByPID = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }
        )

        let entries = output
            .split(separator: "\n")
            .compactMap { parseProcessLine(String($0), appsByPID: appsByPID) }
            .sorted { $0.rssBytes > $1.rssBytes }

        return entries.enumerated().map { index, entry in
            MemoryProcess(
                id: entry.pid,
                rank: index + 1,
                pid: entry.pid,
                name: entry.name,
                rssBytes: entry.rssBytes,
                memoryPercent: entry.memoryPercent,
                cpuPercent: entry.cpuPercent,
                command: entry.command,
                icon: entry.icon
            )
        }
    }

    private struct ParsedProcess {
        let pid: Int32
        let name: String
        let rssBytes: UInt64
        let memoryPercent: Double
        let cpuPercent: Double
        let command: String
        let icon: NSImage
    }

    private static func parseProcessLine(
        _ line: String,
        appsByPID: [pid_t: NSRunningApplication]
    ) -> ParsedProcess? {
        let fields = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)

        guard fields.count == 6,
              let pid = Int32(fields[0]),
              let rssKB = UInt64(fields[1]),
              let cpu = Double(fields[2]),
              let memory = Double(fields[3])
        else {
            return nil
        }

        let ucomm = String(fields[4])
        let command = String(fields[5])
        let app = appsByPID[pid]
        let name = app?.localizedName ?? displayName(ucomm: ucomm, command: command)
        let icon = icon(for: pid, app: app, command: command)

        return ParsedProcess(
            pid: pid,
            name: name,
            rssBytes: rssKB * 1024,
            memoryPercent: memory,
            cpuPercent: cpu,
            command: command,
            icon: icon
        )
    }

    private static func displayName(ucomm: String, command: String) -> String {
        if !ucomm.isEmpty {
            return ucomm
        }

        let executable = command.split(separator: " ").first.map(String.init) ?? command
        let name = (executable as NSString).lastPathComponent
        return name.isEmpty ? command : name
    }

    private static func icon(for pid: pid_t, app: NSRunningApplication?, command: String) -> NSImage {
        if let icon = app?.icon {
            return icon
        }

        if let executable = command.split(separator: " ").first.map(String.init),
           executable.hasPrefix("/") {
            let fileIcon = NSWorkspace.shared.icon(forFile: executable)
            fileIcon.size = NSSize(width: 24, height: 24)
            return fileIcon
        }

        if let symbol = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "进程图标") {
            symbol.size = NSSize(width: 24, height: 24)
            return symbol
        }

        return NSWorkspace.shared.icon(for: .unixExecutable)
    }

    private static func runPS() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,rss=,pcpu=,pmem=,ucomm=,command="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return ""
        }

        return String(data: data, encoding: .utf8) ?? ""
    }
}
