import Foundation

/// Crash-safe file writes: write to a temp file in the same directory, then atomically
/// replace. The previous version is kept as `<name>.bak` so a damaged file can be recovered.
public enum SafeFileWriter {
    public static func write(_ data: Data, to url: URL, keepBackup: Bool = true) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if keepBackup, fileManager.fileExists(atPath: url.path) {
            let backup = backupURL(for: url)
            // Keep the backup only if the current file is readable (never back up garbage over a good backup).
            if let current = try? Data(contentsOf: url), !current.isEmpty,
               (try? LoweyJSON.decode(JSONValue.self, from: current)) != nil {
                try? current.write(to: backup, options: .atomic)
            }
        }
        try data.write(to: url, options: .atomic)
    }

    public static func backupURL(for url: URL) -> URL {
        url.appendingPathExtension("bak")
    }

    /// Reads a file, falling back to its backup when the main file is missing or unreadable
    /// by `validate`. Returns the data and whether the backup was used.
    public static func read(
        _ url: URL, validate: (Data) throws -> Void
    ) throws -> (data: Data, recoveredFromBackup: Bool) {
        var firstError: Error?
        if let data = try? Data(contentsOf: url) {
            do {
                try validate(data)
                return (data, false)
            } catch {
                firstError = error
            }
        }
        let backup = backupURL(for: url)
        if let data = try? Data(contentsOf: backup) {
            try validate(data)
            return (data, true)
        }
        throw firstError ?? CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
    }
}
