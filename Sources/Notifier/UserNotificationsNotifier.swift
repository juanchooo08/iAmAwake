import Foundation
import AwakeCore
import os

/// Implementacion de `Notifying` sobre `UNUserNotificationCenter`.
///
/// La autorizacion se pide una sola vez si la conceden. Si el
/// usuario la niega no se crashea: se registra y se sigue (iAmAwake funciona igual,
/// solo que en silencio).
public final class UserNotificationsNotifier: Notifying, @unchecked Sendable {

    private enum Authorization {
        case unknown, granted
    }

    private static let log = Logger(subsystem: "dev.local.iamawake", category: "notificaciones")

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

    public func notifyArmed() async {
        await send(NotificationTexts.armed)
    }

    public func notifyDisarmed(reason: DisarmReason) async {
        guard let payload = NotificationTexts.disarmed(reason) else { return }
        await send(payload)
    }

    public func notifyFailure(_ error: AwakeError) async {
        await send(NotificationTexts.failure(error))
    }

    // MARK: - Interno

    private func send(_ payload: NotificationPayload) async {
        guard await ensureAuthorized() else {
            Self.log.error("sin permiso, no se entrega: \(payload.identifier, privacy: .public)")
            return
        }
        await center.deliver(payload)
        Self.log.notice("entregada: \(payload.identifier, privacy: .public)")
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
        case .unknown:
            if let existing = inFlight { return .pending(existing) }
            let task = Task { [center] in await center.requestAuthorization() }
            inFlight = task
            return .started(task)
        }
    }

    /// Solo se recuerda el "si".
    ///
    /// Un "no" no siempre es el usuario negando: pedido muy temprano en el
    /// arranque, el sistema puede contestar que no antes de terminar de
    /// registrar la app. Cachearlo dejaba la app muda para el resto de la
    /// sesion, que es exactamente el sintoma que aparecio: la notificacion de
    /// prueba llegaba, las de armado y desarmado no. Si el usuario de verdad
    /// nego el permiso, volver a preguntar contesta que no al instante y sin
    /// molestarlo.
    private func finishAuthorization(_ granted: Bool) {
        lock.lock()
        defer { lock.unlock() }
        authorization = granted ? .granted : .unknown
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
