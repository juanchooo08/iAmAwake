# Guards

Dos guardas que desarman la app bajo condición. Comparten patrón: leen una
fuente del sistema, la comparan contra un umbral de las preferencias, y emiten
un `GuardVerdict`. No conocen `PowerState` ni se desarman solas — solo opinan.

| Tipo | Fuente | Regla |
|---|---|---|
| `BatteryGuard` | `PowerSourceReading` | con batería y `percent <= batteryThreshold` → `.mustDisarm` |
| `ThermalGuard` | `ThermalReading` | `level >= thermalCeiling` → `.mustDisarm` |

`IOPowerSourcesReader` y `ProcessInfoThermalReader` son las implementaciones
reales de esas fuentes; se inyectan por `init`.

## Qué asume

- Que alguien más llama a `start(onVerdict:)` y reacciona al veredicto. La guarda
  no toca el estado de la app.
- Que `apply(_:)` se llama cuando cambian las preferencias. Reevalúa en caliente.
- `BatteryGuard` asume que estar enchufado vuelve la guarda irrelevante: con AC
  siempre devuelve `.ok`. Desarmar enchufado no protege de nada.

## Qué NO maneja

- **No hay grados Celsius.** macOS no expone temperatura absoluta por API
  pública. `ProcessInfo.thermalState` da cuatro niveles y nada más. Leer el SMC
  necesita claves no documentadas y queda fuera de v1.
- No rearma cuando la condición se normaliza. Eso lo decide `PowerState`, y por
  diseño tampoco rearma solo: rearmar tras un corte térmico produce ciclos.
- `ThermalGuard` no distingue calor por tapa cerrada de calor por carga de CPU.
  Solo ve el nivel que reporta el sistema.

## Cómo se testea

Los tests inyectan mocks de `PowerSourceReading` y `ThermalReading`. No tocan
IOKit ni dependen del estado real de la máquina, así que corren igual con
batería llena o al 3%.

```
Scripts/test.sh --filter GuardsTests
```

## Cómo probar el desarme por batería sin descargar la batería

No hace falta drenar nada: movés el umbral en vez del nivel.

1. Mirá tu carga actual: `pmset -g ps`
2. En Preferencias, subí el umbral de batería por encima de ese valor (ej. estás
   al 60%, ponés el umbral en 50 → nada; lo ponés en 65 → dispara).
3. `apply(_:)` reevalúa en caliente, así que la app debe desarmarse en el acto y
   mostrar la notificación explicando que fue por batería.
4. Bajá el umbral de vuelta a 20. Confirmá que el ícono queda en desarmado y
   **no** vuelve a armarse solo.

Para la guarda térmica no hay equivalente limpio sin calentar la máquina de
verdad; el nivel lo dicta el sistema. La cobertura ahí es por tests con mock.


## NetworkGuard (agregado después de v1)

Desarma cuando la red lleva caída más que `networkGraceSeconds`.

Cuenta el margen con un `DelayScheduling` inyectado, no con un `Timer` propio:
así los cinco minutos se testean sin esperarlos. Dos casos borde que están
cubiertos por tests porque son fáciles de romper:

- **Reportes repetidos de caída no reinician la cuenta.** `NWPathMonitor` puede
  repetir `unsatisfied` al cambiar de interfaz; si cada uno regalara un margen
  entero, no vencería nunca.
- **Bajar el margen con la red ya caída desarma sin esperar.** Pasar de 15 a 1
  minuto con 5 minutos caídos tiene que actuar ya, no arrancar otra cuenta.

**NO maneja:** distinguir "hay ruta" de "internet responde". Ver la limitación 10
del README.
