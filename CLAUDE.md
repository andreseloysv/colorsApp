# colorsApp — reglas para agentes

App iOS nativa que reconoce en una foto la combinación de colores de Sanzo Wada
más parecida. Plan completo: `docs/` (DECISIONS.md, RELEASE.md, SETUP.md). Idioma: docs y
comentarios en español; identificadores, ficheros y símbolos en inglés.

## Decisiones fijas (no se debaten; ver docs/DECISIONS.md)

- iOS nativo en SwiftUI (deployment target iOS 17). Sin Android/web en el MVP.
- **Un motor, dos targets**: el motor de color es C11 puro (`engine/Sources/CColorEngine`),
  sin I/O, sin `malloc`, sin dependencias fuera de `<math.h>`, y compila desde la
  misma fuente a nativo (SwiftPM para iOS, CMake para la CLI `ce` y los tests) y a
  WASM (Emscripten). Nada de lógica de color en Swift ni en JS.
- Sin red en la app: `grep -rE "URLSession|NWConnection|CFNetwork" ios/` debe dar 0.
- Determinismo numérico: `#pragma STDC FP_CONTRACT OFF` en **cada** `.c`, todo en
  `double`, nunca `-ffast-math`/`-Ofast`/`-ffp-contract=fast`, nunca `unsafeFlags`
  en `Package.swift`. CMake ya pasa `-ffp-contract=off -Wall -Wextra -Werror -Wpedantic`.
- Espacio de color: CIELAB D65 con matriz derivada de los primarios sRGB; ΔE2000
  (Sharma/Wu/Dalal 2005). El diccionario embebe solo sRGB8; el Lab lo calcula el motor.
- Sin RNG en el motor; un `ce_ctx` por tarea, sin estáticos mutables.
- Distribución: Personal Team (Apple ID gratuito), perfiles de 7 días, reinstalación
  semanal por Wi-Fi (`docs/RELEASE.md`). Prohibido todo lo que exija cuenta de pago:
  push, iCloud, Sign in with Apple, Associated Domains, extensiones, TestFlight.

## Comandos (Makefile raíz + `mk/*.mk`; ejecutar desde la raíz)

| Comando | Qué hace |
|---|---|
| `make test` / `test-asan` / `test-wasm` | Motor C: CMake + ctest nativo / con ASan+UBSan / con Emscripten y node |
| `make swift-test` | `swift test` del paquete `engine/` |
| `make diff-oracle` | 100k colores por `ce convert` contra el oráculo Python (1e-9) |
| `make dict` / `dict-check` | Regenera / verifica `data/wada/dictionary.json`, `errata.json`, `ce_dict_data.h` |
| `make doctor` | Tabla del toolchain (Xcode, clang, cmake, emcc, node, uv, xcodegen, venv, identidades, iPhones) |
| `make check-protected` | Falla si el árbol toca rutas protegidas o el manifiesto sha256 no cuadra |
| `make protected-hash` | Regenera `harness/PROTECTED.sha256` (exige `COLORSAPP_ALLOW_PROTECTED=1`) |
| `make hooks` | Instala `harness/hooks/pre-commit` en `.git/hooks` |
| `make bootstrap` | Reproduce el toolchain sin sudo: `brew install` de lo que falte (cmake, emscripten, uv, xcodegen), `uv sync`, `hooks`, `doctor` (`docs/SETUP.md`) |
| `make release-week DEVICES="<udid> <udid>"` | Ritual semanal (§3 del plan): `check-protected` + gate `RELEASE_GATE=test|eval-fast|eval` (hoy `test`) + `ios-lint` + `ios-install` por UDID; sin `DEVICES` solo comprueba |
| `make fuzz [FUZZ_SECONDS=600] [FUZZ_SEED=1]` | `fuzz_palette` (paleta + parser PNM) bajo ASan/UBSan en `build-asan/`; 0 fallos exigidos |
| `make bench-palette` / `bench-match` | `PERF_1024_RGBA_MS` de la extracción / `MATCH_MS`, `ANALYZE_1024_MS` y `RECALL_EXACT` del match, nativo -O2 (anotar en `engine/BENCHLOG.md`) |
| `make parity` / `parity-fixtures` | Fase 5: `ce match --json` nativo vs WASM (node) sobre `harness/wasm/fixtures/` (20 PPM): salida byte a byte idéntica, mismo top-3 y `ambiguous`; escribe `harness/out/parity.json` / regenera las fixtures y comprueba sus sha256 |
| `make l2` / `l2-fast` | Solo la capa 2 del harness (200 composiciones + invariancias / versión rápida) |
| `make l3` / `l3-fast` | Solo la capa 3 (348 × 10 sintéticos de `wada_gen` cacheados en `harness/out/synth` / 35 combinaciones): `ce batch` en columnas kL1 (oficial), kL2 y skin1, umbrales L3, holdout con `COLORSAPP_HOLDOUT_SEED`, golden-check |
| `make golden-check` / `golden-update GOLDEN_REASON="…"` | Compara `ce palette`/`match` con `harness/golden/` a 1e-9 y mismo top-3 / regenera los goldens (ruta protegida) anotando el motivo en `harness/CHANGELOG.md` |
| `make l4` | Runner mínimo de la capa 4 sobre `$COLORSAPP_GOLDEN_DIR` (`skipped` sin ella) |
| `make eval` / `eval-fast` | Scorecard completo de las capas L1–L4 / L1+L2+10 % de L3 (L1 y L2 desde la fase 2, L3 desde la 3; holdout y L4 `skipped` sin sus datos) |
| `make ios-generate` | `xcodegen generate` en `ios/` (crea `ios/Signing.xcconfig` desde la plantilla si falta) |
| `make ios-build-sim` / `ios-build-device-nosign` | Build sin firma para simulador / dispositivo genérico |
| `make ios-test-sim` / `ios-run-sim` | Todos los XCTest en el simulador `SIM_NAME` (boot si hace falta + `simctl privacy grant photos` + `xcodebuild test`, sin sysdiagnose) / boot+install+launch y captura `harness/out/stub.png` |
| `make ios-addmedia MEDIA_DIR=<dir>` | `xcrun simctl addmedia` de todos los PNG de `MEDIA_DIR` al carrete del simulador `SIM_NAME` (fixtures del escaneo día 0) |
| `make ios-install DEVICE=<udid>` | Build firmada + `devicectl install` + launch en un iPhone (exige identidad Apple Development) |
| `make ios-lint` | Falla si `ios/` (sin el `.xcodeproj` generado ni `build-ios/`) contiene `URLSession|NWConnection|CFNetwork` |

