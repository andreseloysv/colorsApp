/*
 * ce_match.c — capa 3: match de una paleta contra las 348 combinaciones del
 * diccionario de Wada (ce_match) y análisis completo imagen -> paleta ->
 * match (ce_analyze).
 *
 * Score de una combinación C = {c_j} frente a los swatches s_i de peso w_i,
 * bajo una hipótesis de adaptación h (ganancia de exposición g = 2^EV y/o
 * iluminante X adaptado a D65 con Bradford, aplicados a los swatches):
 *
 *   score_h(C) = Σ_i w_i · min_j ΔE00(h(s_i), c_j)          (ajuste de la paleta)
 *              + λ · (1/|C|) · Σ_j min_i ΔE00(c_j, h(s_i))  (cobertura de C)
 *              + exposure_penalty · |EV| + illuminant_penalty · [X != D65]
 *
 *   score(C) = min_h score_h(C)
 *
 * Por defecto (ce_match_opts_default, desde 2026-09-15) solo hay hipótesis de
 * exposición: illuminant_search = 0, porque las fotos del teléfono ya llegan
 * con balance de blancos y la hipótesis de iluminante giraba tonos en fotos
 * reales (rosa palo + negro -> Nº 067 azul; ADR-009). Sigue disponible con
 * illuminant_search = 1.
 *
 * La hipótesis identidad (EV = 0, D65) siempre está y se evalúa la primera:
 * con exposure_ev_max = 0 e illuminant_search = 0 el score es exactamente el
 * de la fase 3 (match v0), bit a bit. Menor es mejor. Se evalúan las 348
 * combinaciones sin poda bajo cada hipótesis y se devuelven las top_k
 * (<= CE_MATCH_MAX_HITS) por score ascendente con desempate por id ascendente
 * (comparación exacta de doubles). ambiguous = 1 si hay al menos dos hits y
 * score[1] - score[0] < ambiguous_gap.
 *
 * Determinismo: las hipótesis se recorren en un orden fijo (identidad, luego
 * ganancias 0, -1, +1, -2, +2... pasos de CE_MATCH_EV_STEP EV por cada
 * iluminante D65, A, D50, D75, F2); ΔE00 se calcula una sola vez por
 * (hipótesis, swatch, color) con la caché Lab del contexto; los sumatorios
 * recorren i y j en orden ascendente; el mínimo entre hipótesis es estricto
 * (en empate gana la primera); sin RNG ni estáticos mutables. Con ce_libm.c
 * el resultado es bit a bit idéntico en nativo y WASM.
 *
 * Reglas: C11, sin I/O, sin malloc, todo en double, sin contracción FMA.
 */
#include "ce_internal.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>

#pragma STDC FP_CONTRACT OFF

_Static_assert(CE_MATCH_MAX_HITS >= 1 && CE_MATCH_MAX_HITS <= 348,
               "CE_MATCH_MAX_HITS fuera de rango");

/* Capacidad de la tabla de mejores scores por combinación (ids 1..ncombos). */
#define CE_MATCH_MAX_COMBOS 512

/* Iluminantes hipotéticos distintos de D65, en orden de evaluación
 * (CE_MATCH_N_ILLS y CE_MATCH_MAX_STEPS viven en ce_internal.h). */
static const ce_illuminant CE_MATCH_ILLS[CE_MATCH_N_ILLS] = {CE_ILL_A, CE_ILL_D50, CE_ILL_D75, CE_ILL_F2};

ce_illuminant ce_match_hyp_illuminant(int ill)
{
    return (ill >= 0 && ill < CE_MATCH_N_ILLS) ? CE_MATCH_ILLS[ill] : CE_ILL_D65;
}

/* ------------------------------------------------------------------------
 * Opciones
 * ---------------------------------------------------------------------- */

void ce_match_opts_default(ce_match_opts *o)
{
    if (o == NULL) {
        return;
    }
    o->kL = 1.0;
    o->kC = 1.0;
    o->kH = 1.0;
    o->coverage_lambda = 1.0;
    o->ambiguous_gap = 1.0;
    o->exposure_ev_max = 1.0;
    o->exposure_penalty = 2.0;
    o->illuminant_search = 0; /* ADR-009: desactivada por defecto (doble corrección del balance de blancos) */
    o->illuminant_penalty = 2.0;
}

