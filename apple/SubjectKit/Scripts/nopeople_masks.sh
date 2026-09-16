#!/bin/sh
# Personas fantasma: visionmask (Vision real, macOS) sobre imágenes SIN personas y tabla
# antes / después del filtro de evidencia corporal (docs/DECISIONS.md, ADR-010).
#
# uso: nopeople_masks.sh VISIONMASK NOPEOPLE_DIR SIM_MEDIA_DIR OUT_DIR [PYTHON]
#   PYTHON        intérprete para la tabla (defecto «uv run --project oracle python», regla del repo)
#   NOPEOPLE_DIR  148 PNG de harness/people/nopeople/build_nopeople.py (make subject-nopeople): bloques,
#                 degradados, texturas y 48 prendas sin persona (percha, perchero, planas, puerta, pila)
#   SIM_MEDIA_DIR los 20 PNG del carrete del simulador (ios/ColorsAppTests/Fixtures/sim_media)
# «antes» = instancias que devolvió Vision (personas aceptadas + fantasmas descartados del JSON);
# «después» = personas aceptadas. Gate (exit 1): alguna persona en sim_media, o menos del 98 % de las
# sintéticas sin personas aceptadas (en total o en la familia de prendas). Escribe
# OUT_DIR/summary.tsv y OUT_DIR/summary.md.
set -eu
VM=$1
NOPEOPLE=$2
SIM=$3
OUT=$4
PY=${5:-uv run --project oracle python}
[ -x "$VM" ] || { echo "nopeople_masks: no existe $VM (make visionmask)" >&2; exit 2; }
rm -rf "$OUT"
mkdir -p "$OUT"
: > "$OUT/summary.tsv"
status=0
for pair in "nopeople:$NOPEOPLE" "sim_media:$SIM"; do
  name=${pair%%:*}
  dir=${pair#*:}
  set -- "$dir"/*.png
  [ -f "$1" ] || { echo "nopeople_masks: no hay PNG en $dir" >&2; exit 2; }
  mkdir -p "$OUT/$name"
  for img in "$@"; do
    "$VM" "$img" --out-dir "$OUT/$name" --variants largest-clothing-skin 2> /dev/null > /dev/null || {
      echo "nopeople_masks: visionmask falló en $img" >&2; exit 1; }
  done
  rm -f "$OUT/$name"/*.ppm "$OUT/$name"/*.pgm
  for json in "$OUT/$name"/*.json; do
    # conjunto, base, personas aceptadas, fantasmas descartados, pasos de la variante por defecto, familia
    $PY - "$json" "$name" >> "$OUT/summary.tsv" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
steps = "+".join(d["variants"][0].get("steps", []))
fam = d["base"].split("_")[1] if sys.argv[2] == "nopeople" and "_" in d["base"] else sys.argv[2]
print("\t".join([sys.argv[2], d["base"], str(d["people_count"]), str(len(d.get("rejected_phantoms", []))), steps, fam]))
PY
  done
done
$PY - "$OUT/summary.tsv" "$OUT/summary.md" <<'PY' || status=1
import sys
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
md = ["# Personas fantasma (visionmask, Vision real)", "",
      "| conjunto | imágenes | con instancias de Vision (antes) | con personas aceptadas (después) | fantasmas descartados |",
      "|---|---|---|---|---|"]
ok = True
for name in ("nopeople", "sim_media"):
    sub = [r for r in rows if r[0] == name]
    before = sum(1 for r in sub if int(r[2]) + int(r[3]) > 0)
    after = sum(1 for r in sub if int(r[2]) > 0)
    phantoms = sum(int(r[3]) for r in sub)
    md.append(f"| {name} | {len(sub)} | {before} | {after} | {phantoms} |")
    print(f"{name}: {len(sub)} imágenes; con instancias de Vision (antes) {before}; con personas aceptadas (después) {after}; fantasmas descartados {phantoms}")
    if name == "sim_media" and after > 0:
        ok = False
    if name == "nopeople" and (len(sub) != 148 or len(sub) - after < 0.98 * len(sub)):
        ok = False
    if name == "nopeople":
        for fam in sorted({r[5] for r in sub}):
            fs = [r for r in sub if r[5] == fam]
            fa = sum(1 for r in fs if int(r[2]) > 0)
            fb = sum(1 for r in fs if int(r[2]) + int(r[3]) > 0)
            md.append(f"| nopeople/{fam} | {len(fs)} | {fb} | {fa} | {sum(int(r[3]) for r in fs)} |")
            print(f"  nopeople/{fam}: {len(fs)} imágenes; con instancias {fb}; con personas aceptadas {fa}")
            if len(fs) - fa < 0.98 * len(fs):
                ok = False
md += ["", "| conjunto | imagen | personas aceptadas | fantasmas | pasos (largest-clothing-skin) |", "|---|---|---|---|---|"]
md += [f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4] or '–'} |" for r in rows if int(r[2]) + int(r[3]) > 0]
open(sys.argv[2], "w").write("\n".join(md) + "\n")
print(f"informe: {sys.argv[2]}")
if not ok:
    print("nopeople_masks: GATE FALLIDO (personas en imágenes sin personas)", file=sys.stderr)
    sys.exit(1)
PY
exit $status
