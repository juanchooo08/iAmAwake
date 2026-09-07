import Foundation
import IOKit.ps

/// Lectura de bateria **propia del daemon**.
///
/// El daemon no le cree a la app sobre el nivel de bateria: la app puede estar
/// colgada, mintiendo o muerta. Este es el piso de seguridad independiente
/// (`Wire.hardBatteryFloor`), no la guarda configurable del usuario.
struct BatterySample: Equatable {
    let percent: Int
    let isOnAC: Bool
}

enum BatteryReader {
    /// `nil` si la maquina no tiene bateria interna (un Mac de escritorio) o si
    /// IOKit no devuelve nada. En ese caso no hay piso que aplicar.
    static func current() -> BatterySample? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 0
            let percent = maximum > 0
                ? Int((Double(current) / Double(maximum) * 100).rounded())
                : current
            let state = description[kIOPSPowerSourceStateKey] as? String
            return BatterySample(percent: percent, isOnAC: state == kIOPSACPowerValue)
        }
        return nil
    }

    /// `true` si estamos con bateria y en o por debajo del piso duro.
    static func isBelowHardFloor(_ sample: BatterySample?, floor: Int) -> Bool {
        guard let sample else { return false }
        return !sample.isOnAC && sample.percent <= floor
    }
}
