# ChromaSol para Android: fundación y mapa del port

Documento del carril A (fundación). Dice qué hay construido en `android/`, cómo
se comprueba, cómo casa cada fichero de iOS con su sitio en Android y cómo se
reparte la segunda ola en carriles paralelos que no se pisan.

Nombre público: **ChromaSol**. Nombre interno: ColorsApp.
`applicationId`: `com.andreseloy.colorsapp`. Google Play, de pago (2,99 $).
Sin red, sin cuentas, sin analítica: la app de Android **no pide
`android.permission.INTERNET`** (puerta `make android-lint` sobre el
manifiesto fusionado de release).

## 1. Qué hay en esta fundación

```
android/
  settings.gradle.kts            módulos :engine y :app
  build.gradle.kts               solo aliases de plugins
  gradle/libs.versions.toml      AGP 8.9.3, Kotlin 2.1.21, Compose BOM 2025.05.01
  gradlew / gradle/wrapper       Gradle 8.11.1 (wrapper versionado)
  icon/icon_master.png           máster 1024x1024 del icono (hoy el de iOS)
  tools/make_icon.py             máster -> adaptativo + monocromo + legados
  tools/gen_wasm_expected.py     esperado de paridad WASM con el `ce` de host
  tools/capture_tabs.py          capturas de pestañas por adb
  engine/                        módulo :engine (biblioteca Android)
    src/main/cpp/CMakeLists.txt  compila engine/Sources/CColorEngine/*.c TAL CUAL
    src/main/cpp/ce_jni.c        puente JNI (solo adapta tipos; sin color)
    src/main/java/.../engine/    API Kotlin espejo de ColorEngine.swift
    src/androidTest/             paridad contra goldens + comportamiento
  app/                           módulo :app (Compose, una actividad)
    src/main/java/.../app/       ColorsApp, AppContainer, MainActivity, rutas
    src/main/java/.../design/    tokens, tipografía, métricas, componentes
    src/main/java/.../data/      diccionario, registros, repos (interfaces)
    src/main/java/.../scan/      contrato del escaneo del carrete
    src/main/java/.../subject/   contrato de segmentación (carril B enchufa aquí)
    src/main/java/.../feature/   pantallas (esqueletos; dueños en la ola 2)
    src/main/assets/licenses/    OFL de Literata y Plus Jakarta Sans
mk/android.mk                    android-build/test/test-device/lint/bundle/…
docs/ANDROID.md                  este documento
```

Decisiones de versión (con el toolchain de esta máquina): compileSdk/targetSdk
**36**, minSdk **26**, JDK 17, NDK 29.0.14206865, ABIs `arm64-v8a` y `x86_64`.
Release con R8 (los símbolos JNI se conservan con
`engine/consumer-rules.pro`). Solo vertical, como iOS.

### El motor: misma fuente C, mismos bits

`:engine` compila directamente `engine/Sources/CColorEngine/*.c` con CMake/NDK
y los mismos flags que `engine/CMakeLists.txt` (`-Wall -Wextra -Werror
-Wpedantic -ffp-contract=off`, C11). Nada de lógica de color en Kotlin: la API
(`ColorEngine`, `ColorMath`, `WadaEngineDictionary`, `EngineRaster`) espeja
`engine/Sources/ColorEngine/ColorEngine.swift` y
`ios/ColorsApp/Engine/EngineBridge.swift` función a función (paleta, match,
prendas, explicación, capas de depuración, regiones por pose, piel, split,
hashes). Los valores por defecto de las opciones se leen del propio motor
(`nativeDefaults`), así un cambio en C no puede desincronizar Kotlin.

### Paridad comprobada (la puerta)

`engine/src/androidTest/EngineParityTest.kt` corre en el emulador y compara,
con la tolerancia de `make golden-check` (1e-9, mismo top-3, mismo hash):

- las **20 paletas** de `harness/golden/palettes_20.json` (Lab, sRGB8, pesos,
  `ce_swatch_hash`),
