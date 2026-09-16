/*
 * test_match.c — tests de la capa 3 (ce_match / ce_analyze) con Unity.
 *
 * 1. Recall exacto: para cada una de las 348 combinaciones, imagen 120x120 de
 *    bandas verticales con proporciones iguales de sus colores sRGB8 exactos
 *    -> ce_analyze en modo uniforme devuelve hits[0].id == id (348/348); se
 *    cuenta cuántas salen `ambiguous` con varios gaps.
 * 2. Paletas exactas (swatches desde ce_dict_color_lab, pesos iguales):
 *    score 0 exacto y hits[0].id == id para las 348; desempate por id
 *    determinista con λ = 0 (todas las combinaciones que contienen un color
 *    empatan a 0 y salen por id ascendente).
 * 3. Propiedades y errores: score >= 0 y finito, orden total, kL <= 0 == 1,
 *    top_k/n fuera de rango, NaN/inf en opciones, swatches inválidos, contexto
 *    sin inicializar; nada escribe en las salidas; semántica de ambiguous_gap;
 *    errores de ce_analyze.
 * 1c. Regresión de "falsa adaptación" (caso real del usuario, 2026-09-15):
 *    la paleta de una foto con camiseta negra y pantalón rosa palo (solo
 *    valores hex y pesos, nunca la foto) no puede dar una combinación azul
 *    con las opciones por defecto; con illuminant_search = 1 sale Nº 067.
 * 4. ce_result_hash: dos análisis idénticos (mismo y distinto contexto) ->
 *    mismo hash; imagen distinta -> hash distinto.
 * 5. Rendimiento: MATCH_MS (5 swatches, 348 combinaciones, mejor de 200) y
 *    ANALYZE_1024_MS (1024x1024 RGBA, mejor de 5); cotas CE_MATCH_GATE_MS y
 *    CE_ANALYZE_GATE_MS solo en nativo -O2 sin sanitizers.
 * Escribe fixtures PPM y la lista del batch en CE_TEST_OUT_DIR para los tests
 * del CLI (ctest cli_match_*, cli_batch_*, cli_match_contract).
 */
/* clock_gettime/CLOCK_MONOTONIC son POSIX (ver test_palette.c). */
#define _POSIX_C_SOURCE 200809L

#include "ce/ce.h"
#include "unity.h"

#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#pragma STDC FP_CONTRACT OFF

#ifndef CE_TEST_OUT_DIR
#error "CE_TEST_OUT_DIR debe definirse (directorio de salida de fixtures)"
#endif

/* Lado de las imágenes sintéticas: divisible por 2, 3 y 4 (tamaños del Vol. 1). */
#define IMG_SIDE 120

void setUp(void) {}
void tearDown(void) {}

/* ------------------------------------------------------------------------
 * Utilidades
 * ---------------------------------------------------------------------- */

static uint64_t g_lcg = 20260915ULL;

static uint32_t lcg_next(void)
{
    g_lcg = g_lcg * 6364136223846793005ULL + 1442695040888963407ULL;
    return (uint32_t)(g_lcg >> 33);
}

static double lcg_uniform(double lo, double hi)
{
    return lo + (hi - lo) * ((double)(lcg_next() & 0xFFFFFF) / 16777215.0);
}

static ce_ctx *ctx_new(void **mem)
{
    ce_ctx *ctx;
    *mem = aligned_alloc(16, ce_ctx_size());
    TEST_ASSERT_NOT_NULL(*mem);
    ctx = ce_ctx_init(*mem, ce_ctx_size());
    TEST_ASSERT_NOT_NULL(ctx);
    return ctx;
}

static ce_palette_opts uniform_opts(void)
{
    ce_palette_opts o;
    ce_palette_opts_default(&o);
    o.center_sigma = 0.0;
    return o;
}

static ce_image make_image(const uint8_t *px, int w, int h, int stride, ce_pixel_format fmt)
{
    ce_image img;
    img.pixels = px;
    img.width = w;
    img.height = h;
    img.stride_bytes = stride;
    img.fmt = fmt;
    img.mask = NULL;
    return img;
}

/* Rellena una imagen RGB8 IMG_SIDE x IMG_SIDE con bandas verticales de
 * proporciones iguales con los colores sRGB8 exactos de la combinación `id`.
 * Devuelve el tamaño de la combinación. */
static int fill_combo_image(uint8_t *px, int id)
{
    uint8_t size = 0;
    uint8_t colors[CE_DICT_COMBO_MAX];
    uint8_t rgb[CE_DICT_COMBO_MAX][3];
    int k, x, y;
    TEST_ASSERT_EQUAL_INT(0, ce_dict_combo(id, &size, colors));
    TEST_ASSERT_TRUE(size >= 2 && size <= CE_DICT_COMBO_MAX);
    for (k = 0; k < (int)size; ++k) {
        TEST_ASSERT_EQUAL_INT(0, ce_dict_color_rgb(colors[k], rgb[k]));
    }
    for (y = 0; y < IMG_SIDE; ++y) {
        for (x = 0; x < IMG_SIDE; ++x) {
            uint8_t *p = px + ((size_t)y * IMG_SIDE + (size_t)x) * 3;
            const int band = (x * (int)size) / IMG_SIDE;
            p[0] = rgb[band][0];
            p[1] = rgb[band][1];
            p[2] = rgb[band][2];
        }
    }
    return (int)size;
}

/* Swatches exactos de la combinación `id` (Lab del diccionario, pesos iguales). */
static int fill_combo_swatches(ce_swatch *sw, int id)
{
    uint8_t size = 0;
    uint8_t colors[CE_DICT_COMBO_MAX];
    int k;
    TEST_ASSERT_EQUAL_INT(0, ce_dict_combo(id, &size, colors));
    for (k = 0; k < (int)size; ++k) {
        sw[k].lab = ce_dict_color_lab(colors[k]);
        TEST_ASSERT_EQUAL_INT(0, ce_dict_color_rgb(colors[k], sw[k].rgb));
        sw[k].weight = 1.0 / (double)size;
    }
    return (int)size;
}

/* Comprueba el orden total (score asc, id asc) y score >= 0 finito. */
static void assert_hits_sorted(const ce_hit *h, int n)
{
    int i;
    for (i = 0; i < n; ++i) {
        TEST_ASSERT_TRUE_MESSAGE(h[i].score >= 0.0, "score negativo");
        TEST_ASSERT_TRUE_MESSAGE(isfinite(h[i].score), "score no finito");
        TEST_ASSERT_TRUE(h[i].combo_id >= 1 && (int)h[i].combo_id <= ce_dict_num_combos());
        if (i > 0) {
            const int ok = (h[i - 1].score < h[i].score)
                || (h[i - 1].score == h[i].score && h[i - 1].combo_id < h[i].combo_id);
            TEST_ASSERT_TRUE_MESSAGE(ok, "hits fuera de orden (score asc, id asc)");
        }
    }
}