/* Las opciones reales deben ser finitas (NaN o ±inf => CE_ERR_OPTS);
 * coverage_lambda >= 0 (un λ negativo haría scores negativos); kL/kC/kH <= 0
 * los normaliza ce_de2000_k a 1.0; ambiguous_gap <= 0 => nunca ambiguo;
 * exposure_ev_max en [0, CE_MATCH_EV_MAX_LIMIT]; penalizaciones >= 0;
 * illuminant_search 0 o 1. */
int ce_match_opts_valid(const ce_match_opts *o)
{
    if (!isfinite(o->kL) || !isfinite(o->kC) || !isfinite(o->kH)) return 0;
    if (!isfinite(o->coverage_lambda) || o->coverage_lambda < 0.0) return 0;
    if (!isfinite(o->ambiguous_gap)) return 0;
    if (!isfinite(o->exposure_ev_max) || o->exposure_ev_max < 0.0 || o->exposure_ev_max > CE_MATCH_EV_MAX_LIMIT) return 0;
    if (!isfinite(o->exposure_penalty) || o->exposure_penalty < 0.0) return 0;
    if (o->illuminant_search != 0 && o->illuminant_search != 1) return 0;
    if (!isfinite(o->illuminant_penalty) || o->illuminant_penalty < 0.0) return 0;
    return 1;
}

/* Lab finito y peso finito >= 0 en cada swatch (la paleta lo garantiza). */
int ce_match_swatches_valid(const ce_swatch *sw, int n)
{
    int i;
    for (i = 0; i < n; ++i) {
        if (!isfinite(sw[i].lab.L) || !isfinite(sw[i].lab.a) || !isfinite(sw[i].lab.b)) return 0;
        if (!isfinite(sw[i].weight) || !(sw[i].weight >= 0.0)) return 0;
    }
    return 1;
}

/* ------------------------------------------------------------------------
 * Top-k por inserción (orden total: score asc, id asc)
 * ---------------------------------------------------------------------- */

static int ce_hit_before(double score, int id, const ce_hit *h)
{
    if (score != h->score) return score < h->score;
    return id < (int)h->combo_id;
}

/* Inserta (id, score) en `best` (ordenado, `*n` elementos, capacidad `cap`)
 * si entra entre los cap mejores. */
static void ce_hits_insert(ce_hit *best, int *n, int cap, int id, double score)
{
    int pos;
    if (*n == cap) {
        if (!ce_hit_before(score, id, &best[cap - 1])) {
            return;
        }
        pos = cap - 1; /* el último cae */
    } else {
        pos = *n;
        ++*n;
    }
    while (pos > 0 && ce_hit_before(score, id, &best[pos - 1])) {
        best[pos] = best[pos - 1];
        --pos;
    }
    best[pos].combo_id = (uint16_t)id;
    best[pos].score = score;
}

/* ------------------------------------------------------------------------
 * Hipótesis de adaptación
 * ---------------------------------------------------------------------- */

/* Aplica la hipótesis (matriz de Bradford X -> D65 opcional y ganancia g en
 * XYZ lineal) a un Lab. La identidad no pasa por aquí: conserva los bits. */
ce_lab ce_match_adapt_lab(ce_lab lab, const double *m, double gain)
{
    ce_xyz xyz = ce_lab_to_xyz(lab);
    if (m != NULL) {
        xyz = ce_xyz_adapt(xyz, m);
    }
    xyz.X *= gain;
    xyz.Y *= gain;
    xyz.Z *= gain;
    return ce_xyz_to_lab(xyz);
}

/* Evalúa las 348 combinaciones con los swatches ya adaptados (dist[i][c] =
 * ΔE00 del swatch i al color c) y actualiza best[id] con el mínimo estricto. */
