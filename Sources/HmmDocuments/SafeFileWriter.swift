import Foundation

/// Crash-safe file writes: the data goes to a temporary file in the same folder, then atomically replaces the old
/// file. The previous good version is kept as `<name>.bak`, so a damaged file can always be recovered.
public enum SafeFileWriter {
    /// Writes `data` to `url` atomically. With `keepBackup`, the current file is copied to `<name>.bak` first, but
    /// only when `isValid` accepts it: a damaged file never overwrites a good backup.
    public static func write(
        _ data: Data, to url: URL, keepBackup: Bool = true, isValid: (Data) -> Bool = SafeFileWriter.isJSON
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if keepBackup, fileManager.fileExists(atPath: url.path),
           let current = try? Data(contentsOf: url), !current.isEmpty, isValid(current) {
            try? current.write(to: backupURL(for: url), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }

    public static func backupURL(for url: URL) -> URL {
        url.appendingPathExtension("bak")
    }

    /// Reads a file, falling back to its backup when the file is missing or `validate` rejects it.
    /// Returns the data and whether the backup was used.
    public static func read(_ url: URL, validate: (Data) throws -> Void) throws -> (data: Data, recoveredFromBackup: Bool) {
        var firstError: Error?
        if let data = try? Data(contentsOf: url) {
            do {
                try validate(data)
                return (data, false)
            } catch {
                firstError = error
            }
        }
        if let data = try? Data(contentsOf: backupURL(for: url)) {
            try validate(data)
            return (data, true)
        }
        throw firstError ?? CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
    }

    /// Whether `data` parses as JSON (the default validity check for backups).
    public static func isJSON(_ data: Data) -> Bool {
        (try? HmmJSON.decode(JSONValue.self, from: data)) != nil
    }
}
