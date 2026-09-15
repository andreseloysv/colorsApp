/*
 * test_debug.c — capas de depuración (ce_debug.c) con Unity: lo que la app y
 * `ce ... --debug-dir` muestran para entender de dónde sale cada color.
 *
 * Composición sintética 200x200 (uniforme, center_sigma 0):
 *   A rojo (filas 0..99, cols 0..99) con un bloque diminuto magenta 6x6
 *   (0,12 % del peso < min_weight), B azul (filas 0..99, cols 100..199),
 *   C verde (filas 100..199, cols 0..99) y D amarillo (filas 100..199,
 *   cols 100..199) anulado por la máscara.
 *  (1) label map: cada bloque con el índice de su swatch, D con CE_LABEL_NONE,
 *      el magenta con CE_LABEL_DISCARDED y su cluster con fate 2;
 *      zero_weight_fraction = 0,25; reduced/weight map exactos.
 *  (2) dos rojos casi iguales (ΔE00 < merge_de, bins distintos): uno de los dos
 *      clusters con fate 1 y final_index = el swatch rojo; los dos bloques con
 *      la misma etiqueta. max_colors 2 -> el tercer grupo con fate 3.
 *  (3) Σ weight_map por etiqueta / Σ total reproduce el peso de cada swatch
 *      (±1 punto), también con peso al centro (sigma 0,35).
 *  (4) ce_match_explain_combo: score bit a bit igual al de ce_match en el
 *      top-10 (opciones por defecto y match v0, paleta de la imagen y paletas
 *      aleatorias), y fit_term + coverage_term + hypothesis_penalty == score.
 *  (5) errores: CE_ERR_CTX sin extracción (ctx recién iniciado, tras una
 *      extracción fallida y con memoria a cero), CE_ERR_ARG con buffers cortos
 *      o nulos sin escribir.
 *  (6) paridad: hash FNV-1a de todas las capas y de la explicación igual a una
 *      constante: el mismo binario pasa en nativo, ASan y WASM, así que las
 *      capas son bit a bit idénticas entre plataformas.
 */
#include "ce/ce.h"
#include "unity.h"

#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma STDC FP_CONTRACT OFF

void setUp(void) {}
void tearDown(void) {}

#define W 200
#define H 200

static const uint8_t RED[3] = {200, 30, 40};
static const uint8_t RED2[3] = {208, 38, 48}; /* bins distintos, ΔE00 ~ 2,6 */
static const uint8_t BLUE[3] = {30, 60, 200};
static const uint8_t GREEN[3] = {40, 180, 60};
static const uint8_t YELLOW[3] = {230, 210, 40};
static const uint8_t MAGENTA[3] = {200, 30, 200};

static ce_ctx *ctx_new(void **mem)
{
    ce_ctx *ctx;
    *mem = aligned_alloc(16, ce_ctx_size());
    TEST_ASSERT_NOT_NULL(*mem);
    ctx = ce_ctx_init(*mem, ce_ctx_size());
    TEST_ASSERT_NOT_NULL(ctx);
    return ctx;
}

static void put(uint8_t *px, int x, int y, const uint8_t *c)
{
    uint8_t *p = px + (size_t)y * (size_t)W * 3u + (size_t)x * 3u;
    p[0] = c[0];
    p[1] = c[1];
    p[2] = c[2];
}

/* Composición del caso (1); `a2` != NULL pinta la mitad derecha de A con ese
 * color (caso de fusión) y omite el magenta. */
static void fill_scene(uint8_t *px, uint8_t *mask, const uint8_t *a2)
{
    int x, y;
    for (y = 0; y < H; ++y) {
        for (x = 0; x < W; ++x) {
            const uint8_t *c = (y < 100) ? ((x < 100) ? RED : BLUE) : ((x < 100) ? GREEN : YELLOW);
            if (a2 != NULL && y < 100 && x >= 50 && x < 100) {
                c = a2;
            }
            if (a2 == NULL && y >= 40 && y < 46 && x >= 40 && x < 46) {
                c = MAGENTA;
            }
            put(px, x, y, c);
            mask[(size_t)y * W + (size_t)x] = (y >= 100 && x >= 100) ? 0 : 255;
        }
    }
}

static ce_image image_of(const uint8_t *px, const uint8_t *mask)
{
    ce_image img;
    img.pixels = px;
    img.width = W;
    img.height = H;
    img.stride_bytes = W * 3;
    img.fmt = CE_RGB8;
    img.mask = mask;
    return img;
}

