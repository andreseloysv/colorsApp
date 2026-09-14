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
