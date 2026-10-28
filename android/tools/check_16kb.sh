#!/usr/bin/env bash
# Comprueba que todas las librerías nativas de un AAB/APK admiten páginas de 16 KB: cada
# segmento LOAD del ELF debe estar alineado a 0x4000 o más. Play rechaza la release si no.
# uso: check_16kb.sh <app.aab|app.apk> <llvm-readelf>
set -euo pipefail
PKG=$1; READELF=$2
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
unzip -q -o "$PKG" '*.so' -d "$TMP" 2>/dev/null || { echo "16 KB: sin librerías nativas en $PKG"; exit 0; }
fail=0
while IFS= read -r so; do
  for a in $("$READELF" -lW "$so" | awk '/LOAD/{print $NF}'); do
    if [ $((a)) -lt $((0x4000)) ]; then echo "16 KB: FALLO ${so#$TMP/} alineado a $a"; fail=1; fi
  done
done < <(find "$TMP" -name '*.so')
[ $fail -eq 0 ] && echo "16 KB: OK, todas las librerías nativas alineadas a 16 KB o más" || exit 1