static int swatch_index_of(const ce_swatch *sw, int n, const uint8_t *rgb)
{
    const ce_lab lab = ce_srgb8_to_lab(rgb[0], rgb[1], rgb[2]);
    int i, best = -1;
    double best_d = 1e300;
    for (i = 0; i < n; ++i) {
        const double d = ce_de2000(sw[i].lab, lab);
        if (d < best_d) {
            best_d = d;
            best = i;
        }
    }
    return best_d < 1.0 ? best : -1;
}

static uint64_t fnv_bytes(uint64_t h, const void *data, size_t n)
{
    const unsigned char *p = (const unsigned char *)data;
    size_t i;
    for (i = 0; i < n; ++i) {
        h ^= p[i];
        h *= 0x100000001b3ULL;
    }
    return h;
}

static uint64_t fnv_double(uint64_t h, double v)
{
    return fnv_bytes(h, &v, sizeof v);
}

static uint64_t fnv_int(uint64_t h, int v)
{
    const int64_t w = v;
    return fnv_bytes(h, &w, sizeof w);
}

static uint64_t hash_debug(uint64_t h, const ce_palette_debug *d)
{
    int c;
    h = fnv_int(h, d->reduced_width);
    h = fnv_int(h, d->reduced_height);
    h = fnv_int(h, d->n_clusters);
    for (c = 0; c < d->n_clusters; ++c) {
        const ce_cluster_debug *cd = &d->clusters[c];
        h = fnv_double(h, cd->lab.L);
        h = fnv_double(h, cd->lab.a);
        h = fnv_double(h, cd->lab.b);
        h = fnv_bytes(h, cd->rgb, 3);
        h = fnv_double(h, cd->weight);
        h = fnv_int(h, cd->fate);
        h = fnv_int(h, cd->final_index);
        h = fnv_int(h, cd->group_head);
    }
    h = fnv_int(h, d->lloyd_iterations);
    h = fnv_double(h, d->total_weight);
    h = fnv_double(h, d->zero_weight_fraction);
    h = fnv_double(h, d->center_sigma_px);
    return fnv_int(h, d->n_swatches);
}

static uint64_t hash_explain(uint64_t h, const ce_match_explain *e)
{
    int i;
    h = fnv_int(h, e->combo_id);
    h = fnv_double(h, e->score);
    h = fnv_double(h, e->fit_term);
    h = fnv_double(h, e->coverage_term);
    h = fnv_double(h, e->hypothesis_penalty);
    h = fnv_double(h, e->exposure_ev);
    h = fnv_int(h, e->illuminant);
    h = fnv_int(h, e->n_swatches);
    for (i = 0; i < e->n_swatches; ++i) {
        h = fnv_int(h, e->per_swatch[i].nearest_color_index);
        h = fnv_double(h, e->per_swatch[i].de);
    }
    h = fnv_int(h, e->combo_size);
    for (i = 0; i < e->combo_size; ++i) {
        h = fnv_int(h, e->per_color[i].color_index);
        h = fnv_int(h, e->per_color[i].nearest_swatch);
        h = fnv_double(h, e->per_color[i].de);
    }
    return h;
}

/* Capas de un contexto con extracción válida (buffers exactos). */
typedef struct layers {
    ce_palette_debug info;
    uint8_t reduced[W * H * 3];
    uint8_t weights[W * H];
    uint8_t labels[W * H];
    uint8_t clusters[W * H];
} layers;

static void read_layers(const ce_ctx *ctx, layers *L)
{
    size_t n;
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_palette_debug_info(ctx, &L->info));
    n = (size_t)L->info.reduced_width * (size_t)L->info.reduced_height;
    TEST_ASSERT_EQUAL_INT((int)(n * 3u), ce_debug_reduced_rgb(ctx, L->reduced, sizeof L->reduced));
    TEST_ASSERT_EQUAL_INT((int)n, ce_debug_weight_map(ctx, L->weights, sizeof L->weights));
    TEST_ASSERT_EQUAL_INT((int)n, ce_debug_label_map(ctx, L->labels, sizeof L->labels));
    TEST_ASSERT_EQUAL_INT((int)n, ce_debug_cluster_map(ctx, L->clusters, sizeof L->clusters));
}

