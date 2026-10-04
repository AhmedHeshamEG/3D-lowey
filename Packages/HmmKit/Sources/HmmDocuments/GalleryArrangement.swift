import Foundation

/// One document on a Home gallery (Maquette's projects, Cutaway's edits).
public struct GalleryItem: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var created: Date
    public var modified: Date

    public init(id: String, name: String, created: Date, modified: Date) {
        self.id = id
        self.name = name
        self.created = created
        self.modified = modified
    }
}

public enum GallerySort: String, Codable, CaseIterable, Sendable {
    /// Most recently changed first (the default, as in Procreate).
    case recent
    case name
    /// Newest first.
    case created

    public var title: String {
        switch self {
        case .recent: "Recent"
        case .name: "Name"
        case .created: "Date created"
        }
    }
}

/// Documents stacked together, like a folder on the gallery.
public struct GalleryStack: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var members: [String]
    public var created: Date

    public init(id: String, name: String, members: [String], created: Date) {
        self.id = id
        self.name = name
        self.members = members
        self.created = created
    }
}

/// What a gallery shows: a document, or a stack with its documents (sorted).
public enum GalleryEntry: Hashable, Sendable, Identifiable {
    case item(GalleryItem)
    case stack(GalleryStack, [GalleryItem])

    public var id: String {
        switch self {
        case let .item(item): "item-\(item.id)"
        case let .stack(stack, _): "stack-\(stack.id)"
        }
    }
}

/// How a person arranged their gallery: stacks and the sort order. It's how the documents are shown, not what they
/// hold, so it lives beside them as `gallery.json` (moved with the folder to iCloud Drive) and never in a document.
public struct GalleryArrangement: Codable, Equatable, Sendable {
    public static let fileName = "gallery.json"
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var stacks: [GalleryStack]
    public var sort: GallerySort

    public init(stacks: [GalleryStack] = [], sort: GallerySort = .recent) {
        schemaVersion = Self.schemaVersion
        self.stacks = stacks
        self.sort = sort
    }

    // MARK: Changing stacks

    /// Stacks documents together (taking them out of any stack they were in) and returns the new stack's id.
    @discardableResult
    public mutating func stack(_ ids: [String], name: String, id: String = UUID().uuidString, now: Date = Date()) -> String {
        remove(ids)
        stacks.append(GalleryStack(id: id, name: name, members: unique(ids), created: now))
        return id
    }

    /// Adds documents to an existing stack (moving them from any other).
    public mutating func add(_ ids: [String], to stackID: String) {
        guard stacks.contains(where: { $0.id == stackID }) else { return }
        remove(ids)
        if let index = stacks.firstIndex(where: { $0.id == stackID }) {
            stacks[index].members.append(contentsOf: unique(ids))
        }
    }

    /// Takes documents out of their stacks (back to the top level); stacks left empty go.
    public mutating func remove(_ ids: [String]) {
        let leaving = Set(ids)
        for index in stacks.indices {
            stacks[index].members.removeAll { leaving.contains($0) }
        }
        stacks.removeAll { $0.members.isEmpty }
    }

    /// Dissolves a stack: its documents go back to the top level.
    public mutating func unstack(_ stackID: String) {
        stacks.removeAll { $0.id == stackID }
    }

    public mutating func rename(_ stackID: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = stacks.firstIndex(where: { $0.id == stackID }) else { return }
        stacks[index].name = trimmed
    }

    /// Forgets documents that no longer exist (deleted, archived, moved away).
    public mutating func prune(keeping existing: Set<String>) {
        for index in stacks.indices {
            stacks[index].members.removeAll { !existing.contains($0) }
        }
        stacks.removeAll { $0.members.isEmpty }
    }

    public func stack(containing id: String) -> GalleryStack? {
        stacks.first { $0.members.contains(id) }
    }

    // MARK: What the gallery shows

