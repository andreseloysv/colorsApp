#!/usr/bin/env python3
"""Piel EN SOMBRA y zonas de pelo de apple/SubjectKit/Fixtures/people_references.json.

    uv run --project oracle python apple/SubjectKit/Scripts/people_references_shaded.py write
    uv run --project oracle python apple/SubjectKit/Scripts/people_references_shaded.py check

La verificación de ADR-010 mostró que la métrica «swatch a <= 10 ΔE00 de un parche de piel
iluminada» no veía la piel en sombra ni la mezclada en los bordes (swatches marrones a 12-39
ΔE00 de los parches). Cada parche de piel se oscurece en LUZ LINEAL (sRGB -> lineal x k ->
sRGB, IEC 61966-2-1: lo que hace una sombra sin cambio de cromaticidad) con k en SHADES, y el
resultado de 8 bits se guarda como «skin_shaded» (hex, nombre «<parche> xk», k). Las métricas
de SubjectKit (PeoplePhotosTests, visionmask report) clasifican con ellas; así no hay aritmética
de color en Swift fuera del motor.

«hair_zones» ([x0, y0, x1, y1] en píxeles del PNG, elegidos a mano sobre recortes con rejilla)
marca el pelo largo castaño que cae SOBRE la región de ropa (harness/people 02 y 03): tiene el
color de la piel en sombra y no es piel; las métricas por píxel no cuentan como piel lo que cae
dentro. Las zonas son fijas en este script (no se editan a mano en el JSON).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
REFS = ROOT / "apple" / "SubjectKit" / "Fixtures" / "people_references.json"
SHADES = [0.6, 0.35, 0.2]
HAIR_ZONES = {
    "02_single_dress_umbrella.png": [[388, 330, 455, 520]],
    "03_couple_denim_street.png": [[170, 335, 310, 580]],
}


def to_linear(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * np.power(np.clip(c, 0, None), 1 / 2.4) - 0.055)


def shaded(hex_: str, k: float) -> str:
    rgb = np.array([int(hex_[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float64) / 255.0
    out = np.clip(np.rint(to_srgb(to_linear(rgb) * k) * 255.0), 0, 255).astype(int)
    return "#%02x%02x%02x" % tuple(out)


def computed(doc: dict) -> dict:
    out = json.loads(json.dumps(doc))
    out["skin_shades"] = SHADES
    for name, photo in out["photos"].items():
        photo["skin_shaded"] = [{"hex": shaded(p["hex"], k), "name": f"{p['name']} x{k}", "k": k}
                                for p in photo["skin"] for k in SHADES]
        photo["hair_zones"] = HAIR_ZONES.get(name, [])
    return out


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in ("write", "check"):
        print(__doc__, file=sys.stderr)
        return 2
    doc = json.loads(REFS.read_text())
    want = computed(doc)
    if sys.argv[1] == "write":
        REFS.write_text(json.dumps(want, indent=1, ensure_ascii=False) + "\n")
        n = sum(len(p["skin_shaded"]) for p in want["photos"].values())
        print(f"people_references: {n} parches de piel en sombra y {sum(len(v) for v in HAIR_ZONES.values())} zonas de pelo -> {REFS}")
        return 0
    if doc != want:
        print("people_references: skin_shaded/hair_zones no coinciden con el script (ejecuta write)", file=sys.stderr)
        return 1
    print("people_references: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