static uint64_t hash_layers(uint64_t h, const layers *L)
{
    const size_t n = (size_t)L->info.reduced_width * (size_t)L->info.reduced_height;
    h = hash_debug(h, &L->info);
    h = fnv_bytes(h, L->reduced, n * 3u);
    h = fnv_bytes(h, L->weights, n);
    h = fnv_bytes(h, L->labels, n);
    return fnv_bytes(h, L->clusters, n);
}

/* (3) Σ weight_map por etiqueta frente al peso de cada swatch (±0,01). */
static void assert_label_weights(const layers *L, const ce_swatch *sw, int n)
{
    double per[CE_PALETTE_MAX_COLORS] = {0};
    double total = 0.0;
    size_t i;
    const size_t np = (size_t)L->info.reduced_width * (size_t)L->info.reduced_height;
    int k;
    for (i = 0; i < np; ++i) {
        const int lab = L->labels[i];
        if (lab == CE_LABEL_NONE) {
            TEST_ASSERT_EQUAL_UINT8(0, L->weights[i]);
            continue;
        }
        if (lab == CE_LABEL_DISCARDED) {
            continue;
        }
        TEST_ASSERT_TRUE(lab < n);
        per[lab] += (double)L->weights[i];
        total += (double)L->weights[i];
    }
    TEST_ASSERT_TRUE(total > 0.0);
    for (k = 0; k < n; ++k) {
        char msg[96];
        snprintf(msg, sizeof msg, "swatch %d: peso %.5f, por etiquetas %.5f", k, sw[k].weight, per[k] / total);
        TEST_ASSERT_TRUE_MESSAGE(fabs(per[k] / total - sw[k].weight) <= 0.01, msg);
    }
}

static uint64_t g_parity_hash = 0xcbf29ce484222325ULL;

/* ------------------------------------------------------------------------
 * (1) Composición de tres bloques + máscara + bloque diminuto
 * ---------------------------------------------------------------------- */

