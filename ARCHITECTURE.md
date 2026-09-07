# iAmAwake — Contrato de Arquitectura (v1)

Estado: **propuesta, pendiente de aprobacion**. Ningun modulo se implementa hasta
que este documento este aprobado.

---

## 0. Hecho verificado en Fase 0 que condiciona todo el diseño

Las power assertions de IOKit **no** evitan el sueño al cerrar la tapa en este
hardware (MacBookAir10,1 / M1 / macOS 26.6.2). Medido: durmio a los 22 s con
`PreventUserIdleSystemSleep` + `PreventSystemSleep` + `NoDisplaySleep` activas.

Lo unico que funciona es poner `DisableClamshellSleep` en `IOPMrootDomain`, que
es lo que hace `pmset -a disablesleep 1`. Medido: 296 s de heartbeat continuo,
tapa cerrada, con bateria, sin perifericos.

Esa escritura exige root. Por eso la arquitectura tiene **dos procesos**:

```
  iAmAwake.app  (tu usuario, sin privilegios)          iamawaked  (root, LaunchDaemon)
  ├─ menu bar, hotkey, guardas, preferencias    <──>  ├─ toggle DisableClamshellSleep
  └─ habla por socket Unix 0600                 JSON  └─ dead man's switch
```

### Dead man's switch (no negociable)

Con `disablesleep=1` la Mac no duerme **nunca**. Si `iAmAwake.app` crashea o la
matas sin desarmar, la bateria se drena hasta 0 con la tapa cerrada.

Por lo tanto: el daemon revierte a `disablesleep=0` cuando ocurre cualquiera de
estas, sin depender de la app:

1. No recibe heartbeat por > `heartbeatTimeout` (default 30 s).
2. El socket del cliente se cierra (la app murio).
3. El daemon recibe `SIGTERM` / `SIGINT` (handler de shutdown).
4. Lee `IOPowerSources` por su cuenta y ve bateria <= `hardFloor` (default 5 %),
   independientemente de lo que diga la app. Es un piso de seguridad, no la
   guarda configurable del usuario.

---

## 1. Fuente unica de verdad

`PowerState`, en el modulo `AwakeCore`. Es un `@MainActor final class` que
conforma `ObservableObject`. Elegido sobre `actor` porque `NSStatusItem` y el
hotkey son main-thread-only; las guardas empujan hacia el con `Task { @MainActor }`.

**Nadie mas muta el estado.** Los modulos solo:
- reciben el estado ya calculado (`StatusPresenting.render`), o
- le mandan intenciones a `PowerState` (`requestArm`, `requestDisarm`, `report`).

`PowerState` no conoce ninguna implementacion concreta: recibe todo por
protocolo en el init. Eso es lo que hace testeable cada modulo por separado.

```swift
@MainActor
public final class PowerState: ObservableObject {
    @Published public private(set) var status: ArmState
    @Published public private(set) var lastError: AwakeError?

    public init(
        inhibitor: SleepInhibiting,
        lid: LidSleepControlling,
        guards: [Guarding],
        preferences: PreferencesStoring,
        notifier: Notifying,
        clock: ClockProviding
    )

    public func requestArm() async
    public func requestDisarm(reason: DisarmReason) async
    public func report(_ verdict: GuardVerdict, from: GuardID) async
    public func applyPreferences(_ snapshot: PreferencesSnapshot) async
}
```

### Maquina de estados

```
        requestArm() y todas las guardas ok
disarmed ─────────────────────────────────> armed
   ^                                          │
   │  requestDisarm(.user)                    │ mustDisarm(.lowBattery)
   │<─────────────────────────────────────────┤ mustDisarm(.thermal)
   │                                          │ assertionFailure
   │                                          v
   └──────────────────────────────── blockedLowBattery / blockedThermal / failed
              la guarda vuelve a ok  (no rearma sola: requiere accion del usuario)
```

Decision explicita: **no rearma automaticamente** cuando la condicion se
normaliza. Rearmar solo tras un corte termico produce ciclos. El usuario decide.

---

## 2. Tipos compartidos (`AwakeCore`)

```swift
public enum ArmState: Equatable {
    case disarmed
    case armed
    case blockedLowBattery(percent: Int)
    case blockedThermal(ThermalLevel)
    case failed(AwakeError)
}

public enum DisarmReason: Equatable {
    case user
    case lowBattery(percent: Int)
    case thermal(ThermalLevel)
    case assertionFailure(AwakeError)
    case appTerminating
}

public enum ThermalLevel: Int, Comparable, Codable { case nominal, fair, serious, critical }

public enum GuardID: String, Codable { case battery, thermal }

public enum GuardVerdict: Equatable {
    case ok
    case mustDisarm(DisarmReason)
    case mustNotArm(DisarmReason)
}

public struct PowerSnapshot: Equatable {
    public let percent: Int
    public let isOnAC: Bool
    public let isCharging: Bool
    public let timeToEmpty: TimeInterval?
}

public struct HotkeyCombo: Equatable, Codable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public static let defaultCombo: HotkeyCombo  // Control + Option + S
}

public struct PreferencesSnapshot: Equatable, Codable {
    public var batteryThreshold: Int      // 5...50, default 20
    public var thermalCeiling: ThermalLevel   // default .serious
    public var hotkey: HotkeyCombo
    public var batteryGuardEnabled: Bool  // default true
    public var thermalGuardEnabled: Bool  // default true
}

public enum AwakeError: Error, Equatable {
    case assertionFailed(kern_return_t)
    case helperUnavailable          // daemon no instalado o no corriendo
    case helperRefused(String)      // daemon respondio error
    case helperVersionMismatch(expected: Int, got: Int)
    case hotkeyRegistrationFailed(OSStatus)
    case notificationPermissionDenied
}
```

