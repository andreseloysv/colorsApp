/*
 * ce_debug.c — capas de depuración: lectura del estado que deja en el
 * contexto la última extracción (imagen reducida, peso por píxel, etiqueta de
 * swatch y de cluster por píxel, destino de cada cluster) y explicación del
 * score de una combinación (ce_match_explain_combo).
 *
 * Nada de lo que hay aquí modifica el contexto ni el resultado del motor: la
 * contabilidad la escribe ce_palette.c con enteros y copias. La explicación
 * del match repite las operaciones de ce_match.c en el mismo orden (mismas
 * hipótesis, mismas expresiones, mismas funciones), así que su score es bit a
 * bit el de ce_match (test_debug.c lo comprueba en las 348 combinaciones).
 *
 * Reglas: C11, sin I/O, sin malloc, todo en double, sin contracción FMA.
 */
#include "ce_internal.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>

#pragma STDC FP_CONTRACT OFF

_Static_assert(CE_DICT_MAX_COLORS == CE_DICT_COMBO_MAX, "per_color debe cubrir la combinacion mas grande");

/* Contexto con una extracción completada; si no, el código de error. */
static int ce_debug_check(const ce_ctx *ctx)
{
    if (ctx == NULL) {
        return CE_ERR_ARG;
    }
    if (ctx->magic != CE_CTX_MAGIC || ctx->dbg.valid != 1) {
        return CE_ERR_CTX;
    }
    if (ctx->reduced_w < 1 || ctx->reduced_h < 1 || ctx->reduced_w > CE_CTX_MAX_SIDE
        || ctx->reduced_h > CE_CTX_MAX_SIDE) {
        return CE_ERR_CTX;
    }
    return CE_OK;
}

static size_t ce_debug_npixels(const ce_ctx *ctx)
{
    return (size_t)ctx->reduced_w * (size_t)ctx->reduced_h;
}

int ce_palette_debug_info(const ce_ctx *ctx, ce_palette_debug *out)
{
    const int rc = (out == NULL) ? CE_ERR_ARG : ce_debug_check(ctx);
    size_t i, n, zeros = 0;
    int c;
    if (rc != CE_OK) {
        return rc;
    }
    n = ce_debug_npixels(ctx);
    for (i = 0; i < n; ++i) {
        if (!(ctx->weights[i] > 0.0)) {
            ++zeros;
        }
    }
    out->reduced_width = ctx->reduced_w;
    out->reduced_height = ctx->reduced_h;
    out->n_clusters = ctx->dbg.n_clusters;
    for (c = 0; c < CE_PALETTE_K_MAX; ++c) {
        /* Campo a campo: el relleno no recibe bytes indeterminados. */
        const ce_cluster_debug *src = &ctx->dbg.clusters[c];
        ce_cluster_debug *dst = &out->clusters[c];
        const int used = c < ctx->dbg.n_clusters;
        dst->lab.L = used ? src->lab.L : 0.0;
        dst->lab.a = used ? src->lab.a : 0.0;
        dst->lab.b = used ? src->lab.b : 0.0;
        dst->rgb[0] = used ? src->rgb[0] : 0;
        dst->rgb[1] = used ? src->rgb[1] : 0;
        dst->rgb[2] = used ? src->rgb[2] : 0;
        dst->weight = used ? src->weight : 0.0;
        dst->fate = used ? src->fate : 0;
        dst->final_index = used ? src->final_index : 0;
        dst->group_head = used ? src->group_head : 0;
    }
    out->lloyd_iterations = ctx->dbg.lloyd_iterations;
    out->total_weight = ctx->dbg.total_weight;
    out->zero_weight_fraction = (double)zeros / (double)n;
    out->center_sigma_px = ctx->dbg.center_sigma_px;
    out->n_swatches = ctx->dbg.n_swatches;
    return CE_OK;
}

int ce_debug_reduced_rgb(const ce_ctx *ctx, uint8_t *out_rgb, size_t cap)
{
    int rc = ce_debug_check(ctx);
    size_t i, need;
    if (rc != CE_OK) {
        return rc;
    }
    need = ce_debug_npixels(ctx) * 3u;
    if (out_rgb == NULL || cap < need) {
        return CE_ERR_ARG;
    }
    for (i = 0; i < need; ++i) {
        out_rgb[i] = ctx->reduced[i];
    }
    return (int)need;
}