static void test_layers_three_blocks(void)
{
    static uint8_t px[W * H * 3], mask[W * H];
    static layers L;
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_image img;
    ce_palette_opts o;
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    int n, ir, ib, ig, x, y, c, magenta_cluster = -1, fate_counts[4] = {0};

    fill_scene(px, mask, NULL);
    img = image_of(px, mask);
    ce_palette_opts_default(&o);
    o.center_sigma = 0.0;
    n = ce_palette_extract(ctx, &img, &o, sw, CE_PALETTE_MAX_COLORS);
    TEST_ASSERT_EQUAL_INT(3, n);
    read_layers(ctx, &L);

    TEST_ASSERT_EQUAL_INT(W, L.info.reduced_width);
    TEST_ASSERT_EQUAL_INT(H, L.info.reduced_height);
    TEST_ASSERT_EQUAL_INT(3, L.info.n_swatches);
    TEST_ASSERT_EQUAL_DOUBLE(0.25, L.info.zero_weight_fraction);
    TEST_ASSERT_EQUAL_DOUBLE(0.0, L.info.center_sigma_px);
    /* Máscara 255 como factor entero: 30000 píxeles con peso 255. */
    TEST_ASSERT_EQUAL_DOUBLE(30000.0 * 255.0, L.info.total_weight);
    TEST_ASSERT_EQUAL_MEMORY(px, L.reduced, sizeof px); /* sin reducción: 200 <= 256 */

    ir = swatch_index_of(sw, n, RED);
    ib = swatch_index_of(sw, n, BLUE);
    ig = swatch_index_of(sw, n, GREEN);
    TEST_ASSERT_TRUE(ir >= 0 && ib >= 0 && ig >= 0);
    TEST_ASSERT_TRUE(ir != ib && ib != ig && ir != ig);

    for (y = 0; y < H; ++y) {
        for (x = 0; x < W; ++x) {
            const size_t i = (size_t)y * W + (size_t)x;
            const int in_magenta = (y >= 40 && y < 46 && x >= 40 && x < 46);
            int want;
            if (y >= 100 && x >= 100) {
                want = CE_LABEL_NONE;
            } else if (in_magenta) {
                want = CE_LABEL_DISCARDED;
            } else {
                want = (y < 100) ? ((x < 100) ? ir : ib) : ig;
            }
            if (L.labels[i] != want) {
                char msg[96];
                snprintf(msg, sizeof msg, "label (%d,%d) = %u, esperaba %d", x, y, L.labels[i], want);
                TEST_FAIL_MESSAGE(msg);
            }
            TEST_ASSERT_EQUAL_UINT8(want == CE_LABEL_NONE ? 0 : 255, L.weights[i]);
            if (want == CE_LABEL_NONE) {
                TEST_ASSERT_EQUAL_UINT8(CE_LABEL_NONE, L.clusters[i]);
            } else {
                TEST_ASSERT_TRUE(L.clusters[i] < L.info.n_clusters);
                if (in_magenta) {
                    if (magenta_cluster < 0) magenta_cluster = L.clusters[i];
                    TEST_ASSERT_EQUAL_INT(magenta_cluster, L.clusters[i]);
                }
            }
        }
    }
    TEST_ASSERT_EQUAL_INT(4, L.info.n_clusters); /* rojo, azul, verde, magenta (amarillo sin peso) */
    TEST_ASSERT_TRUE(magenta_cluster >= 0);
    TEST_ASSERT_EQUAL_INT(CE_FATE_DISCARDED, L.info.clusters[magenta_cluster].fate);
    TEST_ASSERT_EQUAL_INT(-1, L.info.clusters[magenta_cluster].final_index);
    TEST_ASSERT_EQUAL_DOUBLE(36.0 / 30000.0, L.info.clusters[magenta_cluster].weight);
    for (c = 0; c < L.info.n_clusters; ++c) {
        const ce_cluster_debug *cd = &L.info.clusters[c];
        fate_counts[cd->fate]++;
        TEST_ASSERT_EQUAL_INT(c, cd->group_head);
        if (cd->fate == CE_FATE_KEPT) {
            TEST_ASSERT_TRUE(cd->final_index >= 0 && cd->final_index < n);
            TEST_ASSERT_TRUE(ce_de2000(cd->lab, sw[cd->final_index].lab) < 1e-9);
        }
    }
    TEST_ASSERT_EQUAL_INT(3, fate_counts[CE_FATE_KEPT]);
    TEST_ASSERT_EQUAL_INT(1, fate_counts[CE_FATE_DISCARDED]);
    for (c = L.info.n_clusters; c < CE_PALETTE_K_MAX; ++c) {
        TEST_ASSERT_EQUAL_DOUBLE(0.0, L.info.clusters[c].weight);
    }
    assert_label_weights(&L, sw, n);
    g_parity_hash = hash_layers(g_parity_hash, &L);

    /* ce_analyze deja las mismas capas que ce_palette_extract. */
    {
        static layers L2;
        ce_result res;
        TEST_ASSERT_TRUE(ce_analyze(ctx, &img, &o, NULL, &res) > 0);
        read_layers(ctx, &L2);
        TEST_ASSERT_EQUAL_UINT64(hash_layers(0, &L), hash_layers(0, &L2));
    }

    /* Todo el peso a cero: paleta de reserva, sin clusters, todo NONE. */
    {
        static uint8_t zero[W * H];
        memset(zero, 0, sizeof zero);
        img.mask = zero;
        TEST_ASSERT_EQUAL_INT(1, ce_palette_extract(ctx, &img, &o, sw, CE_PALETTE_MAX_COLORS));
        read_layers(ctx, &L);
        TEST_ASSERT_EQUAL_INT(0, L.info.n_clusters);
        TEST_ASSERT_EQUAL_INT(1, L.info.n_swatches);
        TEST_ASSERT_EQUAL_DOUBLE(1.0, L.info.zero_weight_fraction);
        for (x = 0; x < W * H; ++x) {
            TEST_ASSERT_EQUAL_UINT8(CE_LABEL_NONE, L.labels[x]);
            TEST_ASSERT_EQUAL_UINT8(CE_LABEL_NONE, L.clusters[x]);
            TEST_ASSERT_EQUAL_UINT8(0, L.weights[x]);
        }
        g_parity_hash = hash_layers(g_parity_hash, &L);
    }
    free(mem);
}

/* ------------------------------------------------------------------------
 * (2) Fusión y recorte
 * ---------------------------------------------------------------------- */

