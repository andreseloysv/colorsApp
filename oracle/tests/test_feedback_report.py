"""Tests de ``oracle/tools/feedback_report.py`` con zips sintéticos que reproducen el formato de
``ios/ColorsApp/Support/Diagnostics.swift`` (README.txt, feedback.csv, scans.csv, times.txt,
images/<scan_id>.png) y su ampliación con extracción de sujeto (columnas subject_mode,
region_mode, adaptive_skin, people_count, person_index; images/<scan_id>.<variante>.pgm y
images/<scan_id>.json). Los números esperados están calculados a mano en los comentarios."""

from __future__ import annotations

import io
import json
import zipfile
from pathlib import Path

import pytest
from PIL import Image

from tools import feedback_report as fr


def _png(color: tuple[int, int, int]) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (256, 256), color).save(buf, format="PNG")
    return buf.getvalue()


def _csv_field(v: str) -> str:
    return '"' + v.replace('"', '""') + '"' if any(ch in v for ch in ',"\n\r') else v


def _pgm(w: int = 256, h: int = 256) -> bytes:
    return f"P5\n{w} {h}\n255\n".encode("ascii") + bytes(w * h)


def make_zip(path: Path, scans: list[dict], feedback: list[dict], times: list[str], images: list[str],
             readme_extra: str = "", feedback_columns: list[str] | None = None, masks: dict[str, list[str]] | None = None,
             extra_members: list[str] | None = None) -> Path:
    """Zip con la estructura de Diagnostics.export (scores como JSON entrecomillado, como en la app).

    ``feedback_columns``: columnas añadidas al final de feedback.csv (valor de cada fila en ``f[col]``);
    ``masks``: ``{scan_id: [variante, ...]}`` -> ``images/<scan_id>.<variante>.pgm``; ``extra_members``:
    otros ficheros de ``images/`` (p. ej. ``s1.json``)."""
    by_id = {s["id"]: s for s in scans}
    extra_cols = list(feedback_columns or [])
    fb_lines = [",".join([*fr.FEEDBACK_HEADER, *extra_cols])]
    for f in feedback:
        s = by_id.get(f["scan_id"], {})
        fields = [f["scan_id"], f["verdict"], str(s.get("top1", "")), str(s.get("top2", "")), str(s.get("top3", "")),
                  json.dumps([1.5, 2.5, 3.5]), f.get("created_at", "2026-09-15T10:00:00Z"), *(str(f.get(c, "")) for c in extra_cols)]
        fb_lines.append(",".join(_csv_field(x) for x in fields))
    sc_lines = [",".join(fr.SCANS_HEADER)]
    for s in scans:
        fields = [s["id"], s["source"], str(s.get("top1", "")), str(s.get("top2", "")), str(s.get("top3", "")),
                  json.dumps([1.5, 2.5, 3.5]), str(s.get("ambiguous", 0)), "0.1.0", "fd95ac692777", "2026-09-15T09:00:00Z",
                  "#112233:0.6000;#445566:0.4000"]
        sc_lines.append(",".join(_csv_field(x) for x in fields))
    readme = ("colorsApp — diagnóstico\nexportado: 2026-09-15T12:00:00Z\napp 0.1 (7) · motor 0.1.0 · diccionario fd95ac692777 · GRDB 7.11.1 · SQLite 3.50.0\n"
              "feedback.csv: scan_id, verdict (yes|no), top1..top3, scores (JSON), created_at\n" + readme_extra)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("README.txt", readme)
        zf.writestr("feedback.csv", "\n".join(fb_lines) + "\n")
        zf.writestr("scans.csv", "\n".join(sc_lines) + "\n")
        zf.writestr("times.txt", "".join(t + "\n" for t in times))
        for i, sid in enumerate(images):
            zf.writestr(f"images/{sid}.png", _png((i * 40 % 256, 80, 120)))
        for sid, variants in (masks or {}).items():
            for v in variants:
                zf.writestr(f"images/{sid}.{v}.pgm", _pgm())
        for name in extra_members or []:
            zf.writestr(f"images/{name}", "{}\n")
    return path


