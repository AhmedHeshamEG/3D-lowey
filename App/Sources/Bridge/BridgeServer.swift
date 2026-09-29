import Foundation
import LoweyCore
import Network
import os

/// The LAN Bridge's network side: an HTTP listener (port 7717, Bonjour `_lowey._tcp`) and a WebSocket event
/// stream (port 7718). Parsing, auth and routing are LoweyCore's `HTTPParser` / `BridgeRouter`.
@MainActor
final class BridgeServer {
    static let httpPort: NWEndpoint.Port = 7717
    static let eventsPort: NWEndpoint.Port = 7718

    private var listener: NWListener?
    private var eventsListener: NWListener?
    private var eventClients: [NWConnection] = []
    private let router: BridgeRouter
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "bridge")
    var onStatus: ((String) -> Void)?

    init(router: BridgeRouter) {
        self.router = router
    }

    var isRunning: Bool { listener != nil }
    /// Both listeners are still accepting (iOS can cancel them while the app is in the background).
    var isHealthy: Bool {
        guard let listener, let eventsListener else { return false }
        return listener.state == .ready && eventsListener.state == .ready
    }

    func start() throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: Self.httpPort)
        listener.service = NWListener.Service(name: "3D-lowey", type: "_lowey._tcp")
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.serve(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case let .failed(error) = state { self?.onStatus?("Bridge stopped: \(error.localizedDescription)") }
            }
        }
        listener.start(queue: .main)
        self.listener = listener

        let events = NWParameters.tcp
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        events.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        let eventsListener = try NWListener(using: events, on: Self.eventsPort)
        eventsListener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.acceptEvents(connection) }
        }
        eventsListener.start(queue: .main)
        self.eventsListener = eventsListener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        eventsListener?.cancel()
        eventsListener = nil
        for client in eventClients {
            client.cancel()
        }
        eventClients = []
    }

    // MARK: HTTP

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { return }
                var pending = buffer
                if let data { pending.append(data) }
                switch HTTPParser.parse(pending) {
                case .incomplete:
                    if complete || error != nil {
                        connection.cancel()
                    } else {
                        self.read(connection, buffer: pending)
                    }
                case let .invalid(reason):
                    self.send(.error(400, reason), on: connection)
                case let .request(request):
                    let address = Self.address(of: connection)
                    let response = await self.router.handle(request, from: address)
                    self.send(response, on: connection)
                }
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
    }

    static func address(of connection: NWConnection) -> String {
        if case let .hostPort(host, _) = connection.endpoint {
            switch host {
            case let .ipv4(address): return "\(address)"
            case let .ipv6(address): return "\(address)"
            case let .name(name, _): return name
            @unknown default: return ""
            }
        }
        return ""
    }

    // MARK: Events (WebSocket)

    private func acceptEvents(_ connection: NWConnection) {
        guard NetworkPolicy.isLocal(Self.address(of: connection)) else {
            connection.cancel()
            return
        }
        connection.start(queue: .main)
        eventClients.append(connection)
        // The first message must be the token; unpaired clients are dropped.
        connection.receiveMessage { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self else { return }
                let token = data.flatMap { String(bytes: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !self.router.auth.pairedTokens.contains(token) {
                    connection.cancel()
                    self.eventClients.removeAll { $0 === connection }
                }
            }
        }
    }

    /// Pushes an event (`{"type": "scene", …}`) to every connected client.
    func broadcast(_ event: [String: String]) {
        guard !eventClients.isEmpty, let data = try? JSONEncoder().encode(event) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "event", metadata: [metadata])
        for client in eventClients {
            client.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
        }
    }

    /// This iPad's address on the local network (what to type on the laptop).
    static func localAddress() -> String? {
        var result: String?
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let text = String(cString: host)
                if NetworkPolicy.isLocal(text), !text.hasPrefix("127.") { result = result ?? text }
            }
        }
        return result
    }
}
