import Foundation
import HmmDiagnostics
import LoweyCore
import LoweyEngine
import Synchronization
import UIKit

/// Local-only diagnostics: a rotating log, MetricKit crash and hang reports, an "it quit unexpectedly" marker, and the
/// export Hesham shares when something goes wrong. Nothing leaves the iPad unless he exports it.
public final class DiagnosticsCenter: Sendable {
    public static let shared = DiagnosticsCenter()

    public let folder: URL
    public let log: RotatingLog
    private let metrics: MetricsSubscriber
    private let crashedLastTime = Mutex(false)

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        folder = documents.appendingPathComponent("Diagnostics", isDirectory: true)
        log = RotatingLog(folder: folder, name: "lowey")
        metrics = MetricsSubscriber(log: log)
    }

    private var runningMarker: URL { folder.appendingPathComponent(".running") }

    /// True when the previous session didn't end cleanly.
    public var previousSessionCrashed: Bool { crashedLastTime.withLock { $0 } }

    public func start() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let crashed = FileManager.default.fileExists(atPath: runningMarker.path)
        crashedLastTime.withLock { $0 = crashed }
        try? Data().write(to: runningMarker)
        metrics.start()
        NSSetUncaughtExceptionHandler { exception in
            DiagnosticsCenter.shared.log.write("UNCAUGHT \(exception.name.rawValue): \(exception.reason ?? "") \(exception.callStackSymbols.prefix(12))")
            DiagnosticsCenter.shared.log.flush()
        }
        log("Launch \(Self.deviceSummary)\(previousSessionCrashed ? " (previous session ended unexpectedly)" : "")")
    }

    /// Going to the background counts as a clean end: iPadOS may close the app from there without a crash.
    public func markClean() {
        try? FileManager.default.removeItem(at: runningMarker)
        log.flush()
    }

    public func markRunning() {
        try? Data().write(to: runningMarker)
    }

    public func log(_ message: String) {
        log.write(message)
    }

    public static var deviceSummary: String {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
        return "\(AppIdentity.displayName) \(AppIdentity.version) · \(model) · iPadOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }

    public static var deviceModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// A zip with the log, the renderer's capabilities, benchmark reports and a summary of the setup (no project content).
    @MainActor
    public func exportArchive(summary extra: String) -> URL? {
        let thermal = ThermalLevel.current.rawValue
        let gpu = (try? RenderDevice.sharedDevice().capabilities.summary) ?? "no Metal device"
        let summary = """
        \(Self.deviceSummary)
        GPU: \(gpu)
        Thermal: \(thermal) · Low power: \(ProcessInfo.processInfo.isLowPowerModeEnabled)
        Memory: \(ProcessInfo.processInfo.physicalMemory / 1_048_576) MB
        \(extra)
        """
        var files: [(name: String, data: Data)] = [("summary.txt", Data(summary.utf8)), ("lowey.log", Data(log.contents().utf8))]
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url) { files.append((url.lastPathComponent, data)) }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(AppIdentity.displayName) diagnostics.zip")
        do {
            try ZipWriter.storedArchive(files).write(to: url, options: .atomic)
            return url
        } catch {
            log("Diagnostics export failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Benchmark reports live next to the log (and go into the export).
    public var benchmarksFolder: URL { folder }
}
