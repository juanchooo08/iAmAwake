import Foundation

/// Frontera con `/usr/bin/pmset`.
///
/// Por que un binario y no IOKit directo: escribir `DisableClamshellSleep` en
/// `IOPMrootDomain` devuelve `kIOReturnNotPermitted` sin root, y con el user
/// client abierto el selector 11 devuelve `kIOReturnBadArgument` (medido en este
/// hardware). `pmset -a disablesleep 1` si funciona, y ya corremos como root.
enum PMSet {
    static let path = "/usr/bin/pmset"

    struct Failure: Error, CustomStringConvertible {
        let status: Int32
        let output: String
        var description: String {
            output.isEmpty ? "pmset salio con codigo \(status)" : "pmset: \(output)"
        }
    }

    /// `pmset -a disablesleep 0|1`. Lanza `Failure` si el codigo de salida no es 0.
    static func setDisableSleep(_ disabled: Bool) throws {
        try run(["-a", "disablesleep", disabled ? "1" : "0"])
    }

    private static func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw Failure(status: -1, output: "no se pudo ejecutar \(path): \(error)")
        }

        // Leer antes de esperar: si pmset llenara el pipe, esperar primero
        // deadlockearia. La salida es minima, pero el orden correcto es gratis.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let text = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(status: process.terminationStatus, output: text)
        }
    }
}
