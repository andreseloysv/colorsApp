# Decisiones de arquitectura (ADR)

Registro corto y numerado. Una decisión "fija" no se reabre sin una entrada nueva
que la sustituya. Fecha de partida: 2026-09-14.

## ADR-001 — App iOS nativa en SwiftUI

**Decisión.** La app es nativa iOS (Swift/SwiftUI, deployment target iOS 17, Xcode 27,
proyecto generado con XcodeGen desde `ios/project.yml`). Android y web quedan fuera
del MVP.
**Motivo.** Es la plataforma pedida por el usuario; PhotoKit (escaneo del carrete),
Vision (máscara de persona) y `ImageRenderer`/`ShareLink` solo existen en nativo.
Una PWA no puede enumerar el carrete (sin File System Access API en Safari).
**Consecuencias.** Toda la UI y el acceso a fotos viven en `ios/`. Xcode 27 solo
depura iOS ≥ 17, de ahí el target.

## ADR-002 — Un motor, dos targets: C puro compilado a nativo y a WASM

**Decisión.** El motor de color se escribe en C11 (`engine/Sources/CColorEngine`),
sin I/O, sin `malloc`, sin dependencias más allá de `<math.h>`. La misma fuente
compila a nativo (SwiftPM para iOS/macOS, CMake para la CLI `ce` y los tests) y a
WebAssembly (Emscripten) para una futura app web con exactamente el mismo motor.
**Motivo.** Decisión cerrada del usuario: "the color engine should be written in C
and port via wasm bc I want also the exact same engine for the web app later".
Además el differential testing nativo/WASM detecta comportamiento indefinido.
**Consecuencias.** Nada de lógica de color en Swift ni en JS; el wrapper Swift
(`engine/Sources/ColorEngine`) solo traduce tipos. El llamante reserva el contexto
(`ce_ctx_size`/`ce_ctx_init`); no hay estáticos mutables.

## ADR-003 — Determinismo numérico

**Decisión.** `#pragma STDC FP_CONTRACT OFF` en cada `.c`, todo en `double`, nunca
`-ffast-math`, `-Ofast` ni `-ffp-contract=fast`, nunca `unsafeFlags` en
`Package.swift`. CMake añade `-ffp-contract=off -Wall -Wextra -Werror -Wpedantic`.
**Motivo.** El mismo píxel debe dar los mismos bits (salvo libm) en iOS y en WASM;
la paridad se mide a 1e-9 y los empates se resuelven por id de combinación.
**Consecuencias.** Sin RNG en el motor (histograma → MMCQ → Lloyd ponderado, todo
determinista). Si libm diverge, se añade `ce_libm.c` portable.
Medido en F5 (`make parity`, 20 fixtures, 2026-09-15): con la libm del sistema, Lab y scores a ≤ 5,7e-14 salvo en swatches acromáticos, donde ΔE00 ∝ √C' en C' = 0 amplifica 1e-14 de libm a 2,4e-8 en el score (rampa de grises). **Resolución (misma fecha):** `ce_libm.c` implementado (cbrt, pow, exp, atan2, sin, cos de musl 1.2.6, sin FMA, compilados con el motor en todas las plataformas): `make parity` sale 0 con la salida JSON byte a byte idéntica en las 20 fixtures (|Δ| = 0, hash igual 20/20) y `test_math` gatea un golden de bits de las seis funciones (`HASH_LIBM`) igual en nativo, ASan y WASM; coste medido: paleta 1024² 2,27 → 2,70 ms, match 0,034 → 0,047 ms (`engine/BENCHLOG.md`). El `hash` de resultados pasa a ser comparable entre plataformas.

## ADR-004 — Espacio de color único: CIELAB D65 + ΔE2000

