import Darwin
import Foundation

public enum ThermalLevel: Int, Comparable, Codable, Sendable {
    case nominal = 0, fair = 1, serious = 2, critical = 3
    public static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }
}

public enum GuardID: String, Codable, Sendable, CaseIterable { case battery, thermal, network }

public enum AwakeError: Error, Equatable, Sendable {
    case assertionFailed(kern_return_t)
    case helperUnavailable
    case helperRefused(String)
    case helperVersionMismatch(expected: Int, got: Int)
    case hotkeyRegistrationFailed(OSStatus)
    case notificationPermissionDenied
}

public enum DisarmReason: Equatable, Sendable {
    case user
    case lowBattery(percent: Int)
    case thermal(ThermalLevel)
    /// Se cayo la red y no volvio dentro del margen. `afterSeconds` es el margen
    /// que se agoto, no el tiempo total sin conexion.
    case networkLost(afterSeconds: Int)
    case assertionFailure(AwakeError)
    case appTerminating
}

public enum ArmState: Equatable, Sendable {
    case disarmed
    case armed
    case blockedLowBattery(percent: Int)
    case blockedThermal(ThermalLevel)
    case blockedNetworkLost(afterSeconds: Int)
    case failed(AwakeError)

    public var isArmed: Bool { self == .armed }
}

public enum GuardVerdict: Equatable, Sendable {
    case ok
    case mustDisarm(DisarmReason)
    case mustNotArm(DisarmReason)

    public var blockingReason: DisarmReason? {
        switch self {
        case .ok: return nil
        case .mustDisarm(let r), .mustNotArm(let r): return r
        }
    }
}

public struct PowerSnapshot: Equatable, Sendable {
    public let percent: Int
    public let isOnAC: Bool
    public let isCharging: Bool
    public let timeToEmpty: TimeInterval?
    public init(percent: Int, isOnAC: Bool, isCharging: Bool, timeToEmpty: TimeInterval? = nil) {
        self.percent = percent; self.isOnAC = isOnAC
        self.isCharging = isCharging; self.timeToEmpty = timeToEmpty
    }
}

public struct HotkeyCombo: Equatable, Codable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode; self.modifiers = modifiers
    }
    /// Control + Option + S  (kVK_ANSI_S = 1, controlKey = 0x1000, optionKey = 0x0800)
    public static let defaultCombo = HotkeyCombo(keyCode: 1, modifiers: 0x1000 | 0x0800)
}

public struct PreferencesSnapshot: Equatable, Codable, Sendable {
    public var batteryThreshold: Int
    public var thermalCeiling: ThermalLevel
    public var hotkey: HotkeyCombo
    public var batteryGuardEnabled: Bool
    public var thermalGuardEnabled: Bool
    /// Desarmar cuando se cae la red. Sin internet, lo que justificaba tener la
    /// Mac despierta con la tapa cerrada (descargas, Claude Code) ya no corre.
    public var networkGuardEnabled: Bool
    /// Cuanto tiene que estar caida la red antes de desarmar. Un margen chico
    /// desarma ante un salto de WiFi; uno grande gasta bateria al pedo.
    public var networkGraceSeconds: Int
    /// Animacion de parpado al cerrar y abrir la tapa.
    public var animationsEnabled: Bool

    public static let batteryThresholdRange = 5...50
    public static let networkGraceRange = 0...1800

    public init(
        batteryThreshold: Int = 20,
        thermalCeiling: ThermalLevel = .serious,
        hotkey: HotkeyCombo = .defaultCombo,
        batteryGuardEnabled: Bool = true,
        thermalGuardEnabled: Bool = true,
        networkGuardEnabled: Bool = true,
        networkGraceSeconds: Int = 300,
        animationsEnabled: Bool = true
    ) {
        self.batteryThreshold = batteryThreshold
        self.thermalCeiling = thermalCeiling
        self.hotkey = hotkey
        self.batteryGuardEnabled = batteryGuardEnabled
        self.thermalGuardEnabled = thermalGuardEnabled
        self.networkGuardEnabled = networkGuardEnabled
        self.networkGraceSeconds = networkGraceSeconds
        self.animationsEnabled = animationsEnabled
    }

    /// Corrige valores fuera de rango en vez de fallar: las preferencias vienen
    /// de UserDefaults, que puede tener basura de una version anterior.
    public func clamped() -> PreferencesSnapshot {
        var c = self
        c.batteryThreshold = min(max(batteryThreshold, Self.batteryThresholdRange.lowerBound),
                                 Self.batteryThresholdRange.upperBound)
        if c.thermalCeiling == .nominal { c.thermalCeiling = .fair }
        c.networkGraceSeconds = min(max(networkGraceSeconds, Self.networkGraceRange.lowerBound),
                                    Self.networkGraceRange.upperBound)
        return c
    }
}

public enum HelperInstallState: Equatable, Sendable {
    case notInstalled
    case installedNotRunning
    case ready(protocolVersion: Int)
}