/* Igualdad campo a campo (el relleno de ce_hit no lo escribe el motor). */
static void assert_hits_equal(const ce_hit *a, const ce_hit *b, int n)
{
    int i;
    for (i = 0; i < n; ++i) {
        TEST_ASSERT_EQUAL_UINT16(a[i].combo_id, b[i].combo_id);
        TEST_ASSERT_TRUE_MESSAGE(a[i].score == b[i].score, "scores distintos bit a bit");
    }
}

static double now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1.0e6;
}

/* ------------------------------------------------------------------------
 * 1. Recall exacto sobre imágenes de bloques
 * ---------------------------------------------------------------------- */

static void test_recall_exact_block_images(void)
{
    const int ncombos = ce_dict_num_combos();
    static const double gaps[4] = {0.5, 1.0, 2.0, 5.0};
    uint8_t *px = (uint8_t *)malloc((size_t)IMG_SIDE * IMG_SIDE * 3);
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_palette_opts po = uniform_opts();
    ce_match_opts mo;
    ce_result r;
    int id, ok = 0, amb_default = 0, exact_zero = 0, palette_full = 0;
    int amb_by_gap[4] = {0, 0, 0, 0};
    double max_top = 0.0, min_gap = HUGE_VAL;

    TEST_ASSERT_NOT_NULL(px);
    ce_match_opts_default(&mo);
    TEST_ASSERT_EQUAL_DOUBLE(1.0, mo.ambiguous_gap);
    for (id = 1; id <= ncombos; ++id) {
        const int size = fill_combo_image(px, id);
        ce_image img = make_image(px, IMG_SIDE, IMG_SIDE, IMG_SIDE * 3, CE_RGB8);
        int rc = ce_analyze(ctx, &img, &po, &mo, &r);
        int g;
        TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, rc);
        TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, r.n_hits);
        assert_hits_sorted(r.hits, r.n_hits);
        if (r.n_swatches == size) palette_full++;
        if ((int)r.hits[0].combo_id == id) {
            ok++;
        } else {
            printf("recall fallido: combo %d (size %d) -> top1 %u (score %.4g), correcto en pos ?\n",
                   id, size, (unsigned)r.hits[0].combo_id, r.hits[0].score);
        }
        if (r.hits[0].score == 0.0) exact_zero++;
        if (r.hits[0].score > max_top) max_top = r.hits[0].score;
        if (r.hits[1].score - r.hits[0].score < min_gap) min_gap = r.hits[1].score - r.hits[0].score;
        amb_default += r.ambiguous;
        for (g = 0; g < 4; ++g) {
            amb_by_gap[g] += (r.hits[1].score - r.hits[0].score < gaps[g]) ? 1 : 0;
        }
    }
    printf("RECALL_EXACT=%d/%d AMBIGUOUS_EXACT=%d (gap 1.0) | gap 0.5: %d, 2.0: %d, 5.0: %d | "
           "score 0 exacto: %d/%d | paleta completa: %d/%d | max top1 score %.3g | gap minimo %.3f\n",
           ok, ncombos, amb_default, amb_by_gap[0], amb_by_gap[2], amb_by_gap[3],
           exact_zero, ncombos, palette_full, ncombos, max_top, min_gap);
    TEST_ASSERT_EQUAL_INT_MESSAGE(ncombos, ok, "recall@1 sobre bloques exactos debe ser 348/348");
    TEST_ASSERT_EQUAL_INT_MESSAGE(ncombos, palette_full, "la paleta debe recuperar todos los colores");
    TEST_ASSERT_EQUAL_INT(amb_by_gap[1], amb_default);
    free(px);
    free(mem);
}

/* ------------------------------------------------------------------------
 * 1b. Hipótesis de adaptación: paletas exactas degradadas (exposición e
 *     iluminante, como las variantes 4-6 y 8 de wada_gen) y validación
 * ---------------------------------------------------------------------- */

/* Paleta exacta de la combinación `id` (pesos iguales) degradada: ganancia
 * `gain` en XYZ lineal (exposición) y, si `from` != CE_ILL_D65, Bradford
 * D65 -> `from` (la foto "se tomó" bajo `from` sin balance de blancos). */
static int degraded_palette(int id, double gain, ce_illuminant from, ce_swatch *sw)
{
    uint8_t size = 0;
    uint8_t colors[CE_DICT_COMBO_MAX];
    double m[9];
    int j;
    TEST_ASSERT_EQUAL_INT(0, ce_dict_combo(id, &size, colors));
    if (from != CE_ILL_D65) {
        ce_bradford_matrix(CE_ILL_D65, from, m);
    }
    for (j = 0; j < (int)size; ++j) {
        ce_xyz xyz = ce_lab_to_xyz(ce_dict_color_lab(colors[j]));
        if (from != CE_ILL_D65) {
            xyz = ce_xyz_adapt(xyz, m);
        }
        xyz.X *= gain; xyz.Y *= gain; xyz.Z *= gain;
        sw[j].lab = ce_xyz_to_lab(xyz);
        ce_lab_to_srgb8(sw[j].lab, &sw[j].rgb[0], &sw[j].rgb[1], &sw[j].rgb[2]);
        sw[j].weight = 1.0 / (double)size;
    }
    return (int)size;
}

