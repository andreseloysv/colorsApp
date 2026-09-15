"""Capa 4 por variantes de recorte (``l4.variants`` dentro de ``l4.run``) y smoke test de personas
(``l4.people_smoke``), con un set dorado temporal de 6 imágenes sintéticas.

Cada imagen (256 x 256) pone a la izquierda la combinación X (la del consenso de 3 jueces) y a la
derecha otra combinación Y, con máscaras PGM ficticias en el manifest: ``largest``,
``largest-clothing`` y ``largest-clothing-skin`` cubren la mitad izquierda y ``allPeople`` la
derecha, así que cada variante tiene un resultado distinto y comprobable. La foto 5 no trae
máscaras: sin visionmask queda ``skipped`` con motivo y con el doble ``l4.fake_visionmask`` toma
sus máscaras de visionmask. Las métricas se comprueban a mano con resultados fabricados (sin CLI)
y de extremo a extremo con ``ce batch`` (si el CLI admite máscara por línea)."""

from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from l4 import fake_visionmask as fvm
from l4 import people_smoke as ps
from l4 import run as l4
from l4 import variants as l4v
from oracle import l3
from oracle.l2 import Check
from synth import wada_gen as wg

X_COMBOS = [1, 12, 150, 300, 348, 77]
Y_COMBOS = [200, 250, 40, 90, 10, 160]
MASKED = ["allPeople", "largest", "largest-clothing", "largest-clothing-skin"]


def _batch_supports_masks(cli: Path | None) -> bool:
    if cli is None:
        return False
    with tempfile.TemporaryDirectory(prefix="colorsapp-probe-") as tmp:
        t = Path(tmp)
        (t / "a b.ppm").write_bytes(b"P6\n2 2\n255\n" + bytes([128] * 12))
        (t / "m.pgm").write_bytes(b"P5\n2 2\n255\n" + bytes([255] * 4))
        (t / "list.txt").write_text(f'"{t / "a b.ppm"}" "{t / "m.pgm"}"\n', encoding="utf-8")
        proc = subprocess.run([str(cli), "batch", str(t / "list.txt"), "--json"], capture_output=True, text=True, check=False)
    try:
        row = json.loads(proc.stdout.splitlines()[0])
    except (IndexError, json.JSONDecodeError):
        return False
    return row.get("mask", "").endswith("m.pgm") and isinstance(row.get("hits"), list)


CLI = l3.find_cli_optional()
CLI_MASK_LINES = _batch_supports_masks(CLI)
needs_cli = pytest.mark.skipif(not CLI_MASK_LINES, reason=f"ce batch sin máscara por línea: {CLI}")


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _pgm(path: Path, mask: np.ndarray) -> None:
    h, w = mask.shape
    path.write_bytes(f"P5\n{w} {h}\n255\n".encode("ascii") + mask.astype(np.uint8).tobytes())


def _split_image(x: int, y: int) -> np.ndarray:
    a, _ = wg.variant(x, 0)
    b, _ = wg.variant(y, 0)
    left = np.asarray(Image.fromarray(a).resize((128, 256), Image.Resampling.NEAREST))
    right = np.asarray(Image.fromarray(b).resize((128, 256), Image.Resampling.NEAREST))
    return np.concatenate([left, right], axis=1)


@pytest.fixture
def golden(tmp_path: Path) -> Path:
    gdir = tmp_path / "golden"
    gdir.mkdir()
    left = np.zeros((256, 256), dtype=np.uint8)
    left[:, :128] = 255
    right = 255 - left
    entries = []
    for i, (x, y) in enumerate(zip(X_COMBOS, Y_COMBOS)):
        name = f"photo{i}.png"
        Image.fromarray(_split_image(x, y)).save(gdir / name)
        entry = {"file": name, "sha256": _sha(gdir / name), "tags": (["grupo", "denim"] if i < 2 else ["negro"]),
                 "labels": {"ana": x, "bea": x, "carl": x if i % 2 else None}}
        if i < 5:
            masks = {}
            for variant in MASKED:
                rel = f"photo{i}.{variant}.pgm"
                _pgm(gdir / rel, right if variant == "allPeople" else left)
                masks[variant] = rel
            entry["masks"] = masks
        entries.append(entry)
    (gdir / "manifest.json").write_text(json.dumps({"photos": entries}, indent=1), encoding="utf-8")
    return gdir


