"""Generadores sintéticos del harness (rutas protegidas ``oracle/synth/**``).

* ``synth.compose``: composiciones de bloques con verdad conocida (capa 2).
* ``synth.wada_gen`` (fase 3): variantes por combinación del diccionario (capa 3).

Todo es determinista a partir de una semilla (``numpy.random.default_rng``); el
oráculo de color es ``oracle.reference`` (colour-science).
"""
