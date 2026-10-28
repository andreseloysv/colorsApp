#!/usr/bin/env python3
"""Tests de check_strings.py con res/ y catálogo sintéticos en un temporal.

Ejecutar: python3 -m unittest android/tools/test_check_strings.py
(o `python3 android/tools/test_check_strings.py`).
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_strings  # noqa: E402


def write_strings(res: Path, folder: str, entries: dict[str, str]) -> None:
    directory = res / folder
    directory.mkdir(parents=True, exist_ok=True)
    body = "\n".join(
        f'    <string name="{name}">{text}</string>' for name, text in entries.items()
    )
    (directory / "strings_test.xml").write_text(
        f'<?xml version="1.0" encoding="utf-8"?>\n<resources>\n{body}\n</resources>\n',
        encoding="utf-8",
    )


def write_catalog(path: Path, strings: dict[str, dict[str, str]]) -> None:
    data = {"sourceLanguage": "es", "version": "1.0", "strings": {}}
    for key, langs in strings.items():
        data["strings"][key] = {
            "localizations": {
                lang: {"stringUnit": {"state": "translated", "value": value}}
                for lang, value in langs.items()
            }
        }
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


class NormalizeFormatTest(unittest.TestCase):
    def test_android_posicional_e_ios_secuencial_casan(self):
        self.assertEqual(
            check_strings.normalize_format("Nº %1$s y %2$d de %3$d"),
            check_strings.normalize_format("Nº %@ y %lld de %lld"),
        )
        # Reusar un argumento no es lo mismo que consumir dos.
        self.assertNotEqual(
            check_strings.normalize_format("%1$d de %1$d"),
            check_strings.normalize_format("%lld de %lld"),
        )

    def test_porcentaje_literal_y_tipos(self):
        self.assertEqual(check_strings.normalize_format("100 %%"), "100 %")
        self.assertEqual(
            check_strings.normalize_format("%1$03d"), "{INT:1}"
        )
        self.assertNotEqual(
            check_strings.normalize_format("%1$d"),
            check_strings.normalize_format("%@"),
        )


class CheckTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.res = root / "res"
        self.catalog = root / "Localizable.xcstrings"
        write_catalog(
            self.catalog,
            {
                "Parte de arriba": {"de": "Oberteil", "en": "Top"},
                "Nº %@": {"de": "Nr. %@", "en": "No. %@"},
                "Sin alemán": {"en": "No German"},
            },
        )

    def run_check(self, allowlist=frozenset()):
        return check_strings.check(self.res, self.catalog, set(allowlist))

    def test_fiel_al_catalogo_pasa(self):
        write_strings(self.res, "values", {"a": "Parte de arriba", "n": "Nº %1$s"})
        write_strings(self.res, "values-de", {"a": "Oberteil", "n": "Nr. %1$s"})
        write_strings(self.res, "values-en", {"a": "Top", "n": "No. %1$s"})
        errors, stats = self.run_check()
        self.assertEqual(errors, [])
        self.assertEqual(stats["corresponding"], 2)

    def test_texto_distinto_falla(self):
        write_strings(self.res, "values", {"a": "Parte de arriba"})
        write_strings(self.res, "values-de", {"a": "Oben"})
        write_strings(self.res, "values-en", {"a": "Top"})
        errors, _ = self.run_check()
        self.assertEqual(len(errors), 1)
        self.assertIn("'a' (de)", errors[0])

    def test_falta_traduccion_falla(self):
        write_strings(self.res, "values", {"a": "Parte de arriba"})
        write_strings(self.res, "values-de", {"a": "Oberteil"})
        write_strings(self.res, "values-en", {})
        errors, _ = self.run_check()
        self.assertTrue(any("falta la traducción en" in e for e in errors))

    def test_catalogo_sin_esa_traduccion_falla(self):
        write_strings(self.res, "values", {"a": "Sin alemán"})
        write_strings(self.res, "values-de", {"a": "irgendwas"})
        write_strings(self.res, "values-en", {"a": "No German"})
        errors, _ = self.run_check()
        self.assertTrue(any("no trae esta traducción" in e for e in errors))

    def test_allowlist_exime_la_divergencia_no_la_ausencia(self):
        write_strings(self.res, "values", {"a": "Parte de arriba"})
        write_strings(self.res, "values-de", {"a": "Oben"})
        write_strings(self.res, "values-en", {"a": "Top"})
        errors, stats = self.run_check({("a", "de")})
        self.assertEqual(errors, [])
        self.assertEqual(stats["allowed"], 1)

    def test_texto_propio_solo_exige_traduccion(self):
        write_strings(self.res, "values", {"nuevo": "Solo de Android"})
        write_strings(self.res, "values-de", {"nuevo": "Nur Android"})
        write_strings(self.res, "values-en", {"nuevo": "Android only"})
        errors, stats = self.run_check()
        self.assertEqual(errors, [])
        self.assertEqual(stats["skipped"], ["nuevo"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
