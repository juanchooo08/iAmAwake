import Darwin
import Foundation

/// Errores de transporte. No cruzan la frontera del modulo: `SocketLidController`
/// los traduce a `AwakeError`.
enum SocketError: Error, Equatable {
    /// No se pudo abrir/conectar el socket (no existe, permisos, backlog lleno).
    case cannotConnect(Int32)
    /// La operacion excedio el timeout. Nunca colgamos esperando al daemon.
    case timedOut
    /// El daemon corto la conexion antes de terminar la linea de respuesta.
    case truncated
    /// Fallo de `read`/`write` distinto de timeout o EOF.
    case io(Int32)
    /// La respuesta excedio el tamaño maximo razonable de una linea JSON.
    case lineTooLong
}

/// Conexion cliente a un socket Unix de tipo stream, con timeout en **todas**
/// las operaciones (connect, read, write).
///
/// No es thread-safe por si sola: `SocketLidController` la usa exclusivamente
/// desde una cola serial. Por eso el `@unchecked Sendable`.
final class UnixSocketConnection: @unchecked Sendable {

    /// Tope de una linea de respuesta. Un daemon que manda mas que esto esta roto
    /// o no es el nuestro; cortamos en vez de crecer el buffer sin limite.
    static let maxLineBytes = 64 * 1024

    private var fd: Int32 = -1
    /// Bytes ya leidos que todavia no forman una linea completa.
    private var pending = Data()

    var isOpen: Bool { fd >= 0 }

    // MARK: - Ciclo de vida

    init(path: String, timeout: TimeInterval) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else { throw SocketError.cannotConnect(ENAMETOOLONG) }
        withUnsafeMutablePointer(to: &address.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dest in
                for (index, byte) in pathBytes.enumerated() { dest[index] = CChar(bitPattern: byte) }
                dest[pathBytes.count] = 0
            }
        }

        let handle = socket(AF_UNIX, SOCK_STREAM, 0)
        guard handle >= 0 else { throw SocketError.cannotConnect(errno) }

        do {
            // Conectamos en modo no bloqueante para poder aplicar el timeout:
            // un `connect` bloqueante sobre un backlog lleno se queda colgado.
            try Self.setNonBlocking(handle, true)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    Darwin.connect(handle, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if result != 0 {
                guard errno == EINPROGRESS else { throw SocketError.cannotConnect(errno) }
                guard try Self.wait(handle, for: Int16(POLLOUT), timeout: timeout) else {
                    throw SocketError.timedOut
                }
                // `poll` avisa que termino, pero no si salio bien: eso esta en SO_ERROR.
                var pendingError: Int32 = 0
                var size = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(handle, SOL_SOCKET, SO_ERROR, &pendingError, &size) == 0 else {
                    throw SocketError.cannotConnect(errno)
                }
                guard pendingError == 0 else { throw SocketError.cannotConnect(pendingError) }
            }
            try Self.setNonBlocking(handle, false)

            // A partir de aca read/write son bloqueantes pero con tope temporal.
            var tv = Self.timeval(from: timeout)
            _ = setsockopt(handle, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(handle, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            // Sin esto, escribir en un socket que el daemon ya cerro mata el proceso.
            var on: Int32 = 1
            _ = setsockopt(handle, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        } catch {
            close(handle)
            throw error
        }

        fd = handle
    }

    deinit { closeConnection() }

    func closeConnection() {
        guard fd >= 0 else { return }
        close(fd)
        fd = -1
        pending.removeAll(keepingCapacity: false)
    }

    // MARK: - Transferencia

    func write(_ data: Data) throws {
        guard fd >= 0 else { throw SocketError.io(EBADF) }
        var offset = 0
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            while offset < raw.count {
                let written = Darwin.write(fd, base + offset, raw.count - offset)
                if written > 0 { offset += written; continue }
                if written == 0 { throw SocketError.truncated }
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { throw SocketError.timedOut }
                throw SocketError.io(errno)
            }
        }
    }

    /// Lee hasta el proximo `\n` (excluido). Los bytes sobrantes quedan guardados
    /// para la siguiente llamada, asi no se pierde nada si el daemon manda dos
    /// respuestas en un mismo paquete.
    func readLine() throws -> Data {
        guard fd >= 0 else { throw SocketError.io(EBADF) }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            if let index = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<index]
                // `Data(...)` rebasea el slice: un slice conserva el startIndex
                // original y eso confunde a cualquier codigo que asuma 0.
                pending = Data(pending[pending.index(after: index)...])
                return Data(line)
            }
            guard pending.count <= Self.maxLineBytes else { throw SocketError.lineTooLong }

            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                Darwin.read(fd, raw.baseAddress, raw.count)
            }
            if count > 0 {
                pending.append(contentsOf: buffer[0..<count])
                continue
            }
            // EOF con datos a medias: el daemon murio en mitad de la respuesta.
            if count == 0 { throw SocketError.truncated }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { throw SocketError.timedOut }
            throw SocketError.io(errno)
        }
    }

    // MARK: - Utilidades

    private static func setNonBlocking(_ fd: Int32, _ enabled: Bool) throws {
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else { throw SocketError.cannotConnect(errno) }
        let updated = enabled ? (flags | O_NONBLOCK) : (flags & ~O_NONBLOCK)
        guard fcntl(fd, F_SETFL, updated) >= 0 else { throw SocketError.cannotConnect(errno) }
    }

    /// `true` si el descriptor quedo listo dentro del timeout, `false` si expiro.
    private static func wait(_ fd: Int32, for events: Int16, timeout: TimeInterval) throws -> Bool {
        var descriptor = pollfd(fd: fd, events: events, revents: 0)
        let milliseconds = Int32(max(1, (timeout * 1000).rounded()))
        while true {
            let result = poll(&descriptor, 1, milliseconds)
            if result > 0 { return true }
            if result == 0 { return false }
            if errno == EINTR { continue }
            throw SocketError.cannotConnect(errno)
        }
    }

    private static func timeval(from interval: TimeInterval) -> Darwin.timeval {
        let clamped = max(interval, 0.001)
        let seconds = Int(clamped)
        let microseconds = Int32((clamped - Double(seconds)) * 1_000_000)
        return Darwin.timeval(tv_sec: seconds, tv_usec: microseconds)
    }
}