static void test_adaptation_hypotheses(void)
{
    const int ncombos = ce_dict_num_combos();
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_match_opts on, off;
    ce_swatch sw[CE_DICT_COMBO_MAX];
    ce_hit h_on[CE_MATCH_MAX_HITS], h_off[CE_MATCH_MAX_HITS];
    int amb_on, amb_off, id, k;
    /* Casos: (ganancia, iluminante). -1 EV / +1 EV / A / F2 / D75 / A -0.5 EV. */
    static const double gains[6] = {0.5, 2.0, 1.0, 1.0, 1.0, 0.7071067811865476};
    static const ce_illuminant froms[6] = {CE_ILL_D65, CE_ILL_D65, CE_ILL_A, CE_ILL_F2, CE_ILL_D75, CE_ILL_A};
    static const char *names[6] = {"-1 EV", "+1 EV", "iluminante A", "iluminante F2", "iluminante D75", "A y -0.5 EV"};
    int ok_on[6] = {0, 0, 0, 0, 0, 0}, ok_off[6] = {0, 0, 0, 0, 0, 0}, not_worse = 0, total = 0;

    ce_match_opts_default(&on);
    on.illuminant_search = 1; /* desde ADR-009 (2026-09-15) no es el valor por defecto */
    ce_match_opts_default(&off);
    off.exposure_ev_max = 0.0;
    off.illuminant_search = 0;
    for (k = 0; k < 6; ++k) {
        for (id = 1; id <= ncombos; ++id) {
            const int n = degraded_palette(id, gains[k], froms[k], sw);
            TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, ce_match(ctx, sw, n, &on, h_on, CE_MATCH_MAX_HITS, &amb_on));
            TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, ce_match(ctx, sw, n, &off, h_off, CE_MATCH_MAX_HITS, &amb_off));
            assert_hits_sorted(h_on, CE_MATCH_MAX_HITS);
            assert_hits_sorted(h_off, CE_MATCH_MAX_HITS);
            /* El mínimo sobre un superconjunto de hipótesis nunca sube el mejor score. */
            if (h_on[0].score <= h_off[0].score) not_worse++;
            total++;
            if ((int)h_on[0].combo_id == id) ok_on[k]++;
            if ((int)h_off[0].combo_id == id) ok_off[k]++;
        }
        printf("ADAPT %-16s recall@1 con hipotesis %d/%d, sin (match v0) %d/%d\n", names[k], ok_on[k], ncombos, ok_off[k], ncombos);
    }
    TEST_ASSERT_EQUAL_INT_MESSAGE(total, not_worse, "con hipotesis el mejor score nunca debe ser peor que sin ellas");
    /* Exposición ±1 EV e iluminantes de la rejilla: la hipótesis correcta deshace
     * la degradación salvo el redondeo, así que el recall debe ser (casi) total;
     * sin hipótesis el mismo caso cae claramente (es la motivación de F4). */
    for (k = 0; k < 5; ++k) {
        TEST_ASSERT_TRUE_MESSAGE(ok_on[k] >= ncombos - 4, "recall@1 con hipotesis debe ser >= 344/348 en las degradaciones de la rejilla");
        TEST_ASSERT_TRUE_MESSAGE(ok_on[k] >= ok_off[k], "las hipotesis nunca deben empeorar el recall");
        /* D75 es tan suave que match v0 ya acierta 348/348; en el resto la mejora es estricta. */
        TEST_ASSERT_TRUE_MESSAGE(ok_off[k] == ncombos || ok_on[k] > ok_off[k], "las hipotesis deben mejorar el recall donde v0 falla");
    }
    /* Combinación A y -0.5 EV (dentro de la rejilla, con una pequeña penalización). */
    TEST_ASSERT_TRUE_MESSAGE(ok_on[5] >= ncombos - 8, "recall@1 con A y -0.5 EV debe ser >= 340/348");
    free(mem);
}

/* Tono hab (grados, [0, 360)) y croma C*ab de un Lab. */
static double lab_hue_deg(ce_lab lab)
{
    double h = atan2(lab.b, lab.a) * 180.0 / 3.14159265358979323846;
    return h < 0.0 ? h + 360.0 : h;
}

static double lab_chroma(ce_lab lab)
{
    return sqrt(lab.a * lab.a + lab.b * lab.b);
}

static double hue_diff_deg(double h1, double h2)
{
    double d = fabs(h1 - h2);
    return d > 180.0 ? 360.0 - d : d;
}

/* Diferencia de tono entre el swatch `s` y el color de la combinación `id`
 * más cercano a él por ΔE00 (sin adaptación: lo que ve el usuario). */
static double nearest_combo_color_hue_diff(int id, ce_lab s, ce_lab *nearest)
{
    uint8_t size = 0, colors[CE_DICT_COMBO_MAX];
    double best = HUGE_VAL;
    int j;
    TEST_ASSERT_EQUAL_INT(0, ce_dict_combo(id, &size, colors));
    for (j = 0; j < (int)size; ++j) {
        const ce_lab c = ce_dict_color_lab(colors[j]);
        const double d = ce_de2000(s, c);
        if (d < best) {
            best = d;
            *nearest = c;
        }
    }
    return hue_diff_deg(lab_hue_deg(s), lab_hue_deg(*nearest));
}

static void test_false_adaptation_pink_black(void)
{
    /* Paleta extraída por la app (CONTEXT §11): #222524 39,4 %, #b49aa2 22,7 %,
     * #917a7e 16,2 %, #d5b8c0 13,4 %, #6b5a57 8,3 %. */
    static const uint8_t rgb[5][3] = {{0x22, 0x25, 0x24}, {0xb4, 0x9a, 0xa2}, {0x91, 0x7a, 0x7e},
                                      {0xd5, 0xb8, 0xc0}, {0x6b, 0x5a, 0x57}};
    static const double weight[5] = {0.394, 0.227, 0.162, 0.134, 0.083};
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch sw[5];
    ce_hit hits[CE_MATCH_MAX_HITS], hits_ill[CE_MATCH_MAX_HITS];
    ce_match_opts mo;
    ce_lab nearest;
    int i, amb, dominant = -1;
    double dh, dh_ill;

    for (i = 0; i < 5; ++i) {
        sw[i].lab = ce_srgb8_to_lab(rgb[i][0], rgb[i][1], rgb[i][2]);
        sw[i].rgb[0] = rgb[i][0]; sw[i].rgb[1] = rgb[i][1]; sw[i].rgb[2] = rgb[i][2];
        sw[i].weight = weight[i];
        /* Swatch cromático dominante: el más pesado con C*ab >= 8 (el mauve #b49aa2). */
        if (dominant < 0 && lab_chroma(sw[i].lab) >= 8.0) dominant = i;
    }
    TEST_ASSERT_EQUAL_INT(1, dominant);

    /* Opciones por defecto (las de la app): rosa + negro, nunca la pareja azul. */
    ce_match_opts_default(&mo);
    TEST_ASSERT_EQUAL_INT(0, mo.illuminant_search);
    TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, ce_match(ctx, sw, 5, &mo, hits, CE_MATCH_MAX_HITS, &amb));
    dh = nearest_combo_color_hue_diff(hits[0].combo_id, sw[dominant].lab, &nearest);
    printf("FALSE_ADAPT default: top-3 %u (%.4f) %u (%.4f) %u (%.4f); color de la top-1 más cercano al mauve "
           "L %.1f C %.1f h %.1f (Δh %.1f)\n", (unsigned)hits[0].combo_id, hits[0].score,
           (unsigned)hits[1].combo_id, hits[1].score, (unsigned)hits[2].combo_id, hits[2].score,
           nearest.L, lab_chroma(nearest), lab_hue_deg(nearest), dh);
    TEST_ASSERT_TRUE_MESSAGE(hits[0].combo_id == 337 || hits[0].combo_id == 27, "top-1 por defecto debe ser 337 o 27");
    for (i = 0; i < 3; ++i) {
        TEST_ASSERT_TRUE_MESSAGE(hits[i].combo_id != 67, "Nº 067 (azul) no puede estar en el top-3 por defecto");
    }
    /* "No azul": el color de la top-1 más cercano a cada swatch rosa conserva el
     * tono (Δhab <= 60°) y ninguno es azul (hab en 200..300 con C*ab >= 8). */
    for (i = 1; i < 5; ++i) {
        const double d = nearest_combo_color_hue_diff(hits[0].combo_id, sw[i].lab, &nearest);
        const double h = lab_hue_deg(nearest);
        TEST_ASSERT_FALSE_MESSAGE(lab_chroma(nearest) >= 8.0 && h >= 200.0 && h <= 300.0,
                                  "un rosa quedó emparejado con un color azul");
        if (i == dominant) TEST_ASSERT_TRUE(d <= 60.0);
    }

    /* La hipótesis sigue disponible como opción y reproduce el fallo: Nº 067
     * gana compensando una luz A inexistente (el giro de tono que mide L3). */
    mo.illuminant_search = 1;
    TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, ce_match(ctx, sw, 5, &mo, hits_ill, CE_MATCH_MAX_HITS, &amb));
    dh_ill = nearest_combo_color_hue_diff(hits_ill[0].combo_id, sw[dominant].lab, &nearest);
    printf("FALSE_ADAPT illuminant_search=1: top-1 %u (%.4f); color más cercano al mauve h %.1f (Δh %.1f)\n",
           (unsigned)hits_ill[0].combo_id, hits_ill[0].score, lab_hue_deg(nearest), dh_ill);
    TEST_ASSERT_EQUAL_INT(67, hits_ill[0].combo_id);
    TEST_ASSERT_TRUE(dh_ill > 60.0);
    free(mem);
}