@pytest.fixture
def two_zips(tmp_path: Path) -> tuple[Path, Path]:
    # Teléfono "andres": 5 scans (library x3, camera, picker), 3 valoraciones (2 sí, 1 no).
    #   top-1 valorados: 12, 7, 12 -> cuota 2/3 (Nº 12); top-1 de todos los scans: 12 x3 de 5 -> 0.6.
    a = make_zip(
        tmp_path / "andres.zip",
        scans=[{"id": "s1", "source": "library", "top1": 12, "top2": 3, "top3": 4},
               {"id": "s2", "source": "library", "top1": 12, "top2": 3, "top3": 4},
               {"id": "s3", "source": "camera", "top1": 7, "top2": 8, "top3": 9, "ambiguous": 1},
               {"id": "s4", "source": "picker", "top1": 12, "top2": 5, "top3": 6},
               {"id": "s5", "source": "library", "top1": 100, "top2": 5, "top3": 6}],
        feedback=[{"scan_id": "s1", "verdict": "yes"}, {"scan_id": "s3", "verdict": "no"}, {"scan_id": "s4", "verdict": "yes"}],
        times=["2026-09-15T10:00:00Z analyze.camera 180 ms", "2026-09-15T10:00:01Z analyze.picker 95 ms",
               "2026-09-15T09:00:00Z scan.done 45000 ms"],
        images=["s1", "s3", "s4"],
    )
    # Teléfono "esposa": 3 scans (library x2, camera), 3 valoraciones (1 sí, 2 no); t3 "no" sin PNG.
    #   top-1 valorados: 7, 33, 7 -> cuota 2/3 (Nº 7). scan.done con formato "<n> <ms> ms".
    b = make_zip(
        tmp_path / "esposa.zip",
        scans=[{"id": "t1", "source": "library", "top1": 7, "top2": 8, "top3": 9},
               {"id": "t2", "source": "library", "top1": 33, "top2": 8, "top3": 9},
               {"id": "t3", "source": "camera", "top1": 7, "top2": 8, "top3": 9}],
        feedback=[{"scan_id": "t1", "verdict": "no"}, {"scan_id": "t2", "verdict": "yes"}, {"scan_id": "t3", "verdict": "no"}],
        times=["2026-09-15T09:00:00Z scan.done 200 130000 ms", "esto no es una medición"],
        images=["t1"],
    )
    return a, b


def test_parse_times_formats():
    rows, bad = fr.parse_times("2026-09-15T10:00:00Z analyze.camera 180 ms\n2026-09-15T09:00:00Z scan.done 200 130000 ms\nbasura\n\n")
    assert rows == [{"ts": "2026-09-15T10:00:00Z", "label": "analyze.camera", "ms": 180},
                    {"ts": "2026-09-15T09:00:00Z", "label": "scan.done", "ms": 130000, "count": 200}]
    assert bad == ["basura"]