- los **50 matches** de `harness/golden/match_50.json` (top-3, scores,
  `ambiguous`, `ce_result_hash` con n_hits = 3),
- las **20 fixtures de paridad WASM** de `harness/wasm/fixtures/`, contra
  `wasm_expected.json`, generado con el CLI nativo `ce` de host (el mismo
  binario que `make parity` enfrenta a WASM) por
  `android/tools/gen_wasm_expected.py` (`make android-wasm-expected` lo
  regenera).

Los assets no se duplican en git: la tarea Gradle `syncParityAssets` copia
los goldens y las fixtures del repo a `build/` en cada compilación de tests.
`make golden-check` en el host sigue siendo la referencia del motor; si los
goldens cambian (con su motivo en `harness/CHANGELOG.md`), el test de Android
los recoge sin tocar código. `ColorEngineTest.kt` cubre además el
comportamiento de la API (errores tipados como en Swift, prendas, capas,
máscaras) y `TabsSmokeTest.kt` el humo de las cuatro pestañas.

Comandos (desde la raíz del repo):

```
make android-build         # APK debug
make android-test          # unit JVM
make android-emulator      # AVD Medium_Phone_API_37.0 sin ventana (fondo)
make android-test-device   # paridad + humo en el emulador
make android-lint          # sin INTERNET en release + lint de Gradle
make android-bundle        # AAB release (firma con CHROMASOL_KEYSTORE_* si están)
make android-screenshots   # harness/out/android/tab-*.png
make android-icon          # tras sustituir android/icon/icon_master.png
```

### Icono

`android/icon/icon_master.png` es hoy el icono de iOS (1024×1024) como
marcador de posición: el dueño no está contento con el icono y hay uno 3D en
marcha. Cambiar el icono = sustituir ese fichero por el máster nuevo (1024×1024
PNG, arte a sangre completa) y `make android-icon`: genera el foreground
adaptativo, la silueta monocroma (derivada por distancia al fondo: revisarla
con el arte nuevo), los legados cuadrado/redondo en las 5 densidades y el
color de fondo muestreado de las esquinas. Lo mismo habrá que hacer en iOS
con su pipeline (`ios/Scripts/render_app_icon.sh`) cuando llegue el máster.

### Idiomas

Español (fuente), alemán e inglés, según el idioma del sistema y sin ajuste en
la app — igual que iOS. El respaldo para cualquier otro idioma es el
**español**: en iOS lo fija `CFBundleDevelopmentRegion = "es"`
(`ios/ColorsApp/Info.plist`, y `sourceLanguage: es` en
`Localizable.xcstrings`); en Android es automático porque `res/values/`
(español) es la carpeta por defecto que se usa cuando ningún
`values-<idioma>` coincide. Traducciones de/en de los textos del esqueleto
copiadas de `Localizable.xcstrings`. Cada carril pone sus textos en
`values*/strings_<carril>.xml` copiados del catálogo (la clave de iOS es el
propio texto español) y la fidelidad la vigila `make android-strings-check`
(`android/tools/check_strings.py`, W1): falla si falta una traducción de/en
o si un texto que corresponde a una clave de iOS difiere del catálogo en
de/en. La cabecera del script dice cómo reusar textos y cómo declarar una
divergencia deliberada (`android/tools/strings_allowlist.json`).

## 2. Reglas que hereda todo el que toque `android/`

1. **Sin lógica de color en Kotlin/Java.** Conversiones, ΔE, paletas, match,
   prendas, piel: todo en el C de `engine/Sources/CColorEngine` vía
   `:engine`. Formatear un hex o empaquetar un ARGB no es lógica de color.
2. **Sin red.** Ni INTERNET en el manifiesto (ojo: algunas dependencias lo
   inyectan al fusionar; `android-lint` lo caza en release), ni analytics, ni
   modelos que se descarguen en tiempo de ejecución (nada de Play Services ML
   con descarga: el modelo que elija el carril B va empaquetado en assets).