def _choice(status: str, *, detected: bool | None = None, steps: list[str] | None = None, mask: bool = True) -> l4v.MaskChoice:
    return l4v.MaskChoice("v", status, source="visionmask" if status != "skipped" else None,
                          mask=Path("m.pgm") if mask and status == "ok" else None, detected=detected, steps=steps or [])


def _hits(*ids: int, ambiguous: int = 0) -> dict:
    return {"hits": [{"id": i, "score": float(k)} for k, i in enumerate(ids)], "ambiguous": ambiguous}


# --------------------------------------------------------------------------------------
# Sin CLI: métricas a mano, resolución de máscaras, gate, propuesta
# --------------------------------------------------------------------------------------


def test_metrics_by_hand():
    truth = [1, 2, 3, 4]
    tags = [["grupo"], ["grupo", "negro"], ["negro"], []]
    none = [_hits(1, 5, 6), _hits(7, 2, 8, ambiguous=1), _hits(9, 10, 11), _hits(4, 12, 13)]
    official = [_hits(1, 20, 21), _hits(2, 22, 23, ambiguous=1), _hits(3, 24, 25), _hits(5, 5, 5)]
    largest = [_hits(9, 9, 1), {"error": "máscara rota"}, _hits(3, 1, 1), {"skipped": "x"}]
    choices = {
        "none": [l4v.MaskChoice("none", "ok", source="none")] * 4,
        "largest-clothing-skin": [_choice("ok", detected=True, steps=["poseRegions", "skinExcluded"]),
                                  _choice("ok", detected=True, steps=["headCut"]),
                                  _choice("ok", detected=False, steps=["noPeople", "none"], mask=False),
                                  _choice("ok", detected=True, steps=["poseRegions", "wholePerson"])],
        "largest": [_choice("ok", detected=True), _choice("error"), _choice("ok", detected=True), _choice("skipped")],
    }
    choices["largest"][3].reason = "sin máscara en el manifest y sin visionmask"
    s = l4v.compute_variant_metrics(["none", "largest", "largest-clothing-skin"], truth, tags, choices,
                                    {"none": none, "largest-clothing-skin": official, "largest": largest})
    n = s["variants"]["none"]["aggregate"]
    assert (n["n"], n["recall_at_1"], n["recall_at_3"], n["ambiguous_rate"]) == (4, 0.5, 0.75, 0.25)
    o = s["variants"]["largest-clothing-skin"]
    a = o["aggregate"]
    assert o["official"] and o["status"] == "ok"
    assert (a["n"], a["recall_at_1"], a["recall_at_3"]) == (4, 0.75, 0.75)
    assert a["delta_recall_at_1_points"] == pytest.approx(25.0) and a["delta_recall_at_3_points"] == pytest.approx(0.0)
    assert a["max_class_share"] == 0.25 and a["ambiguous_rate"] == 0.25
    assert a["person_detected_rate"] == 0.75 and a["mask_rate"] == 0.75
    assert a["top_steps"][0] == ["poseRegions", 2]
    # largest: la foto 3 queda skipped (fuera de n), la 1 es error (cuenta y falla).
    lg = s["variants"]["largest"]
    assert lg["status"] == "partial" and lg["n_skipped"] == 1 and lg["skip_reasons"][0][1] == 1
    b = lg["aggregate"]
    assert b["n"] == 3 and b["errors"] == 1
    assert b["recall_at_1"] == pytest.approx(1 / 3) and b["recall_at_3"] == pytest.approx(2 / 3)
    # none pareado sobre las fotos 0, 1, 2: @3 = 2/3 -> delta 0.
    assert b["none_recall_at_3"] == pytest.approx(2 / 3) and b["delta_recall_at_3_points"] == pytest.approx(0.0)
    # Por tag (grupo = fotos 0 y 1).
    g = o["by_tag"]["grupo"]
    assert g["n"] == 2 and g["recall_at_1"] == 1.0 and g["none_recall_at_1"] == 0.5 and g["delta_recall_at_1_points"] == pytest.approx(50.0)
    assert s["variants"]["largest"]["by_tag"]["grupo"]["n"] == 2 and "grupo" in s["tags"]
    md = l4v.render_markdown(s)
    assert "**largest-clothing-skin (oficial)**" in md and "| grupo |" in md and "+25.0" in md