def test_report_numbers_by_hand(two_zips, tmp_path: Path):
    a, b = two_zips
    report = fr.build_report([a, b], thresholds_path=tmp_path / "no-thresholds.json", log=lambda *_: None)
    assert report is not None
    phones = {p["name"]: p for p in report["phones"]}
    assert set(phones) == {"andres", "esposa"}
    an, es, tot = phones["andres"], phones["esposa"], report["total"]
    assert (an["n_scans"], an["n_ratings"], an["yes"], an["no"]) == (5, 3, 2, 1)
    assert an["yes_rate"] == pytest.approx(2 / 3)
    assert an["rated_top1_share"] == pytest.approx(2 / 3) and an["rated_top1_id"] == 12
    assert an["scans_top1_share"] == pytest.approx(3 / 5) and an["scans_top1_id"] == 12
    assert an["by_source"] == {"camera": 1, "library": 3, "picker": 1}
    assert an["ambiguous_rate"] == pytest.approx(1 / 5)
    assert an["scan_done_ms"] == [45000]
    assert an["times"]["analyze.camera"] == {"n": 1, "median_ms": 180, "mean_ms": 180.0, "max_ms": 180, "min_ms": 180}
    assert an["no_photos"] == [{"scan_id": "s3", "png": "images/s3.png", "in_zip": True}]
    assert an["versions"].startswith("app 0.1 (7)") and an["exported_at"] == "2026-09-15T12:00:00Z"
    assert (es["n_scans"], es["n_ratings"], es["yes"], es["no"]) == (3, 3, 1, 2)
    assert es["rated_top1_share"] == pytest.approx(2 / 3) and es["rated_top1_id"] == 7
    assert es["scan_done_ms"] == [130000]
    assert [(p["scan_id"], p["in_zip"]) for p in es["no_photos"]] == [("t1", True), ("t3", False)]
    assert es["rated_without_png"] == ["t2", "t3"]
    assert any("times.txt ilegibles" in n for n in es["notes"])
    # Global: 8 scans, 6 valoraciones (3 sí / 3 no); top-1 valorados 12,7,12,7,33,7 -> 3/6 (Nº 7).
    assert (tot["n_scans"], tot["n_ratings"], tot["yes"], tot["no"]) == (8, 6, 3, 3)
    assert tot["yes_rate"] == pytest.approx(0.5)
    assert tot["rated_top1_share"] == pytest.approx(0.5) and tot["rated_top1_id"] == 7 and tot["rated_top1_distinct"] == 3
    assert tot["by_source"] == {"camera": 2, "library": 5, "picker": 1}
    assert tot["scan_done_ms"] == [45000, 130000]
    # Zips sin columnas de recorte: todo cae en "sin-datos" (funciona sin ellas).
    assert list(tot["by_crop_mode"]) == [fr.NO_CROP_DATA] and tot["by_crop_mode"][fr.NO_CROP_DATA]["n_ratings"] == 6
    assert list(tot["by_people"]) == [fr.NO_CROP_DATA] and tot["rated_with_masks"] == 0 and tot["mask_variants"] == {}
    # Gate F10 con defaults: 6 < 50, 0.5 < 0.7, 0.5 > 0.3 fallan; scan.done solo informativo.
    status = {c["name"].split(" ")[0]: c["status"] for c in report["checks"]}
    assert [c["status"] for c in report["checks"]] == ["fail", "fail", "fail", "info"]
    assert report["gate_pass"] is False
    assert set(report["thresholds_defaulted"]) == set(fr.DEFAULTS)
    assert status  # solo para usar la variable


def test_dedupe_same_zip_twice_and_phone_subdirs(two_zips, tmp_path: Path):
    a, b = two_zips
    twice = fr.build_report([a, a], thresholds_path=tmp_path / "none.json", log=lambda *_: None)
    assert len(twice["phones"]) == 1 and twice["total"]["n_ratings"] == 3 and twice["total"]["n_scans"] == 5
    # Directorio con un subdirectorio por teléfono (varios exports del mismo teléfono se funden).
    root = tmp_path / "zips"
    (root / "andres").mkdir(parents=True)
    (root / "andres" / "export-1.zip").write_bytes(a.read_bytes())
    (root / "andres" / "export-2.zip").write_bytes(a.read_bytes())
    (root / "esposa.zip").write_bytes(b.read_bytes())
    rep = fr.build_report([root], thresholds_path=tmp_path / "none.json", log=lambda *_: None)
    names = {p["name"]: p for p in rep["phones"]}
    assert set(names) == {"andres", "esposa"}
    assert names["andres"]["n_ratings"] == 3 and len(names["andres"]["zips"]) == 2
    assert rep["total"]["n_ratings"] == 6


def test_device_line_in_readme_overrides_zip_name(tmp_path: Path):
    z = make_zip(tmp_path / "colorsapp-diagnostico-20260915-120000.zip",
                 scans=[{"id": "x1", "source": "camera", "top1": 1}], feedback=[{"scan_id": "x1", "verdict": "yes"}],
                 times=[], images=[], readme_extra="device: iphone-13-mini\n")
    rep = fr.build_report([z], thresholds_path=tmp_path / "none.json", log=lambda *_: None)
    assert [p["name"] for p in rep["phones"]] == ["iphone-13-mini"]


