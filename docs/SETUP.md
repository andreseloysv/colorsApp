# Reproducir el entorno de desarrollo (otra Mac o tras un reset)

Objetivo: dejar una Mac con Apple Silicon lista para `make test`, `make test-wasm`,
`make eval` y las builds de iOS en menos de una hora, sin tocar nada que exija `sudo`
salvo un único paso que ejecuta el usuario (seleccionar Xcode). Versiones verificadas
el 2026-09-15 en la Mac del proyecto (macOS 26.6.2, Darwin 25.6, Homebrew 7.0.1):

| Herramienta | Versión verificada | De dónde sale | Quién la comprueba |
|---|---|---|---|
| Xcode | 27.0 (27A266a) | App Store (**usuario**) | `make doctor` (`xcodebuild -version`) |
| Apple clang | 21.0.0 (clang-2100.3.34.2) | Viene con Xcode | `make doctor` (`cc --version`) |
| cmake | 4.4.3 | `brew install cmake` | `make doctor` / `make bootstrap` |
| Emscripten (`emcc`) | 6.0.9 | `brew install emscripten` | `make doctor` / `make bootstrap` |
| node (PATH) | v24.21.0 (nvm) | ver "node" más abajo | `make doctor` (solo que exista) |
| node (WASM tests) | v26.8.2 (`/opt/homebrew/opt/node`) | dependencia de la fórmula `emscripten` | `em-config NODE_JS` |
| uv | 0.12.13 | `brew install uv` | `make doctor` / `make bootstrap` |
| xcodegen | 2.46.0 | `brew install xcodegen` | `make doctor` / `make bootstrap` |
| Python del oráculo | 3.12.14 en `oracle/.venv` | `uv sync` (uv descarga el intérprete) | `make doctor` (`python-venv`) |

El camino corto es `make bootstrap` (sección 6). Las secciones 1–5 explican qué hace
cada paso y cuáles no puede dar un agente.

## 1. Xcode 27 (solo el usuario)

1. Instalar **Xcode 27** desde la App Store (pide el Apple ID: por eso lo hace el usuario,
   nunca un agente). Abrirlo una vez para que instale sus componentes.