static void test_adaptation_opts_validation(void)
{
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_match_opts mo;
    ce_swatch sw[2];
    ce_hit hits[CE_MATCH_MAX_HITS];
    int amb = 7, n, i;

    n = degraded_palette(12, 1.0, CE_ILL_D65, sw);
    for (i = 0; i < CE_MATCH_MAX_HITS; ++i) { hits[i].combo_id = 999; hits[i].score = -1.0; }
    ce_match_opts_default(&mo); mo.exposure_ev_max = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.exposure_ev_max = -0.5;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.exposure_ev_max = CE_MATCH_EV_MAX_LIMIT + 0.5;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.exposure_penalty = -1.0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.exposure_penalty = HUGE_VAL;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.illuminant_search = 2;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.illuminant_search = -1;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.illuminant_penalty = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.illuminant_penalty = -2.0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    for (i = 0; i < CE_MATCH_MAX_HITS; ++i) {
        TEST_ASSERT_EQUAL_UINT16(999, hits[i].combo_id);
        TEST_ASSERT_TRUE(hits[i].score == -1.0);
    }
    TEST_ASSERT_EQUAL_INT(7, amb);
    /* Valores límite válidos: rejilla máxima (17 ganancias x 5 iluminantes) y
     * penalizaciones 0; la paleta exacta sigue dando score 0 y su id. */
    ce_match_opts_default(&mo);
    mo.exposure_ev_max = CE_MATCH_EV_MAX_LIMIT; mo.exposure_penalty = 0.0; mo.illuminant_penalty = 0.0;
    TEST_ASSERT_EQUAL_INT(3, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    TEST_ASSERT_EQUAL_UINT16(12, hits[0].combo_id);
    TEST_ASSERT_TRUE(hits[0].score == 0.0);
    /* Con la búsqueda apagada y penalizaciones cualesquiera: mismo resultado que
     * con penalizaciones 0 (no hay hipótesis que penalizar). */
    {
        ce_hit a[3], b[3];
        int aa, ab;
        ce_match_opts_default(&mo); mo.exposure_ev_max = 0.0; mo.illuminant_search = 0; mo.exposure_penalty = 9.0; mo.illuminant_penalty = 9.0;
        TEST_ASSERT_EQUAL_INT(3, ce_match(ctx, sw, n, &mo, a, 3, &aa));
        mo.exposure_penalty = 0.0; mo.illuminant_penalty = 0.0;
        TEST_ASSERT_EQUAL_INT(3, ce_match(ctx, sw, n, &mo, b, 3, &ab));
        assert_hits_equal(a, b, 3);
        TEST_ASSERT_EQUAL_INT(aa, ab);
    }
    free(mem);
}

/* ------------------------------------------------------------------------
 * 2. Paletas exactas y desempate por id
 * ---------------------------------------------------------------------- */

static void test_exact_palettes_score_zero(void)
{
    const int ncombos = ce_dict_num_combos();
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch sw[CE_DICT_COMBO_MAX];
    ce_hit hits[CE_MATCH_MAX_HITS];
    int id, ok = 0, amb, n_amb = 0;
    double min_second = HUGE_VAL;

    for (id = 1; id <= ncombos; ++id) {
        const int size = fill_combo_swatches(sw, id);
        const int rc = ce_match(ctx, sw, size, NULL, hits, CE_MATCH_MAX_HITS, &amb);
        TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, rc);
        assert_hits_sorted(hits, rc);
        if ((int)hits[0].combo_id == id) ok++;
        TEST_ASSERT_TRUE_MESSAGE(hits[0].score == 0.0, "la paleta exacta debe puntuar 0 exacto");
        /* Sin conjuntos duplicados en el diccionario el segundo es > 0 estricto. */
        TEST_ASSERT_TRUE(hits[1].score > 0.0);
        if (hits[1].score < min_second) min_second = hits[1].score;
        n_amb += amb;
    }
    printf("RECALL_EXACT_PALETTES=%d/%d ambiguas=%d segundo score minimo=%.4f\n",
           ok, ncombos, n_amb, min_second);
    TEST_ASSERT_EQUAL_INT(ncombos, ok);
    free(mem);
}

/* Cuenta las combinaciones que contienen el color `index` y las lista (asc). */
static int combos_with_color(int index, int *ids, int cap, int *min_size)
{
    const int ncombos = ce_dict_num_combos();
    int id, n = 0;
    *min_size = 99;
    for (id = 1; id <= ncombos; ++id) {
        uint8_t size = 0, colors[CE_DICT_COMBO_MAX];
        int k;
        TEST_ASSERT_EQUAL_INT(0, ce_dict_combo(id, &size, colors));
        for (k = 0; k < (int)size; ++k) {
            if (colors[k] == index) {
                if (n < cap) ids[n] = id;
                ++n;
                if ((int)size < *min_size) *min_size = (int)size;
                break;
            }
        }
    }
    return n;
}

