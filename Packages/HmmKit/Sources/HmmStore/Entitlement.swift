import Foundation

/// Whether this copy of a paid-upfront app was bought through the App Store. The hmm. apps never lock features on
/// it (there are no in-app purchases at 2.0); About shows it, and support can ask for it.
public enum PurchaseStatus: Equatable, Sendable {
    /// App Store copy with a verified app transaction.
    case purchased(originalVersion: String)
    /// TestFlight, sideloaded or development builds: nothing to verify.
    case notFromAppStore
    /// The transaction exists but its signature didn't verify.
    case unverified(String)

    public var summary: String {
        switch self {
        case let .purchased(version): "Purchased (first version \(version))"
        case .notFromAppStore: "Not an App Store copy"
        case let .unverified(reason): "Couldn't verify the purchase: \(reason)"
        }
    }
}

#if canImport(StoreKit)
    import StoreKit

    /// StoreKit 2 app-transaction check (no receipt parsing, no server).
    public enum PurchaseVerifier {
        public static func status() async -> PurchaseStatus {
            do {
                switch try await AppTransaction.shared {
                case let .verified(transaction):
                    if transaction.environment == .xcode || transaction.environment == .sandbox {
                        return .notFromAppStore
                    }
                    return .purchased(originalVersion: transaction.originalAppVersion)
                case let .unverified(_, error):
                    return .unverified(error.localizedDescription)
                }
            } catch {
                return .notFromAppStore
            }
        }
    }
#endif
