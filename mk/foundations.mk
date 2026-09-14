# Cimientos (fase 0): diagnóstico del toolchain y rutas protegidas.
# Incluido automáticamente por el Makefile raíz (usa ROOT, ORACLE, UV, BUILD).
#
#   make doctor           tabla con el toolchain; exit 1 si falta una herramienta
#   make check-protected  falla si el árbol toca harness/PROTECTED.txt o el
#                         manifiesto sha256 no cuadra (salvo COLORSAPP_ALLOW_PROTECTED=1)
#   make protected-hash   regenera harness/PROTECTED.sha256 (exige COLORSAPP_ALLOW_PROTECTED=1)
#   make hooks            instala harness/hooks/pre-commit en .git/hooks

HARNESS := $(ROOT)/harness

.PHONY: doctor check-protected protected-hash hooks

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
    echo "doctor: faltan $$missing herramienta(s) requerida(s)"; exit 1
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
