#!/usr/bin/env python3
"""Chequeo de textos de Android contra el catálogo de iOS (carril W1).

Falla (exit 1) si:

1. Algún recurso de `values/` (español, la fuente) no tiene traducción en
   `values-de/` o `values-en/`, o hay nombres huérfanos en de/en, o un
   mismo nombre aparece duplicado en un idioma.
2. Algún texto en español que *corresponde* a una clave del catálogo de iOS
   (`Localizable.xcstrings`: la clave ES el texto en español) tiene en
   alemán o inglés un texto distinto del del catálogo, o el catálogo no
   trae esa traducción.

Cómo lo usa cada carril:

- Pon tus textos en `values*/strings_<carril>.xml` con el prefijo de tu
  carril (`w3_…`) y copia los textos es/de/en del catálogo de iOS: busca tu
  texto en español como clave de `Localizable.xcstrings` y pega sus
  `localizations.de/en.stringUnit.value`. No inventes textos que iOS ya
  tiene; si el texto es nuevo de Android, tradúcelo tú a de/en (el chequeo
  solo exige que existan: no corresponden a ninguna clave).
- Especificadores: iOS usa `%@` (texto), `%lld`/`%d` (entero) y `%%` en
  orden; Android usa posicionales `%1$s`, `%1$d`, `%%`. El chequeo los
  normaliza por posición y tipo (ignora ancho y banderas: `%1$03d` cuenta
  como entero). Si pasas a Android un entero donde iOS formatea un texto
  (`%@` con `Nº 012` ya acolchado), los tipos no casan y el texto no
  corresponde: prefiere el mismo tipo que iOS (`%1$s` con el acolchado en
  código) para que el chequeo lo cubra.
- Ejecuta `make android-strings-check` antes de entregar. El catálogo se
  busca en: `--xcstrings`, `$COLORSAPP_XCSTRINGS`, el checkout principal
  hermano (`<repo>/../../colorsApp/ios/ColorsApp/Localizable.xcstrings`,
  para los carriles en colorsApp-lanes/) y `<repo>/ios/ColorsApp/…`.
- Divergencia deliberada (un texto que en Android debe diferir del de
  iOS): añádela a `android/tools/strings_allowlist.json` como
  `{"name": "w3_mi_recurso", "lang": "de"|"en"|"all", "reason": "…"}` y
  explícala en tu informe. La allowlist nunca exime de tener traducción.

Limitaciones conocidas: solo `<string>` (los `<plurals>` y
`<string-array>` se cuentan y se saltan); el texto se compara tal cual
salvo escapes de Android (`\\'`, `\\"`, `\\n`, `\\t`, `\\\\`) y un recorte
de espacios en los extremos (Android recorta los no entrecomillados).
Las claves del catálogo con `variations` (plurales) se saltan.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

LOCALES = {"es": "values", "de": "values-de", "en": "values-en"}

_PLACEHOLDER_RE = re.compile(
    r"%(?:(\d+)\$)?[#0\- +,(]*\d*(?:\.\d+)?(?:ll|l|hh|h)?([@a-zA-Z%])"
)


def _placeholder_kind(letter: str) -> str:
    if letter == "%":
        return "LIT"
    if letter in "@sScC":
        return "STR"
    if letter in "diouxXU":
        return "INT"
    return "FLOAT"


def normalize_format(text: str) -> str:
    """Sustituye cada especificador por un marcador {TIPO:posición}.

    Android posicional (%2$s) usa su índice; iOS (%@, %lld) y el Android no
    posicional usan el orden de aparición. `%%` pasa a ser un % literal.
    """
    out: list[str] = []
    last = 0
    sequential = 0
    for m in _PLACEHOLDER_RE.finditer(text):
        kind = _placeholder_kind(m.group(2))
        out.append(text[last : m.start()])
        if kind == "LIT":
            out.append("%")
        else:
            if m.group(1) is not None:
                position = int(m.group(1))
                sequential = max(sequential, position)
            else:
                sequential += 1
                position = sequential
            out.append("{%s:%d}" % (kind, position))
        last = m.end()
    out.append(text[last:])
    return "".join(out)


def android_unescape(text: str) -> str:
    """Aplica la semántica de recorte/escapes de los recursos de Android."""
    stripped = text.strip()
    if len(stripped) >= 2 and stripped[0] == '"' and stripped[-1] == '"':
        stripped = stripped[1:-1]
    return re.sub(
        r"\\(.)",
        lambda m: {"n": "\n", "t": "\t", "r": "\r"}.get(m.group(1), m.group(1)),
        stripped,
    )


def parse_strings_dir(res_dir: Path, folder: str) -> tuple[dict[str, str], set[str], list[str]]:
    """Lee todos los strings*.xml de una carpeta de idioma.

    Devuelve (nombre -> texto, no traducibles, errores)."""
    strings: dict[str, str] = {}
    untranslatable: set[str] = set()
    errors: list[str] = []
    for path in sorted((res_dir / folder).glob("strings*.xml")):
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError as exc:
            errors.append(f"{path}: XML no válido: {exc}")
            continue
        for element in root:
            if element.tag != "string":
                continue
            name = element.get("name")
            if not name:
                continue
            if name in strings:
                errors.append(f"{path}: recurso duplicado '{name}' en {folder}")
                continue
            strings[name] = android_unescape("".join(element.itertext()))
            if element.get("translatable") == "false":
                untranslatable.add(name)
    return strings, untranslatable, errors


def load_catalog(path: Path) -> dict[str, dict[str, str]]:
    """Catálogo iOS: texto español (la clave) -> {de, en} ya normalizados."""
    data = json.loads(path.read_text(encoding="utf-8"))
    catalog: dict[str, dict[str, str]] = {}
    for key, entry in data.get("strings", {}).items():
        localizations = entry.get("localizations") or {}
        row: dict[str, str] = {}
        for lang in ("de", "en"):
            unit = (localizations.get(lang) or {}).get("stringUnit") or {}
            value = unit.get("value")
            if value is not None:
                row[lang] = normalize_format(value)
        catalog[normalize_format(key)] = row
    return catalog


def find_xcstrings(explicit: str | None, repo_root: Path) -> Path | None:
    candidates: list[Path] = []
    if explicit:
        candidates.append(Path(explicit))
    env = os.environ.get("COLORSAPP_XCSTRINGS")
    if env:
        candidates.append(Path(env))
    candidates += [
        repo_root / "../../colorsApp/ios/ColorsApp/Localizable.xcstrings",
        repo_root / "ios/ColorsApp/Localizable.xcstrings",
    ]
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved.is_file():
            return resolved
    return None


def load_allowlist(path: Path | None) -> set[tuple[str, str]]:
    if path is None or not path.is_file():
        return set()
    entries = json.loads(path.read_text(encoding="utf-8"))
    allowed: set[tuple[str, str]] = set()
    for entry in entries:
        lang = entry.get("lang", "all")
        for one in ("de", "en") if lang == "all" else (lang,):
            allowed.add((entry["name"], one))
    return allowed


def check(res_dir: Path, xcstrings: Path, allowlist: set[tuple[str, str]]) -> tuple[list[str], dict]:
    errors: list[str] = []
    per_locale: dict[str, dict[str, str]] = {}
    untranslatable: set[str] = set()
    for lang, folder in LOCALES.items():
        strings, skip, parse_errors = parse_strings_dir(res_dir, folder)
        per_locale[lang] = strings
        untranslatable |= skip
        errors += parse_errors

    spanish = per_locale["es"]
    for name in sorted(spanish):
        if name in untranslatable:
            continue
        for lang in ("de", "en"):
            if name not in per_locale[lang]:
                errors.append(f"falta la traducción {lang} de '{name}'")
    for lang in ("de", "en"):
        for name in sorted(per_locale[lang]):
            if name not in spanish:
                errors.append(f"'{name}' está en {lang} pero no en español (la fuente)")

    catalog = load_catalog(xcstrings)
    stats = {"corresponding": 0, "checked": 0, "skipped": [], "allowed": 0}
    for name, es_text in sorted(spanish.items()):
        if name in untranslatable:
            continue
        row = catalog.get(normalize_format(es_text))
        if row is None:
            stats["skipped"].append(name)
            continue
        stats["corresponding"] += 1
        for lang in ("de", "en"):
            if name not in per_locale[lang]:
                continue  # ya denunciado arriba como traducción ausente
            expected = row.get(lang)
            if expected is None:
                errors.append(
                    f"'{name}' ({lang}): el catálogo de iOS no trae esta traducción"
                )
                continue
            actual = normalize_format(per_locale[lang][name])
            stats["checked"] += 1
            if actual != expected:
                if (name, lang) in allowlist:
                    stats["allowed"] += 1
                else:
                    errors.append(
                        f"'{name}' ({lang}) difiere del catálogo de iOS:\n"
                        f"    Android: {per_locale[lang][name]!r}\n"
                        f"    iOS:     {expected!r} (normalizado; clave es: {es_text!r})"
                    )
    return errors, stats


def main(argv: list[str] | None = None) -> int:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent
    parser = argparse.ArgumentParser(
        description="Comprueba los strings de Android contra Localizable.xcstrings de iOS."
    )
    parser.add_argument("--res", default=str(repo_root / "android/app/src/main/res"),
                        help="directorio res/ de la app")
    parser.add_argument("--xcstrings", default=None,
                        help="ruta a Localizable.xcstrings (defecto: búsqueda automática)")
    parser.add_argument("--allowlist", default=str(script_dir / "strings_allowlist.json"),
                        help="divergencias deliberadas (JSON; puede no existir)")
    parser.add_argument("--verbose", action="store_true",
                        help="lista los recursos sin correspondencia en el catálogo")
    args = parser.parse_args(argv)

    xcstrings = find_xcstrings(args.xcstrings, repo_root)
    if xcstrings is None:
        print("FALLO: no se encontró Localizable.xcstrings; pasa --xcstrings "
              "o define COLORSAPP_XCSTRINGS", file=sys.stderr)
        return 2
    errors, stats = check(
        Path(args.res), xcstrings, load_allowlist(Path(args.allowlist)),
    )
    print(f"catálogo: {xcstrings}")
    print(f"recursos que corresponden a una clave de iOS: {stats['corresponding']} "
          f"(textos de/en comparados: {stats['checked']}, exentos: {stats['allowed']})")
    print(f"sin correspondencia (textos propios de Android): {len(stats['skipped'])}")
    if args.verbose:
        for name in stats["skipped"]:
            print(f"  sin correspondencia: {name}")
    if errors:
        print(f"\n{len(errors)} problema(s):", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("strings OK: traducciones completas y fieles al catálogo de iOS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
