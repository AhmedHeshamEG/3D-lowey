import Foundation
#if canImport(os)
    import os
#endif

/// A small rotating text log in the app's caches (the old apps' logs grew forever). `maxBytes` per file, `keep`
/// files; the newest is `<name>.log`, older ones `<name>.1.log`, `<name>.2.log`…
public final class RotatingLog: Sendable {
    public let folder: URL
    public let name: String
    public let maxBytes: Int
    public let keep: Int
    private let queue = DispatchQueue(label: "hmm.rotating-log")

    public init(folder: URL, name: String, maxBytes: Int = 512 * 1024, keep: Int = 3) {
        self.folder = folder
        self.name = name
        self.maxBytes = maxBytes
        self.keep = max(keep, 1)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    public var currentURL: URL { url(0) }

    func url(_ index: Int) -> URL {
        folder.appendingPathComponent(index == 0 ? "\(name).log" : "\(name).\(index).log")
    }

    /// Appends one timestamped line (asynchronously, in order).
    public func write(_ line: String, date: Date = Date()) {
        let stamp = ISO8601DateFormatter().string(from: date)
        let text = "\(stamp) \(line)\n"
        queue.async { [self] in append(text) }
    }

    /// Waits until everything written so far is on disk.
    public func flush() {
        queue.sync {}
    }

    private func append(_ text: String) {
        let url = currentURL
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size + text.utf8.count > maxBytes { rotate() }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }

    private func rotate() {
        let manager = FileManager.default
        try? manager.removeItem(at: url(keep - 1))
        if keep > 1 {
            for index in stride(from: keep - 2, through: 0, by: -1) where manager.fileExists(atPath: url(index).path) {
                try? manager.moveItem(at: url(index), to: url(index + 1))
            }
        } else {
            try? manager.removeItem(at: url(0))
        }
    }

    /// All files, oldest first, as one text (for "Export logs").
    public func contents() -> String {
        flush()
        return (0 ..< keep).reversed().compactMap { try? String(contentsOf: url($0), encoding: .utf8) }.joined()
    }

    /// Writes an export file (device facts + the log) and returns its URL.
    public func export(header: String, to directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let file = directory.appendingPathComponent("\(name)-log-\(Int(Date().timeIntervalSince1970)).txt")
        try (header + "\n\n" + contents()).write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}

#if canImport(os)
    /// `os_signpost` intervals around expensive work (visible in Instruments; cheap when not recording).
    public struct HmmSignposts: Sendable {
        private let signposter: OSSignposter

        public init(subsystem: String, category: String) {
            signposter = OSSignposter(subsystem: subsystem, category: category)
        }

        /// Measures `body` as the interval `name`.
        public func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
            let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
            defer { signposter.endInterval(name, state) }
            return try body()
        }

        public func event(_ name: StaticString) {
            signposter.emitEvent(name)
        }
    }
#endif

#if canImport(Darwin)
    /// The app's memory footprint in megabytes (what iOS counts against it).
    public enum MemoryFootprint {
        public static func megabytes() -> Double {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            guard result == KERN_SUCCESS else { return 0 }
            return Double(info.phys_footprint) / 1_048_576
        }
    }
#endif
