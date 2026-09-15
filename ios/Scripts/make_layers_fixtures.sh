#!/bin/sh
# Fixtures del inspector de capas (LayersInspectorTests):
#   sh ios/Scripts/make_layers_fixtures.sh <ce> <entrada> <Fixtures/layers>
# <entrada> contiene layers_demo.ppm y layers_demo.mask.pgm tal como los escribe
# LayersInspectorTests.testDemoSceneMatchesFixtures con
# COLORSAPP_LAYERS_FIXTURES_OUT (la escena sintética de la app y la máscara de
# su cadena por defecto). Ejecuta
#   ce match layers_demo.ppm --mask layers_demo.mask.pgm --top 3 --json --debug-dir
# y copia a <Fixtures/layers>: layers_demo.ppm, layers_demo.mask.pgm,
# layers_demo.labels.pgm (labels.pgm), layers_demo.debug.json (debug.json) y
# layers_demo.match.json (stdout), con las rutas de entrada reducidas a su
# nombre para que no dependan del directorio de trabajo. Exit 2 si falta algo.
set -eu
if [ $# -ne 3 ]; then
  echo "uso: $0 <ce> <entrada> <salida>" >&2
  exit 2
fi
CE=$1
IN=$(cd "$2" && pwd)
OUT=$3
for f in layers_demo.ppm layers_demo.mask.pgm; do
  if [ ! -f "$IN/$f" ]; then
    echo "make_layers_fixtures: falta $IN/$f (ejecutar el test con COLORSAPP_LAYERS_FIXTURES_OUT)" >&2
    exit 2
  fi
done
test -x "$CE" || { echo "make_layers_fixtures: no hay CLI ejecutable en $CE" >&2; exit 2; }
DBG="$IN/debug"
rm -rf "$DBG"
(cd "$IN" && "$CE" match layers_demo.ppm --mask layers_demo.mask.pgm --top 3 --json --debug-dir debug > layers_demo.match.json)
mkdir -p "$OUT"
cp "$IN/layers_demo.ppm" "$OUT/layers_demo.ppm"
cp "$IN/layers_demo.mask.pgm" "$OUT/layers_demo.mask.pgm"
cp "$DBG/labels.pgm" "$OUT/layers_demo.labels.pgm"
cp "$DBG/debug.json" "$OUT/layers_demo.debug.json"
cp "$IN/layers_demo.match.json" "$OUT/layers_demo.match.json"
echo "make_layers_fixtures: $(ls "$OUT" | wc -l | tr -d ' ') ficheros en $OUT"
grep -o '"hits": \[[^]]*\]' "$OUT/layers_demo.debug.json" | head -1