**Decisión.** Lab D65 con la matriz derivada de los primarios sRGB (blanco exacto
L = 100), ε/κ exactos, ΔE2000 según Sharma/Wu/Dalal 2005 (kL = 1; kL = 2 como
variante medida). OKLab fuera del MVP.
**Motivo.** Es lo que valida el oráculo (`colour-science`, test set de Sharma) y lo
que el diccionario de Wada necesita para un match creíble.
**Consecuencias.** El diccionario embebe solo sRGB8; el Lab lo calcula el motor con
la misma función que usa para la foto.

## ADR-005 — Sin red en la app

**Decisión.** La app no abre conexiones: sin `URLSession`, `NWConnection` ni
`CFNetwork` en `ios/` (CI: grep = 0). Las fotos se procesan en el dispositivo y solo
salen del teléfono por acción explícita del usuario ("Exportar diagnóstico").
**Motivo.** Privacidad de fotos personales, MVP sin servidor y sin cuentas, y ninguna
capability de cuenta de pago.
**Consecuencias.** El diccionario y los nombres curados van en el bundle; servidor,
sync y roles quedan para el post-MVP.

## ADR-006 — Distribución con Personal Team (Apple ID gratuito)

**Decisión.** Firma automática con el Personal Team del Apple ID del usuario;
bundle ID único y estable `com.andreseloy.colorsapp`; reinstalación semanal en los
dos iPhones (`make ios-install`, ritual en `docs/RELEASE.md`). No se paga el Apple
Developer Program hasta que la app "se sienta bien" (gate de la fase 10).
**Motivo.** Petición explícita del usuario. Límites del Personal Team: 3 dispositivos,
10 App IDs, 3 apps por dispositivo, perfiles de 7 días.
**Consecuencias.** Prohibidos push, iCloud, Sign in with Apple, Associated Domains,
App Attest, extensiones, TestFlight y App Store Connect. Plan B: SideStore.

## ADR-007 — Harness anti-Goodhart con rutas protegidas

**Decisión.** Umbrales, goldens, datos de test, oráculo de referencia, generadores
sintéticos, herramientas de etiquetado y datos curados están en
`harness/PROTECTED.txt`; `make check-protected` (hook pre-commit) falla si el árbol
los toca sin `COLORSAPP_ALLOW_PROTECTED=1`, y `harness/PROTECTED.sha256` detecta
cambios silenciosos. La semilla del holdout y el set dorado viven fuera del repo.
**Motivo.** El motor lo programa un agente de IA; el validador no puede ser editable
por el mismo agente que optimiza contra él.
**Consecuencias.** El agente propone (`thresholds.proposed.json`,
`names.suggested.json`); el usuario promueve. Es detección, no prevención.

## ADR-008 — Idioma y organización del repo

**Decisión.** Docs y comentarios en español; identificadores, ficheros y símbolos en
inglés. El Makefile raíz no se edita: cada área añade `mk/<area>.mk`. Python siempre
vía `uv run --project oracle`.
**Motivo.** Un usuario hispanohablante y varios agentes trabajando en paralelo por
áreas sin pisarse.

## ADR-009 — Match con hipótesis de adaptación (exposición e iluminante)

