# Estado

Ultima sesion: 2026-09-07

- Hecho: v1 completa. 161 tests verdes (swift-testing), release sin warnings,
  StillOn.app firmado ad-hoc en `build/`. Primer commit en main.
- Falta: crear el repo en GitHub y pushear (no hay `gh` ni `brew` en la maquina).
- Falta: `sudo Scripts/install-helper.sh` — el daemon nunca se instalo.
- Falta: la prueba fisica de tapa cerrada con un proceso corriendo. Sin eso la
  v1 no esta confirmada contra hardware real.
- Se intento y fallo: hacerlo sin sudo. Las tres vias sin privilegios devuelven
  NotPrivileged / NotPermitted / BadArgument. Esta medido, no reabrir.
- Ojo: los tests se corren con `Scripts/test.sh`, no con `swift test`.
