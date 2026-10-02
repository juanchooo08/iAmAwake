import Foundation
import AwakeCore

/// Lee las marcas que dejan los hooks de Claude Code
/// (`Scripts/claude-activity-hook.sh`): un archivo por sesion mientras trabaja,
/// borrado al terminar el turno o al quedar esperando una respuesta tuya.
///
/// Por que hooks y no CPU: medido, una sesion ociosa gasta ~1% y una que espera
/// al modelo ~2%. No se separan.
///
/// `staleAfter` cubre lo que los hooks no avisan: interrumpir con Esc o matar
/// la sesion a mitad de turno deja la marca huerfana. Toda herramienta la
/// refresca y ninguna corre mas de 10 min en primer plano, asi que 20 min sin
/// tocarla es una sesion muerta.
public final class ClaudeSessionMarkerReader: ClaudeActivityReading, @unchecked Sendable {
    public static let defaultDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/iAmAwake/claude-sessions")

    private let directory: URL
    private let staleAfter: TimeInterval
    private let clock: ClockProviding

    public init(
        directory: URL = ClaudeSessionMarkerReader.defaultDirectory,
        staleAfter: TimeInterval = 1200,
        clock: ClockProviding = SystemClock()
    ) {
        self.directory = directory
        self.staleAfter = staleAfter
        self.clock = clock
    }

    public func isActive() -> Bool {
        let key = URLResourceKey.contentModificationDateKey
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [key]
        ) else { return false }
        let cutoff = clock.now.addingTimeInterval(-staleAfter)
        return files.contains { url in
            guard let date = try? url.resourceValues(forKeys: [key]).contentModificationDate
            else { return false }
            return date > cutoff
        }
    }
}
