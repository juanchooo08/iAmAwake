import Foundation
import StillOnCore
import Testing

@testable import HelperClient

/// Tests del cliente contra un daemon FALSO en un socket temporal.
/// Nunca se instala el LaunchDaemon real ni se ejecuta `pmset`.
@Suite final class SocketLidControllerTests {

    /// Timeout corto: los casos de "no responde" no deben tardar segundos.
    private let timeout: TimeInterval = 0.3

    /// swift-testing crea una instancia del suite por test, asi que init/deinit
    /// cumplen el rol de setUp/tearDown y cada test tiene su propio plist.
    private let plistPath: String

    init() {
        plistPath = "/tmp/stillond-test-plist-\(UUID().uuidString.prefix(8)).plist"
        FileManager.default.createFile(atPath: plistPath, contents: Data("<plist/>".utf8))
    }

    deinit {
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    private func makeController(socketPath: String, plist: String? = nil) -> SocketLidController {
        SocketLidController(
            socketPath: socketPath,
            plistPath: plist ?? plistPath,
            timeout: timeout)
    }

    private static let okResponse = Wire.Response(ok: true, clamshellSleepDisabled: true)

    // MARK: - Camino feliz

    @Test func testArmSendsArmCommand() async throws {
        let daemon = try FakeDaemon { request in
            .respond(Wire.Response(ok: true, clamshellSleepDisabled: request?.cmd == .arm))
        }
        defer { daemon.stop() }

        let controller = makeController(socketPath: daemon.path)
        try await controller.setClamshellSleepDisabled(true)

        #expect(daemon.commands == [.arm])
    }

    @Test func testDisarmSendsDisarmCommand() async throws {
        let daemon = try FakeDaemon { _ in
            .respond(Wire.Response(ok: true, clamshellSleepDisabled: false))
        }
        defer { daemon.stop() }

        let controller = makeController(socketPath: daemon.path)
        try await controller.setClamshellSleepDisabled(false)

        #expect(daemon.commands == [.disarm])
    }

    @Test func testHeartbeatReusesTheSameConnection() async throws {
        let daemon = try FakeDaemon { _ in .respond(Self.okResponse) }
        defer { daemon.stop() }

        let controller = makeController(socketPath: daemon.path)
        for _ in 0..<5 { try await controller.heartbeat() }

        #expect(daemon.commands == Array(repeating: .ping, count: 5))
        // Lo importante: un solo `accept`, no uno por latido.
        #expect(daemon.connectionCount == 1)
    }

    // MARK: - installState

    @Test func testInstallStateIsNotInstalledWhenPlistMissing() async throws {
        let daemon = try FakeDaemon { _ in .respond(Self.okResponse) }
        defer { daemon.stop() }

        let controller = makeController(
            socketPath: daemon.path, plist: "/tmp/no-existe-\(UUID().uuidString).plist")
        let state = await controller.installState

        #expect(state == .notInstalled)
        // No debe haber ni intentado hablar: sin plist no hay daemon.
        #expect(daemon.connectionCount == 0)
    }

    @Test func testInstallStateIsInstalledNotRunningWhenSocketIsDead() async throws {
        let controller = makeController(socketPath: "/tmp/stillond-inexistente-\(UUID().uuidString)")
        let state = await controller.installState
        #expect(state == .installedNotRunning)
    }

    @Test func testInstallStateIsReadyWhenDaemonAnswersPing() async throws {
        let daemon = try FakeDaemon { _ in .respond(Self.okResponse) }
        defer { daemon.stop() }

        let controller = makeController(socketPath: daemon.path)
        let state = await controller.installState

        #expect(state == .ready(protocolVersion: Wire.protocolVersion))
        #expect(daemon.commands == [.ping])
    }

    @Test func testInstallStateReportsTheDaemonVersionEvenIfItDiffers() async throws {
        let daemon = try FakeDaemon { _ in
            .respond(Wire.Response(ok: true, version: 99))
        }
        defer { daemon.stop() }

        let controller = makeController(socketPath: daemon.path)
        let state = await controller.installState

        // Esta corriendo: quien decide que hacer con la incompatibilidad es
        // PowerState, no el transporte.
        #expect(state == .ready(protocolVersion: 99))
    }

    // MARK: - Errores

    @Test func testServerErrorMapsToHelperRefused() async throws {
        let daemon = try FakeDaemon { _ in
            .respond(Wire.Response(ok: false, error: "bateria en 3 %"))
        }
        defer { daemon.stop() }

        let controller = makeController(socketPath: daemon.path)
        await assertThrows(.helperRefused("bateria en 3 %")) {
            try await controller.setClamshellSleepDisabled(true)
        }
    }

    @Test func testServerErrorWithoutMessageStillMapsToHelperRefused() async throws {
        let daemon = try FakeDaemon { _ in .respond(Wire.Response(ok: false)) }
        defer { daemon.stop() }

        let controller = makeController(socketPath: daemon.path)
        do {
            try await controller.setClamshellSleepDisabled(true)
            Issue.record("deberia haber lanzado")
        } catch StillOnError.helperRefused(let message) {
            #expect(!(message.isEmpty))
        }
    }

    @Test func testVersionMismatchMapsToHelperVersionMismatch() async throws {
        let daemon = try FakeDaemon { _ in
            .respond(Wire.Response(ok: true, version: 42))
        }
        defer { daemon.stop() }

        let controller = makeController(socketPath: daemon.path)
        await assertThrows(.helperVersionMismatch(expected: Wire.protocolVersion, got: 42)) {
            try await controller.heartbeat()
        }
    }

    @Test func testMissingSocketMapsToHelperUnavailable() async {
        let controller = makeController(socketPath: "/tmp/stillond-inexistente-\(UUID().uuidString)")
        await assertThrows(.helperUnavailable) {
            try await controller.setClamshellSleepDisabled(true)
        }
    }

    @Test func testUnresponsiveServerTimesOutInsteadOfHanging() async throws {
        let daemon = try FakeDaemon { _ in .silence }
        defer { daemon.stop() }

        let controller = makeController(socketPath: daemon.path)
        let started = Date()
        await assertThrows(.helperUnavailable) {
            try await controller.heartbeat()
        }
        // Dos intentos (el original y el reintento tras reconectar), no infinito.
        #expect(Date().timeIntervalSince(started) < timeout * 6)
    }

    @Test func testTruncatedResponseIsACleanError() async throws {
        let daemon = try FakeDaemon { _ in .raw("{\"ok\":true,\"vers") }
        defer { daemon.stop() }

        let controller = makeController(socketPath: daemon.path)
        await assertThrows(.helperUnavailable) {
            try await controller.heartbeat()
        }
    }

    @Test func testGarbageResponseIsACleanError() async throws {
        let daemon = try FakeDaemon { _ in .raw("esto no es JSON\n") }
        defer { daemon.stop() }

        let controller = makeController(socketPath: daemon.path)
        await assertThrows(.helperUnavailable) {
            try await controller.heartbeat()
        }
    }

    // MARK: - Reconexion

    @Test func testReconnectsOnceAfterTheServerDropsTheConnection() async throws {
        let counter = Counter()
        let daemon = try FakeDaemon { _ in
            // El primer request se contesta; en el segundo el "daemon" se cae.
            // El tercero (ya reconectado) tiene que funcionar.
            counter.next() == 2 ? .hangUp : .respond(Self.okResponse)
        }
        defer { daemon.stop() }

        let controller = makeController(socketPath: daemon.path)
        try await controller.heartbeat()
        try await controller.heartbeat()

        #expect(daemon.commands == [.ping, .ping, .ping])
        #expect(daemon.connectionCount == 2, "debe reconectar exactamente una vez")
    }

    @Test func testReconnectsAfterAnExplicitDisconnect() async throws {
        let daemon = try FakeDaemon { _ in .respond(Self.okResponse) }
        defer { daemon.stop() }

        let controller = makeController(socketPath: daemon.path)
        try await controller.heartbeat()
        await controller.disconnect()
        try await controller.heartbeat()

        #expect(daemon.connectionCount == 2)
    }

    // MARK: - Utilidades

    private func assertThrows(
        _ expected: StillOnError,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            Issue.record("deberia haber lanzado \(expected)")
        } catch let error as StillOnError {
            #expect(error == expected)
        } catch {
            Issue.record("error inesperado: \(error)")
        }
    }
}

/// Contador compartido con el handler del daemon falso.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