static void test_tie_break_by_id(void)
{
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch sw[1];
    ce_hit hits[CE_MATCH_MAX_HITS];
    ce_match_opts mo;
    int ids[400];
    int best_color = -1, best_count = 0, index, count, min_size, amb, rc, i;
    uint8_t size0 = 0;

    /* Color presente en más combinaciones. */
    for (index = 0; index < ce_dict_num_colors(); ++index) {
        int ms;
        count = combos_with_color(index, ids, 400, &ms);
        if (count > best_count) {
            best_count = count;
            best_color = index;
        }
    }
    TEST_ASSERT_TRUE_MESSAGE(best_count >= 2, "hace falta un color en >= 2 combinaciones");
    count = combos_with_color(best_color, ids, 400, &min_size);

    /* λ = 0 y un único swatch igual a ese color: todas las combinaciones que
     * lo contienen puntúan exactamente 0 (w · ΔE(x, x) = 0) y deben salir por
     * id ascendente. */
    ce_match_opts_default(&mo);
    mo.coverage_lambda = 0.0;
    sw[0].lab = ce_dict_color_lab(best_color);
    TEST_ASSERT_EQUAL_INT(0, ce_dict_color_rgb(best_color, sw[0].rgb));
    sw[0].weight = 1.0;
    rc = ce_match(ctx, sw, 1, &mo, hits, CE_MATCH_MAX_HITS, &amb);
    TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, rc);
    for (i = 0; i < rc && i < count; ++i) {
        TEST_ASSERT_EQUAL_INT_MESSAGE(ids[i], (int)hits[i].combo_id, "empate a 0: orden por id ascendente");
        TEST_ASSERT_TRUE(hits[i].score == 0.0);
    }
    TEST_ASSERT_EQUAL_INT(1, amb); /* 0 - 0 < 1.0 */
    /* Documentado: con λ = 0 no gana la combinación más pequeña que contiene
     * el color sino la de menor id (aquí se comprueba y se informa). */
    TEST_ASSERT_EQUAL_INT(0, ce_dict_combo((int)hits[0].combo_id, &size0, NULL));
    printf("empate lambda=0: color %d en %d combinaciones; gana id %u (size %u), size minimo %d -> %s\n",
           best_color, count, (unsigned)hits[0].combo_id, (unsigned)size0, min_size,
           ((int)size0 == min_size) ? "coincide" : "NO es la mas pequena (esperado)");
    /* Un color cuya combinación de menor id NO es la de menor tamaño: con
     * λ = 0 gana el id menor aunque exista una combinación más pequeña que
     * también lo contiene (propiedad documentada en ce.h / README). */
    {
        int found = -1, ex_ids[400], ex_count = 0, ex_min = 99;
        uint8_t first_size = 0;
        for (index = 0; index < ce_dict_num_colors() && found < 0; ++index) {
            ex_count = combos_with_color(index, ex_ids, 400, &ex_min);
            if (ex_count >= 2) {
                TEST_ASSERT_EQUAL_INT(0, ce_dict_combo(ex_ids[0], &first_size, NULL));
                if ((int)first_size > ex_min) found = index;
            }
        }
        if (found >= 0) {
            ce_hit hx[2];
            sw[0].lab = ce_dict_color_lab(found);
            TEST_ASSERT_EQUAL_INT(0, ce_dict_color_rgb(found, sw[0].rgb));
            TEST_ASSERT_EQUAL_INT(2, ce_match(ctx, sw, 1, &mo, hx, 2, &amb));
            TEST_ASSERT_EQUAL_INT(ex_ids[0], (int)hx[0].combo_id);
            TEST_ASSERT_TRUE(hx[0].score == 0.0 && hx[1].score == 0.0);
            printf("empate lambda=0: color %d -> gana id %d (size %u) aunque hay una de size %d\n",
                   found, ex_ids[0], (unsigned)first_size, ex_min);
        } else {
            printf("empate lambda=0: ningun color tiene una combinacion de menor id mas grande que la minima\n");
        }
        sw[0].lab = ce_dict_color_lab(best_color);
        TEST_ASSERT_EQUAL_INT(0, ce_dict_color_rgb(best_color, sw[0].rgb));
    }
    /* El mismo empate con top_k = 2 y con top_k = 1: prefijos idénticos. */
    {
        ce_hit h2[2], h1[1];
        TEST_ASSERT_EQUAL_INT(2, ce_match(ctx, sw, 1, &mo, h2, 2, &amb));
        TEST_ASSERT_EQUAL_INT(1, amb);
        TEST_ASSERT_EQUAL_INT(1, ce_match(ctx, sw, 1, &mo, h1, 1, &amb));
        TEST_ASSERT_EQUAL_INT(0, amb); /* con un solo hit nunca es ambiguo */
        assert_hits_equal(hits, h2, 2);
        assert_hits_equal(hits, h1, 1);
    }
    /* Con λ > 0 (defecto) el empate se rompe por cobertura: sigue ordenado y
     * el ganador contiene el color. */
    ce_match_opts_default(&mo);
    rc = ce_match(ctx, sw, 1, &mo, hits, CE_MATCH_MAX_HITS, &amb);
    TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, rc);
    assert_hits_sorted(hits, rc);
    {
        uint8_t size = 0, colors[CE_DICT_COMBO_MAX];
        int found = 0, k;
        TEST_ASSERT_EQUAL_INT(0, ce_dict_combo((int)hits[0].combo_id, &size, colors));
        for (k = 0; k < (int)size; ++k) {
            if (colors[k] == best_color) found = 1;
        }
        TEST_ASSERT_TRUE_MESSAGE(found, "con lambda > 0 el ganador debe contener el color");
    }
    free(mem);
}

/* ------------------------------------------------------------------------
 * 3. Propiedades y errores
 * ---------------------------------------------------------------------- */

static void fill_random_swatches(ce_swatch *sw, int n)
{
    double total = 0.0;
    int i;
    for (i = 0; i < n; ++i) {
        sw[i].lab.L = lcg_uniform(0.0, 100.0);
        sw[i].lab.a = lcg_uniform(-100.0, 100.0);
        sw[i].lab.b = lcg_uniform(-100.0, 100.0);
        ce_lab_to_srgb8(sw[i].lab, &sw[i].rgb[0], &sw[i].rgb[1], &sw[i].rgb[2]);
        sw[i].weight = lcg_uniform(0.01, 1.0);
        total += sw[i].weight;
    }
    for (i = 0; i < n; ++i) {
        sw[i].weight /= total;
    }
}

