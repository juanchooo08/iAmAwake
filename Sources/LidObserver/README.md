# LidObserver

Traduce `AppleClamshellState` de `IOPMrootDomain` a transiciones `.open` / `.closed`.

## Asume

- Que `IOServiceAddInterestNotification` sobre `IOPMrootDomain` dispara ante
  cualquier cambio de propiedad, no solo la tapa. Por eso `LidObserver` relee y
  compara antes de emitir.
- Que quien consuma las transiciones vive en el main queue: el puerto de
  notificacion se despacha ahi.

## NO maneja

- **El angulo de la tapa.** No existe en este hardware. El sensor de angulo lo
  traen los MacBook Pro 2021+ por HID (usage page 0x20); un MacBookAir10,1 no lo
  tiene. Verificado con `ioreg`: cero dispositivos en esa usage page. La
  consecuencia practica es que la transicion a `.closed` llega cuando la tapa ya
  esta a ~5 grados del cierre, con el backlight apagandose. No hay forma de
  anticiparla.
- Macs sin tapa. `read()` devuelve `nil` y el observador se queda en el ultimo
  valor conocido en vez de inventar `.open`.
- Decidir que se dibuja. Solo reporta; la animacion es de `Overlay`.
