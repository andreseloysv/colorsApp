"""Tests unitarios de ``oracle.metrics`` sobre casos sintéticos pequeños."""

from __future__ import annotations

import math

import pytest

from oracle import metrics as m


# ---- recall_at_k ----------------------------------------------------------------------


def test_recall_at_k_basic():
    truth = [1, 2, 3, 4]
    ranked = [[1, 9, 9], [9, 2, 9], [9, 9, 3], [9, 9, 9]]
    assert m.recall_at_k(truth, ranked, 1) == 0.25
    assert m.recall_at_k(truth, ranked, 2) == 0.5
    assert m.recall_at_k(truth, ranked, 3) == 0.75
    assert m.recall_at_k(truth, ranked, 10) == 0.75  # rankings más cortos que k


def test_recall_at_k_edge_cases():
    assert m.recall_at_k([], [], 3) == 0.0
    assert m.recall_at_k([5], [[]], 1) == 0.0
    assert m.recall_at_k([5], [(5,)], 1) == 1.0  # tuplas también valen
    with pytest.raises(ValueError):
        m.recall_at_k([1], [[1]], 0)
    with pytest.raises(ValueError):
        m.recall_at_k([1, 2], [[1]], 1)


# ---- class_shares / max_class_share ---------------------------------------------------


def test_class_shares_sorted_desc_with_tiebreak():
    shares = m.class_shares(["b", "a", "a", "c", "b", "a"])
    assert list(shares) == ["a", "b", "c"]
    assert shares["a"] == pytest.approx(0.5)
    assert shares["b"] == pytest.approx(2 / 6)
    assert sum(shares.values()) == pytest.approx(1.0)


def test_max_class_share():
    assert m.max_class_share([1, 1, 1, 2]) == 0.75
    assert m.max_class_share([1, 2, 3, 4]) == 0.25
    assert m.max_class_share([]) == 0.0
    assert m.max_class_share({12: 3, 40: 7}) == 0.7  # también acepta conteos
    assert m.max_class_share({12: 0}) == 0.0


def test_counts_mapping_rejects_bad_values():
    with pytest.raises(ValueError):
        m.max_class_share({1: -1})
    with pytest.raises(ValueError):
        m.entropy({1: True})


# ---- entropy ----------------------------------------------------------------------------


def test_entropy_bits():
    assert m.entropy([1, 1, 1, 1]) == 0.0
    assert m.entropy([1, 2]) == pytest.approx(1.0)
    assert m.entropy([1, 2, 3, 4]) == pytest.approx(2.0)
    assert m.entropy([1, 1, 2, 3]) == pytest.approx(1.5)
    assert m.entropy([]) == 0.0


def test_entropy_normalized():
    assert m.entropy([1, 2, 3, 4], n_classes=4) == pytest.approx(1.0)
    assert m.entropy([1, 2], n_classes=4) == pytest.approx(0.5)
    assert m.entropy([1, 1, 1], n_classes=348) == 0.0
    uniform = list(range(1, 349))
    assert m.entropy(uniform, n_classes=348) == pytest.approx(1.0)
    assert m.entropy(uniform) == pytest.approx(math.log2(348))
    assert m.entropy([1, 1], n_classes=1) == 0.0
    with pytest.raises(ValueError):
        m.entropy([1], n_classes=0)


# ---- coverage ---------------------------------------------------------------------------


def test_coverage():
    assert m.coverage([1, 2, 2, 3], 4) == 0.75
    assert m.coverage([1, 2, 2, 3], [1, 2, 3, 4, 5]) == 0.6
    assert m.coverage([7, 8], 4) == 0.0  # etiquetas fuera del universo no cuentan
    assert m.coverage([], 348) == 0.0
    assert m.coverage([1], []) == 0.0
    assert m.coverage({1: 2, 2: 0}, 2) == 0.5  # conteo 0 no cubre
    assert m.coverage(range(1, 349), 348) == 1.0


def test_metrics_together_on_a_degenerate_engine():
    """Un motor que siempre devuelve la 12 tiene cuota 1, entropía 0 y cobertura 1/348."""
    preds = [12] * 100
    assert m.max_class_share(preds) == 1.0
    assert m.entropy(preds, n_classes=348) == 0.0
    assert m.coverage(preds, 348) == pytest.approx(1 / 348)
    # Solo los casos cuya verdad es 12, 13 o 14 aciertan en el top-3: 3 de 100.
    assert m.recall_at_k(list(range(1, 101)), [[12, 13, 14]] * 100, 3) == pytest.approx(0.03)
    assert m.recall_at_k(list(range(1, 101)), [[12, 13, 14]] * 100, 1) == pytest.approx(0.01)