static void test_layers_merge_and_truncate(void)
{
    static uint8_t px[W * H * 3], mask[W * H];
    static layers L;
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_image img;
    ce_palette_opts o;
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    int n, ir, c, merged = 0, kept_red = 0, red_clusters = 0, truncated = 0;
    const ce_lab lab_red = ce_srgb8_to_lab(RED[0], RED[1], RED[2]);
    const ce_lab lab_red2 = ce_srgb8_to_lab(RED2[0], RED2[1], RED2[2]);

    TEST_ASSERT_TRUE(ce_de2000(lab_red, lab_red2) < 5.0);
    fill_scene(px, mask, RED2);
    img = image_of(px, mask);
    ce_palette_opts_default(&o);
    o.center_sigma = 0.0;
    n = ce_palette_extract(ctx, &img, &o, sw, CE_PALETTE_MAX_COLORS);
    TEST_ASSERT_EQUAL_INT(3, n);
    read_layers(ctx, &L);
    TEST_ASSERT_EQUAL_INT(4, L.info.n_clusters);
    /* El swatch rojo es la media de los dos rojos (50/50). */
    ir = -1;
    for (c = 0; c < n; ++c) {
        if (ce_de2000(sw[c].lab, lab_red) < 3.0 && ce_de2000(sw[c].lab, lab_red2) < 3.0) ir = c;
    }
    TEST_ASSERT_TRUE(ir >= 0);
    for (c = 0; c < L.info.n_clusters; ++c) {
        const ce_cluster_debug *cd = &L.info.clusters[c];
        const int is_red = ce_de2000(cd->lab, lab_red) < 1e-9 || ce_de2000(cd->lab, lab_red2) < 1e-9;
        if (!is_red) {
            TEST_ASSERT_EQUAL_INT(CE_FATE_KEPT, cd->fate);
            continue;
        }
        ++red_clusters;
        TEST_ASSERT_EQUAL_INT(ir, cd->final_index);
        if (cd->fate == CE_FATE_MERGED) {
            ++merged;
            TEST_ASSERT_TRUE(cd->group_head != c);
            TEST_ASSERT_EQUAL_INT(CE_FATE_KEPT, L.info.clusters[cd->group_head].fate);
        } else {
            TEST_ASSERT_EQUAL_INT(CE_FATE_KEPT, cd->fate);
            ++kept_red;
        }
    }
    TEST_ASSERT_EQUAL_INT(2, red_clusters);
    TEST_ASSERT_EQUAL_INT(1, merged);
    TEST_ASSERT_EQUAL_INT(1, kept_red);
    {
        int x, y;
        for (y = 0; y < 100; ++y) {
            for (x = 0; x < 100; ++x) {
                TEST_ASSERT_EQUAL_UINT8(ir, L.labels[(size_t)y * W + (size_t)x]);
            }
        }
    }
    assert_label_weights(&L, sw, n);
    g_parity_hash = hash_layers(g_parity_hash, &L);

    /* max_colors 2: el grupo más ligero queda recortado (fate 3, DISCARDED). */
    o.max_colors = 2;
    n = ce_palette_extract(ctx, &img, &o, sw, CE_PALETTE_MAX_COLORS);
    TEST_ASSERT_EQUAL_INT(2, n);
    read_layers(ctx, &L);
    for (c = 0; c < L.info.n_clusters; ++c) {
        if (L.info.clusters[c].fate == CE_FATE_TRUNCATED) {
            ++truncated;
            TEST_ASSERT_EQUAL_INT(-1, L.info.clusters[c].final_index);
        }
    }
    TEST_ASSERT_EQUAL_INT(1, truncated);
    {
        size_t i;
        int discarded = 0;
        for (i = 0; i < W * H; ++i) {
            TEST_ASSERT_TRUE(L.labels[i] < 2 || L.labels[i] == CE_LABEL_DISCARDED || L.labels[i] == CE_LABEL_NONE);
            discarded += L.labels[i] == CE_LABEL_DISCARDED;
        }
        TEST_ASSERT_EQUAL_INT(10000, discarded); /* un bloque de 100x100 */
    }
    /* cap 1 (< max_colors) recorta igual. */
    o.max_colors = 5;
    TEST_ASSERT_EQUAL_INT(1, ce_palette_extract(ctx, &img, &o, sw, 1));
    read_layers(ctx, &L);
    TEST_ASSERT_EQUAL_INT(1, L.info.n_swatches);
    g_parity_hash = hash_layers(g_parity_hash, &L);
    free(mem);
}

/* ------------------------------------------------------------------------
 * (3) Pesos con gaussiana al centro y reducción
 * ---------------------------------------------------------------------- */

