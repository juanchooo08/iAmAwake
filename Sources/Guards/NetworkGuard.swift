import Foundation
import AwakeCore

/// Estado de red tal como lo mira la guarda: no alcanza con "caida", importa
/// hace cuanto.
public enum NetworkStatus: Equatable, Sendable {
    case online
    case offline(for: TimeInterval)
}

/// Desarma cuando la red lleva caida mas que el margen configurado.
///
/// Reglas:
/// 1. `networkGuardEnabled == false` → `.ok` siempre.
/// 2. `.online` → `.ok`.
/// 3. `.offline(for:)` con menos que el margen → `.ok`. Un salto de WiFi o un
///    cambio de red no tiene que costarte la sesion.
/// 4. `.offline(for:)` alcanzado el margen → `.mustDisarm(.networkLost)`.
///
/// La cuenta del margen la lleva un `DelayScheduling`, no un `Timer` propio, para
/// poder testear los cinco minutos sin esperarlos.
public final class NetworkGuard: Guarding, @unchecked Sendable {
    public let identifier: GuardID = .network

    private let reader: NetworkReachabilityReading
    private let clock: ClockProviding
    private let scheduler: DelayScheduling
    private let box: GuardBox<NetworkStatus>
    private let lock = NSLock()
    private var offlineSince: Date?

    public init(
        reader: NetworkReachabilityReading,
        preferences: PreferencesSnapshot,
        clock: ClockProviding = SystemClock(),
        scheduler: DelayScheduling = DispatchDelayScheduler()
    ) {
        self.reader = reader
        self.clock = clock
        self.scheduler = scheduler
        self.offlineSince = reader.isOnline ? nil : clock.now
        self.box = GuardBox(
            value: reader.isOnline ? .online : .offline(for: 0),
            prefs: preferences,
            evaluate: Self.evaluate
        )
    }

    public var currentVerdict: GuardVerdict { box.verdict(for: currentStatus()) }

    public func start(onVerdict: @escaping @Sendable (GuardVerdict) -> Void) {
        guard box.begin(onVerdict: onVerdict) else { return }
        reader.startMonitoring { [weak self] isOnline in
            self?.handle(isOnline: isOnline)
        }
    }

    public func stop() {
        guard box.end() else { return }
        scheduler.cancelPending()
        reader.stopMonitoring()
    }

    public func apply(_ prefs: PreferencesSnapshot) {
        if let (callback, verdict) = box.apply(prefs) {
            callback(verdict)
        }
        // Cambiar el margen con la red ya caida tiene que re-armar la cuenta:
        // bajarlo de 5 min a 1 con 3 min caidos debe desarmar ya.
        rescheduleIfOffline()
    }

    // MARK: - Privado

    private func handle(isOnline: Bool) {
        setOfflineSince(isOnline ? nil : clock.now)
        emitNow()

        if isOnline {
            scheduler.cancelPending()
        } else {
            rescheduleIfOffline()
        }
    }

    /// Despierta al terminar el margen para volver a evaluar. Sin esto, la red
    /// caida no genera ningun evento nuevo y nadie desarmaria nunca.
    private func rescheduleIfOffline() {
        guard case .offline(let elapsed) = currentStatus() else { return }
        let grace = TimeInterval(box.currentPrefs.networkGraceSeconds)
        let remaining = max(grace - elapsed, 0)
        scheduler.schedule(after: remaining) { [weak self] in
            self?.emitNow()
        }
    }

    private func emitNow() {
        if let (callback, verdict) = box.update(value: currentStatus()) {
            callback(verdict)
        }
    }

    private func currentStatus() -> NetworkStatus {
        lock.lock()
        let since = offlineSince
        lock.unlock()
        guard let since else { return .online }
        return .offline(for: max(clock.now.timeIntervalSince(since), 0))
    }

    private func setOfflineSince(_ date: Date?) {
        lock.lock()
        // Si ya estaba caida, no reiniciar la cuenta: dos notificaciones seguidas
        // de "sigue sin red" no deben regalar otro margen entero.
        if date != nil, offlineSince != nil { lock.unlock(); return }
        offlineSince = date
        lock.unlock()
    }

    static let evaluate: @Sendable (NetworkStatus, PreferencesSnapshot) -> GuardVerdict = {
        status, prefs in
        guard prefs.networkGuardEnabled else { return .ok }
        guard case .offline(let elapsed) = status else { return .ok }
        guard elapsed >= TimeInterval(prefs.networkGraceSeconds) else { return .ok }
        return .mustDisarm(.networkLost(afterSeconds: prefs.networkGraceSeconds))
    }
}
