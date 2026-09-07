import Foundation
import AwakeCore

/// Cliente del daemon root `iamawaked`. Es la unica via real para evitar que la
/// Mac duerma al cerrar la tapa (ver ARCHITECTURE.md seccion 0).
///
/// # Modelo
///
/// Toda la I/O de socket es bloqueante y corre en una cola serial propia; la
/// interfaz `async` la envuelve en continuaciones. Consecuencias:
/// - nunca se bloquea un hilo de la app ni del pool cooperativo de Swift;
/// - las operaciones se serializan solas, asi que la conexion (que no es
///   thread-safe) se usa desde un unico hilo por construccion.
///
/// # Conexion persistente
///
/// `heartbeat()` corre cada 10 s: abrir un socket por latido seria caro y
/// generaria ruido en el accept loop del daemon. Se reusa la conexion y solo se
/// reconecta cuando se cayo. Cada operacion reintenta **una** vez tras
/// reconectar; si el segundo intento falla, se reporta el error.
///
/// # Timeouts
///
/// Connect, read y write tienen tope temporal. La app nunca se cuelga esperando
/// al daemon: en el peor caso recibe `helperUnavailable` y desarma.
public final class SocketLidController: LidSleepControlling, @unchecked Sendable {

    /// Ruta por defecto del plist del LaunchDaemon. Su ausencia es lo que
    /// distingue "no instalado" de "instalado pero caido".
    public static let defaultPlistPath = "/Library/LaunchDaemons/\(Wire.daemonLabel).plist"

    private let socketPath: String
    private let plistPath: String
    private let timeout: TimeInterval
    private let fileManager: FileManager
    private let queue: DispatchQueue

    /// Solo se toca desde `queue`.
    private var connection: UnixSocketConnection?

    public convenience init() {
        self.init(socketPath: Wire.socketPath, plistPath: Self.defaultPlistPath)
    }

    /// - Parameters:
    ///   - socketPath: socket Unix del daemon.
    ///   - plistPath: plist del LaunchDaemon, para detectar `.notInstalled`.
    ///   - timeout: tope de cada operacion de socket.
    public init(
        socketPath: String,
        plistPath: String = SocketLidController.defaultPlistPath,
        timeout: TimeInterval = 2.0,
        fileManager: FileManager = .default
    ) {
        self.socketPath = socketPath
        self.plistPath = plistPath
        self.timeout = timeout
        self.fileManager = fileManager
        self.queue = DispatchQueue(label: "dev.local.iamawake.helper-client")
    }

    // MARK: - LidSleepControlling

    public var installState: HelperInstallState {
        get async {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    continuation.resume(returning: installStateOnQueue())
                }
            }
        }
    }

    public func setClamshellSleepDisabled(_ disabled: Bool) async throws {
        _ = try await send(disabled ? .arm : .disarm)
    }

    public func heartbeat() async throws {
        _ = try await send(.ping)
    }

    /// Estado que reporta el daemon. `nil` si no lo dice.
    public func status() async throws -> Bool? {
        try await send(.status).clamshellSleepDisabled
    }

    /// Cierra la conexion. La proxima operacion reconecta sola.
    public func disconnect() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                connection?.closeConnection()
                connection = nil
                continuation.resume()
            }
        }
    }

    // MARK: - Envio

    @discardableResult
    private func send(_ command: Wire.Request.Command) async throws -> Wire.Response {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                continuation.resume(with: Result { try sendOnQueue(command) })
            }
        }
    }

    private func sendOnQueue(_ command: Wire.Request.Command) throws -> Wire.Response {
        do {
            return try roundTripOnQueue(command)
        } catch let error as SocketError where error != .cannotConnect(ENOENT) {
            // La conexion vieja pudo haber muerto mientras estaba ociosa (daemon
            // reiniciado por launchd). Un reintento limpio, y nada mas: reintentar
            // en bucle escondería un daemon roto.
            connection?.closeConnection()
            connection = nil
            do {
                return try roundTripOnQueue(command)
            } catch {
                throw Self.translate(error)
            }
        } catch {
            throw Self.translate(error)
        }
    }

    private func roundTripOnQueue(_ command: Wire.Request.Command) throws -> Wire.Response {
        let socket = try connectionOnQueue()
        let request = Wire.Request(cmd: command)
        try socket.write(try Wire.encode(request))
        let line = try socket.readLine()
        let response: Wire.Response
        do {
            response = try Wire.decode(Wire.Response.self, from: line)
        } catch {
            // Alguien esta hablando otro idioma en ese socket. No es nuestro daemon.
            throw SocketError.truncated
        }
        guard response.version == Wire.protocolVersion else {
            throw AwakeError.helperVersionMismatch(
                expected: Wire.protocolVersion, got: response.version)
        }
        guard response.ok else {
            throw AwakeError.helperRefused(response.error ?? "el daemon rechazo la operacion")
        }
        return response
    }

    private func connectionOnQueue() throws -> UnixSocketConnection {
        if let existing = connection, existing.isOpen { return existing }
        let fresh = try UnixSocketConnection(path: socketPath, timeout: timeout)
        connection = fresh
        return fresh
    }

    private func installStateOnQueue() -> HelperInstallState {
        guard fileManager.fileExists(atPath: plistPath) else { return .notInstalled }
        do {
            let response = try roundTripOnQueue(.ping)
            return .ready(protocolVersion: response.version)
        } catch AwakeError.helperVersionMismatch(_, let got) {
            // Responde, pero con otra version. Sigue estando "listo": quien decide
            // que hacer con la incompatibilidad es PowerState, no el transporte.
            return .ready(protocolVersion: got)
        } catch AwakeError.helperRefused {
            // Contesta y habla nuestro protocolo: esta corriendo.
            return .ready(protocolVersion: Wire.protocolVersion)
        } catch {
            connection?.closeConnection()
            connection = nil
            return .installedNotRunning
        }
    }

    /// Los errores de transporte no le sirven a la app: solo hay dos preguntas
    /// utiles, "¿esta el daemon?" y "¿que dijo?".
    private static func translate(_ error: Error) -> Error {
        if error is AwakeError { return error }
        return AwakeError.helperUnavailable
    }
}
