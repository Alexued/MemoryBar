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

struct DiskSnapshot {
    static let empty = DiskSnapshot(
        name: "启动磁盘",
        mountPath: "/",
        totalBytes: 0,
        usedBytes: 0,
        availableBytes: 0,
        fileSystem: "未知"
    )

    let name: String
    let mountPath: String
    let totalBytes: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64
    let fileSystem: String

    var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(usedBytes) / Double(totalBytes))
    }

    var usedPercent: Double {
        usedRatio * 100
    }
}

struct DiskAppUsage: Identifiable {
    let id: String
    let rank: Int
    let name: String
    let path: String
    let sizeBytes: UInt64
    let diskPercent: Double
    let bundleIdentifier: String
    let version: String
    let lastModified: Date?
    let icon: NSImage
}

final class SystemMonitor: ObservableObject {
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
    @Published private(set) var diskSnapshot = DiskSnapshot.empty
    @Published private(set) var diskApps: [DiskAppUsage] = []
    @Published private(set) var lastUpdated = Date()

    private var timer: Timer?
    private var cachedDiskApps: [DiskAppUsage] = []
    private let queue = DispatchQueue(label: "MemoryBar.SystemMonitor", qos: .utility)

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh(forceDiskApps: false)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh(forceDiskApps: Bool = true) {
        queue.async { [weak self] in
            guard let self else { return }
            let snapshot = Self.readMemorySnapshot()
            let processes = Self.readProcesses()
            let diskSnapshot = Self.readDiskSnapshot()
            let diskApps: [DiskAppUsage]
            if forceDiskApps || self.cachedDiskApps.isEmpty {
                diskApps = Self.readDiskApps(diskTotalBytes: diskSnapshot.totalBytes)
                self.cachedDiskApps = diskApps
            } else {
                diskApps = self.cachedDiskApps
            }
            let now = Date()

            DispatchQueue.main.async {
                self.snapshot = snapshot
                self.processes = processes
                self.diskSnapshot = diskSnapshot
                self.diskApps = diskApps
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

    private static func readDiskSnapshot() -> DiskSnapshot {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeLocalizedFormatDescriptionKey
        ]

        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: keys),
              let totalCapacity = values.volumeTotalCapacity,
              totalCapacity > 0
        else {
            return .empty
        }

        let total = UInt64(totalCapacity)
        let importantAvailable = values.volumeAvailableCapacityForImportantUsage.flatMap {
            $0 >= 0 ? UInt64($0) : nil
        }
        let standardAvailable = values.volumeAvailableCapacity.flatMap {
            $0 >= 0 ? UInt64($0) : nil
        }
        let available = min(total, importantAvailable ?? standardAvailable ?? 0)
        let used = total > available ? total - available : 0
        let path = "/"
        let name = values.volumeName?.isEmpty == false
            ? values.volumeName ?? "启动磁盘"
            : "启动磁盘"

        return DiskSnapshot(
            name: name,
            mountPath: path,
            totalBytes: total,
            usedBytes: used,
            availableBytes: available,
            fileSystem: values.volumeLocalizedFormatDescription ?? "未知"
        )
    }

    private static func readDiskApps(diskTotalBytes: UInt64) -> [DiskAppUsage] {
        let apps = discoverApplicationURLs()
            .compactMap { parseDiskApp(url: $0, diskTotalBytes: diskTotalBytes) }
            .sorted { $0.sizeBytes > $1.sizeBytes }

        return apps.enumerated().map { index, app in
            DiskAppUsage(
                id: app.id,
                rank: index + 1,
                name: app.name,
                path: app.path,
                sizeBytes: app.sizeBytes,
                diskPercent: app.diskPercent,
                bundleIdentifier: app.bundleIdentifier,
                version: app.version,
                lastModified: app.lastModified,
                icon: app.icon
            )
        }
    }

    private static func discoverApplicationURLs() -> [URL] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true)
        ]

        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        var seen = Set<String>()
        var results: [URL] = []

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame else {
                    continue
                }

                let standardizedPath = url.standardizedFileURL.path
                if seen.insert(standardizedPath).inserted {
                    results.append(url.standardizedFileURL)
                }
                enumerator.skipDescendants()
            }
        }

        return results
    }

    private static func parseDiskApp(url: URL, diskTotalBytes: UInt64) -> DiskAppUsage? {
        let size = allocatedSize(of: url)
        guard size > 0 else {
            return nil
        }

        let bundle = Bundle(url: url)
        let localizedName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let name = localizedName?.isEmpty == false
            ? localizedName ?? url.deletingPathExtension().lastPathComponent
            : url.deletingPathExtension().lastPathComponent
        let bundleIdentifier = bundle?.bundleIdentifier ?? "未知"
        let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "未知"
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 24, height: 24)
        let percent = diskTotalBytes > 0 ? Double(size) / Double(diskTotalBytes) * 100 : 0

        return DiskAppUsage(
            id: url.path,
            rank: 0,
            name: name,
            path: url.path,
            sizeBytes: size,
            diskPercent: percent,
            bundleIdentifier: bundleIdentifier,
            version: version,
            lastModified: values?.contentModificationDate,
            icon: icon
        )
    }

    private static func allocatedSize(of url: URL) -> UInt64 {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]
        var total: UInt64 = 0

        if let values = try? url.resourceValues(forKeys: Set(keys)),
           let directorySize = values.totalFileAllocatedSize ?? values.fileAllocatedSize,
           directorySize > 0 {
            total += UInt64(directorySize)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return total
        }

        for case let itemURL as URL in enumerator {
            guard let values = try? itemURL.resourceValues(forKeys: Set(keys)) else {
                continue
            }

            let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            if size > 0 {
                total += UInt64(size)
            }
        }

        return total
    }
}
