#if canImport(Network)
    import Foundation
    import Network
    import os

    /// The bridge on the network: HTTP on `httpPort` advertised over Bonjour as `_hmm._tcp` (TXT `app=<app>`), and a
    /// WebSocket event stream on `eventsPort` whose first message must be a paired token. Local network only; there
    /// is no internet mode. Parsing, pairing and routing are the pure `HTTPParser` / `BridgeRouter`.
    @MainActor
    public final class BridgeServer {
        public static let serviceType = "_hmm._tcp"

        public let httpPort: NWEndpoint.Port
        public let eventsPort: NWEndpoint.Port
        private let router: BridgeRouter
        private let serviceName: String
        private let app: String
        private var listener: NWListener?
        private var eventsListener: NWListener?
        private var eventClients: [ObjectIdentifier: NWConnection] = [:]
        private let logger: Logger
        public var onStatus: ((String) -> Void)?

        public init(router: BridgeRouter, app: String, serviceName: String, httpPort: UInt16 = 7717, eventsPort: UInt16 = 7718,
                    logSubsystem: String) {
            self.router = router
            self.app = app
            self.serviceName = serviceName
            self.httpPort = NWEndpoint.Port(rawValue: httpPort) ?? 7717
            self.eventsPort = NWEndpoint.Port(rawValue: eventsPort) ?? 7718
            logger = Logger(subsystem: logSubsystem, category: "bridge")
        }

        public var isRunning: Bool { listener != nil }

        /// Both listeners are still accepting (iOS may cancel them while the app is in the background).
        public var isHealthy: Bool {
            guard let listener, let eventsListener else { return false }
            return listener.state == .ready && eventsListener.state == .ready
        }

        public func start() throws {
            guard listener == nil else { return }
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.includePeerToPeer = false
            let listener = try NWListener(using: parameters, on: httpPort)
            listener.service = NWListener.Service(name: serviceName, type: Self.serviceType, domain: nil,
                                                  txtRecord: NWTXTRecord(["app": app, "v": "2"]))
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.serve(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    if case let .failed(error) = state {
                        self?.logger.error("Bridge listener failed: \(error.localizedDescription)")
                        self?.onStatus?("Bridge stopped: \(error.localizedDescription)")
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener

            let events = NWParameters.tcp
            let websocket = NWProtocolWebSocket.Options()
            websocket.autoReplyPing = true
            events.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
            let eventsListener = try NWListener(using: events, on: eventsPort)
            eventsListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.acceptEvents(connection) }
            }
            eventsListener.start(queue: .main)
            self.eventsListener = eventsListener
        }

        public func stop() {
            listener?.cancel()
            listener = nil
            eventsListener?.cancel()
            eventsListener = nil
            for client in eventClients.values {
                client.cancel()
            }
            eventClients.removeAll()
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
                        let response = await self.router.handle(request, from: Self.address(of: connection))
                        self.send(response, on: connection)
                    }
                }
            }
        }

        private func send(_ response: HTTPResponse, on connection: NWConnection) {
            connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
        }

        public static func address(of connection: NWConnection) -> String {
            guard case let .hostPort(host, _) = connection.endpoint else { return "" }
            switch host {
            case let .ipv4(address): return "\(address)"
            case let .ipv6(address): return "\(address)"
            case let .name(name, _): return name
            @unknown default: return ""
            }
        }

        // MARK: Events (WebSocket)

        private func acceptEvents(_ connection: NWConnection) {
            guard NetworkPolicy.isLocal(Self.address(of: connection)) else {
                connection.cancel()
                return
            }
            connection.start(queue: .main)
            // The first message must be a paired token; anything else closes the connection.
            connection.receiveMessage { [weak self] data, _, _, _ in
                Task { @MainActor in
                    guard let self else { return }
                    let token = data.flatMap { String(bytes: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if self.router.authority.authorize(token: token) != nil {
                        self.eventClients[ObjectIdentifier(connection)] = connection
                    } else {
                        connection.cancel()
                    }
                }
            }
        }

        /// Pushes an event (`{"type": "proposal", …}`) to every paired listener.
        public func broadcast(_ event: some Encodable) {
            guard !eventClients.isEmpty, let data = try? JSONEncoder().encode(event) else { return }
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "event", metadata: [metadata])
            for (key, client) in eventClients {
                if case .cancelled = client.state {
                    eventClients[key] = nil
                    continue
                }
                client.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
            }
        }

        /// This device's address on the local network (what to type on a laptop without Bonjour).
        public static func localAddress() -> String? {
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
                    let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    if NetworkPolicy.isLocal(text), !text.hasPrefix("127.") { result = result ?? text }
                }
            }
            return result
        }
    }
#endif
