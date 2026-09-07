import StillOnCore
import Foundation
import Testing

@testable import Preferences

/// Cada test corre sobre una suite de `UserDefaults` efimera con nombre unico.
/// Nunca se toca `dev.local.stillon`, la suite real del usuario.
@Suite final class UserDefaultsPreferencesStoreTests {

    /// Una suite por test: cada uno estrena su propia suite de UserDefaults y la
    /// borra al terminar. Nunca se toca la suite real del usuario.
    private let suiteName: String
    private let defaults: UserDefaults

    init() {
        suiteName = "test.stillon.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Defaults

    @Test func testEmptySuiteYieldsDocumentedDefaults() {
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let snapshot = store.snapshot

        #expect(snapshot.batteryThreshold == 20)
        #expect(snapshot.thermalCeiling == .serious)
        #expect(snapshot.hotkey == .defaultCombo)
        #expect(snapshot.batteryGuardEnabled)
        #expect(snapshot.thermalGuardEnabled)
    }

    @Test func testNeverWritesToTheRealSuite() {
        // Guardia explicita: el default de fabrica es la suite real, y los tests
        // no deben usarla nunca.
        #expect(suiteName != UserDefaultsPreferencesStore.suiteName)
    }

    // MARK: - Round-trip

    @Test func testRoundTripsEveryPreference() {
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let combo = HotkeyCombo(keyCode: 11, modifiers: 0x0100 | 0x0200)

        store.update {
            $0.batteryThreshold = 33
            $0.thermalCeiling = .critical
            $0.hotkey = combo
            $0.batteryGuardEnabled = false
            $0.thermalGuardEnabled = false
        }

        let snapshot = store.snapshot
        #expect(snapshot.batteryThreshold == 33)
        #expect(snapshot.thermalCeiling == .critical)
        #expect(snapshot.hotkey == combo)
        #expect(!(snapshot.batteryGuardEnabled))
        #expect(!(snapshot.thermalGuardEnabled))
    }

    @Test func testPersistsAcrossInstancesOnTheSameSuite() {
        let combo = HotkeyCombo(keyCode: 46, modifiers: 0x1000)
        let first = UserDefaultsPreferencesStore(defaults: defaults)
        first.update {
            $0.batteryThreshold = 41
            $0.thermalCeiling = .fair
            $0.hotkey = combo
            $0.batteryGuardEnabled = false
            $0.thermalGuardEnabled = true
        }
        first.finish()

        // Simula un reinicio de la app: instancia nueva, misma suite.
        let second = UserDefaultsPreferencesStore(defaults: defaults)
        let snapshot = second.snapshot
        #expect(snapshot.batteryThreshold == 41)
        #expect(snapshot.thermalCeiling == .fair)
        #expect(snapshot.hotkey == combo)
        #expect(!(snapshot.batteryGuardEnabled))
        #expect(snapshot.thermalGuardEnabled)
    }

    // MARK: - Clamping

    @Test func testClampsThresholdBelowRange() {
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        store.update { $0.batteryThreshold = 0 }
        #expect(store.snapshot.batteryThreshold == 5)
    }

    @Test func testClampsNegativeThreshold() {
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        store.update { $0.batteryThreshold = -17 }
        #expect(store.snapshot.batteryThreshold == 5)
    }

    @Test func testClampsThresholdAboveRange() {
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        store.update { $0.batteryThreshold = 100 }
        #expect(store.snapshot.batteryThreshold == 50)
    }

    @Test func testNominalCeilingIsCorrectedToFair() {
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        store.update { $0.thermalCeiling = .nominal }
        #expect(store.snapshot.thermalCeiling == .fair)
    }

    @Test func testClampedValuesAreWhatGetsPersisted() {
        let first = UserDefaultsPreferencesStore(defaults: defaults)
        first.update {
            $0.batteryThreshold = 999
            $0.thermalCeiling = .nominal
        }
        first.finish()

        let second = UserDefaultsPreferencesStore(defaults: defaults)
        #expect(second.snapshot.batteryThreshold == 50)
        #expect(second.snapshot.thermalCeiling == .fair)
    }

    // MARK: - Datos corruptos

    @Test func testCorruptStringValuesFallBackToDefaults() {
        defaults.set("banana", forKey: UserDefaultsPreferencesStore.Key.batteryThreshold)
        defaults.set("caliente", forKey: UserDefaultsPreferencesStore.Key.thermalCeiling)
        defaults.set("no", forKey: UserDefaultsPreferencesStore.Key.batteryGuardEnabled)

        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let snapshot = store.snapshot
        #expect(snapshot.batteryThreshold == 20)
        #expect(snapshot.thermalCeiling == .serious)
        #expect(snapshot.batteryGuardEnabled)
    }

    @Test func testOutOfRangeStoredValuesAreClampedOnLoad() {
        defaults.set(-4, forKey: UserDefaultsPreferencesStore.Key.batteryThreshold)
        defaults.set(0, forKey: UserDefaultsPreferencesStore.Key.thermalCeiling)  // .nominal

        let store = UserDefaultsPreferencesStore(defaults: defaults)
        #expect(store.snapshot.batteryThreshold == 5)
        #expect(store.snapshot.thermalCeiling == .fair)
    }

    @Test func testUnknownThermalRawValueFallsBackToDefault() {
        defaults.set(99, forKey: UserDefaultsPreferencesStore.Key.thermalCeiling)
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        #expect(store.snapshot.thermalCeiling == .serious)
    }

    @Test func testCorruptHotkeyFallsBackToDefaultCombo() {
        defaults.set(["nope": 1], forKey: UserDefaultsPreferencesStore.Key.hotkeyKeyCode)
        defaults.set(-1, forKey: UserDefaultsPreferencesStore.Key.hotkeyModifiers)

        let store = UserDefaultsPreferencesStore(defaults: defaults)
        #expect(store.snapshot.hotkey == .defaultCombo)
    }

    @Test func testHalfWrittenHotkeyFallsBackToDefaultCombo() {
        // Solo el keyCode, sin modificadores: version vieja del formato.
        defaults.set(12, forKey: UserDefaultsPreferencesStore.Key.hotkeyKeyCode)
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        #expect(store.snapshot.hotkey == .defaultCombo)
    }

    @Test func testBlobUnderEveryKeyDoesNotCrash() {
        let blob = Data([0xDE, 0xAD, 0xBE, 0xEF])
        for key in [
            UserDefaultsPreferencesStore.Key.batteryThreshold,
            UserDefaultsPreferencesStore.Key.thermalCeiling,
            UserDefaultsPreferencesStore.Key.hotkeyKeyCode,
            UserDefaultsPreferencesStore.Key.hotkeyModifiers,
            UserDefaultsPreferencesStore.Key.batteryGuardEnabled,
            UserDefaultsPreferencesStore.Key.thermalGuardEnabled,
        ] {
            defaults.set(blob, forKey: key)
        }

        let store = UserDefaultsPreferencesStore(defaults: defaults)
        #expect(store.snapshot == PreferencesSnapshot())
    }

    // MARK: - changes

    @Test func testChangesEmitsOnEveryUpdate() async {
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        var iterator = store.changes.makeAsyncIterator()

        store.update { $0.batteryThreshold = 30 }
        let first = await iterator.next()
        #expect(first?.batteryThreshold == 30)

        store.update { $0.batteryThreshold = 45 }
        let second = await iterator.next()
        #expect(second?.batteryThreshold == 45)
    }

    @Test func testChangesEmitsTheClampedValue() async {
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        var iterator = store.changes.makeAsyncIterator()

        store.update { $0.batteryThreshold = 300 }
        let emitted = await iterator.next()
        #expect(emitted?.batteryThreshold == 50)
    }

    @Test func testTwoConsumersBothReceiveEveryEvent() async {
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        var a = store.changes.makeAsyncIterator()
        var b = store.changes.makeAsyncIterator()

        store.update { $0.batteryThreshold = 25 }
        store.update { $0.thermalCeiling = .critical }

        let a1 = await a.next()
        let a2 = await a.next()
        let b1 = await b.next()
        let b2 = await b.next()

        #expect(a1?.batteryThreshold == 25)
        #expect(b1?.batteryThreshold == 25)
        #expect(a2?.thermalCeiling == .critical)
        #expect(b2?.thermalCeiling == .critical)
    }

    @Test func testFinishTerminatesOpenStreams() async {
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        var iterator = store.changes.makeAsyncIterator()
        store.finish()
        let next = await iterator.next()
        #expect(next == nil)
    }

    // MARK: - Formateo de hotkey (helper local, sin depender del modulo Hotkey)

    @Test func testHotkeyDisplayFormatsDefaultCombo() {
        #expect(HotkeyDisplay.string(for: .defaultCombo) == "⌃⌥S")
    }

    @Test func testHotkeyDisplayFormatsAllModifiers() {
        let combo = HotkeyCombo(keyCode: 0, modifiers: 0x1000 | 0x0800 | 0x0200 | 0x0100)
        #expect(HotkeyDisplay.string(for: combo) == "⌃⌥⇧⌘A")
    }

    @Test func testCarbonModifiersFromCocoaFlags() {
        let cocoaControl: UInt = 1 << 18
        let cocoaOption: UInt = 1 << 19
        let raw = cocoaControl | cocoaOption
        #expect(HotkeyDisplay.carbonModifiers(fromCocoaRawValue: raw) == 0x1000 | 0x0800)
    }
}
