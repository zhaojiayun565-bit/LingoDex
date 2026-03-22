import Foundation
import Network

/// Observes network connectivity. Used for offline queue and sync.
final class NetworkMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "lingodex.network")
    private let lock = NSLock()
    private var _isReachable = false

    /// True when network is available (wifi or cellular).
    var isReachable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isReachable
    }

    /// Called when connectivity changes (runs on monitor queue).
    var onReachabilityChanged: (@Sendable (Bool) -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            self?.lock.lock()
            self?._isReachable = reachable
            self?.lock.unlock()
            self?.onReachabilityChanged?(reachable)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
