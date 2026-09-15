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