static void test_score_properties(void)
{
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    ce_hit hits[CE_MATCH_MAX_HITS], hits2[CE_MATCH_MAX_HITS];
    ce_match_opts mo;
    int trial, amb, rc, i;

    for (trial = 0; trial < 60; ++trial) {
        const int n = 1 + (int)(lcg_next() % CE_PALETTE_MAX_COLORS);
        fill_random_swatches(sw, n);
        ce_match_opts_default(&mo);
        rc = ce_match(ctx, sw, n, &mo, hits, CE_MATCH_MAX_HITS, &amb);
        TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, rc);
        assert_hits_sorted(hits, rc);
        TEST_ASSERT_TRUE(amb == 0 || amb == 1);
        TEST_ASSERT_EQUAL_INT((hits[1].score - hits[0].score < 1.0) ? 1 : 0, amb);
        /* Determinismo run-a-run: bit a bit. */
        TEST_ASSERT_EQUAL_INT(rc, ce_match(ctx, sw, n, &mo, hits2, CE_MATCH_MAX_HITS, NULL));
        assert_hits_equal(hits, hits2, rc);
        /* kL/kC/kH <= 0 se tratan como 1.0 (ce_de2000_k): mismos bits. */
        mo.kL = 0.0; mo.kC = -1.0; mo.kH = -0.5;
        TEST_ASSERT_EQUAL_INT(rc, ce_match(ctx, sw, n, &mo, hits2, CE_MATCH_MAX_HITS, NULL));
        assert_hits_equal(hits, hits2, rc);
        /* kL = 2 (textiles): ΔE00 no crece, así que el mejor score no crece. */
        ce_match_opts_default(&mo);
        mo.kL = 2.0;
        TEST_ASSERT_EQUAL_INT(rc, ce_match(ctx, sw, n, &mo, hits2, CE_MATCH_MAX_HITS, NULL));
        assert_hits_sorted(hits2, rc);
        TEST_ASSERT_TRUE(hits2[0].score <= hits[0].score + 1e-12);
        /* λ = 0: solo el ajuste; el score no puede superar al de λ = 1. */
        ce_match_opts_default(&mo);
        mo.coverage_lambda = 0.0;
        TEST_ASSERT_EQUAL_INT(rc, ce_match(ctx, sw, n, &mo, hits2, CE_MATCH_MAX_HITS, NULL));
        TEST_ASSERT_TRUE(hits2[0].score <= hits[0].score + 1e-12);
        /* λ grande: el término de cobertura domina; sigue ordenado y >= 0. */
        mo.coverage_lambda = 1000.0;
        TEST_ASSERT_EQUAL_INT(rc, ce_match(ctx, sw, n, &mo, hits2, CE_MATCH_MAX_HITS, NULL));
        assert_hits_sorted(hits2, rc);
    }
    /* Score de un swatch == color del diccionario con λ = 1, pesos 1: para
     * una combinación de tamaño s que lo contiene el score es
     * (1/s)·Σ_{otros} ΔE00(c_j, swatch) > 0 salvo que s == 1. */
    {
        int index = 7, ids[400], count, min_size;
        count = combos_with_color(index, ids, 400, &min_size);
        if (count > 0) {
            ce_match_opts_default(&mo);
            sw[0].lab = ce_dict_color_lab(index);
            sw[0].weight = 1.0;
            rc = ce_match(ctx, sw, 1, &mo, hits, CE_MATCH_MAX_HITS, &amb);
            TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, rc);
            for (i = 0; i < rc; ++i) TEST_ASSERT_TRUE(hits[i].score > 0.0);
        }
    }
    free(mem);
}

