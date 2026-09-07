# Hotkey

Implementa `HotkeyRegistering` (`StillOnCore`) con Carbon.

## Piezas

- `CarbonHotkeyRegistrar` — el `HotkeyRegistering` publico.
- `CarbonHotkeyAPI` (internal) — frontera inyectable con Carbon.
  `SystemCarbonHotkeyAPI` es la real; los tests pasan un mock.
- `HotkeyFormatter` — `HotkeyCombo` → texto legible (`"⌃⌥S"`). **Publico**: lo
  usa la UI de preferencias. Tambien esta como `combo.displayString`.

## Por que Carbon y no CGEventTap

`RegisterEventHotKey` no exige permiso de Accesibilidad; `CGEventTap` si. Para
un atajo global fijo, Carbon alcanza y evita pedirle permisos al usuario.

## Contrato

- `register(_:action:)` desregistra lo anterior **primero**, instala el handler
  de eventos una sola vez, y lanza `StillOnError.hotkeyRegistrationFailed(OSStatus)`
  si Carbon rechaza el registro (tipico: `eventHotKeyExistsErr`, la combinacion
  ya la tomo otra app). Nunca falla en silencio.
- `unregister()` es idempotente.
- Default: ⌃⌥S (`HotkeyCombo.defaultCombo`).

## Que asume

- Hay un run loop de Carbon vivo (app con `NSApplication`); el handler se
  instala sobre `GetEventDispatcherTarget()` y dispara en el main thread, por eso
  la accion se invoca con `MainActor.assumeIsolated`.
- El `action` es main-actor-isolated, como pide el protocolo.

## Que NO maneja

- No graba ni persiste la combinacion: eso es de `PreferencesStoring`.
- No captura teclas para "grabar" un atajo nuevo (el capturador vive en la UI de
  preferencias).
- No detecta que otra app libere una combinacion ya tomada; hay que reintentar.
- No conoce `PowerState` ni el estado de armado.

## Como se testea

`Tests/MenuBarTests/CarbonHotkeyRegistrarTests.swift` inyecta un `MockCarbonAPI`
via `@testable import Hotkey`: exito, fallo con `OSStatus` (registro y handler),
doble registro, `unregister()` idempotente y disparo del evento. Nunca se
registra un atajo real del sistema. `HotkeyFormatterTests` cubre el formateo,
incluido un keyCode desconocido.