int ce_debug_weight_map(const ce_ctx *ctx, uint8_t *out, size_t cap)
{
    int rc = ce_debug_check(ctx);
    size_t i, n;
    double wmax = 0.0;
    if (rc != CE_OK) {
        return rc;
    }
    n = ce_debug_npixels(ctx);
    if (out == NULL || cap < n) {
        return CE_ERR_ARG;
    }
    for (i = 0; i < n; ++i) {
        if (ctx->weights[i] > wmax) {
            wmax = ctx->weights[i];
        }
    }
    for (i = 0; i < n; ++i) {
        const double w = ctx->weights[i];
        if (wmax > 0.0 && w > 0.0) {
            const double v = w / wmax * 255.0 + 0.5; /* w <= wmax => v <= 255.5 */
            out[i] = (uint8_t)(v >= 255.0 ? 255 : (int)v);
        } else {
            out[i] = 0;
        }
    }
    return (int)n;
}

/* Centro de Lloyd del píxel reducido i (índice previo a la compactación), o
 * -1 si su peso es 0 o su bin no tiene centro. */
static int ce_debug_pixel_center(const ce_ctx *ctx, size_t i)
{
    const uint8_t *p = ctx->reduced + i * 3u;
    const ce_hist_bin *bin;
    if (!(ctx->weights[i] > 0.0)) {
        return -1;
    }
    bin = &ctx->hist[CE_HIST_INDEX(p[0] >> CE_HIST_SHIFT, p[1] >> CE_HIST_SHIFT, p[2] >> CE_HIST_SHIFT)];
    if (!(bin->wsum > 0.0) || bin->center < 0 || bin->center >= CE_PALETTE_K_MAX) {
        return -1;
    }
    return bin->center;
}

int ce_debug_label_map(const ce_ctx *ctx, uint8_t *out, size_t cap)
{
    int rc = ce_debug_check(ctx);
    size_t i, n;
    if (rc != CE_OK) {
        return rc;
    }
    n = ce_debug_npixels(ctx);
    if (out == NULL || cap < n) {
        return CE_ERR_ARG;
    }
    for (i = 0; i < n; ++i) {
        const int c = ce_debug_pixel_center(ctx, i);
        out[i] = (c < 0) ? (uint8_t)CE_LABEL_NONE : ctx->dbg.center_label[c];
    }
    return (int)n;
}

int ce_debug_cluster_map(const ce_ctx *ctx, uint8_t *out, size_t cap)
{
    int rc = ce_debug_check(ctx);
    size_t i, n;
    if (rc != CE_OK) {
        return rc;
    }
    n = ce_debug_npixels(ctx);
    if (out == NULL || cap < n) {
        return CE_ERR_ARG;
    }
    for (i = 0; i < n; ++i) {
        const int c = ce_debug_pixel_center(ctx, i);
        out[i] = (c < 0) ? (uint8_t)CE_LABEL_NONE : ctx->dbg.center_cluster[c];
    }
    return (int)n;
}

/* ------------------------------------------------------------------------
 * Explicación del match
 * ---------------------------------------------------------------------- */

