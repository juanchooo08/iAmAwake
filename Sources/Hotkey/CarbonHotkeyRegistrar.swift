import Carbon.HIToolbox
import Foundation
import AwakeCore

/// `HotkeyRegistering` sobre Carbon.
///
/// - Registrar dos veces desregistra la combinacion anterior primero.
/// - Si Carbon rechaza el registro (combinacion tomada por otra app) lanza
///   `AwakeError.hotkeyRegistrationFailed(OSStatus)`. Nunca falla en silencio.
public final class CarbonHotkeyRegistrar: HotkeyRegistering {

    private let api: CarbonHotkeyAPI
    /// Token y accion van por separado a proposito: la accion esta aislada al
    /// MainActor y guardarla dentro de un struct junto al token hace que
    /// sacarla del diccionario cuente como mandarla a otro aislamiento.
    private var tokens: [HotkeySlot: HotkeyToken] = [:]
    private var actions: [HotkeySlot: @MainActor () -> Void] = [:]
    private var handlerInstalled = false
    private var nextID: UInt32 = 1

    public convenience init() {
        self.init(api: SystemCarbonHotkeyAPI())
    }

    init(api: CarbonHotkeyAPI) {
        self.api = api
    }

    deinit {
        for token in tokens.values { api.unregister(token) }
    }

    public func register(
        _ combo: HotkeyCombo,
        for slot: HotkeySlot,
        action: @escaping @MainActor () -> Void
    ) throws {
        unregister(slot)

        if !handlerInstalled {
            let status = api.installHandler { [weak self] firedID in
                self?.fire(firedID)
            }
            guard status == noErr else {
                throw AwakeError.hotkeyRegistrationFailed(status)
            }
            handlerInstalled = true
        }

        let id = nextID
        nextID &+= 1

        let result = api.register(keyCode: combo.keyCode, modifiers: combo.modifiers, id: id)
        guard result.status == noErr, let newToken = result.token else {
            throw AwakeError.hotkeyRegistrationFailed(result.status)
        }
        tokens[slot] = newToken
        actions[slot] = action
    }

    /// Idempotente: llamarlo sin nada registrado no hace nada.
    public func unregister(_ slot: HotkeySlot) {
        guard let token = tokens.removeValue(forKey: slot) else { return }
        actions[slot] = nil
        api.unregister(token)
    }

    public func unregisterAll() {
        for slot in tokens.keys { unregister(slot) }
    }

    /// Se invoca desde el handler de Carbon, que corre en el main run loop.
    private func fire(_ firedID: UInt32) {
        guard let slot = tokens.first(where: { $0.value.id == firedID })?.key,
              let action = actions[slot] else { return }
        MainActor.assumeIsolated { action() }
    }
}
