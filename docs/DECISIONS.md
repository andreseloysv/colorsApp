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

**Actualización (2026-09-15, tarde): la hipótesis de iluminante deja de estar activa por
defecto.** `ce_match_opts_default` pasa a `illuminant_search = 0` (la exposición ±1 EV se
mantiene); la hipótesis sigue disponible como opción (`--illuminant-search 1`,
`MatchOptions.illuminantSearch = true`) y como columna informativa `illum1` de L3.
- **Caso real** (CONTEXT §11): foto de un tranvía, camiseta negra + pantalón rosa palo, recorte
  correcto. Paleta #222524 39 %, #b49aa2 23 %, #917a7e 16 %, #d5b8c0 13 %, #6b5a57 8 %. Con
  la hipótesis ganaba **Nº 067** (Olympic Blue + Dark Tyrian Blue, score 17,17): al «compensar»
  una luz A inexistente el mauve pasaba a azul y el negro a azul marino, y la penalización de
  2,0 no bastaba. Las fotos del iPhone ya llegan con balance de blancos: era una doble
  corrección. Sin la hipótesis: Nº 337 (19,56) y Nº 027 Corinthian Pink + Slate Color (21,56),
  la pareja más cercana a lo que ve el usuario (Wada no tiene rosa palo + negro exacto). El
  color de la top-1 más cercano al mauve gira 86,8° con la hipótesis y 4,1° sin ella.
- **Por qué L3 no lo vio**: el generador simulaba el iluminante completo con los mismos
  iluminantes que las hipótesis (la tautología ya anotada arriba). `wada_gen` (ruta protegida,
  pendiente de promoción) simula ahora el **tinte residual tras el balance de blancos**:
  `(1 − s)·I + s·Bradford(D65 → A/F2/D75)` con `s` ∈ [0,25, 0,35] por imagen (adaptación
  incompleta de CAT02 con D = 1 − s; razonamiento en la cabecera de `wada_gen.py`).
- **Medido** (dev 3480, columna oficial, `make l3`): antes (hipótesis + iluminante completo)
  illuminant 94,4/98,3, exposure 87,6/96,6, agregado 96,8/99,1; los defaults nuevos sobre el
  generador viejo habrían dado illuminant 54,5/65,1 (falla @3 ≥ 80); **después (defaults nuevos
  + tinte residual) illuminant 98,0/100, exposure 88,8/97,1, distractor 97,4/99,1, agregado
  98,0/99,6, cuota máxima 0,4 %, ambiguous 1,0 %: todos los umbrales de `thresholds.json` pasan
  sin tocarlos**. `illum1` sobre el mismo conjunto: illuminant 99,8/100, agregado 98,4/99,6
  (la hipótesis aporta 1,8 puntos en un tinte suave y cuesta lo de abajo).
- **Gate nuevo de giro de tono** (`oracle.hue_shift`, dentro de L3): 2040 paletas realistas fuera
  del diccionario (apagados, pasteles, tierras, neutros con un color, sombras de una prenda y 40
  de `harness/people`); fracción cuyo swatch cromático dominante y el color más cercano de la
  top-1 difieren > 60° en tono cuando el match v0 no lo hacía: **defaults 0,70 % (14/2005)**,
  **+iluminante 15,6 % (313/2005)**, sobre todo marrones y rosas apagados que caen en Nº 067.
  Umbral propuesto ≤ 1 % en `harness/out/thresholds.proposed.json` (no promovido; L3 lo aplica
  con ese valor por defecto).
- **Consecuencias**: goldens regenerados con motivo (recall de las 50 fixtures sin cambio: top-1
  47/50, top-3 49/50; con las fixtures viejas los defaults nuevos darían 41/44, ver
  `harness/CHANGELOG.md`); match por defecto 25 → 5 hipótesis (más rápido);
  `EngineBridge.appMatchOptions` queda como alias documentado de `MatchOptions.default`; las
  herramientas del Mac (`layers-report`, `visionmask-people`, `l4-people-smoke`, `l4-variants`,
  `label-html`) ya reproducen la app sin pasar flags. Regresiones: `test_false_adaptation_pink_black`
  (Unity), `cli_match_contract` (`ce match-palette`, CLI nuevo de paletas como texto),
  `ColorEngineTests.testPinkAndBlackPaletteDefaultsAvoidBlue` y `MatchPolicyTests` (app).

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
  muestras de piel en píxeles del raster que ve el motor. **Evidencia corporal**: Vision
  inventa instancias en imágenes sin nadie y en prendas sin persona, así que tras asociar poses y
  caras una instancia solo es persona con >= 2 puntos del torso (cuello, hombros, caderas, raíz;
  confianza >= 0,3) dentro de su máscara (tolerancia 2 px), con una cara asociada o, sin pose ni
  cara, con un **rectángulo de persona** de cuerpo entero (`VNDetectHumanRectanglesRequest`,
  confianza >= 0,3, pedido solo si alguna instancia no tiene pose ni cara; cada rectángulo va a la
  instancia con más píxeles dentro y cuenta si contiene >= 50 % de sus píxeles y estos cubren
  >= 10 % del rectángulo). La regla de forma sola (cobertura 1–60 %, alto/ancho 1,2–6, relleno
  <= 0,8, solidez <= 0,88, alto < 95 %) queda **desactivada por defecto** (`acceptShapeOnly`): la
  verificación mostró vestidos y monos colgados en percha y un perchero aceptados como personas por
  forma (alto/ancho 1,26–1,43, relleno 0,43–0,61, solidez 0,58–0,87, dentro del rango de las
  personas reales), con `headCut` sobre la prenda y el match cambiado en silencio. El resto se
  descarta (`PersonEvidence`, `SubjectMaskResult.rejectedPhantoms`, paso `.rejectedPhantom`) y,
  si no queda nadie, la foto se analiza completa. Es geometría de máscaras, puntos y rectángulos,
  sin color: la web aplica las mismas reglas a su segmentador y a su detector de personas.
- **Instancias fusionadas (actualización 2026-09-16, fallo real del usuario):** Vision junta en
  una sola instancia a personas que se tocan o se solapan (una selfie con los dos adultos hombro
  con hombro; `harness/people/07`, con varias mujeres en una instancia). Las caras y las poses sí
  salen por persona, así que SubjectKit (`PersonSplitter`) construye una **semilla** por persona
  y la geometría la decide el motor: `ce_mask_split_instance` da a cada píxel de la instancia la
  semilla con menor distancia al eje dividida por su semiancho (empate al índice menor), sin
  malloc y bit a bit igual en nativo y WASM (`SPLIT_HASH`). Semillas: pose con cuello o dos
  hombros → eje cuello (o punto medio de hombros) → raíz/caderas, o extrapolado 1,6 · anchura de
  hombros; semiancho 0,55 · anchura de hombros, mínimo 0,6 · ancho de su cara; cara sin pose →
  base del rectángulo hacia abajo 3,0 · alto, semiancho 1,1 · ancho; cara y pose se fusionan si el
  centro de la cara está a < 0,8 · ancho de cara del cuello o la nariz. Una semilla cuenta para
  una instancia si su cara cae dentro (>= 128) o su punto superior está en la máscara dilatada
  0,25 · ancho de cara **y** al menos la mitad de las 17 muestras de su eje están dentro (sin esta
  segunda condición 05 se separaba mal: la barbilla de la chica central cae en la máscara de su
  vecina). Una instancia con 2 o más semillas se separa, cada semilla con cara aporta además un
  **segmento de cabeza** (centro de la cara → punto superior del eje, semiancho 0,5 · ancho de
  cara; sin él la selfie sintética daba una persona con dos caras porque el eje de una pose
  empieza en el cuello), las partes de una misma semilla en varias instancias se unen, y cada
  semilla con >= 0,5 % del raster es una `PersonInstance` nueva (`splitFrom` = id de Vision,
  pose y cara propias, paso `.splitByPose` / `.splitByFace`), hasta 8 personas. Las instancias que
  no se separan asocian pose y cara como antes.
