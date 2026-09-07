# Notifier

Notificaciones nativas vía `UNUserNotificationCenter`. Existe por los requisitos
4, 5 y 8: cuando la app se desarma sola, o cuando algo falla, el usuario tiene
que enterarse y saber **por qué**.

- `UserNotificationsNotifier` — implementa `Notifying`.
- `NotificationTexts` — los textos, separados de la entrega para poder testearlos.
- `NotificationDelivering` — el centro real, detrás de un protocolo inyectable.

## Qué asume

- Que el permiso se pide una sola vez y el resultado se recuerda. Llamadas
  concurrentes comparten la misma tarea.
- Que el usuario puede negar el permiso, y que eso **no** es un error fatal:
  se registra y la app sigue funcionando, solo que en silencio.
- `.user` y `.appTerminating` no notifican: el usuario acaba de hacerlo él.

## Qué NO maneja

- No reintenta entregas fallidas ni encola nada.
- No agrupa ráfagas: si dos guardas disparan juntas, salen dos notificaciones.
- No pide permiso solo. Alguien tiene que llamar a `requestAuthorizationIfNeeded()`
  en el arranque.

## Cómo se testea

Con un espía de `NotificationDelivering`. No dispara notificaciones reales. Los
tests verifican que cada `DisarmReason` y cada `StillOnError` produzcan un texto
distinto, no vacío, y que los motivos silenciosos no entreguen nada.

```
Scripts/test.sh --filter PreferencesTests
```
