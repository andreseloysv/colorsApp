"""Tests de ``oracle/tools/merge_labels.py`` (fusión + golden-check del set dorado) y de
``oracle/tools/label_page.py`` con un directorio dorado temporal de 6 imágenes sintéticas (Pillow)
y etiquetas de 3 jueces ficticios (incluye una foto sin consenso, un sha256 corrupto, el tag
"grupo" y máscaras PGM de variantes junto a las fotos)."""

from __future__ import annotations

import hashlib
import json
import os
from html.parser import HTMLParser
from pathlib import Path

import pytest
from PIL import Image

from l4 import run as l4
from oracle import l3
from oracle import names as nm
from tools import label_page as lp
from tools import merge_labels as ml

CLI = l3.find_cli_optional()
CLI_HAS_BATCH = l3.has_batch(CLI)
TAGS = ["negro", "denim", "gris", "interior", "fondo-sucio", "blanco", "grupo"]
COMBOS = [1, 12, 150, 300, 348, 77]


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _band_image(rgbs: list[tuple[int, int, int]], size: int = 256) -> Image.Image:
    img = Image.new("RGB", (size, size))
    px = img.load()
    width = size // len(rgbs)
    for x in range(size):
        for y in range(size):
            px[x, y] = rgbs[min(x // width, len(rgbs) - 1)]
    return img


@pytest.fixture
def golden(tmp_path: Path) -> Path:
    """6 fotos con bandas de los colores exactos de 6 combinaciones (4 PNG, 2 JPEG q95)."""
    dictionary = nm.load_json(lp.DEFAULT_DICTIONARY)
    colors = {c["index"]: tuple(c["rgb"]) for c in dictionary["colors"]}
    combos = {c["id"]: c for c in dictionary["combinations"]}
    for i, cid in enumerate(COMBOS):
        img = _band_image([colors[k] for k in combos[cid]["colors"]])
        if i % 3 == 2:
            img.save(tmp_path / f"photo{i}.jpg", format="JPEG", quality=95)
        else:
            img.save(tmp_path / f"photo{i}.png", format="PNG")
    (tmp_path / "notas.txt").write_text("no es una foto\n")
    return tmp_path


def _files(golden: Path) -> list[Path]:
    return ml.list_photos(golden)[0]


def _write_labels(labels_dir: Path, judge: str, rows: list[dict], kind: str = ml.LABELS_KIND) -> Path:
    labels_dir.mkdir(exist_ok=True)
    p = labels_dir / f"labels-{judge}.json"
    p.write_text(json.dumps({"schema": 1, "kind": kind, "judge": judge, "dict_version": "fd95ac692777", "labels": rows}, indent=1))
    return p


def _write_pgm(path: Path, w: int = 256, h: int = 256, fill: int = 255, left_only: bool = False) -> Path:
    body = bytearray([fill]) * (w * h)
    if left_only:
        for y in range(h):
            body[y * w + w // 2: (y + 1) * w] = bytes(w - w // 2)
    path.write_bytes(f"P5\n{w} {h}\n255\n".encode("ascii") + bytes(body))
    return path


def _judges_clean(golden: Path) -> Path:
    """3 jueces coherentes: unanimidad salvo photo1 (2 de 3) y photo5 (2 de 3 "ninguna").

    Tags: photo_i lleva TAGS[i] (+ "interior" en 0..2); photo5 lleva además "blanco" y "grupo"
    (la unión cubre los 7 tags)."""
    files = _files(golden)
    rows = {"ana": [], "bea": [], "carl": []}
    for i, f in enumerate(files):
        base = {"file": f.name, "sha256": _sha(f), "note": ""}
        tags = [TAGS[i]] + (["interior"] if i < 3 else []) + (["grupo"] if i == 5 else [])
        vote = {"ana": COMBOS[i], "bea": COMBOS[i], "carl": COMBOS[i]}
        if i == 1:
            vote["carl"] = 99
        if i == 5:
            vote = {"ana": None, "bea": None, "carl": COMBOS[i]}
        for j in rows:
            rows[j].append({**base, "combo_id": vote[j], "tags": tags if j != "carl" else tags[:1], "note": "dudo" if (j, i) == ("carl", 1) else ""})
    d = golden / "labels"
    for j, r in rows.items():
        _write_labels(d, j, r)
    return d


def test_list_photos_rejects_heic_and_ignores_other_files(golden: Path):
    photos, problems = ml.list_photos(golden)
    assert [p.name for p in photos] == ["photo0.png", "photo1.png", "photo2.jpg", "photo3.png", "photo4.png", "photo5.jpg"]
    assert problems == []
    (golden / "fake.heic").write_bytes(b"\x00\x00\x00\x18ftypheic" + b"\x00" * 32)
    (golden / "disfrazada.png").write_bytes(b"\x00\x00\x00\x18ftypheic" + b"\x00" * 32)
    photos, problems = ml.list_photos(golden)
    assert len(problems) == 2 and all("HEIC" in p for p in problems)
    assert "disfrazada.png" not in {p.name for p in photos}


def test_read_labels_file_validation(tmp_path: Path):
    p = _write_labels(tmp_path, "ana", [{"file": "a.png", "combo_id": 3, "tags": ["negro"]}, {"file": "b.png", "combo_id": None}])
    judge, entries = ml.read_labels_file(p)
    assert judge == "ana" and entries["a.png"]["combo_id"] == 3 and entries["b.png"]["combo_id"] is None and entries["b.png"]["tags"] == []
    with pytest.raises(ml.LabelsError, match="1..348"):
        ml.read_labels_file(_write_labels(tmp_path, "bea", [{"file": "a.png", "combo_id": 400}]))
    with pytest.raises(ml.LabelsError, match="repetido"):
        ml.read_labels_file(_write_labels(tmp_path, "cal", [{"file": "a.png", "combo_id": 1}, {"file": "a.png", "combo_id": 2}]))
    with pytest.raises(ml.LabelsError, match="kind"):
        ml.read_labels_file(_write_labels(tmp_path, "dan", [], kind="otro"))
    # Sin campo judge: se toma del nombre del fichero.
    q = tmp_path / "labels-eva.json"
    q.write_text(json.dumps({"labels": [{"file": "a.png", "combo_id": 5}]}))
    assert ml.read_labels_file(q)[0] == "eva"
    assert ml.judge_slug("Ana María") == "ana-mar-a" and ml.judge_slug("  ") == "juez"


def test_merge_clean_consensus_and_kappa(golden: Path):
    labels_dir = _judges_clean(golden)
    manifest, problems = ml.merge(golden, ml.find_labels_files(labels_dir), TAGS, 3)
    assert problems == []
    assert manifest["judges"] == ["ana", "bea", "carl"] and manifest["n_photos"] == 6 and manifest["unlabeled"] == []
    # Consenso: photo0..4 por mayoría (photo1 2 de 3); photo5 "ninguna" por mayoría (2 de 3): no puntúa, pero no es empate.
    assert manifest["n_consensus"] == 5 and manifest["consensus_none"] == ["photo5.jpg"] and manifest["without_consensus"] == []
    photos = {e["file"]: e for e in manifest["photos"]}
    assert photos["photo1.png"]["labels"] == {"ana": 12, "bea": 12, "carl": 99} and photos["photo1.png"]["consensus"] == 12
    assert photos["photo5.jpg"]["labels"] == {"ana": None, "bea": None, "carl": 77} and photos["photo5.jpg"]["consensus"] is None
    assert [photos[f"photo{i}.{'jpg' if i % 3 == 2 else 'png'}"]["consensus_kind"] for i in range(6)] == ["combo"] * 5 + ["none"]
    assert manifest["label_sources"]["ana"] == {"file": "labels-ana.json", "dict_version": "fd95ac692777"}
    assert photos["photo0.png"]["tags"] == ["interior", "negro"]  # unión de los jueces
    assert photos["photo5.jpg"]["tags"] == ["blanco", "grupo"]
    assert "masks" not in photos["photo0.png"] and manifest["n_with_masks"] == 0
    assert photos["photo1.png"]["notes"] == {"carl": "dudo"}
    # κ a mano: 6 fotos x 3 jueces; P_i = 1,1/3,1,1,1,1/3 -> P̄ = 7/9; categorías 1(3),12(2),99(1),150(3),300(3),348(3),ninguna(2),77(1)
    # p_j = n_j/18; P_e = (9+4+1+9+9+9+4+1)/324 = 46/324; κ = (7/9 - 46/324)/(1 - 46/324) = (252-46)/(324-46) = 206/278.
    assert manifest["fleiss_kappa"] == pytest.approx(206 / 278) and manifest["fleiss_kappa_photos"] == 6
    assert manifest["fleiss_kappa"] == pytest.approx(l4.fleiss_kappa([e["labels"] for e in manifest["photos"]]))
    # El manifest fusionado es exactamente lo que lee l4.run.
    (golden / "manifest.json").write_text(json.dumps(manifest))
    loaded = l4.load_manifest(golden)
    assert len(loaded) == 6 and all(l4.verify_photo(golden, e)[0] == [] for e in loaded)


def test_merge_reports_no_consensus_corrupt_sha_and_missing_labels(golden: Path):
    labels_dir = _judges_clean(golden)
    files = _files(golden)
    # photo4: tres votos distintos (sin consenso); photo2: sha256 corrupto en bea (la foto "cambió");
    # photo3: carl no la etiquetó; tag desconocido en ana (photo0).
    for judge, edit in {"ana": lambda r: r.__setitem__("combo_id", 300), "bea": lambda r: r.__setitem__("combo_id", 5), "carl": lambda r: r.__setitem__("combo_id", None)}.items():
        p = labels_dir / f"labels-{judge}.json"
        doc = json.loads(p.read_text())
        for r in doc["labels"]:
            if r["file"] == files[4].name:
                edit(r)
            if judge == "bea" and r["file"] == files[2].name:
                r["sha256"] = "0" * 64
            if judge == "ana" and r["file"] == files[0].name:
                r["tags"].append("raro")
        if judge == "carl":
            doc["labels"] = [r for r in doc["labels"] if r["file"] != files[3].name]
        p.write_text(json.dumps(doc))
    manifest, problems = ml.merge(golden, ml.find_labels_files(labels_dir), TAGS, 3)
    photos = {e["file"]: e for e in manifest["photos"]}
    assert photos["photo4.png"]["consensus"] is None and manifest["without_consensus"] == ["photo4.png"]
    assert photos["photo4.png"]["consensus_kind"] == "tie" and manifest["consensus_none"] == ["photo5.jpg"]
    assert set(photos["photo2.jpg"]["labels"]) == {"ana", "carl"} and photos["photo2.jpg"]["consensus"] == 150
    assert set(photos["photo3.png"]["labels"]) == {"ana", "bea"}
    # κ solo sobre las fotos con los 3 jueces (photo2 y photo3 quedan fuera): 4 fotos x 3 jueces.
    #   photo0 (1,1,1) P=1; photo1 (12,12,99) P=1/3; photo4 (300,5,ninguna) P=0; photo5 (ninguna,ninguna,77) P=1/3
    #   P̄ = (1 + 1/3 + 0 + 1/3)/4 = 5/12; n_j: 1:3, 12:2, 99:1, 300:1, 5:1, ninguna:3, 77:1 (12 votos)
    #   P_e = (9+4+1+1+1+9+1)/144 = 26/144; κ = (5/12 - 26/144)/(1 - 26/144) = (60-26)/(144-26) = 34/118.
    assert manifest["fleiss_kappa"] == pytest.approx(34 / 118) and manifest["fleiss_kappa_photos"] == 4
    joined = "\n".join(problems)
    assert "photo2.jpg: sha256 de bea" in joined and "etiqueta descartada" in joined
    assert "photo3.png: sin etiqueta de carl" in joined
    assert "tag 'raro'" in joined
    # Un juez repetido y un número de jueces distinto del esperado también se reportan.
    dup = labels_dir / "labels-ana2.json"
    dup.write_text((labels_dir / "labels-ana.json").read_text())
    _m, problems2 = ml.merge(golden, ml.find_labels_files(labels_dir), TAGS, 4)
    assert any("repetido" in p for p in problems2) and any("se esperaban 4" in p for p in problems2)


def test_cmd_merge_and_check_end_to_end(golden: Path, capsys):
    labels_dir = _judges_clean(golden)
    assert ml.main(["merge", "--golden-dir", str(golden), "--labels", str(labels_dir)]) == 0
    out = capsys.readouterr().out
    assert "6 fotos, jueces: ana, bea, carl" in out and "consenso en 5/6 (+1 \"ninguna\" por mayoría)" in out
    assert "Fleiss κ = 0.741" in out and "0 con máscaras" in out and "\"ninguna\" por mayoría (1;" in out and "sin consenso (" not in out
    manifest = json.loads((golden / "manifest.json").read_text())
    assert manifest["n_photos"] == 6
    # golden-check: falla solo por < 50 fotos, con mensaje claro; el resto pasa.
    ok, checks = ml.check(golden, l3.load_thresholds(), log=lambda *_: None)
    by_name = {c.name: c for c in checks}
    assert ok is False
    photos_check = [c for c in checks if c.name.startswith("fotos >= 50")][0]
    assert photos_check.status == "fail" and "faltan 44 para el mínimo de 50" in photos_check.detail and "94 para el objetivo de 100" in photos_check.detail
    assert by_name["fotos: sha256, PNG/JPEG sRGB, lado <= 256 px, sin HEIC"].status == "pass"
    assert by_name["todos los tags presentes al menos una vez"].status == "pass"
    assert by_name["3 etiquetas por foto (judges)"].status == "pass"
    assert [c.status for c in checks if c.status == "fail"] == ["fail"]
    assert "grupo 1" in by_name["todos los tags presentes al menos una vez"].detail
    assert by_name["objetivos por tag de docs/SHOTLIST.md"].status == "info" and "grupo 1/20" in by_name["objetivos por tag de docs/SHOTLIST.md"].detail
    assert by_name["thresholds.json L4.tags incompleto"].status == "info" and "grupo" in by_name["thresholds.json L4.tags incompleto"].detail
    assert by_name["máscaras (masks)"].status == "info"
    kappa_check = by_name["consenso por mayoría y Fleiss κ"]
    assert "5/6 fotos con consenso en una combinación" in kappa_check.detail and "Fleiss κ = 0.741" in kappa_check.detail
    assert "\"ninguna\" por mayoría: photo5.jpg" in kappa_check.detail and "sin consenso" not in kappa_check.detail
    assert ml.main(["check", "--golden-dir", str(golden)]) == 1
    out = capsys.readouterr().out
    assert "golden-check: FAIL (" in out and "falla: fotos >= 50" in out
    # sha256 corrupto en el manifest + HEIC en el directorio + tag ausente + juez que falta: todos fallan.
    manifest["photos"][0]["sha256"] = "0" * 64
    manifest["photos"][1]["labels"].pop("carl")
    for e in manifest["photos"]:
        e["tags"] = [t for t in e["tags"] if t not in ("blanco", "grupo")]
    (golden / "manifest.json").write_text(json.dumps(manifest))
    (golden / "fake.heic").write_bytes(b"\x00\x00\x00\x18ftypheic" + b"\x00" * 32)
    ok, checks = ml.check(golden, l3.load_thresholds(), log=lambda *_: None)
    by_name = {c.name: c for c in checks}
    assert ok is False
    assert by_name["fotos: sha256, PNG/JPEG sRGB, lado <= 256 px, sin HEIC"].status == "fail" and "photo0.png: sha256" in by_name["fotos: sha256, PNG/JPEG sRGB, lado <= 256 px, sin HEIC"].detail
    assert by_name["ficheros HEIC en el directorio"].status == "fail"
    assert by_name["todos los tags presentes al menos una vez"].status == "fail" and "faltan: blanco, grupo" in by_name["todos los tags presentes al menos una vez"].detail
    assert by_name["3 etiquetas por foto (judges)"].status == "fail" and "photo1.png (2)" in by_name["3 etiquetas por foto (judges)"].detail
    # Sin manifest: fail con mensaje.
    (golden / "manifest.json").unlink()
    ok, checks = ml.check(golden, {}, log=lambda *_: None)
    assert ok is False and checks[0].status == "fail" and "falta" in checks[0].detail


def test_collect_photos_rejects_bad_files(golden: Path):
    photos, problems = lp.collect_photos(golden)
    assert [p["file"] for p in photos] == ["photo0.png", "photo1.png", "photo2.jpg", "photo3.png", "photo4.png", "photo5.jpg"]
    assert all(p["width"] == 256 and p["format"] in ("PNG", "JPEG") for p in photos) and problems == []
    Image.new("RGB", (300, 100)).save(golden / "grande.png")
    (golden / "fake.heic").write_bytes(b"\x00\x00\x00\x18ftypheic" + b"\x00" * 32)
    _photos, problems = lp.collect_photos(golden)
    assert len(problems) == 2 and any("HEIC" in p for p in problems) and any("supera 256" in p for p in problems)


def test_check_html_and_build_without_engine(golden: Path):
    dictionary = nm.load_json(lp.DEFAULT_DICTIONARY)
    view = {"key": "none", "label": "Foto completa", "hits": [{"id": 1, "score": 0.5}], "swatches": [{"hex": "#112233", "weight": 1.0}], "ambiguous": 0}
    photos = [{"i": 0, "file": "photo__PHOTOS__.png", "sha256": "ab" * 32, "mime": "image/png", "width": 256, "height": 256,
               "views": [view], "default_view": "none"}]
    names = [{"id": 1, "lang": "es", "name": "Alba <b>", "notes": "", "status": "done"}, {"id": 2, "lang": "es", "name": "", "notes": "", "status": "pending"}]
    meta = {"generated_at": "2026-09-15", "engine": "0.1.0", "top": 10, "golden_name": "g", "n": 1, "set_hash": "abc", "tags": TAGS}
    html = lp.build_html(photos, ["AAAA"], dictionary, names, TAGS, meta)
    assert lp.check_html(html, n_photos=1) == []
    assert html.startswith("<!DOCTYPE html>") and 'lang="es"' in html
    assert '"1":"Alba <b>"' in html and '"2"' not in html.split("const NAMES = ")[1].split("\n")[0]
    assert "Nº 001 · Alba &lt;b&gt;" in html  # bloque estático escapado
    assert "fetch" not in lp.HTML_TEMPLATE and "fetch" not in html and "<script src" not in html and "<link" not in html
    assert "tres jueces" in html and "mayoría" in html and "Ninguna de estas" in html and "persona más grande" in html
    assert '"grupo"' in html and '"grupo":"grupo (varias personas)"' in html
    # Un marcador dentro de un nombre de fichero no se sustituye (una sola pasada sobre la plantilla).
    assert 'data-file="photo__PHOTOS__.png"' in html and html.count("const PHOTOS = [") == 1
    assert 'src="data:image/png;base64,AAAA"' in html and html.count("AAAA") == 1  # la imagen, una sola vez
    assert lp.check_html(html.replace("</main>", "")) != []
    assert lp.check_html(html, n_photos=2) == ["1 bloques de foto estáticos para 2 fotos"]
    assert any("red" in p for p in lp.check_html(html.replace("</script>", "fetch('x');</script>")))
    assert any("red" in p for p in lp.check_html(html.replace("<main", '<img src="https://x/y.png"><main')))


class _Blocks(HTMLParser):
    """Cuenta los bloques estáticos de foto: <article class="card"> con su <img> y sus <li> de candidatas."""

    def __init__(self) -> None:
        super().__init__()
        self.cards: list[dict] = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "article" and "card" in (a.get("class") or ""):
            self.cards.append({"file": a.get("data-file"), "imgs": 0, "items": 0})
        elif self.cards and tag == "img" and (a.get("src") or "").startswith("data:image/"):
            self.cards[-1]["imgs"] += 1
        elif self.cards and tag == "li":
            self.cards[-1]["items"] += 1


def _payload(html: str) -> list[dict]:
    return json.loads(html.split("const PHOTOS = ", 1)[1].split(";\n", 1)[0])


@pytest.mark.skipif(not CLI_HAS_BATCH, reason=f"sin 'ce batch': {l3.not_implemented_reason(CLI)}")
def test_generate_page_with_real_engine(golden: Path, tmp_path: Path, capsys):
    out = tmp_path / "out" / "index.html"
    rc = lp.generate(golden, out, CLI, 10, lp.DEFAULT_DICTIONARY, lp.DEFAULT_NAMES, TAGS, log=print)
    log = capsys.readouterr().out
    assert rc == 0 and out.is_file() and "6 fotos" in log
    html = out.read_text(encoding="utf-8")
    assert lp.check_html(html, n_photos=6) == []
    payload = _payload(html)
    assert [p["file"] for p in payload] == ["photo0.png", "photo1.png", "photo2.jpg", "photo3.png", "photo4.png", "photo5.jpg"]
    assert all(len(p["views"]) == 1 and len(p["views"][0]["hits"]) == 10 and "error" not in p["views"][0] for p in payload)
    assert all(p["default_view"] == "none" for p in payload)
    # Bandas exactas de la combinación => el top-1 del motor es la combinación (mismo criterio que test_match.c).
    assert [p["views"][0]["hits"][0]["id"] for p in payload] == COMBOS
    assert payload[2]["mime"] == "image/jpeg"
    parser = _Blocks()
    parser.feed(html)
    assert [c["file"] for c in parser.cards] == [p["file"] for p in payload]
    assert all(c["imgs"] == 1 and c["items"] == 10 for c in parser.cards)
    import base64
    assert f'src="data:image/png;base64,{base64.b64encode((golden / "photo0.png").read_bytes()).decode("ascii")}"' in html
    # HEIC falsa y foto > 256 px: se rechazan con mensaje y la página se genera con las 6 válidas (exit 0);
    # con --strict, exit 2 sin escribir.
    (golden / "fake.heic").write_bytes(os.urandom(64))
    Image.new("RGB", (300, 100)).save(golden / "grande.png")
    rc = lp.generate(golden, tmp_path / "out2.html", CLI, 10, lp.DEFAULT_DICTIONARY, lp.DEFAULT_NAMES, TAGS, log=print)
    log = capsys.readouterr().out
    assert rc == 0 and "rechazada: fake.heic: HEIC/HEIF rechazado" in log and "supera 256" in log and "2 rechazadas" in log
    assert len(_payload((tmp_path / "out2.html").read_text(encoding="utf-8"))) == 6
    rc = lp.generate(golden, tmp_path / "out3.html", CLI, 10, lp.DEFAULT_DICTIONARY, lp.DEFAULT_NAMES, TAGS, log=print, strict=True)
    assert rc == 2 and not (tmp_path / "out3.html").exists()
    capsys.readouterr()
    assert lp.main(["--golden-dir", str(tmp_path / "no-existe"), "--out", str(tmp_path / "x.html")]) == 2
    # --ce explícito inexistente: error claro, no se cae a build/tools/ce.
    assert lp.main(["--golden-dir", str(golden), "--out", str(tmp_path / "y.html"), "--ce", str(tmp_path / "no-ce")]) == 2
    assert "--ce" in capsys.readouterr().out and not (tmp_path / "y.html").exists()


@pytest.mark.skipif(not CLI_HAS_BATCH, reason=f"sin 'ce batch': {l3.not_implemented_reason(CLI)}")
def test_generate_page_with_app_masks(golden: Path, tmp_path: Path, capsys):
    # photo0: máscaras de la app (largest = todo, largest-clothing-skin = mitad izquierda); photo1: una máscara con
    # dimensiones erróneas (se muestra como error de esa vista, sin romper la página).
    _write_pgm(golden / "photo0.largest.pgm")
    _write_pgm(golden / "photo0.largest-clothing-skin.pgm", left_only=True)
    _write_pgm(golden / "photo1.largest.pgm", w=128, h=128)
    out = tmp_path / "index.html"
    assert lp.generate(golden, out, CLI, 10, lp.DEFAULT_DICTIONARY, lp.DEFAULT_NAMES, TAGS, log=print) == 0
    assert "2 con máscaras de la app" in capsys.readouterr().out
    html = out.read_text(encoding="utf-8")
    assert lp.check_html(html, n_photos=6) == []
    p0, p1 = _payload(html)[:2]
    assert [v["key"] for v in p0["views"]] == ["none", "largest-clothing-skin", "largest"] and p0["default_view"] == "largest-clothing-skin"
    masked = p0["views"][1]
    assert masked["mask"] == "photo0.largest-clothing-skin.pgm" and masked["overlay"] and len(masked["hits"]) == 10
    # Con la mitad izquierda la paleta cambia respecto a la foto completa (el motor usó la máscara).
    assert masked["swatches"] != p0["views"][0]["swatches"]
    assert [v["key"] for v in p1["views"]] == ["none", "largest"] and "mide 128x128" in p1["views"][1]["error"] and p1["default_view"] == "none"
    # Y merge_labels las lleva al manifest; golden-check valida existencia y dimensiones.
    labels_dir = _judges_clean(golden)
    manifest, problems = ml.merge(golden, ml.find_labels_files(labels_dir), TAGS, 3)
    photos = {e["file"]: e for e in manifest["photos"]}
    assert photos["photo0.png"]["masks"] == {"largest": "photo0.largest.pgm", "largest-clothing-skin": "photo0.largest-clothing-skin.pgm"}
    assert manifest["n_with_masks"] == 2 and problems == []
    (golden / "manifest.json").write_text(json.dumps(manifest))
    ok, checks = ml.check(golden, l3.load_thresholds(), log=lambda *_: None)
    masks_check = [c for c in checks if c.name.startswith("máscaras (masks):")][0]
    assert masks_check.status == "fail" and "photo1.png: máscara largest: photo1.largest.pgm mide 128x128 y la foto 256x256" in masks_check.detail
    _write_pgm(golden / "photo1.largest.pgm")
    manifest["photos"][0]["masks"]["allPeople"] = "no-existe.pgm"
    (golden / "manifest.json").write_text(json.dumps(manifest))
    ok, checks = ml.check(golden, l3.load_thresholds(), log=lambda *_: None)
    masks_check = [c for c in checks if c.name.startswith("máscaras (masks):")][0]
    assert masks_check.status == "fail" and "no-existe.pgm no existe" in masks_check.detail and "photo1" not in masks_check.detail
    del manifest["photos"][0]["masks"]["allPeople"]
    (golden / "manifest.json").write_text(json.dumps(manifest))
    ok, checks = ml.check(golden, l3.load_thresholds(), log=lambda *_: None)
    assert [c.status for c in checks if c.name.startswith("máscaras (masks):")] == ["pass"]
    # Una fusión posterior conserva las máscaras declaradas a mano en el manifest anterior.
    manifest["photos"][2]["masks"] = {"custom": "photo0.largest.pgm"}
    (golden / "manifest.json").write_text(json.dumps(manifest))
    again, _ = ml.merge(golden, ml.find_labels_files(labels_dir), TAGS, 3)
    assert {e["file"]: e.get("masks") for e in again["photos"]}["photo2.jpg"] == {"custom": "photo0.largest.pgm"}


def test_discover_masks_and_pgm_header(tmp_path: Path):
    for name in ("a.png", "a.b.png"):
        Image.new("RGB", (4, 4)).save(tmp_path / name)
    for name in ("a.largest.pgm", "a.b.largest.pgm", "a.b.c.d.pgm", "huerfana.pgm"):
        _write_pgm(tmp_path / name, 4, 4)
    found, orphans = ml.discover_masks(tmp_path, ["a.png", "a.b.png"])
    assert found == {"a.png": {"largest": "a.largest.pgm"}, "a.b.png": {"largest": "a.b.largest.pgm"}}
    assert orphans == ["a.b.c.d.pgm", "huerfana.pgm"]
    assert ml.read_pgm_header(tmp_path / "a.largest.pgm") == (4, 4, 255)
    (tmp_path / "comentada.pgm").write_bytes(b"P5\n# comentario\n4 4\n255\n" + bytes(16))
    assert ml.read_pgm_header(tmp_path / "comentada.pgm") == (4, 4, 255)
    (tmp_path / "corta.pgm").write_bytes(b"P5\n4 4\n255\n" + bytes(10))
    with pytest.raises(ValueError, match="truncado"):
        ml.read_pgm_header(tmp_path / "corta.pgm")
    (tmp_path / "ppm.pgm").write_bytes(b"P6\n4 4\n255\n" + bytes(48))
    with pytest.raises(ValueError, match="no es PGM"):
        ml.read_pgm_header(tmp_path / "ppm.pgm")
    problems = ml.validate_masks(tmp_path, {"file": "a.png", "masks": {"bad variant": "a.largest.pgm", "x": "../fuera.pgm", "y": "a.png"}}, (4, 4))
    assert len(problems) == 3 and "inválida" in problems[0]
    assert ml.validate_masks(tmp_path, {"file": "a.png", "masks": ["a.largest.pgm"]}, (4, 4)) == ["a.png: 'masks' debe ser {variante: fichero.pgm}"]


def test_resolve_tags_and_unlabeled_photos(golden: Path):
    tags, missing = ml.resolve_tags({"tags": ["negro", "denim", "gris", "interior", "fondo-sucio", "blanco", "extra"]})
    assert tags == [*TAGS, "extra"] and missing == ["grupo"]
    assert ml.resolve_tags({}) == (TAGS, [])
    # Una foto nueva sin etiquetas no entra en el manifest (l4.load_manifest exige labels no vacío) y se reporta.
    labels_dir = _judges_clean(golden)
    Image.new("RGB", (256, 256), (10, 20, 30)).save(golden / "zz-nueva.png")
    manifest, problems = ml.merge(golden, ml.find_labels_files(labels_dir), TAGS, 3)
    assert manifest["unlabeled"] == ["zz-nueva.png"] and manifest["n_photos"] == 6
    assert any("sin ninguna etiqueta válida" in p for p in problems)
    (golden / "manifest.json").write_text(json.dumps(manifest))
    assert len(l4.load_manifest(golden)) == 6


def test_shotlist_doc_matches_tags_and_targets():
    """docs/SHOTLIST.md y las herramientas usan los mismos siete tags y objetivos por tag."""
    import re

    text = (ml.l4.REPO_ROOT / "docs" / "SHOTLIST.md").read_text(encoding="utf-8")
    rows = dict(re.findall(r"^\| `([a-z-]+)` \| (?:\*\*)?(\d+)", text, flags=re.M))
    assert list(rows) == ml.GOLDEN_TAGS == TAGS
    assert {t: int(n) for t, n in rows.items()} == ml.SHOTLIST_TARGETS
    assert "Objetivo: 100 fotos. Mínimo: 50" in text and "$COLORSAPP_GOLDEN_DIR" in text
    assert "persona más grande" in text and "Exportar diagnóstico" in text and "nunca en el repo" in text
    assert lp.DEFAULT_TAGS == ml.GOLDEN_TAGS
