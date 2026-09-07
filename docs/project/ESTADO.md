# Estado

Ultima sesion: 2026-09-07

- Hecho: v1 completa. 161 tests verdes (swift-testing), release sin warnings,
  StillOn.app firmado ad-hoc en `build/`. Primer commit en main.
- Hecho: remoto en https://github.com/juanchooo08/iAmAwake, main pusheado.
- Hecho: daemon instalado y verificado contra el socket real (2026-09-07).
  ping/status/version-mismatch ok; arm pone SleepDisabled=1, disarm lo devuelve;
  el dead man's switch revirtio solo ~0.5 s despues de cortar la conexion.
- Falta: la prueba fisica de tapa cerrada con un proceso corriendo. Sin eso la
  v1 no esta confirmada contra hardware real.
- Se intento y fallo: hacerlo sin sudo. Las tres vias sin privilegios devuelven
  NotPrivileged / NotPermitted / BadArgument. Esta medido, no reabrir.
- Ojo: los tests se corren con `Scripts/test.sh`, no con `swift test`.
