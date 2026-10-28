# App Android (ChromaSol): Gradle Wrapper en android/, motor C11 por NDK/JNI.
# Incluido automáticamente por el Makefile raíz (usa ROOT). El Makefile raíz
# no se edita.
#
#   make android-build          APK debug (:app:assembleDebug)
#   make android-test           tests de unidad JVM (host) de :engine y :app
#   make android-test-device    tests instrumentados en un emulador/dispositivo
#                               YA arrancado: paridad del motor contra
#                               harness/golden + fixtures WASM y humo de UI
#   make android-lint           puerta "sin red": falla si el manifiesto
#                               fusionado de release pide INTERNET (o cualquier
#                               permiso de red) o si el código de la app usa
#                               APIs de red; además `gradle lint`
#   make android-bundle         AAB release (sin firmar; firma si están las
#                               variables CHROMASOL_KEYSTORE_PATH/ALIAS/PASSWORD)
#   make android-icon           regenera los iconos desde
#                               android/icon/icon_master.png (1024x1024)
#   make android-emulator       arranca el AVD ANDROID_AVD sin ventana (fondo)
#   make android-install        instala el APK debug en el dispositivo/emulador
#   make android-run            install + lanzar MainActivity
#   make android-screenshots    capturas de las 4 pestañas en harness/out/android
#   make android-wasm-expected  regenera wasm_expected.json con el `ce` de host
#   make android-strings-check  textos es/de/en contra Localizable.xcstrings
#                               de iOS (tools/check_strings.py, carril W1):
#                               falla si falta una traducción de/en o si un
#                               texto que corresponde a una clave de iOS
#                               difiere del catálogo
#
# Variables:
#   ANDROID_DIR   proyecto Gradle (defecto $(ROOT)/android)
#   XCSTRINGS     Localizable.xcstrings de iOS (defecto: búsqueda automática
#                 en el checkout principal hermano o en este repo)
#   ANDROID_AVD   AVD por defecto (defecto Medium_Phone_API_37.0)
#   ADB           adb (defecto el del SDK en ~/Library/Android/sdk)
#   JAVA_HOME     JDK 17 (defecto el de Homebrew openjdk@17)
#
# Requisitos: Android SDK (platform 36, NDK 29.0.14206865, build-tools) en
# ~/Library/Android/sdk y android/local.properties con sdk.dir (lo crea el
# destino android-local-properties si falta; está en .gitignore).

ANDROID_DIR ?= $(ROOT)/android
ANDROID_SDK ?= $(HOME)/Library/Android/sdk
ANDROID_JDK ?= /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
ADB ?= $(ANDROID_SDK)/platform-tools/adb
AAPT2 ?= $(ANDROID_SDK)/build-tools/36.0.0/aapt2
ANDROID_AVD ?= Medium_Phone_API_37.0
ANDROID_APP_ID := com.andreseloy.colorsapp
ANDROID_DEBUG_APK := $(ANDROID_DIR)/app/build/outputs/apk/debug/app-debug.apk
# Sin firma el APK se llama app-release-unsigned.apk; firmado, app-release.apk.
# (Su ruta se resuelve en el shell tras compilar, no con $(wildcard): ver
# android-check-no-network.)
ANDROID_AAB := $(ANDROID_DIR)/app/build/outputs/bundle/release/app-release.aab
ANDROID_OUT := $(ROOT)/harness/out/android

GRADLEW := cd $(ANDROID_DIR) && JAVA_HOME=$(ANDROID_JDK) ANDROID_HOME=$(ANDROID_SDK) ./gradlew --console=plain

.PHONY: android-build android-test android-test-device android-lint android-bundle \
        android-icon android-emulator android-install android-run android-screenshots \
        android-wasm-expected android-local-properties android-check-no-network \
        android-strings-check

android-local-properties:
	@if [ ! -f $(ANDROID_DIR)/local.properties ]; then \
	  echo "sdk.dir=$(ANDROID_SDK)" > $(ANDROID_DIR)/local.properties; \
	  echo "creado $(ANDROID_DIR)/local.properties"; \
	fi

android-build: android-local-properties
	$(GRADLEW) :app:assembleDebug
	@echo "APK: $(ANDROID_DEBUG_APK)"

android-test: android-local-properties
	$(GRADLEW) :engine:testDebugUnitTest :app:testDebugUnitTest

android-test-device: android-local-properties
	@$(ADB) get-state >/dev/null 2>&1 || { \
	  echo "sin dispositivo: arranca el emulador primero (make android-emulator)"; exit 1; }
	$(GRADLEW) :engine:connectedDebugAndroidTest :app:connectedDebugAndroidTest

