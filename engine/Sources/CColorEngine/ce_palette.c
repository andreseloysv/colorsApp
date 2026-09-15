/*
 * ce_palette.c — extracción de paleta (capa 2): histograma 5 bits/canal ->
 * median cut modificado (MMCQ) -> Lloyd ponderado en Lab -> fusión ΔE00 ->
 * descarte por peso -> orden y recorte. Determinista: sin RNG, bins siempre
 * en orden de índice, empates al índice menor.
 *
 * Reglas: C11, sin I/O, sin malloc, todo en double, sin contracción FMA.
 * Funciones de libm usadas: las de ce_math (pow/cbrt/atan2/sin/cos/exp) y
 * exp en la gaussiana (ce_image.c).
 *
 * Al final del fichero viven los stubs de la fase 3 (ce_match, ce_analyze):
 * devuelven CE_ERR_NOT_IMPLEMENTED hasta que exista ce_match.c.
 */
#include "ce_internal.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>

#pragma STDC FP_CONTRACT OFF

/* Fracción de cortes MMCQ decididos por población (Leptonica colorquant2.c). */
#define CE_MMCQ_FRACT_BY_POPULATION 0.85
/* Cota superior de iteraciones de Lloyd admitida en las opciones. */
#define CE_PALETTE_MAX_ITERS 1000

/* ------------------------------------------------------------------------
 * Opciones
 * ---------------------------------------------------------------------- */

void ce_palette_opts_default(ce_palette_opts *o)
{
    if (o == NULL) {
        return;
    }
    o->k_init = 6;
    o->max_iters = 20;
    o->max_colors = 5;
    o->max_side = CE_PALETTE_MAX_SIDE;
    o->center_sigma = 0.35;
    o->merge_de = 5.0;
    o->min_weight = 0.05;
    o->skin_rule = 0;
}

void ce_match_opts_default(ce_match_opts *o)
{
    if (o == NULL) {
        return;
    }
    o->kL = 1.0;
    o->kC = 1.0;
    o->kH = 1.0;
    o->coverage_lambda = 0.5;
    o->ambiguous_gap = 1.0;
}

static int ce_opts_valid(const ce_palette_opts *o)
{
    if (o->k_init < 1 || o->k_init > CE_PALETTE_K_MAX) return 0;
    if (o->max_iters < 0 || o->max_iters > CE_PALETTE_MAX_ITERS) return 0;
    if (o->max_colors < 1 || o->max_colors > CE_PALETTE_MAX_COLORS) return 0;
    if (o->max_side < 1 || o->max_side > CE_PALETTE_MAX_SIDE) return 0;
    if (isnan(o->center_sigma) || isnan(o->merge_de) || isnan(o->min_weight)) return 0;
    return 1;
}

/* ------------------------------------------------------------------------
 * Histograma
 * ---------------------------------------------------------------------- */

static void ce_hist_clear(ce_ctx *ctx)
{
    int i;
    for (i = 0; i < CE_HIST_BINS; ++i) {
        ce_hist_bin *b = &ctx->hist[i];
        b->wsum = 0.0;
        b->c[0] = 0.0;
        b->c[1] = 0.0;
        b->c[2] = 0.0;
        b->count = 0;
        b->center = -1;
    }
}

/* Acumula la imagen reducida. Con peso 1.0 las sumas son enteras exactas
 * (<= 255 * 65536 < 2^53): el resultado no depende del orden de los píxeles. */
static void ce_hist_accumulate(ce_ctx *ctx)
{
    const size_t n = (size_t)ctx->reduced_w * (size_t)ctx->reduced_h;
    size_t i;
    for (i = 0; i < n; ++i) {
        const uint8_t *p = ctx->reduced + i * 3;
        const double w = ctx->weights[i];
        ce_hist_bin *b = &ctx->hist[CE_HIST_INDEX(p[0] >> CE_HIST_SHIFT, p[1] >> CE_HIST_SHIFT,
                                                 p[2] >> CE_HIST_SHIFT)];
        b->count++;
        if (w > 0.0) {
            b->wsum += w;
            b->c[0] += w * (double)p[0];
            b->c[1] += w * (double)p[1];
            b->c[2] += w * (double)p[2];
        }
    }
}

/* Color medio (sin cuantizar) de cada bin con peso -> Lab en c[]. Devuelve
 * el peso total. */
