import AppKit
import Foundation
import AwakeCore

/// Puente entre la ventana SwiftUI y `PreferencesStoring`.
/// No conoce `PowerState` ni ningun otro modulo.
@MainActor
public final class PreferencesViewModel: ObservableObject {

    @Published public var batteryThreshold: Int {
        didSet { let v = batteryThreshold; push { $0.batteryThreshold = v } }
    }
    @Published public var thermalCeiling: ThermalLevel {
        didSet { let v = thermalCeiling; push { $0.thermalCeiling = v } }
    }
    @Published public var batteryGuardEnabled: Bool {
        didSet { let v = batteryGuardEnabled; push { $0.batteryGuardEnabled = v } }
    }
    @Published public var thermalGuardEnabled: Bool {
        didSet { let v = thermalGuardEnabled; push { $0.thermalGuardEnabled = v } }
    }
    @Published public var networkGuardEnabled: Bool {
        didSet { let v = networkGuardEnabled; push { $0.networkGuardEnabled = v } }
    }
    @Published public var networkGraceSeconds: Int {
        didSet { let v = networkGraceSeconds; push { $0.networkGraceSeconds = v } }
    }
    @Published public var animationsEnabled: Bool {
        didSet { let v = animationsEnabled; push { $0.animationsEnabled = v } }
    }
    @Published public private(set) var hotkey: HotkeyCombo
    @Published public private(set) var isCapturingHotkey = false

    /// Techos ofrecidos en la UI. `.nominal` queda fuera a proposito: dispararia siempre.
    public static let selectableCeilings: [ThermalLevel] = [.fair, .serious, .critical]

    /// Margenes ofrecidos en la UI, en segundos.
    public static let selectableGraces = [0, 60, 300, 900, 1800]

    public static func graceLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: return "Al toque"
        case ..<3600: return "\(seconds / 60) min"
        default: return "\(seconds / 3600) h"
        }
    }

    public var hotkeyDisplayString: String { HotkeyDisplay.string(for: hotkey) }

    private let store: PreferencesStoring
    private var applyingRemoteChange = false
    private var observation: Task<Void, Never>?
    private var monitor: Any?

    public init(store: PreferencesStoring) {
        self.store = store
        let snapshot = store.snapshot
        self.batteryThreshold = snapshot.batteryThreshold
        self.thermalCeiling = snapshot.thermalCeiling
        self.batteryGuardEnabled = snapshot.batteryGuardEnabled
        self.thermalGuardEnabled = snapshot.thermalGuardEnabled
        self.networkGuardEnabled = snapshot.networkGuardEnabled
        self.networkGraceSeconds = snapshot.networkGraceSeconds
        self.animationsEnabled = snapshot.animationsEnabled
        self.hotkey = snapshot.hotkey

        let changes = store.changes
        observation = Task { [weak self] in
            for await snapshot in changes {
                guard let self else { return }
                self.absorb(snapshot)
            }
        }
    }

    deinit {
        observation?.cancel()
    }

    // MARK: - Hotkey

    public func beginCapturingHotkey() {
        guard !isCapturingHotkey else { return }
        isCapturingHotkey = true
        // NSEvent no es Sendable, asi que del evento solo cruzan primitivos.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let keyCode = UInt32(event.keyCode)
            let rawFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            var swallow = false
            MainActor.assumeIsolated { swallow = self.handle(keyCode: keyCode, rawFlags: rawFlags) }
            return swallow ? nil : event
        }
    }

    public func cancelCapturingHotkey() {
        isCapturingHotkey = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    public func resetHotkeyToDefault() {
        cancelCapturingHotkey()
        setHotkey(.defaultCombo)
    }

    /// - Returns: `true` si el evento se consume (no llega al resto de la app).
    func handle(keyCode: UInt32, rawFlags: UInt) -> Bool {
        // Escape aborta la captura sin cambiar nada.
        if keyCode == 53 {
            cancelCapturingHotkey()
            return true
        }
        let modifiers = HotkeyDisplay.carbonModifiers(fromCocoaRawValue: rawFlags)
        // Un atajo global sin modificadores secuestraria la tecla en todo el sistema.
        guard modifiers != 0 else { return true }
        cancelCapturingHotkey()
        setHotkey(HotkeyCombo(keyCode: keyCode, modifiers: modifiers))
        return true
    }

    private func setHotkey(_ combo: HotkeyCombo) {
        hotkey = combo
        push { $0.hotkey = combo }
    }

    // MARK: - Sincronizacion con el store

    private func push(_ mutate: @escaping @Sendable (inout PreferencesSnapshot) -> Void) {
        guard !applyingRemoteChange else { return }
        store.update(mutate)
    }

    private func absorb(_ snapshot: PreferencesSnapshot) {
        applyingRemoteChange = true
        if batteryThreshold != snapshot.batteryThreshold { batteryThreshold = snapshot.batteryThreshold }
        if thermalCeiling != snapshot.thermalCeiling { thermalCeiling = snapshot.thermalCeiling }
        if batteryGuardEnabled != snapshot.batteryGuardEnabled { batteryGuardEnabled = snapshot.batteryGuardEnabled }
        if thermalGuardEnabled != snapshot.thermalGuardEnabled { thermalGuardEnabled = snapshot.thermalGuardEnabled }
        if networkGuardEnabled != snapshot.networkGuardEnabled { networkGuardEnabled = snapshot.networkGuardEnabled }
        if networkGraceSeconds != snapshot.networkGraceSeconds { networkGraceSeconds = snapshot.networkGraceSeconds }
        if animationsEnabled != snapshot.animationsEnabled { animationsEnabled = snapshot.animationsEnabled }
        if hotkey != snapshot.hotkey { hotkey = snapshot.hotkey }
        applyingRemoteChange = false
    }
}

extension ThermalLevel {
    /// Etiqueta para el `Picker`. Vive aca porque es texto de UI, no de dominio.
    public var displayName: String {
        switch self {
        case .nominal: return "Normal"
        case .fair: return "Moderada"
        case .serious: return "Alta"
        case .critical: return "Crítica"
        }
    }
}
