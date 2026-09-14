# colorsApp — reglas para agentes

App iOS nativa que reconoce en una foto la combinación de colores de Sanzo Wada
más parecida. Plan completo: `docs/` (DECISIONS.md, RELEASE.md). Idioma: docs y
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
| `make eval` / `eval-fast` | Scorecard completo de las capas L1–L4 / L1+L2+10 % de L3 (fase 1+) |
| `make ios-generate` | `xcodegen generate` en `ios/` (crea `ios/Signing.xcconfig` desde la plantilla si falta) |
| `make ios-build-sim` / `ios-build-device-nosign` | Build sin firma para simulador / dispositivo genérico |
| `make ios-test-sim` / `ios-run-sim` | XCTest en el primer iPhone simulado / boot+install+launch y captura `harness/out/stub.png` |
| `make ios-install DEVICE=<udid>` | Build firmada + `devicectl install` + launch en un iPhone (exige identidad Apple Development) |

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