def test_gate_check_proposed_and_promoted():
    truth = [1, 2]
    ch = {"none": [l4v.MaskChoice("none", "ok", source="none")] * 2,
          l4v.OFFICIAL_VARIANT: [_choice("ok", detected=True), _choice("ok", detected=True)]}
    res = {"none": [_hits(1, 2, 3), _hits(2, 3, 4)], l4v.OFFICIAL_VARIANT: [_hits(1, 7, 8), _hits(9, 8, 7)]}
    s = l4v.compute_variant_metrics(["none", l4v.OFFICIAL_VARIANT], truth, [[], []], ch, res)
    assert s["variants"][l4v.OFFICIAL_VARIANT]["aggregate"]["delta_recall_at_3_points"] == pytest.approx(-50.0)
    proposed = l4v.gate_check(s, {"L4": {}})
    assert proposed.status == "info" and "no promovido" in proposed.name and "NO cumpliría" in proposed.detail
    promoted = l4v.gate_check(s, {"L4_variants": {l4v.GATE_KEY: -3.0}})
    assert promoted.status == "fail" and promoted.threshold == -3.0
    ok = l4v.gate_check(s, {"L4_variants": {l4v.GATE_KEY: -60.0}})
    assert ok.status == "pass"
    skipped = l4v.compute_variant_metrics(["none", l4v.OFFICIAL_VARIANT], truth, [[], []],
                                          {"none": ch["none"], l4v.OFFICIAL_VARIANT: [l4v.MaskChoice("v", "skipped", reason="sin visionmask")] * 2},
                                          {"none": res["none"], l4v.OFFICIAL_VARIANT: [{}, {}]})
    g = l4v.gate_check(skipped, None)
    assert g.status == "skipped" and "sin visionmask" in g.detail


def test_write_proposal_merges(tmp_path: Path):
    (tmp_path / "thresholds.proposed.json").write_text(json.dumps({"schema": 1, "L3": {"x": 1}}), encoding="utf-8")
    path = l4v.write_proposal(tmp_path)
    doc = json.loads(path.read_text(encoding="utf-8"))
    assert doc["L3"] == {"x": 1}
    assert doc["L4_variants"][l4v.GATE_KEY] == -3.0 and doc["L4_variants"]["promoted_by"] is None
    assert doc["L4_variants"]["official_variant"] == "largest-clothing-skin"


