# App iOS (fase 0): proyecto XcodeGen, builds sin firma, tests y ejecución en
# simulador, instalación en iPhone con Personal Team.
# Incluido automáticamente por el Makefile raíz (usa ROOT).
#
#   make ios-generate             xcodegen generate (crea ios/Signing.xcconfig si falta)
#   make ios-build-sim            build para simulador genérico, sin firma
#   make ios-build-device-nosign  build para dispositivo genérico, sin firma
#   make ios-test-sim             boot del simulador SIM_NAME si hace falta + `simctl privacy grant photos`
#                                 + ios-test-sim-media (fixtures del carrete) + xcodebuild test (todos los
#                                 XCTest, sin recogida de sysdiagnose)
#   make ios-test-sim-media       boot + grant photos + `simctl addmedia` de ios/ColorsAppTests/Fixtures/sim_media/*.png
#                                 una sola vez por simulador (sello en harness/out/sim-media/<udid>.stamp:
#                                 addmedia repetido duplica las fotos); SIM_RESET=1 borra el simulador
#                                 (`simctl erase`) y vuelve a añadirlas; SIM_MEDIA=0 lo omite
#   make ios-run-sim              boot + install + launch en simulador y captura harness/out/stub.png
#   make ios-addmedia MEDIA_DIR=<dir>  `xcrun simctl addmedia` de todos los PNG del directorio al
#                                 carrete del simulador (fixtures del escaneo día 0)
#   make ios-install DEVICE=<udid>  build firmada + devicectl install + launch (exige identidad)
#   make ios-lint                 sin red en la app: 0 referencias a URLSession|NWConnection|CFNetwork
#                                 en ios/ (sin el .xcodeproj generado ni build-ios/); exit 1 si hay alguna
#   make ios-layers-fixtures      regenera ios/ColorsAppTests/Fixtures/layers/ (escena sintética de la app +
#                                 máscara de su cadena, escritas por LayersInspectorTests en el simulador, y
#                                 `ce match --mask --debug-dir` con un `ce` propio en $(DERIVED)/engine)
#   make ios-screens-subject      build + install + `simctl launch -uiScreen ...` y capturas del recorte de
#                                 sujeto y del inspector de capas en SUBJECT_SCREENS_DIR
#
# Variables:
#   SIM_NAME   nombre del simulador (defecto "iPhone 18 Pro"); SIM_UDID se resuelve desde él
#              (o se pasa directamente: make ios-test-sim SIM_UDID=<udid>)
#   DERIVED    DerivedData de xcodebuild, relativo a la raíz o absoluto (defecto build-ios);
#              cada agente usa el suyo para no colisionar (make ios-test-sim DERIVED=build-ios-hoy)
#   DEVICE     UDID físico (`xcrun devicectl list devices`), IOS_CONFIG (Debug), MEDIA_DIR (ios-addmedia)
#   SIM_MEDIA_DIR  PNG del carrete de pruebas (defecto ios/ColorsAppTests/Fixtures/sim_media;
#              `uv run --project oracle python oracle/tools/make_sim_media.py` los regenera)
#   SIM_MEDIA  1 (defecto) añade las fixtures antes de los tests; 0 no toca el carrete
#   SIM_RESET  1 = `simctl erase` del simulador antes de añadirlas (borra apps y fotos; defecto 0)
#   SCREENS_DIR  directorio donde DayZeroScanTests guarda rejilla.png y wrapped.png y LayersInspectorTests
#              las hojas de "Compartir capas" (defecto harness/out/screens; TEST_RUNNER_COLORSAPP_SCREENS_DIR)
#   SUBJECT_SCREENS_DIR  capturas de ios-screens-subject (defecto harness/out/screens-subject)
#   SCREEN_WAIT  segundos entre lanzar la app y capturar (defecto 7)

