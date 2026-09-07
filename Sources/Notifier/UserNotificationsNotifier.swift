import Foundation
import StillOnCore

/// Implementacion de `Notifying` sobre `UNUserNotificationCenter`.
///
/// La autorizacion se pide una sola vez y el resultado queda recordado. Si el
/// usuario la niega no se crashea: se registra y se sigue (StillOn funciona igual,
/// solo que en silencio).
public final class UserNotificationsNotifier: Notifying, @unchecked Sendable {

    private enum Authorization {
        case unknown, granted, denied
    }

    private let center: NotificationDelivering
    private let lock = NSLock()
    private var authorization: Authorization = .unknown
    private var inFlight: Task<Bool, Never>?

    public init(center: NotificationDelivering = UNCenterAdapter()) {
        self.center = center
    }

    public func requestAuthorizationIfNeeded() async {
        _ = await ensureAuthorized()
    }

    public func notifyDisarmed(reason: DisarmReason) async {
        guard let payload = NotificationTexts.disarmed(reason) else { return }
        await send(payload)
    }

    public func notifyFailure(_ error: StillOnError) async {
        await send(NotificationTexts.failure(error))
    }

    // MARK: - Interno

    private func send(_ payload: NotificationPayload) async {
        guard await ensureAuthorized() else {
            NSLog("[StillOn] notificacion no entregada (permiso denegado): \(payload.body)")
            return
        }
        await center.deliver(payload)
    }

    /// Pide el permiso a lo sumo una vez; llamadas concurrentes comparten la misma tarea.
    ///
    /// El estado compartido se toca solo en `beginAuthorization` / `finishAuthorization`,
    /// que son sincronas: Swift 6 prohibe `NSLock.lock()` dentro de una funcion async.
    private enum AuthDecision {
        case resolved(Bool)
        case pending(Task<Bool, Never>)
        case started(Task<Bool, Never>)
    }

    private func beginAuthorization() -> AuthDecision {
        lock.lock()
        defer { lock.unlock() }
        switch authorization {
        case .granted:
            return .resolved(true)
        case .denied:
            return .resolved(false)
        case .unknown:
            if let existing = inFlight { return .pending(existing) }
            let task = Task { [center] in await center.requestAuthorization() }
            inFlight = task
            return .started(task)
        }
    }

    private func finishAuthorization(_ granted: Bool) {
        lock.lock()
        defer { lock.unlock() }
        authorization = granted ? .granted : .denied
        inFlight = nil
    }

    private func ensureAuthorized() async -> Bool {
        switch beginAuthorization() {
        case .resolved(let value):
            return value
        case .pending(let task):
            return await task.value
        case .started(let task):
            let granted = await task.value
            finishAuthorization(granted)
            return granted
        }
    }
}
