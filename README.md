# StillOnLocal

App de barra de menú que evita que tu MacBook duerma con la tapa cerrada, para
dejar corriendo Claude Code, builds y descargas. Reemplazo local de StillOn, uso
personal, sin distribución.

Verificado en **MacBook Air M1 (MacBookAir10,1), macOS 26.6.2**. Nada más.

---

## Lo que hay que entender antes de usarla

Las power assertions de IOKit —lo que usa `caffeinate` y casi toda app del
rubro— **no evitan el sueño al cerrar la tapa**. Está medido en esta máquina:
durmió a los 22 segundos con `PreventUserIdleSystemSleep`, `PreventSystemSleep`
y `NoDisplaySleep` activas simultáneamente.

Lo único que funciona es `DisableClamshellSleep` en `IOPMrootDomain`, que es lo
que hace `pmset -a disablesleep 1`. Medido: 296 s de heartbeat continuo, tapa
cerrada, **con batería**, sin periféricos.

Eso exige root. Por eso hay dos procesos:

```
StillOn.app (tu usuario, sin privilegios)        stillond (root, LaunchDaemon)
├─ barra de menú, hotkey, guardas          <──>  ├─ pmset disablesleep
└─ socket Unix 0600                        JSON  └─ dead man's switch
```

El daemon se instala **una vez** con sudo. Después la app nunca vuelve a pedir
contraseña.

## Instalación

```bash
swift build -c release          # o Scripts/build-app.sh para el .app
sudo Scripts/install-helper.sh  # única vez que pide contraseña
Scripts/build-app.sh
cp -R build/StillOn.app /Applications/
xattr -cr /Applications/StillOn.app
open /Applications/StillOn.app
```

## Uso

Clic en el ícono o ⌃⌥S (configurable) para armar y desarmar.

| Ícono | Estado |
|---|---|
| `moon.zzz` | Desarmado |
| `bolt.fill` | Armado — la Mac no va a dormir |
| `battery.25` | Desarmado solo por batería baja |
| `thermometer.high` | Desarmado solo por temperatura |
| `exclamationmark.triangle` | Error — la app te dice cuál |

## El dead man's switch

Con `disablesleep=1` la Mac **no duerme nunca**. Si la app crashea sin desarmar,
tu batería se drena hasta 0 con la tapa cerrada. El daemon revierte por su
cuenta, sin depender de la app, cuando:

1. No recibe heartbeat por 30 s.
2. Se cierra la conexión del cliente.
3. Recibe SIGTERM o SIGINT.
4. Ve la batería en 5% o menos, sin importar tu umbral configurado.

Además fuerza `disablesleep 0` al arrancar, por si quedó colgado de un crash.

---

## Limitaciones conocidas de v1

1. **Requiere sudo una vez.** No hay alternativa: probado. Las tres vías sin
   privilegios (`AppliesToLimitedPower`, escribir `DisableClamshellSleep` por
   IORegistry, y el user client de `IOPMrootDomain`) devuelven
   `NotPrivileged` / `NotPermitted` / `BadArgument` en macOS 26.
2. **Sin grados Celsius.** macOS no expone temperatura absoluta por API pública.
   La guarda térmica usa los 4 niveles de `ProcessInfo.thermalState`. Leer el SMC
   necesita claves no documentadas.
3. **Sin firma de Apple.** Firma ad-hoc. Hay que quitar la cuarentena a mano la
   primera vez (`xattr -cr`). No se puede distribuir a otras máquinas así.
4. **Un solo hardware probado.** M1 / macOS 26.6. En otro Mac puede comportarse
   distinto; corré `Scripts/test.sh` y la prueba manual de tapa antes de confiar.
5. **No rearma sola.** Cuando la batería o la temperatura se normalizan, la app
   queda desarmada esperando que vos decidas. Es deliberado: rearmar solo tras un
   corte térmico produce ciclos de arme/desarme.
6. **La guarda térmica no distingue** calor por tapa cerrada de calor por carga de
   CPU. Solo ve el nivel que reporta el sistema.
7. **El hotkey no valida** que la combinación esté libre hasta que intenta
   registrarla. Si otra app la tiene tomada, falla ahí y te avisa.
8. **`Preferences` duplica el formateador de hotkey** de `Hotkey`, porque el
   contrato prohíbe la dependencia cruzada. Cosmético.

## Lo que falta (roadmap)

- Login item: que arranque sola al iniciar sesión.
- Temporizador: armar por N horas y que se desarme sola.
- Reglas por aplicación: armar solo si cierto proceso está corriendo.
- Historial de por qué se desarmó, más allá de la notificación del momento.
- Instalación del daemon vía `SMAppService` en vez de script con sudo (requiere
  cuenta de desarrollador de Apple para que la firma valide).
- Probar en Intel y en otras versiones de macOS.

## Tests

```bash
Scripts/test.sh                        # los 161
Scripts/test.sh --filter GuardsTests   # uno solo
```

`Scripts/test.sh` existe porque esta máquina tiene Command Line Tools sin Xcode:
`XCTest.framework` no está, todo el proyecto usa swift-testing, y SwiftPM no
encuentra `Testing.framework` sin ayuda. Con Xcode instalado, el script detecta y
usa `swift test` normal.

Ningún test toca IOKit, pmset, la barra de menú ni el daemon real. Todo va contra
dobles inyectados.

## Desinstalar

```bash
sudo Scripts/uninstall-helper.sh
rm -rf /Applications/StillOn.app
```

## Estructura

Ver [ARCHITECTURE.md](ARCHITECTURE.md). Regla: todo depende de `StillOnCore`,
ningún módulo de implementación depende de otro, y solo `StillOnApp` los conoce
a todos.
