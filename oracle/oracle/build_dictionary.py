"""Construye el diccionario de Sanzo Wada para el motor de color.

Entrada: ``data/wada/source/colors.json`` (copia MIT sin modificar de
mattdesl/dictionary-of-colour-combinations 1.0.2; ver ``data/wada/source/PROVENANCE.md``).

Salidas (todas deterministas: dos ejecuciones producen bytes idénticos):

* ``data/wada/dictionary.json``: 159 colores (sRGB8 + CMYK del libro) y las 348
  combinaciones reconstruidas invirtiendo el campo ``combinations`` del fuente.
  Sin Lab: el motor calcula Lab D65 en C desde sRGB8; el ``lab`` del fuente es D50.
  Cada combinación lleva ``collection`` (``null`` hasta que el usuario cure colecciones).
  La raíz lleva ``dict_version`` (sha256 corto del JSON canónico de colores +
  combinaciones tras aplicar overrides) y ``status`` (``provisional`` hasta cotejar con
  el libro).
* ``data/wada/overrides.json``: capa explícita de correcciones que SOLO edita el usuario
  (p. ej. al aceptar una errata). El generador la aplica sobre el fuente en memoria (el
  fuente nunca se modifica), valida la coherencia del resultado y, si ``field`` es
  ``rgb``, recalcula ``hex``. Solo se crea (vacía) si no existe.
* ``data/wada/errata.json``: discrepancias conocidas frente al libro (solo documentación;
  los valores fuente NO se modifican).
* ``data/wada/CONVERSION_CHECK.md``: informe de la reconversión CMYK -> sRGB cuando hay un
  perfil ICC SWOP disponible en la máquina (si no lo hay, el informe lo dice).
* ``data/wada/names.es.json``: plantilla de 348 nombres a curar. Solo se crea si no existe.
* ``engine/Sources/CColorEngine/ce_dict_data.h`` (con ``--emit-c``): header C generado,
  con ``CE_DICT_VERSION`` igual a ``dict_version`` (el motor lo expone en
  ``ce_dict_version()`` y la app lo cruza con el JSON del bundle).

Uso::

    uv run --project oracle python -m oracle.build_dictionary [--emit-c] [--check]

Códigos de salida: 0 correcto; 1 ``--check`` detectó diferencias con el disco;
2 el fuente (o el fuente con los overrides aplicados) no pasa la validación.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# --------------------------------------------------------------------------------------
# Rutas y constantes
# --------------------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = REPO_ROOT / "data" / "wada" / "source" / "colors.json"
DEFAULT_OUT_DIR = REPO_ROOT / "data" / "wada"
DEFAULT_HEADER = REPO_ROOT / "engine" / "Sources" / "CColorEngine" / "ce_dict_data.h"

DICTIONARY_NAME = "dictionary.json"
ERRATA_NAME = "errata.json"
CONVERSION_CHECK_NAME = "CONVERSION_CHECK.md"
NAMES_NAME = "names.es.json"
OVERRIDES_NAME = "overrides.json"

SCHEMA = 1
OVERRIDES_SCHEMA = 1
#: Campos del fuente que un override puede corregir.
OVERRIDE_FIELDS: tuple[str, ...] = ("cmyk", "rgb", "name")
#: Claves obligatorias de cada override.
OVERRIDE_KEYS: frozenset[str] = frozenset({"index", "field", "value", "reason", "accepted_at"})
#: Estado del diccionario: "provisional" hasta que el usuario lo coteje con el libro
#: (Seigensha Vol. 1) y lo cambie a "book-verified" a mano en esta constante.
DICT_STATUS = "provisional"
#: Longitud de ``dict_version`` (hex del sha256 del JSON canónico).
DICT_VERSION_HEX_LEN = 12
SOURCE_LABEL = "mattdesl/dictionary-of-colour-combinations 1.0.2 (MIT)"
GENERATOR = "oracle.build_dictionary"

EXPECTED_NUM_COLORS = 159
EXPECTED_NUM_COMBOS = 348
EXPECTED_SIZE_HISTOGRAM = {2: 120, 3: 120, 4: 108}
NUM_SWATCHES = 6          # capítulos del libro (campo ``swatch`` 0..5)
MAX_COLORS = 7            # reserva para el Vol. 2 (combinaciones de 3 a 7 colores)
NONE_INDEX = 0xFF         # relleno en ``ce_dict_combo.colors`` más allá de ``size``

ISSUE_1 = "https://github.com/mattdesl/dictionary-of-colour-combinations/issues/1"
PR_2 = "https://github.com/mattdesl/dictionary-of-colour-combinations/pull/2"

# Erratas conocidas del dataset frente al libro impreso (Seigensha 2010/2011).
# Fuente: issue #1 de mattdesl (eesur, 2023-07-03, cotejo con el libro físico) y PR #2
# (jaspervdj). Los índices del issue son 1-based; aquí ``color`` identifica por nombre y el
# índice 0-based se resuelve contra el fuente al generar. Los valores fuente NO se tocan.
KNOWN_ERRATA: tuple[dict[str, Any], ...] = (
    {
        "color": "Citrine",
        "field": "cmyk",
        "dataset_value": [36, 32, 100, 0],
        "book_value": [36, 32, 100, 7],
        "reference": ISSUE_1,
        "notes": "K debería ser 7 según el cotejo con el libro (issue #1, índice 72 1-based).",
    },
    {
        "color": "Rainette Green",
        "field": "cmyk",
        "dataset_value": [42, 20, 62, 10],
        "book_value": [42, 20, 62, 28],
        "reference": ISSUE_1,
        "notes": "K debería ser 28 según el cotejo con el libro (issue #1, índice 97 1-based).",
    },
    {
        "color": "Diamine Green",
        "field": "cmyk",
        "dataset_value": [87, 32, 91, 18],
        "book_value": [87, 20, 100, 10],
        "reference": ISSUE_1,
        "notes": "Solo C coincide con el libro (issue #1, índice 106 1-based).",
    },
    {
        "color": "Dull Violet Black",
        "field": "cmyk",
        "dataset_value": [95, 106, 38, 50],
        "book_value": [100, 90, 38, 50],
        "reference": ISSUE_1,
        "notes": (
            "M=106 es imposible (>100); el libro da C=100, M=90 (issue #1, índice 131 1-based). "
            "El validador acepta este valor fuera de rango solo como errata conocida. "
            "dblodorn/sanzo-wada issue #47: el color se ve verde."
        ),
    },
    {
        "color": "Mars Brown Tobacco",
        "field": "name",
        "dataset_value": "Mars Brown Tobacco",
        "book_value": "Mars Brown/Tobacco",
        "reference": ISSUE_1,
        "notes": "Falta la barra: el libro escribe 'Mars Brown/Tobacco' (issue #1, índice 86 1-based).",
    },
    {
        "color": "Calamine BLue",
        "field": "name",
        "dataset_value": "Calamine BLue",
        "book_value": "Calamine Blue",
        "reference": PR_2,
        "notes": "Errata de mayúscula (PR #2, sin fusionar). Nombre de Ridgway (1912): 'Calamine Blue'.",
    },
)

# Directorios donde buscar un perfil CMYK SWOP (Adobe "U.S. Web Coated (SWOP) v2").
PROFILE_SEARCH_DIRS: tuple[str, ...] = (
    "/System/Library/ColorSync/Profiles",
    "/Library/ColorSync/Profiles",
    "~/Library/ColorSync/Profiles",
    "/Library/Application Support/Adobe/Color/Profiles",
    "~/Library/Application Support/Adobe/Color/Profiles",
)
PROFILE_KEYWORDS = ("swop", "webcoated")
PROFILE_ENV_VAR = "COLORSAPP_SWOP_PROFILE"

# Perfil CMYK genérico de macOS: sirve solo para un anexo informativo del informe, nunca
# para derivar candidatos (no es el perfil con el que mattdesl calculó los rgb).
GENERIC_CMYK_PROFILE = Path("/System/Library/ColorSync/Profiles/Generic CMYK Profile.icc")

_HEX_RE = re.compile(r"^#[0-9a-f]{6}$")


# --------------------------------------------------------------------------------------
# Carga y validación del fuente
# --------------------------------------------------------------------------------------


def load_source(path: Path = DEFAULT_SOURCE) -> list[dict[str, Any]]:
    """Lee ``colors.json`` tal cual (sin normalizar nada)."""
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, list):
        raise ValueError(f"{path}: se esperaba una lista JSON en la raíz")
    return data


@dataclass
class ValidationReport:
    """Resultado de :func:`validate_source`. ``errors`` vacío significa fuente válido."""

    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


def _is_int_list(value: Any, length: int) -> bool:
    return (
        isinstance(value, list)
        and len(value) == length
        and all(isinstance(v, int) and not isinstance(v, bool) for v in value)
    )


def invert_combinations(colors: list[dict[str, Any]]) -> dict[int, list[int]]:
    """id de combinación -> índices de color ascendentes (reconstrucción del fuente)."""
    members: dict[int, list[int]] = {}
    for index, color in enumerate(colors):
        for combo_id in color.get("combinations", []):
            members.setdefault(combo_id, []).append(index)
    return {cid: sorted(idx) for cid, idx in sorted(members.items())}


def validate_source(colors: list[dict[str, Any]]) -> ValidationReport:
    """Aplica todas las invariantes conocidas del dataset de mattdesl.

    Las erratas de ``KNOWN_ERRATA`` (p. ej. M=106 de "Dull Violet Black") se reportan como
    avisos, no como fallos; cualquier otro valor fuera de rango es un fallo.
    """
    report = ValidationReport()
    errors, warnings = report.errors, report.warnings

    if len(colors) != EXPECTED_NUM_COLORS:
        errors.append(f"se esperaban {EXPECTED_NUM_COLORS} colores, hay {len(colors)}")

    known_cmyk = {
        (e["color"], tuple(e["dataset_value"])) for e in KNOWN_ERRATA if e["field"] == "cmyk"
    }
    required = {"name": str, "combinations": list, "swatch": int, "cmyk": list, "rgb": list, "hex": str}
    hex_seen: dict[str, int] = {}
    name_seen: dict[str, int] = {}

    for index, color in enumerate(colors):
        label = f"color[{index}] {color.get('name')!r}"
        if not isinstance(color, dict):
            errors.append(f"{label}: no es un objeto")
            continue
        missing = [k for k, t in required.items() if not isinstance(color.get(k), t)]
        if missing:
            errors.append(f"{label}: campos ausentes o de tipo incorrecto: {missing}")
            continue

        name = color["name"]
        if not name.strip():
            errors.append(f"{label}: nombre vacío")
        if name in name_seen:
            errors.append(f"{label}: nombre duplicado (también en color[{name_seen[name]}])")
        name_seen.setdefault(name, index)

        rgb = color["rgb"]
        if not _is_int_list(rgb, 3) or not all(0 <= v <= 255 for v in rgb):
            errors.append(f"{label}: rgb inválido {rgb!r}")
        hex_value = color["hex"]
        if not _HEX_RE.match(hex_value):
            errors.append(f"{label}: hex inválido {hex_value!r} (se espera '#rrggbb' en minúsculas)")
        elif _is_int_list(rgb, 3) and hex_value != "#{:02x}{:02x}{:02x}".format(*rgb):
            errors.append(f"{label}: hex {hex_value} no coincide con rgb {rgb}")
        if hex_value in hex_seen:
            errors.append(f"{label}: hex duplicado {hex_value} (también en color[{hex_seen[hex_value]}])")
        hex_seen.setdefault(hex_value, index)

        cmyk = color["cmyk"]
        if not _is_int_list(cmyk, 4):
            errors.append(f"{label}: cmyk inválido {cmyk!r}")
        elif not all(0 <= v <= 100 for v in cmyk):
            if (name, tuple(cmyk)) in known_cmyk:
                warnings.append(f"{label}: cmyk fuera de rango {cmyk} (errata conocida, ver errata.json)")
            else:
                errors.append(f"{label}: cmyk fuera de 0..100: {cmyk}")

        swatch = color["swatch"]
        if isinstance(swatch, bool) or not 0 <= swatch < NUM_SWATCHES:
            errors.append(f"{label}: swatch fuera de 0..{NUM_SWATCHES - 1}: {swatch!r}")

        combos = color["combinations"]
        if not combos:
            errors.append(f"{label}: no aparece en ninguna combinación")
        if not all(isinstance(c, int) and not isinstance(c, bool) for c in combos):
            errors.append(f"{label}: combinations contiene valores no enteros")
        else:
            if len(set(combos)) != len(combos):
                errors.append(f"{label}: ids de combinación repetidos")
            bad = [c for c in combos if not 1 <= c <= EXPECTED_NUM_COMBOS]
            if bad:
                errors.append(f"{label}: ids de combinación fuera de 1..{EXPECTED_NUM_COMBOS}: {bad}")

    if errors:
        # Con errores estructurales la inversión no es fiable: no seguir.
        return report

    members = invert_combinations(colors)
    ids = list(members)
    expected_ids = list(range(1, EXPECTED_NUM_COMBOS + 1))
    if ids != expected_ids:
        missing_ids = sorted(set(expected_ids) - set(ids))
        extra_ids = sorted(set(ids) - set(expected_ids))
        errors.append(f"ids de combinación con huecos: faltan {missing_ids}, sobran {extra_ids}")

    histogram = dict(sorted(Counter(len(v) for v in members.values()).items()))
    if histogram != EXPECTED_SIZE_HISTOGRAM:
        errors.append(f"histograma de tamaños {histogram} != esperado {EXPECTED_SIZE_HISTOGRAM}")
    too_big = [cid for cid, v in members.items() if len(v) > MAX_COLORS]
    if too_big:
        errors.append(f"combinaciones con más de {MAX_COLORS} colores: {too_big}")

    for erratum in KNOWN_ERRATA:
        if erratum["field"] == "name" and erratum["dataset_value"] in name_seen:
            warnings.append(
                f"color[{name_seen[erratum['dataset_value']]}] {erratum['dataset_value']!r}: "
                f"nombre con errata conocida (libro: {erratum['book_value']!r})"
            )
    return report


# --------------------------------------------------------------------------------------
# Overrides (capa explícita de correcciones; solo la edita el usuario)
# --------------------------------------------------------------------------------------


def build_overrides_template() -> dict[str, Any]:
    """Documento ``overrides.json`` vacío. Se crea solo si no existe; nunca se sobreescribe."""
    return {"schema": OVERRIDES_SCHEMA, "overrides": []}


def load_overrides(path: Path | None) -> list[dict[str, Any]]:
    """Lee ``overrides.json``. Sin archivo (o ``None``) devuelve una lista vacía.

    Solo comprueba la forma del documento; la coherencia con el fuente la valida
    :func:`validate_overrides`.
    """
    if path is None or not path.is_file():
        return []
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
    if not isinstance(doc, dict) or doc.get("schema") != OVERRIDES_SCHEMA:
        raise ValueError(f"{path}: se esperaba un objeto con 'schema': {OVERRIDES_SCHEMA}")
    overrides = doc.get("overrides")
    if not isinstance(overrides, list):
        raise ValueError(f"{path}: 'overrides' debe ser una lista")
    return overrides


def validate_overrides(overrides: list[dict[str, Any]], colors: list[dict[str, Any]]) -> list[str]:
    """Errores de forma y de coherencia de los overrides frente al fuente (vacío = OK)."""
    errors: list[str] = []
    seen: set[tuple[int, str]] = set()
    for pos, ov in enumerate(overrides):
        label = f"override[{pos}]"
        if not isinstance(ov, dict):
            errors.append(f"{label}: no es un objeto")
            continue
        missing = sorted(OVERRIDE_KEYS - set(ov))
        extra = sorted(set(ov) - OVERRIDE_KEYS)
        if missing:
            errors.append(f"{label}: faltan claves {missing}")
        if extra:
            errors.append(f"{label}: claves desconocidas {extra}")
        if missing:
            continue
        index, field_name, value = ov["index"], ov["field"], ov["value"]
        if isinstance(index, bool) or not isinstance(index, int) or not 0 <= index < len(colors):
            errors.append(f"{label}: index {index!r} fuera de 0..{len(colors) - 1}")
            continue
        if field_name not in OVERRIDE_FIELDS:
            errors.append(f"{label}: field {field_name!r} no es uno de {list(OVERRIDE_FIELDS)}")
            continue
        if (index, field_name) in seen:
            errors.append(f"{label}: override repetido para index {index} field {field_name!r}")
        seen.add((index, field_name))
        if field_name == "rgb" and not (_is_int_list(value, 3) and all(0 <= v <= 255 for v in value)):
            errors.append(f"{label}: rgb debe ser [r, g, b] enteros 0..255, no {value!r}")
        elif field_name == "cmyk" and not (_is_int_list(value, 4) and all(0 <= v <= 100 for v in value)):
            errors.append(f"{label}: cmyk debe ser [c, m, y, k] enteros 0..100, no {value!r}")
        elif field_name == "name" and (not isinstance(value, str) or not value.strip() or not value.isascii()):
            errors.append(f"{label}: name debe ser un texto ASCII no vacío, no {value!r}")
        if value == colors[index].get(field_name):
            errors.append(f"{label}: value {value!r} es idéntico al fuente (override inútil)")
        if not isinstance(ov["reason"], str) or not ov["reason"].strip():
            errors.append(f"{label}: reason debe ser un texto no vacío")
        if not isinstance(ov["accepted_at"], str) or not re.match(r"^\d{4}-\d{2}-\d{2}", ov["accepted_at"]):
            errors.append(f"{label}: accepted_at debe ser una fecha ISO (AAAA-MM-DD...), no {ov['accepted_at']!r}")
    return errors


def apply_overrides(colors: list[dict[str, Any]], overrides: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Devuelve una copia del fuente con los overrides aplicados (el fuente no se toca).

    Precondición: :func:`validate_overrides` sin errores. Si ``field`` es ``rgb`` se
    recalcula ``hex``. La coherencia global del resultado (hex únicos, nombres únicos...)
    se comprueba después con :func:`validate_source`.
    """
    result = copy.deepcopy(colors)
    for ov in overrides:
        color = result[ov["index"]]
        color[ov["field"]] = copy.deepcopy(ov["value"])
        if ov["field"] == "rgb":
            color["hex"] = "#{:02x}{:02x}{:02x}".format(*ov["value"])
    return result


