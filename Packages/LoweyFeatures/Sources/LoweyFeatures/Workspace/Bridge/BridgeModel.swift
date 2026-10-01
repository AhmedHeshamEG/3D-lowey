import Foundation
import HmmBridge
import LoweyCore
import Observation
import UIKit

/// The AI & laptop bridge: off until you switch it on; a laptop pairs with a single-use code shown here and gets a
/// token kept in the Keychain; unpaired requests are refused; local network only. AI proposes, you decide: every
/// script waits for your OK unless you allow auto-apply for this session.
@Observable
@MainActor
final class BridgeModel {
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored let authority: PairingAuthority
    @ObservationIgnored private var server: BridgeServer?
    @ObservationIgnored private let keeper = BackgroundKeeper()
    private(set) var isOn = false
    private(set) var status = "Off"
    /// The code a new laptop types (only while pairing; it expires after five minutes and works once).
    private(set) var pairingCode: PairingCode?
    private(set) var clients: [PairedClient] = []
    /// Scripts apply without asking until the app closes (each is still one undo step).
    var autoApplyThisSession = false
    @ObservationIgnored private var pairingTask: Task<Void, Never>?

    static let wantsOnKey = "bridge.on"

    init(app: AppModel) {
        self.app = app
        let store = KeychainClientStore(service: "\(AppIdentity.subsystem).bridge")
        authority = PairingAuthority(store: store)
        clients = authority.clients
    }

    /// The address to type on a laptop without Bonjour.
    var address: String { "\(BridgeServer.localAddress() ?? "this iPad's address"):7717" }

    /// Off unless you switched it on (and the build includes the bridge).
    private var wantsOn: Bool {
        get { FeatureFlags.aiBridge && UserDefaults.standard.bool(forKey: Self.wantsOnKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.wantsOnKey) }
    }

    func setOn(_ on: Bool) {
        wantsOn = on
        if on { start() } else { stop() }
    }

    func restoreIfWanted() {
        if wantsOn { start() }
    }

    /// Back in front: iOS may have torn the listeners down while the app was away.
    func resume() {
        keeper.stop()
        BridgeNotice.clear()
        guard wantsOn else { return }
        if let server, server.isHealthy { return }
        stop()
        start()
    }

    /// The app left the screen: keep answering (sideloaded builds keep running with silent audio).
    func enterBackground() {
        guard isOn else { return }
        if FeatureFlags.backgroundBridge { keeper.start() }
        BridgeNotice.showOn(address: address)
    }

    func start() {
        guard server == nil, FeatureFlags.aiBridge else { return }
        let deviceName = UIDevice.current.name
        let router = BridgeRouter(authority: authority, routes: routes()) {
            BridgeHello(app: "lowey", appVersion: AppIdentity.shortVersion, device: deviceName, pairing: false)
        }
        let server = BridgeServer(router: router, app: "lowey", serviceName: "\(AppIdentity.displayName) on \(UIDevice.current.name)",
                                  logSubsystem: AppIdentity.subsystem)
        server.onStatus = { [weak self] message in self?.status = message }
        do {
            try server.start()
            self.server = server
            isOn = true
            status = clients.isEmpty ? "On. Pair a laptop to let it in." : "On. \(clients.count) paired."
            BridgeNotice.requestPermission()
        } catch {
            status = "Couldn't start: \(error.localizedDescription)"
        }
    }

    func stop() {
        cancelPairing()
        server?.stop()
        server = nil
        isOn = false
        status = "Off"
        keeper.stop()
        BridgeNotice.clear()
    }

    // MARK: Pairing

    /// Shows a fresh single-use code for five minutes; a laptop that redeems it is paired.
    func startPairing() {
        pairingCode = authority.startPairing()
        pairingTask?.cancel()
        pairingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let before = clients.count
                clients = authority.clients
                pairingCode = authority.currentCode()
                if clients.count > before {
                    app.show("A laptop paired with the bridge", kind: .success)
                    pairingCode = nil
                    authority.cancelPairing()
                    return
                }
                if pairingCode == nil { return }
            }
        }
    }

    func cancelPairing() {
        pairingTask?.cancel()
        pairingTask = nil
        authority.cancelPairing()
        pairingCode = nil
    }

    func revoke(_ client: PairedClient) {
        authority.revoke(client.id)
        clients = authority.clients
    }

    func revokeAll() {
        authority.revokeAll()
        clients = authority.clients
    }

    /// Tells listening laptops something changed (they re-read what they need).
    func notify(_ type: String, _ extra: [String: String] = [:]) {
        server?.broadcast(extra.merging(["type": type]) { first, _ in first })
    }
}

/// Build-time switches (Info.plist), so the App Store build can ship without the bridge until 2.1.
enum FeatureFlags {
    /// The AI & laptop bridge (on in sideloaded builds).
    static var aiBridge: Bool { Bundle.main.object(forInfoDictionaryKey: "LoweyAIBridge") as? Bool ?? true }
    /// Keep the bridge answering in the background with silent audio (sideloaded builds only: App Review rejects it).
    static var backgroundBridge: Bool { Bundle.main.object(forInfoDictionaryKey: "LoweyBackgroundBridge") as? Bool ?? true }
}
