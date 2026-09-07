import Carbon.HIToolbox
import Foundation

/// Token opaco de un hotkey registrado. Los tests crean tokens sin `EventHotKeyRef`.
final class HotkeyToken {
    let id: UInt32
    let ref: EventHotKeyRef?
    init(id: UInt32, ref: EventHotKeyRef?) {
        self.id = id
        self.ref = ref
    }
}

/// Frontera inyectable con Carbon. Existe solo para poder testear
/// `CarbonHotkeyRegistrar` sin registrar atajos reales del sistema.
protocol CarbonHotkeyAPI: AnyObject {
    /// Instala el handler de eventos una sola vez. Devuelve `noErr` si ya estaba.
    func installHandler(_ onFire: @escaping (UInt32) -> Void) -> OSStatus
    /// Devuelve `noErr` + token en exito; el `OSStatus` de Carbon y `nil` en fallo.
    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> (status: OSStatus, token: HotkeyToken?)
    @discardableResult
    func unregister(_ token: HotkeyToken) -> OSStatus
}

/// Implementacion real: `InstallEventHandler` + `RegisterEventHotKey`.
/// Se usa Carbon y no `CGEventTap` porque Carbon no exige permiso de Accesibilidad.
final class SystemCarbonHotkeyAPI: CarbonHotkeyAPI {
    /// 'STON'
    private static let signature: OSType = 0x5354_4F4E

    private var handlerRef: EventHandlerRef?
    fileprivate var onFire: ((UInt32) -> Void)?

    init() {}

    deinit {
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    func installHandler(_ onFire: @escaping (UInt32) -> Void) -> OSStatus {
        self.onFire = onFire
        guard handlerRef == nil else { return noErr }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        return InstallEventHandler(
            GetEventDispatcherTarget(),
            hotkeyEventHandler,
            1,
            &spec,
            selfPtr,
            &handlerRef
        )
    }

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> (status: OSStatus, token: HotkeyToken?) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            return (status == noErr ? OSStatus(eventInternalErr) : status, nil)
        }
        return (noErr, HotkeyToken(id: id, ref: ref))
    }

    @discardableResult
    func unregister(_ token: HotkeyToken) -> OSStatus {
        guard let ref = token.ref else { return noErr }
        return UnregisterEventHotKey(ref)
    }
}

/// Callback de C: sin capturas, para poder convertirse a `@convention(c)`.
private let hotkeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let api = Unmanaged<SystemCarbonHotkeyAPI>.fromOpaque(userData).takeUnretainedValue()
    api.onFire?(hotKeyID.id)
    return noErr
}
