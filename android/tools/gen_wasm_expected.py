#!/usr/bin/env python3
"""Genera wasm_expected.json: salida esperada de las 20 fixtures de paridad WASM.

Las fixtures (harness/wasm/fixtures/) solo traen los PPM y los argumentos; el
valor esperado lo produce el CLI nativo `ce` del motor en el host, el mismo
que compara `make parity` contra WASM. El test instrumentado de Android
compara el motor compilado por el NDK contra este fichero: mismo contrato que
`make golden-check` (tolerancia 1e-9, mismo top-3, mismo hash).

Uso:
    cmake -S engine -B build-android/host-ce -DCMAKE_BUILD_TYPE=Release
    cmake --build build-android/host-ce --parallel --target ce
    python3 android/tools/gen_wasm_expected.py [ruta-al-ce]
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "harness" / "wasm" / "fixtures"
OUT = ROOT / "android" / "engine" / "src" / "androidTest" / "assets" / "wasm_expected.json"


def main() -> int:
    ce = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build-android" / "host-ce" / "tools" / "ce"
    if not ce.exists():
        print(f"no existe el CLI ce: {ce}", file=sys.stderr)
        return 2
    manifest = json.loads((FIXTURES / "manifest.json").read_text(encoding="utf-8"))
    entries = []
    for entry in manifest["entries"]:
        ppm = FIXTURES / entry["file"]
        cmd = [str(ce), "match", str(ppm), "--json", "--top", "3", *entry.get("args", [])]
        proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if proc.returncode != 0:
            print(f"ce falló en {entry['file']}: {proc.stderr}", file=sys.stderr)
            return 1
        result = json.loads(proc.stdout)
        entries.append({
            "file": entry["file"],
            "args": entry.get("args", []),
            "width": result["width"],
            "height": result["height"],
            "swatches": result["swatches"],
            "hits": result["hits"],
            "ambiguous": result["ambiguous"],
            "hash": result["hash"],
        })
        print(f"ok {entry['file']}: top1={result['hits'][0]['id']} hash={result['hash']}")
    doc = {
        "schema": 1,
        "kind": "wasm_parity_expected",
        "generator": "android/tools/gen_wasm_expected.py (ce nativo del host)",
        "dict_version": manifest["dict_version"],
        "tolerance": 1e-9,
        "top_k": 3,
        "n": len(entries),
        "entries": entries,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"escrito {OUT} ({len(entries)} fixtures)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
