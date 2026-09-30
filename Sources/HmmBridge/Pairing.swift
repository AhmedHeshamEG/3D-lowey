import Foundation
import Synchronization

/// A laptop (or another tool) that paired with this device.
public struct PairedClient: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// What the client called itself ("Hesham's MacBook — hmm-bridge").
    public var name: String
    /// The long-lived secret it sends as `Authorization: Bearer …`. Stored in the Keychain on device.
    public var token: String
    public var created: Date
    public var lastSeen: Date

    public init(id: String, name: String, token: String, created: Date, lastSeen: Date) {
        self.id = id
        self.name = name
        self.token = token
        self.created = created
        self.lastSeen = lastSeen
    }
}

/// The code shown on the device while pairing.
public struct PairingCode: Hashable, Sendable {
    public var digits: String
    public var expires: Date

    public init(digits: String, expires: Date) {
        self.digits = digits
        self.expires = expires
    }
}

public enum PairingError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Nobody opened "Pair a laptop" on the device.
    case notPairing
    case expired
    case wrongCode(attemptsLeft: Int)
    /// Too many wrong codes: the code was thrown away.
    case tooManyAttempts

    public var description: String {
        switch self {
        case .notPairing: "Open Bridge ▸ Pair a laptop on the device first: it shows a new code."
        case .expired: "That code expired. Open Bridge ▸ Pair a laptop again for a new one."
        case let .wrongCode(left): "Wrong code (\(left) tries left). Check the code shown on the device."
        case .tooManyAttempts: "Too many wrong codes, so that code was cancelled. Start pairing again on the device."
        }
    }
}

/// Where paired clients are kept (the Keychain on device, memory in tests).
public protocol PairedClientStore: Sendable {
    func load() -> [PairedClient]
    func save(_ clients: [PairedClient])
}

/// Keeps paired clients in memory only.
public final class InMemoryClientStore: PairedClientStore {
    private let clients: Mutex<[PairedClient]>

    public init(_ clients: [PairedClient] = []) {
        self.clients = Mutex(clients)
    }

    public func load() -> [PairedClient] { clients.withLock { $0 } }
    public func save(_ clients: [PairedClient]) { self.clients.withLock { $0 = clients } }
}

/// Pairing and authorisation for the bridge.
///
/// - Pairing only happens while the user has "Pair a laptop" open on the device: it shows a **random 6-digit code,
///   valid for 5 minutes and for one use**. The client trades it for a long-lived token (32 random bytes).
/// - Five wrong codes throw the code away (no brute force: a new pairing has to be started on the device).
/// - Every other request must carry a known token; unpaired requests are refused.
/// - Tokens are stored through a `PairedClientStore` (the Keychain on device) and can be revoked one by one.
public final class PairingAuthority: Sendable {
    public static let codeLifetime: TimeInterval = 300
    public static let maxAttempts = 5

    private struct State {
        var code: PairingCode?
        var attemptsLeft = PairingAuthority.maxAttempts
        var clients: [PairedClient]
    }

    private let state: Mutex<State>
    private let store: any PairedClientStore
    private let onChange: @Sendable () -> Void

    public init(store: any PairedClientStore, onChange: @escaping @Sendable () -> Void = {}) {
        self.store = store
        self.onChange = onChange
        state = Mutex(State(clients: store.load()))
    }

    /// Six random digits.
    public static func makeCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return String(format: "%06d", Int.random(in: 0 ... 999_999, using: &generator))
    }

    /// 32 random bytes as 64 hex characters.
    public static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0 ..< 32).map { _ in String(format: "%02x", UInt8.random(in: 0 ... 255, using: &generator)) }.joined()
    }

    /// Shows a new code (the user opened "Pair a laptop"). Any previous code stops working.
    @discardableResult
    public func startPairing(now: Date = Date()) -> PairingCode {
        let code = PairingCode(digits: Self.makeCode(), expires: now.addingTimeInterval(Self.codeLifetime))
        state.withLock {
            $0.code = code
            $0.attemptsLeft = Self.maxAttempts
        }
        onChange()
        return code
    }

    /// The user closed the pairing screen.
    public func cancelPairing() {
        state.withLock { $0.code = nil }
        onChange()
    }

    /// The code on screen right now (nil when not pairing or expired).
    public func currentCode(now: Date = Date()) -> PairingCode? {
        state.withLock { state in
            guard let code = state.code, code.expires > now else { return nil }
            return code
        }
    }

    /// Trades the code for a token. The code works once.
    public func redeem(code attempt: String, clientName: String, now: Date = Date()) -> Result<PairedClient, PairingError> {
        let result: Result<PairedClient, PairingError> = state.withLock { state in
            guard let code = state.code else { return .failure(.notPairing) }
            guard code.expires > now else {
                state.code = nil
                return .failure(.expired)
            }
            guard Self.constantTimeEqual(attempt.trimmingCharacters(in: .whitespaces), code.digits) else {
                state.attemptsLeft -= 1
                if state.attemptsLeft <= 0 {
                    state.code = nil
                    return .failure(.tooManyAttempts)
                }
                return .failure(.wrongCode(attemptsLeft: state.attemptsLeft))
            }
            state.code = nil
            let name = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
            let client = PairedClient(id: UUID().uuidString, name: name.isEmpty ? "A laptop" : String(name.prefix(80)),
                                      token: Self.makeToken(), created: now, lastSeen: now)
            state.clients.append(client)
            return .success(client)
        }
        if case .success = result {
            store.save(clients)
        }
        onChange()
        return result
    }

    /// The paired client a token belongs to (nil = refuse the request).
    public func authorize(token: String?, now: Date = Date()) -> PairedClient? {
        guard let token, !token.isEmpty else { return nil }
        return state.withLock { state in
            guard let index = state.clients.firstIndex(where: { Self.constantTimeEqual($0.token, token) }) else { return nil }
            state.clients[index].lastSeen = now
            return state.clients[index]
        }
    }

    public var clients: [PairedClient] {
        state.withLock { $0.clients }
    }

    public func revoke(_ id: String) {
        let remaining = state.withLock { state in
            state.clients.removeAll { $0.id == id }
            return state.clients
        }
        store.save(remaining)
        onChange()
    }

    public func revokeAll() {
        state.withLock { $0.clients.removeAll() }
        store.save([])
        onChange()
    }

    /// Compares without leaking how many leading characters matched.
    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8)
        let y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var difference: UInt8 = 0
        for index in x.indices {
            difference |= x[index] ^ y[index]
        }
        return difference == 0
    }
}