static void test_errors_do_not_write(void)
{
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch sw[CE_PALETTE_MAX_COLORS + 1];
    ce_hit hits[CE_MATCH_MAX_HITS], sentinel[CE_MATCH_MAX_HITS];
    ce_match_opts mo;
    ce_result res, res_sentinel;
    int amb = 42, n, rc;
    uint8_t *px = (uint8_t *)malloc((size_t)IMG_SIDE * IMG_SIDE * 3);
    ce_image img;
    ce_palette_opts po = uniform_opts();

    TEST_ASSERT_NOT_NULL(px);
    n = fill_combo_swatches(sw, 5);
    memset(hits, 0xAB, sizeof hits);
    memcpy(sentinel, hits, sizeof hits);
    ce_match_opts_default(&mo);

    /* Punteros y rangos. */
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(NULL, sw, n, &mo, hits, 3, &amb));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, NULL, n, &mo, hits, 3, &amb));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, n, &mo, NULL, 3, &amb));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, 0, &mo, hits, 3, &amb));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, -1, &mo, hits, 3, &amb));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, CE_PALETTE_MAX_COLORS + 1, &mo, hits, 3, &amb));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, n, &mo, hits, 0, &amb));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, n, &mo, hits, -1, &amb));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, n, &mo, hits, CE_MATCH_MAX_HITS + 1, &amb));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, n, &mo, hits, 11, &amb));
    /* Contexto sin inicializar. */
    {
        void *raw = aligned_alloc(16, ce_ctx_size());
        TEST_ASSERT_NOT_NULL(raw);
        memset(raw, 0, ce_ctx_size());
        TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_match((ce_ctx *)raw, sw, n, &mo, hits, 3, &amb));
        memset(&res, 0x77, sizeof res);
        memcpy(&res_sentinel, &res, sizeof res);
        img = make_image(px, IMG_SIDE, IMG_SIDE, IMG_SIDE * 3, CE_RGB8);
        TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_analyze((ce_ctx *)raw, &img, &po, &mo, &res));
        TEST_ASSERT_EQUAL_MEMORY(&res_sentinel, &res, sizeof res);
        free(raw);
    }
    /* Opciones: NaN o ±inf en cualquiera de las cinco => CE_ERR_OPTS; λ < 0. */
    ce_match_opts_default(&mo); mo.kL = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.kC = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.kH = -NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.coverage_lambda = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.ambiguous_gap = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.kL = HUGE_VAL;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.coverage_lambda = HUGE_VAL;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.ambiguous_gap = -HUGE_VAL;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    ce_match_opts_default(&mo); mo.coverage_lambda = -0.5;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    /* Swatches inválidos: Lab no finito, peso NaN / negativo / inf. */
    ce_match_opts_default(&mo);
    sw[1].lab.a = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    n = fill_combo_swatches(sw, 5);
    sw[n - 1].lab.L = HUGE_VAL;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    n = fill_combo_swatches(sw, 5);
    sw[0].weight = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    sw[0].weight = -0.1;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    sw[0].weight = HUGE_VAL;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, n, &mo, hits, 3, &amb));
    n = fill_combo_swatches(sw, 5);
    /* Nada escribió en las salidas. */
    TEST_ASSERT_EQUAL_MEMORY(sentinel, hits, sizeof hits);
    TEST_ASSERT_EQUAL_INT(42, amb);

    /* Valores admitidos: `ambiguous` NULL, opciones NULL, peso 0, gap <= 0. */
    TEST_ASSERT_EQUAL_INT(3, ce_match(ctx, sw, n, NULL, hits, 3, NULL));
    sw[0].weight = 0.0;
    TEST_ASSERT_EQUAL_INT(3, ce_match(ctx, sw, n, NULL, hits, 3, &amb));
    n = fill_combo_swatches(sw, 5);
    ce_match_opts_default(&mo); mo.ambiguous_gap = 0.0;
    TEST_ASSERT_EQUAL_INT(2, ce_match(ctx, sw, n, &mo, hits, 2, &amb));
    TEST_ASSERT_EQUAL_INT(0, amb);
    mo.ambiguous_gap = -3.0;
    TEST_ASSERT_EQUAL_INT(2, ce_match(ctx, sw, n, &mo, hits, 2, &amb));
    TEST_ASSERT_EQUAL_INT(0, amb);
    mo.ambiguous_gap = 1.0e9;
    TEST_ASSERT_EQUAL_INT(2, ce_match(ctx, sw, n, &mo, hits, 2, &amb));
    TEST_ASSERT_EQUAL_INT(1, amb);
    mo.ambiguous_gap = 1.0e9;
    TEST_ASSERT_EQUAL_INT(1, ce_match(ctx, sw, n, &mo, hits, 1, &amb));
    TEST_ASSERT_EQUAL_INT(0, amb); /* un solo hit: nunca ambiguo */
    /* Gap exactamente igual a la diferencia no es ambiguo (< estricto). */
    TEST_ASSERT_EQUAL_INT(2, ce_match(ctx, sw, n, NULL, hits, 2, &amb));
    mo.ambiguous_gap = hits[1].score - hits[0].score;
    TEST_ASSERT_EQUAL_INT(2, ce_match(ctx, sw, n, &mo, hits, 2, &amb));
    TEST_ASSERT_EQUAL_INT(0, amb);

    /* ce_analyze: errores sin escribir en `out`. */
    fill_combo_image(px, 5);
    img = make_image(px, IMG_SIDE, IMG_SIDE, IMG_SIDE * 3, CE_RGB8);
    memset(&res, 0x77, sizeof res);
    memcpy(&res_sentinel, &res, sizeof res);
    ce_match_opts_default(&mo);
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_analyze(NULL, &img, &po, &mo, &res));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_analyze(ctx, NULL, &po, &mo, &res));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_analyze(ctx, &img, &po, &mo, NULL));
    img.width = 0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_DIMS, ce_analyze(ctx, &img, &po, &mo, &res));
    img.width = IMG_SIDE;
    img.stride_bytes = 1;
    TEST_ASSERT_EQUAL_INT(CE_ERR_STRIDE, ce_analyze(ctx, &img, &po, &mo, &res));
    img.stride_bytes = IMG_SIDE * 3;
    img.fmt = (ce_pixel_format)9;
    TEST_ASSERT_EQUAL_INT(CE_ERR_FORMAT, ce_analyze(ctx, &img, &po, &mo, &res));
    img.fmt = CE_RGB8;
    po.k_init = 0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_analyze(ctx, &img, &po, &mo, &res));
    po = uniform_opts();
    mo.coverage_lambda = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_analyze(ctx, &img, &po, &mo, &res));
    mo.coverage_lambda = -1.0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_analyze(ctx, &img, &po, &mo, &res));
    TEST_ASSERT_EQUAL_MEMORY(&res_sentinel, &res, sizeof res);
    /* Caso válido: opciones NULL, posiciones no usadas a cero. */
    rc = ce_analyze(ctx, &img, NULL, NULL, &res);
    TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, rc);
    TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, res.n_hits);
    TEST_ASSERT_TRUE(res.n_swatches >= 1 && res.n_swatches <= CE_PALETTE_MAX_COLORS);
    TEST_ASSERT_EQUAL_INT(5, (int)res.hits[0].combo_id);
    {
        int i;
        for (i = res.n_swatches; i < CE_PALETTE_MAX_COLORS; ++i) {
            TEST_ASSERT_EQUAL_DOUBLE(0.0, res.swatches[i].weight);
            TEST_ASSERT_EQUAL_DOUBLE(0.0, res.swatches[i].lab.L);
        }
    }
    free(px);
    free(mem);
}

/* ------------------------------------------------------------------------
 * 4. Hash
 * ---------------------------------------------------------------------- */

static void test_result_hash_determinism(void)
{
    void *mem1, *mem2;
    ce_ctx *c1 = ctx_new(&mem1);
    ce_ctx *c2 = ctx_new(&mem2);
    uint8_t *px = (uint8_t *)malloc((size_t)IMG_SIDE * IMG_SIDE * 3);
    ce_image img;
    ce_result a, b, c, d;
    uint64_t ha, hb, hc, hd;

    TEST_ASSERT_NOT_NULL(px);
    fill_combo_image(px, 42);
    img = make_image(px, IMG_SIDE, IMG_SIDE, IMG_SIDE * 3, CE_RGB8);
    /* A cero antes: el motor escribe campo a campo y no toca el relleno de
     * los structs, así que el memcmp exige además que no queden bytes sin
     * escribir en las posiciones usadas. */
    memset(&a, 0, sizeof a);
    memset(&b, 0, sizeof b);
    memset(&c, 0, sizeof c);
    memset(&d, 0, sizeof d);
    /* Con peso al centro (defecto): pesos no enteros, el caso más exigente. */
    TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, ce_analyze(c1, &img, NULL, NULL, &a));
    TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, ce_analyze(c1, &img, NULL, NULL, &b));
    TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, ce_analyze(c2, &img, NULL, NULL, &c));
    ha = ce_result_hash(&a);
    hb = ce_result_hash(&b);
    hc = ce_result_hash(&c);
    TEST_ASSERT_EQUAL_MEMORY(&a, &b, sizeof a);
    TEST_ASSERT_EQUAL_MEMORY(&a, &c, sizeof a);
    TEST_ASSERT_EQUAL_UINT64(ha, hb);
    TEST_ASSERT_EQUAL_UINT64(ha, hc);
    TEST_ASSERT_EQUAL_INT(42, (int)a.hits[0].combo_id);
    /* Otra imagen -> otro hash. */
    fill_combo_image(px, 43);
    TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, ce_analyze(c1, &img, NULL, NULL, &d));
    hd = ce_result_hash(&d);
    TEST_ASSERT_NOT_EQUAL_UINT64(ha, hd);
    /* Truncar n_hits (lo que hace el CLI con --top K) cambia el hash. */
    b.n_hits = 3;
    TEST_ASSERT_NOT_EQUAL_UINT64(ha, ce_result_hash(&b));
    TEST_ASSERT_EQUAL_UINT64(ce_result_hash(&b), ce_result_hash(&b));
    printf("RESULT_HASH_COMBO42=%016" PRIx64 "\n", ha);
    free(px);
    free(mem1);
    free(mem2);
}