def test_thresholds_section_f10_and_scan_done_gate(two_zips, tmp_path: Path):
    a, b = two_zips
    th = tmp_path / "thresholds.json"
    th.write_text(json.dumps({"F10": {"min_ratings": 5, "yes_rate_min": 0.5, "max_class_share_max": 0.6, "scan_done_max_ms": 100000}}))
    rep = fr.build_report([a, b], thresholds_path=th, log=lambda *_: None)
    assert rep["thresholds_defaulted"] == []
    assert [c["status"] for c in rep["checks"]] == ["pass", "pass", "pass", "fail"]  # scan.done 130000 > 100000 gatea
    assert rep["gate_pass"] is False
    th.write_text(json.dumps({"F10": {"min_ratings": 5, "yes_rate_min": 0.5, "max_class_share_max": 0.6, "scan_done_max_ms": 200000}}))
    rep = fr.build_report([a, b], thresholds_path=th, log=lambda *_: None)
    assert [c["status"] for c in rep["checks"]] == ["pass", "pass", "pass", "pass"] and rep["gate_pass"] is True


def test_main_exit_codes_and_outputs(two_zips, tmp_path: Path, capsys):
    a, b = two_zips
    out = tmp_path / "out"
    assert fr.main([str(a), str(b), "--out", str(out), "--thresholds", str(tmp_path / "none.json"), "--extract", str(tmp_path / "extract")]) == 1
    text = capsys.readouterr().out
    assert "| andres" in text and "| global" in text and "FAIL (gate F10)" in text
    assert (out / "feedback-report.json").is_file() and (out / "feedback-report.md").is_file()
    doc = json.loads((out / "feedback-report.json").read_text())
    assert doc["total"]["n_ratings"] == 6 and "_phones" not in doc
    md = (out / "feedback-report.md").read_text()
    assert "images/s3.png" in md and "images/t3.png" in md and "(PNG no incluido en el zip)" in md
    # --extract: PNG de las fotos valoradas que están en el zip (s1, s3, s4, t1) + índice.
    extracted = sorted(p.name for p in (tmp_path / "extract").glob("*.png"))
    assert extracted == ["andres_s1.png", "andres_s3.png", "andres_s4.png", "esposa_t1.png"]
    index = (tmp_path / "extract" / "feedback-index.csv").read_text().splitlines()
    assert index[0] == "phone,scan_id,verdict,top1,top2,top3,file,subject_mode,region_mode,adaptive_skin,people_count,person_index,masks"
    assert len(index) == 5
    # Sin zips legibles: 2.
    (tmp_path / "vacio").mkdir()
    assert fr.main([str(tmp_path / "vacio"), "--out", str(out)]) == 2
    bad = tmp_path / "roto.zip"
    with zipfile.ZipFile(bad, "w") as zf:
        zf.writestr("feedback.csv", "x\n")
    assert fr.main([str(bad), "--out", str(out)]) == 2


def test_gate_passes_with_enough_good_ratings(tmp_path: Path):
    # 60 scans/valoraciones: 45 sí (0.75 >= 0.70); top-1 repartido en 4 combinaciones (15 cada una -> 0.25 <= 0.30).
    scans = [{"id": f"u{i}", "source": "picker", "top1": [10, 20, 30, 40][i % 4]} for i in range(60)]
    feedback = [{"scan_id": f"u{i}", "verdict": "yes" if i < 45 else "no", "created_at": f"2026-09-15T10:{i:02d}:00Z"} for i in range(60)]
    z = make_zip(tmp_path / "bueno.zip", scans, feedback, ["2026-09-15T09:00:00Z scan.done 60000 ms"], [])
    rep = fr.build_report([z], thresholds_path=tmp_path / "none.json", log=lambda *_: None)
    assert rep["total"]["n_ratings"] == 60 and rep["total"]["yes_rate"] == pytest.approx(0.75)
    assert rep["total"]["rated_top1_share"] == pytest.approx(0.25)
    assert [c["status"] for c in rep["checks"]] == ["pass", "pass", "pass", "info"] and rep["gate_pass"] is True
    assert fr.main([str(z), "--out", str(tmp_path / "o"), "--thresholds", str(tmp_path / "none.json")]) == 0


