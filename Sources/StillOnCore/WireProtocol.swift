import Foundation

/// Protocolo de cable entre StillOn.app (usuario) y stillond (root).
/// JSON delimitado por "\n" sobre un socket Unix.
public enum Wire {
    public static let protocolVersion = 1
    public static let socketPath = "/var/run/stillond.sock"
    public static let daemonLabel = "dev.local.stillond"
    /// Si el daemon no recibe nada en este lapso, revierte solo.
    public static let heartbeatTimeout: TimeInterval = 30
    /// Cada cuanto manda heartbeat la app.
    public static let heartbeatInterval: TimeInterval = 10
    /// Piso duro del daemon, independiente de la preferencia del usuario.
    public static let hardBatteryFloor = 5

    public struct Request: Codable, Equatable, Sendable {
        public enum Command: String, Codable, Sendable { case arm, disarm, ping, status }
        public let cmd: Command
        public let version: Int
        public init(cmd: Command, version: Int = Wire.protocolVersion) {
            self.cmd = cmd; self.version = version
        }
    }

    public struct Response: Codable, Equatable, Sendable {
        public let ok: Bool
        public let version: Int
        public let clamshellSleepDisabled: Bool?
        public let error: String?
        public init(ok: Bool, version: Int = Wire.protocolVersion,
                    clamshellSleepDisabled: Bool? = nil, error: String? = nil) {
            self.ok = ok; self.version = version
            self.clamshellSleepDisabled = clamshellSleepDisabled; self.error = error
        }
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line)
    }
}