---

## 3. Interfaces por modulo

Cada protocolo vive en `AwakeCore`. Cada implementacion vive en su propio
target y **no importa ningun otro target de implementacion**.

### a) MenuBarModule → `StatusPresenting`

```swift
@MainActor
public protocol StatusPresenting: AnyObject {
    func render(_ state: ArmState)
    var onToggle: (() -> Void)? { get set }
    var onOpenPreferences: (() -> Void)? { get set }
    var onQuit: (() -> Void)? { get set }
}
```

Cuatro iconos distintos + uno de error (req. 1). SF Symbols, template images:

| Estado | Simbolo | Descripcion accesible |
|---|---|---|
| `disarmed` | `moon.zzz` | "Desarmado" |
| `armed` | `bolt.fill` | "Armado — la Mac no dormira" |
| `blockedLowBattery` | `battery.25` | "Desarmado por bateria baja (N %)" |
| `blockedThermal` | `thermometer.high` | "Desarmado por temperatura" |
| `failed` | `exclamationmark.triangle` | "Error: ..." |

### b) PowerAssertionModule → `SleepInhibiting`

```swift
public protocol SleepInhibiting: AnyObject {
    var isEngaged: Bool { get }
    func engage() async throws     // lanza AwakeError.assertionFailed
    func disengage() async
}
```

Cubre display + idle sleep. **No** cubre el cierre de tapa (ver seccion 0); eso
es responsabilidad de `LidSleepControlling`. Se arman las dos juntas.
Fallback a `caffeinate` si `IOPMAssertionCreateWithName` falla.

### c) HelperClient → `LidSleepControlling`

```swift
public protocol LidSleepControlling: AnyObject {
    var installState: HelperInstallState { get async }
    func setClamshellSleepDisabled(_ disabled: Bool) async throws
    func heartbeat() async throws
}

public enum HelperInstallState: Equatable {
    case notInstalled
    case installedNotRunning
    case ready(protocolVersion: Int)
}
```

Protocolo de cable: JSON delimitado por `\n` sobre `/var/run/iamawaked.sock`
(0600, owner = tu uid). Comandos: `{"cmd":"arm"}`, `{"cmd":"disarm"}`,
`{"cmd":"ping"}`, `{"cmd":"status"}`. Respuesta: `{"ok":true,...}` o
`{"ok":false,"error":"..."}`.

La app manda `heartbeat()` cada 10 s mientras esta armada.

### d) HotkeyModule → `HotkeyRegistering`

```swift
public protocol HotkeyRegistering: AnyObject {
    func register(_ combo: HotkeyCombo, action: @escaping @MainActor () -> Void) throws
    func unregister()
}
```

Carbon `RegisterEventHotKey` (no requiere permiso de Accesibilidad, a diferencia
de `CGEventTap`). Default ⌃⌥S.

### e) BatteryGuard y ThermalGuard → `Guarding`

Mismo protocolo, dos implementaciones. Comparten patron: leen una fuente,
comparan contra un umbral, emiten veredicto.

```swift
public protocol Guarding: AnyObject {
    var identifier: GuardID { get }
    func start(onVerdict: @escaping (GuardVerdict) -> Void)
    func stop()
    func apply(_ prefs: PreferencesSnapshot)
}
```

Dependencias inyectadas, para poder mockearlas sin tocar macOS real:

```swift
public protocol PowerSourceReading: AnyObject {
    var snapshot: PowerSnapshot { get }
    func startMonitoring(onChange: @escaping (PowerSnapshot) -> Void)
    func stopMonitoring()
}

public protocol ThermalReading: AnyObject {
    var level: ThermalLevel { get }
    func startMonitoring(onChange: @escaping (ThermalLevel) -> Void)
    func stopMonitoring()
}
```

- `BatteryGuard`: `IOPSNotificationCreateRunLoopSource` + `IOPSCopyPowerSourcesInfo`.
  Con cargador conectado no desarma nunca (no tiene sentido).
- `ThermalGuard`: `ProcessInfo.processInfo.thermalState` +
  `.thermalStateDidChangeNotification`. **Nota honesta:** macOS no expone grados
  Celsius por API publica; solo estos 4 niveles. Leer el SMC requiere claves no
  documentadas y no lo hacemos en v1. Se documenta en el README.

### f) PreferencesModule → `PreferencesStoring`