CROP = ["subject_mode", "region_mode", "adaptive_skin", "people_count", "person_index"]


def test_crop_columns_masks_and_aggregation_by_mode(tmp_path: Path, capsys):
    # 6 valoraciones con columnas de recorte (build nueva):
    #   c1 yes largestPerson/clothing/1  people 3 idx 0  top1 10
    #   c2 no  largestPerson/clothing/1  people 1 idx 0  top1 10
    #   c3 yes largestPerson/clothing/1  people 2 idx 1  top1 20
    #   c4 yes allPeople/wholePerson/0   people 2 idx ""  top1 30
    #   c5 no  off/""/""                 people 0 idx ""  top1 30
    #   c6 yes (sin columnas en feedback: se toman de scans.csv? no, scans sin columnas) -> sin-datos, top1 40
    # Por modo: largestPerson/clothing/skin 3 (2 sí, 1 no; top1 10 x2 -> 2/3); allPeople/wholePerson/noskin 1 (1 sí);
    #   off 1 (0 sí); sin-datos 1 (1 sí). Por personas: 2+ -> c1,c3,c4 (3 sí de 3); 1 -> c2; 0 -> c5; sin-datos -> c6.
    #   person_index > 0: 1 (c3). Máscaras: c1 (3 variantes), c3 (1) -> 2 fotos valoradas; variantes largest 2, resto 1.
    rows = [("c1", "yes", "largestPerson", "clothing", "1", "3", "0", 10), ("c2", "no", "largestPerson", "clothing", "true", "1", "0", 10),
            ("c3", "yes", "largestPerson", "clothing", "1", "2", "1", 20), ("c4", "yes", "allPeople", "wholePerson", "0", "2", "", 30),
            ("c5", "no", "off", "", "", "0", "", 30), ("c6", "yes", "", "", "", "", "", 40)]
    scans = [{"id": r[0], "source": "camera", "top1": r[7], "top2": 1, "top3": 2} for r in rows]
    feedback = [{"scan_id": r[0], "verdict": r[1], "created_at": f"2026-09-15T10:0{i}:00Z", **dict(zip(CROP, r[2:7]))} for i, r in enumerate(rows)]
    z = make_zip(tmp_path / "andres.zip", scans, feedback, [], images=["c1", "c2", "c3"], feedback_columns=[*CROP, "columna_rara"],
                 masks={"c1": ["largest", "largest-clothing", "largest-clothing-skin"], "c3": ["largest"], "zz": ["largest"]},
                 extra_members=["c1.json"])
    rep = fr.build_report([z], thresholds_path=tmp_path / "none.json", log=lambda *_: None)
    tot = rep["total"]
    modes = tot["by_crop_mode"]
    assert set(modes) == {"largestPerson/clothing/skin", "allPeople/wholePerson/noskin", "off", fr.NO_CROP_DATA}
    lc = modes["largestPerson/clothing/skin"]
    assert (lc["n_ratings"], lc["yes"], lc["no"]) == (3, 2, 1) and lc["yes_rate"] == pytest.approx(2 / 3)
    assert lc["top1_share"] == pytest.approx(2 / 3) and lc["top1_id"] == 10
    assert lc["label"] == "persona principal · solo ropa · piel adaptativa"
    assert (modes["allPeople/wholePerson/noskin"]["n_ratings"], modes["allPeople/wholePerson/noskin"]["yes"]) == (1, 1)
    assert (modes["off"]["n_ratings"], modes["off"]["yes"], modes["off"]["label"]) == (1, 0, "sin recorte")
    assert modes[fr.NO_CROP_DATA]["n_ratings"] == 1
    people = tot["by_people"]
    assert {k: (v["n_ratings"], v["yes"]) for k, v in people.items()} == {"2+": (3, 3), "1": (1, 0), "0": (1, 0), fr.NO_CROP_DATA: (1, 1)}
    assert tot["person_index_not_largest"] == 1
    assert tot["rated_with_masks"] == 2 and tot["mask_variants"] == {"largest": 2, "largest-clothing": 1, "largest-clothing-skin": 1}
    assert any("columna_rara" in n for n in rep["phones"][0]["notes"])
    # Consola y md muestran la tabla por modo de recorte; --extract copia PGM y JSON con nombres descubribles.
    assert fr.main([str(z), "--out", str(tmp_path / "o"), "--thresholds", str(tmp_path / "none.json"), "--extract", str(tmp_path / "ex")]) == 1
    text = capsys.readouterr().out
    assert "modo de recorte (global)" in text and "persona principal · solo ropa · piel adaptativa" in text
    md = (tmp_path / "o" / "feedback-report.md").read_text()
    assert "## Por modo de recorte" in md and "grupo (2+ personas)" in md
    ex = sorted(p.name for p in (tmp_path / "ex").iterdir())
    assert ex == ["andres_c1.largest-clothing-skin.pgm", "andres_c1.largest-clothing.pgm", "andres_c1.largest.pgm",
                  "andres_c1.png", "andres_c2.png", "andres_c3.largest.pgm", "andres_c3.png", "capas", "feedback-index.csv"]
    # Los extras (JSON de pasos, capas) van a capas/: nunca se confunden con fotos del set dorado.
    assert sorted(p.name for p in (tmp_path / "ex" / "capas").iterdir()) == ["andres_c1.json"]
    index = (tmp_path / "ex" / "feedback-index.csv").read_text().splitlines()
    assert index[1].endswith("largestPerson,clothing,1,3,0,largest;largest-clothing;largest-clothing-skin")
    # Lo extraído es exactamente lo que descubre merge_labels (fotos + máscaras por variante).
    from tools import merge_labels as ml
    photos, problems = ml.list_photos(tmp_path / "ex")
    found, orphans = ml.discover_masks(tmp_path / "ex", [p.name for p in photos])
    assert problems == [] and orphans == []
    assert found == {"andres_c1.png": {"largest": "andres_c1.largest.pgm", "largest-clothing": "andres_c1.largest-clothing.pgm",
                                       "largest-clothing-skin": "andres_c1.largest-clothing-skin.pgm"},
                     "andres_c3.png": {"largest": "andres_c3.largest.pgm"}}


