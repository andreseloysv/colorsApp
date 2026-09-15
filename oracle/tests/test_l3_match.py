"""Capa 3 como pytest: ``ce match``/``ce batch`` sobre sintéticos de ``wada_gen`` (versión reducida
de ``oracle.l3``; ``make eval`` ejecuta las 3480 imágenes dev y ``make eval-fast`` 350).

Los tests que necesitan el CLI se saltan si ``build/tools/ce`` (o ``$COLORSAPP_CE_CLI``) no
tiene el subcomando ``match``; los de métricas y contrato corren siempre.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

from oracle import l3
from oracle import metrics as mt
from synth import compose as sc
from synth import wada_gen as wg

CLI = l3.find_cli_optional()
CLI_HAS_MATCH = l3.has_match(CLI)
needs_cli = pytest.mark.skipif(not CLI_HAS_MATCH, reason=f"sin 'ce match': {l3.not_implemented_reason(CLI)}")
TH, _DEFAULTED = l3.resolve_thresholds(l3.load_thresholds())


# ---- sin CLI: métricas, contrato, modo rápido ---------------------------------------------------


def _fake_result(ids: list[int], scores: list[float] | None = None, ambiguous: int | None = None) -> dict:
    scores = scores or [float(i) for i in range(len(ids))]
    hits = [{"id": i, "score": s, "size": 2, "colors": [0, 1]} for i, s in zip(ids, scores)]
    amb = ambiguous if ambiguous is not None else (1 if len(scores) > 1 and scores[1] - scores[0] < 1.0 else 0)
    return {"engine": "0.1.0", "dict_version": "f" * 12, "file": "x.ppm", "width": 2, "height": 2, "reduced_width": 2,
            "reduced_height": 2, "opts": {"palette": {}, "match": dict(l3.ENGINE_DEFAULT_MATCH_OPTS)},
            "swatches": [{"lab": [50, 0, 0], "weight": 1.0, "rgb": [119, 119, 119], "hex": "#777777"}],
            "hits": hits, "ambiguous": amb, "hash": "0" * 16}


def test_metrics_for_and_evaluate():
    rows = [{"combo_id": 1, "degradation": "clean"}, {"combo_id": 2, "degradation": "clean"},
            {"combo_id": 3, "degradation": "jpeg_q10"}, {"combo_id": 4, "degradation": "jpeg_q10"}]
    results = [_fake_result([1, 5, 6]), _fake_result([7, 2, 6], [0.0, 0.5, 2.0]), _fake_result([3]), {"file": "x", "error": "ilegible"}]
    ev = l3.evaluate(rows, results)
    assert list(ev["by_group"]) == ["clean", "jpeg_q10"]
    c = ev["by_group"]["clean"]
    assert c["n"] == 2 and c["recall_at_1"] == 0.5 and c["recall_at_3"] == 1.0 and c["ambiguous_rate"] == 0.5
    j = ev["by_group"]["jpeg_q10"]
    assert j["recall_at_1"] == 0.5 and j["errors"] == 1
    a = ev["aggregate"]
    assert a["n"] == 4 and a["recall_at_1"] == 0.5 and a["recall_at_3"] == 0.75 and a["errors"] == 1
    assert a["max_class_share"] == pytest.approx(1 / 3) and 0.0 < a["entropy_norm"] < 1.0
    assert ev["top_confusions"][0] == {"truth": 2, "pred": 7, "n": 1}


def test_validate_match_result_contract():
    assert l3.validate_match_result(_fake_result([1, 2, 3])) == []
    bad = _fake_result([1, 2, 3], [2.0, 1.0, 3.0])
    assert any("orden" in p for p in l3.validate_match_result(bad))
    tie = _fake_result([2, 1, 3], [1.0, 1.0, 3.0])
    assert any("orden" in p for p in l3.validate_match_result(tie))
    wrong_amb = _fake_result([1, 2], [0.0, 5.0], ambiguous=1)
    assert any("ambiguous" in p for p in l3.validate_match_result(wrong_amb))
    assert l3.validate_match_result({"file": "x", "error": "boom"}) == ["error del CLI: boom"]
    assert l3.ranked_ids({"file": "x", "error": "boom"}) == []
    missing = _fake_result([1])
    del missing["hash"]
    assert l3.validate_match_result(missing) == ["falta la clave 'hash'"]


def test_fast_combo_ids_are_fixed():
    ids = l3.fast_combo_ids()
    assert len(ids) == 35 and len(set(ids)) == 35 and ids == sorted(ids)
    assert ids == l3.fast_combo_ids() and all(1 <= i <= 348 for i in ids)


def test_match_args_formatting():
    args = l3.match_args(palette_opts={"skin_rule": 1, "center_sigma": 0.2}, match_opts={"kL": 2.0, "coverage_lambda": 0.5}, top=5)
    assert args == ["--skin-rule", "1", "--center-sigma", "0.2", "--kL", "2.0", "--coverage-lambda", "0.5", "--top", "5", "--json"]


def test_resolve_thresholds_reads_l3_section():
    th, defaulted = l3.resolve_thresholds({"L3": {"max_class_share_max": 0.1, "by_degradation": {"clean": {"recall_at_1_min": 0.9}}}})
    assert th["max_class_share_max"] == 0.1 and th["by_degradation"] == {"clean": {"recall_at_1_min": 0.9}}
    assert "variants_per_combo" in defaulted and "max_class_share_max" not in defaulted


# ---- con CLI ----------------------------------------------------------------------------------


@pytest.fixture(scope="module")
def sample_set(tmp_path_factory) -> tuple[Path, list[dict]]:
    out = tmp_path_factory.mktemp("l3set")
    manifest = wg.generate_set(out, wg.DEV_VARIANTS, [1, 12, 150, 300, 348])
    _meta, rows = wg.read_manifest(manifest)
    return out, rows


@needs_cli
@pytest.mark.parametrize("combo_id", [1, 12, 150, 300, 348])
def test_clean_variant_matches_its_combo(tmp_path: Path, combo_id: int):
    img, _meta = wg.variant(combo_id, 0)
    r = l3.run_match(CLI, sc.write_ppm(img, tmp_path / "c.ppm"))
    assert l3.validate_match_result(r) == []
    assert r["hits"][0]["id"] == combo_id, r["hits"]
    assert r["dict_version"] == wg.dict_version()
    assert {k: float(r["opts"]["match"][k]) for k in l3.ENGINE_DEFAULT_MATCH_OPTS} == l3.ENGINE_DEFAULT_MATCH_OPTS


@needs_cli
def test_analyze_is_alias_of_match(tmp_path: Path):
    img, _ = wg.variant(12, 3)
    p = sc.write_ppm(img, tmp_path / "c.ppm")
    a = l3.run_match(CLI, p, subcommand="match")
    b = l3.run_match(CLI, p, subcommand="analyze")
    assert a["_stdout"] == b["_stdout"]


@needs_cli
def test_batch_equals_match_and_is_deterministic(sample_set):
    out, rows = sample_set
    files = [out / r["file"] for r in rows[:12]]
    use_batch = l3.has_batch(CLI)
    assert use_batch, "el contrato exige 'ce batch'"
    batch = l3.run_batch(CLI, files, use_batch=True)
    again = l3.run_batch(CLI, files, use_batch=True)
    assert [b["_line"] for b in batch] == [a["_line"] for a in again]
    for f, b in zip(files, batch):
        m = l3.run_match(CLI, f)
        assert b["hits"] == m["hits"] and b["hash"] == m["hash"] and b["swatches"] == m["swatches"]
        assert Path(b["file"]).name == f.name
        assert l3.validate_match_result(b) == []


@needs_cli
def test_batch_reports_unreadable_file_and_continues(sample_set, tmp_path: Path):
    out, rows = sample_set
    bad = tmp_path / "bad.ppm"
    bad.write_bytes(b"P6\n4 4\n255\n\x00\x01")  # cuerpo truncado
    files = [out / rows[0]["file"], bad, out / rows[1]["file"]]
    res = l3.run_batch(CLI, files, use_batch=True)
    assert len(res) == 3
    assert "error" in res[1] and "hits" not in res[1]
    assert res[0]["hits"] and res[2]["hits"]


@needs_cli
def test_match_options_change_scores(sample_set):
    out, rows = sample_set
    f = out / rows[0]["file"]
    base = l3.run_match(CLI, f)
    kl2 = l3.run_match(CLI, f, match_opts={"kL": 2.0})
    assert kl2["opts"]["match"]["kL"] == 2.0 and base["opts"]["match"]["kL"] == 1.0
    top10 = l3.run_match(CLI, f, top=10)
    assert len(top10["hits"]) == 10 and top10["hits"][:3] == base["hits"]
    scores = [h["score"] for h in top10["hits"]]
    assert scores == sorted(scores)


@needs_cli
def test_recall_on_sample_set(sample_set):
    """5 combinaciones x 10 variantes: la limpia y las formas deben salir top-1; todas top-3 salvo distractor/exposición."""
    out, rows = sample_set
    res = l3.run_batch(CLI, [out / r["file"] for r in rows])
    ev = l3.evaluate(rows, res)
    assert ev["aggregate"]["errors"] == 0
    assert ev["by_group"]["clean"]["recall_at_1"] == 1.0, ev["by_group"]["clean"]
    assert ev["aggregate"]["recall_at_3"] >= 0.8, ev["by_group"]


@needs_cli
def test_run_layer3_fast_official_column(tmp_path: Path):
    checks, detail, table = l3.run_layer3(CLI, l3.load_thresholds(), tmp_path, fast=True, with_golden=False, columns=("kL1",), log=lambda *_: None)
    names = [c.name for c in checks]
    assert detail["n_images"] == 350 and detail["n_combos"] == 35
    assert any(n.startswith("clean: recall@1") for n in names)
    assert any(c.status == "skipped" and c.name.startswith("holdout") for c in checks) or wg.holdout_seed_base() is not None
    assert "| dev clean |" in table and "**dev agregado**" in table
    assert (tmp_path / "l3_detail.json").is_file() and (tmp_path / "l3_batch_kL1.jsonl").is_file()
    det = json.loads((tmp_path / "l3_detail.json").read_text())
    assert len(det["per_image"]) == 350
    # Segunda llamada: el conjunto está cacheado (no se regenera).
    checks2, detail2, _ = l3.run_layer3(CLI, l3.load_thresholds(), tmp_path, fast=True, with_golden=False, columns=("kL1",), log=lambda *_: None)
    assert detail2["generation_seconds"] == 0.0
    assert [c.status for c in checks2 if c.name.startswith("determinismo")] == ["pass"]