def overrides_by_target(overrides: list[dict[str, Any]]) -> dict[tuple[int, str], dict[str, Any]]:
    """(index, field) -> override, para cruzar con las erratas."""
    return {(ov["index"], ov["field"]): ov for ov in overrides}


# --------------------------------------------------------------------------------------
# Generación de artefactos
# --------------------------------------------------------------------------------------


def canonical_json(obj: Any) -> bytes:
    """JSON canónico para hashes: claves ordenadas, sin espacios, UTF-8."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def compute_dict_version(color_entries: list[dict[str, Any]], combo_entries: list[dict[str, Any]]) -> str:
    """sha256 corto (12 hex) del JSON canónico de ``{"colors", "combinations"}``.

    Cambia si cambia cualquier color (overrides incluidos), combinación o colección;
    no depende de metadatos (``source``, ``status``...) ni del formato del archivo.
    """
    digest = hashlib.sha256(canonical_json({"colors": color_entries, "combinations": combo_entries}))
    return digest.hexdigest()[:DICT_VERSION_HEX_LEN]


def dump_json(obj: Any) -> bytes:
    """Serialización canónica: claves ordenadas, indentación 2, UTF-8, salto final."""
    return (json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")


def build_dictionary(colors: list[dict[str, Any]]) -> dict[str, Any]:
    """Documento ``dictionary.json``. Sin Lab (lo calcula el motor).

    ``colors`` es el fuente ya con los overrides aplicados (ver :func:`apply_overrides`).
    """
    color_entries = [
        {
            "index": index,
            "name": color["name"],
            "hex": color["hex"],
            "rgb": list(color["rgb"]),
            "cmyk": list(color["cmyk"]),
            "swatch": color["swatch"],
        }
        for index, color in enumerate(colors)
    ]
    combo_entries = [
        # ``collection`` es curación futura del usuario (temática); null hasta entonces.
        {"id": cid, "size": len(idx), "colors": idx, "collection": None}
        for cid, idx in invert_combinations(colors).items()
    ]
    return {
        "schema": SCHEMA,
        "source": SOURCE_LABEL,
        "generated_by": GENERATOR,
        "status": DICT_STATUS,
        "dict_version": compute_dict_version(color_entries, combo_entries),
        "colors": color_entries,
        "combinations": combo_entries,
    }


def build_names_template() -> list[dict[str, Any]]:
    """Plantilla de ``names.es.json``: la cura el usuario, el generador nunca la sobreescribe."""
    return [
        {"id": n, "name": "", "lang": "es", "status": "pending", "notes": ""}
        for n in range(1, EXPECTED_NUM_COMBOS + 1)
    ]


def validate_names_file(path: Path) -> list[str]:
    """Comprueba la forma de ``names.es.json`` sin juzgar su contenido curado."""
    problems: list[str] = []
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        return [f"{path.name}: no se puede leer: {exc}"]
    if not isinstance(data, list):
        return [f"{path.name}: se esperaba una lista"]
    ids = [e.get("id") for e in data if isinstance(e, dict)]
    if ids != list(range(1, EXPECTED_NUM_COMBOS + 1)):
        problems.append(f"{path.name}: ids deben ser exactamente 1..{EXPECTED_NUM_COMBOS} en orden")
    for entry in data:
        if not isinstance(entry, dict) or not {"id", "name", "lang", "status", "notes"} <= set(entry):
            problems.append(f"{path.name}: entrada malformada: {entry!r}")
            break
    return problems


# --------------------------------------------------------------------------------------
# Conversión CMYK -> sRGB (misma receta que mattdesl/src/cmyk_icc)
# --------------------------------------------------------------------------------------


def find_swop_profile(explicit: Path | None = None) -> Path | None:
    """Localiza un perfil ICC SWOP: argumento explícito, variable de entorno o búsqueda."""
    if explicit is not None:
        if not explicit.is_file():
            raise FileNotFoundError(f"perfil ICC no encontrado: {explicit}")
        return explicit
    env = os.environ.get(PROFILE_ENV_VAR)
    if env:
        candidate = Path(env).expanduser()
        if not candidate.is_file():
            raise FileNotFoundError(f"{PROFILE_ENV_VAR} apunta a un archivo inexistente: {candidate}")
        return candidate
    for directory in PROFILE_SEARCH_DIRS:
        base = Path(directory).expanduser()
        if not base.is_dir():
            continue
        candidates = sorted(p for p in base.rglob("*") if p.is_file() and p.suffix.lower() in (".icc", ".icm"))
        for candidate in candidates:
            compact = candidate.name.lower().replace(" ", "")
            if any(keyword in compact for keyword in PROFILE_KEYWORDS):
                return candidate
    return None


def percent_to_byte(value: float) -> int:
    """0..100 -> 0..255 exactamente como ``cmyk_icc`` de mattdesl (``round`` de Python)."""
    return max(0, min(255, round(value / 100 * 255)))


def cmyk_to_srgb(cmyks: list[list[int]], profile: Path) -> list[list[int]]:
    """CMYK (0..100) -> sRGB8 con Pillow/LittleCMS, relative colorimetric + BPC.

    Reproduce la receta de mattdesl: entrada CMYK 8 bits, salida RGB 8 bits, flags
    NOCACHE | NOOPTIMIZE | HIGHRESPRECALC | BLACKPOINTCOMPENSATION. El perfil sRGB es el
    integrado de LittleCMS (mattdesl usó el archivo "sRGB IEC61966-2.1.icc"; mismas primarias
    y curva, diferencias esperables de ±1 por redondeo).
    """
    from PIL import Image, ImageCms

    cmyk_profile = ImageCms.getOpenProfile(str(profile))
    srgb_profile = ImageCms.createProfile("sRGB")
    flags = (
        ImageCms.Flags.NOCACHE
        | ImageCms.Flags.NOOPTIMIZE
        | ImageCms.Flags.HIGHRESPRECALC
        | ImageCms.Flags.BLACKPOINTCOMPENSATION
    )
    transform = ImageCms.buildTransform(
        cmyk_profile,
        srgb_profile,
        "CMYK",
        "RGB",
        renderingIntent=ImageCms.Intent.RELATIVE_COLORIMETRIC,
        flags=flags,
    )
    image = Image.new("CMYK", (len(cmyks), 1))
    image.putdata([tuple(percent_to_byte(v) for v in cmyk) for cmyk in cmyks])
    raw = ImageCms.applyTransform(image, transform).tobytes()
    return [list(raw[i : i + 3]) for i in range(0, len(raw), 3)]


def profile_description(profile: Path) -> str:
    from PIL import ImageCms

    try:
        return ImageCms.getProfileDescription(ImageCms.getOpenProfile(str(profile))).strip()
    except Exception:  # pragma: no cover - solo informativo
        return profile.name


@dataclass
class ConversionStats:
    """Comparación entre el rgb del fuente y una reconversión CMYK -> sRGB."""

    profile: Path
    description: str
    recomputed: list[list[int]]
    diffs: list[list[int]]

    @property
    def max_per_channel(self) -> list[int]:
        return [max(abs(d[c]) for d in self.diffs) for c in range(3)]

    @property
    def max_abs(self) -> int:
        return max(self.max_per_channel)

    def count_within(self, tolerance: int) -> int:
        return sum(1 for d in self.diffs if max(abs(v) for v in d) <= tolerance)


def compare_conversion(colors: list[dict[str, Any]], profile: Path) -> ConversionStats:
    recomputed = cmyk_to_srgb([list(c["cmyk"]) for c in colors], profile)
    diffs = [[r - s for r, s in zip(rec, color["rgb"])] for rec, color in zip(recomputed, colors)]
    return ConversionStats(profile, profile_description(profile), recomputed, diffs)


def build_errata(
    colors: list[dict[str, Any]], profile: Path | None, overrides: list[dict[str, Any]] | None = None
) -> dict[str, Any]:
    """Documento ``errata.json``. Falla si el fuente cambió y una errata ya no aplica.

    ``colors`` es el fuente SIN overrides (las erratas describen el fuente). Si hay un
    override para el mismo ``(index, field)``, la errata pasa a ``status: "accepted"`` y
    registra ``accepted_at`` y ``override_value``.
    """
    by_name = {color["name"]: index for index, color in enumerate(colors)}
    by_target = overrides_by_target(overrides or [])
    entries: list[dict[str, Any]] = []
    for erratum in KNOWN_ERRATA:
        if erratum["color"] not in by_name:
            raise ValueError(f"errata desincronizada: no existe el color {erratum['color']!r} en el fuente")
        index = by_name[erratum["color"]]
        actual = colors[index][erratum["field"]]
        if actual != erratum["dataset_value"]:
            raise ValueError(
                f"errata desincronizada: {erratum['color']!r}.{erratum['field']} vale {actual!r}, "
                f"se esperaba {erratum['dataset_value']!r}"
            )
        entry = {
            "index": index,
            "color": erratum["color"],
            "field": erratum["field"],
            "dataset_value": erratum["dataset_value"],
            "book_value": erratum["book_value"],
            "reference": erratum["reference"],
            "status": "pending",
            "notes": erratum["notes"],
        }
        if profile is not None and erratum["field"] == "cmyk":
            entry["derived_rgb_candidate"] = cmyk_to_srgb([list(erratum["book_value"])], profile)[0]
        override = by_target.get((index, erratum["field"]))
        if override is not None:
            entry["status"] = "accepted"
            entry["accepted_at"] = override["accepted_at"]
            entry["override_value"] = override["value"]
        entries.append(entry)
    conversion: dict[str, Any] | None = None
    if profile is not None:
        conversion = {
            "profile": str(profile),
            "description": profile_description(profile),
            "intent": "relative colorimetric",
            "black_point_compensation": True,
            "output": "sRGB (perfil integrado de LittleCMS)",
        }
    return {
        "schema": SCHEMA,
        "source": SOURCE_LABEL,
        "generated_by": GENERATOR,
        "policy": (
            "ARCHIVO GENERADO: no editar a mano (--check lo compara con la regeneración). "
            "Los valores del fuente no se modifican. Cada entrada documenta una discrepancia "
            "frente al libro impreso. Para aceptar una errata el usuario añade un override en "
            "data/wada/overrides.json (mismo index y field) y regenera con 'make dict': la "
            "entrada pasa a 'accepted' con 'accepted_at' y 'override_value'. "
            "'derived_rgb_candidate' (si existe) es el sRGB recalculado a "
            "partir del CMYK del libro con un perfil SWOP local; depende del entorno y --check "
            "lo ignora al comparar."
        ),
        "references": [ISSUE_1, PR_2],
        "conversion_profile": conversion,
        "errata": entries,
    }


def strip_environment_fields(errata_doc: dict[str, Any]) -> dict[str, Any]:
    """Quita de ``errata.json`` lo que depende de la máquina (perfil ICC y candidatos)."""
    doc = dict(errata_doc)
    doc["conversion_profile"] = None
    doc["errata"] = [
        {k: v for k, v in entry.items() if k != "derived_rgb_candidate"} for entry in errata_doc["errata"]
    ]
    return doc


def render_conversion_check(
    colors: list[dict[str, Any]],
    stats: ConversionStats | None,
    informative: ConversionStats | None,
) -> str:
    """Informe Markdown ``CONVERSION_CHECK.md``."""
    lines: list[str] = []
    add = lines.append
    add("# Comprobación de la conversión CMYK -> sRGB")
    add("")
    add("Generado por `oracle.build_dictionary`, no editar a mano.")
    add("")
    add("Los `rgb`/`hex` de `source/colors.json` los derivó mattdesl de los CMYK del libro con")
    add("LittleCMS: perfil *U.S. Web Coated (SWOP) v2* -> *sRGB IEC61966-2.1*, intent relative")
    add("colorimetric, compensación de punto negro, entrada y salida de 8 bits, CMYK escalado con")
    add("`round(v / 100 * 255)`. Este informe repite esa receta con Pillow/ImageCms y compara el")
    add("resultado con el `rgb` del fuente para los 159 colores.")
    add("")
    if stats is None:
        add("## Resultado: sin perfil SWOP en esta máquina")
        add("")
        add("No se encontró ningún perfil ICC cuyo nombre contenga `SWOP` o `WebCoated` en:")
        add("")
        for directory in PROFILE_SEARCH_DIRS:
            add(f"- `{directory}`")
        add("")
        add(f"Tampoco está definida la variable de entorno `{PROFILE_ENV_VAR}`.")
        add("")
        add("Consecuencias:")
        add("")
        add("- No se ha podido verificar la reproducibilidad de los `rgb` de mattdesl.")
        add("- `errata.json` no lleva `derived_rgb_candidate`.")
        add("")
        add("Para hacer la comprobación: instalar el perfil *U.S. Web Coated (SWOP) v2.icc* (viene con")
        add("las aplicaciones de Adobe y con su paquete de perfiles ICC, sujeto a la licencia de Adobe;")
        add("no lo añadas al repositorio) y volver a ejecutar el generador, o pasar la ruta con")
        add(f"`--swop-profile` o `{PROFILE_ENV_VAR}`.")
        add("")
        if informative is not None:
            add(f"## Anexo informativo: `{informative.profile.name}` (NO es una validación)")
            add("")
            add(f"Perfil: *{informative.description}* (`{informative.profile}`). No es el perfil SWOP con")
            add("el que se calcularon los `rgb`, así que las diferencias solo muestran cuánto depende el")
            add("resultado del perfil de imprenta elegido; no señalan errores del dataset.")
            add("")
            _append_stats(lines, colors, informative, include_table=False)
    else:
        add("## Resultado")
        add("")
        add(f"Perfil CMYK: *{stats.description}* (`{stats.profile}`).")
        add("")
        _append_stats(lines, colors, stats)
        add("")
        if stats.max_abs <= 1:
            add("Veredicto: la receta se reproduce (diferencia máxima <= 1 por canal, atribuible al")
            add("redondeo y a la variante del perfil sRGB). Los `derived_rgb_candidate` de `errata.json`")
            add("son comparables con los `rgb` del fuente.")
        else:
            add("Veredicto: la receta NO se reproduce exactamente. Antes de usar los")
            add("`derived_rgb_candidate` de `errata.json` conviene entender la diferencia (versión del")
            add("perfil, versión de LittleCMS, precalc).")
    add("")
    return "\n".join(lines)


def _append_stats(
    lines: list[str], colors: list[dict[str, Any]], stats: ConversionStats, include_table: bool = True
) -> None:
    add = lines.append
    mx = stats.max_per_channel
    add(f"- Diferencia máxima por canal (recalculado - fuente): R {mx[0]}, G {mx[1]}, B {mx[2]}.")
    add(f"- Colores idénticos: {stats.count_within(0)} de {len(colors)}.")
    add(f"- Colores con diferencia <= 1 en todos los canales: {stats.count_within(1)} de {len(colors)}.")
    add(f"- Colores con diferencia <= 3 en todos los canales: {stats.count_within(3)} de {len(colors)}.")
    add("")
    outliers = [
        (index, color, rec, diff)
        for index, (color, rec, diff) in enumerate(zip(colors, stats.recomputed, stats.diffs))
        if max(abs(v) for v in diff) > 1
    ]
    if not outliers:
        add("Ningún color difiere en más de 1 por canal.")
        return
    if not include_table:
        add(f"Colores con diferencia > 1 en algún canal: {len(outliers)} (tabla omitida en el anexo).")
        return
    add(f"Colores con diferencia > 1 en algún canal ({len(outliers)}):")
    add("")
    add("| índice | nombre | cmyk | rgb fuente | rgb recalculado | diferencia |")
    add("|---:|---|---|---|---|---|")
    for index, color, rec, diff in outliers:
        name = color["name"].replace("|", "\\|")  # escapar el separador de tabla Markdown
        add(f"| {index} | {name} | {color['cmyk']} | {color['rgb']} | {rec} | {diff} |")


# --------------------------------------------------------------------------------------
# Header C
# --------------------------------------------------------------------------------------


def _c_string(text: str) -> str:
    if not text.isascii():
        raise ValueError(f"nombre no ASCII, el header C exige ASCII: {text!r}")
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _c_comment(text: str) -> str:
    if "*/" in text:
        raise ValueError(f"texto no apto para comentario C: {text!r}")
    return text


def render_c_header(dictionary: dict[str, Any]) -> str:
    """Header C generado con todo ``static const`` (incluir desde un único .c)."""
    colors = dictionary["colors"]
    combos = dictionary["combinations"]
    if len(colors) > NONE_INDEX:
        raise ValueError("más de 255 colores: uint8_t ya no sirve como índice")
    lines: list[str] = []
    add = lines.append
    add("/*")
    add(" * ce_dict_data.h: diccionario de Sanzo Wada embebido")
    add(f" * ({len(colors)} colores, {len(combos)} combinaciones).")
    add(" *")
    add(" * GENERADO por oracle.build_dictionary, no editar.")
    add(" * Regenerar: uv run --project oracle python -m oracle.build_dictionary --emit-c")
    add(f" * Fuente: {dictionary['source']} (ver data/wada/README.md).")
    add(" *")
    add(" * Todo es `static const` para poder incluir este header desde un unico .c")
    add(" * (ce_dict.c); la API publica esta en ce/ce.h (ce_dict_*).")
    add(" * Solo sRGB8: el motor calcula Lab D65 en C; aqui no hay Lab.")
    add(" * Los indices de color de cada combinacion van en orden ascendente; las")
    add(" * posiciones mas alla de `size` valen CE_DICT_NONE.")
    add(" * (Comentarios sin acentos a proposito: el header es ASCII puro.)")
    add(" */")
    add("#ifndef CE_DICT_DATA_H")
    add("#define CE_DICT_DATA_H")
    add("")
    add("#include <stdint.h>")
    add("")
    add(f"#define CE_DICT_SCHEMA {dictionary['schema']}")
    add(f"#define CE_DICT_VERSION {_c_string(dictionary['dict_version'])} /* = dict_version de dictionary.json */")
    add(f"#define CE_DICT_NUM_COLORS {len(colors)}")
    add(f"#define CE_DICT_NUM_COMBOS {len(combos)}")
    add(f"#define CE_DICT_MAX_COLORS {MAX_COLORS} /* reserva para el Vol. 2 (3..7 colores) */")
    add(f"#define CE_DICT_NUM_SWATCHES {NUM_SWATCHES} /* capitulos del libro, campo swatch 0..5 */")
    add(f"#define CE_DICT_NONE 0x{NONE_INDEX:02X} /* relleno de ce_dict_combo.colors */")
    add("")
    add("#if defined(__GNUC__) || defined(__clang__)")
    add("#define CE_DICT_UNUSED __attribute__((unused))")
    add("#else")
    add("#define CE_DICT_UNUSED")
    add("#endif")
    add("")
    add("/* sRGB de 8 bits por canal, indexado por indice de color (0..CE_DICT_NUM_COLORS-1). */")
    add("CE_DICT_UNUSED static const uint8_t ce_dict_data_rgb[CE_DICT_NUM_COLORS][3] = {")
    for color in colors:
        r, g, b = color["rgb"]
        add(f"    {{{r:3d}, {g:3d}, {b:3d}}}, /* {color['index']:3d} {_c_comment(color['name'])} */")
    add("};")
    add("")
    add("/* Nombres en ingles del libro (nomenclatura de Ridgway), tal cual en el fuente. */")
    add("CE_DICT_UNUSED static const char *const ce_dict_data_names[CE_DICT_NUM_COLORS] = {")
    for color in colors:
        add(f"    {_c_string(color['name'])}, /* {color['index']} */")
    add("};")
    add("")
    add("/* Capitulo del libro (0..CE_DICT_NUM_SWATCHES-1) de cada color. */")
    add("CE_DICT_UNUSED static const uint8_t ce_dict_data_swatch[CE_DICT_NUM_COLORS] = {")
    swatches = [color["swatch"] for color in colors]
    for start in range(0, len(swatches), 16):
        chunk = ", ".join(str(s) for s in swatches[start : start + 16])
        add(f"    {chunk}, /* {start}.. */")
    add("};")
    add("")
    add("typedef struct {")
    add("    uint16_t id;                         /* 1..CE_DICT_NUM_COMBOS, numero de lamina */")
    add("    uint8_t size;                        /* colores usados: 2..CE_DICT_MAX_COLORS */")
    add("    uint8_t colors[CE_DICT_MAX_COLORS];  /* indices ascendentes; CE_DICT_NONE de relleno */")
    add("} ce_dict_data_combo;")
    add("")
    add("CE_DICT_UNUSED static const ce_dict_data_combo ce_dict_data_combos[CE_DICT_NUM_COMBOS] = {")
    for combo in combos:
        padded = list(combo["colors"]) + [NONE_INDEX] * (MAX_COLORS - len(combo["colors"]))
        cells = ", ".join(f"0x{v:02X}" if v == NONE_INDEX else f"{v:3d}" for v in padded)
        add(f"    {{{combo['id']:3d}, {combo['size']}, {{{cells}}}}},")
    add("};")
    add("")
    add("#endif /* CE_DICT_DATA_H */")
    add("")
    text = "\n".join(lines)
    if not text.isascii():
        raise ValueError("el header C generado debe ser ASCII puro")
    return text


# --------------------------------------------------------------------------------------
# Orquestación
# --------------------------------------------------------------------------------------


@dataclass
class Outputs:
    """Artefactos generados en memoria (bytes exactos que irían a disco)."""

    dictionary: bytes
    errata: bytes
    conversion_check: bytes
    header: bytes
    profile: Path | None
    dict_version: str = ""
    overrides_applied: int = 0


def generate_outputs(
    colors: list[dict[str, Any]],
    profile: Path | None,
    use_icc: bool = True,
    overrides: list[dict[str, Any]] | None = None,
) -> Outputs:
    """Genera todos los artefactos en memoria.

    ``colors`` es el fuente tal cual; los ``overrides`` (ya validados con
    :func:`validate_overrides`) se aplican aquí. El resultado debe pasar
    :func:`validate_source` sin errores, si no se lanza ``ValueError``.
    """
    overrides = list(overrides or [])
    effective = apply_overrides(colors, overrides) if overrides else colors
    if overrides:
        report = validate_source(effective)
        if not report.ok:
            raise ValueError("fuente con overrides inválido: " + "; ".join(report.errors))
    dictionary = build_dictionary(effective)
    errata = build_errata(colors, profile, overrides)
    stats = compare_conversion(colors, profile) if profile is not None else None
    informative = None
    if use_icc and stats is None and GENERIC_CMYK_PROFILE.is_file():
        informative = compare_conversion(colors, GENERIC_CMYK_PROFILE)
    return Outputs(
        dictionary=dump_json(dictionary),
        errata=dump_json(errata),
        conversion_check=render_conversion_check(colors, stats, informative).encode("utf-8"),
        header=render_c_header(dictionary).encode("utf-8"),
        profile=profile,
        dict_version=dictionary["dict_version"],
        overrides_applied=len(overrides),
    )


def _read_bytes(path: Path) -> bytes | None:
    try:
        return path.read_bytes()
    except FileNotFoundError:
        return None


def _errata_equivalent(on_disk: bytes | None, generated: bytes) -> bool:
    if on_disk is None:
        return False
    try:
        disk_doc = json.loads(on_disk.decode("utf-8"))
    except ValueError:
        return False
    gen_doc = json.loads(generated.decode("utf-8"))
    return dump_json(strip_environment_fields(disk_doc)) == dump_json(strip_environment_fields(gen_doc))


def check_outputs(outputs: Outputs, out_dir: Path, header_path: Path, emit_c: bool) -> list[str]:
    """Compara lo generado con el disco. Devuelve una lista de diferencias (vacía = OK)."""
    diffs: list[str] = []
    dictionary_path = out_dir / DICTIONARY_NAME
    if _read_bytes(dictionary_path) != outputs.dictionary:
        diffs.append(f"{dictionary_path}: difiere o no existe")
    errata_path = out_dir / ERRATA_NAME
    if not _errata_equivalent(_read_bytes(errata_path), outputs.errata):
        diffs.append(f"{errata_path}: difiere o no existe (ignorando campos dependientes del entorno)")
    names_path = out_dir / NAMES_NAME
    if names_path.is_file():
        diffs.extend(validate_names_file(names_path))
    else:
        diffs.append(f"{names_path}: no existe (el generador la crearía)")
    overrides_path = out_dir / OVERRIDES_NAME
    if overrides_path.is_file():
        try:
            load_overrides(overrides_path)
        except ValueError as exc:
            diffs.append(str(exc))
    else:
        diffs.append(f"{overrides_path}: no existe (el generador la crearía vacía)")
    if emit_c or header_path.is_file():
        if _read_bytes(header_path) != outputs.header:
            diffs.append(f"{header_path}: difiere o no existe")
    return diffs


def write_outputs(outputs: Outputs, out_dir: Path, header_path: Path, emit_c: bool) -> list[Path]:
    """Escribe los artefactos. ``names.es.json`` y ``overrides.json`` solo si no existen."""
    written: list[Path] = []
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, payload in (
        (DICTIONARY_NAME, outputs.dictionary),
        (ERRATA_NAME, outputs.errata),
        (CONVERSION_CHECK_NAME, outputs.conversion_check),
    ):
        path = out_dir / name
        path.write_bytes(payload)
        written.append(path)
    names_path = out_dir / NAMES_NAME
    if not names_path.exists():
        names_path.write_bytes(dump_json(build_names_template()))
        written.append(names_path)
    overrides_path = out_dir / OVERRIDES_NAME
    if not overrides_path.exists():
        overrides_path.write_bytes(dump_json(build_overrides_template()))
        written.append(overrides_path)
    if emit_c:
        header_path.parent.mkdir(parents=True, exist_ok=True)
        header_path.write_bytes(outputs.header)
        written.append(header_path)
    return written


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m oracle.build_dictionary",
        description="Construye data/wada/dictionary.json, errata.json, names.es.json y el header C del motor.",
    )
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE, help="colors.json de mattdesl")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR, help="directorio data/wada")
    parser.add_argument("--header", type=Path, default=DEFAULT_HEADER, help="ruta del header C")
    parser.add_argument(
        "--overrides",
        type=Path,
        default=None,
        help=f"overrides.json a aplicar (por defecto <out-dir>/{OVERRIDES_NAME}; si no existe, ninguno)",
    )
    parser.add_argument("--emit-c", action="store_true", help="genera (o comprueba) el header C")
    parser.add_argument("--check", action="store_true", help="no escribe: compara con el disco, sale 1 si difiere")
    parser.add_argument("--swop-profile", type=Path, default=None, help="perfil ICC CMYK SWOP a usar")
    parser.add_argument("--no-icc", action="store_true", help="no usar ningún perfil ICC (salida independiente del entorno)")
    parser.add_argument("-q", "--quiet", action="store_true")
    args = parser.parse_args(argv)

    def say(message: str) -> None:
        if not args.quiet:
            print(message)

    colors = load_source(args.source)
    report = validate_source(colors)
    for warning in report.warnings:
        say(f"aviso: {warning}")
    if not report.ok:
        for error in report.errors:
            print(f"error: {error}", file=sys.stderr)
        print(f"fuente inválido: {len(report.errors)} error(es)", file=sys.stderr)
        return 2
    combos = invert_combinations(colors)
    histogram = dict(sorted(Counter(len(v) for v in combos.values()).items()))
    say(f"fuente válido: {len(colors)} colores, {len(combos)} combinaciones {histogram}, {len(report.warnings)} aviso(s)")

    overrides_path = args.overrides if args.overrides is not None else args.out_dir / OVERRIDES_NAME
    try:
        overrides = load_overrides(overrides_path)
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    problems = validate_overrides(overrides, colors)
    if problems:
        for problem in problems:
            print(f"error: {overrides_path}: {problem}", file=sys.stderr)
        print(f"overrides inválidos: {len(problems)} error(es)", file=sys.stderr)
        return 2
    say(f"overrides: {len(overrides)} aplicado(s) desde {overrides_path if overrides_path.is_file() else 'ninguno'}")

    try:
        profile = None if args.no_icc else find_swop_profile(args.swop_profile)
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    say(f"perfil SWOP: {profile if profile else 'no encontrado (sin derived_rgb_candidate)'}")
    try:
        outputs = generate_outputs(colors, profile, use_icc=not args.no_icc, overrides=overrides)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    say(f"dict_version: {outputs.dict_version} (status: {DICT_STATUS})")

    if args.check:
        diffs = check_outputs(outputs, args.out_dir, args.header, args.emit_c)
        if diffs:
            for diff in diffs:
                print(f"check: {diff}", file=sys.stderr)
            print("check: los artefactos en disco NO coinciden con el generador", file=sys.stderr)
            return 1
        say("check: artefactos en disco al día")
        return 0

    for path in write_outputs(outputs, args.out_dir, args.header, args.emit_c):
        say(f"escrito {path.relative_to(REPO_ROOT) if path.is_relative_to(REPO_ROOT) else path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