def test_resolve_masks_sources(golden: Path, tmp_path: Path):
    entries = l4.load_manifest(golden)
    # (a) manifest
    ch, doc = l4v.resolve_masks(golden, entries[0], list(l4v.VARIANTS), None, tmp_path / "w0", image_size=(256, 256))
    assert doc is None and ch["none"].source == "none" and ch["none"].mask is None
    for v in MASKED:
        assert ch[v].status == "ok" and ch[v].source == "manifest" and ch[v].mask == golden / f"photo0.{v}.pgm"
        assert ch[v].detected is True and ch[v].coverage == pytest.approx(0.5)
    # (c) sin máscaras ni visionmask
    ch, _ = l4v.resolve_masks(golden, entries[5], list(l4v.VARIANTS), None, tmp_path / "w5", image_size=(256, 256),
                              no_visionmask_reason="no existe build-subject/visionmask")
    assert all(ch[v].status == "skipped" and "visionmask" in ch[v].reason for v in MASKED)
    # máscara del manifest con otras dimensiones -> error
    _pgm(golden / "small.pgm", np.full((10, 10), 255, dtype=np.uint8))
    bad = dict(entries[0], masks={"largest": "small.pgm", "allPeople": "../fuera.pgm"})
    ch, _ = l4v.resolve_masks(golden, bad, ["none", "largest", "allPeople"], None, tmp_path / "wb", image_size=(256, 256))
    assert ch["largest"].status == "error" and "10x10" in ch["largest"].reason
    assert ch["allPeople"].status == "error" and "relativo" in ch["allPeople"].reason
    # (b) visionmask (doble de pruebas): la foto 5 no trae máscaras.
    vm = fvm.write_executable(tmp_path / "visionmask")
    ch, doc = l4v.resolve_masks(golden, entries[5], list(l4v.VARIANTS), vm, tmp_path / "wv", image_size=(256, 256))
    assert doc is not None and doc["people_count"] == 2
    for v in MASKED:
        assert ch[v].status == "ok" and ch[v].source == "visionmask"
        assert ch[v].mask is not None and ch[v].mask.resolve() == (tmp_path / "wv" / f"photo5.{v}.pgm").resolve()
        assert ch[v].detected is True
    assert ch["largest-clothing-skin"].steps == ["poseRegions", "skinExcluded"]
    # manifest parcial: las variantes declaradas vienen del manifest y el resto de visionmask.
    partial = dict(entries[0], masks={"largest": entries[0]["masks"]["largest"]})
    ch, doc = l4v.resolve_masks(golden, partial, list(l4v.VARIANTS), vm, tmp_path / "wp", image_size=(256, 256))
    assert ch["largest"].source == "manifest" and ch["allPeople"].source == "visionmask"
    assert [v["name"] for v in doc["variants"]] == ["allPeople", "largest-clothing", "largest-clothing-skin"]
    # sin personas: la variante se analiza sin máscara, como la app.
    Image.fromarray(np.zeros((64, 64, 3), dtype=np.uint8)).save(golden / "nopeople.png")
    ch, _ = l4v.resolve_masks(golden, {"file": "nopeople.png"}, ["none", "largest"], vm, tmp_path / "wn", image_size=(64, 64))
    assert ch["largest"].status == "ok" and ch["largest"].mask is None and ch["largest"].detected is False
    assert ch["largest"].steps == ["noPeople", "none"]


def test_skipped_layer_reports_variants(monkeypatch, tmp_path: Path):
    monkeypatch.delenv(l4.GOLDEN_DIR_ENV, raising=False)
    status, checks, detail = l4.run_layer4(CLI, l3.load_thresholds(), tmp_path)
    assert status == "skipped" and detail["variants"]["status"] == "skipped"
    assert json.loads((tmp_path / "thresholds.proposed.json").read_text(encoding="utf-8"))["L4_variants"]["variants"] == list(l4v.VARIANTS)


# --------------------------------------------------------------------------------------
# Extremo a extremo con ce batch
# --------------------------------------------------------------------------------------


def _by_name(checks: list[Check]) -> dict[str, Check]:
    return {c.name: c for c in checks}