def test_crop_columns_from_scans_csv_and_missing_base_column(tmp_path: Path):
    # Si feedback.csv no trae las columnas pero scans.csv sí, se usan las del scan.
    z = tmp_path / "x.zip"
    with zipfile.ZipFile(z, "w") as zf:
        zf.writestr("feedback.csv", ",".join(fr.FEEDBACK_HEADER) + "\ns1,yes,5,6,7,[],2026-09-15T10:00:00Z\n")
        zf.writestr("scans.csv", ",".join([*fr.SCANS_HEADER, *CROP, "mask_steps", "mask_coverage"]) + "\n"
                    's1,camera,5,6,7,[],0,0.1.0,fd95ac692777,2026-09-15T09:00:00Z,#112233:1.0000,largestPerson,clothing,1,4,0,"[""poseRegions""]",0.21\n')
        zf.writestr("times.txt", "")
    rep = fr.build_report([z], thresholds_path=tmp_path / "none.json", log=lambda *_: None)
    assert list(rep["total"]["by_crop_mode"]) == ["largestPerson/clothing/skin"] and list(rep["total"]["by_people"]) == ["2+"]
    assert rep["phones"][0]["notes"] == []
    # Falta una columna base (verdict): el zip se ignora con motivo y, sin otros, exit 2.
    bad = tmp_path / "bad.zip"
    with zipfile.ZipFile(bad, "w") as zf:
        zf.writestr("feedback.csv", "scan_id,top1,top2,top3,scores,created_at\ns1,5,6,7,[],x\n")
        zf.writestr("scans.csv", ",".join(fr.SCANS_HEADER) + "\n")
        zf.writestr("times.txt", "")
    errors: list[str] = []
    assert fr.build_report([bad], thresholds_path=tmp_path / "none.json", log=errors.append) is None
    assert any("faltan columnas ['verdict']" in e for e in errors)