- **Caras que no son personas (semillas de cara con evidencia corporal):** convertir toda cara de
  Vision en una semilla de persona hace que un retrato enmarcado, una pantalla o una cara
  estampada en una camiseta cree una **persona fantasma** que se lleva parte de la ropa de la
  persona de verdad (medido con `harness/people/faces`: `poster_on_torso` daba 2 personas y la
  «mayor» era la fantasma, con la cobertura de la persona real cayendo de 6,2 % a 3,7 %). Por eso
  una semilla de **cara sin pose** solo cuenta si tiene cuerpo: un rectángulo de persona de Vision
  que sea EL SUYO (contiene el centro de la cara, empieza a su altura —como mucho un alto de cara
  por encima de su borde superior y medio por debajo— y baja al menos un alto de cara por debajo
  de ella) o >= 2 puntos utilizables de una pose que no es semilla, por debajo de la cara y dentro
  de su eje (`SplitOptions.requireBodyForFaceSeeds`, activo por defecto). La condición del borde
  superior es la que distingue «la cabeza de esta persona» de «una cara dentro del rectángulo de
  otra»: sin ella el rectángulo de la persona real validaba la cara de su camiseta.
- **Geometría y piel (motor C):** la región de ropa (`ce_mask_clothing_regions`,
  `ce_mask_cut_head`) y la exclusión de piel con un modelo gaussiano adaptativo
  (`ce_skin_model_fit` + `ce_mask_exclude_skin`, salvaguarda del 35 %; Mahalanobis 2,5 por
  defecto en el motor y 2,75 como preajuste de SubjectKit) viven en el motor, deterministas y
  sin malloc, para que la web futura (MediaPipe como detector) aplique exactamente la misma
  lógica. SubjectKit prepara ENTRADAS del motor (puntos de pose, opciones, fracción de corte,
  muestras), elige entre candidatas por recuento de píxeles y aplica reglas geométricas sin
  color documentadas aquí (evidencia corporal, crecimiento conectado de la piel en sombra y halo).
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
     hay modelo, **prueba de mangas**: los brazos se quedan si >= 70 % de sus píxeles está a
     Mahalanobis <= 2 del modelo gaussiano del torso (`ce_skin_model_fit` con el torso como
     muestra; camisa de espaldas en 03) y si no se quitan (manga corta = piel que nadie quita);
     con modelo, **piel del cuerpo aprendida**: si los brazos o las piernas son desnudos (>= 25 %
     de sus píxeles es piel con el modelo de la cara), hasta 2 pasadas amplían la muestra con los
     píxeles de la región (con brazos) que el modelo vigente marca como piel a Mahalanobis <= 3 y
     reajustan el modelo (se para si la pasada no añade nada, si marca > 35 % de la región o si el
     modelo ampliado dispararía la salvaguarda); después, **prueba de brazos desnudos** con el
     modelo final: si >= 25 % de los píxeles de los brazos es piel, se quitan. **Silueta de
     la pose**: la misma llamada con cápsulas de 1,0 anchos de hombros, margen de torso 0,35,
     antebrazos y piernas enteras (sigue sin cabeza ni manos). Se usan las regiones si miden
     >= 15 % de la silueta (suficiencia RELATIVA a la persona que describe la pose, no al
     raster ni a la instancia: un bebé dentro de un cochecito conserva su ropa y el cochecito
     no entra); si no, la silueta.
  3. Sin pose, con `CE_ERR_POSE` o con una silueta por debajo del suelo absoluto: `cutHead`
     con la altura de la cara si la hay (borde inferior + 0,25 · alto de la cara, entre 0,18 y
     0,5 del alto de la persona), 0,18 sin cara.
  4. Piel: `excludeSkin` sobre la región (umbral estricto 2,75); **crecimiento de la piel en
     sombra** (histéresis): los píxeles que quedan a Mahalanobis <= 5 del mismo modelo (candidatos de
     `excludeSkin` sin salvaguarda sobre la máscara ya excluida) y conectados por vecindad de 8 con
     la piel quitada en <= 12 pasos también se quitan, salvo que piel + crecimiento superen la
     salvaguarda del 35 % o el crecimiento supere 0,5 veces la piel quitada; y **halo** de 2 px:
     fuera también los píxeles a distancia de Chebyshev <= 2 de la piel quitada (bordes piel/prenda
     mezclados por desenfoque, JPEG y reescalado; además el motor promedia bloques de 4 px del raster
     de 1024 incluyendo los píxeles fuera de la máscara), salvo con la salvaguarda. El crecimiento y
     el halo son geometría de SubjectKit (sin comando `ce`; `repro.sh` comprueba el recuento de
     candidatos con `ce skin`; la web debe aplicar la misma geometría).
  5. Suelo absoluto de 0,05 % del raster (≈ 350 px en 1024 × 683): solo si la máscara final
     no llega se usa la silueta (con pose; nunca la instancia cruda de Vision) o la persona
     binaria (`wholePerson`), y si tampoco, sin máscara (`none`).
  `allPeople` une (máximo por píxel) las salidas que llegan al suelo; `off`, sin personas
  (`noPeople`, precedido de `rejectedPhantom` si Vision solo dio fantasmas) o Vision lanzando
  (`visionUnavailable`, simulador) analizan sin máscara, sin crash. Pasos en `SubjectMaskResult.steps`; decisión con recuentos en
  `PersonLayers.regionDecision` (fuente, píxeles requeridos, silueta, caderas estimadas,
  brazos probados y quitados, piernas probadas, mangas, fracción de corte) y `fallbackSource`;
  `learnedSampleMasks`, `skinLearningPixels`, `skinGrownMask`, `skinGrownPixels`,
  `skinGrowCandidatePixels` y `skinHaloPixels` para la piel.