static void test_layers_center_weight_and_reduce(void)
{
    static uint8_t px[W * H * 3], mask[W * H];
    static layers L;
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_image img;
    ce_palette_opts o;
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    int n;

    fill_scene(px, mask, NULL);
    img = image_of(px, mask);
    ce_palette_opts_default(&o); /* sigma 0,35 */
    n = ce_palette_extract(ctx, &img, &o, sw, CE_PALETTE_MAX_COLORS);
    TEST_ASSERT_TRUE(n >= 2);
    read_layers(ctx, &L);
    TEST_ASSERT_EQUAL_DOUBLE(0.35 * 200.0, L.info.center_sigma_px);
    assert_label_weights(&L, sw, n);
    g_parity_hash = hash_layers(g_parity_hash, &L);

    /* max_side 64: reducida 64x64 (factor 4), capas del tamaño reducido. */
    o.max_side = 64;
    n = ce_palette_extract(ctx, &img, &o, sw, CE_PALETTE_MAX_COLORS);
    TEST_ASSERT_TRUE(n >= 2);
    read_layers(ctx, &L);
    TEST_ASSERT_EQUAL_INT(50, L.info.reduced_width);
    TEST_ASSERT_EQUAL_INT(50, L.info.reduced_height);
    assert_label_weights(&L, sw, n);
    g_parity_hash = hash_layers(g_parity_hash, &L);
    free(mem);
}

/* ------------------------------------------------------------------------
 * (4) Explicación del match
 * ---------------------------------------------------------------------- */

static void check_explain_top(const ce_ctx *ctx, const ce_swatch *sw, int n, const ce_match_opts *mo)
{
    ce_hit hits[CE_MATCH_MAX_HITS];
    int k, i, amb = 0;
    const int nh = ce_match(ctx, sw, n, mo, hits, CE_MATCH_MAX_HITS, &amb);
    TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, nh);
    for (k = 0; k < nh; ++k) {
        ce_match_explain e;
        double sum;
        memset(&e, 0x5A, sizeof e);
        TEST_ASSERT_EQUAL_INT(CE_OK, ce_match_explain_combo(ctx, sw, n, mo, hits[k].combo_id, &e));
        TEST_ASSERT_EQUAL_INT(hits[k].combo_id, e.combo_id);
        /* Bit a bit (memcmp: también el signo de un cero). */
        TEST_ASSERT_EQUAL_MEMORY(&hits[k].score, &e.score, sizeof(double));
        sum = e.fit_term + e.coverage_term + e.hypothesis_penalty;
        TEST_ASSERT_EQUAL_MEMORY(&e.score, &sum, sizeof(double));
        TEST_ASSERT_TRUE(fabs(sum - e.score) <= 1e-12);
        TEST_ASSERT_TRUE(e.fit_term >= 0.0 && e.coverage_term >= 0.0 && e.hypothesis_penalty >= 0.0);
        TEST_ASSERT_EQUAL_INT(n, e.n_swatches);
        TEST_ASSERT_TRUE(e.combo_size >= 2 && e.combo_size <= CE_DICT_MAX_COLORS);
        TEST_ASSERT_TRUE(e.illuminant == -1 || (e.illuminant >= 0 && e.illuminant < CE_ILL_COUNT && e.illuminant != CE_ILL_D65));
        TEST_ASSERT_TRUE(fabs(e.exposure_ev) <= mo->exposure_ev_max + 1e-12);
        {
            uint8_t size = 0, colors[CE_DICT_COMBO_MAX];
            double fit = 0.0, coverage = 0.0, coverage_term;
            TEST_ASSERT_EQUAL_INT(0, ce_dict_combo(e.combo_id, &size, colors));
            TEST_ASSERT_EQUAL_INT(size, e.combo_size);
            for (i = 0; i < e.combo_size; ++i) {
                TEST_ASSERT_EQUAL_INT(colors[i], e.per_color[i].color_index);
                TEST_ASSERT_TRUE(e.per_color[i].nearest_swatch >= 0 && e.per_color[i].nearest_swatch < n);
                TEST_ASSERT_TRUE(e.per_color[i].de >= 0.0);
                coverage += e.per_color[i].de;
            }
            /* fit_term = Σ w_i · de_i y coverage_term = λ·(Σ de_j / |C|), mismo orden. */
            for (i = 0; i < n; ++i) {
                int j, found = 0;
                TEST_ASSERT_TRUE(e.per_swatch[i].de >= 0.0);
                for (j = 0; j < e.combo_size; ++j) found |= (colors[j] == e.per_swatch[i].nearest_color_index);
                TEST_ASSERT_TRUE(found);
                fit += sw[i].weight * e.per_swatch[i].de;
            }
            coverage_term = mo->coverage_lambda * (coverage / (double)e.combo_size);
            TEST_ASSERT_EQUAL_MEMORY(&e.fit_term, &fit, sizeof(double));
            TEST_ASSERT_EQUAL_MEMORY(&e.coverage_term, &coverage_term, sizeof(double));
        }
        if (k < 3) {
            g_parity_hash = hash_explain(g_parity_hash, &e);
        }
    }
}