3. **Un `ColorEngine` (ce_ctx) por tarea**, nunca compartido entre hilos;
   el trabajo pesado fuera del hilo principal (Dispatchers.Default).
4. **Comentarios en español, identificadores en inglés** (regla del repo).
5. El aspecto manda: tokens y medidas salen de `design/` (§3). Los colores de
   datos del motor solo se pintan dentro de pocillos neutros (`WellContainer`).
6. Permisos, los mínimos y en su momento: selector de fotos sin permiso;
   carrete con `READ_MEDIA_IMAGES` (y acceso limitado en API 34+); cámara
   solo al usarla. Nada de pedir permisos al arrancar.

## 3. Sistema de diseño portado

| iOS (`ios/ColorsApp/Design/`) | Android (`app/.../design/`) | Estado |
|---|---|---|
| `Theme.swift` (ThemeTokens, Tone) | `SolarTokens.kt` + `SolarTheme.kt` | Completo: los 71 tokens claro/oscuro, ColorScheme M3 derivado, `LocalSolarColors` |
| `Typography.swift` (TextRole ×16, FontRegistry) | `SolarType.kt` | Roles 1:1 (pt→sp); Literata/PJS variables con eje wght; mono del sistema |
| `Metrics.swift` (Spacing/Radius/Sizes) | `SolarMetrics.kt` | Completo |
| `Materials.swift` (ParchmentFrost, SolarWash) | `parchmentFrost` (solo tinte 78 %) y `SolarWash` (blur) en `SolarComponents.kt` | Sin desenfoque de fondo real (ver §6) |
| `Components/Cards.swift`, `Controls.swift`, `Chrome.swift`, `SwatchWell.swift`, `Garden.swift`, `PinOverlay.swift`, `BookComposition.swift` | `SolarComponents.kt` (SolarCard, WellContainer, SwatchStrip, botones, chip, insignias, SolarTabBar, press 0,97) + `SolarHeader.kt` | Núcleo; pins, libro y componentes de Jardín: ola 2 |
| `PaletteColor.swift` (color de datos) | — (en Android: `Swatch.argb` / `WadaColor.argb`) | Por diseño: sin conversión, solo empaquetado |
| `Brand/` (emblema, logo, personajes de pestaña animados) | `SolarIcons.kt` (glifos sol/gota/rejilla/hoja/cámara/destellos) | Personajes originales animados: ola 2 |
| `Motion/` (luces, motas, curvas, reloj ambiental) | — | Ola 2 (carril de pulido; ver FIDELITY.md) |
| `DesignSystemRoot.swift`, `AppBrand.swift`, `FontLicenses.swift` | `ChromaSolTheme` + `LicensesScreen` (OFL desde assets) | Hecho |

## 4. Mapa fichero a fichero (iOS → Android)

Fuente iOS = la publicada (checkout principal, con sus ficheros sin
versionar: `Localizable.xcstrings`, `Views/Extract/*`, `Views/Resultado/*`,
`Views/Wrapped/*`, `Components/BookComposition.swift`). «Base» = contrato o
esqueleto ya en esta fundación; «Ola 2» indica el carril dueño (§5).

### App, datos y motor

