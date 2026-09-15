"""Goldens del harness (``oracle.golden``): fixtures deterministas, update con motivo obligatorio
y check a 1e-9 con mismo top-3. El update/check real necesita ``ce palette`` y ``ce match``."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from oracle import golden, l2, l3
from synth import wada_gen as wg

CLI = l3.find_cli_optional()
CLI_HAS_MATCH = l3.has_match(CLI)
needs_cli = pytest.mark.skipif(not CLI_HAS_MATCH, reason=f"sin 'ce match': {l3.not_implemented_reason(CLI)}")


def test_fixture_specs_are_fixed():
    specs = golden.fixture_specs()
    assert len(specs) == 50 and len({c for c, _ in specs}) == 50
    assert all(v in wg.DEV_VARIANTS for _, v in specs) and specs == golden.fixture_specs()


def test_write_fixtures_deterministic(tmp_path: Path):
    a = golden.write_fixtures(tmp_path / "a", golden.fixture_specs()[:5])
    b = golden.write_fixtures(tmp_path / "b", golden.fixture_specs()[:5])
    assert [x["sha256"] for x in a] == [x["sha256"] for x in b]
    assert (tmp_path / "a" / a[0]["file"]).stat().st_size == golden.FIXTURE_SIZE * golden.FIXTURE_SIZE * 3 + len(f"P6\n{golden.FIXTURE_SIZE} {golden.FIXTURE_SIZE}\n255\n")


def test_update_requires_reason(tmp_path: Path):
    with pytest.raises(ValueError):
        golden.update(CLI or Path("ce"), "   ", golden_dir=tmp_path, changelog=tmp_path / "CHANGELOG.md")


def test_check_without_goldens(tmp_path: Path):
    ok, summary, detail = golden.check(CLI, golden_dir=tmp_path)
    assert not ok and "sin goldens" in summary and detail["mismatches"] == 2


@needs_cli
def test_repo_goldens_match_current_engine():
    ok, summary, detail = golden.check(CLI)
    assert ok, summary
    assert detail["palettes"]["n"] == 20 and detail["matches"]["n"] == 50


@needs_cli
def test_update_and_check_roundtrip_and_regression_detection(tmp_path: Path):
    gdir = tmp_path / "golden"
    log = tmp_path / "CHANGELOG.md"
    summary = golden.update(CLI, "test: golden temporal", golden_dir=gdir, changelog=log, log=lambda *_: None)
    assert summary["palettes"] == 20 and summary["matches"] == 50 and summary["fixtures"] == 50
    assert "golden-update: test: golden temporal" in log.read_text(encoding="utf-8")
    ok, text, detail = golden.check(CLI, golden_dir=gdir)
    assert ok, text
    # Regresión simulada: un score cambia 1e-6 y el top-3 de otra entrada se altera.
    doc = json.loads((gdir / golden.MATCHES_NAME).read_text(encoding="utf-8"))
    doc["entries"][0]["hits"][0]["score"] += 1e-6
    doc["entries"][1]["hits"][0], doc["entries"][1]["hits"][1] = doc["entries"][1]["hits"][1], doc["entries"][1]["hits"][0]
    (gdir / golden.MATCHES_NAME).write_text(json.dumps(doc), encoding="utf-8")
    ok, text, detail = golden.check(CLI, golden_dir=gdir)
    assert not ok and detail["matches"]["mismatches"] == 2 and "Δscore" in text and "top-3" in text
    # Fixture alterada: sha256 distinto.
    fx = gdir / golden.FIXTURES_NAME / doc["entries"][2]["file"]
    fx.write_bytes(fx.read_bytes()[:-3] + b"\x00\x00\x00")
    ok, text, detail = golden.check(CLI, golden_dir=gdir)
    assert not ok and "sha256" in text