static double ce_hist_finalize(ce_ctx *ctx)
{
    double total = 0.0;
    int i;
    for (i = 0; i < CE_HIST_BINS; ++i) {
        ce_hist_bin *b = &ctx->hist[i];
        if (b->wsum > 0.0) {
            const double r = b->c[0] / b->wsum;
            const double g = b->c[1] / b->wsum;
            const double bl = b->c[2] / b->wsum;
            const ce_lab lab = ce_srgb_to_lab(r / 255.0, g / 255.0, bl / 255.0);
            b->c[0] = lab.L;
            b->c[1] = lab.a;
            b->c[2] = lab.b;
            total += b->wsum;
        }
    }
    return total;
}

/* ------------------------------------------------------------------------
 * Median cut modificado (Heckbert 1982 / Leptonica colorquant2.c)
 * ---------------------------------------------------------------------- */

/* Encoge la caja al menor paralelepípedo que contiene sus bins con peso y
 * recalcula población, volumen y si es divisible. */
static void ce_box_shrink(const ce_ctx *ctx, ce_box *box)
{
    int lo[3] = {CE_HIST_SIDE, CE_HIST_SIDE, CE_HIST_SIDE};
    int hi[3] = {-1, -1, -1};
    double wsum = 0.0;
    int r, g, b, k;
    for (r = box->lo[0]; r <= box->hi[0]; ++r) {
        for (g = box->lo[1]; g <= box->hi[1]; ++g) {
            for (b = box->lo[2]; b <= box->hi[2]; ++b) {
                const ce_hist_bin *bin = &ctx->hist[CE_HIST_INDEX(r, g, b)];
                if (bin->wsum > 0.0) {
                    wsum += bin->wsum;
                    if (r < lo[0]) lo[0] = r;
                    if (r > hi[0]) hi[0] = r;
                    if (g < lo[1]) lo[1] = g;
                    if (g > hi[1]) hi[1] = g;
                    if (b < lo[2]) lo[2] = b;
                    if (b > hi[2]) hi[2] = b;
                }
            }
        }
    }
    box->wsum = wsum;
    if (hi[0] < 0) {
        /* Caja vacía (no debería ocurrir: los cortes dejan peso a ambos lados). */
        box->volume = 0;
        box->splittable = 0;
        return;
    }
    box->volume = 1;
    box->splittable = 0;
    for (k = 0; k < 3; ++k) {
        box->lo[k] = lo[k];
        box->hi[k] = hi[k];
        box->volume *= hi[k] - lo[k] + 1;
        if (hi[k] > lo[k]) {
            box->splittable = 1;
        }
    }
}

/* Población de la rebanada `i` de la caja a lo largo del eje `axis`. */
static double ce_box_slice(const ce_ctx *ctx, const ce_box *box, int axis, int i)
{
    double s = 0.0;
    int c[3];
    int u, v;
    const int a1 = (axis + 1) % 3;
    const int a2 = (axis + 2) % 3;
    c[axis] = i;
    for (u = box->lo[a1]; u <= box->hi[a1]; ++u) {
        c[a1] = u;
        for (v = box->lo[a2]; v <= box->hi[a2]; ++v) {
            c[a2] = v;
            s += ctx->hist[CE_HIST_INDEX(c[0], c[1], c[2])].wsum;
        }
    }
    return s;
}

/* Divide boxes[src] en boxes[src] y boxes[dst]. Precondición: splittable.
 * Eje más largo (empates: r, g, b); mediana de población; el corte se aleja de
 * la mediana hacia el lado más largo (regla de Leptonica), acotado a
 * [lo, hi-1] para que ambas mitades conserven peso (los extremos están
 * encogidos, así que sus rebanadas tienen peso). */