| iOS | Android | Estado / carril |
|---|---|---|
| `App/ColorsAppApp.swift` | `app/ColorsApp.kt` + `MainActivity.kt` | Base |
| `App/AppEnvironment.swift` | `app/AppContainer.kt` | Base (DI manual; bootstrap) |
| `App/RootTabView.swift` (AppTab, RootTabBar, scanBadge) | `app/ChromaSolApp.kt` + `SolarTabBar` | Base; personajes animados y motions = pulido (W5) |
| `Engine/EngineBridge.swift` (+ `PPM.swift`) | `engine/EngineRaster.kt` (PPM solo en tests) | Base |
| `engine/Sources/ColorEngine/ColorEngine.swift` | `engine/ColorEngine.kt` + tipos | Base (completo) |
| `Model/WadaDictionary.swift` | `data/WadaDictionary.kt` (EngineWadaDictionary hoy) | W1: cargar `dictionary.json` + `names.{es,de}.json` como assets generados desde `data/wada` (¡`names.es.json` es ruta protegida: solo lectura; script Gradle que copia a build, como los goldens), chequeo `dict_version`, colecciones curadas, cmyk |
| `Model/Color+Wada.swift`, `Model/GarmentText.swift` | `data/` (textos de prenda con strings) | W1/W3 |
| `DB/AppDatabase.swift` + migraciones v1–v4 | Room `ColorsDatabase` (§7) | W1 |
| `DB/Records.swift`, `DB/UUIDv7.swift`, `DB/AnalysisPolicy.swift` | `data/Records.kt` (ya) + UUIDv7 en W1 | Base/W1 |
| `DB/Repositories.swift` | `data/Repositories.kt` (interfaces + memoria) | W1 pone Room |
| `Scan/ScanRunning.swift` | `scan/ScanRunning.kt` | Base |
| `Scan/PhotoKitScanRunner.swift` | `scan/MediaStoreScanRunner.kt` | W2 (MediaStore, miniaturas 256, 3 en paralelo, unlocks) |
| `Subject/SubjectSettings.swift` | `subject/SubjectSegmentation.kt` (SubjectSettings/Options) | Base |
| `Subject/LayerBitmaps.swift`, `SyntheticPersonScene.swift` | `subject/` (bitmaps de capas; escena sintética para tests) | W2/W4 |
| `Support/LaunchCounter.swift` | `LaunchCounter` en AppContainer | Base |
| `Support/Diagnostics*.swift` + `DiagnosticsZip.swift` | `data/Diagnostics.kt` (zip con `java.util.zip`, compartir por Intent) | W4 |

### SubjectKit (`apple/SubjectKit/Sources/SubjectKit/`)

| SubjectKit | Android (`subject/`) | Notas |
|---|---|---|
| `SubjectTypes.swift` | `SubjectSegmentation.kt` | Base: SubjectMode, RegionMode, MaskStep, SubjectMaskResult, PersonDetection |
| `VisionDetector.swift` | `PersonDetector` (interfaz) | W2 con el modelo del informe del carril B; general a propósito: máscara de instancia + pose 15 puntos + cara + mapa semántico opcional (piel/ropa) |
| `SubjectChain.swift`, `RegionPlanning.swift`, `MaskOps.swift`, `FaceSample.swift`, `PersonEvidence.swift`, `PersonSplit.swift` | `SubjectChain.kt` & cía. | W2: la cadena es plataforma-agnóstica; la geometría fina ya está en C (`clothingRegions`, `garmentRegions`, `fitSkinModel`, `excludeSkin`, `splitInstance`, `cutHead`) |
| `Raster.swift` | `EngineRaster` + helpers | Base |
| `SubjectMetrics/SkinMetrics.swift`, `visionmask/` | (herramientas de evaluación, no van en la app) | W2 decide si portar el harness a `harness/` |

### Vistas

| iOS (`Views/`) | Android (`feature/`) | Carril |
|---|---|---|
| `Feed/*` (FeedView, FeedDayCard, FeedLuminousPost, FeedModel, FeedDemo, CameraPicker, ScanAnalyzer, NavigationRoutes…) | `feature/feed/` | W3. Picker de cámara/fotos = contratos ActivityResult; regla exacta de la combinación del día y datos demo incluidos |
| `Extract/*` (visor, pins, resultado) + `Resultado/ResultView*.swift` | `feature/extract/` | W3 con W2 (necesita la cadena de sujeto) |
| `Capas/*` (inspector de 11 capas, explicación, compartir) | `feature/layers/` | W4; el motor ya da todas las capas (`analyzeWithLayers`) |
| `Rejilla/*` (rejilla, buscador, ficha, aleatoria, renombrar) + `Explorar/*` (buscador de color, detalle) | `feature/grid/` | W4 |
| `Garden/*` (jardín, perfil, cosechas, estudio, exportar) | `feature/garden/` | W4 |
| `Wrapped/*` (onboarding del escaneo + resumen) | `feature/wrapped/` | W3 (con el escaneo) |
| `Tarjeta/*` (tarjeta para compartir) | `feature/share/` (render a Bitmap + Intent) | W4/W5 |
| `Ajustes/*` (ajustes, acerca de, licencias, diagnósticos) | `feature/settings/` | W4 (licencias ya en la base) |
| `Common/SecondaryChrome.swift` | en `SettingsScreen.kt` (`SecondaryTopBar`) | Base; mover a `design/` si W4 lo prefiere |
| `Design/DesignGalleryView`, `MotionGalleryView`, `Feed/DebugLaunch` | pantallas DEBUG equivalentes u omitir | W5 opcional; nunca en release |

