#!/bin/sh
# Capa 4 con personas: visionmask sobre cada foto, `ce batch` con todas las
# variantes, reproducción de cada capa con la CLI `ce` (repro.sh + cmp, y
# <foto>.split_repro.sh con `ce split` para las instancias separadas) e informe.
#
# uso: people_masks.sh VISIONMASK CE PEOPLE_DIR OUT_DIR [VARIANTS] [LAYERS 1|0] [MIN_COVERAGE]
#                      [MIN_REGION_FRACTION] [REFERENCES]
# Las variantes -garments (paleta por prenda, ADR-011) se analizan con `ce batch --garments`
# (imagen + máscara + mapa de regiones) y salen en el informe con un color por prenda.
# REFERENCES: JSON de parches de piel y fondo (apple/SubjectKit/Fixtures/people_references.json)
# para repartir el peso de la paleta en prenda / piel / fondo / otro; vacío = sin reparto.
# Exit != 0 si visionmask, ce batch, alguna reproducción o el informe fallan.
set -eu
VM=$1
CE=$2
PEOPLE=$3
OUT=$4
VARIANTS=${5:-none,allPeople,largest,largest-clothing,largest-clothing-skin}
LAYERS=${6:-1}
MINCOV=${7:-}
MINREGION=${8:-}
REFS=${9:-}

[ -x "$VM" ] || { echo "people_masks: no existe $VM (make visionmask)" >&2; exit 2; }
[ -x "$CE" ] || { echo "people_masks: no existe $CE" >&2; exit 2; }
[ -z "$REFS" ] || [ -f "$REFS" ] || { echo "people_masks: no existe $REFS" >&2; exit 2; }
set -- "$PEOPLE"/*.png
[ -f "$1" ] || { echo "people_masks: no hay PNG en $PEOPLE" >&2; exit 2; }

rm -rf "$OUT"
mkdir -p "$OUT"
EXTRA=""
[ "$LAYERS" = "1" ] && EXTRA="--layers"
[ -n "$MINCOV" ] && EXTRA="$EXTRA --min-coverage $MINCOV"
[ -n "$MINREGION" ] && EXTRA="$EXTRA --min-region-fraction $MINREGION"

echo "== visionmask ($# fotos, variantes $VARIANTS)"
for img in "$@"; do
  # Vision imprime avisos internos (FBBA...) por stderr: se filtran.
  "$VM" "$img" --out-dir "$OUT" --variants "$VARIANTS" $EXTRA 2> "$OUT/visionmask.stderr" || {
    cat "$OUT/visionmask.stderr" >&2; echo "people_masks: visionmask falló en $img" >&2; exit 1; }
  grep -v "FBBA" "$OUT/visionmask.stderr" >&2 || true
done
rm -f "$OUT/visionmask.stderr"

echo "== ce batch"
cat "$OUT"/*.batch.txt > "$OUT/batch.txt"
# Política de match de la app (EngineBridge.appMatchOptions): sin hipótesis de iluminante
# (ADR-009). Explícito para no depender del valor por defecto del motor.
"$CE" batch "$OUT/batch.txt" --json --illuminant-search 0 > "$OUT/batch.jsonl"
echo "$(wc -l < "$OUT/batch.jsonl" | tr -d ' ') análisis en $OUT/batch.jsonl"

# Paleta por prenda (ADR-011): las variantes -garments con pose dejan líneas
# "imagen mascara regiones" y se analizan con `ce batch --garments` (un color por prenda,
# tono iluminado). Sin pose la variante va en batch.txt (camino clásico, como la app).
GARMENTS=""
if ls "$OUT"/*.garments.txt > /dev/null 2>&1; then
  echo "== ce batch --garments"
  cat "$OUT"/*.garments.txt > "$OUT/garments.txt"
  "$CE" batch "$OUT/garments.txt" --garments --n-regions 2 --json --illuminant-search 0 > "$OUT/garments.jsonl"
  echo "$(wc -l < "$OUT/garments.jsonl" | tr -d ' ') análisis por prenda en $OUT/garments.jsonl"
  GARMENTS="$OUT/garments.jsonl"
fi

status=0
: > "$OUT/repro.tsv"
if [ "$LAYERS" = "1" ]; then
  echo "== reproducción de capas con ce"
  for script in "$OUT"/*.layers/repro.sh; do
    [ -f "$script" ] || continue
    sh "$script" "$CE" >> "$OUT/repro.tsv" || status=1
  done
  # Separación de instancias fusionadas: split<id>.labels.pgm == `ce split`.
  for script in "$OUT"/*.split_repro.sh; do
    [ -f "$script" ] || continue
    sh "$script" "$CE" >> "$OUT/repro.tsv" || status=1
  done
  rm -f "$OUT"/*.layers/repro_*.pgm "$OUT"/*.layers/repro_garments.json
  rm -rf "$OUT"/*.layers/repro_garments
  cut -f4 "$OUT/repro.tsv" | sort | uniq -c
fi

echo "== informe"
set --
[ -n "$REFS" ] && set -- --references "$REFS"
[ -n "$GARMENTS" ] && set -- "$@" --garments-batch "$GARMENTS"
"$VM" report --masks-dir "$OUT" --batch "$OUT/batch.jsonl" --expected "$PEOPLE/expected.json" \
  --out "$OUT/report.md" --repro "$OUT/repro.tsv" "$@" || status=1
exit $status