static void ce_box_split(ce_ctx *ctx, int src, int dst)
{
    ce_box *box = &ctx->boxes[src];
    ce_box *other = &ctx->boxes[dst];
    int axis = 0, k, i, lo, hi, median, left, right, cut;
    double total, half, acc;

    for (k = 1; k < 3; ++k) {
        if (box->hi[k] - box->lo[k] > box->hi[axis] - box->lo[axis]) {
            axis = k;
        }
    }
    lo = box->lo[axis];
    hi = box->hi[axis];
    acc = 0.0;
    for (i = lo; i <= hi; ++i) {
        acc += ce_box_slice(ctx, box, axis, i);
        ctx->axis_partial[i] = acc;
    }
    total = acc;
    half = total / 2.0;
    median = hi;
    for (i = lo; i <= hi; ++i) {
        if (ctx->axis_partial[i] > half) {
            median = i;
            break;
        }
    }
    left = median - lo;
    right = hi - median;
    if (left <= right) {
        cut = median + right / 2;
        if (cut > hi - 1) cut = hi - 1;
    } else {
        cut = median - 1 - left / 2;
        if (cut < lo) cut = lo;
    }
    *other = *box;
    box->hi[axis] = cut;
    other->lo[axis] = cut + 1;
    ce_box_shrink(ctx, box);
    ce_box_shrink(ctx, other);
}

/* Construye hasta k cajas; devuelve cuántas. Los primeros cortes se eligen
 * por población y el resto por población x volumen; siempre la caja de mayor
 * prioridad entre las divisibles (empates: índice menor). */
static int ce_mmcq(ce_ctx *ctx, int k)
{
    int nboxes = 1;
    const int by_pop = (int)(CE_MMCQ_FRACT_BY_POPULATION * (double)k);
    ce_box *root = &ctx->boxes[0];
    root->lo[0] = root->lo[1] = root->lo[2] = 0;
    root->hi[0] = root->hi[1] = root->hi[2] = CE_HIST_SIDE - 1;
    ce_box_shrink(ctx, root);
    if (root->volume == 0) {
        return 0;
    }
    while (nboxes < k) {
        int best = -1, j;
        double best_pri = -1.0;
        for (j = 0; j < nboxes; ++j) {
            const ce_box *b = &ctx->boxes[j];
            double pri;
            if (!b->splittable) {
                continue;
            }
            pri = (nboxes < by_pop) ? b->wsum : b->wsum * (double)b->volume;
            if (pri > best_pri) {
                best_pri = pri;
                best = j;
            }
        }
        if (best < 0) {
            break;
        }
        ce_box_split(ctx, best, nboxes);
        ++nboxes;
    }
    return nboxes;
}

/* Asigna cada bin con peso a la caja que lo contiene (partición del cubo). */
static void ce_assign_from_boxes(ce_ctx *ctx, int nboxes)
{
    int j, r, g, b;
    for (j = 0; j < nboxes; ++j) {
        const ce_box *box = &ctx->boxes[j];
        for (r = box->lo[0]; r <= box->hi[0]; ++r) {
            for (g = box->lo[1]; g <= box->hi[1]; ++g) {
                for (b = box->lo[2]; b <= box->hi[2]; ++b) {
                    ce_hist_bin *bin = &ctx->hist[CE_HIST_INDEX(r, g, b)];
                    if (bin->wsum > 0.0) {
                        bin->center = j;
                    }
                }
            }
        }
    }
}

/* ------------------------------------------------------------------------
 * Lloyd ponderado en Lab
 * ---------------------------------------------------------------------- */

static double ce_lab_dist2(const double *c, const ce_lab *lab)
{
    const double dL = c[0] - lab->L;
    const double da = c[1] - lab->a;
    const double db = c[2] - lab->b;
    return dL * dL + da * da + db * db;
}

/* Recalcula cada centro como media ponderada de sus bins (orden de índice).
 * Un centro sin bins conserva su Lab y queda con wsum 0. */
static void ce_lloyd_update(ce_ctx *ctx, int k)
{
    int i, j;
    for (j = 0; j < k; ++j) {
        ce_center *c = &ctx->centers[j];
        c->wsum = 0.0;
        c->sum[0] = c->sum[1] = c->sum[2] = 0.0;
    }
    for (i = 0; i < CE_HIST_BINS; ++i) {
        const ce_hist_bin *bin = &ctx->hist[i];
        ce_center *c;
        if (bin->wsum <= 0.0 || bin->center < 0) {
            continue;
        }
        c = &ctx->centers[bin->center];
        c->wsum += bin->wsum;
        c->sum[0] += bin->wsum * bin->c[0];
        c->sum[1] += bin->wsum * bin->c[1];
        c->sum[2] += bin->wsum * bin->c[2];
    }
    for (j = 0; j < k; ++j) {
        ce_center *c = &ctx->centers[j];
        if (c->wsum > 0.0) {
            c->lab.L = c->sum[0] / c->wsum;
            c->lab.a = c->sum[1] / c->wsum;
            c->lab.b = c->sum[2] / c->wsum;
        }
    }
}

