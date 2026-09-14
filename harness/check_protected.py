#!/usr/bin/env python3
"""Comprueba que nadie ha tocado las rutas protegidas del repo.

Uso:
    uv run --project oracle python harness/check_protected.py [--write-hash]

Sin argumentos:
  1. Lee los globs de harness/PROTECTED.txt.
  2. Une `git diff --name-only HEAD`, `git diff --name-only --cached` y los
     ficheros untracked de `git status --porcelain` y los cruza con los globs.
  3. Recalcula el sha256 de cada fichero protegido existente (tracked o
     untracked no ignorado) y lo compara con harness/PROTECTED.sha256.
  4. Si hay hallazgos y COLORSAPP_ALLOW_PROTECTED != "1", los lista y sale con 1.
     Con COLORSAPP_ALLOW_PROTECTED=1 los lista como aviso y sale con 0.

Con --write-hash regenera harness/PROTECTED.sha256 (formato de `shasum -a 256`);
exige COLORSAPP_ALLOW_PROTECTED=1. Solo usa la biblioteca estándar.
"""

from __future__ import annotations

import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

HARNESS_DIR = Path(__file__).resolve().parent
ROOT = HARNESS_DIR.parent
PROTECTED_LIST = HARNESS_DIR / "PROTECTED.txt"
HASH_FILE = HARNESS_DIR / "PROTECTED.sha256"
ALLOW_ENV = "COLORSAPP_ALLOW_PROTECTED"


def allowed() -> bool:
    return os.environ.get(ALLOW_ENV, "") == "1"