**Decisión.** Desde la corrección de F3/F5 (2026-09-15) el score del match es el
mínimo, sobre un conjunto fijo de hipótesis de adaptación aplicadas a los swatches
(identidad; ganancias 2^EV con EV = k · 0,5 y |EV| ≤ 1; Bradford A/D50/D75/F2 → D65;
y sus combinaciones, 25 en total), del score de la fase 3 más una penalización lineal
(2,0 ΔE por EV, 2,0 ΔE por iluminante ≠ D65). La identidad siempre está y gana los
empates; con `exposure_ev_max = 0` e `illuminant_search = 0` el motor es exactamente
el match v0 (`ce_match_opts` gana esos cuatro campos al final del struct).
**Motivo.** La línea base L3 fallaba iluminante (@3 68 % < 80 %) y exposición (@1
22 % < 75 %) y ningún ajuste de kL/kC/λ/σ los alcanzaba (`engine/BENCHLOG.md`):
ΔE00 no es invariante a un cambio global de exposición ni a un iluminante sin
balance de blancos, así que hay que modelarlos. Con las hipótesis: illuminant
94,4/98,3, exposure 87,6/96,6, agregado 96,8/99,1 sin pérdida en el resto (clean,
shapes, texture, shading, JPEG 100 %; distractor 97,4/99,1); cuota máxima 0,9 %,
`ambiguous` 1,6 %.
**Consecuencias.** Match 0,03 → 1,2 ms nativo (cota 5 ms) y `ce_analyze` 1024² 3,8 ms
(cota 10 ms). Los iluminantes hipotéticos coinciden con los estándar CIE del
generador L3 (A, F2, D75): la mejora en `illuminant` es en parte tautológica y la
prueba real es L4 (fotos); el barrido con rejillas que no contienen ±1 EV ni F2/D75
sigue pasando los umbrales. El scorecard conserva el match v0 como columna
informativa `noadapt`; los goldens se regeneraron con motivo en `harness/CHANGELOG.md`
(recall 39/50 → 47/50).

## ADR-010 — Extracción de sujeto y piel: Vision para detectar, motor C para la geometría

**Decisión.** El sujeto de la foto se aísla en dos mitades con frontera fija:
- **Detección (plataforma):** el paquete `apple/SubjectKit` usa Apple Vision on-device
  (iOS 17 / macOS 14, sin red ni capabilities de pago): `VNGeneratePersonInstanceMaskRequest`
  (una petición; máscara por instancia con `generateScaledMaskForImage(forInstances:from:)`
  reescalada al raster con CoreGraphics; instancias con menos del 0,05 % del raster se
  descartan como fragmentos), `VNDetectHumanBodyPoseRequest` (cada pose va a la instancia que
  contiene más muestras de su esqueleto, con el torso contando doble) y
  `VNDetectFaceLandmarksRequest` (cada cara va a la instancia que contiene más muestras de su
  centro; la muestra de piel son mejillas y frente derivadas de los landmarks, sin ojos, cejas,
  labios ni pelo). Solo produce máscaras de instancia, puntos de pose, rectángulos de cara y
  muestras de piel en píxeles del raster que ve el motor.
- **Geometría y piel (motor C):** la región de ropa (`ce_mask_clothing_regions`,
  `ce_mask_cut_head`) y la exclusión de piel con un modelo gaussiano adaptativo
  (`ce_skin_model_fit` + `ce_mask_exclude_skin`, Mahalanobis 2,5, salvaguarda del 35 %) viven
  en el motor, deterministas y sin malloc, para que la web futura (MediaPipe como detector)
  aplique exactamente la misma lógica. SubjectKit solo prepara ENTRADAS del motor (puntos de
  pose, opciones, fracción de corte, muestra) y elige entre candidatas por recuento de píxeles.
