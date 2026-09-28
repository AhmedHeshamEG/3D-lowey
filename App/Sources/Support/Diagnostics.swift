import Foundation
import LoweyCore
import LoweyRender
import MetricKit
import os
import UIKit

/// Local-only diagnostics: a small rotating log, MetricKit crash/hang reports delivered on the next launch, and an
/// "it quit unexpectedly" marker. Nothing leaves the iPad unless Hesham exports it.
final class Diagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = Diagnostics()

    private let queue = DispatchQueue(label: "com.hesham.lowey.diagnostics")
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "diagnostics")
    let folder: URL
    private var logURL: URL { folder.appendingPathComponent("log.txt") }
    private var runningMarker: URL { folder.appendingPathComponent(".running") }
    /// True when the previous session didn't end cleanly.
    private(set) var previousSessionCrashed = false

    override init() {
        folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Diagnostics")
        super.init()
    }

    func start() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        previousSessionCrashed = FileManager.default.fileExists(atPath: runningMarker.path)
        try? Data().write(to: runningMarker)
        MXMetricManager.shared.add(self)
        NSSetUncaughtExceptionHandler { exception in
            Diagnostics.shared.logNow("UNCAUGHT \(exception.name.rawValue): \(exception.reason ?? "") \(exception.callStackSymbols.prefix(12))")
        }
        log("Launch \(Self.deviceSummary)\(previousSessionCrashed ? " — previous session ended unexpectedly" : "")")
    }

    /// Clean exit (going to the background counts: iPadOS may end the app from there without a crash).
    func markClean() {
        try? FileManager.default.removeItem(at: runningMarker)
    }

    func markRunning() {
        try? Data().write(to: runningMarker)
    }

    func log(_ message: String) {
        queue.async { self.logNow(message) }
    }

    private func logNow(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: logURL)
        }
        // Keep the log small: past 1 MB, keep the newest half.
        if let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? nil, size > 1_000_000,
           let data = try? Data(contentsOf: logURL) {
            try? data.suffix(500_000).write(to: logURL)
        }
    }

    // MARK: MetricKit

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for (index, payload) in payloads.enumerated() {
            let url = folder.appendingPathComponent("diagnostic-\(Int(Date().timeIntervalSince1970))-\(index).json")
            try? payload.jsonRepresentation().write(to: url)
        }
        log("MetricKit delivered \(payloads.count) diagnostic report(s)")
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        log("MetricKit delivered \(payloads.count) metric report(s)")
    }

    // MARK: Export

    static var deviceSummary: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
        return "3D-lowey \(version) (\(build)) · \(model) · iPadOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }

    /// A zip with the log, crash reports and a summary of the setup (no project content).
    @MainActor
    func exportArchive(app: AppModel) -> URL? {
        var files: [(name: String, data: Data)] = []
        let thermal = ["nominal", "fair", "serious", "critical"][min(ProcessInfo.processInfo.thermalState.rawValue, 3)]
        var summary = """
        \(Self.deviceSummary)
        Thermal: \(thermal) · Low power: \(ProcessInfo.processInfo.isLowPowerModeEnabled)
        Memory: \(ProcessInfo.processInfo.physicalMemory / 1_048_576) MB
        Projects: \(app.projects.count) · Library: \(app.library.manifest.assets.count) models, \(app.library.manifest.prefabs.count) prefabs
        Fog shader: \(MaterialFactory.shared.customShaderAvailable ? "yes" : "no")
        """
        if let editor = app.editor {
            summary += "\nOpen scene: \(editor.baseScene.objects.count) objects, \(editor.timeline.tracks.count) tracks, "
                + "\(editor.timeline.audio.count) sounds, \(editor.timeline.words.count) words"
        }
        files.append(("summary.txt", Data(summary.utf8)))
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in contents where !url.lastPathComponent.hasPrefix(".") {
            if let data = try? Data(contentsOf: url) { files.append((url.lastPathComponent, data)) }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("3D-lowey diagnostics.zip")
        do {
            try ZipWriter.storedArchive(files).write(to: url, options: .atomic)
            return url
        } catch {
            logger.error("Diagnostics export failed: \(error.localizedDescription)")
            return nil
        }
    }
}