### Recursos y proyecto

| iOS | Android |
|---|---|
| `Localizable.xcstrings` (683 claves es + de/en) | `res/values{,-de,-en}/strings.xml` vía script de volcado (W1): nombre de recurso estable derivado de la clave + manifiesto; los `%lld`/`%@` → `%1$d`/`%1$s` con orden |
| `InfoPlist.xcstrings` (textos de permisos) | strings de justificación en la UI antes de pedir permiso (Android no tiene texto en el diálogo del sistema) |
| `Resources/Fonts/*` + OFL | `res/font/literata.ttf`, `plus_jakarta_sans.ttf`, OFL en `assets/licenses/` (hecho) |
| `dictionary.json` + `names.*.json` en el bundle | assets generados en build desde `data/wada` (W1), sin duplicar en git |
| `Assets.xcassets/AppIcon.appiconset` | `android/icon/icon_master.png` + `make android-icon` (hecho) |
| `Info.plist` (vertical, sin red) | `AndroidManifest.xml` (hecho; permisos según carril) |
| Tests XCTest (`ColorsAppTests`, `EngineParityTests`, SubjectKitTests) | JUnit host + instrumentados por módulo; paridad ya hecha |

## 5. Ola 2: cinco carriles en paralelo

Regla de oro: **cada carril escribe solo en sus paquetes**. Lo compartido
(`app/`, `design/`, interfaces de `data/`, `subject/`, `scan/`,
`strings.xml` común, `libs.versions.toml`) lo toca solo quien lo posee según
la tabla; el resto pide cambios ahí al integrador o los deja como nota.
`strings.xml`: cada carril añade su fichero `strings_<carril>.xml` en las
tres carpetas de idioma para no pisar el mismo fichero (Android fusiona por
nombre de recurso; sin duplicados).

| Carril | Posee (escribe) | Programa contra | Entrega |
|---|---|---|---|
| **W1 Datos** | `app/.../data/` (Room, diccionario JSON, UUIDv7, volcado de strings), `app/AppContainer.kt` (solo cableado), deps en `libs.versions.toml`/`build.gradle.kts` | `Repositories.kt`, `Records.kt`, `WadaDictionary` (ya) | Room con esquema v1–v4 (§7) + `JsonWadaDictionary` con test de `dict_version` y de migraciones; `tools/dump_strings.py` xcstrings→xml |
| **W2 Sujeto y escaneo** | `app/.../subject/` (impls), `app/.../scan/` (impls), assets del modelo, permisos de fotos/cámara en el manifiesto | `PersonDetector`, `SubjectSegmenter`, `ScanRunning`, `PhotoLibrarySource`, API `:engine` | detector con el modelo del carril B (empaquetado, sin descargas) + cadena completa (mask, garmentRegions, steps, timings) + `MediaStoreScanRunner` día 0 + tests con `harness/people` |
| **W3 Feed y Extraer** | `app/.../feature/feed/`, `feature/extract/`, `feature/wrapped/`, rutas nuevas en `ChromaSolApp.kt` solo añadiendo destinos | repos (W1), segmentador (W2, con `WholePhotoSubjectSegmenter` mientras), `design/` | Feed foto-primero con escaneo y tarjeta del día exacta, Extraer (cámara/picker) + Resultado con avisos de la cadena, onboarding y Wrapped |
| **W4 Rejilla, Jardín, Capas y Ajustes** | `feature/grid/`, `feature/garden/`, `feature/layers/`, `feature/settings/`, `data/Diagnostics.kt` | repos (W1), diccionario (W1), capas del motor | rejilla 348 con búsqueda/filtros/detalle, jardín con colecciones y exportación, inspector de capas con compartir, ajustes completos y diagnósticos |
| **W5 Pulido y marca** | `app/.../design/` (solo motion/brand nuevos), `feature/share/`, tests visuales | todo lo anterior | personajes de pestaña y movimiento ambiental de FIDELITY.md, tarjeta para compartir, pase de fidelidad con capturas vs `fastlane/screenshots`, rendimiento de listas |

