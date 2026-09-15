# Cimientos (fase 0): diagnóstico del toolchain y rutas protegidas.
# Incluido automáticamente por el Makefile raíz (usa ROOT, ORACLE, UV, BUILD).
#
#   make doctor           tabla con el toolchain; exit 1 si falta una herramienta
#   make check-protected  falla si el árbol toca harness/PROTECTED.txt o el
#                         manifiesto sha256 no cuadra (salvo COLORSAPP_ALLOW_PROTECTED=1)
#   make protected-hash   regenera harness/PROTECTED.sha256 (exige COLORSAPP_ALLOW_PROTECTED=1)
#   make hooks            instala harness/hooks/pre-commit en .git/hooks
#   make bootstrap        reproduce el toolchain sin sudo: brew install de lo que falte
#                         (cmake, emscripten, uv, xcodegen), uv sync, hooks y doctor;
#                         idempotente (docs/SETUP.md)
#   make release-week     ritual semanal (§3 del plan): check-protected + gate de la
#                         escalera (RELEASE_GATE=test|eval-fast|eval) + ios-lint +
#                         ios-install en cada UDID de DEVICES (docs/RELEASE.md)

HARNESS := $(ROOT)/harness

.PHONY: doctor check-protected protected-hash hooks bootstrap release-week

# Guion del doctor. Cada fila: nombre, comando; la fila es informativa
# (no falla) cuando se marca con "info". `$$` porque lo expande make.
define DOCTOR_SH
missing=0
row() { printf '  %-14s %s\n' "$$1" "$$2"; }
probe() { # probe <nombre> <required|info> <comando...>
    name=$$1; kind=$$2; shift 2
    if out=$$("$$@" 2>/dev/null | head -1) && [ -n "$$out" ]; then
        row "$$name" "$$out"
    elif [ "$$kind" = required ]; then
        row "$$name" "NO ENCONTRADO"; missing=$$((missing+1))
    else
        row "$$name" "(no disponible)"
    fi
}
echo "colorsApp doctor"
probe xcode-select required xcode-select -p
probe xcodebuild   required sh -c 'xcodebuild -version 2>/dev/null | tr "\n" " "'
probe cc           required sh -c 'cc --version'
probe cmake        required sh -c 'cmake --version'
probe emcc         required sh -c 'emcc --version'
probe node         required node --version
probe uv           required uv --version
probe xcodegen     required xcodegen --version
probe python-venv  required sh -c 'cd "$(ORACLE)" && uv run python -c "import sys;print(sys.version.split()[0], sys.executable)"'
ids=$$(security find-identity -v -p codesigning 2>/dev/null | grep -c "Apple Development" || true)
row identidades "$$ids (Apple Development; informativo, 0 => iniciar sesión en Xcode > Settings > Apple Accounts)"
devs=$$(xcrun devicectl list devices 2>/dev/null | awk 'NR>2 && NF>0' | sed -E 's/  +/ | /g')
if [ -n "$$devs" ]; then
    printf '%s\n' "$$devs" | while IFS= read -r d; do row dispositivo "$$d"; done
else
    row dispositivo "(ninguno emparejado; informativo)"
fi
sims=$$(xcrun simctl list devices available 2>/dev/null | grep -c '^[[:space:]]*iPhone' || true)
row simuladores "$$sims iPhone disponibles (informativo)"
if [ "$$missing" -gt 0 ]; then
    echo "doctor: faltan $$missing herramienta(s) requerida(s); ver docs/SETUP.md o ejecuta make bootstrap"; exit 1
fi
echo "doctor: OK"
endef
export DOCTOR_SH

doctor:
	@printf '%s\n' "$$DOCTOR_SH" | sh -s

check-protected:
	$(UV) python $(HARNESS)/check_protected.py

protected-hash:
	$(UV) python $(HARNESS)/check_protected.py --write-hash

