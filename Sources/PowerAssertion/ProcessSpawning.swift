import Foundation

/// Un proceso hijo ya lanzado. Se mantiene vivo mientras la inhibicion este activa.
protocol SpawnedProcess: AnyObject, Sendable {
    var isRunning: Bool { get }
    /// Lo mata y espera a que muera. Debe ser idempotente.
    func terminateAndWait()
}

/// Frontera con `Foundation.Process`, para testear el fallback sin lanzar
/// `/usr/bin/caffeinate` de verdad.
protocol ProcessSpawning: Sendable {
    func spawn(path: String, arguments: [String]) throws -> SpawnedProcess
}

/// Implementacion real: `Process` de Foundation.
struct FoundationProcessSpawner: ProcessSpawning {
    func spawn(path: String, arguments: [String]) throws -> SpawnedProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return LiveProcess(process)
    }
}

/// `Process` no es `Sendable`; se encapsula tras un lock para poder cruzarlo de hilo.
final class LiveProcess: SpawnedProcess, @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process

    init(_ process: Process) { self.process = process }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return process.isRunning
    }

    func terminateAndWait() {
        lock.lock(); defer { lock.unlock() }
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }
}