def test_extract_destination_must_live_outside_repo(two_zips, tmp_path: Path, capsys):
    a, _b = two_zips
    assert fr.extract_dest_problem(tmp_path / "golden") is None
    assert fr.extract_dest_problem(fr.REPO_ROOT / "harness" / "out" / "extract") is None
    assert "dentro del repo" in (fr.extract_dest_problem(fr.REPO_ROOT / "docs" / "fotos") or "")
    assert "dentro del repo" in (fr.extract_dest_problem(fr.REPO_ROOT) or "")
    dest = fr.REPO_ROOT / "harness" / "label" / "fotos-no"
    assert fr.main([str(a), "--out", str(tmp_path / "o"), "--extract", str(dest)]) == 2
    assert "dentro del repo" in capsys.readouterr().err and not dest.exists()


def test_latest_verdict_per_scan_and_times_dedupe(tmp_path: Path):
    # x1 votado dos veces (yes 10:00, luego no 10:05) => 1 valoración "no"; x2 yes. Dos exports del mismo teléfono
    # con el times.txt acumulado: scan.done 50000 aparece en ambos y cuenta una vez; 70000 solo en el segundo.
    scans = [{"id": "x1", "source": "camera", "top1": 5}, {"id": "x2", "source": "picker", "top1": 6}]
    fb1 = [{"scan_id": "x1", "verdict": "yes", "created_at": "2026-09-15T10:00:00Z"}, {"scan_id": "x2", "verdict": "yes", "created_at": "2026-09-15T10:01:00Z"}]
    fb2 = fb1 + [{"scan_id": "x1", "verdict": "no", "created_at": "2026-09-15T10:05:00Z"}]
    root = tmp_path / "zips" / "andres"
    root.mkdir(parents=True)
    make_zip(root / "e1.zip", scans, fb1, ["2026-09-15T09:00:00Z scan.done 50000 ms"], images=["x1", "x2"])
    make_zip(root / "e2.zip", scans, fb2, ["2026-09-15T09:00:00Z scan.done 50000 ms", "2026-09-16T09:00:00Z scan.done 70000 ms"], images=["x1", "x2"])
    rep = fr.build_report([tmp_path / "zips"], thresholds_path=tmp_path / "none.json", log=lambda *_: None)
    (phone,) = rep["phones"]
    assert (phone["n_ratings"], phone["yes"], phone["no"], phone["superseded_verdicts"]) == (2, 1, 1, 1)
    assert [p["scan_id"] for p in phone["no_photos"]] == ["x1"]
    assert phone["scan_done_ms"] == [50000, 70000] and rep["total"]["scan_done_ms"] == [50000, 70000]
    assert any("veredicto(s) anteriores" in n for n in phone["notes"])
    assert (rep["total"]["n_ratings"], rep["total"]["yes"]) == (2, 1)
    fr.extract_rated(fr.load_phones(fr.find_zips([tmp_path / "zips"]), log=lambda *_: None)[0], tmp_path / "ex", log=lambda *_: None)
    index = (tmp_path / "ex" / "feedback-index.csv").read_text().splitlines()
    assert [line.split(",")[:3] for line in index[1:]] == [["andres", "x1", "no"], ["andres", "x2", "yes"]]


def test_split_member():
    assert fr.split_member("images/abc.png") == ("abc", "", "png")
    assert fr.split_member("images/abc.largest-clothing.pgm") == ("abc", "largest-clothing", "pgm")
    assert fr.split_member("images/abc.json") == ("abc", "", "json")
    assert fr.split_member("feedback.csv") is None and fr.split_member("images/") is None and fr.split_member("images/sub/x.png") is None
