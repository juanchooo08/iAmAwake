// Los tests del Notifier viven aca por pedido del contrato, pero el target de test
// `PreferencesTests` NO declara `Notifier` como dependencia en Package.swift, y no
// tengo permiso para tocar ese archivo. El `#if canImport` deja el archivo listo:
// en cuanto alguien agregue "Notifier" a las dependencias de PreferencesTests, estos
// tests se activan solos sin romper nada mientras tanto.
#if canImport(Notifier)

    import AwakeCore
    import Foundation
import Testing

    @testable import Notifier

    /// Doble del centro de notificaciones: registra lo entregado, no dispara nada real.
    final class SpyNotificationCenter: NotificationDelivering, @unchecked Sendable {
        private let lock = NSLock()
        private var _delivered: [NotificationPayload] = []
        private var _authorizationRequests = 0
        let grants: Bool

        init(grants: Bool = true) { self.grants = grants }

        var delivered: [NotificationPayload] {
            lock.lock(); defer { lock.unlock() }
            return _delivered
        }

        var authorizationRequests: Int {
            lock.lock(); defer { lock.unlock() }
            return _authorizationRequests
        }

        // Los cuerpos con lock viven en metodos sincronos: Swift 6 prohibe
        // NSLock.lock() dentro de una funcion async.
        private func countRequest() {
            lock.lock(); defer { lock.unlock() }
            _authorizationRequests += 1
        }

        private func record(_ payload: NotificationPayload) {
            lock.lock(); defer { lock.unlock() }
            _delivered.append(payload)
        }

        func requestAuthorization() async -> Bool {
            countRequest()
            return grants
        }

        func deliver(_ payload: NotificationPayload) async {
            record(payload)
        }
    }

    @Suite struct NotifierTests {

        // MARK: - Motivos de desarme

        @Test func testLowBatteryExplainsWhy() async {
            let spy = SpyNotificationCenter()
            let notifier = UserNotificationsNotifier(center: spy)
            await notifier.notifyDisarmed(reason: .lowBattery(percent: 12))

            #expect(spy.delivered.count == 1)
            #expect(spy.delivered[0].body == "iAmAwake se desarmó — batería en 12%. Tu Mac va a poder dormir para no quedarse sin carga.")
        }

        @Test func testThermalExplainsWhy() async {
            let spy = SpyNotificationCenter()
            let notifier = UserNotificationsNotifier(center: spy)
            await notifier.notifyDisarmed(reason: .thermal(.critical))

            #expect(spy.delivered[0].body == "iAmAwake se desarmó — temperatura alta (crítica). Con la tapa cerrada el calor no se disipa.")
        }

        @Test func testAssertionFailureDescribesTheConcreteError() async {
            let spy = SpyNotificationCenter()
            let notifier = UserNotificationsNotifier(center: spy)
            await notifier.notifyDisarmed(reason: .assertionFailure(.helperUnavailable))

            let body = spy.delivered[0].body
            #expect(body.hasPrefix("iAmAwake se desarmó — "))
            #expect(body.contains("iamawaked"))
            #expect(body.contains("cierre de tapa"))
        }

        @Test func testUserAndTerminatingDoNotNotify() async {
            let spy = SpyNotificationCenter()
            let notifier = UserNotificationsNotifier(center: spy)
            await notifier.notifyDisarmed(reason: .user)
            await notifier.notifyDisarmed(reason: .appTerminating)

            #expect(spy.delivered.isEmpty)
            // Ni siquiera se molesta al usuario pidiendo permiso.
            #expect(spy.authorizationRequests == 0)
        }

        // MARK: - Errores

        @Test func testEveryErrorProducesADistinctNonEmptyMessage() async {
            let errors: [AwakeError] = [
                .assertionFailed(-536_870_207),
                .helperUnavailable,
                .helperRefused("socket cerrado"),
                .helperVersionMismatch(expected: 2, got: 1),
                .hotkeyRegistrationFailed(-9868),
                .notificationPermissionDenied,
            ]

            let spy = SpyNotificationCenter()
            let notifier = UserNotificationsNotifier(center: spy)
            for error in errors { await notifier.notifyFailure(error) }

            #expect(spy.delivered.count == errors.count)
            let bodies = spy.delivered.map(\.body)
            for body in bodies { #expect(!(body.isEmpty)) }
            #expect(Set(bodies).count == errors.count, "los mensajes deben ser distintos entre si")
        }

        @Test func testHelperUnavailableSaysTheLidIsNotCovered() {
            let body = NotificationTexts.failure(.helperUnavailable).body
            #expect(body.contains("no está instalado"))
            #expect(body.contains("NO se cubre el cierre de tapa"))
        }

        @Test func testHelperRefusedIncludesTheDaemonMessage() {
            let body = NotificationTexts.failure(.helperRefused("permiso denegado")).body
            #expect(body.contains("permiso denegado"))
        }

        @Test func testVersionMismatchIncludesBothVersions() {
            let body = NotificationTexts.failure(.helperVersionMismatch(expected: 3, got: 1)).body
            #expect(body.contains("3"))
            #expect(body.contains("1"))
        }

        // MARK: - Autorizacion

        @Test func testAuthorizationIsRequestedOnlyOnce() async {
            let spy = SpyNotificationCenter()
            let notifier = UserNotificationsNotifier(center: spy)
            await notifier.requestAuthorizationIfNeeded()
            await notifier.requestAuthorizationIfNeeded()
            await notifier.notifyFailure(.helperUnavailable)

            #expect(spy.authorizationRequests == 1)
        }

        @Test func testDeniedAuthorizationDoesNotCrashAndDeliversNothing() async {
            let spy = SpyNotificationCenter(grants: false)
            let notifier = UserNotificationsNotifier(center: spy)
            await notifier.requestAuthorizationIfNeeded()
            await notifier.notifyFailure(.helperUnavailable)
            await notifier.notifyDisarmed(reason: .lowBattery(percent: 3))

            #expect(spy.delivered.isEmpty)
            #expect(spy.authorizationRequests == 1)
        }
    }

#endif