/* Asigna cada bin al centro más cercano (ΔE76 al cuadrado; empates al índice
 * menor). Devuelve 1 si alguna asignación cambió. */
static int ce_lloyd_assign(ce_ctx *ctx, int k)
{
    int changed = 0, i, j;
    for (i = 0; i < CE_HIST_BINS; ++i) {
        ce_hist_bin *bin = &ctx->hist[i];
        int best = 0;
        double best_d;
        if (bin->wsum <= 0.0) {
            continue;
        }
        best_d = ce_lab_dist2(bin->c, &ctx->centers[0].lab);
        for (j = 1; j < k; ++j) {
            const double d = ce_lab_dist2(bin->c, &ctx->centers[j].lab);
            if (d < best_d) {
                best_d = d;
                best = j;
            }
        }
        if (bin->center != best) {
            bin->center = best;
            changed = 1;
        }
    }
    return changed;
}

/* ------------------------------------------------------------------------
 * Fusión, descarte, orden
 * ---------------------------------------------------------------------- */

/* Elimina los centros sin peso; devuelve cuántos quedan. */
static int ce_centers_compact(ce_ctx *ctx, int k)
{
    int j, n = 0;
    for (j = 0; j < k; ++j) {
        if (ctx->centers[j].wsum > 0.0) {
            if (n != j) {
                ctx->centers[n] = ctx->centers[j];
            }
            ++n;
        }
    }
    return n;
}

/* Fusiona iterativamente el par más próximo mientras ΔE00 < merge_de. */
static int ce_centers_merge(ce_ctx *ctx, int n, double merge_de)
{
    if (!(merge_de > 0.0)) {
        return n;
    }
    while (n > 1) {
        int bi = -1, bj = -1, i, j;
        double best = HUGE_VAL;
        for (i = 0; i < n; ++i) {
            for (j = i + 1; j < n; ++j) {
                const double d = ce_de2000(ctx->centers[i].lab, ctx->centers[j].lab);
                if (d < best) {
                    best = d;
                    bi = i;
                    bj = j;
                }
            }
        }
        if (bi < 0 || !(best < merge_de)) {
            break;
        }
        {
            ce_center *a = &ctx->centers[bi];
            const ce_center *b = &ctx->centers[bj];
            const double w = a->wsum + b->wsum;
            a->lab.L = (a->wsum * a->lab.L + b->wsum * b->lab.L) / w;
            a->lab.a = (a->wsum * a->lab.a + b->wsum * b->lab.a) / w;
            a->lab.b = (a->wsum * a->lab.b + b->wsum * b->lab.b) / w;
            a->wsum = w;
        }
        for (j = bj + 1; j < n; ++j) {
            ctx->centers[j - 1] = ctx->centers[j];
        }
        --n;
    }
    return n;
}

/* Descarta los centros con peso relativo < min_weight; el más pesado (primero
 * en caso de empate) siempre se conserva. */
static int ce_centers_discard(ce_ctx *ctx, int n, double min_weight)
{
    double total = 0.0;
    int heaviest = 0, j, m = 0;
    if (!(min_weight > 0.0)) {
        return n;
    }
    for (j = 0; j < n; ++j) {
        total += ctx->centers[j].wsum;
        if (ctx->centers[j].wsum > ctx->centers[heaviest].wsum) {
            heaviest = j;
        }
    }
    for (j = 0; j < n; ++j) {
        if (j == heaviest || ctx->centers[j].wsum / total >= min_weight) {
            if (m != j) {
                ctx->centers[m] = ctx->centers[j];
            }
            ++m;
        }
    }
    return m;
}

/* Orden total: peso desc, luego L, a, b asc, luego índice original. */
static int ce_center_before(const ce_center *a, int ia, const ce_center *b, int ib)
{
    if (a->wsum != b->wsum) return a->wsum > b->wsum;
    if (a->lab.L != b->lab.L) return a->lab.L < b->lab.L;
    if (a->lab.a != b->lab.a) return a->lab.a < b->lab.a;
    if (a->lab.b != b->lab.b) return a->lab.b < b->lab.b;
    return ia < ib;
}

