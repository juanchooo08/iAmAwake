import Carbon.HIToolbox
import Foundation
import StillOnCore

/// Convierte un `HotkeyCombo` a texto legible ("⌃⌥S").
/// Publico a proposito: lo consume la UI de preferencias.
public enum HotkeyFormatter {
    public static func displayString(for combo: HotkeyCombo) -> String {
        modifiersString(combo.modifiers) + keyString(combo.keyCode)
    }

    /// Modificadores en el orden canonico de macOS: ⌃ ⌥ ⇧ ⌘.
    public static func modifiersString(_ modifiers: UInt32) -> String {
        var out = ""
        if modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { out += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { out += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { out += "⌘" }
        return out
    }

    /// Nombre de la tecla. Para codigos desconocidos devuelve "Tecla \(n)"
    /// en vez de fallar: el combo puede venir de UserDefaults con basura.
    public static func keyString(_ keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Tecla \(keyCode)"
    }

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Espacio",
        50: "`", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
        111: "F12", 113: "F15", 115: "↖", 116: "⇞", 117: "⌦", 118: "F4",
        119: "↘", 120: "F2", 121: "⇟", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

extension HotkeyCombo {
    /// Azucar sobre `HotkeyFormatter.displayString(for:)`.
    public var displayString: String { HotkeyFormatter.displayString(for: self) }
}
