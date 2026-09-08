import Carbon.HIToolbox
import Foundation
import Testing

@testable import Hotkey
import AwakeCore

/// Doble de prueba de la frontera Carbon. Nunca toca el sistema real.
private final class MockCarbonAPI: CarbonHotkeyAPI {
    var installStatus: OSStatus = noErr
    var registerStatus: OSStatus = noErr

    private(set) var installCallCount = 0
    private(set) var registeredIDs: [UInt32] = []
    private(set) var unregisteredIDs: [UInt32] = []
    private(set) var lastKeyCode: UInt32?
    private(set) var lastModifiers: UInt32?
    private var onFire: ((UInt32) -> Void)?

    var liveTokenIDs: [UInt32] {
        registeredIDs.filter { !unregisteredIDs.contains($0) }
    }

    func installHandler(_ onFire: @escaping (UInt32) -> Void) -> OSStatus {
        installCallCount += 1
        guard installStatus == noErr else { return installStatus }
        self.onFire = onFire
        return noErr
    }

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> (status: OSStatus, token: HotkeyToken?) {
        lastKeyCode = keyCode
        lastModifiers = modifiers
        guard registerStatus == noErr else { return (registerStatus, nil) }
        registeredIDs.append(id)
        return (noErr, HotkeyToken(id: id, ref: nil))
    }

    @discardableResult
    func unregister(_ token: HotkeyToken) -> OSStatus {
        unregisteredIDs.append(token.id)
        return noErr
    }

    /// Simula que Carbon despacha el evento del hotkey.
    func simulateFire(id: UInt32) { onFire?(id) }
}

@MainActor
@Suite struct CarbonHotkeyRegistrarTests {
    @Test func testRegisterSuccessPassesComboThroughAndInstallsHandler() throws {
        let api = MockCarbonAPI()
        let sut = CarbonHotkeyRegistrar(api: api)

        try sut.register(.defaultCombo, for: .toggle) {}

        #expect(api.installCallCount == 1)
        #expect(api.lastKeyCode == HotkeyCombo.defaultCombo.keyCode)
        #expect(api.lastModifiers == HotkeyCombo.defaultCombo.modifiers)
        #expect(api.liveTokenIDs.count == 1)
    }