/* Inserción estable sobre un vector de índices (n <= CE_PALETTE_K_MAX). */
static void ce_centers_sort(const ce_ctx *ctx, int n, int *order)
{
    int i, j;
    for (i = 0; i < n; ++i) {
        order[i] = i;
    }
    for (i = 1; i < n; ++i) {
        const int v = order[i];
        j = i - 1;
        while (j >= 0 && ce_center_before(&ctx->centers[v], v, &ctx->centers[order[j]], order[j])) {
            order[j + 1] = order[j];
            --j;
        }
        order[j + 1] = v;
    }
}

static void ce_swatch_from_lab(ce_swatch *sw, ce_lab lab, double weight)
{
    sw->lab = lab;
    ce_lab_to_srgb8(lab, &sw->rgb[0], &sw->rgb[1], &sw->rgb[2]);
    sw->weight = weight;
}

/* Peso total 0: un swatch con el color medio (sin ponderar) de la reducida. */
static int ce_palette_fallback_mean(const ce_ctx *ctx, ce_swatch *out)
{
    const size_t n = (size_t)ctx->reduced_w * (size_t)ctx->reduced_h;
    uint64_t sr = 0, sg = 0, sb = 0;
    size_t i;
    ce_lab lab;
    for (i = 0; i < n; ++i) {
        sr += ctx->reduced[i * 3 + 0];
        sg += ctx->reduced[i * 3 + 1];
        sb += ctx->reduced[i * 3 + 2];
    }
    lab = ce_srgb_to_lab((double)sr / (double)n / 255.0,
                         (double)sg / (double)n / 255.0,
                         (double)sb / (double)n / 255.0);
    ce_swatch_from_lab(out, lab, 1.0);
    return 1;
}

/* ------------------------------------------------------------------------
 * API
 * ---------------------------------------------------------------------- */

int ce_palette_extract(ce_ctx *ctx, const ce_image *img, const ce_palette_opts *o,
                       ce_swatch *out, int cap)
{
    ce_palette_opts def;
    int rc, n_max, nboxes, k, n, it, j;
    int order[CE_PALETTE_K_MAX];
    double total;

    if (ctx == NULL || img == NULL || out == NULL || cap < 1) {
        return CE_ERR_ARG;
    }
    if (ctx->magic != CE_CTX_MAGIC) {
        return CE_ERR_CTX;
    }
    rc = ce_image_validate(img);
    if (rc != CE_OK) {
        return rc;
    }
    if (o == NULL) {
        ce_palette_opts_default(&def);
        o = &def;
    }
    if (!ce_opts_valid(o)) {
        return CE_ERR_OPTS;
    }
    n_max = o->max_colors < cap ? o->max_colors : cap;

    /* 1-2. Reducción y pesos. */
    ce_image_reduce(ctx, img, o->max_side);
    if (o->center_sigma > 0.0) {
        const int m = ctx->reduced_w < ctx->reduced_h ? ctx->reduced_w : ctx->reduced_h;
        ce_image_apply_center_weight(ctx, o->center_sigma * (double)m);
    }
    if (o->skin_rule != 0) {
        ce_image_apply_skin_rule(ctx);
    }

    /* 3. Histograma. */
    ce_hist_clear(ctx);
    ce_hist_accumulate(ctx);
    total = ce_hist_finalize(ctx);
    if (!(total > 0.0)) {
        return ce_palette_fallback_mean(ctx, out);
    }

    /* 4. MMCQ -> asignación inicial y centros. */
    nboxes = ce_mmcq(ctx, o->k_init);
    if (nboxes < 1) {
        return ce_palette_fallback_mean(ctx, out);
    }
    ce_assign_from_boxes(ctx, nboxes);
    k = nboxes;
    ce_lloyd_update(ctx, k);

    /* 5. Lloyd. */
    for (it = 0; it < o->max_iters; ++it) {
        if (!ce_lloyd_assign(ctx, k)) {
            break;
        }
        ce_lloyd_update(ctx, k);
    }

    /* 6. Fusión y descarte. */
    n = ce_centers_compact(ctx, k);
    n = ce_centers_merge(ctx, n, o->merge_de);
    n = ce_centers_discard(ctx, n, o->min_weight);

    /* 7. Orden, recorte, normalización. */
    ce_centers_sort(ctx, n, order);
    if (n > n_max) {
        n = n_max;
    }
    total = 0.0;
    for (j = 0; j < n; ++j) {
        total += ctx->centers[order[j]].wsum;
    }
    for (j = 0; j < n; ++j) {
        const ce_center *c = &ctx->centers[order[j]];
        ce_swatch_from_lab(&out[j], c->lab, c->wsum / total);
    }
    return n;
}

