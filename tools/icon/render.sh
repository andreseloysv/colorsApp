#!/bin/sh
# Renderiza el icono ChromaSol con Blender (headless, Cycles/Metal).
# Uso: ./render.sh [--preview|--final] [opciones extra de build_icon.py]
set -eu
cd "$(dirname "$0")"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
MODE="${1:---final}"
case "$MODE" in --preview|--final) shift || true ;; *) MODE="--final" ;; esac
exec "$BLENDER" -b --factory-startup --python-exit-code 1 -P build_icon.py -- "$MODE" "$@"