Variables de `mk/ios.mk`: `SIM_NAME` (simulador por nombre, defecto `iPhone 18 Pro`; `SIM_UDID`
se resuelve desde él o se pasa directo), `DERIVED` (DerivedData de xcodebuild, defecto
`build-ios`; **cada agente que compile en paralelo usa el suyo y su propio simulador**, p. ej.
`make ios-test-sim DERIVED=build-ios-hoy SIM_NAME="iPhone 17"`), `MEDIA_DIR` (ios-addmedia),
`DEVICE` (UDID físico), `IOS_CONFIG` (Debug). Fixtures de `EngineParityTests`: `uv run --project
oracle python oracle/tools/make_ios_fixtures.py` (solo lee `harness/golden/`; `--check` verifica).

Python siempre vía uv: `uv run --project oracle python ...` (el venv vive en `oracle/.venv`).
El Makefile raíz no se edita: cada área añade sus targets en `mk/<area>.mk` usando
`ROOT`, `ENGINE`, `ORACLE`, `UV`, `BUILD`.

## Rutas protegidas (anti-Goodhart)

Los globs están en `harness/PROTECTED.txt` (umbrales, goldens, datos de test,
`oracle/oracle/reference.py`, generadores sintéticos, herramientas de etiquetado,
nombres curados, overrides y fuente del diccionario). `make check-protected` compara
el árbol de trabajo (diff contra HEAD, staged y untracked) con esos globs y el sha256
de cada fichero con `harness/PROTECTED.sha256`; el hook pre-commit lo ejecuta.

- Un agente **nunca** modifica una ruta protegida por su cuenta. Si un cambio ahí es
  imprescindible, lo propone (p. ej. `harness/out/thresholds.proposed.json`,
  `data/wada/names.suggested.json`) y lo explica.
- `COLORSAPP_ALLOW_PROTECTED=1` es la llave del usuario/orquestador: permite el cambio,
  y después se regenera el manifiesto con `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash`.
- Los umbrales de `harness/thresholds.json` solo los promueve el usuario; los goldens
  cambian solo con motivo anotado en `harness/CHANGELOG.md`. Un golden nuevo sin subida
  de recall es una regresión, no una mejora.

## Seguridad en la máquina del usuario

- Nunca `sudo`, nunca cambiar ajustes del sistema (Gatekeeper, llavero, privacidad,
  `xcode-select -s`), nunca instalar nada que pida el Apple ID del usuario.
- Nunca pedir ni introducir el Apple ID o su contraseña fuera de Xcode.
- `security find-identity` y `xcrun devicectl list devices` son solo lectura; no crear
  certificados ni perfiles por línea de comandos.
- Las fotos personales nunca entran en el repo: viven en `$COLORSAPP_GOLDEN_DIR`.

## Solo el usuario puede

- Iniciar sesión con el Apple ID en Xcode > Settings > Apple Accounts y poner su Team
  ID en `ios/Signing.xcconfig` (gitignored; plantilla `ios/Signing.example.xcconfig`).
- Emparejar iPhones (cable, "Trust This Computer", Developer Mode, confiar el desarrollador).
- Aportar fotos reales y etiquetarlas; nombrar combinaciones en español o alemán
  (`data/wada/names.es.json`); aceptar erratas (`overrides.json`).
- Promover umbrales (`thresholds.json`) y elegir/guardar `COLORSAPP_HOLDOUT_SEED` y
  `COLORSAPP_GOLDEN_DIR` fuera del repo.

## Flujo de trabajo

- Antes de devolver trabajo: todo lo afirmado ejecutado y en verde, con la salida real.
- `git commit` solo cuando lo pida el orquestador o el usuario; nunca `--no-verify`.
- Trabajar solo dentro del repo; temporales en el scratchpad de la sesión, no en `/tmp`.
- Artefactos generados que no se versionan: `build*/`, `engine/.build/`, `ios/*.xcodeproj/`,
  `harness/out/`, `oracle/out/`.