int ce_dict_nearest_color(ce_lab lab, double *de)
{
    const int n = ce_dict_num_colors();
    int best = -1, i;
    double best_d = HUGE_VAL;
    if (isnan(lab.L) || isnan(lab.a) || isnan(lab.b)) {
        if (de != NULL) {
            *de = NAN;
        }
        return -1;
    }
    for (i = 0; i < n; ++i) {
        const double d = ce_de2000(lab, ce_dict_color_lab(i));
        if (d < best_d) {
            best_d = d;
            best = i;
        }
    }
    if (de != NULL) {
        *de = best_d;
    }
    return best;
}

/* ------------------------------------------------------------------------
 * Hashes FNV-1a (misma plataforma)
 * ---------------------------------------------------------------------- */

static uint64_t ce_fnv1a_bytes(uint64_t h, const unsigned char *p, size_t n)
{
    size_t i;
    for (i = 0; i < n; ++i) {
        h ^= (uint64_t)p[i];
        h *= 0x100000001b3ULL;
    }
    return h;
}

static uint64_t ce_fnv1a_double(uint64_t h, double v)
{
    union {
        double d;
        unsigned char b[sizeof(double)];
    } u;
    u.d = v;
    return ce_fnv1a_bytes(h, u.b, sizeof u.b);
}

static uint64_t ce_swatch_hash_from(uint64_t h, const ce_swatch *sw, int n)
{
    int i;
    if (sw == NULL || n < 0) {
        n = 0;
    }
    for (i = 0; i < n; ++i) {
        h = ce_fnv1a_double(h, sw[i].lab.L);
        h = ce_fnv1a_double(h, sw[i].lab.a);
        h = ce_fnv1a_double(h, sw[i].lab.b);
        h = ce_fnv1a_double(h, sw[i].weight);
    }
    return h;
}

uint64_t ce_swatch_hash(const ce_swatch *sw, int n)
{
    return ce_swatch_hash_from(0xcbf29ce484222325ULL, sw, n);
}

uint64_t ce_result_hash(const ce_result *r)
{
    uint64_t h = 0xcbf29ce484222325ULL;
    int i, n;
    if (r == NULL) {
        return h;
    }
    n = r->n_swatches;
    if (n > CE_PALETTE_MAX_COLORS) n = CE_PALETTE_MAX_COLORS;
    h = ce_swatch_hash_from(h, r->swatches, n);
    n = r->n_hits;
    if (n > (int)(sizeof r->hits / sizeof r->hits[0])) n = (int)(sizeof r->hits / sizeof r->hits[0]);
    for (i = 0; i < n; ++i) {
        unsigned char id[2];
        id[0] = (unsigned char)(r->hits[i].combo_id & 0xFF);
        id[1] = (unsigned char)(r->hits[i].combo_id >> 8);
        h = ce_fnv1a_bytes(h, id, 2);
        h = ce_fnv1a_double(h, r->hits[i].score);
    }
    {
        const unsigned char amb = (unsigned char)(r->ambiguous != 0);
        h = ce_fnv1a_bytes(h, &amb, 1);
    }
    return h;
}

/* ------------------------------------------------------------------------
 * Fase 3 (stubs): ce_match.c los sustituirá.
 * ---------------------------------------------------------------------- */

int ce_match(const ce_ctx *ctx, const ce_swatch *sw, int n, const ce_match_opts *o,
             ce_hit *out, int top_k, int *ambiguous)
{
    (void)ctx; (void)sw; (void)n; (void)o; (void)out; (void)top_k; (void)ambiguous;
    return CE_ERR_NOT_IMPLEMENTED;
}

int ce_analyze(ce_ctx *ctx, const ce_image *img, const ce_palette_opts *po,
               const ce_match_opts *mo, ce_result *out)
{
    (void)ctx; (void)img; (void)po; (void)mo; (void)out;
    return CE_ERR_NOT_IMPLEMENTED;
}
