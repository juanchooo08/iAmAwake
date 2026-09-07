import Darwin
import Foundation
import StillOnCore

/// Daemon falso: habla el mismo protocolo de cable en un socket Unix temporal.
///
/// Los tests del cliente NO instalan el daemon real ni ejecutan `pmset`. Esto
/// existe para poder provocar a voluntad los casos feos (silencio, respuesta
/// cortada a la mitad, version equivocada, caida de conexion) que en el daemon
/// de verdad serian imposibles de reproducir.
final class FakeDaemon: @unchecked Sendable {

    /// Que contesta el servidor ante un request.
    enum Reply: Sendable {
        case respond(Wire.Response)
        /// Manda esos bytes tal cual (sin agregar `\n`) y corta la conexion.
        /// Con eso se simula una respuesta cortada a la mitad.
        case raw(String)
        /// No contesta nada y deja la conexion abierta: el cliente debe timeoutear.
        case silence
        /// Corta la conexion sin contestar.
        case hangUp
    }

    let path: String
    private let directory: String
    private let handler: @Sendable (Wire.Request?) -> Reply

    private var listenFD: Int32 = -1
    private let lock = NSLock()
    private var receivedCommands: [Wire.Request.Command] = []
    private var acceptedConnections = 0
    private var isStopped = false

    /// Requests que llegaron, en orden.
    var commands: [Wire.Request.Command] {
        lock.lock(); defer { lock.unlock() }
        return receivedCommands
    }

    /// Cuantas veces se conecto el cliente. Sirve para probar que el heartbeat
    /// reusa la conexion en vez de abrir una por latido.
    var connectionCount: Int {
        lock.lock(); defer { lock.unlock() }
        return acceptedConnections
    }

    init(handler: @escaping @Sendable (Wire.Request?) -> Reply) throws {
        // /tmp y no NSTemporaryDirectory(): `sun_path` tiene 104 bytes y las rutas
        // de /var/folders/... se pasan de largo con facilidad.
        directory = "/tmp/stillond-test-\(UUID().uuidString.prefix(8))"
        path = "\(directory)/sock"
        self.handler = handler
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)

        listenFD = try Self.bindAndListen(path: path)
        let thread = Thread { [weak self] in self?.acceptLoop() }
        thread.stackSize = 512 * 1024
        thread.start()
    }

    deinit { stop() }

    func stop() {
        lock.lock()
        guard !isStopped else { lock.unlock(); return }
        isStopped = true
        let fd = listenFD
        listenFD = -1
        lock.unlock()

        if fd >= 0 { close(fd) }
        try? FileManager.default.removeItem(atPath: directory)
    }

    // MARK: - Servidor

    private func acceptLoop() {
        while true {
            lock.lock()
            let fd = listenFD
            lock.unlock()
            guard fd >= 0 else { return }

            let client = accept(fd, nil, nil)
            guard client >= 0 else {
                if errno == EINTR { continue }
                return
            }
            lock.lock()
            acceptedConnections += 1
            lock.unlock()

            let thread = Thread { [weak self] in self?.serve(client) }
            thread.stackSize = 512 * 1024
            thread.start()
        }
    }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            while let index = pending.firstIndex(of: 0x0A) {
                let line = Data(pending[pending.startIndex..<index])
                pending = Data(pending[pending.index(after: index)...])
                let request = try? Wire.decode(Wire.Request.self, from: line)
                if let request {
                    lock.lock()
                    receivedCommands.append(request.cmd)
                    lock.unlock()
                }
                switch handler(request) {
                case .respond(let response):
                    guard let data = try? Wire.encode(response), send(fd, data) else { return }
                case .raw(let text):
                    _ = send(fd, Data(text.utf8))
                    return
                case .silence:
                    continue
                case .hangUp:
                    return
                }
            }
            let count = buffer.withUnsafeMutableBytes { raw in
                read(fd, raw.baseAddress, raw.count)
            }
            guard count > 0 else { return }
            pending.append(contentsOf: buffer[0..<count])
        }
    }

    private func send(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let written = write(fd, base + offset, raw.count - offset)
                if written > 0 { offset += written; continue }
                if written < 0 && errno == EINTR { continue }
                return false
            }
            return true
        }
    }

    private static func bindAndListen(path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FakeDaemonError.setup("socket(): \(errno)") }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else {
            close(fd)
            throw FakeDaemonError.setup("ruta demasiado larga: \(path)")
        }
        withUnsafeMutablePointer(to: &address.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dest in
                for (index, byte) in bytes.enumerated() { dest[index] = CChar(bitPattern: byte) }
                dest[bytes.count] = 0
            }
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                bind(fd, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw FakeDaemonError.setup("bind(): \(code)")
        }
        guard listen(fd, 4) == 0 else {
            let code = errno
            close(fd)
            throw FakeDaemonError.setup("listen(): \(code)")
        }
        return fd
    }
}

enum FakeDaemonError: Error, CustomStringConvertible {
    case setup(String)
    var description: String {
        switch self { case .setup(let message): return message }
    }
}

/// Reloj manual. El dead man's switch se testea con tiempo simulado: esperar
/// 30 segundos de verdad en un test es inaceptable y ademas frágil.
final class MutableClock: ClockProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) { current = start }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(_ interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }
}