```swift
public protocol PreferencesStoring: AnyObject {
    var snapshot: PreferencesSnapshot { get }
    func update(_ transform: (inout PreferencesSnapshot) -> Void)
    var changes: AsyncStream<PreferencesSnapshot> { get }
}
```

`UserDefaults` bajo el suite `dev.local.iamawake`. Los tests usan
`UserDefaults(suiteName:)` efimero, nunca el real.

### g) Notifier → `Notifying`

```swift
public protocol Notifying: AnyObject {
    func requestAuthorizationIfNeeded() async
    func notifyDisarmed(reason: DisarmReason) async
    func notifyFailure(_ error: AwakeError) async
}
```

`UNUserNotificationCenter`. Requisitos 4, 5 y 8. Cada notificacion dice **por
que** paso, no solo que paso.

### h) AppDelegate

Unico lugar que conoce implementaciones concretas. Construye el grafo, lo
conecta a `PowerState`, y en `applicationWillTerminate` fuerza
`requestDisarm(.appTerminating)` de forma sincrona.

---

## 4. Layout del paquete

```
iAmAwake/
├── Package.swift
├── ARCHITECTURE.md          <- este archivo
├── README.md
├── Sources/
│   ├── AwakeCore/         tipos + protocolos. Sin AppKit. Sin IOKit.
│   ├── PowerAssertion/      → SleepInhibiting
│   ├── HelperClient/        → LidSleepControlling
│   ├── MenuBar/             → StatusPresenting
│   ├── Hotkey/              → HotkeyRegistering
│   ├── Guards/              → Guarding x2, PowerSourceReading, ThermalReading
│   ├── Preferences/         → PreferencesStoring
│   ├── Notifier/            → Notifying
│   ├── AwakeApp/          ejecutable GUI (AppDelegate)
│   └── iamawaked/            ejecutable root (daemon)
├── Tests/
│   ├── AwakeCoreTests/    maquina de estados de PowerState, con todo mockeado
│   ├── PowerAssertionTests/
│   ├── GuardsTests/
│   ├── PreferencesTests/
│   ├── HelperClientTests/   contra un daemon falso en un socket temporal
│   └── IntegrationTests/    flujo completo, sin tocar macOS real
└── Scripts/
    ├── install-helper.sh    se corre UNA vez con sudo
    ├── uninstall-helper.sh
    └── build-app.sh         .app + firma ad-hoc
```

Regla de dependencias: todo depende de `AwakeCore`; **ningun** modulo de
implementacion depende de otro modulo de implementacion. Solo `AwakeApp` los
conoce a todos. Eso es lo que permite compilar y testear cada uno aislado.

---

## 5. Limites conocidos que van al README

1. Requiere instalar un daemon root una vez (`sudo`). No hay alternativa: probado.
2. Sin grados Celsius reales, solo los 4 niveles de `ProcessInfo`.
3. Sin firma de Apple: hay que quitar la cuarentena a mano la primera vez.
4. Solo probado en M1 / macOS 26.6. Otro hardware sin verificar.
5. Si arrancas la app sin el daemon instalado, arma solo las assertions y avisa
   claramente que el cierre de tapa **no** esta cubierto.


---

## Anexo: animación de tapa (agregado después de v1)

Dos módulos nuevos, los dos colgando de `AwakeCore` como todos los demás.

### `LidObserver`

Lee `AppleClamshellState` de `IOPMrootDomain` y emite `.open` / `.closed`.

La frontera con IOKit es `ClamshellSource`, para poder testear sin abrir una tapa
real. `LidObserver` existe encima de esa frontera por dos razones concretas:

1. `IOServiceAddInterestNotification` dispara ante **cualquier** cambio de
   propiedad de `IOPMrootDomain`. Hay que releer y comparar, o la animación
   aparecería sola cada dos por tres.
2. `state` relee la fuente en vez de contestar con el último valor visto. Mismo
   bug que tuvo `BatteryGuard` en v1.

**Límite del hardware, medido, no supuesto:** no hay ángulo de tapa. El sensor
está en los MacBook Pro 2021+ (HID, usage page 0x20); en un MacBookAir10,1 no
existe. La transición a `.closed` llega a ~5° del cierre, con el backlight ya
apagándose. Ninguna animación puede anticiparla.

### `Overlay`

- `OverlayCopy` — regla pura: **solo anima si estaba armado**, y qué texto va.
- `AwakeTally` — formatea la duración en castellano.
- `LidSessionTracker` — cuenta cuánto estuvo cerrada. Está separado del
  `AppDelegate` porque tiene un caso borde que se rompe fácil: si se limpia
  `closedAt` antes de leerlo, la duración se pierde siempre. Eso se testea.
- `CurtainOverlayController` — el AppKit. Una sola capa que se traslada: baja
  desde arriba al cerrar, se levanta al abrir. El texto es capa hija, así que
  viaja con la cortina. `NSWindow` borderless a nivel `.screenSaver`,
  `ignoresMouseEvents`, se va sola. Honra «Reducir movimiento».

`PowerState` **no conoce nada de esto**. La animación es decoración: si fallara
entera, iAmAwake mantiene la Mac despierta igual. El `AppDelegate` la cablea
igual que a todo lo demás.
