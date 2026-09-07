import Darwin
import Foundation

enum ServerSocketError: Error, CustomStringConvertible {
    case create(Int32)
    case bind(String, Int32)
    case listen(Int32)
    case chown(uid_t, Int32)

    var description: String {
        switch self {
        case .create(let code): return "socket() fallo: \(String(cString: strerror(code)))"
        case .bind(let path, let code): return "bind(\(path)) fallo: \(String(cString: strerror(code)))"
        case .listen(let code): return "listen() fallo: \(String(cString: strerror(code)))"
        case .chown(let uid, let code):
            return "chown(uid \(uid)) fallo: \(String(cString: strerror(code)))"
        }
    }
}

/// Socket Unix de escucha, creado con permisos 0600 y dueño = el uid autorizado.
///
/// El control de acceso es el del filesystem: solo ese uid (y root) puede abrir
/// el socket. Ademas, cada conexion aceptada se verifica con `getpeereid`, por
/// si alguien lograra heredar un descriptor.
final class ListeningSocket {
    let path: String
    private(set) var fd: Int32 = -1

    init(path: String, ownerUID: uid_t?, ownerGID: gid_t?) throws {
        self.path = path

        // Un socket viejo de una ejecucion anterior impide el bind. Se borra:
        // si el daemon anterior siguiera vivo, launchd no nos habria arrancado.
        unlink(path)

        let handle = socket(AF_UNIX, SOCK_STREAM, 0)
        guard handle >= 0 else { throw ServerSocketError.create(errno) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else {
            close(handle)
            throw ServerSocketError.bind(path, ENAMETOOLONG)
        }
        withUnsafeMutablePointer(to: &address.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dest in
                for (index, byte) in bytes.enumerated() { dest[index] = CChar(bitPattern: byte) }
                dest[bytes.count] = 0
            }
        }

        // El umask decide los permisos del nodo en el instante del bind: hay que
        // apretarlo ANTES, no despues, o queda una ventana con el socket abierto
        // a todo el mundo.
        let previousMask = umask(0o177)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                Darwin.bind(handle, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previousMask)
        guard bound == 0 else {
            let code = errno
            close(handle)
            throw ServerSocketError.bind(path, code)
        }

        // Cinturon y tirantes: el umask ya deberia bastar.
        chmod(path, 0o600)

        if let ownerUID {
            guard Darwin.chown(path, ownerUID, ownerGID ?? gid_t(bitPattern: -1)) == 0 else {
                let code = errno
                close(handle)
                unlink(path)
                throw ServerSocketError.chown(ownerUID, code)
            }
        }

        guard Darwin.listen(handle, 4) == 0 else {
            let code = errno
            close(handle)
            unlink(path)
            throw ServerSocketError.listen(code)
        }

        fd = handle
    }

    /// Bloquea hasta que llegue una conexion. `nil` si el socket se cerro
    /// (shutdown) o la llamada fue interrumpida por una señal.
    func accept() -> ClientConnection? {
        while true {
            let client = Darwin.accept(fd, nil, nil)
            if client >= 0 { return ClientConnection(fd: client) }
            if errno == EINTR { continue }
            return nil
        }
    }

    func closeAndUnlink() {
        guard fd >= 0 else { return }
        close(fd)
        fd = -1
        unlink(path)
    }
}

/// Una conexion aceptada. Lee lineas terminadas en `\n` con timeout.
///
/// `@unchecked Sendable`: se pasa una unica vez del hilo del `accept` al hilo que
/// la atiende, y a partir de ahi la toca solo ese hilo. No hay estado compartido.
final class ClientConnection: @unchecked Sendable {
    enum ReadResult {
        case line(Data)
        /// No llego nada dentro del timeout. No es un error: el cliente esta
        /// vivo pero callado. Quien decide si eso importa es el dead man's switch.
        case timedOut
        /// El cliente cerro o el socket fallo. La app murio.
        case closed
    }

    static let maxLineBytes = 64 * 1024

    private var fd: Int32
    private var pending = Data()

    init(fd: Int32) {
        self.fd = fd
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit { closeConnection() }

    /// uid del proceso del otro lado. Se usa para rechazar a cualquiera que no
    /// sea el usuario que instalo el daemon.
    var peerUID: uid_t? {
        var uid = uid_t(0)
        var gid = gid_t(0)
        guard getpeereid(fd, &uid, &gid) == 0 else { return nil }
        return uid
    }

    func setReadTimeout(_ interval: TimeInterval) {
        let seconds = Int(interval)
        var tv = timeval(
            tv_sec: seconds,
            tv_usec: Int32((interval - Double(seconds)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    func readLine() -> ReadResult {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            if let index = pending.firstIndex(of: 0x0A) {
                let line = Data(pending[pending.startIndex..<index])
                pending = Data(pending[pending.index(after: index)...])
                return .line(line)
            }
            // Un cliente que manda basura infinita sin `\n` no nos va a comer la RAM.
            guard pending.count <= Self.maxLineBytes else { return .closed }

            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                Darwin.read(fd, raw.baseAddress, raw.count)
            }
            if count > 0 {
                pending.append(contentsOf: buffer[0..<count])
                continue
            }
            if count == 0 { return .closed }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { return .timedOut }
            return .closed
        }
    }

    @discardableResult
    func write(_ data: Data) -> Bool {
        guard fd >= 0 else { return false }
        var offset = 0
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return true }
            while offset < raw.count {
                let written = Darwin.write(fd, base + offset, raw.count - offset)
                if written > 0 { offset += written; continue }
                if written < 0 && errno == EINTR { continue }
                return false
            }
            return true
        }
    }

    func closeConnection() {
        guard fd >= 0 else { return }
        close(fd)
        fd = -1
    }
}
