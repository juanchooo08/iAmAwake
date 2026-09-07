# PowerAssertion

Implementa `SleepInhibiting` (StillOnCore). Evita el sueño **por inactividad**:
pantalla e idle del sistema.

## Que hace

`PowerAssertionInhibitor.engage()` crea dos power assertions de IOKit con
`IOPMAssertionCreateWithName`, en este orden:

1. `kIOPMAssertionTypeNoDisplaySleep`
2. `kIOPMAssertionTypePreventUserIdleSystemSleep`

Si alguna devuelve algo distinto de `kIOReturnSuccess`, se liberan las que si se
crearon (nada de estados a medias) y se intenta el fallback.

`disengage()` libera con `IOPMAssertionRelease`, mata el `caffeinate` del
fallback si lo hubo, y deja `isEngaged == false`. Es idempotente. `engage()`
tambien: llamarlo dos veces no duplica assertions.

## Que NO hace: el cierre de tapa

**Estas assertions no evitan que la Mac duerma al cerrar la tapa.** No es un bug
de este modulo. Medido en este hardware (MacBookAir10,1 / M1 / macOS 26.6.2): la
maquina **durmio a los 22 segundos** con `NoDisplaySleep` +
`PreventUserIdleSystemSleep` + `PreventSystemSleep` activas simultaneamente.

El clamshell sleep lo decide `IOPMrootDomain` por otra via
(`DisableClamshellSleep`, que exige root). Eso es responsabilidad de
`LidSleepControlling` — el daemon `stillond`. Las dos capas se arman juntas; este
modulo por si solo cubre display + idle y nada mas.

No agregues una cuarta assertion esperando arreglarlo. Ya se probo.

## Fallback a `caffeinate`

Si IOKit falla, se lanza `/usr/bin/caffeinate -dis` como proceso hijo y se mata
en `disengage()`. `isUsingFallback` expone si la inhibicion activa viene del
fallback, para que la UI pueda avisar que se esta en modo degradado.

Solo si el fallback **tambien** falla se lanza
`StillOnError.assertionFailed(kern_return_t)`, con el `kern_return_t` de la
llamada IOKit que fallo primero. Nunca se falla en silencio.

## Como se testea

Todo se testea con mocks; los tests **no tocan** el power management real de
macOS ni lanzan procesos.

Dos protocolos internos aislan el sistema, ambos inyectados por el init interno
`init(assertions:spawner:)` (el `public init()` usa las implementaciones reales):

- `AssertionCreating` — las llamadas IOKit. Real: `IOKitAssertionCreator`.
- `ProcessSpawning` / `SpawnedProcess` — el hijo `caffeinate`. Real:
  `FoundationProcessSpawner` / `LiveProcess`.

Los mocks estan en `Tests/PowerAssertionTests/Mocks.swift`. `MockAssertionCreator`
recibe una lista de `kern_return_t` para guionar exito y fallo por llamada, y
lleva cuenta de los IDs vivos y liberados.

Framework: **swift-testing** (`import Testing`, `@Test`), no XCTest.

```
swift build --package-path <repo> --scratch-path <repo>/.build-powerassertion --target PowerAssertion
swift test  --package-path <repo> --scratch-path <repo>/.build-powerassertion --filter PowerAssertionTests
```

### Nota sobre esta maquina

Solo estan instaladas las Command Line Tools (sin Xcode). `XCTest.framework` no
existe ahi, y SwiftPM por eso tampoco agrega la ruta de busqueda de
`Testing.framework`. Para correr los tests hace falta apuntarla a mano:

```
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
DYLD_LIBRARY_PATH="$LIB" swift test --package-path <repo> \
  -Xswiftc -F -Xswiftc "$FW" \
  -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$LIB" \
  --filter PowerAssertionTests
```

Con Xcode instalado, `swift test` a secas alcanza.

## Concurrencia

`SleepInhibiting` es `Sendable`. `PowerAssertionInhibitor` es un `final class`
`@unchecked Sendable` con el estado (IDs y proceso hijo) protegido por `NSLock`.
No es un `actor` porque el protocolo exige `isEngaged` sincrono. `engage()` y
`disengage()` son `async` por el protocolo pero no suspenden: delegan en cuerpos
sincronos, ya que `NSLock` no se puede tomar directamente en contexto async.
