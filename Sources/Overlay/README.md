# Overlay

La cortina. Al cerrar la tapa baja desde arriba y tapa todo; al abrirla se
levanta, asi que la pantalla se destapa de abajo hacia arriba.

## Asume

- Que corre en el main actor y que hay una `NSScreen.main`.
- Que quien la llama ya decidio que la app estaba armada: `OverlayCopy` filtra el
  caso desarmado, pero la ventana no vuelve a chequear.

## NO maneja

- **Hacer visible la bajada de la cortina.** El backlight se apaga a los ~0.2 s
  de que la tapa llega a los ~5 grados, que es cuando recien se entera el sistema
  (ver `LidObserver`). La cortina baja igual y en general no se alcanza a ver. La
  que se ve de verdad es la que se levanta al abrir.
- Multiples pantallas. Dibuja en `NSScreen.main` y nada mas.
- Bloquear al usuario. La ventana ignora el mouse y se va sola; nunca se queda
  atravesada.