static void test_match_explain_bit_exact(void)
{
    static uint8_t px[W * H * 3], mask[W * H];
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_image img;
    ce_palette_opts po;
    ce_match_opts mo;
    ce_result res;
    ce_swatch rnd[5];
    uint64_t lcg = 12345;
    int t, i;

    fill_scene(px, mask, NULL);
    img = image_of(px, mask);
    ce_palette_opts_default(&po);
    ce_match_opts_default(&mo);
    TEST_ASSERT_TRUE(ce_analyze(ctx, &img, &po, &mo, &res) > 0);
    check_explain_top(ctx, res.swatches, res.n_swatches, &mo);
    /* El top-3 de ce_analyze (lo que ve la app) también. */
    for (i = 0; i < 3; ++i) {
        ce_match_explain e;
        TEST_ASSERT_EQUAL_INT(CE_OK, ce_match_explain_combo(ctx, res.swatches, res.n_swatches, &mo, res.hits[i].combo_id, &e));
        TEST_ASSERT_EQUAL_MEMORY(&res.hits[i].score, &e.score, sizeof(double));
    }
    /* Match v0 (sin hipótesis): la identidad siempre gana. */
    mo.exposure_ev_max = 0.0;
    mo.illuminant_search = 0;
    check_explain_top(ctx, res.swatches, res.n_swatches, &mo);
    {
        ce_match_explain e;
        TEST_ASSERT_EQUAL_INT(CE_OK, ce_match_explain_combo(ctx, res.swatches, res.n_swatches, &mo, 1, &e));
        TEST_ASSERT_EQUAL_INT(-1, e.illuminant);
        TEST_ASSERT_EQUAL_DOUBLE(0.0, e.exposure_ev);
        TEST_ASSERT_EQUAL_DOUBLE(0.0, e.hypothesis_penalty);
    }
    /* Paletas aleatorias (LCG) con kL 2 y λ 0,5: exposición e iluminante activos. */
    ce_match_opts_default(&mo);
    mo.kL = 2.0;
    mo.coverage_lambda = 0.5;
    for (t = 0; t < 20; ++t) {
        double wsum = 0.0;
        const int n = 1 + t % 5;
        for (i = 0; i < n; ++i) {
            uint8_t rgb[3];
            int ch;
            for (ch = 0; ch < 3; ++ch) {
                lcg = lcg * 6364136223846793005ULL + 1442695040888963407ULL;
                rgb[ch] = (uint8_t)(lcg >> 56);
            }
            rnd[i].lab = ce_srgb8_to_lab(rgb[0], rgb[1], rgb[2]);
            ce_lab_to_srgb8(rnd[i].lab, &rnd[i].rgb[0], &rnd[i].rgb[1], &rnd[i].rgb[2]);
            rnd[i].weight = (double)(i + 1);
            wsum += rnd[i].weight;
        }
        for (i = 0; i < n; ++i) rnd[i].weight /= wsum;
        check_explain_top(ctx, rnd, n, &mo);
    }
    /* Errores de la explicación (sin escribir). */
    {
        ce_match_explain e, before;
        memset(&e, 0x77, sizeof e);
        before = e;
        TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match_explain_combo(ctx, res.swatches, res.n_swatches, NULL, 0, &e));
        TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match_explain_combo(ctx, res.swatches, res.n_swatches, NULL, 349, &e));
        TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match_explain_combo(ctx, res.swatches, 0, NULL, 1, &e));
        TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match_explain_combo(ctx, NULL, 1, NULL, 1, &e));
        TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match_explain_combo(NULL, res.swatches, 1, NULL, 1, &e));
        mo.coverage_lambda = -1.0;
        TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match_explain_combo(ctx, res.swatches, res.n_swatches, &mo, 1, &e));
        TEST_ASSERT_EQUAL_MEMORY(&before, &e, sizeof e);
        TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match_explain_combo(ctx, res.swatches, 1, NULL, 1, NULL));
    }
    free(mem);
}

/* ------------------------------------------------------------------------
 * (5) Errores
 * ---------------------------------------------------------------------- */