Orden de mezcla: **W1 primero** (desbloquea datos reales), luego W2, y W3/W4
encima (pueden empezar ya contra los stubs de la fundación); W5 el último,
solo aditivo en `design/`. Conflictos previsibles, ya acotados: `AppContainer`
(solo W1 lo edita tras la fundación; W2 registra su runner pidiendo el
cambio a W1 o en su mezcla), `AndroidManifest.xml` (solo W2 añade permisos;
nadie más lo toca), `ChromaSolApp.kt` (cada carril añade sus `composable(...)`
y rutas en `Routes` sin reordenar), `libs.versions.toml` (solo W1 en su
mezcla; el resto declara la dependencia en su PR y la resuelve el integrador).

## 6. Qué no puede ser idéntico (y el equivalente elegido)

| Aspecto | iOS | Android | Impacto |
|---|---|---|---|
| Detección de personas/pose/caras | Vision (sistema) | Modelo empaquetado (decisión del carril B; prohibido descargar en tiempo de ejecución) | Las máscaras no serán las de Vision: misma cadena y mismo motor detrás, pero los resultados foto a foto pueden diferir donde el detector difiera. Es LA diferencia funcional del port. |
| Rasterizado a 1024 px | CoreGraphics sRGB con interpolación .high | Android: decodificación Bitmap (sRGB) + escalado bilineal de Canvas | Píxeles ligeramente distintos al reducir → el motor da lo mismo para los mismos píxeles, pero la misma foto no produce bits idénticos a iOS tras el escalado de plataforma. A 1:1 (≤1024 px) sí es byte a byte. |
| Espacios de color de la foto | ColorSync convierte P3/ICC a sRGB al dibujar | BitmapFactory entrega sRGB por defecto (API 26+); fotos P3 llegan convertidas por el decodificador | Conversión de plataforma distinta, mismo espíritu. Verificar con fixtures P3 en W2 (EngineParityTests de iOS es el modelo). |
| Materiales | `.ultraThinMaterial` (desenfoque real) | Tinte `frostTint` 78 % sin desenfoque (blur de fondo = API 31+ y caro) | Barras un poco más planas sobre fotos; el contraste AA se mantiene por diseño del token. |
| Tipografía dinámica | Dynamic Type por rol (`relativeTo`) | sp con el tamaño de letra del sistema, sin granularidad por rol | Con letra de accesibilidad los saltos entre roles no replican la tabla de iOS. |
| Fecha en la BD | GRDB guarda `Date` como texto | Room: epoch ms `INTEGER` (decisión W1, documentada) | Las BD no se comparten entre plataformas; migraciones y semántica sí son las mismas. |
| ID de foto | `PHAsset.localIdentifier` | Uri de MediaStore (`content://…/images/media/<id>`) | Estable mientras la foto exista; no portable entre dispositivos (igual que en iOS). |
| Fotos solo en la nube | iCloud: se omiten sin red (`needsPicker`) | No aplica: MediaStore es local (o el proveedor devuelve el fichero) | Menos casos borde; se mantiene la rama `needsPicker` para acceso limitado. |
| Selector de fotos | PhotosPicker / acceso limitado | Photo Picker del sistema (sin permiso); acceso limitado con `READ_MEDIA_VISUAL_USER_SELECTED` (API 34+) | Equivalente funcional; UX del sistema distinta. |
| Compartir | UIActivityViewController | `Intent.ACTION_SEND` + FileProvider | El contenido (tarjeta/capas/zip) es el mismo. |
| Personajes/movimiento | SwiftUI Canvas + TimelineView | Compose Canvas + `withInfiniteTransition`/reloj propio | Paridad visual por FIDELITY.md, no de código; «reducir movimiento» se lee de Ajustes del sistema vía `Settings.Global.ANIMATOR_DURATION_SCALE`. |
| Iconos de pestaña | Personajes originales; SF Symbols de respaldo | Glifos propios en `SolarIcons.kt` (fundación) | W5 porta los personajes; SF Symbols no existe en Android. |
| Firma/publicación | App Store | Play App Signing: se sube el AAB; la clave de subida va por env vars (ver `android-bundle`) | La clave de firma final la guarda Google; el dueño crea la de subida (pendiente, §8). |

