import Carbon.HIToolbox
import Foundation
import Testing

@testable import Hotkey
import StillOnCore

@Suite struct HotkeyFormatterTests {
    @Test func testDefaultComboIsControlOptionS() {
        #expect(HotkeyFormatter.displayString(for: .defaultCombo) == "⌃⌥S")
        #expect(HotkeyCombo.defaultCombo.displayString == "⌃⌥S")
    }

    @Test func testModifierOrderIsCanonical() {
        let all = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        #expect(HotkeyFormatter.modifiersString(all) == "⌃⌥⇧⌘")
    }

    @Test func testEachModifierAlone() {
        #expect(HotkeyFormatter.modifiersString(UInt32(controlKey)) == "⌃")
        #expect(HotkeyFormatter.modifiersString(UInt32(optionKey)) == "⌥")
        #expect(HotkeyFormatter.modifiersString(UInt32(shiftKey)) == "⇧")
        #expect(HotkeyFormatter.modifiersString(UInt32(cmdKey)) == "⌘")
        #expect(HotkeyFormatter.modifiersString(0) == "")
    }

    @Test func testCommandShiftCombo() {
        let combo = HotkeyCombo(keyCode: 49, modifiers: UInt32(cmdKey | shiftKey))
        #expect(combo.displayString == "⇧⌘Espacio")
    }

    @Test func testComboWithoutModifiers() {
        #expect(HotkeyCombo(keyCode: 122, modifiers: 0).displayString == "F1")
    }

    @Test func testKnownKeyNames() {
        #expect(HotkeyFormatter.keyString(0) == "A")
        #expect(HotkeyFormatter.keyString(1) == "S")
        #expect(HotkeyFormatter.keyString(49) == "Espacio")
        #expect(HotkeyFormatter.keyString(53) == "⎋")
        #expect(HotkeyFormatter.keyString(126) == "↑")
    }

    /// Un combo corrupto en UserDefaults no debe romper la UI de preferencias.
    @Test func testUnknownKeyCodeFallsBackInsteadOfCrashing() {
        #expect(HotkeyFormatter.keyString(9999) == "Tecla 9999")
        #expect(HotkeyCombo(keyCode: 9999, modifiers: UInt32(cmdKey)).displayString == "⌘Tecla 9999")
    }
}