static void test_debug_errors(void)
{
    static uint8_t px[W * H * 3], mask[W * H], buf[W * H * 3 + 1];
    ce_palette_debug info;
    void *mem, *zero_mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_image img;
    ce_palette_opts o;
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    size_t i;

    /* Sin extracción: CE_ERR_CTX en todas. */
    TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_palette_debug_info(ctx, &info));
    TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_debug_reduced_rgb(ctx, buf, sizeof buf));
    TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_debug_weight_map(ctx, buf, sizeof buf));
    TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_debug_label_map(ctx, buf, sizeof buf));
    TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_debug_cluster_map(ctx, buf, sizeof buf));
    /* Memoria a cero (sin ce_ctx_init). */
    zero_mem = aligned_alloc(16, ce_ctx_size());
    TEST_ASSERT_NOT_NULL(zero_mem);
    memset(zero_mem, 0, ce_ctx_size());
    TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_palette_debug_info((const ce_ctx *)zero_mem, &info));
    TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_debug_label_map((const ce_ctx *)zero_mem, buf, sizeof buf));
    free(zero_mem);
    /* Punteros nulos. */
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_palette_debug_info(NULL, &info));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_palette_debug_info(ctx, NULL));

    fill_scene(px, mask, NULL);
    img = image_of(px, mask);
    ce_palette_opts_default(&o);
    TEST_ASSERT_TRUE(ce_palette_extract(ctx, &img, &o, sw, CE_PALETTE_MAX_COLORS) > 0);
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_palette_debug_info(ctx, &info));

    /* Buffers cortos o nulos: CE_ERR_ARG sin escribir. */
    memset(buf, 0xAB, sizeof buf);
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_debug_reduced_rgb(ctx, buf, W * H * 3 - 1));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_debug_weight_map(ctx, buf, W * H - 1));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_debug_label_map(ctx, buf, W * H - 1));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_debug_cluster_map(ctx, buf, 0));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_debug_reduced_rgb(ctx, NULL, sizeof buf));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_debug_label_map(ctx, NULL, sizeof buf));
    for (i = 0; i < sizeof buf; ++i) {
        TEST_ASSERT_EQUAL_UINT8(0xAB, buf[i]);
    }
    /* Capacidad sobrante: escribe solo lo necesario. */
    TEST_ASSERT_EQUAL_INT(W * H, ce_debug_label_map(ctx, buf, sizeof buf));
    TEST_ASSERT_EQUAL_UINT8(0xAB, buf[W * H]);

    /* Una extracción fallida invalida las capas. */
    o.k_init = 0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_palette_extract(ctx, &img, &o, sw, CE_PALETTE_MAX_COLORS));
    TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_palette_debug_info(ctx, &info));
    TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_debug_label_map(ctx, buf, sizeof buf));
    /* ce_analyze con opciones de match inválidas también. */
    o.k_init = 6;
    TEST_ASSERT_TRUE(ce_palette_extract(ctx, &img, &o, sw, CE_PALETTE_MAX_COLORS) > 0);
    {
        ce_match_opts mo;
        ce_result res;
        ce_match_opts_default(&mo);
        mo.kL = NAN;
        TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_analyze(ctx, &img, &o, &mo, &res));
        TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_palette_debug_info(ctx, &info));
    }
    /* El contexto sigue cabiendo en 2 MiB con el estado de depuración. */
    printf("ce_ctx_size=%zu bytes\n", ce_ctx_size());
    TEST_ASSERT_TRUE(ce_ctx_size() <= 2u * 1024u * 1024u);
    free(mem);
}

/* ------------------------------------------------------------------------
 * (6) Paridad nativo/WASM
 * ---------------------------------------------------------------------- */

/* Constante medida en nativo (Apple arm64); el mismo test en WASM (node) y
 * con ASan debe dar exactamente este valor. */
#define CE_DEBUG_PARITY_HASH 0x60b15a4bf131c4bfULL

static void test_layers_parity_hash(void)
{
    printf("DEBUG_LAYERS_HASH=%016" PRIx64 "\n", g_parity_hash);
    TEST_ASSERT_EQUAL_HEX64(CE_DEBUG_PARITY_HASH, g_parity_hash);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_layers_three_blocks);
    RUN_TEST(test_layers_merge_and_truncate);
    RUN_TEST(test_layers_center_weight_and_reduce);
    RUN_TEST(test_match_explain_bit_exact);
    RUN_TEST(test_debug_errors);
    RUN_TEST(test_layers_parity_hash);
    return UNITY_END();
}
