#!/usr/bin/env python3
"""Regenera el YuNet TFLite de la app desde el ONNX fijado (carril W6).

La app ya no enlaza ONNX Runtime (libonnxruntime.so arm64 = 17,6 MB para
un modelo de 232 KB): YuNet corre con TFLite y el modelo convertido va
versionado en app/src/main/assets/models/ porque no tiene URL oficial.

Origen (inventario docs/research/android-subject.md §8.3):
  face_detection_yunet_2023mar.onnx, 232589 B, MIT (OpenCV Zoo),
  sha256 8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4
  https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx
Conversión: onnx2tf 2.6.9 (flatbuffer_direct), float32, sin cuantizar.
Salida versionada: face_detection_yunet_2023mar_float32.tflite, 236564 B,
sha256 43c65782ae622ea5aefc97632f2c69033fb8a314469e4c30703c88f9907cc380.

Paridad validada contra ONNX Runtime sobre harness/people (script de
validación en el informe W6): tensores con |Δ|máx 1,3e-5, mismas caras
y cajas a 0,00 px en las 9 fotos. Entrada TFLite NHWC [1,640,640,3]
(B,G,R entrelazado), salidas con los mismos nombres y formas que el
ONNX (cls/obj/bbox/kps × 8/16/32), por lo que YuNetDecode no cambia.

Uso (desde la raíz del repo, con el .onnx ya descargado por Gradle o a
mano verificando su sha256):
  uv run --project oracle --with onnx2tf==2.6.9 \\
      python android/tools/convert_yunet.py <ruta-al.onnx>
Deja el .tflite float32 en android/app/src/main/assets/models/.
"""

import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

EXPECTED_SHA256 = "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4"
EXPECTED_BYTES = 232589
OUT_NAME = "face_detection_yunet_2023mar_float32.tflite"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    src = Path(sys.argv[1])
    if src.stat().st_size != EXPECTED_BYTES or sha256(src) != EXPECTED_SHA256:
        print(f"ERROR: {src} no es el YuNet fijado (bytes/sha256 no cuadran)")
        return 1
    repo = Path(__file__).resolve().parents[2]
    work = repo / "build-android" / "yunet-tflite"
    work.mkdir(parents=True, exist_ok=True)
    local = work / "face_detection_yunet_2023mar.onnx"
    shutil.copyfile(src, local)
    out = work / "out"
    subprocess.run(
        [sys.executable, "-m", "onnx2tf", "-i", str(local), "-o", str(out)],
        check=True,
    )
    produced = out / OUT_NAME
    dest = repo / "android/app/src/main/assets/models" / OUT_NAME
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(produced, dest)
    print(f"{dest} ({dest.stat().st_size} B, sha256 {sha256(dest)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
