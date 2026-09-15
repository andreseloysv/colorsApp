# Ritual de release semanal (Personal Team, sin Apple Developer Program)

La "release" del MVP es reinstalar la app en los dos iPhones antes de que caduque
el perfil de 7 días del Personal Team. Es la sección 3 del plan (`PLAN.md`) llevada a
comandos. Fuente de los límites y pasos: nota de investigación
`docs/research/ios-free-provisioning.md` (Apple, "Choosing a membership",
https://developer.apple.com/support/compare-memberships/, verificada 2026-09-14).
Cómo reproducir el toolchain antes de todo esto: `docs/SETUP.md` / `make bootstrap`.

## Límites del Personal Team (Apple ID gratuito)

| Límite | Valor | Cómo nos afecta |
|---|---|---|
| Dispositivos registrados | 3 (caducan a los 7 días) | Usamos 2: iPhone 13 mini del usuario + iPhone de su esposa |
| App IDs | 10 por semana | Un solo bundle ID estable (`com.andreseloy.colorsapp`), sin extensiones |
| Apps instaladas por dispositivo | 3 | ColorsApp es 1; SideStore (plan B) sería otra |
| Perfil de aprovisionamiento | 7 días desde la emisión | Tras caducar, la app **no se abre**; hay que recompilar y reinstalar |
| Depuración en dispositivo | Xcode 27: iOS ≥ 17 | Ambos iPhones con iOS ≥ 17 (el de la esposa, sin verificar) |
| No incluido | TestFlight, App Store Connect, certificados manuales, Xcode Cloud, push, iCloud | Nada de eso en el MVP |

Reinstalar sobre el mismo bundle ID debería conservar el contenedor de datos (Documents):
verificado en simulador; pendiente de comprobar en iPhone con el perfil caducado a los
7 días (criterio de salida de la fase 0). El stub de la fase 0 lo mide: muestra un
contador de lanzamientos guardado en `Documents/launches.txt`; si tras reinstalar no
vuelve a 1, los datos se conservan.

## Pasos que solo hace el usuario (una vez)

1. **Apple ID en Xcode.** Xcode > Settings > Apple Accounts > "+" > iniciar sesión.
   Xcode muestra la cuenta con el rol "Personal Team". No hace falta pagar nada.
   Criterio: `security find-identity -v -p codesigning` lista una identidad
   "Apple Development: …" (hoy lista 0; `make doctor` lo muestra en la fila
   `identidades`). Si aún no aparece, abrir `ios/ColorsApp.xcodeproj`, target
   ColorsApp > Signing & Capabilities > Team = Personal Team; Xcode crea el
   certificado en ese momento.
2. **Team ID.** En la misma pantalla de cuentas, seleccionar el Personal Team y
   copiar el Team ID (10 caracteres). Ponerlo en `ios/Signing.xcconfig`
   (`DEVELOPMENT_TEAM = XXXXXXXXXX`; hoy dice `REEMPLAZAR` y `make ios-install` se
   niega hasta que cambie). El fichero está en `.gitignore`; la plantilla commiteada
   es `ios/Signing.example.xcconfig`.
3. **iPhone del usuario (13 mini).** Ya emparejado con Developer Mode activo
   (`xcrun devicectl list devices` lo muestra; UDID `00008110-000E65AC1E69801E`).
4. **iPhone de la esposa.** Con el teléfono desbloqueado:
   1. Conectarlo por cable al Mac y tocar "Trust This Computer" (Confiar) e
      introducir el código del iPhone. No hace falta su Apple ID: el dispositivo se
      registra en el Personal Team del usuario (pendiente de confirmar en la práctica;
      Apple no lo documenta explícitamente).
   2. En Xcode > Window > Devices and Simulators (Device Hub) pulsar "Pair" si lo
      pide. A partir de entonces aparece la opción Developer Mode en el teléfono.
   3. Activar Developer Mode: Ajustes > Privacidad y seguridad > Modo de
      desarrollador > activar > Reiniciar > tras reiniciar, "Activar" + código.
   4. Primera instalación (ritual de abajo). Al abrir la app por primera vez iOS
      dirá "Desarrollador no confiable": ir a Ajustes > General > VPN y gestión de
      dispositivos > (el Apple ID del usuario) > Confiar.
   5. Después ya no hace falta cable: con el iPhone en la misma Wi-Fi que el Mac
      (IPv6 activado en la red), Xcode y `devicectl` lo ven por red. Comprobar con
      `xcrun devicectl list devices`.
   Requisito: iOS ≥ 17 en ese iPhone (no verificado todavía).

## Ritual semanal (cada ≤ 7 días): `make release-week`

```sh
xcrun devicectl list devices      # ambos iPhones "connected" (cable o Wi-Fi); copiar los UDID
make release-week DEVICES="00008110-000E65AC1E69801E <udid iPhone esposa>"
```

`make release-week` (en `mk/foundations.mk`) ejecuta, **parando en el primer fallo**:

1. `make check-protected`: nadie ha tocado umbrales, goldens ni el resto de rutas protegidas.
2. La puerta de calidad de la fase, elegida con `RELEASE_GATE` (escalera de §3 del plan):

   | Fase | `RELEASE_GATE` | Qué corre |
   |---|---|---|
   | F0–F2 (**hoy, valor por defecto**) | `test` | `make test` (motor C nativo, ctest) |
   | Desde F3 | `eval-fast` | `make eval-fast` (L1 + L2 + 10 % de L3, < 2 min) |
   | Desde F4 | `eval` | `make eval` completo con scorecard |

   Al cerrar F3 y F4 se sube el valor por defecto en `mk/foundations.mk`; mientras
   tanto se puede forzar con `make release-week RELEASE_GATE=eval ...`. Hoy `make eval`
   sale 1 por diseño (L2–L4 `not implemented`), por eso el gate de F0 es `test`.
3. `make ios-lint`: 0 referencias a `URLSession|NWConnection|CFNetwork` en `ios/`
   (la app no usa red).
4. `make ios-install DEVICE=<udid>` por cada UDID de `DEVICES`, en orden. Cada
   instalación hace: comprobar que hay identidad "Apple Development" y que
   `Signing.xcconfig` no dice `REEMPLAZAR`; `xcodebuild -destination id=<udid>
   -allowProvisioningUpdates -allowProvisioningDeviceRegistration build`;
   `xcrun devicectl device install app`; `xcrun devicectl device process launch`.

Sin `DEVICES`, `make release-week` ejecuta solo los pasos 1–3, imprime las
instrucciones para instalar y sale 0 (sirve como comprobación previa). Nunca instala
en un iPhone que no esté en `DEVICES`.

Tras instalar en cada teléfono: abrir la app, confirmar que el contador de
lanzamientos no se ha reiniciado (conservación de datos) y, desde la fase 8,
exportar el diagnóstico de la semana.

### Fallback: Run desde Xcode

Nada de la ruta de firma headless se ha ejercitado todavía con el Personal Team
(0 identidades hoy). Si `xcodebuild ... -allowProvisioningUpdates` falla (por ejemplo
pidiendo interacción para registrar el dispositivo o crear el perfil):

1. `make ios-generate` (o ya está generado) y abrir `ios/ColorsApp.xcodeproj`.
2. Target ColorsApp > Signing & Capabilities: "Automatically manage signing" activo,
   Team = Personal Team, bundle ID `com.andreseloy.colorsapp`.
3. Seleccionar el iPhone en la barra de destinos y Run (⌘R). Xcode registra el
   dispositivo, crea el perfil de 7 días, instala y lanza. Repetir con el segundo iPhone.
4. Anotar en la sección final de este documento qué paso falló en modo headless, para
   arreglar `make ios-install`.

### Plan B: SideStore (solo si el iPhone de la esposa no puede pasar por el Mac)

SideStore 0.6.4 (AGPLv3) + LocalDevVPN (App Store, gratis) permite refrescar el perfil
de 7 días desde el propio iPhone por Wi-Fi, sin cable ni Mac después de la primera
instalación (con `iloader` desde el Mac). Costes: hay que generar un IPA de ColorsApp,
introducir el Apple ID en una app de terceros, y depender de un proyecto comunitario
que va a remolque de cada versión de iOS (**compatibilidad con iOS 27 no verificada**).
**SideStore ocupa 1 de los 3 slots de apps por dispositivo del Personal Team**:
quedarían 2 para ColorsApp y otra app. Sigue siendo plan B, no plan A; detalles en
`docs/research/ios-free-provisioning.md`, sección 3.

## Qué NO hacer

- No añadir capabilities (push, iCloud, Sign in with Apple, Associated Domains, App
  Attest): el Personal Team las rechaza y el proyecto deja de firmar.
- No crear extensiones ni cambiar el bundle ID: cada uno gasta un App ID de los 10.
- No instalar AltStore/SideStore como plan A.
- No compartir el Apple ID fuera de Xcode; ningún agente lo pide ni lo introduce.
- No crear certificados ni perfiles por línea de comandos; `security find-identity` y
  `xcrun devicectl list devices` son solo lectura.

## Salida real del primer `make ios-install`

Pegar aquí, sin editar, la salida del primer `make ios-install DEVICE=00008110-000E65AC1E69801E`
(o de `make release-week DEVICES=...`) que instale de verdad en el iPhone 13 mini, y
después la del iPhone de la esposa. Es criterio de salida de la fase 0 (`PLAN.md` §8).

```
(fecha:)
(comando:)
(salida:)
```

Si hizo falta el fallback ⌘R, anotar aquí en qué paso falló la ruta headless.