2. Apuntar las herramientas de línea de comandos a Xcode. Recién instalado,
   `xcode-select -p` suele decir `/Library/Developer/CommandLineTools`, con lo que
   `xcodebuild`, `xcrun simctl` y `xcrun devicectl` no funcionan:

   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer   # usuario (pide contraseña)
   xcode-select -p   # debe imprimir /Applications/Xcode.app/Contents/Developer
   ```

   Alternativa **sin sudo** (válida para un agente o una shell concreta): exportar
   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. `xcode-select -p`,
   `xcodebuild` y `xcrun` la respetan; hay que ponerla en cada shell (o en el perfil).
3. Primer arranque y licencia:

   ```sh
   xcodebuild -checkFirstLaunchStatus || xcodebuild -runFirstLaunch   # puede pedir contraseña de administrador
   xcodebuild -license accept                                        # solo si xcodebuild se queja de la licencia
   xcodebuild -version                                               # Xcode 27.0 Build version 27A266a
   ```
4. Opcional, solo para `make ios-test-sim` / `make ios-run-sim`: el runtime de simulador
   de iOS (`xcodebuild -downloadPlatform iOS`, varios GB). Las builds `ios-build-sim`,
   `ios-build-device-nosign` e `ios-install` no lo necesitan. Comprobar con
   `xcrun simctl list devices available`.

## 2. Homebrew: cmake, emscripten, uv, xcodegen

```sh
brew install cmake emscripten uv xcodegen
```

Homebrew (en `/opt/homebrew`) no usa `sudo`. La fórmula `emscripten` arrastra `node`,
`binaryen` y su propio LLVM; es la instalación más larga. No hace falta `emsdk`: los
`make test-wasm` y `make parity` del proyecto usan el `emcmake`/`emcc` de brew.

## 3. Python del oráculo: `uv sync`

```sh
cd oracle && uv sync
```

`oracle/.python-version` fija **3.12** y `pyproject.toml` exige `>=3.12,<3.15`; el
Python 3.9.6 del sistema no sirve y no hay que tocarlo: si uv no encuentra un 3.12,
lo descarga él solo (a `~/.local/share/uv/python`) y crea `oracle/.venv` con numpy,
scipy, scikit-image, colour-science, Pillow, scikit-learn, opensimplex y pytest
(`uv.lock` fija las versiones exactas). Repetir `uv sync` es idempotente (~20 ms si
no hay nada que hacer). A partir de ahí, Python **siempre** vía uv:
`uv run --project oracle python ...` (o `cd oracle && uv run ...`); el Makefile lo
hace con `$(UV)`.

## 4. node: cuál usa cada cosa

Ningún `mk/*.mk` ni el `engine/CMakeLists.txt` nombran un binario de node: solo lo
mencionan en comentarios. La resolución real es esta:

- **`make test-wasm`** ejecuta `emcmake cmake -S engine -B build-wasm ...`. El
  toolchain de Emscripten fija `CMAKE_CROSSCOMPILING_EMULATOR` con el `NODE_JS` de su
  fichero de configuración, `$(brew --prefix emscripten)/libexec/.emscripten`
  (línea `NODE_JS='/opt/homebrew/opt/node/bin/node'`), y ctest lanza cada test `.js`
  con ese node. Se puede ver con `em-config NODE_JS` y con
  `grep CMAKE_CROSSCOMPILING_EMULATOR build-wasm/CMakeCache.txt`. Es el node de brew
  (26.8.2), que llega como dependencia de la fórmula `emscripten`, **independientemente
  del `node` del PATH**.
- **`make doctor`** solo comprueba que exista un `node` en el PATH y muestra su versión
  (hoy v24.21.0 vía nvm, que va antes que `/opt/homebrew/bin` en el PATH). No hace falta
  que coincida con el de Emscripten ni cambiar nvm; si algún día se cambia el node de
  Emscripten (`EM_CONFIG` o editando `.emscripten`), re-verificar `make test-wasm`.
- Requisito práctico: node ≥ 20. Con solo `brew install emscripten` ya se cumple.

## 5. Hooks y diagnóstico

```sh
make hooks     # copia harness/hooks/pre-commit a .git/hooks (ejecuta make check-protected antes de cada commit)
make doctor    # tabla del toolchain; exit 1 si falta una herramienta requerida
```

`make doctor` es el criterio de "entorno listo": debe salir 0. Las filas `identidades`,
`dispositivo` y `simuladores` son informativas (0 identidades solo significa que aún no
se ha iniciado sesión con el Apple ID en Xcode; ver `docs/RELEASE.md`).

## 6. `make bootstrap`: todo lo anterior salvo Xcode, en un comando

`make bootstrap` (en `mk/foundations.mk`) es idempotente y **no usa sudo**:

1. Comprueba que existe `brew` (si no, lo dice y sigue; solo falla si además falta alguna
   herramienta).
2. Para `cmake`, `emscripten` (comando `emcc`), `uv` y `xcodegen`: instala con brew
   **solo** las que falten; si están todas, no llama a brew.
3. Avisa (sin ejecutarlo) si `xcode-select -p` no apunta a `Xcode.app`, con el comando
   `sudo xcode-select -s ...` para el usuario y la alternativa `DEVELOPER_DIR`; avisa si
   `xcodebuild -checkFirstLaunchStatus` falla (entonces toca `xcodebuild -runFirstLaunch`).
4. `cd oracle && uv sync`.
5. `make hooks`.
6. Termina con `make doctor`, cuyo código de salida es el de `bootstrap`.

Con todo instalado tarda unos segundos. Lo que `bootstrap` no puede hacer: instalar
Xcode, cambiar `xcode-select`, iniciar sesión con el Apple ID, emparejar iPhones.

## 7. Verificación completa tras el bootstrap

```sh
make test                         # motor C nativo: cmake + ctest (test_math, test_dict)
make test-wasm                    # el mismo motor con Emscripten, tests con node
make dict-check                   # dictionary.json, errata.json y ce_dict_data.h al día
uv run --project oracle pytest -q # oráculo Python
make check-protected              # rutas protegidas intactas (exit 0 tras la promoción del usuario)
make ios-generate && make ios-build-device-nosign   # xcodegen + build iOS sin firma
make ios-lint                     # 0 referencias a red en ios/
```

Para instalar en los iPhones (Apple ID en Xcode, Team ID, Developer Mode, ritual
semanal `make release-week`): `docs/RELEASE.md`.