- **Cadena por defecto (decisión del usuario: persona más grande + solo ropa + piel
  adaptativa)**, por persona y siempre sobre su máscara **binaria** (instancia de Vision
  `>= 128 → 255`; el halo blando 1…127 cae sobre vecinos y fondo y no entra ni en el bbox de
  `cutHead` ni en la máscara del motor):
  1. Muestra de piel: la de su cara o, si no tiene una utilizable (de espaldas, gafas,
     mascarilla, < 50 muestras), la de la persona de la foto con más muestras
     (`shareSkinModel`).
  2. Con pose: si el motor no puede formar las caderas pero sí los hombros (plano medio), se
     **estiman** (raíz a 1,2 anchos de hombros bajo la línea de hombros, lejos de la nariz;
     caderas a 0,75 de la separación de hombros; rodillas y tobillos fuera): torso superior y
     brazos, sin cabeza ni manos. Regiones con las opciones de la app; si se pidió piel y no
     hay modelo, sin brazos (manga corta = piel); con modelo, **prueba de brazos desnudos**:
     si >= 25 % de los píxeles de los brazos es piel según el modelo, se quitan. **Silueta de
     la pose**: la misma llamada con cápsulas de 1,0 anchos de hombros, margen de torso 0,35,
     antebrazos y piernas enteras (sigue sin cabeza ni manos). Se usan las regiones si miden
     >= 15 % de la silueta (suficiencia RELATIVA a la persona que describe la pose, no al
     raster ni a la instancia: un bebé dentro de un cochecito conserva su ropa y el cochecito
     no entra); si no, la silueta.
  3. Sin pose, con `CE_ERR_POSE` o con una silueta por debajo del suelo absoluto: `cutHead`
     con la altura de la cara si la hay (borde inferior + 0,25 · alto de la cara, entre 0,18 y
     0,5 del alto de la persona), 0,18 sin cara.
  4. Piel: `excludeSkin` sobre la región.
  5. Suelo absoluto de 0,05 % del raster (≈ 350 px en 1024 × 683): solo si la máscara final
     no llega se usa la silueta (con pose; nunca la instancia cruda de Vision) o la persona
     binaria (`wholePerson`), y si tampoco, sin máscara (`none`).
  `allPeople` une (máximo por píxel) las salidas que llegan al suelo; `off`, sin personas
  (`noPeople`) o Vision lanzando (`visionUnavailable`, simulador) analizan sin máscara, sin
  crash. Pasos en `SubjectMaskResult.steps`; decisión con recuentos en
  `PersonLayers.regionDecision` (fuente, píxeles requeridos, silueta, caderas estimadas,
  brazos probados y quitados, fracción de corte) y `fallbackSource`.
- **Capas visibles y reproducibles:** `SubjectLayers` expone por persona la persona binaria,
  la pose, la silueta, los brazos probados, la región, la muestra de piel, la piel quitada y la
  máscara final, más el mapa de instancias. `visionmask` (CLI macOS del mismo paquete) escribe
  el raster exacto de la app, las máscaras por variante, esas capas, la pose que recibió el
  motor (`pose.txt`, con caderas estimadas) y un `repro.sh` que recalcula cada capa y cada
  decisión con `ce regions|cut-head|skin` y la compara byte a byte. `make visionmask-people`
  lo ejecuta sobre `harness/people` con `ce batch` y reparte el peso de cada paleta en prenda /
  piel / fondo / otro con parches medidos a mano (`apple/SubjectKit/Fixtures/people_references.json`).

**Motivo.** El usuario fotografía a varias personas y el fondo y la piel meten error
(CONTEXT §10). Una regla de piel por color fijo borra colores de Wada (camel, beige, salmón:
la regla YCbCr bajó L3 del 97 % al 66 %), así que la piel se modela por persona desde su
cara y se limita por geometría. Vision es gratis, está en el dispositivo y separa hasta 4
personas; poner la geometría en C conserva «un motor, dos targets» (ADR-002).
La primera versión (cobertura mínima del 2 % del raster, `CE_ERR_POSE` → `cutHead` 0,18 sobre
la máscara blanda) dejaba en la paleta oficial de 05 un 44 % de piel, en 07 volvía a la persona
completa con el mural y en 08 se quedaba con cara y manos, aunque el ΔE00 del swatch dominante
parecía bueno; con el bebé del tranvía (CONTEXT §12) volvía a la instancia con el cochecito.
Medido en `harness/people` (8 fotos CC0; `make visionmask-people`, 2026-09-15), peso medio de la
paleta por clase (máximo por foto entre paréntesis):

| variante | prenda | piel | fondo | otro | ΔE00 dominante (media / mediana) |
|---|---|---|---|---|---|
| sin máscara | 13,0 % | 8,6 % (33,4) | 46,3 % (83,3) | 32,0 % | 42,3 / 35,4 |
| todas las personas | 38,1 % | 15,2 % (46,1) | 9,6 % (64,8) | 37,0 % | 11,0 / 2,2 |
| persona más grande | 45,9 % | 15,7 % (43,3) | 12,6 % (64,8) | 25,8 % | 2,6 / 2,2 |
| + solo ropa | 67,5 % | 15,4 % (46,3) | 1,8 % (14,2) | 15,4 % | 2,7 / 2,9 |
| **+ piel (defecto)** | **71,9 %** | **7,1 % (29,9)** | **1,8 % (14,2)** | **19,3 %** | **2,9 / 2,6** |