# Puerta sin red, simétrica de ios-lint pero sobre el artefacto: se compila
# release (el manifiesto fusionado incluye lo que añadan las dependencias)
# y se buscan permisos de red en el manifiesto binario del APK.
# El APK se resuelve en el shell DESPUÉS de compilar: un $(wildcard) en la
# receta se expandía antes de ejecutar assembleRelease y en un árbol limpio
# salía vacío (había que correr android-lint dos veces).
android-check-no-network: android-local-properties
	$(GRADLEW) :app:assembleRelease
	@APK=$$(ls -t $(ANDROID_DIR)/app/build/outputs/apk/release/app-release*.apk 2>/dev/null | head -n 1); \
	  test -n "$$APK" || { echo "FALLO: no se generó el APK release"; exit 1; }; \
	  echo "permisos del APK release ($$APK):"; \
	  $(AAPT2) dump permissions "$$APK" || { echo "FALLO: aapt2 no pudo leer el APK"; exit 1; }; \
	  if $(AAPT2) dump permissions "$$APK" | grep -E "INTERNET|ACCESS_NETWORK_STATE|ACCESS_WIFI_STATE|CHANGE_NETWORK_STATE"; then \
	    echo "FALLO: permiso de red en el manifiesto fusionado de release"; exit 1; \
	  fi
	@if grep -rEl --include="*.kt" "java\.net\.|HttpURLConnection|OkHttp|Retrofit|Socket\(" $(ANDROID_DIR)/app/src/main $(ANDROID_DIR)/engine/src/main; then \
	  echo "FALLO: uso de APIs de red en el código de la app"; exit 1; \
	fi
	@echo "sin red: manifiesto y código OK"

android-lint: android-check-no-network
	$(GRADLEW) :app:lintRelease :engine:lint

android-bundle: android-local-properties
	$(GRADLEW) :app:bundleRelease
	@if [ -n "$$CHROMASOL_KEYSTORE_PATH" ] && [ -n "$$CHROMASOL_KEYSTORE_ALIAS" ]; then \
	  echo "AAB firmado: $(ANDROID_AAB)"; \
	else \
	  echo "AAB sin firmar: $(ANDROID_AAB) (define CHROMASOL_KEYSTORE_PATH/ALIAS/PASSWORD para firmar; con Play App Signing se sube así)"; \
	fi

android-icon:
	python3 $(ANDROID_DIR)/tools/make_icon.py

android-emulator:
	@$(ADB) get-state >/dev/null 2>&1 && echo "ya hay un dispositivo/emulador" || \
	  (echo "arrancando $(ANDROID_AVD) (segundo plano, log en build-android/emulator.log)"; \
	   mkdir -p $(ROOT)/build-android; \
	   $(ANDROID_SDK)/emulator/emulator -avd $(ANDROID_AVD) -no-window -no-audio -no-snapshot-save \
	     >>$(ROOT)/build-android/emulator.log 2>&1 & \
	   $(ADB) wait-for-device)
	@for i in $$(seq 1 60); do \
	  [ "$$($(ADB) shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break; sleep 5; \
	done; $(ADB) shell getprop sys.boot_completed

android-install: android-build
	$(ADB) install -r $(ANDROID_DEBUG_APK)

android-run: android-install
	$(ADB) shell am start -n $(ANDROID_APP_ID)/.app.MainActivity

android-screenshots: android-run
	mkdir -p $(ANDROID_OUT)
	@sleep 4; $(ADB) shell screencap -p /sdcard/tab-feed.png; $(ADB) pull -q /sdcard/tab-feed.png $(ANDROID_OUT)/tab-feed.png
	python3 $(ANDROID_DIR)/tools/capture_tabs.py $(ADB) $(ANDROID_OUT)
	@echo "capturas en $(ANDROID_OUT)"

android-wasm-expected:
	cmake -S $(ENGINE) -B $(ROOT)/build-android/host-ce -DCMAKE_BUILD_TYPE=Release
	cmake --build $(ROOT)/build-android/host-ce --parallel --target ce
	python3 $(ANDROID_DIR)/tools/gen_wasm_expected.py $(ROOT)/build-android/host-ce/tools/ce

# Cada carril pone sus textos en strings_<carril>.xml (es/de/en) copiados del
# catálogo de iOS y pasa este chequeo; ver la cabecera del script.
android-strings-check:
	python3 $(ANDROID_DIR)/tools/check_strings.py $(if $(XCSTRINGS),--xcstrings $(XCSTRINGS),)
