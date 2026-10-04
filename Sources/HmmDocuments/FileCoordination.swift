#if canImport(Darwin)
    import Foundation

    /// Coordinated reads and writes, so iCloud never syncs a half-written package and never swaps one under a reader.
    public enum CoordinatedFileAccess {
        /// Runs `body` with read access to `url` (the URL passed in may differ: use it).
        public static func read<T>(_ url: URL, presenter: NSFilePresenter? = nil, _ body: (URL) throws -> T) throws -> T {
            var coordinationError: NSError?
            var result: Result<T, Error>?
            NSFileCoordinator(filePresenter: presenter).coordinate(readingItemAt: url, options: [], error: &coordinationError) { actual in
                result = Result { try body(actual) }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw CocoaError(.fileReadUnknown) }
            return try result.get()
        }

        /// Runs `body` with write access to `url`.
        public static func write<T>(_ url: URL, presenter: NSFilePresenter? = nil, _ body: (URL) throws -> T) throws -> T {
            var coordinationError: NSError?
            var result: Result<T, Error>?
            NSFileCoordinator(filePresenter: presenter).coordinate(writingItemAt: url, options: [], error: &coordinationError) { actual in
                result = Result { try body(actual) }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw CocoaError(.fileWriteUnknown) }
            return try result.get()
        }

        /// Deletes a document the way Files does (other devices see it go).
        public static func delete(_ url: URL) throws {
            try write(url) { actual in try FileManager.default.removeItem(at: actual) }
        }

        /// Starts downloading an iCloud document that isn't on this device yet.
        public static func startDownloading(_ url: URL) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }

        /// Whether an iCloud item is fully on this device (local items always are).
        public static func isDownloaded(_ url: URL) -> Bool {
            guard let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
                  let status = values.ubiquitousItemDownloadingStatus else { return true }
            return status == .current
        }
    }

    /// Watches one open document for changes made elsewhere (another device through iCloud, the Files app) and for
    /// new conflict versions. Register with `start()` while the document is open, `stop()` when it closes.
    public final class DocumentPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
        // @unchecked: the callbacks are set once before `start()` and only read afterwards, on `presentedItemOperationQueue`.
        public private(set) var presentedItemURL: URL?
        public let presentedItemOperationQueue: OperationQueue = {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            queue.name = "hmm.document-presenter"
            return queue
        }()

        /// The package changed on disk (reload it).
        public var onChange: (@Sendable () -> Void)?
        /// Another device saved a conflicting version (show the conflict sheet).
        public var onConflict: (@Sendable () -> Void)?
        /// The package was moved or renamed (keep using the new URL).
        public var onMove: (@Sendable (URL) -> Void)?
        /// The package was deleted elsewhere (close it).
        public var onDelete: (@Sendable () -> Void)?

        public init(url: URL) {
            presentedItemURL = url
            super.init()
        }

        public func start() {
            NSFileCoordinator.addFilePresenter(self)
        }

        public func stop() {
            NSFileCoordinator.removeFilePresenter(self)
        }

        public func presentedItemDidChange() {
            onChange?()
        }

        public func presentedSubitemDidChange(at _: URL) {
            onChange?()
        }

        public func presentedItemDidGain(_ version: NSFileVersion) {
            if version.isConflict { onConflict?() }
        }

        public func presentedItemDidMove(to newURL: URL) {
            presentedItemURL = newURL
            onMove?(newURL)
        }

        public func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable (Error?) -> Void) {
            onDelete?()
            completionHandler(nil)
        }
    }
#endif
