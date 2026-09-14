"""Tests del generador del diccionario de Wada (``oracle.build_dictionary``).

Cubren: invariantes del fuente, forma de los artefactos, idempotencia byte a byte,
que los artefactos del repo estén al día (equivalente a ``--check``), que la plantilla
de nombres nunca se sobreescriba, que el header C compile solo con flags estrictas, y
la capa de overrides (validación, aplicación con recálculo de hex, efecto sobre
``dict_version`` y sobre el estado de las erratas), ``collection`` y ``dict_version``.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path

import pytest

from oracle import build_dictionary as bd

SELFTEST_C = r"""
#include <stdio.h>
#include "ce_dict_data.h"

_Static_assert(sizeof(ce_dict_data_combos) / sizeof(ce_dict_data_combos[0]) == CE_DICT_NUM_COMBOS, "combos");
_Static_assert(sizeof(ce_dict_data_rgb) / sizeof(ce_dict_data_rgb[0]) == CE_DICT_NUM_COLORS, "rgb");
_Static_assert(sizeof(ce_dict_data_names) / sizeof(ce_dict_data_names[0]) == CE_DICT_NUM_COLORS, "names");
_Static_assert(sizeof(ce_dict_data_swatch) / sizeof(ce_dict_data_swatch[0]) == CE_DICT_NUM_COLORS, "swatch");
_Static_assert(sizeof(CE_DICT_VERSION) == 13, "dict_version de 12 hex");