    @Test func testRegisterFailureThrowsWithTheOSStatus() {
        let api = MockCarbonAPI()
        api.registerStatus = OSStatus(eventHotKeyExistsErr)
        let sut = CarbonHotkeyRegistrar(api: api)

        #expect(throws: AwakeError.hotkeyRegistrationFailed(OSStatus(eventHotKeyExistsErr))) {
            try sut.register(.defaultCombo, for: .toggle) {}
        }
        #expect(api.liveTokenIDs.isEmpty)
    }

    @Test func testHandlerInstallFailureThrows() {
        let api = MockCarbonAPI()
        api.installStatus = OSStatus(-50)
        let sut = CarbonHotkeyRegistrar(api: api)

        #expect(throws: AwakeError.hotkeyRegistrationFailed(-50)) {
            try sut.register(.defaultCombo, for: .toggle) {}
        }
        #expect(api.registeredIDs.isEmpty, "no debe registrar si el handler fallo")
    }

    @Test func testFailedRegistrationDoesNotFireTheOldAction() throws {
        let api = MockCarbonAPI()
        let sut = CarbonHotkeyRegistrar(api: api)
        var fired = 0
        try sut.register(.defaultCombo, for: .toggle) { fired += 1 }

        api.registerStatus = OSStatus(eventHotKeyExistsErr)
        #expect(throws: AwakeError.self) {
            try sut.register(HotkeyCombo(keyCode: 2, modifiers: 0), for: .toggle) {}
        }

        // El registro previo se solto antes de intentar el nuevo.
        #expect(api.liveTokenIDs.isEmpty)
        api.simulateFire(id: 1)
        #expect(fired == 0)
    }

    @Test func testDoubleRegisterUnregistersThePreviousOne() throws {
        let api = MockCarbonAPI()
        let sut = CarbonHotkeyRegistrar(api: api)

        try sut.register(.defaultCombo, for: .toggle) {}
        try sut.register(HotkeyCombo(keyCode: 2, modifiers: UInt32(cmdKey)), for: .toggle) {}

        #expect(api.registeredIDs.count == 2)
        #expect(api.unregisteredIDs == [api.registeredIDs[0]])
        #expect(api.liveTokenIDs == [api.registeredIDs[1]])
        // El handler global se instala una sola vez.
        #expect(api.installCallCount == 1)
        #expect(api.lastKeyCode == 2)
    }

    @Test func dosSlotsConvivenSinPisarse() throws {
        let api = MockCarbonAPI()
        let sut = CarbonHotkeyRegistrar(api: api)
        var armados = 0
        var cortinas = 0

        try sut.register(.defaultCombo, for: .toggle) { armados += 1 }
        try sut.register(.defaultCurtainCombo, for: .curtain) { cortinas += 1 }

        #expect(api.liveTokenIDs.count == 2, "registrar el segundo no debe desregistrar el primero")

        api.simulateFire(id: api.registeredIDs[0])
        api.simulateFire(id: api.registeredIDs[1])

        #expect(armados == 1)
        #expect(cortinas == 1)
    }

    @Test func desregistrarUnSlotDejaVivoAlOtro() throws {
        let api = MockCarbonAPI()
        let sut = CarbonHotkeyRegistrar(api: api)
        var cortinas = 0

        try sut.register(.defaultCombo, for: .toggle) {}
        try sut.register(.defaultCurtainCombo, for: .curtain) { cortinas += 1 }
        sut.unregister(.toggle)

        #expect(api.liveTokenIDs == [api.registeredIDs[1]])
        api.simulateFire(id: api.registeredIDs[1])
        #expect(cortinas == 1)
    }

    @Test func testUnregisterIsIdempotent() throws {
        let api = MockCarbonAPI()
        let sut = CarbonHotkeyRegistrar(api: api)

        sut.unregister(.toggle)
        #expect(api.unregisteredIDs.isEmpty)

        try sut.register(.defaultCombo, for: .toggle) {}
        sut.unregister(.toggle)
        sut.unregister(.toggle)
        sut.unregister(.toggle)

        #expect(api.unregisteredIDs.count == 1)
        #expect(api.liveTokenIDs.isEmpty)
    }

    @Test func testFiringInvokesTheAction() throws {
        let api = MockCarbonAPI()
        let sut = CarbonHotkeyRegistrar(api: api)
        var fired = 0
        try sut.register(.defaultCombo, for: .toggle) { fired += 1 }

        api.simulateFire(id: try try #require(api.registeredIDs.first))
        api.simulateFire(id: try try #require(api.registeredIDs.first))
        #expect(fired == 2)
    }

    @Test func testFiringAnUnknownIDIsIgnored() throws {
        let api = MockCarbonAPI()
        let sut = CarbonHotkeyRegistrar(api: api)
        var fired = 0
        try sut.register(.defaultCombo, for: .toggle) { fired += 1 }

        api.simulateFire(id: 999)
        #expect(fired == 0)
    }

    @Test func testAfterReRegisterOnlyTheNewActionRuns() throws {
        let api = MockCarbonAPI()
        let sut = CarbonHotkeyRegistrar(api: api)
        var old = 0
        var new = 0
        try sut.register(.defaultCombo, for: .toggle) { old += 1 }
        try sut.register(HotkeyCombo(keyCode: 2, modifiers: 0), for: .toggle) { new += 1 }

        api.simulateFire(id: api.registeredIDs[0])
        api.simulateFire(id: api.registeredIDs[1])
        #expect(old == 0)
        #expect(new == 1)
    }

    @Test func testFiringAfterUnregisterDoesNothing() throws {
        let api = MockCarbonAPI()
        let sut = CarbonHotkeyRegistrar(api: api)
        var fired = 0
        try sut.register(.defaultCombo, for: .toggle) { fired += 1 }
        let id = try try #require(api.registeredIDs.first)
        sut.unregister(.toggle)

        api.simulateFire(id: id)
        #expect(fired == 0)
    }
}
