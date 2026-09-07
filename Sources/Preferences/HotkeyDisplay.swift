import Foundation
import AwakeCore

/// Formateo local de `HotkeyCombo` ("⌃⌥S").
///
/// El modulo `Hotkey` expone un helper equivalente, pero este target NO depende de
/// el (regla de arquitectura: ningun modulo de implementacion depende de otro).
/// Por eso esta duplicado a proposito.
public enum HotkeyDisplay {

    // Modificadores Carbon, sin importar Carbon.
    public static let controlKey: UInt32 = 0x1000
    public static let optionKey: UInt32 = 0x0800
    public static let shiftKey: UInt32 = 0x0200
    public static let cmdKey: UInt32 = 0x0100

    public static func string(for combo: HotkeyCombo) -> String {
        var out = ""
        if combo.modifiers & controlKey != 0 { out += "⌃" }
        if combo.modifiers & optionKey != 0 { out += "⌥" }
        if combo.modifiers & shiftKey != 0 { out += "⇧" }
        if combo.modifiers & cmdKey != 0 { out += "⌘" }
        out += keyName(combo.keyCode)
        return out
    }

    public static func keyName(_ keyCode: UInt32) -> String {
        if let named = specialKeys[keyCode] { return named }
        if let letter = ansiKeys[keyCode] { return letter }
        return "#\(keyCode)"
    }

    private static let ansiKeys: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
        9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
    ]

    private static let specialKeys: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// Traduce los modificadores de `NSEvent` (`NSEvent.ModifierFlags.rawValue`)
    /// a la mascara Carbon que espera `RegisterEventHotKey`.
    public static func carbonModifiers(fromCocoaRawValue raw: UInt) -> UInt32 {
        // Constantes de NSEvent.ModifierFlags, sin importar AppKit.
        let cocoaShift: UInt = 1 << 17
        let cocoaControl: UInt = 1 << 18
        let cocoaOption: UInt = 1 << 19
        let cocoaCommand: UInt = 1 << 20

        var out: UInt32 = 0
        if raw & cocoaControl != 0 { out |= controlKey }
        if raw & cocoaOption != 0 { out |= optionKey }
        if raw & cocoaShift != 0 { out |= shiftKey }
        if raw & cocoaCommand != 0 { out |= cmdKey }
        return out
    }
}
