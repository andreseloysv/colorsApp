#!/bin/sh
# Capa 4 con personas: visionmask sobre cada foto, `ce batch` con todas las
# variantes, reproducción de cada capa con la CLI `ce` (repro.sh + cmp) e informe.
#
# uso: people_masks.sh VISIONMASK CE PEOPLE_DIR OUT_DIR [VARIANTS] [LAYERS 1|0] [MIN_COVERAGE]
#                      [MIN_REGION_FRACTION] [REFERENCES]
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
"$CE" batch "$OUT/batch.txt" --json > "$OUT/batch.jsonl"
echo "$(wc -l < "$OUT/batch.jsonl" | tr -d ' ') análisis en $OUT/batch.jsonl"

status=0
: > "$OUT/repro.tsv"
if [ "$LAYERS" = "1" ]; then
  echo "== reproducción de capas con ce"
  for script in "$OUT"/*.layers/repro.sh; do
    [ -f "$script" ] || continue
    sh "$script" "$CE" >> "$OUT/repro.tsv" || status=1
  done
  rm -f "$OUT"/*.layers/repro_*.pgm
  cut -f4 "$OUT/repro.tsv" | sort | uniq -c
fi

echo "== informe"
if [ -n "$REFS" ]; then
  set -- --references "$REFS"
else
  set --
fi
"$VM" report --masks-dir "$OUT" --batch "$OUT/batch.jsonl" --expected "$PEOPLE/expected.json" \
  --out "$OUT/report.md" --repro "$OUT/repro.tsv" "$@" || status=1
exit $status
