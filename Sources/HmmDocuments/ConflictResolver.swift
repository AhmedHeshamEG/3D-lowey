import Foundation

/// How the user settles a sync conflict (two devices changed the same document while apart).
public enum ConflictChoice: String, Sendable, CaseIterable, Identifiable {
    /// Keep this device's version and save the other one next to it as a copy.
    case keepBoth
    /// Keep this device's version; discard the other one.
    case keepThis
    /// Replace this device's version with the other one.
    case keepOther

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keepBoth: "Keep Both"
        case .keepThis: "Keep This Version"
        case .keepOther: "Keep the Other Version"
        }
    }
}

/// One version of a document in conflict, as shown to the user.
public struct ConflictVersion: Sendable, Hashable, Identifiable {
    public var id: String
    public var deviceName: String
    public var modified: Date

    public init(id: String, deviceName: String, modified: Date) {
        self.id = id
        self.deviceName = deviceName
        self.modified = modified
    }
}

/// Name for the "keep both" copy: "Film (from Hesham's iPhone).lowey".
public enum ConflictNaming {
    public static func copyName(for url: URL, device: String) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let cleanDevice = device.replacingOccurrences(of: "/", with: "-")
        let name = "\(base) (from \(cleanDevice))"
        return ext.isEmpty ? name : "\(name).\(ext)"
    }
}

#if canImport(Darwin)
    /// Reads and settles iCloud conflicts with `NSFileVersion`.
    public enum ConflictResolver {
        /// The other devices' versions of `url` still waiting to be settled.
        public static func conflicts(at url: URL) -> [ConflictVersion] {
            (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).map { version in
                ConflictVersion(id: version.persistentIdentifier.description,
                                deviceName: version.localizedNameOfSavingComputer ?? "another device",
                                modified: version.modificationDate ?? .distantPast)
            }
        }

        public static func hasConflicts(at url: URL) -> Bool {
            !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty
        }

        /// Settles every conflict of `url`. Returns the copy's URL for `.keepBoth`.
        @discardableResult
        public static func resolve(_ url: URL, choice: ConflictChoice) throws -> URL? {
            let others = (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [])
                .sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
            guard let newest = others.first else { return nil }
            var copy: URL?
            switch choice {
            case .keepThis:
                break
            case .keepOther:
                try CoordinatedFileAccess.write(url) { actual in
                    _ = try newest.replaceItem(at: actual, options: [])
                }
            case .keepBoth:
                let name = ConflictNaming.copyName(for: url, device: newest.localizedNameOfSavingComputer ?? "another device")
                let destination = DocumentLocator.uniqueURL(for: name, in: url.deletingLastPathComponent())
                try CoordinatedFileAccess.write(destination) { actual in
                    try FileManager.default.copyItem(at: newest.url, to: actual)
                }
                copy = destination
            }
            for version in others {
                version.isResolved = true
            }
            try NSFileVersion.removeOtherVersionsOfItem(at: url)
            return copy
        }
    }
#endif