int main(void) {
    unsigned hist[CE_DICT_MAX_COLORS + 1] = {0};
    for (unsigned i = 0; i < CE_DICT_NUM_COMBOS; i++) {
        const ce_dict_data_combo *c = &ce_dict_data_combos[i];
        if (c->id != i + 1) return 10;
        if (c->size < 2 || c->size > CE_DICT_MAX_COLORS) return 11;
        for (unsigned k = 0; k < CE_DICT_MAX_COLORS; k++) {
            if (k < c->size) {
                if (c->colors[k] >= CE_DICT_NUM_COLORS) return 12;
                if (k > 0 && c->colors[k] <= c->colors[k - 1]) return 13;
            } else if (c->colors[k] != CE_DICT_NONE) {
                return 14;
            }
        }
        hist[c->size]++;
    }
    for (unsigned i = 0; i < CE_DICT_NUM_COLORS; i++) {
        if (ce_dict_data_swatch[i] >= CE_DICT_NUM_SWATCHES) return 15;
        if (ce_dict_data_names[i][0] == '\0') return 16;
    }
    printf("%u %u %u %u %u %u %s %s\n", hist[2], hist[3], hist[4],
           ce_dict_data_rgb[0][0], ce_dict_data_rgb[0][1], ce_dict_data_rgb[0][2],
           ce_dict_data_names[0], CE_DICT_VERSION);
    return 0;
}
"""

CC_FLAGS = ["-std=c11", "-Wall", "-Wextra", "-Werror"]


# --------------------------------------------------------------------------------------
# Fixtures
# --------------------------------------------------------------------------------------


@pytest.fixture(scope="module")
def colors() -> list[dict]:
    return bd.load_source(bd.DEFAULT_SOURCE)


@pytest.fixture(scope="module")
def dictionary(colors) -> dict:
    return bd.build_dictionary(colors)


@pytest.fixture(scope="module")
def repo_overrides() -> list[dict]:
    return bd.load_overrides(bd.DEFAULT_OUT_DIR / bd.OVERRIDES_NAME)


@pytest.fixture(scope="module")
def outputs(colors, repo_overrides) -> bd.Outputs:
    # Sin ICC: salida independiente de la máquina. Con los overrides del repo (hoy ninguno).
    return bd.generate_outputs(colors, profile=None, use_icc=False, overrides=repo_overrides)


def read_json(path: Path) -> dict | list:
    return json.loads(path.read_text(encoding="utf-8"))


ISO_DATE = "2026-09-14"


def run_cli(*args: str, cwd: Path = bd.REPO_ROOT) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "oracle.build_dictionary", *args],
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )


# --------------------------------------------------------------------------------------
# Validación del fuente
# --------------------------------------------------------------------------------------


def test_source_is_valid_with_only_known_warnings(colors):
    report = bd.validate_source(colors)
    assert report.errors == []
    assert any("Dull Violet Black" in w and "106" in w for w in report.warnings)
    assert len(report.warnings) == 3  # M=106 + dos nombres con errata


def test_counts(colors):
    assert len(colors) == 159
    members = bd.invert_combinations(colors)
    assert list(members) == list(range(1, 349))
    assert dict(Counter(len(v) for v in members.values())) == {2: 120, 3: 120, 4: 108}
    assert sum(len(v) for v in members.values()) == 1032


def test_hex_unique_and_matches_rgb(colors):
    hexes = [c["hex"] for c in colors]
    assert len(set(hexes)) == len(hexes)
    for c in colors:
        assert c["hex"] == "#{:02x}{:02x}{:02x}".format(*c["rgb"])


def test_every_color_in_at_least_one_combination(colors):
    assert all(len(c["combinations"]) >= 1 for c in colors)


def test_cmyk_range_except_known_erratum(colors):
    out_of_range = [(c["name"], c["cmyk"]) for c in colors if any(not 0 <= v <= 100 for v in c["cmyk"])]
    assert out_of_range == [("Dull Violet Black", [95, 106, 38, 50])]


def test_swatch_range(colors):
    assert all(0 <= c["swatch"] < bd.NUM_SWATCHES for c in colors)


@pytest.mark.parametrize(
    "mutate, fragment",
    [
        (lambda cs: cs.pop(), "se esperaban 159"),
        (lambda cs: cs[1].__setitem__("hex", cs[0]["hex"]), "hex duplicado"),
        (lambda cs: cs[0].__setitem__("hex", "#000000"), "no coincide con rgb"),
        (lambda cs: cs[0].__setitem__("cmyk", [0, 101, 0, 0]), "fuera de 0..100"),
        (lambda cs: cs[0].__setitem__("combinations", []), "ninguna combinación"),
        (lambda cs: cs[0]["combinations"].append(349), "fuera de 1..348"),
        (lambda cs: cs[0]["combinations"].remove(176), "histograma"),
    ],
)
def test_validation_detects_corruption(colors, mutate, fragment):
    corrupted = json.loads(json.dumps(colors))
    mutate(corrupted)
    report = bd.validate_source(corrupted)
    assert any(fragment in e for e in report.errors), report.errors


# --------------------------------------------------------------------------------------
# dictionary.json
# --------------------------------------------------------------------------------------


def test_dictionary_shape(dictionary, colors):
    assert set(dictionary) == {
        "schema",
        "source",
        "generated_by",
        "status",
        "dict_version",
        "colors",
        "combinations",
    }
    assert dictionary["schema"] == 1
    assert dictionary["status"] == "provisional"
    assert dictionary["generated_by"] == "oracle.build_dictionary"
    assert "MIT" in dictionary["source"]
    assert len(dictionary["colors"]) == 159
    assert len(dictionary["combinations"]) == 348
    first = dictionary["colors"][0]
    assert first == {
        "index": 0,
        "name": "Hermosa Pink",
        "hex": "#f9c1ce",
        "rgb": [249, 193, 206],
        "cmyk": [0, 30, 6, 0],
        "swatch": 0,
    }
    for index, entry in enumerate(dictionary["colors"]):
        assert entry["index"] == index
        assert "lab" not in entry


def test_dictionary_combinations_sorted_and_consistent(dictionary, colors):
    for combo in dictionary["combinations"]:
        assert set(combo) == {"id", "size", "colors", "collection"}
        assert combo["collection"] is None  # curación futura del usuario
        assert combo["colors"] == sorted(combo["colors"])
        assert len(set(combo["colors"])) == combo["size"] == len(combo["colors"])
        assert 2 <= combo["size"] <= bd.MAX_COLORS
        for index in combo["colors"]:
            assert combo["id"] in colors[index]["combinations"]
    assert [c["id"] for c in dictionary["combinations"]] == list(range(1, 349))


def test_json_is_sorted_and_indented(outputs):
    text = outputs.dictionary.decode("utf-8")
    assert text.startswith('{\n  "colors": [\n')
    assert text.endswith("}\n")
    doc = json.loads(text)
    assert json.dumps(doc, indent=2, sort_keys=True, ensure_ascii=False) + "\n" == text


# --------------------------------------------------------------------------------------
# dict_version
# --------------------------------------------------------------------------------------


def test_dict_version_is_short_sha256_of_canonical_content(dictionary):
    version = dictionary["dict_version"]
    assert len(version) == 12 and all(c in "0123456789abcdef" for c in version)
    assert version == bd.compute_dict_version(dictionary["colors"], dictionary["combinations"])
    # No depende de metadatos ni del formato: solo de colors + combinations.
    canonical = json.dumps(
        {"colors": dictionary["colors"], "combinations": dictionary["combinations"]},
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    import hashlib

    assert version == hashlib.sha256(canonical).hexdigest()[:12]


def test_dict_version_tracks_colors_and_collections(dictionary):
    base = bd.compute_dict_version(dictionary["colors"], dictionary["combinations"])
    colors = json.loads(json.dumps(dictionary["colors"]))
    colors[0]["rgb"][0] ^= 1
    assert bd.compute_dict_version(colors, dictionary["combinations"]) != base
    combos = json.loads(json.dumps(dictionary["combinations"]))
    combos[0]["collection"] = "Japón"
    assert bd.compute_dict_version(dictionary["colors"], combos) != base
    assert bd.compute_dict_version(dictionary["colors"], dictionary["combinations"]) == base


def test_dict_version_consistent_across_repo_artifacts(outputs):
    """dictionary.json, ce_dict_data.h y golden_wada_lab.tsv llevan la misma versión."""
    on_disk = read_json(bd.DEFAULT_OUT_DIR / bd.DICTIONARY_NAME)
    assert on_disk["dict_version"] == outputs.dict_version
    header = bd.DEFAULT_HEADER.read_text(encoding="ascii")
    assert f'#define CE_DICT_VERSION "{outputs.dict_version}"' in header
    golden = bd.REPO_ROOT / "engine" / "tests" / "data" / "golden_wada_lab.tsv"
    assert golden.is_file(), "falta engine/tests/data/golden_wada_lab.tsv (make golden)"
    versions = [
        line.split(":", 1)[1].strip()
        for line in golden.read_text(encoding="utf-8").splitlines()
        if line.startswith("# dict_version:")
    ]
    assert versions == [outputs.dict_version], "golden_wada_lab.tsv desactualizado: make dict && make golden"
    rows = [l for l in golden.read_text(encoding="utf-8").splitlines() if l and not l.startswith("#")]
    assert len(rows) == 159


# --------------------------------------------------------------------------------------
# overrides.json
# --------------------------------------------------------------------------------------


def test_overrides_template_and_repo_file():
    assert bd.build_overrides_template() == {"schema": 1, "overrides": []}
    path = bd.DEFAULT_OUT_DIR / bd.OVERRIDES_NAME
    assert path.is_file()
    doc = read_json(path)
    assert doc["schema"] == 1 and isinstance(doc["overrides"], list)
    assert bd.validate_overrides(doc["overrides"], bd.load_source()) == []


def test_overrides_file_is_never_overwritten(tmp_path, outputs):
    out_dir = tmp_path / "wada"
    out_dir.mkdir()
    path = out_dir / bd.OVERRIDES_NAME
    custom = b'{"schema": 1, "overrides": []}\n'
    path.write_bytes(custom)
    bd.write_outputs(outputs, out_dir, tmp_path / "h.h", emit_c=False)
    assert path.read_bytes() == custom


def _override(index, field_name, value, reason="test", accepted_at=ISO_DATE) -> dict:
    return {"index": index, "field": field_name, "value": value, "reason": reason, "accepted_at": accepted_at}


@pytest.mark.parametrize(
    "override, fragment",
    [
        (_override(159, "rgb", [1, 2, 3]), "fuera de 0..158"),
        (_override(-1, "rgb", [1, 2, 3]), "fuera de 0..158"),
        (_override(0, "lab", [1, 2, 3]), "no es uno de"),
        (_override(0, "rgb", [1, 2]), "enteros 0..255"),
        (_override(0, "rgb", [1, 2, 256]), "enteros 0..255"),
        (_override(0, "cmyk", [0, 30, 6, 101]), "enteros 0..100"),
        (_override(0, "name", ""), "ASCII no vacío"),
        (_override(0, "name", "Rosa Hermosa"), None),  # válido
        (_override(0, "rgb", [249, 193, 206]), "idéntico al fuente"),
        (_override(0, "rgb", [1, 2, 3], reason=""), "reason"),
        (_override(0, "rgb", [1, 2, 3], accepted_at="ayer"), "accepted_at"),
        ({"index": 0, "field": "rgb", "value": [1, 2, 3]}, "faltan claves"),
        ({**_override(0, "rgb", [1, 2, 3]), "extra": 1}, "claves desconocidas"),
    ],
)
def test_validate_overrides(colors, override, fragment):
    errors = bd.validate_overrides([override], colors)
    if fragment is None:
        assert errors == []
    else:
        assert any(fragment in e for e in errors), errors


def test_validate_overrides_rejects_duplicates(colors):
    dup = [_override(0, "rgb", [1, 2, 3]), _override(0, "rgb", [4, 5, 6])]
    assert any("repetido" in e for e in bd.validate_overrides(dup, colors))


def test_apply_overrides_recomputes_hex_and_keeps_source(colors):
    before = json.dumps(colors)
    result = bd.apply_overrides(colors, [_override(0, "rgb", [1, 2, 3]), _override(115, "name", "Calamine Blue")])
    assert json.dumps(colors) == before  # el fuente en memoria no cambia
    assert result[0]["rgb"] == [1, 2, 3] and result[0]["hex"] == "#010203"
    assert result[115]["name"] == "Calamine Blue"
    assert result[1] == colors[1]


def test_override_changes_rgb_hex_and_dict_version(tmp_path, colors, outputs):
    """Un override rgb en un tmp cambia rgb/hex, dict_version, el header C y la errata."""
    out_dir = tmp_path / "wada"
    out_dir.mkdir()
    header = tmp_path / "engine" / "ce_dict_data.h"
    overrides = [
        _override(0, "rgb", [1, 2, 3], reason="prueba"),
        _override(115, "name", "Calamine Blue", reason="PR #2 aceptado"),
    ]
    (out_dir / bd.OVERRIDES_NAME).write_bytes(bd.dump_json({"schema": 1, "overrides": overrides}))
    common = ["--source", str(bd.DEFAULT_SOURCE), "--out-dir", str(out_dir), "--header", str(header), "--no-icc"]
    result = run_cli("--emit-c", *common)
    assert result.returncode == 0, result.stderr
    assert "overrides: 2 aplicado(s)" in result.stdout

    doc = read_json(out_dir / bd.DICTIONARY_NAME)
    assert doc["colors"][0]["rgb"] == [1, 2, 3]
    assert doc["colors"][0]["hex"] == "#010203"
    assert doc["colors"][115]["name"] == "Calamine Blue"
    assert doc["colors"][1] == json.loads(outputs.dictionary)["colors"][1]
    assert doc["dict_version"] != outputs.dict_version
    assert doc["dict_version"] == bd.compute_dict_version(doc["colors"], doc["combinations"])
    assert f'#define CE_DICT_VERSION "{doc["dict_version"]}"' in header.read_text(encoding="ascii")
    assert "{  1,   2,   3}, /*   0 Hermosa Pink */" in header.read_text(encoding="ascii")

    errata = {e["index"]: e for e in read_json(out_dir / bd.ERRATA_NAME)["errata"]}
    assert errata[115]["status"] == "accepted"
    assert errata[115]["accepted_at"] == ISO_DATE
    assert errata[115]["override_value"] == "Calamine Blue"
    assert errata[115]["dataset_value"] == "Calamine BLue"  # el fuente sigue documentado tal cual
    assert all(e["status"] == "pending" for i, e in errata.items() if i != 115)

    # --check con los mismos overrides está al día; el mismo override es idempotente.
    ok = run_cli("--check", "--emit-c", *common)
    assert ok.returncode == 0, ok.stderr


def test_override_that_breaks_coherence_is_rejected(tmp_path, colors):
    """Un rgb igual al de otro color duplica el hex: el generador lo rechaza (exit 2)."""
    out_dir = tmp_path / "wada"
    out_dir.mkdir()
    dup_rgb = list(colors[1]["rgb"])
    (out_dir / bd.OVERRIDES_NAME).write_bytes(
        bd.dump_json({"schema": 1, "overrides": [_override(0, "rgb", dup_rgb)]})
    )
    with pytest.raises(ValueError, match="hex duplicado"):
        bd.generate_outputs(colors, profile=None, use_icc=False, overrides=[_override(0, "rgb", dup_rgb)])
    result = run_cli("--source", str(bd.DEFAULT_SOURCE), "--out-dir", str(out_dir), "--no-icc")
    assert result.returncode == 2
    assert "hex duplicado" in result.stderr


def test_invalid_overrides_file_exits_2(tmp_path):
    out_dir = tmp_path / "wada"
    out_dir.mkdir()
    (out_dir / bd.OVERRIDES_NAME).write_bytes(
        bd.dump_json({"schema": 1, "overrides": [_override(0, "rgb", [1, 2, 3], accepted_at="ayer")]})
    )
    result = run_cli("--source", str(bd.DEFAULT_SOURCE), "--out-dir", str(out_dir), "--no-icc")
    assert result.returncode == 2
    assert "accepted_at" in result.stderr


# --------------------------------------------------------------------------------------
# errata.json y names.es.json
# --------------------------------------------------------------------------------------


def test_errata_entries_match_source(colors, outputs):
    doc = json.loads(outputs.errata)
    assert doc["conversion_profile"] is None
    assert len(doc["errata"]) == 6
    for entry in doc["errata"]:
        assert entry["status"] == "pending"
        assert colors[entry["index"]]["name"] == entry["color"]
        assert colors[entry["index"]][entry["field"]] == entry["dataset_value"]
        assert entry["dataset_value"] != entry["book_value"]
        assert "derived_rgb_candidate" not in entry
    by_color = {e["color"]: e for e in doc["errata"]}
    assert by_color["Dull Violet Black"]["book_value"] == [100, 90, 38, 50]
    assert by_color["Mars Brown Tobacco"]["book_value"] == "Mars Brown/Tobacco"
    assert by_color["Calamine BLue"]["book_value"] == "Calamine Blue"


def test_errata_out_of_sync_is_detected(colors):
    modified = json.loads(json.dumps(colors))
    modified[71]["cmyk"] = [36, 32, 100, 7]  # "corregir" Citrine invalida la errata
    with pytest.raises(ValueError, match="desincronizada"):
        bd.build_errata(modified, profile=None)


def test_names_template_shape():
    template = bd.build_names_template()
    assert len(template) == 348
    assert template[0] == {"id": 1, "name": "", "lang": "es", "status": "pending", "notes": ""}
    assert [e["id"] for e in template] == list(range(1, 349))


def test_names_template_is_never_overwritten(tmp_path, outputs):
    out_dir = tmp_path / "wada"
    out_dir.mkdir()
    names = out_dir / bd.NAMES_NAME
    curated = b'[{"id": 1, "name": "Curado", "lang": "es", "status": "done", "notes": ""}]\n'
    names.write_bytes(curated)
    bd.write_outputs(outputs, out_dir, tmp_path / "h.h", emit_c=False)
    assert names.read_bytes() == curated


def test_names_file_in_repo_is_well_formed():
    path = bd.DEFAULT_OUT_DIR / bd.NAMES_NAME
    assert path.is_file()
    assert bd.validate_names_file(path) == []


# --------------------------------------------------------------------------------------
# Idempotencia y artefactos al día
# --------------------------------------------------------------------------------------


def test_two_runs_produce_identical_bytes(tmp_path, colors):
    results = []
    for n in range(2):
        out_dir = tmp_path / f"run{n}"
        header = out_dir / "ce_dict_data.h"
        outs = bd.generate_outputs(colors, profile=None, use_icc=False)
        bd.write_outputs(outs, out_dir, header, emit_c=True)
        results.append({p.name: p.read_bytes() for p in list(out_dir.iterdir())})
    assert results[0] == results[1]
    assert set(results[0]) == {
        bd.DICTIONARY_NAME,
        bd.ERRATA_NAME,
        bd.CONVERSION_CHECK_NAME,
        bd.NAMES_NAME,
        bd.OVERRIDES_NAME,
        "ce_dict_data.h",
    }


def test_repo_artifacts_are_up_to_date(outputs):
    """Equivalente a ``--check`` sobre el repo: falla si alguien olvidó regenerar."""
    diffs = bd.check_outputs(outputs, bd.DEFAULT_OUT_DIR, bd.DEFAULT_HEADER, emit_c=True)
    assert diffs == []


def test_cli_check_exit_codes(tmp_path):
    out_dir = tmp_path / "wada"
    header = tmp_path / "engine" / "ce_dict_data.h"
    common = ["--source", str(bd.DEFAULT_SOURCE), "--out-dir", str(out_dir), "--header", str(header), "--no-icc"]

    missing = run_cli("--check", "--emit-c", *common)
    assert missing.returncode == 1, missing.stderr

    generated = run_cli("--emit-c", *common)
    assert generated.returncode == 0, generated.stderr
    assert header.is_file()

    ok = run_cli("--check", "--emit-c", *common)
    assert ok.returncode == 0, ok.stderr

    tampered = out_dir / bd.DICTIONARY_NAME
    tampered.write_bytes(tampered.read_bytes().replace(b"Hermosa Pink", b"Hermosa Rosa"))
    bad = run_cli("--check", "--emit-c", *common)
    assert bad.returncode == 1
    assert "dictionary.json" in bad.stderr


def test_cli_rejects_invalid_source(tmp_path):
    broken = tmp_path / "colors.json"
    broken.write_text("[]", encoding="utf-8")
    result = run_cli("--source", str(broken), "--out-dir", str(tmp_path / "out"), "--no-icc")
    assert result.returncode == 2
    assert "159" in result.stderr


# --------------------------------------------------------------------------------------
# Header C
# --------------------------------------------------------------------------------------


def test_header_text(outputs):
    text = outputs.header.decode("ascii")  # debe ser ASCII puro
    assert "GENERADO por oracle.build_dictionary, no editar" in text
    assert "#define CE_DICT_NUM_COLORS 159" in text
    assert "#define CE_DICT_NUM_COMBOS 348" in text
    assert "#define CE_DICT_MAX_COLORS 7" in text
    assert f'#define CE_DICT_VERSION "{outputs.dict_version}"' in text
    assert "static const uint8_t ce_dict_data_rgb[CE_DICT_NUM_COLORS][3]" in text
    assert "static const char *const ce_dict_data_names[CE_DICT_NUM_COLORS]" in text
    assert "static const uint8_t ce_dict_data_swatch[CE_DICT_NUM_COLORS]" in text
    assert "static const ce_dict_data_combo ce_dict_data_combos[CE_DICT_NUM_COMBOS]" in text
    assert "uint8_t colors[CE_DICT_MAX_COLORS];" in text
    assert '"Vandar Poel\'s Blue"' in text
    # Sin tablas Lab ni datos en coma flotante: el motor deriva todo desde sRGB8.
    assert "ce_dict_color_lab" not in text
    assert "double" not in text and "float" not in text


@pytest.fixture(scope="module")
def cc() -> str:
    compiler = shutil.which("cc") or shutil.which("clang") or shutil.which("gcc")
    if compiler is None:
        pytest.skip("no hay compilador C en PATH")
    return compiler


def test_header_compiles_standalone(tmp_path, outputs, cc):
    """Un .c que solo incluye el header compila con -std=c11 -Wall -Wextra -Werror."""
    (tmp_path / "ce_dict_data.h").write_bytes(outputs.header)
    source = tmp_path / "only_include.c"
    source.write_text('#include "ce_dict_data.h"\n', encoding="ascii")
    result = subprocess.run(
        [cc, *CC_FLAGS, "-I", str(tmp_path), "-c", str(source), "-o", str(tmp_path / "only_include.o")],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr


def test_header_selftest_runs(tmp_path, outputs, cc):
    """Programa C que recorre las tablas y comprueba las invariantes desde el lado C."""
    (tmp_path / "ce_dict_data.h").write_bytes(outputs.header)
    source = tmp_path / "selftest.c"
    source.write_text(SELFTEST_C, encoding="ascii")
    exe = tmp_path / "selftest"
    build = subprocess.run(
        [cc, *CC_FLAGS, "-I", str(tmp_path), str(source), "-o", str(exe)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert build.returncode == 0, build.stderr
    run = subprocess.run([str(exe)], capture_output=True, text=True, check=False)
    assert run.returncode == 0, f"selftest devolvió {run.returncode}"
    assert run.stdout.strip() == f"120 120 108 249 193 206 Hermosa Pink {outputs.dict_version}"


# --------------------------------------------------------------------------------------
# Conversión CMYK -> sRGB (solo si hay perfil SWOP en la máquina)
# --------------------------------------------------------------------------------------


def test_percent_to_byte_matches_mattdesl_scaling():
    assert bd.percent_to_byte(0) == 0
    assert bd.percent_to_byte(100) == 255
    assert bd.percent_to_byte(30) == 76  # round(76.5) -> 76 (redondeo de Python, como mattdesl)
    assert bd.percent_to_byte(106) == 255  # M=106 se satura


def test_swop_reconversion_reproduces_source(colors):
    profile = bd.find_swop_profile()
    if profile is None:
        pytest.skip("sin perfil ICC SWOP en esta máquina (ver data/wada/CONVERSION_CHECK.md)")
    stats = bd.compare_conversion(colors, profile)
    assert stats.max_abs <= 2, stats.max_per_channel