def git(*args: str) -> str:
    """Ejecuta git en la raíz del repo y devuelve stdout (texto)."""
    proc = subprocess.run(
        ["git", "-C", str(ROOT), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} falló: {proc.stderr.strip()}")
    return proc.stdout


def git_z(*args: str) -> list[str]:
    """Como git(), pero con salida separada por NUL (-z) y sin entradas vacías."""
    return [p for p in git(*args, "-z").split("\0") if p]


def load_globs() -> list[str]:
    globs: list[str] = []
    for raw in PROTECTED_LIST.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        globs.append(line.rstrip("/"))
    return globs


def glob_to_regex(pattern: str) -> re.Pattern[str]:
    """Traduce un glob con `**` (cruza directorios) y `*`/`?` (no cruzan)."""
    out = []
    i = 0
    n = len(pattern)
    while i < n:
        c = pattern[i]
        if c == "*":
            if pattern.startswith("**", i):
                i += 2
                if i < n and pattern[i] == "/":
                    # "**/" al principio o en medio: cero o más directorios.
                    out.append("(?:.*/)?")
                    i += 1
                else:
                    # "**" final o pegado: cualquier cosa, incluidos "/".
                    out.append(".*")
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    return re.compile("^" + "".join(out) + "$")


def matcher(globs: list[str]):
    compiled = [(g, glob_to_regex(g)) for g in globs]

    def match(path: str) -> str | None:
        for g, rx in compiled:
            if rx.match(path):
                return g
        return None

    return match


def has_head() -> bool:
    proc = subprocess.run(
        ["git", "-C", str(ROOT), "rev-parse", "--verify", "-q", "HEAD"],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode == 0


def changed_paths() -> dict[str, str]:
    """Rutas cambiadas -> etiqueta corta (M = diff vs HEAD, A = staged, ?? = untracked)."""
    changed: dict[str, str] = {}
    if has_head():
        for p in git_z("diff", "--name-only", "HEAD"):
            changed[p] = "M "
        for p in git_z("diff", "--name-only", "--cached"):
            changed.setdefault(p, "A ")
    else:
        for p in git_z("diff", "--name-only", "--cached"):
            changed[p] = "A "
    # Untracked (no ignorados). En la salida -z de status cada entrada es
    # "XY ruta"; las renombradas llevan una segunda entrada con el origen.
    entries = git_z("status", "--porcelain", "--untracked-files=all")
    skip_next = False
    for e in entries:
        if skip_next:
            skip_next = False
            continue
        status, _, path = e[:2], e[2:3], e[3:]
        if status[0] == "R" or status[0] == "C":
            skip_next = True
        if status == "??":
            changed.setdefault(path, "??")
    return changed


def protected_files_on_disk(match) -> list[str]:
    """Ficheros protegidos presentes: tracked + untracked no ignorados."""
    paths = git_z("ls-files", "--cached", "--others", "--exclude-standard")
    seen: set[str] = set()
    result: list[str] = []
    for p in paths:
        if p in seen or match(p) is None:
            continue
        seen.add(p)
        if (ROOT / p).is_file():
            result.append(p)
    return sorted(result)


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_manifest() -> dict[str, str] | None:
    if not HASH_FILE.is_file():
        return None
    manifest: dict[str, str] = {}
    for raw in HASH_FILE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        digest, _, path = line.partition("  ")
        if len(digest) == 64 and path:
            manifest[path] = digest
    return manifest


def write_manifest(match) -> int:
    files = protected_files_on_disk(match)
    lines = [
        "# sha256 de cada fichero protegido (harness/PROTECTED.txt). Generado por",
        "# `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash`; verificable también con",
        "# `shasum -a 256 -c harness/PROTECTED.sha256` desde la raíz del repo.",
    ]
    for p in files:
        lines.append(f"{sha256_of(ROOT / p)}  {p}")
    HASH_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return len(files)


def hash_findings(match) -> list[tuple[str, str]]:
    """Discrepancias (tipo, ruta) entre el manifiesto y el disco."""
    manifest = read_manifest()
    if manifest is None:
        return [("sin-manifiesto", str(HASH_FILE.relative_to(ROOT)))]
    findings: list[tuple[str, str]] = []
    on_disk = protected_files_on_disk(match)
    disk_set = set(on_disk)
    for p in on_disk:
        expected = manifest.get(p)
        if expected is None:
            findings.append(("nuevo", p))
        elif sha256_of(ROOT / p) != expected:
            findings.append(("cambiado", p))
    for p in sorted(manifest):
        if p not in disk_set:
            findings.append(("ausente", p))
    return findings


def main(argv: list[str]) -> int:
    os.chdir(ROOT)
    globs = load_globs()
    match = matcher(globs)

    if "--write-hash" in argv:
        if not allowed():
            print(
                f"check-protected: --write-hash exige {ALLOW_ENV}=1 "
                "(solo el usuario/orquestador regenera harness/PROTECTED.sha256).",
                file=sys.stderr,
            )
            return 1
        n = write_manifest(match)
        print(f"check-protected: harness/PROTECTED.sha256 regenerado con {n} fichero(s).")
        return 0

    touched = [(tag, p, match(p)) for p, tag in sorted(changed_paths().items()) if match(p)]
    hashes = hash_findings(match)
    problems = bool(touched or hashes)

    if touched:
        print(f"check-protected: {len(touched)} ruta(s) protegida(s) con cambios en el árbol de trabajo:")
        for tag, p, g in touched:
            print(f"  {tag} {p}    (glob: {g})")
    if hashes:
        print(f"check-protected: {len(hashes)} discrepancia(s) con harness/PROTECTED.sha256:")
        for kind, p in hashes:
            print(f"  {kind:<15} {p}")

    if not problems:
        print(f"check-protected: OK ({len(globs)} globs, sin cambios en rutas protegidas).")
        return 0
    if allowed():
        print(f"check-protected: permitido por {ALLOW_ENV}=1 (recuerda `make protected-hash`).")
        return 0
    sys.stdout.flush()
    print(
        f"check-protected: FALLO. Revierte los cambios o, si el usuario los ha aprobado, "
        f"repite con {ALLOW_ENV}=1 y regenera el manifiesto con `make protected-hash`.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