/* ------------------------------------------------------------------------
 * 5. Rendimiento
 * ---------------------------------------------------------------------- */

static void test_perf_match_and_analyze(void)
{
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch sw[5];
    ce_hit hits[CE_MATCH_MAX_HITS];
    ce_match_opts mo;
    ce_result res;
    double t0, best_match = HUGE_VAL, sum_match = 0.0, best_an = HUGE_VAL;
    const int W = 1024, H = 1024, stride = W * 4;
    uint8_t *px;
    ce_image img;
    int rep, i, x, y, amb;
    static const int idx[5] = {0, 10, 20, 30, 40};
    static const double w[5] = {0.3, 0.25, 0.2, 0.15, 0.1};

    for (i = 0; i < 5; ++i) {
        sw[i].lab = ce_dict_color_lab(idx[i]);
        TEST_ASSERT_EQUAL_INT(0, ce_dict_color_rgb(idx[i], sw[i].rgb));
        sw[i].weight = w[i];
    }
    ce_match_opts_default(&mo);
    for (rep = 0; rep < 200; ++rep) {
        double dt;
        t0 = now_ms();
        TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, ce_match(ctx, sw, 5, &mo, hits, CE_MATCH_MAX_HITS, &amb));
        dt = now_ms() - t0;
        sum_match += dt;
        if (dt < best_match) best_match = dt;
    }
    assert_hits_sorted(hits, CE_MATCH_MAX_HITS);

    px = (uint8_t *)malloc((size_t)stride * (size_t)H);
    TEST_ASSERT_NOT_NULL(px);
    for (y = 0; y < H; ++y) {
        for (x = 0; x < W; ++x) {
            uint8_t *p = px + (size_t)y * (size_t)stride + (size_t)x * 4;
            p[0] = (uint8_t)((x / 4 + (int)(lcg_next() % 16)) & 255);
            p[1] = (uint8_t)((y / 4 + (int)(lcg_next() % 16)) & 255);
            p[2] = (uint8_t)(((x + y) / 8 + (int)(lcg_next() % 16)) & 255);
            p[3] = 255;
        }
    }
    img = make_image(px, W, H, stride, CE_RGBA8);
    for (rep = 0; rep < 5; ++rep) {
        double dt;
        t0 = now_ms();
        TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, ce_analyze(ctx, &img, NULL, NULL, &res));
        dt = now_ms() - t0;
        if (dt < best_an) best_an = dt;
    }
    printf("MATCH_MS=%.3f (5 swatches x 348 combinaciones, mejor de 200; media %.3f) "
           "ANALYZE_1024_MS=%.2f (1024x1024 RGBA, mejor de 5)\n",
           best_match, sum_match / 200.0, best_an);
#ifdef CE_MATCH_GATE_MS
    TEST_ASSERT_TRUE_MESSAGE(best_match < (double)CE_MATCH_GATE_MS, "ce_match debe tardar < CE_MATCH_GATE_MS ms (nativo -O2)");
#endif
#ifdef CE_ANALYZE_GATE_MS
    TEST_ASSERT_TRUE_MESSAGE(best_an < (double)CE_ANALYZE_GATE_MS, "ce_analyze 1024x1024 debe tardar < 10 ms (nativo -O2)");
#endif
    free(px);
    free(mem);
}

/* ------------------------------------------------------------------------
 * Fixtures para los tests del CLI
 * ---------------------------------------------------------------------- */

static void write_combo_ppm(const char *path, uint8_t *px, int id)
{
    FILE *f;
    fill_combo_image(px, id);
    f = fopen(path, "wb");
    TEST_ASSERT_NOT_NULL_MESSAGE(f, "no puedo escribir el fixture PPM");
    fprintf(f, "P6\n# fixture de test_match: bandas exactas de la combinacion %d\n%d %d\n255\n",
            id, IMG_SIDE, IMG_SIDE);
    TEST_ASSERT_EQUAL_size_t((size_t)IMG_SIDE * IMG_SIDE * 3,
                             fwrite(px, 1, (size_t)IMG_SIDE * IMG_SIDE * 3, f));
    fclose(f);
}

static void test_write_cli_fixtures(void)
{
    static const int ids[3] = {1, 100, 348};
    uint8_t *px = (uint8_t *)malloc((size_t)IMG_SIDE * IMG_SIDE * 3);
    char path[1024];
    FILE *f;
    int i;
    TEST_ASSERT_NOT_NULL(px);
    for (i = 0; i < 3; ++i) {
        snprintf(path, sizeof path, "%s/match_%d.ppm", CE_TEST_OUT_DIR, ids[i]);
        write_combo_ppm(path, px, ids[i]);
    }
    /* Lista del batch: 3 válidas, una inexistente, línea vacía y comentario. */
    snprintf(path, sizeof path, "%s/batch_list.txt", CE_TEST_OUT_DIR);
    f = fopen(path, "wb");
    TEST_ASSERT_NOT_NULL(f);
    fprintf(f, "# lista de test_match\n");
    for (i = 0; i < 3; ++i) {
        fprintf(f, "%s/match_%d.ppm\n", CE_TEST_OUT_DIR, ids[i]);
        if (i == 1) fprintf(f, "%s/does_not_exist.ppm\r\n", CE_TEST_OUT_DIR);
    }
    fprintf(f, "\n");
    fclose(f);
    printf("fixtures del CLI escritos en %s\n", CE_TEST_OUT_DIR);
    free(px);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_recall_exact_block_images);
    RUN_TEST(test_adaptation_hypotheses);
    RUN_TEST(test_adaptation_opts_validation);
    RUN_TEST(test_false_adaptation_pink_black);
    RUN_TEST(test_exact_palettes_score_zero);
    RUN_TEST(test_tie_break_by_id);
    RUN_TEST(test_score_properties);
    RUN_TEST(test_errors_do_not_write);
    RUN_TEST(test_result_hash_determinism);
    RUN_TEST(test_perf_match_and_analyze);
    RUN_TEST(test_write_cli_fixtures);
    return UNITY_END();
}