- **Mapa de regiones de prenda (entrada de ADR-011):** con `SubjectOptions.computeGarmentRegions`
  (aditivo, **desactivado por defecto** hasta que la app integre las tarjetas de prenda: así los
  pasos, la máscara y lo que guarda la app no cambian), la cadena añade
  `SubjectMaskResult.garmentRegions` para la persona elegida y `PersonLayers.garmentRegions` por
  persona (`allPeople`), con el paso `.garmentRegions` al final. Es `ce_mask_garment_regions` (la
  geometría vive en el motor) con tres entradas que decide SubjectKit y la web debe repetir:
  1. la **máscara que recibe el motor** para esa persona (regiones de la pose o silueta, ya sin
     piel), no la instancia de Vision;
  2. la pose del motor (`regionDecision.regionPose`, con caderas estimadas si hizo falta) y las
     **opciones de la silueta** (`SubjectExtractor.garmentRegionOptions` = `silhouetteOptions`:
     margen de torso 0,35, cápsulas de 1,0 anchos de hombros, antebrazos y piernas enteras), con
     las que la máscara final cae entera dentro del mapa (medido: `upper + lower == máscara` en las
     7 fotos de `harness/people` con pose); es la configuración con la que se calibró la paleta por
     prenda (`--torso-margin 0.35 --limb-width 1.0 --forearms 1`, ADR-011);
  3. **caderas estimadas** (plano medio, sin caderas en la pose): no se ve la parte de abajo, así
     que los píxeles que el motor etiqueta 2 (la franja del torso más allá de las caderas
     inventadas) pasan a 1 y la persona tiene una sola prenda. Sin esta regla, 08 (busto, caderas
     inventadas) sacaba un tercer color «de abajo» (#a0cefe, 7,5 % del peso) que es la misma
     camiseta.
  Sin pose utilizable (recorte de cabeza), con `wholePerson`, sin máscara o con `CE_ERR_POSE` el
  mapa es nil y **la app sigue con el camino clásico** (`analyze`): sin geometría no hay prendas
  que separar (ADR-011). En `allPeople` el mapa va por persona y `SubjectMaskResult.garmentRegions`
  es nil (cada persona se analizaría con su propia máscara).
- **Capas visibles y reproducibles:** `SubjectLayers` expone por persona la persona binaria,
  la pose, la silueta, los brazos probados, la región, la muestra de piel, la piel quitada y la
  máscara final, más el mapa de instancias. `visionmask` (CLI macOS del mismo paquete) escribe
  el raster exacto de la app, las máscaras por variante, esas capas, la pose que recibió el
  motor (`pose.txt`, con caderas estimadas) y un `repro.sh` que recalcula cada capa y cada
  decisión con `ce regions|cut-head|skin` y la compara byte a byte. `make visionmask-people`
  lo ejecuta sobre `harness/people` con `ce batch` y reparte el peso de cada paleta en prenda /
  piel / fondo / otro con parches medidos a mano (`apple/SubjectKit/Fixtures/people_references.json`,
  con la piel también oscurecida en luz lineal ×0,6/×0,35/×0,2 y zonas de pelo) y mide con
  `SubjectMetrics` qué fracción de la paleta viene de píxeles reducidos de piel y qué fracción de la
  máscara es piel.

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
| + piel (defecto de adf1164) | 71,9 % | 7,1 % (29,9) | 1,8 % (14,2) | 19,3 % | 2,9 / 2,6 |
| + piel (corrección intermedia: 2,75, piel aprendida, halo 1, mangas) | 78,9 % | 0,0 % (0,0)* | 1,8 % (14,2) | 19,3 % | 2,7 / 2,6 |
| **+ piel (defecto actual: + crecimiento en sombra y halo 2)** | **79,7 %** | **0,0 % (0,0)*** | **1,8 % (14,2)** | **18,6 %** | **2,7 / 2,6** |

\* Métrica de swatches contra parches de piel ILUMINADA: la verificación mostró que no veía la piel
en sombra ni la de los bordes (swatches marrones a 12–39 ΔE00 de los parches: #7b5549 9 % en 05,
#876a55 7 % en 07, que seguían decidiendo el top-1). Medida corregida (`SubjectMetrics`, piel
iluminada y en sombra, sin zonas de pelo), variante por defecto, antes (corrección intermedia) →
después (actual):

| foto | cara visible | piel en la paleta (px reducidos) | piel en la máscara | prenda en la paleta (px reducidos) | top-3 (app, sin iluminante) | top-1 sin la piel que queda |
|---|---|---|---|---|---|---|
| 02 | sí | 1,2 → 0,7 % | 5,7 → 0,9 % | 34,1 → 36,2 % | [69, 221, 139] → igual | 69 → 69 (igual que con ella) |
| 05 | sí | 11,0 → 0,1 % | 9,2 → 4,0 % | 55,7 → 63,6 % | [237, 231, 212] → [67, 218, 324] | antes 218 ≠ 237; después 67 = 67 |
| 06 | sí | 0 → 0 % | 0 → 0 % | 67,0 → 67,0 % | [139, 218, 67] → igual | igual |
| 07 | sí | 5,5 → 0,5 % | 8,3 → 3,0 % | 59,7 → 64,6 % | [55, 8, 273] → [55, 34, 218] | antes 34 ≠ 55; después 55 = 55 |
| 01, 03, 04, 08 | no | 0–0,3 % sin cambio | 0–2,2 % sin cambio | sin cambio | sin cambio | – |

Media de la variante por defecto: piel en la paleta 2,3 → 0,2 % (máx 11,0 → 0,7), en la máscara
3,3 → 1,4 % (máx 9,2 → 4,0), prenda en la paleta 70,0 → 71,9 %. Con los swatches clasificados
también contra la piel en sombra (`make visionmask-people` actual) la piel de la variante por
defecto es 1,1 % de media (máx 8,5 %: el swatch #462a1c de 02 es pelo, que en las medidas por
píxel cae en la zona de pelo).

05 pasa de 44 % a 17 % de piel, 07 usa la región de la pose (fondo 0 %) y 08 usa el torso con
caderas estimadas (0 % de piel, 95 % de prenda). Con la cadena actual (misma herramienta y mismo
motor, 2026-09-15) la piel de la paleta por foto antes → después es 02: 9 → 0 %, 05: 17 → 0 %,
07: 30 → 0 % y 0 → 0 % en el resto; la prenda nunca baja (02: 50 → 51, 03: 63 → 80, 05: 44 → 55,
07: 38 → 65 %) y el ΔE00 medio de la prenda 1 pasa de 5,6 a 2,7 (03: 27,7 → 3,1 al conservar las
mangas). En 07 el top-1 deja de ser Nº 8 (Cinnamon Rufous, el tono de la piel) y en 05 Nº 231
(Cameo Pink + Hay's Russet). Personas fantasma con visionmask (imágenes con persona aceptada; antes =
regla de forma sola, después = pose, cara o rectángulo de persona): 148 sintéticas sin personas de
`harness/people/nopeople` 7 → 0 (las 7 eran prendas: vestido en percha, abrigo en puerta ×4,
perchero, conjunto plano; 32 imágenes con instancias de Vision), 20 del carrete del simulador 0 → 0
(2 con instancias), 20 imágenes del verificador 3 → 0 (hanger_dress_0, hanger_dress_3, rack_1),
12 prendas colgadas del verificador 1 → 0 (hang_dress_08), 100 de la capa 3 0 → 0 (7 con
instancias); ninguna de esas 300 imágenes tiene rectángulo de persona. `harness/people` 18 → 18
personas (16 por pose, 2 por cara; sin pose ni cara pasarían 17 de 18 por forma y 16 de 18 por
rectángulo).

**Separación de instancias fusionadas (medido con `visionmask`, macOS 26, 2026-09-16).**
Instancias de Vision → personas: 01 1→1, 02 1→1, 03 2→2, 04 2→2, 05 3→3, 06 4→4, **07 4→7**
(dos instancias separadas: 1→2 y 2→4, las dos por pose) y 08 1→1; `synthetic_tight_selfie`
(derivada de 05 con `make_tight_selfie.py`, Vision junta a dos mujeres) **2→3**, separada por
cara. Total de `harness/people` 18 → 21 personas. En 07 la persona por defecto deja de ser la
instancia fusionada de tres mujeres (que no es ninguna persona) y pasa a ser la mujer de la
izquierda anotada en `expected.json`, con su propia región de prenda y su propia paleta.
Contrapartida medida y anotada como límite conocido del **modelo de piel** (no de la separación,
`PeoplePhotosTests.knownSkinLimits`): con esa persona el modelo ajustado a su cara al sol (muestra
de 106 px) no alcanza sus piernas desnudas en sombra, y la piel de la máscara pasa de 3,0 % (sobre
la instancia fusionada) a 24,2 % (sobre la persona correcta); con `SplitOptions(enabled: false)` el
gate vuelve a pasar.

Caras que no son personas (`harness/out/faces`, 8 fixtures derivadas de 01 y 05 con
`harness/people/faces/build_faces.py`; personas detectadas con la regla de evidencia corporal
activa → sin ella → sin separar):

| fixture | con la regla | sin la regla | sin separar | qué pasa |
|---|---|---|---|---|
| `poster_touching` | 1 | 1 | 1 | el retrato no entra en la instancia de la persona |
| `screen_touching` | 1 | 1 | 1 | idem |
| `poster_behind` | 1 | 1 | 1 | la persona tapa el retrato |
| `screen_behind` | 1 | 1 | 1 | la semilla de la pantalla no llega a la mitad del eje dentro |
| **`poster_on_torso`** | **1** | **2** | 1 | cara estampada en el pecho: sin la regla, persona fantasma con la mitad de su ropa (cobertura de la real 6,2 % → 3,7 %) |
| `screen_on_torso` | **2** | 2 | 1 | **límite abierto**: Vision devuelve una POSE entera dentro de la pantalla (cuello y caderas propios), así que la semilla es de pose y la regla de las semillas de cara no la ve; la separación reparte fielmente lo que Vision dice que hay |
| `poster_alone` | 1 | 1 | 1 | **límite abierto** de la regla anti-fantasmas: la instancia del retrato solo tiene cara y se acepta (regla 2) |
| `screen_alone` | 1 | 1 | 1 | idem |

Los dos `*_alone` bajan a **0 personas** con `PhantomOptions.requireBodyForFaceOnly` (nueva,
apagada por defecto; `visionmask --face-only-body`): la regla 2 exige entonces que el rectángulo de
persona de la instancia sea el de esa cara. Medido sin ningún cambio en `harness/people` (los mismos
1/1/2/2/3/4/7/1 y las dos personas de 05 aceptadas por cara conservan su rectángulo). Se deja
apagada porque cambia el comportamiento por defecto de la detección y el contrato de la regla
anti-fantasmas; promoverla es cambiar el valor por defecto y una línea de `PhantomEvidenceTests`. El dominante solo no distingue la variante por
defecto de la persona completa: por eso `make subject-test` falla si la variante por defecto no
deja menos piel y menos fondo de media que la persona completa o si alguna foto pasa del 35 %
de peso de piel, y además si alguna foto con cara visible (modelo de piel propio o compartido)
pasa del 5 % de piel en la paleta (px reducidos) o en la máscara (piel en sombra incluida) o la
prenda media baja frente a «solo ropa» (swatches y paleta por píxel); también si una imagen de
`sim_media` o más del 2 % de las 148 sintéticas (o de sus 48 prendas) conservan una persona.
`make visionmask-people` aplica el mismo gate de piel. Las 95 comprobaciones de `repro.sh`
coinciden con la CLI, incluido el recuento de candidatos del crecimiento (7 `skip`: 01 tiene < 50
muestras de piel; crecimiento y halo de 02, 05 y 07 sin comando `ce`). Las anotaciones son parches aproximados de una sola persona:
es evidencia orientativa; la prueba real es la capa 4 con el set dorado.

**Consecuencias.**
- Límites de Vision medidos: como mucho 4 instancias (06: 4 de 5; 07: 4 de 6, con tres mujeres
  fusionadas en una instancia: la cadena usa la pose que gana la asociación y la región deja
  fuera a las otras dos); el paraguas entra en la instancia (02; la región lo excluye); caras de espaldas,
  de perfil o con mascarilla no dan muestra (03, 04, 08) y una cara de ~35 px da < 50 muestras
  (01). En 05 Vision no da pose a la persona central (gafas de sol) ni en la foto entera ni en
  recortes de su bbox con márgenes de 0 a 50 % (probado): cae a `cutHead`; la mano extendida
  quedaba en parte (17 % de piel) y con el umbral 2,75 y el halo sale de la paleta (0 %), aunque
  quedan uñas rosas y pelo en «otro». Repetir la pose por recorte no se incorporó por no aportar
  en estas fotos.
- La piel en sombra conectada a la piel quitada (cuello y axila en 07, canto de la mano, dedos y
  muñeca en 05) queda fuera del elipsoide de 2,75 aunque el modelo se aprenda del cuerpo. Medido en
  numpy con las exclusiones del motor reproducidas bit a bit y la métrica corregida: umbral de
  crecimiento 4,5 deja 05 en 5,5 %; 5,0 con 12–24 px y halo 2 deja 02/05/07 en 0,6–0,7 / 0,0–0,2 /
  0,5 %; con halo 1, 05 y 07 siguen en 6,0 y 5,6 %; las manos de Vision (`VNDetectHumanHandPoseRequest`)
  como exclusión geométrica no hicieron falta y quitaban prenda entre los dedos. Riesgo espacial
  (simulación sobre las regiones reales de 02/05/06/07 con la prenda anotada recoloreada con cada
  uno de los 159 colores de Wada conservando su textura de luminancia; «perdida» = > 50 % fuera):
  prenda entera 1 → 2 pérdidas de 636 (> 25 %: 9 → 11; media 0,6 → 1,8 %), mitad superior de la
  prenda 11 → 11 (> 25 %: 13 → 19; media 1,7 → 4,0 %); sin el tope de 0,5 veces la piel quitada
  eran 7 y 15. Queda sin quitar: en 05 la sombra bajo el pulgar, el brazo de la amiga que abraza
  y los dedos de la mano de la derecha (4,0 % de la máscara, 0,1 % de la paleta); en 07 motas en
  dedos y tobillo (3,0 %). Vuelta atrás: `skinGrowRadius = 0` y `skinHaloRadius = 1`.
- El modelo de piel de la cara es estrecho cuando la cara y el cuerpo tienen luz distinta (07:
  cara iluminada y hombros, escote y brazos en sombra o al sol, 30 % de piel; 02: piernas en
  sombra). Medido con una reproducción numpy del modelo del motor (exclusiones idénticas a las
  del motor en 02, 05, 06 y 07): subir solo el umbral no basta (3,0: 07 sigue en 27 %); la
  varianza a priori en L propuesta por el verificador (σ = 15 en `cov[L][L]`) deja 07 en 12 % y
  05 en 6 % (con halo, 7 % y 0 %). La combinación elegida, toda en SubjectKit con funciones del
  motor (umbral 2,75 + piel del cuerpo aprendida con miembros desnudos + halo de 1 px), deja 0 %
  de piel en las 4 fotos con cara visible, quita <= 0,1 % de los píxeles del color de la prenda
  anotada (halo incluido) y sube la prenda media de 71,9 a 78,9 %. Riesgo medido (simulación en Lab sobre las regiones reales de 02,
  06 y 07 con una prenda sombreada de cada uno de los 159 colores de Wada como pieza del torso
  —15 y 30 %—, como mangas o como pantalón; «perdida» = > 50 % de sus píxeles fuera): 28 → 47
  pérdidas de 1908 casos (+1 punto), sobre todo colores cercanos a la piel (camel, beige, salmón,
  rosas) cuando los brazos o las piernas desnudos activan el aprendizaje. Se acepta hasta medir en
  la capa 4 con prendas de esos colores; `skinLearningIterations = 0`, `skinHaloRadius = 0` y
  `skinOptions.maxMahalanobis = 2,5` vuelven a la cadena de adf1164.
- Propuesta para el motor (dueño de `engine/**`; no aplicada): (1) `ce_skin_fit_opts {double
  prior_var_L; double prior_var_ab;}` y `ce_skin_model_fit_ex(img, sample_mask, opts, out)` que
  sume `prior_var_L` a `cov[0]` y `prior_var_ab` a `cov[4]` y `cov[8]` antes de invertir (0 = el
  ajuste actual bit a bit; preajuste propuesto 15² = 225 en L), con `ce skin --prior-var-l F` en la
  CLI; (2) `ce_mask_dilate(inout, width, height, radius)` (Chebyshev, dos pasadas separables) y
  `ce skin --halo R` para que el halo y (3) `ce skin --learn N --learn-mahalanobis F --zone
  zona.pgm` para que la piel aprendida se reproduzcan con la CLI y la web los comparta. Con (1)
  el aprendizaje podría bajar a 1 pasada y el riesgo medido de la prior sola es menor (pérdidas
  3/6/4 frente a 2/4/8 de la base en 02/06/07, escenario de pieza del torso). (4) `ce skin
  --grow-mahalanobis F --grow-radius N --grow-max-ratio F` (crecimiento conectado, BFS por capas en
  orden de índice) para el crecimiento. (5) `ce_image_reduce` promedia el color de TODO el bloque
  aunque parte esté fuera de la máscara (el peso es la media de la máscara): la piel y el fondo
  quitados vuelven a la paleta mezclados en los bloques del borde. Propuesta: color = Σ m·p / Σ m
  cuando hay máscara (sin máscara, idéntico bit a bit); emulado con una imagen preprocesada (fuera
  de la máscara, el color medio ponderado del bloque dentro), el swatch de piel de 07 con crecimiento
  a Mahalanobis 4 y halo 1 pasa de 5,3 % a 0 %. Cambia goldens con máscara y la paridad de capas.
- Propuesta para el motor (sigue abierta): región de torso superior cuando hay hombros y no
  caderas. Mientras tanto SubjectKit estima las caderas como entrada de `ce_mask_clothing_regions`
  (regla documentada en `SubjectExtractor.regionPose`, reproducible con `ce regions` y el
  `pose.txt` de las capas); la web debe aplicar la misma regla.
- Regiones de prenda medidas en `harness/people` (`make subject-test`, `make visionmask-people`,
  2026-09-16): 7 de las 8 fotos tienen mapa (05 no: Vision no da pose a la persona central y la
  cadena cae a `cutHead`), el mapa cubre exactamente la máscara en las 7 y la máscara no cambia al
  calcularlo. Con la paleta por prenda del motor: swatches 3,86 → 2,29 de media y un solo color
  abajo en 01, 03 y 04; 06 saca dos (límite del motor documentado en ADR-011: el mismo vaquero al
  sol y a la sombra, L* 12,6–62, supera `CE_GARMENT_SHADE_MIN_RATIO` 0,2). El ΔE00 a la prenda
  anotada sube de 2,8 a 5,0 (mediana) porque las anotaciones son parches en tonos medios y el motor
  devuelve el TONO ILUMINADO, que es el que el usuario dice ver (CONTEXT §13); en el sintético del
  tranvía (camiseta #2b2c2c + pantalón #ddc0c8 con sombreado lambertiano y pliegues) el camino
  clásico da 2 rosas distintos (ΔE00 mínimo 3,21 al color real) y el de prendas 1 solo a 0,92.
- Para la app: `MaskFallback` gana los casos `.rejectedPhantom` y `.garmentRegions` (aditivos; los
  `switch` exhaustivos como `MaskStepsText.stepTitle` deben añadirlos, p. ej. «Regiones de prenda»)
  y `SubjectMaskResult` gana `rejectedPhantoms` y `garmentRegions`;
  `PersonEvidence.Kind` gana `.humanRectangle` (aditivo) y `PeopleDetection.humanRectangles`;
  `skinExcludedPixels` incluye crecimiento y halo (`skinGrownPixels`, `skinHaloPixels`);
  `headCut` ya no implica el 18 % fijo (ver `regionDecision.headCutFraction`),
  `wholePerson` con pose es la silueta (`fallbackSource`) y `poseRegions` seguido de `headCut`
  significa una pose que no describe a la persona. La app integra `SubjectKit` como paquete
  local (compila para iOS genérico sin firma) y debe pasar a Vision la imagen orientada con el
  mismo contenido que el raster.
- Coste en un Mac Apple Silicon (visionmask release, 1024 px): detección de Vision 0,47–0,74 s
  por foto (instancias, pose y caras; la primera carga los modelos) y cadena sin Vision
  1–13 ms por variante (la variante por defecto 3–12,5 ms). Medir en el iPhone antes del
  escaneo del carrete.

## ADR-011 — Paleta por prenda: un color por prenda lisa con su tono iluminado

**Contexto.** Requisito del usuario con la foto real del tranvía (CONTEXT §13): «me dice que hay
distintos colores de rosa por el pantalón de la mujer pero el pantalón es de un solo color. Solo
debería mostrar un color por ese pantalón». La paleta clásica (`ce_palette_extract`) salía #222524
39 % (camiseta) + #b49aa2 23 %, #917a7e 16 %, #d5b8c0 13 %, #6b5a57 8 %: los cuatro últimos son el
mismo pantalón con luz, sombra y pliegues. El usuario lo percibe como #ddc0c8 (el tono iluminado)
y #2b2c2c. La fusión de sombras global (`merge_light_de`, experimento de ADR-009) no distingue
prendas: fusiona tonos de prendas distintas y no sabe cuál es el tono con luz.

**Decisión.** La paleta se calcula **por región de prenda** en el motor C (`ce_garment.c`), para
que la web futura sea igual:
- **Regiones** (`ce_mask_garment_regions`, misma geometría que `ce_mask_clothing_regions`):
  1 = arriba (torso y brazos superiores), 2 = abajo (caderas a tobillos: cápsulas de pierna fuera
  del torso o torso/pierna más allá de la perpendicular al eje hombros → caderas por las caderas).
  SubjectKit entrega el mapa de la persona elegida (`SubjectMaskResult.garmentRegions`); sin pose,
  nil. **Sin pose la app sigue con el camino clásico**: con una sola región y 2 colores por
  región, los sintéticos de Wada de 3-4 colores pierden recall (columna informativa `garments` de
  L3), y sin geometría no hay prendas que separar.
- **Agrupación de tonos**: enlace simple por distancia de los clusters de Lloyd de la región con
  ΔE00 (kL = `shade_kL`) < `shade_merge_de` (o las fusiones de `ce_palette_opts`): tolera L*
  (sombra) y no croma ni tono, con dos límites físicos. (1) **Luminancia**: no se unen tonos cuya
  luminancia mínima (Y + 0,01) sea < 0,2 veces la máxima (`CE_GARMENT_SHADE_MIN_RATIO`: ninguna
  sombra oscurece 5 veces la luz lineal; el pantalón del tranvía llega a 0,23). (2) **Mezclas**: un
  tono que está en XYZ lineal sobre el segmento entre otros dos que no pueden ser el mismo color, y
  que no es una sombra de ninguno, es el borde desenfocado de un estampado: se reparte entre los
  extremos (`CE_GARMENT_MIXTURE_DE` 3). Sin ellos, en `harness/people/02` (vestido azul marino con
  estampado blanco) los tonos de mezcla encadenaban los dos colores por transitividad y la prenda
  salía como un gris (#838f9a); con ellos, prenda entera azul marino (#0b0d17) + estampado (#b0c2cd).
  (3) **Sombra pura** (corrección 2026-09-16, ver más abajo): dos tonos también se unen, **sin el
  límite de luminancia**, si uno es el otro escalado en XYZ lineal (`c ≈ s·a`, s de mínimos cuadrados
  en [`CE_GARMENT_SHADE_S_MIN` 0,02, 50], ΔE00 al modelo < `CE_GARMENT_SHADE_LIT_DE` 3), que es lo que
  hace la luz: la misma reflectancia con menos fotones.
- **Color de la prenda = tono iluminado**: media en Lab de los píxeles del grupo entre los
  percentiles 75 y 95 de L* (60 y 90 hasta la corrección de 2026-09-16), sin sombras ni brillos especulares (no la media, que oscurecen las
  sombras), con los clusters que pesan >= 0,35 veces el mayor del grupo (`CE_GARMENT_LIT_CORE_FRACTION`:
  los restos de mezcla, pocos y más claros, no aclaran el color oscuro de un estampado). Pantalón
  sintético de los tests: #dbbec6 a ΔE00 0,41 de #ddc0c8; la media de todos sus píxeles, #cdb3ba,
  a 3,7.
- **Segundo color** solo si pesa >= 25 % de su región y su tono iluminado no es agrupable con el
  primero (rayas, estampado, bloques); máximo 2 por región.
- **Prenda entera** (región 3: vestido, mono) si cada color de arriba es fusionable con alguno de
  abajo y viceversa. **Fusionable compara tonos iluminados sin tolerancia a L*** (ΔE00 kL = 1 <
  `shade_merge_de`): los tonos iluminados ya no tienen sombras y la tolerancia de la agrupación
  fusionaba prendas distintas de tono cercano (camiseta azul marino #1f2a44 y vaquero #3d5b7d,
  ΔE00 16,8, ΔE00 kL 4 = 7,7). Medido: con la tolerancia de la agrupación (kL 4, umbral 7) 24 de
  25 pares de tono cercano fusionados; con la regla estricta, 0 de 25 en toda la meseta elegida.
- **Peso** = cuota de la región en la máscara × cuota del color en la región. El match
  (`ce_match`) no cambia: `ce_analyze_garments` le pasa los swatches de prenda.
- **Valores por defecto** (barrido `make garments-sweep`, `engine/BENCHLOG.md`): `shade_kL` 3,
  `shade_merge_de` 6,5, percentiles 0,75-0,95, `secondary_min_share` 0,25,
  `max_colors_per_region` 2. kL 3 × 6,5 es el mayor umbral con kL 3 que no funde ningún par de
  colores distintos de L2 (el primero aparece con 7) y conserva la meseta de 114/115 composiciones
  sombreadas con los colores exactos (0 fusiones erróneas, rayas intactas, vestidos fusionados);
  por debajo de 5 las sombras duras se parten. Encadena los tonos reales del pantalón del tranvía
  (ΔE00 kL 3 entre vecinos: 2,94, 4,14 y 6,16): la paleta real en bandas planas
  (`test_real_pants_palette_bands`) sale con un solo color abajo, y el pantalón sintético de
  `test_garment` con 2 swatches y top-1 Nº 027 (Corinthian Pink + Slate Color, la pareja rosa +
  gris oscuro más cercana). La foto real no está en el Mac: falta verlo con ella.

**Consecuencias.**
- Un color por prenda lisa y dos en prendas bicolores; las capas «Prendas» (mapa de regiones,
  swatch de prenda por píxel, tonos agrupados en cada prenda) están en `ce --debug-dir`, en
  `make layers-report` y en `garmentDebugLayers` para el inspector de la app.
- El contexto baja de 2 047 936 a 1 994 576 B (centro de Lloyd por bin en un `int8_t` aparte, mismas
  operaciones de coma flotante: goldens, paridad y hashes sin cambio) aunque gana 2 capas por píxel,
  el histograma de L* y la matriz de distancias entre clusters.
- Riesgos: calibrado con sintéticos (115 composiciones de L2 «prendas» desde la corrección de 2026-09-16, 200 composiciones de L2,
  3 imágenes de test) y solo 7 fotos reales con pose (`harness/people`), cuyas anotaciones son
  parches medidos a mano y no el tono iluminado; la prenda en sombra entera (una región a la luz y
  la otra no) puede no fusionarse como prenda entera; una sombra dura que ocupa ~50 % de la prenda
  **con giro de tono** (la luz rebotada tiñe la sombra) sale como segundo color (1 caso de 15 en
  «sombras duras»: el modelo de sombra pura no lo cubre); estampados pequeños
  con < 25 % desaparecen; un gris sobre blanco pasa por su sombra **siempre** desde la corrección
  de 2026-09-16 (era «puede pasar» entre 0,2 y 0,5 del blanco): es la contrapartida deliberada del
  requisito; los límites de luminancia, núcleo y mezclas son constantes del motor
  (`ce.h`), no opciones: se calibraron con compilaciones del scratchpad. Medir en la capa 4 con el set dorado antes de fijar los valores; umbrales
  del bloque propuestos en `harness/out/thresholds.proposed.json` (`L2_garments`), no promovidos.
- El generador de composiciones sombreadas vive en `oracle/oracle/garments.py` (no protegido): se
  propone moverlo a `oracle/synth/` al promover los umbrales.

**Corrección 2026-09-16 (sombra proyectada: un solo color también con media prenda al sol).** La
verificación midió el hueco mayor de la primera versión: una **sombra proyectada contigua** sobre
una prenda lisa (sol contra sombra abierta, 1,5-4 pasos de luz) saca un **segundo color falso**,
que es literalmente la queja del usuario. Con el generador independiente del verificador (cilindros
con luz lateral a 40°, degradado vertical, pliegues y ruido) fallaban **14 de 24** configuraciones
de (luz × profundidad), y también 2 de 5 semillas de un beige liso con sombra propia dura. El
bloque «prendas» de L2 no lo veía porque sus sombras duras son 3-5 bandas verticales estrechas con
ambiente 0,75, no una sombra contigua de media prenda.

- **Causa.** La agrupación por ΔE00(kL = `shade_kL`) divide la diferencia de L* por 3, pero una
  sombra de 2 pasos deja ΔL* > 20 (ΔE00 kL 3 > 6,5) y, además, el límite de luminancia
  (`CE_GARMENT_SHADE_MIN_RATIO` 0,2) prohíbe expresamente unir tonos tan separados. Subir `shade_kL`
  o bajar el límite no vale: funde prendas de verdad bicolores (medido por el equipo de SubjectKit:
  con el límite a 0,07 el bloque cae de 99/100 a 98/100 y se funde una camisa de rayas).
- **Regla nueva (`ce_garment_same_material`).** Dos tonos son el **mismo tejido con distinta luz**
  si uno es el otro **escalado en XYZ lineal**: `c ≈ s·a` con s de mínimos cuadrados en
  [0,02, 50] y ΔE00(c, s·a) < 3 (el límite pasa a 0,04 y se añade el modelo de sombra cromática en
  la corrección de la segunda vuelta, más abajo). Es el modelo físico de una sombra y no tiene límite de
  luminancia (una sombra de 4 pasos tiene s ≈ 0,06). Se aplica en dos sitios: al **agrupar
  clusters** (par marcado `CE_GARMENT_PAIR_SHADE`, que salta el límite de luminancia) y al
  **seleccionar colores** (un grupo que es el color ya elegido con menos luz se suma a él). El
  reparto queda: la agrupación por ΔE00(kL) con límite de luminancia sigue igual para los tonos
  cercanos, y la sombra pura es la excepción que el modelo físico justifica.
- **Separación medida** (ΔE00 del tono iluminado del segundo grupo al modelo escalado del primero,
  sobre las escenas del verificador): sombras 0,42-1,34; prendas de verdad bicolores 10,5-28,1
  (rayas marino/blanco 13,8; rojo + rosa palo 17,7; azul + celeste 10,5; degradado de color 12,4).
  Casi un orden de magnitud de margen con el umbral en 3.
- **Contrapartida deliberada.** Cualquier par que comparta cromaticidad cumple el modelo con s
  exacto —no solo dos neutros: escalar en XYZ conserva xy, así que también un tinte y su propia
  sombra (ver la corrección de la segunda vuelta, más abajo)—: una prenda a rayas blanco + gris
  sale con un solo color. Antes se perdía
  por debajo de ΔE00 real 16-20 y ahora se pierde siempre. Es ambigüedad real: sin razonamiento
  espacial o semántico no hay señal local que las separe (se probaron y descartaron tres: número de
  alternancias A|B por barrido, salto de color en la frontera y valle del histograma de L*; las tres
  confunden los pliegues de un cilindro con unas rayas, tabla en `engine/BENCHLOG.md`). El requisito
  del usuario es explícito y manda: un color por prenda lisa.
- **Percentiles del tono iluminado 0,60-0,90 → 0,75-0,95.** Al agrupar la sombra con la luz, la
  banda de percentiles de la unión baja y el tono se oscurecía (pantalón rosa con luz dura: ΔE00
  5,5 → 8,0). Recalibrados con la métrica válida (composiciones sintéticas cuyo color base se
  conoce, **no** las anotaciones de `harness/people`, que son parches en tonos medios): ΔE00 al tono
  iluminado verdadero p50 0,49 → 0,31 y p90 3,27 → 1,51; el pantalón de `test_garment` pasa de
  ΔE00 1,4 a 0,41 de #ddc0c8. Se deja `lit_high` en 0,95 (y no 0,98, que da p90 0,98) para conservar
  margen contra los brillos especulares. Coste: la mediana de `harness/people` sube de 4,56 a 5,82
  (métrica declarada inválida para esto) y las fusiones de colores distintos de L2 pasan de 1/400 a
  2/400. Efecto secundario bueno: el par «marino + marino claro» (ΔE00 real 5,69) dejó de fusionarse
  en región 3 con luz media y dura, que era otro hallazgo de la verificación.
- **Reserva sin regiones con peso.** Con máscara válida y mapa de regiones desalineado (o vacío) el
  swatch de reserva era el color medio de TODA la imagen reducida, fondo incluido: justo el fallo de
  CONTEXT §12. Ahora es la media ponderada de los píxeles de la **máscara** de la imagen original
  (enteros, mismos bits en nativo y WASM) y solo sin máscara se usa la media de la reducida.
- **`region_share` documentado como lo que es**: la cuota de la región sobre el **área cubierta por
  el mapa** (las cuotas suman 1), que coincide con su cuota en la máscara solo cuando el mapa cubre
  la máscara entera, como hace SubjectKit (invariante verificada en las 7 fotos con pose).
- **Lo que mide el gate**: familia `sombra_proyectada` del bloque «prendas» de L2 (15 de 115
  composiciones: sombra contigua de 2-4,5 pasos sobre el 40-60 % de una pieza, borde recto con
  penumbra de 0-3 px) con umbral «0 prendas lisas partidas en dos», y el test Unity
  `test_cast_shadow` (1, 2, 3 y 4 pasos sobre media pierna, con la camisa de rayas bajo la misma
  sombra como control). Sin la regla: 6 de 15 en el bloque y el test Unity falla a 2 pasos.

**Corrección 2026-09-16 (segunda vuelta: enlace completo, sombra cromática de exterior y
degradados).** La verificación de la corrección anterior encontró dos MAYORES y cuatro menores. Los
dos mayores venían de la misma raíz: la regla nueva se aplicaba a una agrupación por **enlace simple
transitivo**, y su promesa en la cabecera no era la que cumplía el código.

- **Encadenado (MAYOR).** `ce_garment_same_material` no tiene límite de luminancia, así que con
  enlace simple una cadena de tonos intermedios unía el fondo oscuro de un estampado con su motivo
  claro. Reproducido en la MISMA foto real que había motivado el límite de luminancia
  (`harness/people/02`, vestido azul marino con estampado blanco): el estampado, el 38 % de la
  región de arriba, DESAPARECÍA y el vestido dejaba de fusionar a «prenda entera», así que la app
  mostraba «Parte de arriba #0f0f19» y «Parte de abajo #0f1221» (el mismo marino, ΔE00 3,4) en dos
  tarjetas. **Arreglo: enlace COMPLETO.** Dos grupos se unen solo si TODOS sus pares cruzados son
  compatibles; un grupo es una camarilla y nada se encadena. Además (a) el límite de luminancia pasa
  a ser condición del par «agrupable» —sin eso, la fusión por luz de `ce_palette_opts`
  (`merge_light_de`, que ignora L*) metía en la camarilla pares que el límite prohibía— y (b) en la
  selección, un grupo se suma a un color solo si es compatible con su tono ACTUAL **y** con su
  ANCLA (el tono del primer grupo, que no se mueve), así el tono no deriva de uno en uno.
  Resultado en la foto real: `whole #0e0f1b 66 % + #b7cad4 34 %`, que es la respuesta correcta y la
  que daba el motor antes de la regresión. Gate nuevo: familia `estampado_sombra` del bloque y el
  test Unity `test_print_dress_shadow`.
- **Promesa de la cabecera (MAYOR).** `ce.h` decía que el límite era «dos NEUTROS (un gris medio
  sobre blanco)». No es cierto: escalar en XYZ conserva la cromaticidad, así que la regla une
  **cualquier par que comparta cromaticidad**, por saturado que sea (un tinte y su propia sombra:
  beige + marrón, rosa palo + malva, crema + tierra). Ahora `ce.h`, este ADR y `engine/README.md`
  lo dicen con esas palabras, y el daño está **acotado** por tres cosas: `CE_GARMENT_SHADE_S_MIN`
  sube de 0,02 a **0,04** (ninguna sombra oscurece más de ~4,6 pasos; el marino y su estampado
  blanco de 02 están a s = 0,012 y ya no se unen), el enlace completo y el **veto de mezcla** (dos
  colores unidos por un tono de mezcla —hay píxeles que son la combinación de los dos, es decir un
  borde de estampado o de rayas— nunca son el mismo material, por bien que ajusten al modelo; «la
  penumbra de una sombra no es una mezcla» — **esa frase era FALSA para una sombra CROMÁTICA y fue
  el hallazgo mayor de la tercera vuelta: ver más abajo**). Lo que se pierde está **medido**: familia
  informativa `bicolor_tonal` del bloque (un tinte y su propia sombra a ΔE00 real 10/20/30/45), 0 de
  10 conservadas, dentro y fuera del diccionario de Wada.
- **Sombra cromática de exterior (menor del verificador, requisito literal del usuario).** La sombra
  de sol contra cielo azul **no es una escala de la luz: se azulea**, y el vaquero liso de
  `harness/people/06` —la única foto real del fallo que hay en el repo— seguía saliendo con dos
  colores. Se modela como **mezcla de dos iluminantes**: `c ≈ s·(a + w·S·a)`, con `S = M⁻¹·diag(g−1)·M`
  (M = CAT de Bradford, g = blanco de cielo CIE D 12000 K sobre blanco de escena 5500 K, normalizado
  al canal M) y (s, w·s) por mínimos cuadrados. Son dos incógnitas y tres ecuaciones, así que el
  residuo sigue discriminando, y la intensidad `w` —estimada del propio par, no fijada— está acotada
  por la física: `0 ≤ w ≤ min(CE_GARMENT_SKY_W_MAX 1,15, CE_GARMENT_SKY_W_SLOPE 0,54·(1−s)/s)`, es
  decir el azuleo no puede superar el de la sombra abierta (w = 1 con el margen del modelo) ni crecer
  si la luminancia apenas cae (con una fracción de cielo ≤ 0,35, w = f/(1−f)·(1−s)/s). Resultado:
  06 pasa de `low #729ac6 + #223d62` (dos colores) a `low #6b94c1` (uno), y su chaqueta —que la
  anotación describe como «azul claro CON ESTAMPADO BLANCO»— sigue con dos colores gracias al veto
  de mezcla. Gate nuevo: familia `sombra_cielo` (2-3,3 pasos, que es la profundidad física de una
  sombra abierta con fracción de cielo 0,10-0,25) y el test Unity `test_sky_shadow`, cuyas ganancias
  se derivan **fuera** del motor y en otro espacio (diagonal en sRGB lineal, no en conos): 13/15 → 15/15.
- **Degradados de color (menor).** Un tie-dye ya no colapsa: el enlace completo quita el modo de
  colapso por encadenado y, cuando la cuota del extremo no llega a `secondary_min_share`, se conserva
  igual si es el **extremo de un degradado** — hay tonos de mezcla entre los dos (variación de tono
  CONTINUA), pesan ≥ 25 % del grupo candidato y los dos tonos se separan en croma y tono (≥ 12).
  Medido: tie-dye 0,41-0,48 de masa de mezcla y 36-46 de ΔE00 de tono; el borde de la persona de al
  lado en `harness/people/03`, 0,16 y 8,7 (no dispara). Gate nuevo: familia `degradado_color` y el
  test Unity `test_tie_dye` (con `secondary_min_share` 0,35, donde la regla es lo único que conserva
  el extremo, y con la prenda lisa con sombra como control).
- **Documentación coherente (menores).** `ce.h` tenía los percentiles viejos (0,60-0,90) mientras
  `ce_garment_opts_default` pone 0,75-0,95: corregido y **verificado por test**
  (`cli_garment_check.js` compara los valores del JSON con los que documenta `ce.h`). Y la promesa
  «dos prendas distintas de tono cercano con ΔE00 ≥ `shade_merge_de` nunca se fusionan» era absoluta
  siendo sobre tonos iluminados ESTIMADOS: ahora dice que hay una banda de ~1 alrededor del umbral,
  con la curva medida (familia informativa `banda_fusion`: fusionan 4,8 · 5,2 · 5,8 · 6,2 · 6,3 y no
  fusionan 6,6 · 7,0 · 7,2 · 7,9 · 8,0).
- **Bloque «prendas» de L2: 115 → 170 composiciones** (las 115 anteriores conservan índice, semilla y
  bytes; las familias nuevas van al final). Gates nuevos: `sky_shadow_split_max` 0,
  `gradient_collapsed_max` 0 y `print_shadow_lost_max` 1 (medido 1/10 con el motor nuevo y 2/10 con
  el anterior: el caso que falla es un fondo L* 14 con motivo fino cuyo motivo en sombra se fragmenta
  por debajo de `secondary_min_share`, no un encadenado). Las familias informativas `bicolor_tonal` y
  `banda_fusion` quedan FUERA de `colors_ok_rate` y de `lit_de00_p90` —miden límites conocidos— y sus
  cifras se publican aparte; el ΔE00 al tono iluminado verdadero se sigue midiendo sobre las seis
  familias con las que se calibró el umbral, porque una prenda con media pieza en sombra profunda
  sesga el tono a propósito (p90 de las familias nuevas: 32,3 → 16,6). Propuesta completa en
  `harness/out/thresholds.proposed.json`.

**Corrección 2026-09-16 (tercera vuelta: la penumbra de una sombra cromática NO es una mezcla).** La
verificación final volvió a medir el caso (b) del usuario con un generador independiente (siluetas
propias, lambertiano de cilindro, pliegues fbm, ruido de disparo, exposición global y sombra derivada
de iluminantes CIE D 5500 K → D 12000 K por Bradford) y encontró que **el pantalón liso con sombra
azul de exterior seguía saliendo con DOS colores en 32 de 32 escenas**, con un segundo color
azul-violeta falso a ΔE00 24-40 del pantalón real, pese a que el modelo de cielo de la segunda vuelta
**acepta el par** (residuos 0,03-0,42, muy por debajo de la tolerancia 3).

- **Causa raíz (localizada por el verificador con una ablación causal).** No falla el modelo: falla
  el **veto de mezcla**. Una oclusión PARCIAL de la luz es una **combinación lineal de los dos
  iluminantes**, así que los tonos de la penumbra caen exactamente sobre el segmento entre el tono al
  sol y el tono en sombra; el paso 3 los tomaba por una MEZCLA de dos colores distintos, marcaba el
  par (luz, sombra) como «unidos por un tono de mezcla» y ese veto bloqueaba `CE_GARMENT_PAIR_SHADE`,
  que es el ÚNICO camino por el que el modelo de cielo puede agrupar. Con sombra NEUTRA no pasaba
  porque los tonos intermedios sí son escalas puras y quedaban excluidos del test por
  `ce_garment_is_shade_of`. La familia `sombra_cielo` del bloque no lo veía porque su penumbra era de
  0-3 px y no llegaba a formar un cluster propio: **el gate era ciego al fallo**.
- **Arreglo 1 (la penumbra no es una mezcla, ahora de verdad).** Un par que es el **mismo material
  con distinta luz bajo CUALQUIERA de los dos modelos** no puede ser los dos extremos de una mezcla:
  lo que hay entre ellos es penumbra, la misma tela con luz intermedia. Antes solo se excluían los
  extremos de los que el tono intermedio era una escala pura (`ce_garment_is_shade_of`).
- **Arreglo 2 (estrella de sombra).** Con el arreglo 1 solo, el enlace COMPLETO seguía bloqueando la
  unión: el modelo de cielo se define **desde la luz** y dos penumbras intermedias de la misma rampa
  no siempre se ajustan entre ELLAS (la cota del azuleo `0,54·(1−s)/s` supone que la referencia es el
  tono al sol; medido, un par penumbra-sombra daba w = 0,679 con wmax 0,621). Se añade un segundo
  control de cadena, alternativo al enlace completo: **ESTRELLA** — todos los miembros de la unión son
  el mismo material que el **más luminoso** de la unión. Tampoco encadena por transitividad (el fondo
  marino de un estampado no es una sombra de su motivo blanco, s = 0,012), y es la forma física del
  problema: una prenda bajo una sola luz tiene UN tono al sol y el resto son ese tono con menos luz.
- **Arreglo 3 (extremos de una mezcla con peso propio).** Los dos extremos de un borde son áreas de
  verdad de la prenda: ahora tienen que pesar ≥ `min_weight` de la región. Un cluster de 47 px de
  ruido hacía de extremo y convertía la sombra entera (794 px) en «mezcla», y su peso en un color
  falso por la regla del degradado.
- **Arreglo 4 (tono iluminado con media prenda en sombra, menor del verificador).** El tono que
  devuelve la paleta se alejaba del color real según se hacía más profunda la sombra NEUTRA (ΔE00
  5,2-6,3 con 3 pasos, por encima del «< 5» de la checklist), porque los percentiles
  `lit_low_pct`-`lit_high_pct` se calculaban sobre el grupo ENTERO, sombra incluida. El núcleo del
  tono iluminado pasa a tener **dos filtros**: peso (como antes) y **nivel de luz**
  (`CE_GARMENT_LIT_Y_RATIO` 0,5: a menos de un paso de luz del más luminoso del núcleo). Medido en el
  barrido del verificador: sombra neutra 10/16 → **16/16** con ΔE00 < 5; sombra azul 0/32 → **32/32**.
  El valor 0,5 está en el centro de la meseta (0,4-0,7 dan las mismas 48/48 escenas; por debajo de 0,4
  vuelve el sesgo y por encima de 0,7 el tono lo decide un solo cluster).
- **Límite medido y documentado.** El filtro de peso va ANTES que el de nivel, así que cuando la
  sombra cubre **más del ~70 %** de la prenda el nivel iluminado ya no pesa lo suficiente y el color
  devuelto es el **tono EN SOMBRA** (sigue siendo UN color —el requisito del usuario—, pero el hex es
  el de la sombra). Fijado por el test `SKY_SHADOW_80` de `engine/tests/test_garment.c`, que falla si
  el límite se mueve en cualquier dirección.
- **El gate deja de ser ciego.** La familia `sombra_cielo` pasa a tener penumbra de **6-18 px** (sobre
  piezas de ~140 px) y sombra sobre el **55-70 %** de la prenda, y en un tercio de los casos la
  transición es **continua de arriba abajo** (lambertiano entre luz y sombra, sin borde). Con esa
  familia, el motor ANTERIOR da `sky_shadow_split` **4/15** y el bloque falla (143/150); con el motor
  nuevo, **0/15** y 148/150. La familia `estampado_sombra` también lleva penumbra (8-16 px).
- **Coste medido y dónde se mide.** El modelo (2) hace ambiguos los pares «neutro claro + neutro
  oscuro azulado» (un gris #c6c6c6 y su versión bajo cielo abierto es exactamente #414652: residuo
  0,41). Las familias de gate (`rayas`, `estampado_sombra`) rechazan a propósito los pares con
  `same_material_residual < 5` —si no, medirían el límite conocido en vez de lo que dicen medir— y la
  familia informativa `bicolor_tonal` se amplía: la mitad de sus pares son ahora ambiguos por el
  modelo (2) (el mismo tinte bajo el cielo, 1,5-3 pasos). Conservados: **1 de 10** (antes 4 de 10).
- **Fotos reales (`harness/people`, `make l4-people-smoke` con Vision real, variante oficial).** Las
  9 fotos siguen dando 9/9 con máscara y los mismos pasos; el ΔE00 mediano de cada prenda anotada a
  su región baja de **5,2 a 4,5**. El único cambio estructural está en `06_group_courier_street`
  (la foto del vaquero al sol y a la sombra): la parte de ARRIBA pasa de dos colores
  (#e2e9f0 a ΔE00 9,7 de la anotación y #586a90 a 30,7) a **uno** (#dde4ed, ΔE00 **8,4**), que es lo
  que dice la anotación («chaqueta con capucha azul claro CON ESTAMPADO BLANCO», UN color #b9c8dd):
  el blanco y el azul claro de esa chaqueta son justo el par ambiguo que el modelo (2) une. Las
  piernas siguen con un solo color y su tono iluminado sube de #6b94c1 a #739dc9 (ΔE00 a la anotación
  14,0 → 16,8: la anotación es un parche medido a mano en un tono medio, no el tono al sol, y esa
  métrica está declarada inválida para calibrar el tono iluminado desde la primera vuelta).
- **Resumen antes → después** (mismo generador independiente del verificador, 48 escenas):
  sombra azul de exterior 0/32 → **32/32** con UN color a ΔE00 < 5; sombra neutra proyectada 10/16 →
  **16/16**; bloque «prendas» de L2 (170 composiciones, familia reforzada) 143/150 → **148/150**, con
  los 8 checks en verde (antes 7 fallaban por la sombra azul). `GARMENT_HASH` `15db5b325e98c7ac` →
  `2f33620fa4322acb`, idéntico en nativo, ASan y WASM; el resto de hashes (LIGHT_MERGE, MASK, SPLIT,
  DEBUG_LAYERS, RESULT_HASH_COMBO42) y los goldens, sin tocar.