@needs_cli
def test_each_variant_uses_its_manifest_masks(golden: Path, tmp_path: Path):
    status, checks, detail = l4.run_layer4(CLI, l3.load_thresholds(), tmp_path / "out", golden_dir=golden,
                                           log=lambda *_: None, visionmask=None)
    names = _by_name(checks)
    assert names["variantes: ce batch con máscara por línea (contrato y máscara usada)"].status == "pass"
    v = detail["variants"]["variants"]
    per_photo = detail["variants_per_photo"]
    assert len(per_photo) == 6 and detail["n_scored"] == 6
    # Cada variante usó exactamente la máscara de su manifest (ce batch devuelve la ruta en "mask").
    batch_rows = {}
    for i, p in enumerate(per_photo[:5]):
        for variant in MASKED:
            cell = p["variants"][variant]
            assert cell["source"] == "manifest" and cell["mask"] == str(golden / f"photo{i}.{variant}.pgm")
            batch_rows[(i, variant)] = cell["top"]
        assert p["variants"]["none"]["mask"] is None
    # La foto 5 (sin máscaras, sin visionmask) queda skipped con motivo en las variantes con máscara.
    for variant in MASKED:
        cell = per_photo[5]["variants"][variant]
        assert cell["status"] == "skipped" and "visionmask desactivado" in cell["reason"]
        assert v[variant]["status"] == "partial" and v[variant]["n_skipped"] == 1
    # Mitad izquierda = combinación del consenso: top-1 correcto; mitad derecha (allPeople): nunca en el top-3.
    for i in range(5):
        assert batch_rows[(i, "largest-clothing-skin")][0] == X_COMBOS[i]
        assert X_COMBOS[i] not in batch_rows[(i, "allPeople")]
    off = v["largest-clothing-skin"]["aggregate"]
    ap = v["allPeople"]["aggregate"]
    none5 = l3.metrics_for(X_COMBOS[:5], [{"hits": [{"id": t} for t in p["variants"]["none"]["top"]]} for p in per_photo[:5]])
    assert off["n"] == 5 and off["recall_at_1"] == 1.0 and off["recall_at_3"] == 1.0
    assert ap["recall_at_1"] == 0.0 and ap["recall_at_3"] == 0.0
    assert off["none_recall_at_1"] == none5["recall_at_1"] and off["none_recall_at_3"] == none5["recall_at_3"]
    assert off["delta_recall_at_1_points"] == pytest.approx(100 * (1.0 - none5["recall_at_1"]))
    assert ap["delta_recall_at_3_points"] == pytest.approx(-100 * none5["recall_at_3"])
    assert off["person_detected_rate"] == 1.0 and off["sources"] == {"manifest": 5}
    # none usa las 6 fotos y coincide con las métricas base de la capa.
    assert v["none"]["aggregate"]["n"] == 6
    assert v["none"]["aggregate"]["recall_at_1"] == detail["aggregate"]["recall_at_1"]
    assert v["none"]["aggregate"]["recall_at_3"] == detail["aggregate"]["recall_at_3"]
    # Por tag, grupo incluido.
    assert v["largest-clothing-skin"]["by_tag"]["grupo"]["n"] == 2 and v["largest-clothing-skin"]["by_tag"]["grupo"]["recall_at_1"] == 1.0
    gate = [c for c in checks if c.name.startswith("variantes: largest-clothing-skin recall@3")][0]
    assert gate.status == "info" and "cumpliría" in gate.detail
    md = detail["variants_markdown"]
    assert "**largest-clothing-skin (oficial)**" in md and "Δ@3" in md
    saved = json.loads((tmp_path / "out" / "l4_detail.json").read_text(encoding="utf-8"))
    assert saved["variants"]["official"] == "largest-clothing-skin" and "variants_per_photo" in saved
    assert json.loads((tmp_path / "out" / "thresholds.proposed.json").read_text(encoding="utf-8"))["L4_variants"]


