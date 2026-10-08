#if canImport(MetricKit)
    import Foundation
    import MetricKit

    /// Receives MetricKit's crash, hang and performance payloads (delivered by iOS, at most daily) and writes them to
    /// the rotating log, so "Export logs" carries them. Nothing leaves the device unless the user shares the export.
    public final class MetricsSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
        // @unchecked: `log` is immutable and itself Sendable; MetricKit calls on a background queue.
        private let log: RotatingLog

        public init(log: RotatingLog) {
            self.log = log
            super.init()
        }

        public func start() {
            MXMetricManager.shared.add(self)
        }

        public func stop() {
            MXMetricManager.shared.remove(self)
        }

        public func didReceive(_ payloads: [MXMetricPayload]) {
            for payload in payloads {
                log.write("MetricKit metrics: \(String(decoding: payload.jsonRepresentation(), as: UTF8.self))")
            }
        }

        public func didReceive(_ payloads: [MXDiagnosticPayload]) {
            for payload in payloads {
                log.write("MetricKit diagnostics: \(String(decoding: payload.jsonRepresentation(), as: UTF8.self))")
            }
        }
    }
#endif