hooks:
	@hooks_dir=$$(git -C $(ROOT) rev-parse --git-path hooks) && \
	  case $$hooks_dir in /*) ;; *) hooks_dir=$(ROOT)/$$hooks_dir;; esac && \
	  mkdir -p "$$hooks_dir" && \
	  cp $(HARNESS)/hooks/pre-commit "$$hooks_dir/pre-commit" && \
	  chmod +x "$$hooks_dir/pre-commit" && \
	  echo "hooks: instalado $$hooks_dir/pre-commit"

# ---- bootstrap --------------------------------------------------------------
# Reproduce el toolchain en otra Mac o tras un reset (docs/SETUP.md). Idempotente
# y SIN sudo: lo que exige privilegios (Xcode desde la App Store, xcode-select -s)
# solo se avisa, no se ejecuta. Fórmula de brew => comando que la delata.
BOOTSTRAP_TOOLS := cmake:cmake emscripten:emcc uv:uv xcodegen:xcodegen

bootstrap:
	@echo "colorsApp bootstrap (idempotente, sin sudo)"
	@if command -v brew >/dev/null 2>&1; then \
	  printf '  %-14s %s\n' brew "$$(brew --version | head -1) en $$(brew --prefix)"; brew_ok=1; \
	else \
	  printf '  %-14s %s\n' brew "NO ENCONTRADO (https://brew.sh; lo instala el usuario)"; brew_ok=0; \
	fi; \
	missing=""; \
	for pair in $(BOOTSTRAP_TOOLS); do \
	  formula=$${pair%%:*}; cmd=$${pair##*:}; \
	  if command -v "$$cmd" >/dev/null 2>&1; then \
	    printf '  %-14s %s\n' "$$formula" "ok ($$(command -v "$$cmd"))"; \
	  else \
	    printf '  %-14s %s\n' "$$formula" "FALTA (no hay comando $$cmd)"; missing="$$missing $$formula"; \
	  fi; \
	done; \
	if [ -n "$$missing" ]; then \
	  if [ "$$brew_ok" = 1 ]; then \
	    echo "bootstrap: brew install$$missing"; brew install $$missing || exit 1; \
	  else \
	    echo "bootstrap: faltan$$missing y no hay brew; instala Homebrew (o esas herramientas a mano) y repite make bootstrap"; exit 1; \
	  fi; \
	else \
	  echo "bootstrap: cmake, emscripten, uv y xcodegen presentes; nada que instalar"; \
	fi
	@dev=$$(xcode-select -p 2>/dev/null); \
	case "$$dev" in \
	  */Xcode*.app/Contents/Developer) printf '  %-14s %s\n' xcode-select "$$dev";; \
	  *) printf '  %-14s %s\n' xcode-select "$${dev:-(sin ruta)}"; \
	     echo "bootstrap: AVISO: xcode-select no apunta a Xcode.app; make doctor fallará. Solo el usuario:"; \
	     echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"; \
	     echo "  o, sin sudo, en cada shell: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer";; \
	esac; \
	if xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then \
	  printf '  %-14s %s\n' xcodebuild "first launch OK"; \
	else \
	  echo "bootstrap: AVISO: xcodebuild -checkFirstLaunchStatus falló; ejecuta xcodebuild -runFirstLaunch (puede pedir contraseña de administrador) y, si lo pide, xcodebuild -license accept"; \
	fi
	cd $(ORACLE) && uv sync
	$(MAKE) -C $(ROOT) hooks
	$(MAKE) -C $(ROOT) doctor

# ---- release-week -----------------------------------------------------------
# Ritual semanal del Personal Team (perfil de 7 días), §3 del plan. La puerta de
# calidad sube por fases (escalera): test en F0–F2 (hoy), eval-fast desde F3,
# eval desde F4; se elige con RELEASE_GATE. Cada paso para la secuencia si falla.
# DEVICES = UDIDs separados por espacios (xcrun devicectl list devices); vacío =>
# solo comprobaciones e instrucciones, exit 0. Nunca se ejecuta contra un iPhone
# sin DEVICES explícito.
RELEASE_GATE ?= test
DEVICES ?=

release-week:
	@echo "release-week: gate=$(RELEASE_GATE) (escalera §3: test F0-F2, eval-fast F3, eval F4+); DEVICES='$(strip $(DEVICES))'"
	@case "$(RELEASE_GATE)" in test|eval-fast|eval) ;; \
	  *) echo "release-week: RELEASE_GATE debe ser test, eval-fast o eval (es '$(RELEASE_GATE)')"; exit 1;; esac
	$(MAKE) -C $(ROOT) check-protected
	$(MAKE) -C $(ROOT) $(RELEASE_GATE)
	$(MAKE) -C $(ROOT) ios-lint
# Condicional de make (se resuelve al leer el fichero): con DEVICES vacío la receta
# termina aquí con instrucciones y exit 0; un `exit 0` de shell solo cerraría su línea.
ifeq ($(strip $(DEVICES)),)
	@echo "release-week: comprobaciones en verde; no se instala nada porque DEVICES está vacío."; \
	echo "  Lista los iPhones emparejados:   xcrun devicectl list devices"; \
	echo "  Instala en los dos:              make release-week DEVICES=\"<udid iPhone 13 mini> <udid iPhone esposa>\""; \
	echo "  Fallback si la firma headless falla: abrir ios/ColorsApp.xcodeproj y Run (⌘R); ver docs/RELEASE.md"
else
	@for d in $(DEVICES); do \
	  echo "release-week: instalando en $$d"; \
	  $(MAKE) -C $(ROOT) ios-install DEVICE=$$d || exit 1; \
	done
	@echo "release-week: instalado en $(words $(DEVICES)) iPhone(s). Abre la app en cada uno y comprueba que el contador de lanzamientos no vuelve a 1 (docs/RELEASE.md)."
endif
