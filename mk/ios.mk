# App iOS (fase 0): proyecto XcodeGen, builds sin firma, tests y ejecución en
# simulador, instalación en iPhone con Personal Team.
# Incluido automáticamente por el Makefile raíz (usa ROOT).
#
#   make ios-generate             xcodegen generate (crea ios/Signing.xcconfig si falta)
#   make ios-build-sim            build para simulador genérico, sin firma
#   make ios-build-device-nosign  build para dispositivo genérico, sin firma
#   make ios-test-sim             xcodebuild test en el primer iPhone simulado disponible
#   make ios-run-sim              boot + install + launch en simulador y captura harness/out/stub.png
#   make ios-install DEVICE=<udid>  build firmada + devicectl install + launch (exige identidad)
#   make ios-lint                 sin red en la app: 0 referencias a URLSession|NWConnection|CFNetwork
#                                 en ios/ (sin el .xcodeproj generado ni build-ios/); exit 1 si hay alguna
#
# Variables: SIM_UDID (simulador; por defecto el primer iPhone disponible),
# DEVICE (UDID físico, ver `xcrun devicectl list devices`), IOS_CONFIG (Debug).

IOS_DIR    := $(ROOT)/ios
IOS_PROJ   := $(IOS_DIR)/ColorsApp.xcodeproj
IOS_SCHEME := ColorsApp
IOS_BUNDLE := com.andreseloy.colorsapp
BUILD_IOS  := $(ROOT)/build-ios
IOS_CONFIG ?= Debug
XCB := xcodebuild -project $(IOS_PROJ) -scheme $(IOS_SCHEME) -configuration $(IOS_CONFIG) -derivedDataPath $(BUILD_IOS)
XCB_QUIET ?= -quiet
# Primer iPhone simulado disponible (se evalúa solo cuando un target lo usa).
SIM_UDID ?= $(shell xcrun simctl list devices available | grep -m1 -E '^[[:space:]]+iPhone' | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')
SIM_APP    := $(BUILD_IOS)/Build/Products/$(IOS_CONFIG)-iphonesimulator/ColorsApp.app
DEVICE_APP := $(BUILD_IOS)/Build/Products/$(IOS_CONFIG)-iphoneos/ColorsApp.app
STUB_PNG   := $(ROOT)/harness/out/stub.png

.PHONY: ios-generate ios-build-sim ios-build-device-nosign ios-test-sim ios-run-sim ios-install ios-lint ios-clean

ios-generate:
	@test -f $(IOS_DIR)/Signing.xcconfig || { cp $(IOS_DIR)/Signing.example.xcconfig $(IOS_DIR)/Signing.xcconfig && echo "ios-generate: creado ios/Signing.xcconfig desde la plantilla (DEVELOPMENT_TEAM = REEMPLAZAR)"; }
	cd $(IOS_DIR) && xcodegen generate

$(IOS_PROJ)/project.pbxproj: $(IOS_DIR)/project.yml
	$(MAKE) ios-generate

ios-build-sim: $(IOS_PROJ)/project.pbxproj
	$(XCB) $(XCB_QUIET) -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

ios-build-device-nosign: $(IOS_PROJ)/project.pbxproj
	$(XCB) $(XCB_QUIET) -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

ios-test-sim: $(IOS_PROJ)/project.pbxproj
	@test -n "$(SIM_UDID)" || { echo "ios-test-sim: no hay iPhone simulado disponible (xcrun simctl list devices available)"; exit 1; }
	$(XCB) $(XCB_QUIET) -destination 'platform=iOS Simulator,id=$(SIM_UDID)' CODE_SIGNING_ALLOWED=NO test

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
