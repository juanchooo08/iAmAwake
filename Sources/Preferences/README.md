# Preferences

Persistencia de las preferencias y su ventana de configuración.

- `UserDefaultsPreferencesStore` — implementa `PreferencesStoring`. Suite
  `dev.local.stillon`. El `UserDefaults` se inyecta por `init`.
- `PreferencesWindowController` / `PreferencesViewModel` — ventana SwiftUI:
  umbral de batería, techo térmico, toggles de cada guarda, captura de hotkey.
- `HotkeyDisplay` — formatea un `HotkeyCombo` como "⌃⌥S".

## Qué asume

- Que `PowerState` escucha `changes` y reevalúa las guardas. La tienda no
  desarma nada por sí sola.
- Que los valores fuera de rango son normales, no excepcionales: vienen de
  UserDefaults, que puede tener basura de una versión anterior. Todo pasa por
  `PreferencesSnapshot.clamped()` antes de guardarse.
- El picker térmico no ofrece `.nominal` a propósito: como techo dispararía
  siempre y la app nunca podría armarse.

## Qué NO maneja

- No valida que el hotkey elegido esté libre. Eso lo descubre el módulo `Hotkey`
  al registrarlo, y falla con `hotkeyRegistrationFailed`.
- No sincroniza entre máquinas (nada de iCloud). Es local a propósito: sin red.
- `HotkeyDisplay` duplica el formateador público de `Hotkey`. Es deliberado: el
  contrato prohíbe que `Preferences` dependa de `Hotkey`. Si molesta, la salida
  limpia es mover el formateador a `StillOnCore`, no cruzar los módulos.

## Cómo se testea

`UserDefaults(suiteName:)` efímero, uno por test, borrado en `deinit`. Nunca se
tocan las preferencias reales del usuario.

```
Scripts/test.sh --filter PreferencesTests
```