05 pasa de 44 % a 17 % de piel, 07 usa la región de la pose (fondo 0 %) y 08 usa el torso con
caderas estimadas (0 % de piel, 95 % de prenda). El dominante solo no distingue la variante por
defecto de la persona completa: por eso `make subject-test` falla si la variante por defecto no
deja menos piel y menos fondo de media que la persona completa o si alguna foto pasa del 35 %
de peso de piel. Las 66 comprobaciones de `repro.sh` coinciden byte a byte con la CLI (1 `skip`:
01 tiene < 50 muestras de piel). Las anotaciones son parches aproximados de una sola persona:
es evidencia orientativa; la prueba real es la capa 4 con el set dorado.

**Consecuencias.**
- Límites de Vision medidos: como mucho 4 instancias (06: 4 de 5; 07: 4 de 6, con tres mujeres
  fusionadas en una instancia: la cadena usa la pose que gana la asociación y la región deja
  fuera a las otras dos); el paraguas entra en la instancia (02; la región lo excluye); caras de espaldas,
  de perfil o con mascarilla no dan muestra (03, 04, 08) y una cara de ~35 px da < 50 muestras
  (01). En 05 Vision no da pose a la persona central (gafas de sol) ni en la foto entera ni en
  recortes de su bbox con márgenes de 0 a 50 % (probado): cae a `cutHead` y la mano extendida
  queda en parte (17 % de piel). Repetir la pose por recorte no se incorporó por no aportar
  en estas fotos.
- El modelo de piel es estrecho cuando la cara y el cuerpo tienen luz distinta (07: cara
  iluminada y brazos en sombra, 30 % de piel; 02: cara a la sombra del paraguas y piernas al
  sol). Barrido de `max_mahalanobis` con la variante por defecto (2,5 / 3,0 / 3,5 / 4,0): piel
  media 7,1 / 4,2 / 2,9 / 1,7 % (máx. 29,9 / 26,8 / 22,9 / 13,4), prenda 71,9 → 73,7 %, pero
  los colores del diccionario de Wada dentro del elipsoide de cada modelo pasan de 1–4 a 5–10
  de 159 (Ochraceous Salmon, Fawn, Cinnamon Rufous…). Se mantiene 2,5 hasta medir en la capa 4
  con prendas camel, beige y salmón. Una prueba de piernas desnudas análoga a la de brazos no
  se añadió: en 02 el modelo solo marca el 21 % de las espinillas (< 25 %).
- Propuesta para el motor (sigue abierta): región de torso superior cuando hay hombros y no
  caderas. Mientras tanto SubjectKit estima las caderas como entrada de `ce_mask_clothing_regions`
  (regla documentada en `SubjectExtractor.regionPose`, reproducible con `ce regions` y el
  `pose.txt` de las capas); la web debe aplicar la misma regla.
- Para la app: `headCut` ya no implica el 18 % fijo (ver `regionDecision.headCutFraction`),
  `wholePerson` con pose es la silueta (`fallbackSource`) y `poseRegions` seguido de `headCut`
  significa una pose que no describe a la persona. La app integra `SubjectKit` como paquete
  local (compila para iOS genérico sin firma) y debe pasar a Vision la imagen orientada con el
  mismo contenido que el raster.
- Coste en un Mac Apple Silicon (visionmask release, 1024 px): detección de Vision 0,47–0,74 s
  por foto (instancias, pose y caras; la primera carga los modelos) y cadena sin Vision
  1–13 ms por variante (la variante por defecto 3–12,5 ms). Medir en el iPhone antes del
  escaneo del carrete.