static void ce_score_combos(const double dist[CE_PALETTE_MAX_COLORS][CE_CTX_DICT_CAP],
                            const ce_swatch *sw, int n, int ncolors, int ncombos,
                            double lambda, double penalty, double *best)
{
    int id;
    for (id = 1; id <= ncombos; ++id) {
        uint8_t size = 0;
        uint8_t colors[CE_DICT_COMBO_MAX];
        double fit = 0.0, coverage = 0.0, score;
        int i, j, valid = 1;

        if (ce_dict_combo(id, &size, colors) != 0 || size < 1 || size > CE_DICT_COMBO_MAX) {
            continue; /* hueco en los ids: no debería ocurrir (test_dict) */
        }
        for (j = 0; j < (int)size; ++j) {
            if (colors[j] >= ncolors) {
                valid = 0;
            }
        }
        if (!valid) {
            continue; /* índice fuera de la caché Lab: tabla corrupta */
        }
        /* Ajuste: cada swatch contra su color más cercano de C. */
        for (i = 0; i < n; ++i) {
            double m = HUGE_VAL;
            for (j = 0; j < (int)size; ++j) {
                const double d = dist[i][colors[j]];
                if (d < m) m = d;
            }
            fit += sw[i].weight * m;
        }
        /* Cobertura: cada color de C contra su swatch más cercano. */
        for (j = 0; j < (int)size; ++j) {
            double m = HUGE_VAL;
            for (i = 0; i < n; ++i) {
                const double d = dist[i][colors[j]];
                if (d < m) m = d;
            }
            coverage += m;
        }
        score = fit + lambda * (coverage / (double)size) + penalty;
        if (score != score) {
            /* Solo alcanzable con Lab absurdos (overflow en ΔE00): un NaN
             * rompería el orden total; se envía al final de forma determinista. */
            score = HUGE_VAL;
        }
        if (score < best[id]) {
            best[id] = score;
        }
    }
}

/* ------------------------------------------------------------------------
 * API
 * ---------------------------------------------------------------------- */

int ce_match(const ce_ctx *ctx, const ce_swatch *sw, int n, const ce_match_opts *o,
             ce_hit *out, int top_k, int *ambiguous)
{
    ce_match_opts def;
    /* ΔE00 de cada swatch adaptado a cada color del diccionario (<= 8 x 256
     * doubles, 16 KiB de pila): se calcula una vez por hipótesis. */
    double dist[CE_PALETTE_MAX_COLORS][CE_CTX_DICT_CAP];
    double best[CE_MATCH_MAX_COMBOS + 1];
    double bradford[CE_MATCH_N_ILLS][9];
    ce_hit hits[CE_MATCH_MAX_HITS];
    int n_best = 0;
    int ncolors, ncombos, i, id, steps, ill, step;

    if (ctx == NULL || sw == NULL || out == NULL) {
        return CE_ERR_ARG;
    }
    if (n < 1 || n > CE_PALETTE_MAX_COLORS) {
        return CE_ERR_ARG;
    }
    if (top_k < 1 || top_k > CE_MATCH_MAX_HITS) {
        return CE_ERR_ARG;
    }
    if (ctx->magic != CE_CTX_MAGIC) {
        return CE_ERR_CTX;
    }
    if (o == NULL) {
        ce_match_opts_default(&def);
        o = &def;
    }
    if (!ce_match_opts_valid(o)) {
        return CE_ERR_OPTS;
    }
    if (!ce_match_swatches_valid(sw, n)) {
        return CE_ERR_ARG;
    }

    ncolors = ctx->dict_n;
    ncombos = ce_dict_num_combos();
    if (ncombos < 1 || ncombos > CE_MATCH_MAX_COMBOS) {
        return CE_ERR_CTX; /* tabla del diccionario incoherente */
    }
    for (id = 0; id <= ncombos; ++id) {
        best[id] = HUGE_VAL;
    }
    /* Rejilla de exposición: k · CE_MATCH_EV_STEP con |k| <= steps. */
    steps = (int)(o->exposure_ev_max / CE_MATCH_EV_STEP + 1e-9);
    if (steps > CE_MATCH_MAX_STEPS) steps = CE_MATCH_MAX_STEPS;
    if (o->illuminant_search) {
        for (ill = 0; ill < CE_MATCH_N_ILLS; ++ill) {
            ce_bradford_matrix(CE_MATCH_ILLS[ill], CE_ILL_D65, bradford[ill]);
        }
    }

    /* ill = -1 es D65 (sin adaptación); step = 0 es EV 0. La identidad
     * (ill = -1, step = 0) va primero y no transforma los Lab. */
    for (ill = -1; ill < (o->illuminant_search ? CE_MATCH_N_ILLS : 0); ++ill) {
        const double *m = (ill < 0) ? NULL : bradford[ill];
        const double pen_ill = (ill < 0) ? 0.0 : o->illuminant_penalty;
        for (step = 0; step <= 2 * steps; ++step) {
            /* 0, -1, +1, -2, +2, ... */
            const int k = (step == 0) ? 0 : ((step & 1) ? -((step + 1) / 2) : (step / 2));
            const double ev = (double)k * CE_MATCH_EV_STEP;
            const double penalty = pen_ill + o->exposure_penalty * ((ev < 0.0) ? -ev : ev);
            const int identity = (ill < 0 && k == 0);
            const double gain = identity ? 1.0 : ce_pow(2.0, ev);
            int c;
            for (i = 0; i < n; ++i) {
                const ce_lab lab = identity ? sw[i].lab : ce_match_adapt_lab(sw[i].lab, m, gain);
                for (c = 0; c < ncolors; ++c) {
                    dist[i][c] = ce_de2000_k(lab, ctx->dict_lab[c], o->kL, o->kC, o->kH);
                }
            }
            ce_score_combos(dist, sw, n, ncolors, ncombos, o->coverage_lambda, penalty, best);
        }
    }

    for (id = 1; id <= ncombos; ++id) {
        if (best[id] < HUGE_VAL) {
            ce_hits_insert(hits, &n_best, top_k, id, best[id]);
        }
    }

    /* Campo a campo (no copia de struct): el relleno de `out` no recibe bytes
     * indeterminados de la pila y el resultado es comparable byte a byte. */
    for (i = 0; i < n_best; ++i) {
        out[i].combo_id = hits[i].combo_id;
        out[i].score = hits[i].score;
    }
    if (ambiguous != NULL) {
        *ambiguous = (n_best >= 2 && hits[1].score - hits[0].score < o->ambiguous_gap) ? 1 : 0;
    }
    return n_best;
}

