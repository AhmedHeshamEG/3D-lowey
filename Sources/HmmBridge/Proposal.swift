import Foundation

/// A change an AI client wants to make. Nothing touches the document until the user applies it (or turned on
/// "Auto-apply for this session"); an applied proposal is one undo step.
public struct Proposal: Identifiable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending, applied, declined, expired
    }

    public var id: String
    /// "Build the desk set", "Punch in on ‘Enigma’".
    public var title: String
    /// One human sentence: what will change.
    public var summary: String
    /// A line per change ("+ Lamp on Desk", "Camera 2: push in at 3.2 s").
    public var details: [String]
    /// Which client sent it.
    public var source: String
    public var created: Date
    /// PNG of the result (rendered before anything is applied).
    public var thumbnail: Data?
    public var status: Status

    public init(id: String = UUID().uuidString, title: String, summary: String, details: [String] = [], source: String,
                created: Date = Date(), thumbnail: Data? = nil, status: Status = .pending) {
        self.id = id
        self.title = title
        self.summary = summary
        self.details = details
        self.source = source
        self.created = created
        self.thumbnail = thumbnail
        self.status = status
    }
}

/// Proposals waiting for the user, and what happened to recent ones.
public struct ProposalQueue: Sendable {
    public private(set) var pending: [Proposal] = []
    public private(set) var recent: [Proposal] = []
    /// Apply without asking until the app quits (never saved).
    public var autoApplyThisSession = false
    public var recentLimit = 20

    public init() {}

    public enum Decision: Equatable, Sendable {
        /// Show it and wait for the user.
        case ask
        /// Auto-apply is on: apply at once.
        case apply
    }

    /// Adds a proposal and says whether to ask.
    public mutating func submit(_ proposal: Proposal) -> Decision {
        if autoApplyThisSession {
            var applied = proposal
            applied.status = .applied
            remember(applied)
            return .apply
        }
        pending.append(proposal)
        return .ask
    }

    /// Records the user's answer. Returns the resolved proposal (nil when it wasn't pending).
    @discardableResult
    public mutating func resolve(_ id: String, as status: Proposal.Status) -> Proposal? {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return nil }
        var proposal = pending.remove(at: index)
        proposal.status = status
        remember(proposal)
        return proposal
    }

    /// Proposals older than `age` seconds expire (the client stopped waiting).
    public mutating func expire(olderThan age: TimeInterval, now: Date = Date()) -> [Proposal] {
        let old = pending.filter { now.timeIntervalSince($0.created) > age }
        for proposal in old {
            resolve(proposal.id, as: .expired)
        }
        return old
    }

    private mutating func remember(_ proposal: Proposal) {
        recent.insert(proposal, at: 0)
        if recent.count > recentLimit { recent.removeLast(recent.count - recentLimit) }
    }
}

/// Lets a bridge request wait for the user's answer to its proposal.
public actor ProposalDecisions {
    private var waiters: [String: CheckedContinuation<Proposal.Status, Never>] = [:]
    private var early: [String: Proposal.Status] = [:]

    public init() {}

    /// Waits until `decide` is called for `id`, or `timeout` passes (then `.expired`).
    public func wait(for id: String, timeout: Duration) async -> Proposal.Status {
        if let status = early.removeValue(forKey: id) { return status }
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.decide(id, .expired)
        }
        let status = await withCheckedContinuation { continuation in
            waiters[id] = continuation
        }
        timer.cancel()
        return status
    }

    public func decide(_ id: String, _ status: Proposal.Status) {
        if let waiter = waiters.removeValue(forKey: id) {
            waiter.resume(returning: status)
        } else {
            early[id] = status
        }
    }
}
