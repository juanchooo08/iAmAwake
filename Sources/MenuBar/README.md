# MenuBar

Implementa `StatusPresenting` (`AwakeCore`) con un `NSStatusItem`.

## Piezas

- `StatusPresentation` — struct puro, **sin AppKit**. `init(state: ArmState)` mapea
  cada estado a `symbolName` / `accessibilityDescription` / `tooltip` /
  `toggleTitle` / `statusLine`. Toda la logica de presentacion vive aca.
- `StatusItemController` — `@MainActor`, envuelve `NSStatusItem` y el `NSMenu`.
  Solo traduce `StatusPresentation` a AppKit.
- `StatusText` — textos legibles para `ThermalLevel` y `AwakeError`.

## Los cinco estados

| `ArmState` | SF Symbol | Toggle |
|---|---|---|
| `.disarmed` | `eye.slash` | Armar |
| `.armed` | `eye` | Desarmar |
| `.blockedLowBattery(p)` | `battery.25` | Armar |
| `.blockedThermal(l)` | `thermometer.high` | Armar |
| `.failed(e)` | `exclamationmark.triangle` | Armar |

Imagenes template, con `accessibilityDescription` en todas.

## Menu

toggle · linea de estado (deshabilitada) · separador · `Ver la cortina` ·
separador · `Preferencias…` (⌘,) · separador · `Salir` (⌘Q).

`Ver la cortina` muestra su atajo en el titulo y no en `keyEquivalent`: es un
atajo global de Carbon, y un `keyEquivalent` solo dispara con la app al frente. `menu.autoenablesItems = false` para que la linea de
estado se quede gris.

## Que asume

- Corre en el main actor y con AppKit ya inicializado (`NSApplication` viva).
- Los SF Symbols de la tabla existen en macOS 14+.
- Alguien externo llama `render(_:)` cada vez que cambia el estado; el modulo no
  observa nada por su cuenta.

## Que NO maneja

- No conoce `PowerState`, `PreferencesStoring` ni ningun otro modulo. Su unica
  salida son `onToggle`, `onOpenPreferences` y `onQuit`.
- No decide si se puede armar; solo dibuja el estado que le pasan.
- No abre la ventana de preferencias ni termina la app: invoca el closure.
- No persiste nada.

## Como se testea

`Tests/MenuBarTests/StatusPresentationTests.swift` cubre `StatusPresentation`
sin instanciar un `NSStatusItem`: los cinco estados, que ningun par comparte
simbolo/tooltip/linea de estado, que el porcentaje y el error viajan al texto, y
que ningun campo queda vacio. `StatusItemController` no se testea
automaticamente: crear un `NSStatusItem` toca la barra de menu real.