int ce_analyze(ce_ctx *ctx, const ce_image *img, const ce_palette_opts *po,
               const ce_match_opts *mo, ce_result *out)
{
    ce_match_opts def;
    int n, rc, i;

    if (ctx == NULL || img == NULL || out == NULL) {
        return CE_ERR_ARG;
    }
    if (ctx->magic != CE_CTX_MAGIC) {
        return CE_ERR_CTX;
    }
    /* Las capas de depuración solo describen un análisis completado. */
    ctx->dbg.valid = 0;
    if (mo == NULL) {
        ce_match_opts_default(&def);
        mo = &def;
    }
    /* Se valida antes de extraer para que ningún error escriba en `out`
     * (ce_palette_extract ya valida imagen y opciones de paleta sin escribir). */
    if (!ce_match_opts_valid(mo)) {
        return CE_ERR_OPTS;
    }
    n = ce_palette_extract(ctx, img, po, out->swatches, CE_PALETTE_MAX_COLORS);
    if (n < 0) {
        return n;
    }
    out->n_swatches = n;
    rc = ce_match(ctx, out->swatches, n, mo, out->hits, CE_MATCH_MAX_HITS, &out->ambiguous);
    if (rc < 0) {
        /* Inalcanzable con una paleta válida; se deja `out` vacío y coherente. */
        out->n_swatches = 0;
        out->n_hits = 0;
        out->ambiguous = 0;
        return rc;
    }
    out->n_hits = rc;
    /* Las posiciones no usadas quedan a cero: el struct es comparable byte a byte. */
    for (i = n; i < CE_PALETTE_MAX_COLORS; ++i) {
        out->swatches[i].lab.L = 0.0;
        out->swatches[i].lab.a = 0.0;
        out->swatches[i].lab.b = 0.0;
        out->swatches[i].rgb[0] = 0;
        out->swatches[i].rgb[1] = 0;
        out->swatches[i].rgb[2] = 0;
        out->swatches[i].weight = 0.0;
    }
    for (i = rc; i < CE_MATCH_MAX_HITS; ++i) {
        out->hits[i].combo_id = 0;
        out->hits[i].score = 0.0;
    }
    return rc;
}
