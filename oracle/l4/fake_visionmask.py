"""Doble de pruebas de ``visionmask`` (apple/SubjectKit) sin Vision, para los tests del oráculo.

    python -m l4.fake_visionmask <imagen> --out-dir DIR [--variants LISTA] [--layers] [--max-side N]
                                [--min-coverage F]

Respeta el contrato de salida de ``visionmask`` que usan ``l4.variants``, ``l4.people_smoke`` y
``tools/layers_report.py`` (``<base>.ppm``, ``<base>.<variante>.pgm``, ``<base>.batch.txt``,
``<base>.json`` y, con ``--layers``, ``<base>.<variante>.layers/`` con ``person.pgm``,
``region.pgm``, ``face_sample.pgm``, ``skin_removed.pgm``, ``person_final.pgm``, ``final.pgm``,
``instances.pgm|ppm`` y ``pose.txt``), con personas geométricas deterministas:

- persona 0 (la más grande): x en [0,05·W, 0,55·W), y en [0,05·H, H);
- persona 1: x en [0,65·W, 0,95·W), y en [0,30·H, H);
- ``-clothing``: la persona desde y = 0,30·H (pasos ``poseRegions``, con pose.txt coherente);
- ``-skin``: se quita la franja x en [0,05·W, 0,15·W), y en [0,30·H, 0,40·H) (``skinExcluded``) y la
  muestra de cara es x en [0,20·W, 0,40·W), y en [0,10·H, 0,20·H);
- si el nombre del fichero contiene ``nopeople``: ninguna persona (pasos ``noPeople``, sin máscara).

Exit: 0 ok; 2 uso o E/S (como visionmask).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

JOINTS = ["nose", "neck", "left_shoulder", "right_shoulder", "left_elbow", "right_elbow", "left_wrist",
          "right_wrist", "left_hip", "right_hip", "left_knee", "right_knee", "left_ankle", "right_ankle", "root"]
INSTANCE_COLORS = [(0, 0, 0), (230, 25, 75), (60, 180, 75), (0, 130, 200), (245, 130, 48)]


def _fail(msg: str) -> "None":
    sys.stderr.write(f"visionmask: {msg}\n")
    raise SystemExit(2)


def _rect(w: int, h: int, x0: float, x1: float, y0: float, y1: float) -> np.ndarray:
    m = np.zeros((h, w), dtype=np.uint8)
    m[int(round(y0 * h)):int(round(y1 * h)), int(round(x0 * w)):int(round(x1 * w))] = 255
    return m


def _pgm(path: Path, m: np.ndarray) -> None:
    h, w = m.shape
    path.write_bytes(f"P5\n{w} {h}\n255\n".encode("ascii") + m.astype(np.uint8).tobytes())


def _ppm(path: Path, rgb: np.ndarray) -> None:
    h, w, _ = rgb.shape
    path.write_bytes(f"P6\n{w} {h}\n255\n".encode("ascii") + rgb.astype(np.uint8).tobytes())


def _pose(w: int, h: int, x0: float, x1: float, y0: float) -> list[tuple[float, float, float]]:
    cx = (x0 + x1) / 2 * w
    sw = (x1 - x0) * w * 0.6
    top = y0 * h
    ys = {"nose": top + 0.08 * h, "neck": top + 0.2 * h, "sh": top + 0.25 * h, "el": top + 0.4 * h, "wr": top + 0.5 * h,
          "hip": top + 0.55 * h, "knee": top + 0.72 * h, "ank": top + 0.9 * h}
    pts = {"nose": (cx, ys["nose"]), "neck": (cx, ys["neck"]),
           "left_shoulder": (cx + sw / 2, ys["sh"]), "right_shoulder": (cx - sw / 2, ys["sh"]),
           "left_elbow": (cx + sw / 2 + 4, ys["el"]), "right_elbow": (cx - sw / 2 - 4, ys["el"]),
           "left_wrist": (cx + sw / 2 + 6, ys["wr"]), "right_wrist": (cx - sw / 2 - 6, ys["wr"]),
           "left_hip": (cx + sw / 3, ys["hip"]), "right_hip": (cx - sw / 3, ys["hip"]),
           "left_knee": (cx + sw / 3, ys["knee"]), "right_knee": (cx - sw / 3, ys["knee"]),
           "left_ankle": (cx + sw / 3, ys["ank"]), "right_ankle": (cx - sw / 3, ys["ank"]), "root": (cx, ys["hip"])}
    return [(float(pts[j][0]), float(pts[j][1]), 0.9) for j in JOINTS]


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    image = out_dir = None
    variants = ["none", "allPeople", "largest", "largest-clothing", "largest-clothing-skin"]
    layers = False
    max_side = 1024
    min_cov = 0.02
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("--out-dir", "--variants", "--max-side", "--min-coverage"):
            if i + 1 >= len(args):
                _fail(f"falta el valor de {a}")
            val = args[i + 1]
            i += 1
            if a == "--out-dir":
                out_dir = Path(val)
            elif a == "--variants":
                variants = [v for v in val.split(",") if v]
            elif a == "--max-side":
                max_side = int(val)
            else:
                min_cov = float(val)
        elif a == "--layers":
            layers = True
        elif a.startswith("--") or image is not None:
            _fail(f"argumento no reconocido: {a}")
        else:
            image = Path(a)
        i += 1
    if image is None or out_dir is None:
        _fail("uso: fake_visionmask <imagen> --out-dir DIR")
    try:
        with Image.open(image) as im:
            img = im.convert("RGB")
    except OSError as exc:
        _fail(f"no se pudo decodificar {image}: {exc}")
    if max(img.size) > max_side:
        f = max_side / float(max(img.size))
        img = img.resize((max(1, round(img.width * f)), max(1, round(img.height * f))), Image.Resampling.BOX)
    rgb = np.asarray(img, dtype=np.uint8)
    h, w, _ = rgb.shape
    out_dir.mkdir(parents=True, exist_ok=True)
    base = image.stem
    ppm = (out_dir / f"{base}.ppm").resolve()
    _ppm(ppm, rgb)
    nobody = "nopeople" in base.lower()
    rects = [] if nobody else [(0.05, 0.55, 0.05, 1.0), (0.65, 0.95, 0.30, 1.0)]
    persons = [_rect(w, h, *r) for r in rects]
    overlay = np.zeros((h, w), dtype=np.uint8)
    for k, m in enumerate(persons):
        overlay[(m >= 128) & (overlay == 0)] = k + 1
    people_json = [{"index": k, "id": k + 1, "coverage": float((m >= 128).mean()),
                    "bbox_xyxy": [round(r[0] * w), round(r[2] * h), round(r[1] * w), round(r[3] * h)],
                    "mask_pixels": int((m >= 128).sum()), "pose": True, "face": k == 0,
                    "face_sample_pixels": 0} for k, (m, r) in enumerate(zip(persons, rects))]
    batch_lines: list[str] = []
    variants_json: list[dict] = []
    for name in variants:
        if name == "none":
            batch_lines.append(f'"{ppm}"')
            variants_json.append({"name": "none", "mode": "off", "region": "wholePerson", "adaptive_skin": False,
                                  "mask": None, "mask_coverage": 0, "mask_pixels": None, "chosen_index": None,
                                  "steps": ["none"], "persons": [], "layers": None, "min_coverage": min_cov})
            continue
        parts = name.split("-")
        clothing, skin = "clothing" in parts, "skin" in parts
        if parts[0] == "allPeople":
            chosen = list(range(len(persons)))
        elif parts[0] == "largest":
            chosen = [0] if persons else []
        elif parts[0].startswith("selected") and parts[0][8:].isdigit():
            n = int(parts[0][8:])
            chosen = [n if n < len(persons) else 0] if persons else []
        else:
            _fail(f"variante desconocida: {name}")
        pl_json = []
        finals = []
        layer_masks: dict[str, list[np.ndarray]] = {"person": [], "region": [], "face_sample": [], "skin_removed": [], "person_final": []}
        poses = []
        for k in chosen:
            x0, x1, y0, _y1 = rects[k]
            person = persons[k]
            steps = []
            region = None
            cur = person
            if clothing:
                region = person & _rect(w, h, 0.0, 1.0, 0.30, 1.0)
                steps.append("poseRegions")
                cur = region
            face = removed = None
            if skin:
                face = _rect(w, h, 0.20, 0.40, 0.10, 0.20) & person
                removed = cur & _rect(w, h, 0.05, 0.15, 0.30, 0.40)
                cur = cur & ~removed
                steps.append("skinExcluded")
            layer_masks["person"].append(person)
            if region is not None:
                layer_masks["region"].append(region)
            if face is not None:
                layer_masks["face_sample"].append(face)
            if removed is not None:
                layer_masks["skin_removed"].append(removed)
            layer_masks["person_final"].append(cur)
            finals.append(cur)
            poses.append((k, _pose(w, h, x0, x1, y0)))
            pl_json.append({"index": k, "id": k + 1, "steps": steps, "person_pixels": int((person > 0).sum()),
                            "region_pixels": int((region > 0).sum()) if region is not None else None,
                            "face_sample_pixels": int((face > 0).sum()) if face is not None else None,
                            "skin_removed_pixels": int((removed > 0).sum()) if removed is not None else 0,
                            "final_pixels": int((cur > 0).sum()), "skin_note": None})
        mask = np.maximum.reduce(finals) if finals else None
        steps_all = sorted({s for p in pl_json for s in p["steps"]}, key=["poseRegions", "skinExcluded"].index) if finals else ["noPeople", "none"]
        coverage = float((mask >= 128).mean()) if mask is not None else 0.0
        mask_path = None
        if mask is not None:
            mask_path = (out_dir / f"{base}.{name}.pgm").resolve()
            _pgm(mask_path, mask)
            batch_lines.append(f'"{ppm}" "{mask_path}"')
        else:
            batch_lines.append(f'"{ppm}"')
        layers_path = None
        if layers:
            d = (out_dir / f"{base}.{name}.layers").resolve()
            d.mkdir(parents=True, exist_ok=True)
            layers_path = str(d)
            for key, ms in layer_masks.items():
                if ms:
                    _pgm(d / f"{key}.pgm", np.maximum.reduce(ms))
            if mask is not None:
                _pgm(d / "final.pgm", mask)
            _pgm(d / "instances.pgm", overlay)
            _ppm(d / "instances.ppm", np.array(INSTANCE_COLORS, dtype=np.uint8)[overlay % len(INSTANCE_COLORS)])
            for j, (k, pose) in enumerate(poses):
                text = f"# fake_visionmask {base} {name}: persona {k}\n" + "".join(f"{x} {y} {c}\n" for x, y, c in pose)
                if j == 0:
                    (d / "pose.txt").write_text(text, encoding="utf-8")
                if parts[0] == "allPeople":
                    (d / f"pose_{k}.txt").write_text(text, encoding="utf-8")
        variants_json.append({"name": name, "mode": "allPeople" if parts[0] == "allPeople" else "largestPerson",
                              "region": "clothing" if clothing else "wholePerson", "adaptive_skin": skin,
                              "mask": str(mask_path) if mask_path else None, "mask_coverage": coverage,
                              "mask_pixels": int((mask > 0).sum()) if mask is not None else None,
                              "chosen_index": chosen[0] if chosen and parts[0] != "allPeople" else None,
                              "steps": steps_all, "persons": pl_json, "layers": layers_path, "min_coverage": min_cov})
    (out_dir / f"{base}.batch.txt").write_text("\n".join(batch_lines) + "\n", encoding="utf-8")
    summary = {"tool": "visionmask", "fake": True, "engine": "fake", "dict_version": "fake", "image": str(image.resolve()),
               "base": base, "orientation": 1, "source_width": w, "source_height": h, "max_side": max_side, "width": w,
               "height": h, "stride": 4 * w, "raster": str(ppm), "batch": str((out_dir / f"{base}.batch.txt").resolve()),
               "vision": {"available": True, "error": None, "warnings": [], "unassigned_poses": 0, "unassigned_faces": 0},
               "timings_detect_ms": {"detect": 0.0}, "people_count": len(persons), "people": people_json, "variants": variants_json}
    (out_dir / f"{base}.json").write_text(json.dumps(summary, indent=1) + "\n", encoding="utf-8")
    print(f"{base}: {w}x{h} personas={len(persons)} (fake)")
    return 0


def write_executable(path: Path) -> Path:
    """Escribe un ejecutable ``sh`` que lanza este módulo con el intérprete actual (para los tests)."""
    oracle_dir = Path(__file__).resolve().parents[1]
    path.write_text(f'#!/bin/sh\nPYTHONPATH="{oracle_dir}${{PYTHONPATH:+:$PYTHONPATH}}" exec "{sys.executable}" -m l4.fake_visionmask "$@"\n',
                    encoding="utf-8")
    path.chmod(0o755)
    return path


if __name__ == "__main__":
    sys.exit(main())
