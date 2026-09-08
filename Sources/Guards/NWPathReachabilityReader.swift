import Foundation
import Network
import AwakeCore

/// `NetworkReachabilityReading` sobre `NWPathMonitor`.
///
/// Reporta si hay **camino** a la red, no si internet responde. Un WiFi de hotel
/// con portal cautivo cuenta como online. Distinguirlo pediria pegarle a un
/// servidor, y eso es trafico de red: el proyecto no hace ninguno.
public final class NWPathReachabilityReader: NetworkReachabilityReading, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.local.iamawake.network")
    private let lock = NSLock()
    private var started = false
    private var lastKnownOnline = true

    public init() {}

    public var isOnline: Bool {
        lock.lock()
        let started = self.started
        let cached = lastKnownOnline
        lock.unlock()
        // Antes de arrancar, `monitor.currentPath` todavia no vale nada.
        return started ? monitor.currentPath.status == .satisfied : cached
    }

    public func startMonitoring(onChange: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            self?.remember(online)
            onChange(online)
        }
        monitor.start(queue: queue)
    }

    public func stopMonitoring() {
        lock.lock()
        guard started else { lock.unlock(); return }
        started = false
        lock.unlock()
        monitor.cancel()
    }

    private func remember(_ online: Bool) {
        lock.lock()
        lastKnownOnline = online
        lock.unlock()
    }
}