@needs_cli
def test_visionmask_fallback_and_no_sources(golden: Path, tmp_path: Path):
    vm = fvm.write_executable(tmp_path / "visionmask")
    _status, checks, detail = l4.run_layer4(CLI, l3.load_thresholds(), tmp_path / "out", golden_dir=golden,
                                            log=lambda *_: None, visionmask=vm)
    per_photo = detail["variants_per_photo"]
    for variant in MASKED:
        cell = per_photo[5]["variants"][variant]
        assert cell["status"] == "ok" and cell["source"] == "visionmask"
        assert cell["mask"].endswith(f"photo5.{variant}.pgm") and "/variants/visionmask/p005/" in cell["mask"]
        assert per_photo[0]["variants"][variant]["source"] == "manifest"
        agg = detail["variants"]["variants"][variant]
        assert agg["status"] == "ok" and agg["aggregate"]["n"] == 6 and agg["aggregate"]["sources"] == {"manifest": 5, "visionmask": 1}
    assert _by_name(checks)["variantes: ce batch con máscara por línea (contrato y máscara usada)"].status == "pass"

    # Sin máscaras en el manifest ni visionmask: todas las variantes con máscara quedan skipped con motivo.
    manifest = json.loads((golden / "manifest.json").read_text(encoding="utf-8"))
    for e in manifest["photos"]:
        e.pop("masks", None)
    (golden / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    _status, checks, detail = l4.run_layer4(CLI, l3.load_thresholds(), tmp_path / "out2", golden_dir=golden,
                                            log=lambda *_: None, visionmask=str(tmp_path / "no-existe"))
    v = detail["variants"]["variants"]
    assert v["none"]["status"] == "ok"
    for variant in MASKED:
        assert v[variant]["status"] == "skipped" and v[variant]["n_skipped"] == 6
        assert "visionmask" in v[variant]["skip_reasons"][0][0] and "no-existe" in v[variant]["skip_reasons"][0][0]
        c = _by_name(checks)[f"variante {variant}{' (oficial)' if variant == l4v.OFFICIAL_VARIANT else ''}: recall@3"]
        assert c.status == "skipped" and "visionmask" in c.detail
    gate = [c for c in checks if c.name.startswith("variantes: largest-clothing-skin recall@3")][0]
    assert gate.status == "skipped"


@needs_cli
def test_people_smoke_with_fake_visionmask(tmp_path: Path):
    people = tmp_path / "people"
    people.mkdir()
    img = _split_image(1, 200)
    Image.fromarray(img).save(people / "a_pair.png")
    Image.fromarray(img).save(people / "b_nopeople.png")
    left_hex = "#%02x%02x%02x" % tuple(int(c) for c in img[128, 40])
    (people / "expected.json").write_text(json.dumps([
        {"file": "a_pair.png", "people": 2, "largest_person": {"garments": [{"part": "torso", "color_hex": left_hex}]}},
        {"file": "b_nopeople.png", "people": 0, "largest_person": {"garments": []}}]), encoding="utf-8")
    vm = fvm.write_executable(tmp_path / "visionmask")
    code, doc = ps.run_smoke(CLI, people, tmp_path / "out", visionmask=vm, log=lambda *_: None)
    assert code == 0
    agg = doc["aggregate"]
    assert list(agg) == list(l4v.VARIANTS)
    assert agg["none"]["n"] == 2 and agg["largest-clothing-skin"]["n"] == 2
    assert agg["largest"]["person_detected"] == 1 and agg["largest"]["with_mask"] == 1
    a = doc["photos"][0]["variants"]
    assert a["largest"]["de_dominant"] is not None and a["largest"]["garment_weight"] >= 0.0
    assert doc["photos"][1]["variants"]["largest"]["mask"] is None and doc["photos"][1]["variants"]["largest"]["de_dominant"] is None
    assert agg["largest"]["de_dominant_median"] == pytest.approx(a["largest"]["de_dominant"])
    md = (tmp_path / "out" / "l4_people_smoke.md").read_text(encoding="utf-8")
    assert "único número disponible hoy" in md and "**largest-clothing-skin (oficial)**" in md
    # Sin visionmask: none se calcula y las variantes con máscara quedan skipped.
    code, doc = ps.run_smoke(CLI, people, tmp_path / "out3", visionmask=None, log=lambda *_: None)
    assert code == 0 and doc["aggregate"]["none"]["n"] == 2
    assert doc["aggregate"]["largest"]["n"] == 0 and doc["aggregate"]["largest"]["skipped"] == 2