IOS_DIR    := $(ROOT)/ios
IOS_PROJ   := $(IOS_DIR)/ColorsApp.xcodeproj
IOS_SCHEME := ColorsApp
IOS_BUNDLE := com.andreseloy.colorsapp
DERIVED   ?= build-ios
BUILD_IOS  := $(if $(filter /%,$(DERIVED)),$(DERIVED),$(ROOT)/$(DERIVED))
IOS_CONFIG ?= Debug
XCB := xcodebuild -project $(IOS_PROJ) -scheme $(IOS_SCHEME) -configuration $(IOS_CONFIG) -derivedDataPath $(BUILD_IOS)
XCB_QUIET ?= -quiet
# Simulador por nombre (SIM_NAME) -> UDID; se evalúa solo cuando un target lo usa.
# Con varios runtimes del mismo nombre se toma el primero que lista simctl.
SIM_NAME ?= iPhone 18 Pro
SIM_UDID ?= ${shell xcrun simctl list devices available | grep -m1 -E '^[[:space:]]+$(SIM_NAME) \(' | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/'}
SIM_APP    := $(BUILD_IOS)/Build/Products/$(IOS_CONFIG)-iphonesimulator/ColorsApp.app
DEVICE_APP := $(BUILD_IOS)/Build/Products/$(IOS_CONFIG)-iphoneos/ColorsApp.app
STUB_PNG   := $(ROOT)/harness/out/stub.png
SIM_MEDIA_DIR ?= $(IOS_DIR)/ColorsAppTests/Fixtures/sim_media
SIM_MEDIA ?= 1
SIM_RESET ?= 0
SIM_MEDIA_STAMP = $(ROOT)/harness/out/sim-media/$(SIM_UDID).stamp
SCREENS_DIR ?= $(ROOT)/harness/out/screens

.PHONY: ios-generate ios-build-sim ios-build-device-nosign ios-test-sim ios-test-sim-media ios-run-sim ios-addmedia ios-install ios-lint ios-clean ios-layers-fixtures ios-screens-subject

ios-generate:
	@test -f $(IOS_DIR)/Signing.xcconfig || { cp $(IOS_DIR)/Signing.example.xcconfig $(IOS_DIR)/Signing.xcconfig && echo "ios-generate: creado ios/Signing.xcconfig desde la plantilla (DEVELOPMENT_TEAM = REEMPLAZAR)"; }
	cd $(IOS_DIR) && xcodegen generate

$(IOS_PROJ)/project.pbxproj: $(IOS_DIR)/project.yml
	$(MAKE) ios-generate

ios-build-sim: $(IOS_PROJ)/project.pbxproj
	$(XCB) $(XCB_QUIET) -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

ios-build-device-nosign: $(IOS_PROJ)/project.pbxproj
	$(XCB) $(XCB_QUIET) -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

# Todos los XCTest en el simulador SIM_NAME: arranca el simulador si está apagado
# (bootstatus -b), concede el acceso a Fotos a la app (PLAN §8 F7: el escaneo día 0
# necesita `.authorized`; el comando está en `xcrun simctl help privacy`), añade las
# fixtures del carrete (ios-test-sim-media, una vez por simulador) y lanza
# xcodebuild test. `-collect-test-diagnostics never`: sin un fallo, xcodebuild
# recogería un sysdiagnose del simulador (~10 min) antes de terminar.
# DayZeroScanTests guarda rejilla.png y wrapped.png en SCREENS_DIR.
ios-test-sim: $(IOS_PROJ)/project.pbxproj ios-test-sim-media
	@test -n "$(SIM_UDID)" || { echo "ios-test-sim: no hay simulador '$(SIM_NAME)' (xcrun simctl list devices available; o pasa SIM_NAME=... / SIM_UDID=...)"; exit 1; }
	xcrun simctl bootstatus $(SIM_UDID) -b
	xcrun simctl privacy $(SIM_UDID) grant photos $(IOS_BUNDLE)
	mkdir -p $(SCREENS_DIR)
	TEST_RUNNER_COLORSAPP_SCREENS_DIR=$(SCREENS_DIR) $(XCB) $(XCB_QUIET) -destination 'platform=iOS Simulator,id=$(SIM_UDID)' CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never test

# Fixtures del carrete para DayZeroScanTests (PLAN §8 F7): boot, grant photos y
# `simctl addmedia` de los 20 PNG de SIM_MEDIA_DIR. addmedia no es idempotente
# (cada llamada duplica las fotos), así que se deja un sello por simulador en
# harness/out/sim-media/<udid>.stamp y no se repite mientras exista. Si el
# simulador se borra por otra vía, borrar el sello o usar SIM_RESET=1, que hace
# `simctl shutdown` + `simctl erase` (borra apps, fotos y ajustes del simulador)
# antes de arrancarlo y añadirlas de nuevo. SIM_MEDIA=0 no toca el carrete.
ios-test-sim-media:
	@test "$(SIM_MEDIA)" = "1" || { echo "ios-test-sim-media: omitido (SIM_MEDIA=$(SIM_MEDIA))"; exit 0; }; \
	test -n "$(SIM_UDID)" || { echo "ios-test-sim-media: no hay simulador '$(SIM_NAME)'"; exit 1; }; \
	n=$$(ls "$(SIM_MEDIA_DIR)"/*.png 2>/dev/null | wc -l | tr -d ' '); test "$$n" -gt 0 || { echo "ios-test-sim-media: ningún PNG en $(SIM_MEDIA_DIR) (uv run --project oracle python oracle/tools/make_sim_media.py)"; exit 1; }; \
	if [ "$(SIM_RESET)" = "1" ]; then \
	  echo "ios-test-sim-media: SIM_RESET=1, borrando el simulador $(SIM_NAME) ($(SIM_UDID))"; \
	  xcrun simctl shutdown $(SIM_UDID) >/dev/null 2>&1 || true; \
	  xcrun simctl erase $(SIM_UDID); \
	  rm -f $(SIM_MEDIA_STAMP); \
	fi; \
	if [ -f $(SIM_MEDIA_STAMP) ]; then \
	  echo "ios-test-sim-media: fixtures ya añadidas a $(SIM_NAME) ($$(cat $(SIM_MEDIA_STAMP))); rm $(SIM_MEDIA_STAMP) o SIM_RESET=1 para repetir"; \
	else \
	  xcrun simctl bootstatus $(SIM_UDID) -b && \
	  xcrun simctl privacy $(SIM_UDID) grant photos $(IOS_BUNDLE) && \
	  xcrun simctl addmedia $(SIM_UDID) "$(SIM_MEDIA_DIR)"/*.png && \
	  mkdir -p $(dir $(SIM_MEDIA_STAMP)) && echo "$$n PNG de $(SIM_MEDIA_DIR) $$(date -u +%Y-%m-%dT%H:%M:%SZ)" > $(SIM_MEDIA_STAMP) && \
	  echo "ios-test-sim-media: $$n PNG añadidos al carrete de $(SIM_NAME) ($(SIM_UDID))"; \
	fi

# Añade al carrete del simulador todos los PNG de MEDIA_DIR (fixtures del escaneo
# día 0, PLAN §8 F7). El simulador debe estar arrancado (bootstatus -b lo arranca).
ios-addmedia:
	@test -n "$(MEDIA_DIR)" || { echo "ios-addmedia: falta MEDIA_DIR=<directorio con PNG>"; exit 1; }
	@test -n "$(SIM_UDID)" || { echo "ios-addmedia: no hay simulador '$(SIM_NAME)'"; exit 1; }
	@n=$$(ls "$(MEDIA_DIR)"/*.png 2>/dev/null | wc -l | tr -d ' '); test "$$n" -gt 0 || { echo "ios-addmedia: ningún PNG en $(MEDIA_DIR)"; exit 1; }; \
	xcrun simctl bootstatus $(SIM_UDID) -b && \
	xcrun simctl addmedia $(SIM_UDID) "$(MEDIA_DIR)"/*.png && echo "ios-addmedia: $$n PNG añadidos al carrete de $(SIM_NAME) ($(SIM_UDID))"

ios-run-sim: $(IOS_PROJ)/project.pbxproj
	@test -n "$(SIM_UDID)" || { echo "ios-run-sim: no hay iPhone simulado disponible"; exit 1; }
	$(XCB) $(XCB_QUIET) -destination 'platform=iOS Simulator,id=$(SIM_UDID)' CODE_SIGNING_ALLOWED=NO build
	xcrun simctl bootstatus $(SIM_UDID) -b
	xcrun simctl install $(SIM_UDID) $(SIM_APP)
	xcrun simctl launch $(SIM_UDID) $(IOS_BUNDLE)
	sleep 4
	mkdir -p $(dir $(STUB_PNG))
	xcrun simctl io $(SIM_UDID) screenshot $(STUB_PNG)
	@echo "ios-run-sim: captura en $(STUB_PNG) ($$(stat -f%z $(STUB_PNG)) bytes)"

# Instalación en un iPhone físico con el Personal Team. Requiere que el usuario
# haya iniciado sesión con su Apple ID en Xcode (identidad "Apple Development")
# y haya puesto su Team ID en ios/Signing.xcconfig. Ver docs/RELEASE.md.
ios-install: $(IOS_PROJ)/project.pbxproj
	@test -n "$(DEVICE)" || { echo "ios-install: falta DEVICE=<udid>. Lista: xcrun devicectl list devices"; exit 1; }
	@n=$$(security find-identity -v -p codesigning 2>/dev/null | grep -c "Apple Development" || true); \
	if [ "$$n" -lt 1 ]; then \
	  echo "ios-install: no hay ninguna identidad 'Apple Development' en el llavero (security find-identity -v -p codesigning)."; \
	  echo "  Pasos (solo el usuario, ver docs/RELEASE.md):"; \
	  echo "   1. Xcode > Settings > Apple Accounts > + > iniciar sesión con el Apple ID (Personal Team)."; \
	  echo "   2. Copiar el Team ID a ios/Signing.xcconfig (DEVELOPMENT_TEAM = XXXXXXXXXX)."; \
	  echo "   3. Abrir ios/ColorsApp.xcodeproj una vez, Signing & Capabilities > Team, para que Xcode cree el certificado."; \
	  echo "   4. Repetir: make ios-install DEVICE=$(DEVICE)"; \
	  exit 1; \
	fi
	@grep -q "REEMPLAZAR" $(IOS_DIR)/Signing.xcconfig 2>/dev/null && { echo "ios-install: ios/Signing.xcconfig sigue con DEVELOPMENT_TEAM = REEMPLAZAR; pon el Team ID del Personal Team."; exit 1; } || true
	$(XCB) $(XCB_QUIET) -destination 'id=$(DEVICE)' -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
	xcrun devicectl device install app --device $(DEVICE) $(DEVICE_APP)
	xcrun devicectl device process launch --device $(DEVICE) $(IOS_BUNDLE)

ios-clean:
	rm -rf $(BUILD_IOS) $(IOS_PROJ)

# Sin red en la app (CLAUDE.md, §7 del plan): ninguna referencia a URLSession,
# NWConnection ni CFNetwork en ios/. Se excluyen el .xcodeproj generado por
# xcodegen y cualquier build-ios/ (DerivedData). Forma parte de make release-week
# desde F0 y de make eval desde F6. grep devuelve 1 cuando no hay coincidencias
# (eso es el OK) y 0 cuando las hay (eso es el fallo); >1 es un error de grep.
IOS_LINT_PATTERN := URLSession|NWConnection|CFNetwork

ios-lint:
	@out=$$(grep -rnE --exclude-dir='*.xcodeproj' --exclude-dir=build-ios '$(IOS_LINT_PATTERN)' $(IOS_DIR)); rc=$$?; \
	if [ $$rc -eq 0 ]; then \
	  printf '%s\n' "$$out"; \
	  echo "ios-lint: FALLO: $$(printf '%s\n' "$$out" | wc -l | tr -d ' ') línea(s) con $(IOS_LINT_PATTERN) en ios/ (la app no usa red)"; exit 1; \
	elif [ $$rc -eq 1 ]; then \
	  echo "ios-lint: OK (0 referencias a $(IOS_LINT_PATTERN) en ios/, sin contar *.xcodeproj ni build-ios/)"; \
	else \
	  echo "ios-lint: grep falló (rc=$$rc)"; exit $$rc; \
	fi

# Fixtures del inspector de capas (LayersInspectorTests): el test escribe la
# escena sintética de la app (SyntheticPersonScene) y la máscara de su cadena
# por defecto en $(IOS_LAYERS_WORK) (en esa pasada falla la comparación si las
# fixtures estaban desfasadas: se ignora), el CLI `ce` compilado en
# $(BUILD_IOS)/engine calcula labels.pgm y debug.json con --debug-dir, y
# ios/Scripts/make_layers_fixtures.sh copia todo a Fixtures/layers/. Después se
# regenera el proyecto (ficheros nuevos) y hay que volver a ejecutar ios-test-sim.
IOS_LAYERS_FIXTURES := $(IOS_DIR)/ColorsAppTests/Fixtures/layers
IOS_LAYERS_WORK = $(BUILD_IOS)/layers-fixtures
IOS_CE_BUILD = $(BUILD_IOS)/engine

ios-layers-fixtures: $(IOS_PROJ)/project.pbxproj
	@test -n "$(SIM_UDID)" || { echo "ios-layers-fixtures: no hay simulador '$(SIM_NAME)'"; exit 1; }
	cmake -S $(ENGINE) -B $(IOS_CE_BUILD) -DCMAKE_BUILD_TYPE=Release > /dev/null
	cmake --build $(IOS_CE_BUILD) --parallel --target ce
	rm -rf $(IOS_LAYERS_WORK) && mkdir -p $(IOS_LAYERS_WORK)
	xcrun simctl bootstatus $(SIM_UDID) -b
	-TEST_RUNNER_COLORSAPP_LAYERS_FIXTURES_OUT=$(IOS_LAYERS_WORK) $(XCB) $(XCB_QUIET) -destination 'platform=iOS Simulator,id=$(SIM_UDID)' CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never test -only-testing:ColorsAppTests/LayersInspectorTests/testDemoSceneMatchesFixtures
	sh $(IOS_DIR)/Scripts/make_layers_fixtures.sh $(IOS_CE_BUILD)/tools/ce $(IOS_LAYERS_WORK) $(IOS_LAYERS_FIXTURES)
	$(MAKE) ios-generate

# Capturas del recorte de sujeto y de las capas (atajos DEBUG de DebugLaunch):
# Resultado con la foto de grupo embebida (result-people), con "Ver máscara"
# (result-people-mask), inspector de esa foto (layers-people), la escena
# sintética con una persona (result-demo-person; layers-demo, una captura por
# capa con -uiLayer) y con dos (result-demo-people[-mask]: fila "Personas" y
# "Ver máscara" con la cadena real) y Ajustes (sección Recorte arriba). En el simulador Vision no crea su contexto
# de inferencia: result-people y layers-people muestran el retorno "Vision no
# disponible"; layers-demo usa personas sintéticas y la cadena real del motor.
SUBJECT_SCREENS_DIR ?= $(ROOT)/harness/out/screens-subject
SCREEN_WAIT ?= 7
SUBJECT_SCREENS := result-people:-uiScreen,result-people \
  result-people-mask:-uiScreen,result-people-mask \
  layers-people-04:-uiScreen,layers-people,-uiLayer,4 \
  layers-people-07:-uiScreen,layers-people,-uiLayer,7 \
  layers-people-08:-uiScreen,layers-people,-uiLayer,8 \
  layers-people-12:-uiScreen,layers-people,-uiLayer,12 \
  result-demo-person:-uiScreen,result-demo-person \
  result-demo-people:-uiScreen,result-demo-people \
  result-demo-people-mask:-uiScreen,result-demo-people-mask \
  layers-demo-01:-uiScreen,layers-demo,-uiLayer,1 \
  layers-demo-03:-uiScreen,layers-demo,-uiLayer,3 \
  layers-demo-04:-uiScreen,layers-demo,-uiLayer,4 \
  layers-demo-05:-uiScreen,layers-demo,-uiLayer,5 \
  layers-demo-06:-uiScreen,layers-demo,-uiLayer,6 \
  layers-demo-07:-uiScreen,layers-demo,-uiLayer,7 \
  layers-demo-08:-uiScreen,layers-demo,-uiLayer,8 \
  layers-demo-09:-uiScreen,layers-demo,-uiLayer,9 \
  layers-demo-10:-uiScreen,layers-demo,-uiLayer,10 \
  layers-demo-11:-uiScreen,layers-demo,-uiLayer,11 \
  layers-demo-12:-uiScreen,layers-demo,-uiLayer,12 \
  ajustes-recorte:-uiScreen,ajustes

ios-screens-subject: $(IOS_PROJ)/project.pbxproj
	@test -n "$(SIM_UDID)" || { echo "ios-screens-subject: no hay simulador '$(SIM_NAME)'"; exit 1; }
	$(XCB) $(XCB_QUIET) -destination 'platform=iOS Simulator,id=$(SIM_UDID)' CODE_SIGNING_ALLOWED=NO build
	xcrun simctl bootstatus $(SIM_UDID) -b
	xcrun simctl install $(SIM_UDID) $(SIM_APP)
	mkdir -p $(SUBJECT_SCREENS_DIR)
	@for spec in $(SUBJECT_SCREENS); do \
	  name=$${spec%%:*}; args=$$(echo "$${spec#*:}" | tr ',' ' '); \
	  xcrun simctl terminate $(SIM_UDID) $(IOS_BUNDLE) >/dev/null 2>&1 || true; \
	  xcrun simctl launch $(SIM_UDID) $(IOS_BUNDLE) $$args >/dev/null || exit 1; \
	  sleep $(SCREEN_WAIT); \
	  xcrun simctl io $(SIM_UDID) screenshot $(SUBJECT_SCREENS_DIR)/$$name.png >/dev/null 2>&1 || exit 1; \
	  echo "ios-screens-subject: $$name ($$args) -> $(SUBJECT_SCREENS_DIR)/$$name.png"; \
	done
	xcrun simctl terminate $(SIM_UDID) $(IOS_BUNDLE) >/dev/null 2>&1 || true