    /// At the top level: stacks and the documents in none. Inside a stack: its documents. With a search: every
    /// document whose name matches, wherever it is, and the stacks whose name matches.
    public func entries(_ items: [GalleryItem], in stackID: String? = nil, query: String = "") -> [GalleryEntry] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            let matchingStacks = stacks.filter { stackID == nil && Self.matches($0.name, needle) }
                .map { GalleryEntry.stack($0, sorted($0.members.compactMap { byID[$0] })) }
            let pool = stackID.flatMap { id in stacks.first { $0.id == id } }.map { $0.members.compactMap { byID[$0] } } ?? items
            return sortedStacks(matchingStacks) + sorted(pool.filter { Self.matches($0.name, needle) }).map(GalleryEntry.item)
        }
        if let stackID {
            guard let stack = stacks.first(where: { $0.id == stackID }) else { return [] }
            return sorted(stack.members.compactMap { byID[$0] }).map(GalleryEntry.item)
        }
        let stacked = Set(stacks.flatMap(\.members))
        let stackEntries = stacks.compactMap { stack -> GalleryEntry? in
            let members = sorted(stack.members.compactMap { byID[$0] })
            return members.isEmpty ? nil : .stack(stack, members)
        }
        let loose = sorted(items.filter { !stacked.contains($0.id) }).map(GalleryEntry.item)
        return merged(stacks: stackEntries, items: loose)
    }

    /// Documents in the arrangement's order.
    public func sorted(_ items: [GalleryItem]) -> [GalleryItem] {
        items.sorted { before(SortKey($0.name, $0.created, $0.modified), SortKey($1.name, $1.created, $1.modified)) }
    }

    /// Stacks and loose documents interleaved by the same order (a stack sorts by its newest document).
    private func merged(stacks: [GalleryEntry], items: [GalleryEntry]) -> [GalleryEntry] {
        (stacks + items).sorted { before(key($0), key($1)) }
    }

    private func sortedStacks(_ entries: [GalleryEntry]) -> [GalleryEntry] {
        merged(stacks: entries, items: [])
    }

    private struct SortKey {
        var name: String
        var created: Date
        var modified: Date

        init(_ name: String, _ created: Date, _ modified: Date) {
            self.name = name
            self.created = created
            self.modified = modified
        }
    }

    private func key(_ entry: GalleryEntry) -> SortKey {
        switch entry {
        case let .item(item):
            return SortKey(item.name, item.created, item.modified)
        case let .stack(stack, members):
            return SortKey(stack.name, stack.created, members.map(\.modified).max() ?? stack.created)
        }
    }

    private func before(_ lhs: SortKey, _ rhs: SortKey) -> Bool {
        switch sort {
        case .recent:
            if lhs.modified != rhs.modified { return lhs.modified > rhs.modified }
        case .created:
            if lhs.created != rhs.created { return lhs.created > rhs.created }
        case .name:
            break
        }
        let order = lhs.name.compare(rhs.name, options: [.caseInsensitive, .numeric, .diacriticInsensitive])
        return order == .orderedSame ? lhs.name < rhs.name : order == .orderedAscending
    }

    private func unique(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }

    static func matches(_ name: String, _ query: String) -> Bool {
        name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    // MARK: File

    /// The arrangement saved in `folder` (an empty one when there's none or it can't be read).
    public static func load(from folder: URL) -> GalleryArrangement {
        let url = folder.appendingPathComponent(fileName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let (data, _) = try? SafeFileWriter.read(url, validate: { _ = try decoder.decode(GalleryArrangement.self, from: $0) }),
              let arrangement = try? decoder.decode(GalleryArrangement.self, from: data) else { return GalleryArrangement() }
        return arrangement
    }

    public func save(to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try SafeFileWriter.write(encoder.encode(self), to: folder.appendingPathComponent(Self.fileName))
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, stacks, sort
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.schemaVersion
        stacks = try container.decodeIfPresent([GalleryStack].self, forKey: .stacks) ?? []
        sort = (try? container.decodeIfPresent(GallerySort.self, forKey: .sort)) ?? .recent
    }
}
