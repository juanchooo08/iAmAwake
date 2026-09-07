# Overlay

La animacion de parpado. Un parpado que intenta cerrarse, se frena, y deja el ojo
abierto.

## Asume

- Que corre en el main actor y que hay una `NSScreen.main`.
- Que quien la llama ya decidio que la app estaba armada: `OverlayCopy` filtra el
  caso desarmado, pero la ventana no vuelve a chequear.

## NO maneja

- **Hacer visible la animacion de cierre.** El backlight se apaga a los ~0.2 s de
  que la tapa llega a los ~5 grados, que es cuando recien se entera el sistema
  (ver `LidObserver`). La animacion `.closing` dispara igual y en general no se
  alcanza a ver. La que se ve de verdad es `.opening`.
- Multiples pantallas. Dibuja en `NSScreen.main` y nada mas.
- Bloquear al usuario. La ventana ignora el mouse y se va sola; nunca se queda
  atravesada.