## 7. Base de datos (contrato para W1)

Mismo esquema que GRDB, mismas tablas y columnas `snake_case`, mismas
migraciones versionadas (Room `@Database(version = 4)` con migraciones
1→2, 2→3, 3→4 que ejecuten exactamente lo mismo que `AppDatabase.swift`:
v2 añade a `scans` las columnas de sujeto y convierte el ajuste heredado
`person_mask`; v3/v4 las de prendas y política; leer el Swift y sus tests
`SubjectDatabaseTests`/`GarmentDatabaseTests` y replicar los casos). Nunca
`fallbackToDestructiveMigration` (en iOS `eraseDatabaseOnSchemaChange =
false` también en Debug: hay desbloqueos del usuario). Tipos: ids TEXT
(UUIDv7 como en iOS), booleanos INTEGER 0/1, fechas INTEGER epoch ms,
`scores`/`palette_json`/`garments_json`/`mask_steps` JSON compacto con
claves en el mismo orden que `JSONCoding` de iOS (sortedKeys) para que un
volcado de diagnóstico se lea igual en las dos plataformas. Room exige
ksp/kapt: lo añade W1 al catálogo en su mezcla.

## 8. Pendiente del dueño / decisiones abiertas

1. **Clave de subida de Play** (keystore): la crea y guarda el dueño; hasta
   entonces `make android-bundle` produce el AAB sin firmar (válido para
   revisarlo con bundletool, no para subirlo).
2. **Icono nuevo 3D**: dejar el máster en `android/icon/icon_master.png` y
   `make android-icon`; revisar la silueta monocroma generada.
3. Informe del **carril B** (segmentación): su modelo elegido aterriza en
   `PersonDetector`; si el modelo no da pose, la cadena cae a
   `cutHead`/`wholePerson` como en iOS sin pose (ya previsto en el contrato).
4. Textos y gráficos de Play: carril C en `docs/play/` (este documento no
   los toca).
5. `resourceConfigurations` fijado a es/de/en en `:app`: si alguna
   dependencia futura mete otros idiomas, seguirán recortados; revisar si
   Play exige algo más para la ficha (no para la app).

## 9. Verificación de esta fundación

Todo lo de arriba se ha ejecutado en esta máquina; la salida real va en el
informe del carril. Para repetirlo:

```
make golden-check          # referencia del motor en el host (sigue verde)
make android-build         # APK debug
make android-test          # unit JVM :engine + :app
make android-lint          # release sin INTERNET + lint
make android-bundle        # AAB release
make android-emulator      # en otra terminal o antes; deja el AVD listo
make android-test-device   # paridad 20+50+20 y humo de pestañas en el AVD
make android-screenshots   # harness/out/android/tab-feed|extract|grid|garden.png
# al terminar: adb emu kill
```
