import Foundation
import StillOnCore

/// Textos legibles para los tipos de `StillOnCore`. Vive aca (y no en Core)
/// porque Core no conoce la capa de presentacion.
public enum StatusText {
    public static func describe(_ level: ThermalLevel) -> String {
        switch level {
        case .nominal: return "normal"
        case .fair: return "elevada"
        case .serious: return "alta"
        case .critical: return "critica"
        }
    }

    public static func describe(_ error: StillOnError) -> String {
        switch error {
        case .assertionFailed(let code):
            return "no se pudo crear la power assertion (codigo \(code))"
        case .helperUnavailable:
            return "el daemon stillond no esta instalado o no responde"
        case .helperRefused(let message):
            return "el daemon rechazo el pedido: \(message)"
        case .helperVersionMismatch(let expected, let got):
            return "version de protocolo incompatible (esperaba \(expected), llego \(got))"
        case .hotkeyRegistrationFailed(let status):
            return "no se pudo registrar el atajo de teclado (OSStatus \(status))"
        case .notificationPermissionDenied:
            return "no hay permiso para mostrar notificaciones"
        }
    }
}

/// Logica pura de presentacion de la barra de menu: mapea un `ArmState` a los
/// textos y al simbolo que hay que mostrar. Sin AppKit a proposito, para poder
/// testear las cinco presentaciones sin instanciar un `NSStatusItem`.
public struct StatusPresentation: Equatable, Sendable {
    /// Nombre de SF Symbol, imagen template.
    public let symbolName: String
    /// `accessibilityDescription` de la imagen.
    public let accessibilityDescription: String
    /// Tooltip del boton de la barra de menu.
    public let tooltip: String
    /// Titulo del item de menu que arma/desarma.
    public let toggleTitle: String
    /// Linea de estado (item deshabilitado) que describe la situacion actual.
    public let statusLine: String

    public init(
        symbolName: String,
        accessibilityDescription: String,
        tooltip: String,
        toggleTitle: String,
        statusLine: String
    ) {
        self.symbolName = symbolName
        self.accessibilityDescription = accessibilityDescription
        self.tooltip = tooltip
        self.toggleTitle = toggleTitle
        self.statusLine = statusLine
    }

    public init(state: ArmState) {
        switch state {
        case .disarmed:
            self.init(
                symbolName: "moon.zzz",
                accessibilityDescription: "Desarmado",
                tooltip: "Desarmado",
                toggleTitle: "Armar",
                statusLine: "Desarmado — la Mac duerme normalmente"
            )

        case .armed:
            self.init(
                symbolName: "bolt.fill",
                accessibilityDescription: "Armado — la Mac no dormirá",
                tooltip: "Armado — la Mac no dormirá",
                toggleTitle: "Desarmar",
                statusLine: "Armado — la Mac no dormirá"
            )

        case .blockedLowBattery(let percent):
            self.init(
                symbolName: "battery.25",
                accessibilityDescription: "Desarmado por batería baja (\(percent) %)",
                tooltip: "Desarmado por batería baja (\(percent) %)",
                toggleTitle: "Armar",
                statusLine: "Bloqueado por batería baja (\(percent) %)"
            )

        case .blockedThermal(let level):
            self.init(
                symbolName: "thermometer.high",
                accessibilityDescription: "Desarmado por temperatura",
                tooltip: "Desarmado por temperatura (\(StatusText.describe(level)))",
                toggleTitle: "Armar",
                statusLine: "Bloqueado por temperatura \(StatusText.describe(level))"
            )

        case .failed(let error):
            let detail = StatusText.describe(error)
            self.init(
                symbolName: "exclamationmark.triangle",
                accessibilityDescription: "Error: \(detail)",
                tooltip: "Error: \(detail)",
                toggleTitle: "Armar",
                statusLine: "Error: \(detail)"
            )
        }
    }
}
