# Estado

v1 terminada y verificada end-to-end (2026-09-07).

- 161 tests en 12 suites pasan; `swift build -c release` sin warnings.
- Daemon `dev.local.stillond` instalado: arm pone SleepDisabled=1, disarm lo
  devuelve, y el dead man's switch revierte ~0.5 s despues de cortar la conexion.
- **Prueba fisica de tapa cerrada: PASO.** Tapa cerrada, sin cargador, el
  `sleep 300` llego al final (14:16 CST).
- No queda ningun criterio de aceptacion sin verificar.

Pendiente opcional: probar a mano el desarme por bateria baja subiendo el umbral
en Preferencias por encima de la carga actual.
