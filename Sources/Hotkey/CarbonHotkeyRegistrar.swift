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
    private var token: HotkeyToken?
    private var action: (@MainActor () -> Void)?
    private var handlerInstalled = false
    private var nextID: UInt32 = 1

    public convenience init() {
        self.init(api: SystemCarbonHotkeyAPI())
    }

    init(api: CarbonHotkeyAPI) {
        self.api = api
    }

    deinit {
        if let token { api.unregister(token) }
    }

    public func register(_ combo: HotkeyCombo, action: @escaping @MainActor () -> Void) throws {
        unregister()

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
        token = newToken
        self.action = action
    }

    /// Idempotente: llamarlo sin nada registrado no hace nada.
    public func unregister() {
        guard let token else { return }
        api.unregister(token)
        self.token = nil
        self.action = nil
    }

    /// Se invoca desde el handler de Carbon, que corre en el main run loop.
    private func fire(_ firedID: UInt32) {
        guard let token, token.id == firedID, let action else { return }
        MainActor.assumeIsolated { action() }
    }
}
