"""Tests de ``oracle.names`` (curación de nombres): todo, HTML autocontenido y bien formado."""

from __future__ import annotations

import json
import subprocess
import sys

from oracle import build_dictionary as bd
from oracle import names as nm


def test_compress_ranges():
    assert nm.compress_ranges([]) == ""
    assert nm.compress_ranges([5]) == "5"
    assert nm.compress_ranges([1, 2, 3, 7, 9, 10]) == "1-3, 7, 9-10"


def test_pending_ids_uses_status_or_empty_name():
    names = [
        {"id": 1, "name": "", "lang": "es", "status": "pending", "notes": ""},
        {"id": 2, "name": "Otoño", "lang": "es", "status": "done", "notes": ""},
        {"id": 3, "name": "", "lang": "es", "status": "done", "notes": ""},  # sin nombre => pendiente
        {"id": 4, "name": "Winter", "lang": "de", "status": "pending", "notes": ""},  # status manda
    ]
    assert nm.pending_ids(names) == [1, 3, 4]


def test_html_is_self_contained_and_well_formed(tmp_path):
    dictionary = nm.load_json(nm.DEFAULT_DICTIONARY)
    names = nm.load_json(nm.DEFAULT_NAMES)
    html = nm.build_html(dictionary, names, "2026-09-14")
    assert nm.check_html(html) == []
    assert html.startswith("<!DOCTYPE html>")
    assert 'lang="es"' in html
    assert "español o en alemán" in html
    assert dictionary["dict_version"] in html
    assert "Hermosa Pink" in html and "#f9c1ce" in html
    assert "fetch(" not in html and "<script src" not in html and "<link" not in html
    assert "data:application/json" in html
    assert 40_000 < len(html.encode("utf-8")) < 1_000_000


def test_embed_json_escapes_script_terminator():
    assert "</" not in nm.embed_json({"x": "</script><b>"})
    assert nm.embed_json({"x": "</script>"}) == '{"x":"<\\/script>"}'


def test_check_html_detects_problems():
    assert any("sin cerrar" in p for p in nm.check_html("<!DOCTYPE html><html><body><div></body></html>"))
    assert any("DOCTYPE" in p for p in nm.check_html("<html></html>"))


def test_cli_html_and_todo(tmp_path):
    out = tmp_path / "names.html"
    html = subprocess.run(
        [sys.executable, "-m", "oracle.names", "html", "--out", str(out)],
        cwd=bd.REPO_ROOT, capture_output=True, text=True, check=False,
    )
    assert html.returncode == 0, html.stderr
    assert out.is_file() and out.stat().st_size > 40_000
    assert nm.check_html(out.read_text(encoding="utf-8")) == []

    todo = subprocess.run(
        [sys.executable, "-m", "oracle.names", "todo"],
        cwd=bd.REPO_ROOT, capture_output=True, text=True, check=False,
    )
    assert todo.returncode == 0, todo.stderr
    names = json.loads(nm.DEFAULT_NAMES.read_text(encoding="utf-8"))
    expected = len(nm.pending_ids(names))
    assert f"{expected} de 348 combinaciones pendientes" in todo.stdout
    assert "ids pendientes:" in todo.stdout
