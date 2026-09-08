# Hotkey

Implementa `HotkeyRegistering` (`AwakeCore`) con Carbon.

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

- `register(_:for:action:)` desregistra lo que hubiera en ese slot **primero**,
  instala el handler
  de eventos una sola vez, y lanza `AwakeError.hotkeyRegistrationFailed(OSStatus)`
  si Carbon rechaza el registro (tipico: `eventHotKeyExistsErr`, la combinacion
  ya la tomo otra app). Nunca falla en silencio.
- `unregister(_:)` es idempotente; `unregisterAll()` limpia todos los slots.
- Hay un slot por atajo (`HotkeySlot`): `.toggle` arma y desarma, `.curtain`
  reproduce la cortina de cierre. Van por slot y no por combinacion porque
  Carbon identifica los atajos por un entero suyo, y sin llave estable el
  segundo registro pisaba al primero.
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
doble registro, `unregister(_:)` idempotente, convivencia de dos slots y
disparo del evento. Nunca se
registra un atajo real del sistema. `HotkeyFormatterTests` cubre el formateo,
incluido un keyCode desconocido.
