# Probar en dos iPhones sin pagar el Apple Developer Program: nativo vs PWA

Fecha de investigación: 2026-09-14. Toolchain local verificado en esta sesión: macOS 26.6.2, Xcode 27.0 (build 27A266a) en /Applications/Xcode.app, SDK iPhoneOS27.0, runtime de simulador iOS 27.0, `xcode-select -p` = /Library/Developer/CommandLineTools, `xcodebuild -checkFirstLaunchStatus` devuelve 0 (componentes ya instalados).

## 1. Personal Team (Apple ID gratuito): límites vigentes

Fuente primaria (Apple, https://developer.apple.com/support/compare-memberships/): "You can register up to 10 App IDs, which expire after 7 days. You can register up to 3 devices, which expire after 7 days. You can install up to 3 apps per device. Provisioning profiles that enable apps to be installed on a device will expire 7 days from issuance. You'll need to rebuild and reinstall your app to your device after expiration." El tier gratuito incluye betas, "On-device testing using Xcode", foros y Feedback Assistant; NO incluye Certificates/Identifiers/Profiles, App Store Connect, TestFlight, Xcode Cloud ni notarización. Capabilities: Xcode rechaza Push Notifications e iCloud ("Personal development teams, including 'X', do not support the Push Notifications capability", foro Apple 2022; "...Push Notifications and iCloud capabilities", blog oct-2025). Sign in with Apple y Associated Domains: solo fuentes secundarias (no pude parsear la tabla oficial). El MVP no necesita ninguna. Consejo: un solo bundle ID estable y sin extensiones (cada extensión consume un App ID de los 10 semanales).

## 2. Instalar en los dos iPhones

- Xcode 27 exige macOS Tahoe 26.6+ (cumplido) y "supports on-device debugging in iOS 17 and later": ambos iPhones deben tener iOS >= 17. Con iOS 27 se puede emparejar sin cable ("Device Hub adds a new way to pair iPhone... running iOS 27... over a network"); si no, cable una vez.
- Pasos: (1) Xcode > Settings > Apple Accounts, iniciar sesión con el Apple ID; Xcode lo marca "Personal Team". En Signing & Capabilities: "Automatically manage signing" + bundle ID único; "Xcode registers the device and creates the development provisioning profile for you". (2) Conectar por cable, tocar "Trust This Computer"; en Device Hub, "Pair"; activar Developer Mode (Ajustes > Privacidad y seguridad > Developer Mode > Restart > Enable + passcode). Developer Mode "only appears in Settings if you initiate pairing or if you previously paired the device to a Mac". (3) Tras emparejar: "You can disconnect the physical cable and run apps on the device through Xcode using Wi-Fi with IPv6 enabled on the same network as your Mac". (4) Primera apertura: Ajustes > General > VPN y gestión de dispositivos > confiar en el desarrollador (verificado para apps de SideStore; mismo mecanismo para Xcode, likely).
- Varios dispositivos: sí, hasta 3 por Apple ID; el iPhone de la esposa es el dispositivo 2. A los 7 días la app deja de abrirse (AltStore FAQ para el mismo mecanismo: "expire after 7 days, at which point they can no longer be opened"); hay que volver a hacer Run desde Xcode (por Wi-Fi si está en la misma red). Si el iPhone está en la misma Wi-Fi que el Mac, no hace falta cable. La conservación de datos al reinstalar sobre el mismo bundle ID no la verifiqué (likely: el contenedor se conserva).

## 3. AltStore y SideStore

- AltStore Classic (https://faq.altstore.io): 3 apps sideloaded por dispositivo, 10 App IDs a la vez (caducan en una semana), caducidad a 7 días; "Background Refresh" refresca con AltServer si el iPhone está "on the same WiFi network as a computer running AltServer — or is plugged-in directly". AltServer macOS 1.7.3 (22-may-2025, macOS 11+); Mail plug-in ya no requerido desde 1.7 (sep-2023, secundario). El propio AltStore ocupa 1 de los 3 slots. Remote AltServers permiten refrescar sin ordenador vía LocalDevVPN + Wi-Fi.
- SideStore (https://docs.sidestore.io, AGPLv3): "untethered": "You only need a computer once during installation" (iloader, macOS/Windows/Linux); iOS 15+; refresco on-device con LocalDevVPN (App Store, gratis, Coxson Engineering LLC, id6755608044) + Wi-Fi ("mobile network is not suitable"); en iOS 18+ hay que activar Developer Mode. Última release 0.6.4 (9-sep-2026): refresco por celular vía Shortcuts, 2FA por SMS/voz, portal de desarrollador integrado; issue conocido con LocalDevVPN en iOS 16. Compatibilidad con iOS 27 no verificada.
- Viabilidad para la esposa: sí da independencia del cable y del Mac, a costa de introducir el Apple ID en una app de terceros, generar un IPA y confiar en un proyecto comunitario que va a remolque de cada iOS. Recomendación: plan B, no plan A.

## 4. PWA en iOS (Safari, web app en pantalla de inicio)

- iOS 26: "every website added to the Home Screen opens as a web app" (WebKit blog 17333). Almacenamiento: las web apps de pantalla de inicio están exentas del borrado ITP de 7 días ("have their own counter of days of use", WebKit blog 10218). Cuota Safari 17+: hasta 60% del disco por origen en navegadores; `navigator.storage.persist()` se concede "based on heuristics like whether the website is opened as a Home Screen Web App" (WebKit blog 14403). IndexedDB OK.
- getUserMedia en standalone funciona desde iOS 13.4 (WebKit bug 185448), pero el permiso de cámara "is not persisted for PWAs" (STRICH KB, ago-2026, secundario). Web Share con archivos: Safari 15 ("Web Share level 2... enable sharing files from a web page to an app"). `<input type=file multiple accept=image/*>`: permite selección múltiple desde Fototeca (foro Apple, iOS 12/13, secundario); iOS puede recomprimir capturas (foro, sin respuesta).
- CONFIRMADO: no existe API web para enumerar el carrete: File System Access API no está soportada en Safari ni Safari iOS (caniuse), solo hay `<input type=file>` y getUserMedia. El "escaneo del carrete al instalar" en batch es imposible sin selección manual del usuario.
- WASM: sin límite fijo; "on iOS the OS is free to kill any process it wants for using too much memory... based on system pressure not a fixed limit" (Keith Miller, WebKit). Godot: `maximum` de 2048 MB fallaba en iPhone 13 Pro iOS 16.2, 256 MB funcionaba. Safari 26 añade intérprete in-place para wasm. Canvas total ~224 MB (iOS 12, secundario). Sin Vision/PhotoKit.

## 5. Stack nativo para el MVP

SwiftUI + PhotoKit: acceso limitado desde iOS 14 (`PHPhotoLibrary.requestAuthorization(for: .readWrite)` -> `.limited`, `presentLimitedLibraryPicker`, clave `PHPhotoLibraryPreventAutomaticLimitedAccessAlert`); `PHFetchOptions.fetchLimit` (iOS 9+) + `sortDescriptors` por `creationDate` desc para las últimas N; `PHImageManager.requestImage` con `PHImageRequestOptions` (`deliveryMode = .fastFormat`, `resizeMode = .fast`, `isSynchronous`, `isNetworkAccessAllowed`) y `targetSize` pequeño para batch. OJO: el escaneo de 200 fotos requiere `.authorized`; con `.limited` solo se ven las fotos elegidas. Vision: `VNGeneratePersonSegmentationRequest` iOS 15+ (`qualityLevel` .fast/.balanced/.accurate, salida `VNPixelBufferObservation`); `VNGenerateForegroundInstanceMaskRequest` iOS 17+ (`[VNInstanceMaskObservation]`). `ImageRenderer` iOS 16+ (`cgImage`/`uiImage`, `scale`; solo rasteriza vistas SwiftUI puras). `ShareLink` iOS 16+ con `Transferable` + `SharePreview`. Persistencia: SwiftData iOS 17+; GRDB.swift iOS 13+, Swift 6.1+/Xcode 16.3+, MIT. Mínimo recomendado: iOS 17 (SwiftData + foreground mask + suelo de depuración de Xcode 27); en la práctica ambos iPhones estarán en iOS 26/27 (79% de iPhones en iOS 26 al 7-jun-2026). Motor en C como target de SwiftPM (mismo fuente para CLI macOS `make eval`; emcc solo si se hace la PWA).

## 6. Flutter / React Native

No aportan nada para iPhone-only: Flutter usa `dart:ffi` + `ffigen` + template `plugin_ffi` con `.podspec`/`.framework` y caveat de strip de símbolos; RN usa Nitro Modules (C++ `HybridObject` sobre JSI, generador Nitrogen). Ambos añaden runtime, capa de bindings y aún necesitan Vision/PhotoKit vía puente, con los MISMOS límites de Personal Team.

## 7. Corregir xcode-select

```
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcode-select -p            # debe imprimir la ruta anterior
sudo xcodebuild -license accept   # solo si xcodebuild se queja de la licencia
xcodebuild -checkFirstLaunchStatus || xcodebuild -runFirstLaunch
xcodebuild -version        # esperado: Xcode 27.0 Build 27A266a
xcrun simctl list runtimes && xcrun simctl list devices available
xcrun devicectl list devices
```
Alternativa sin sudo: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (man xcode-select).

## 8. Recomendación

Nativo SwiftUI + motor C primero; PWA solo después (Android/web) si se quiere. Ver `recommendation` en la salida estructurada.

---

## Findings (claim | confidence | URL)

1. Personal Team: 10 App IDs / 3 dispositivos / 3 apps por dispositivo / perfiles de 7 días / rebuild+reinstall | verified | https://developer.apple.com/support/compare-memberships/
2. Free tier sin TestFlight, App Store Connect, portal de certificados, Xcode Cloud | verified | https://developer.apple.com/support/compare-memberships/
3. Xcode: "Personal development teams ... do not support the Push Notifications capability" | verified | https://developer.apple.com/forums/thread/718388
4. Error también para iCloud (oct-2025) | likely | https://gordonbeeming.com/blog/2025-10-15/solving-xcode-provisioning-profile-and-capability-errors
5. Sign in with Apple / Associated Domains no disponibles en Personal Team | unverified (secundarias) | https://developer.apple.com/help/account/reference/supported-capabilities-ios/
6. Developer Mode: pasos y "only appears in Settings if you initiate pairing" | verified | https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device
7. Developer Mode existe desde iOS 16 | likely | https://docs.expo.dev/guides/ios-developer-mode/
8. Device Hub: cable + Trust, luego Wi-Fi con IPv6; emparejado inalámbrico requiere iOS 27 | verified | https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub
9. Xcode registra el dispositivo y crea el perfil con "Automatically manage signing" | verified | https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices
10. Xcode 27: macOS 26.6+, SDK iOS 27, depuración solo iOS 17+, pairing por red iOS 27 | verified | https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes
11. Xcode 27: deployment targets 15.0–27.0 | likely | https://bleepingswift.com/blog/deployment-target-supported-range-xcode-27
12. Xcode local = 27.0 (27A266a), xcode-select en CommandLineTools, first launch OK | verified | (local, esta sesión)
13. Apps caducadas "can no longer be opened" (mismo mecanismo de perfil de 7 días) | verified | https://faq.altstore.io/altstore-classic/your-altstore
14. AltStore: 3 apps, Background Refresh con AltServer, deactivate | verified | https://faq.altstore.io/altstore-classic/your-altstore
15. AltStore: 10 App IDs a la vez, caducan en una semana, extensiones cuentan | verified | https://faq.altstore.io/altstore-classic/app-ids
16. AltServer: misma Wi-Fi o USB; dejarlo abierto al arrancar | verified | https://faq.altstore.io/altstore-classic/altserver
17. AltServer macOS 1.7.3 (22-may-2025), macOS 11+ | verified | https://faq.altstore.io/release-notes/altserver
18. Mail plug-in no requerido desde AltServer 1.7 (sep-2023) | likely | https://x.com/altstoreio/status/1702757993438163116
19. Remote AltServers: refrescar sin ordenador con LocalDevVPN + Wi-Fi | verified | https://faq.altstore.io/altstore-classic/remote-altservers
20. SideStore untethered; ordenador solo una vez; VPN; refresco periódico; AGPLv3 | verified | https://github.com/SideStore/SideStore/blob/develop/README.md
21. SideStore prereqs: iOS 15+, Wi-Fi (no celular), LocalDevVPN, iloader | verified | https://docs.sidestore.io/docs/installation/prerequisites
22. SideStore install: VPN & Device Management > Trust; Developer Mode en iOS 18+ | verified | https://docs.sidestore.io/docs/installation/install
23. SideStore 0.6.4 (9-sep-2026), cellular refresh via Shortcuts, issue iOS 16 | verified | https://github.com/SideStore/SideStore/releases
24. LocalDevVPN en App Store, gratis, iOS 14+ | verified | https://apps.apple.com/app/id6755608044
25. ITP 7 días: web apps de pantalla de inicio exentas | verified | https://webkit.org/blog/10218/full-third-party-cookie-blocking-and-more/
26. Safari 17: cuota 60%/15%, persist por heurística Home Screen | verified | https://webkit.org/blog/14403/updates-to-storage-policy/
27. iOS 26: toda web añadida abre como web app; zero installability reqs; wasm in-place interpreter | verified | https://webkit.org/blog/17333/webkit-features-in-safari-26-0/
28. getUserMedia en standalone desde iOS 13.4 | verified | https://bugs.webkit.org/show_bug.cgi?id=185448
29. Permiso de cámara no persiste en PWA | likely | https://kb.strich.io/article/29-camera-access-issues-in-ios-pwa
30. Web Share level 2 (archivos) desde Safari 15 | verified | https://developer.apple.com/documentation/safari-release-notes/safari-15-release-notes
31. input file multiple: selección múltiple desde Fototeca | likely | https://developer.apple.com/forums/thread/129845
32. File System Access API no soportada en Safari/iOS | verified | https://caniuse.com/native-filesystem-api
33. WASM iOS: sin límite fijo, el SO mata por presión | verified | https://bugs.webkit.org/show_bug.cgi?id=221530
34. WASM: 2048 MB falla, 256 MB OK en iPhone 13 Pro iOS 16.2 | verified | https://github.com/godotengine/godot/issues/70621
35. PhotoKit acceso limitado iOS 14+; APIs | verified | https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app
36. PHFetchOptions.fetchLimit iOS 9+ | verified | https://developer.apple.com/documentation/photos/phfetchoptions/fetchlimit
37. PHImageRequestOptions deliveryMode/resizeMode/isSynchronous/isNetworkAccessAllowed | verified | https://developer.apple.com/documentation/photos/phimagerequestoptions
38. VNGeneratePersonSegmentationRequest iOS 15+, qualityLevel | verified | https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest
39. VNGenerateForegroundInstanceMaskRequest iOS 17+ | verified | https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest
40. ImageRenderer iOS 16+ | verified | https://developer.apple.com/documentation/swiftui/imagerenderer
41. ShareLink iOS 16+ | verified | https://developer.apple.com/documentation/swiftui/sharelink
42. SwiftData iOS 17+ | verified | https://developer.apple.com/documentation/swiftdata
43. GRDB iOS 13+, Swift 6.1+, MIT | verified | https://github.com/groue/GRDB.swift
44. iOS 26 en 79% de iPhones (7-jun-2026) | verified | https://developer.apple.com/support/app-store/
45. Flutter FFI: plugin_ffi, podspec/.framework, strip symbols | verified | https://docs.flutter.dev/platform-integration/ios/c-interop
46. RN Nitro: C++ HybridObject sobre JSI, Nitrogen | verified | https://nitro.margelo.com/
47. xcode-select -s/-p/-r, DEVELOPER_DIR | verified | https://keith.github.io/xcode-man-pages/xcode-select.1.html
48. xcodebuild -runFirstLaunch / -checkFirstLaunchStatus / -license | verified | https://keith.github.io/xcode-man-pages/xcodebuild.1.html