int ce_match_explain_combo(const ce_ctx *ctx, const ce_swatch *sw, int n, const ce_match_opts *o,
                           int combo_id, ce_match_explain *out)
{
    ce_match_opts def;
    double bradford[CE_MATCH_N_ILLS][9];
    double dist[CE_PALETTE_MAX_COLORS][CE_DICT_COMBO_MAX];
    uint8_t size = 0;
    uint8_t colors[CE_DICT_COMBO_MAX];
    double best = HUGE_VAL;
    int have = 0, steps, ill, step, i, j, ncombos;

    if (ctx == NULL || sw == NULL || out == NULL) {
        return CE_ERR_ARG;
    }
    if (n < 1 || n > CE_PALETTE_MAX_COLORS) {
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
    ncombos = ce_dict_num_combos();
    if (combo_id < 1 || combo_id > ncombos) {
        return CE_ERR_ARG;
    }
    if (ce_dict_combo(combo_id, &size, colors) != 0 || size < 1 || size > CE_DICT_COMBO_MAX) {
        return CE_ERR_ARG;
    }
    for (j = 0; j < (int)size; ++j) {
        if (colors[j] >= ctx->dict_n) {
            return CE_ERR_CTX; /* caché Lab incoherente con la tabla */
        }
    }

    /* Mismo recorrido y mismas expresiones que ce_match (ce_match.c). */
    steps = (int)(o->exposure_ev_max / CE_MATCH_EV_STEP + 1e-9);
    if (steps > CE_MATCH_MAX_STEPS) steps = CE_MATCH_MAX_STEPS;
    if (o->illuminant_search) {
        for (ill = 0; ill < CE_MATCH_N_ILLS; ++ill) {
            ce_bradford_matrix(ce_match_hyp_illuminant(ill), CE_ILL_D65, bradford[ill]);
        }
    }
    for (ill = -1; ill < (o->illuminant_search ? CE_MATCH_N_ILLS : 0); ++ill) {
        const double *m = (ill < 0) ? NULL : bradford[ill];
        const double pen_ill = (ill < 0) ? 0.0 : o->illuminant_penalty;
        for (step = 0; step <= 2 * steps; ++step) {
            const int k = (step == 0) ? 0 : ((step & 1) ? -((step + 1) / 2) : (step / 2));
            const double ev = (double)k * CE_MATCH_EV_STEP;
            const double penalty = pen_ill + o->exposure_penalty * ((ev < 0.0) ? -ev : ev);
            const int identity = (ill < 0 && k == 0);
            const double gain = identity ? 1.0 : ce_pow(2.0, ev);
            double fit = 0.0, coverage = 0.0, coverage_term, score;
            for (i = 0; i < n; ++i) {
                const ce_lab lab = identity ? sw[i].lab : ce_match_adapt_lab(sw[i].lab, m, gain);
                for (j = 0; j < (int)size; ++j) {
                    dist[i][j] = ce_de2000_k(lab, ctx->dict_lab[colors[j]], o->kL, o->kC, o->kH);
                }
            }
            for (i = 0; i < n; ++i) {
                double mn = HUGE_VAL;
                for (j = 0; j < (int)size; ++j) {
                    const double d = dist[i][j];
                    if (d < mn) mn = d;
                }
                fit += sw[i].weight * mn;
            }
            for (j = 0; j < (int)size; ++j) {
                double mn = HUGE_VAL;
                for (i = 0; i < n; ++i) {
                    const double d = dist[i][j];
                    if (d < mn) mn = d;
                }
                coverage += mn;
            }
            coverage_term = o->coverage_lambda * (coverage / (double)size);
            score = fit + coverage_term + penalty;
            if (score != score) {
                score = HUGE_VAL; /* como ce_match: un NaN va al final */
            }
            if (!have || score < best) {
                have = 1;
                best = score;
                out->combo_id = (uint16_t)combo_id;
                out->score = score;
                out->fit_term = fit;
                out->coverage_term = coverage_term;
                out->hypothesis_penalty = penalty;
                out->exposure_ev = ev;
                out->illuminant = (ill < 0) ? -1 : (int)ce_match_hyp_illuminant(ill);
                out->n_swatches = n;
                out->combo_size = (int)size;
                for (i = 0; i < CE_PALETTE_MAX_COLORS; ++i) {
                    int bj = -1;
                    double mn = HUGE_VAL;
                    if (i < n) {
                        for (j = 0; j < (int)size; ++j) {
                            if (bj < 0 || dist[i][j] < mn) {
                                mn = dist[i][j];
                                bj = j;
                            }
                        }
                    }
                    out->per_swatch[i].nearest_color_index = (i < n) ? (int)colors[bj] : -1;
                    out->per_swatch[i].de = (i < n) ? mn : 0.0;
                }
                for (j = 0; j < CE_DICT_MAX_COLORS; ++j) {
                    int bi = -1;
                    double mn = HUGE_VAL;
                    if (j < (int)size) {
                        for (i = 0; i < n; ++i) {
                            if (bi < 0 || dist[i][j] < mn) {
                                mn = dist[i][j];
                                bi = i;
                            }
                        }
                    }
                    out->per_color[j].color_index = (j < (int)size) ? (int)colors[j] : -1;
                    out->per_color[j].nearest_swatch = bi;
                    out->per_color[j].de = (j < (int)size) ? mn : 0.0;
                }
            }
        }
    }
    return CE_OK;
}
