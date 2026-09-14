# Ritual de release semanal (Personal Team, sin Apple Developer Program)

La "release" del MVP es reinstalar la app en los dos iPhones antes de que caduque
el perfil de 7 días del Personal Team. Fuente de los límites y pasos: nota de
investigación `ios-free-provisioning.md` (Apple, "Choosing a membership",
https://developer.apple.com/support/compare-memberships/, verificada 2026-09-14).

## Límites del Personal Team (Apple ID gratuito)

| Límite | Valor | Cómo nos afecta |
|---|---|---|
| Dispositivos registrados | 3 (caducan a los 7 días) | Usamos 2: iPhone 13 mini del usuario + iPhone de su esposa |
| App IDs | 10 por semana | Un solo bundle ID estable (`com.andreseloy.colorsapp`), sin extensiones |
| Apps instaladas por dispositivo | 3 | ColorsApp es 1 |
| Perfil de aprovisionamiento | 7 días desde la emisión | Tras caducar, la app **no se abre**; hay que recompilar y reinstalar |
| Depuración en dispositivo | Xcode 27: iOS ≥ 17 | Ambos iPhones con iOS ≥ 17 |
| No incluido | TestFlight, App Store Connect, certificados manuales, Xcode Cloud, push, iCloud | Nada de eso en el MVP |

Reinstalar sobre el mismo bundle ID debería conservar el contenedor de datos (Documents):
verificado en simulador; pendiente de comprobar en iPhone con el perfil caducado a los 7 días
(criterio de salida de la fase 0).
El stub de la fase 0 lo comprueba: muestra un contador de lanzamientos guardado en
`Documents/launches.txt`; si tras reinstalar no vuelve a 1, los datos se conservan.

## Pasos que solo hace el usuario (una vez)

1. **Apple ID en Xcode.** Xcode > Settings > Apple Accounts > "+" > iniciar sesión.
   Xcode muestra la cuenta con el rol "Personal Team". No hace falta pagar nada.
   Criterio: `security find-identity -v -p codesigning` lista una identidad
   "Apple Development: …" (hoy lista 0). Si aún no aparece, abrir
   `ios/ColorsApp.xcodeproj`, target ColorsApp > Signing & Capabilities > Team =
   Personal Team; Xcode crea el certificado en ese momento.
2. **Team ID.** En la misma pantalla de cuentas, seleccionar el Personal Team y
   copiar el Team ID (10 caracteres). Ponerlo en `ios/Signing.xcconfig`
   (`DEVELOPMENT_TEAM = XXXXXXXXXX`). El fichero está en `.gitignore`; la plantilla
   commiteada es `ios/Signing.example.xcconfig`.
3. **iPhone del usuario (13 mini).** Ya emparejado con Developer Mode activo
   (`xcrun devicectl list devices` lo muestra).
4. **iPhone de la esposa.** Con el teléfono desbloqueado:
   1. Conectarlo por cable al Mac y tocar "Trust This Computer" (Confiar) e
      introducir el código del iPhone.
   2. En Xcode > Window > Devices and Simulators (Device Hub) pulsar "Pair" si lo
      pide. A partir de entonces aparece la opción Developer Mode en el teléfono.
   3. Activar Developer Mode: Ajustes > Privacidad y seguridad > Modo de
      desarrollador > activar > Reiniciar > tras reiniciar, "Activar" + código.
   4. Primera instalación (paso "Instalar" de abajo). Al abrir la app por primera
      vez iOS dirá "Desarrollador no confiable": ir a Ajustes > General > VPN y
      gestión de dispositivos > (el Apple ID del usuario) > Confiar.
   5. Después ya no hace falta cable: con el iPhone en la misma Wi-Fi que el Mac
      (IPv6 activado en la red), Xcode y `devicectl` lo ven por red. Comprobar con
      `xcrun devicectl list devices`.
   Requisito: iOS ≥ 17 en ese iPhone (no verificado todavía).

## Ritual semanal (cada ≤ 7 días)

```
make eval                                  # scorecard en verde (fase 1+; hoy make test)
make check-protected                       # nadie ha tocado umbrales ni goldens
xcrun devicectl list devices               # ambos iPhones "connected" (cable o Wi-Fi)
make ios-install DEVICE=<udid iPhone 13 mini>
make ios-install DEVICE=<udid iPhone esposa>
```

`make ios-install` hace: comprobar que hay identidad "Apple Development" y que
`Signing.xcconfig` no dice `REEMPLAZAR`; `xcodebuild -destination id=<udid>
-allowProvisioningUpdates -allowProvisioningDeviceRegistration build`;
`xcrun devicectl device install app`; `xcrun devicectl device process launch`.
Si la parte headless falla con el Personal Team (no probado aún), el fallback es
abrir `ios/ColorsApp.xcodeproj` y hacer Run (⌘R) con el iPhone seleccionado.

Tras instalar en cada teléfono: abrir la app, confirmar que el contador de
lanzamientos no se ha reiniciado y (fase 8) exportar el diagnóstico de la semana.

## Qué NO hacer

- No añadir capabilities (push, iCloud, Sign in with Apple, Associated Domains, App
  Attest): el Personal Team las rechaza y el proyecto deja de firmar.
- No crear extensiones ni cambiar el bundle ID: cada uno gasta un App ID de los 10.
- No instalar AltStore/SideStore como plan A; queda como plan B documentado en la
  nota de investigación si el iPhone de la esposa no puede pasar por el Mac.
- No compartir el Apple ID fuera de Xcode.
