"""Métricas del harness (capas 3 y 4): recall@k, entropía, cuota máxima y cobertura.

Funciones puras sobre secuencias de etiquetas (ids de combinación 1..348 o cualquier
valor hashable); sin numpy para que sean triviales de auditar. Convenciones:

* ``recall_at_k(truth, ranked, k)``: fracción de casos cuyo id verdadero aparece entre
  los ``k`` primeros de su ranking. Rankings más cortos que ``k`` se aceptan.
* ``entropy(labels, n_classes=None)``: entropía de Shannon en bits de la distribución
  empírica de etiquetas. Con ``n_classes`` devuelve la entropía normalizada por
  ``log2(n_classes)`` (1.0 = uniforme sobre todas las clases).
* ``max_class_share(labels)``: cuota (0..1) de la etiqueta más frecuente. Es la métrica
  "si >30 % de las fotos cae en la misma combinación, el motor no está listo".
* ``coverage(labels, classes)``: fracción de las clases del universo que reciben al
  menos una etiqueta.

Sobre secuencias vacías todas devuelven 0.0 (nunca lanzan ni dividen por cero).
"""

from __future__ import annotations

import math
from collections import Counter
from collections.abc import Hashable, Iterable, Mapping, Sequence


def recall_at_k(truth: Sequence[Hashable], ranked: Sequence[Sequence[Hashable]], k: int) -> float:
    """Fracción de ``truth[i]`` presentes en ``ranked[i][:k]``."""
    if k < 1:
        raise ValueError("k debe ser >= 1")
    if len(truth) != len(ranked):
        raise ValueError(f"truth ({len(truth)}) y ranked ({len(ranked)}) deben tener la misma longitud")
    if not truth:
        return 0.0
    hits = sum(1 for t, r in zip(truth, ranked) if t in list(r)[:k])
    return hits / len(truth)


def class_shares(labels: Iterable[Hashable] | Mapping[Hashable, int]) -> dict[Hashable, float]:
    """Cuota de cada etiqueta, ordenada de mayor a menor (desempate por repr de la etiqueta)."""
    counts = _counts(labels)
    total = sum(counts.values())
    if total <= 0:
        return {}
    items = sorted(counts.items(), key=lambda kv: (-kv[1], repr(kv[0])))
    return {label: n / total for label, n in items}


def max_class_share(labels: Iterable[Hashable] | Mapping[Hashable, int]) -> float:
    """Cuota (0..1) de la etiqueta más frecuente; 0.0 sin etiquetas."""
    shares = class_shares(labels)
    return next(iter(shares.values()), 0.0)


def entropy(labels: Iterable[Hashable] | Mapping[Hashable, int], n_classes: int | None = None) -> float:
    """Entropía de Shannon (bits) de la distribución empírica; normalizada si se da ``n_classes``."""
    shares = class_shares(labels)
    if not shares:
        return 0.0
    h = -sum(p * math.log2(p) for p in shares.values() if p > 0.0)
    if n_classes is None:
        return h
    if n_classes < 1:
        raise ValueError("n_classes debe ser >= 1")
    if n_classes == 1:
        return 0.0
    return h / math.log2(n_classes)


def coverage(labels: Iterable[Hashable] | Mapping[Hashable, int], classes: Iterable[Hashable] | int) -> float:
    """Fracción de ``classes`` (colección o número n => 1..n) con al menos una etiqueta."""
    universe = set(range(1, classes + 1)) if isinstance(classes, int) else set(classes)
    if not universe:
        return 0.0
    counts = _counts(labels)
    seen = {label for label, n in counts.items() if n > 0}
    return len(seen & universe) / len(universe)


def _counts(labels: Iterable[Hashable] | Mapping[Hashable, int]) -> Counter:
    if isinstance(labels, Mapping):
        counts = Counter()
        for label, n in labels.items():
            if not isinstance(n, int) or isinstance(n, bool) or n < 0:
                raise ValueError(f"conteo inválido para {label!r}: {n!r}")
            if n:
                counts[label] += n
        return counts
    return Counter(labels)
