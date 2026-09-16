/*
 * test_palette.c — tests de la capa 2 (extracción de paleta) con Unity.
 *
 * Todo sintético (sin ficheros de entrada): imágenes generadas en memoria con
 * un LCG propio para el barajado. Casos (F2 del plan, §6 capa 2):
 *  (a) 200x200 con bloques 50/30/20 de colores con ΔE00 mutuo > 15 -> 3
 *      swatches con ΔE00 < 1 y peso +-0.02 en modo uniforme;
 *  (b) barajado de píxeles en modo uniforme -> bit-idéntico (memcmp);
 *  (c) dos ejecuciones (mismo ctx y ctx distinto) -> mismo hash y bytes;
 *  (d) máscara que anula un bloque -> ese color desaparece;
 *  (e) imágenes 1x1 y 1xN;
 *  (f) RGBA / RGBX / RGB con stride mayor que el mínimo -> mismo resultado;
 *  (g) todos los pesos a 0 -> 1 swatch con el color medio, sin NaN;
 *  (h) ce_dict_nearest_color sobre un color exacto del diccionario -> ΔE00 = 0.
 * Además: downscale (1024x1024 -> 256x256) con el mismo resultado que la
 * imagen ya reducida, regla de piel, parser PNM (ce_pnm.c) y rendimiento de
 * 1024x1024 RGBA (clock_gettime; cota CE_PERF_GATE_MS solo en nativo -O2).
 * Escribe fixtures PPM/PGM en CE_TEST_OUT_DIR para los tests del CLI.
 */
/* clock_gettime/CLOCK_MONOTONIC son POSIX: con -std=c11 estricto (sin
 * extensiones) musl/Emscripten solo los declara si se pide explícitamente. */
#define _POSIX_C_SOURCE 200809L

#include "ce/ce.h"
#include "ce_pnm.h"
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

static void *ctx_mem_alloc(void)
{
    void *mem = aligned_alloc(16, ce_ctx_size());
    TEST_ASSERT_NOT_NULL(mem);
    return mem;
}

static ce_ctx *ctx_new(void **mem)
{
    ce_ctx *ctx;
    *mem = ctx_mem_alloc();
    ctx = ce_ctx_init(*mem, ce_ctx_size());
    TEST_ASSERT_NOT_NULL(ctx);
    return ctx;
}

typedef struct {
    uint8_t rgb[3];
    double fraction; /* fracción de filas */
} block_spec;

/* Tres colores con ΔE00 mutuo > 15. */
static const block_spec BLOCKS3[3] = {
    {{200, 30, 40}, 0.50},
    {{30, 60, 200}, 0.30},
    {{40, 180, 60}, 0.20}
};

/* Imagen por bandas horizontales: rellena `px` (w x h, stride, bpp). Los
 * bytes fuera de los canales RGB (alpha, relleno del stride) se llenan con
 * basura del LCG para comprobar que se ignoran. */
static void fill_bands(uint8_t *px, int w, int h, int stride, int bpp,
                       const block_spec *blocks, int nblocks)
{
    int y, x, b = 0, boundary;
    memset(px, 0, (size_t)stride * (size_t)h);
    for (y = 0; y < h; ++y) {
        uint8_t *row = px + (size_t)y * (size_t)stride;
        int i;
        for (i = 0; i < stride; ++i) {
            row[i] = (uint8_t)lcg_next();
        }
    }
    boundary = (int)(h * blocks[0].fraction + 0.5);
    for (y = 0; y < h; ++y) {
        while (y >= boundary && b + 1 < nblocks) {
            double acc = 0.0;
            int k;
            ++b;
            for (k = 0; k <= b; ++k) acc += blocks[k].fraction;
            boundary = (int)(h * acc + 0.5);
        }
        for (x = 0; x < w; ++x) {
            uint8_t *p = px + (size_t)y * (size_t)stride + (size_t)x * (size_t)bpp;
            p[0] = blocks[b].rgb[0];
            p[1] = blocks[b].rgb[1];
            p[2] = blocks[b].rgb[2];
        }
    }
}

static ce_image make_image(const uint8_t *px, int w, int h, int stride, ce_pixel_format fmt, const uint8_t *mask)
{
    ce_image img;
    img.pixels = px;
    img.width = w;
    img.height = h;
    img.stride_bytes = stride;
    img.fmt = fmt;
    img.mask = mask;
    return img;
}

static ce_palette_opts uniform_opts(void)
{
    ce_palette_opts o;
    ce_palette_opts_default(&o);
    o.center_sigma = 0.0;
    return o;
}

/* Comprueba las invariantes de cualquier paleta válida. */
static void assert_palette_invariants(const ce_swatch *sw, int n, int max_colors)
{
    double sum = 0.0;
    int i;
    TEST_ASSERT_TRUE(n >= 1 && n <= max_colors);
    for (i = 0; i < n; ++i) {
        uint8_t r, g, b;
        TEST_ASSERT_TRUE(isfinite(sw[i].lab.L) && isfinite(sw[i].lab.a) && isfinite(sw[i].lab.b));
        TEST_ASSERT_TRUE(sw[i].weight > 0.0 && sw[i].weight <= 1.0);
        if (i > 0) {
            TEST_ASSERT_TRUE_MESSAGE(sw[i - 1].weight >= sw[i].weight, "swatches no ordenados por peso");
        }
        ce_lab_to_srgb8(sw[i].lab, &r, &g, &b);
        TEST_ASSERT_EQUAL_UINT8(r, sw[i].rgb[0]);
        TEST_ASSERT_EQUAL_UINT8(g, sw[i].rgb[1]);
        TEST_ASSERT_EQUAL_UINT8(b, sw[i].rgb[2]);
        sum += sw[i].weight;
    }
    TEST_ASSERT_DOUBLE_WITHIN(1e-12, 1.0, sum);
}

/* ΔE00 mínimo entre `lab` y los n swatches. */
static double min_de_to_palette(ce_lab lab, const ce_swatch *sw, int n)
{
    double best = HUGE_VAL;
    int i;
    for (i = 0; i < n; ++i) {
        const double d = ce_de2000(lab, sw[i].lab);
        if (d < best) best = d;
    }
    return best;
}

/* Comprueba que la paleta contiene los bloques (ΔE00 < de_tol) con sus pesos
 * (+- w_tol), en el orden de peso descendente. */
static void assert_blocks_recovered(const ce_swatch *sw, int n, const block_spec *blocks,
                                    int nblocks, double de_tol, double w_tol)
{
    int k;
    TEST_ASSERT_EQUAL_INT(nblocks, n);
    for (k = 0; k < nblocks; ++k) {
        const ce_lab want = ce_srgb8_to_lab(blocks[k].rgb[0], blocks[k].rgb[1], blocks[k].rgb[2]);
        const double de = ce_de2000(want, sw[k].lab);
        char msg[128];
        snprintf(msg, sizeof msg, "bloque %d: dE00=%.4f peso=%.4f (esperado %.2f)", k, de, sw[k].weight,
                 blocks[k].fraction);
        TEST_ASSERT_TRUE_MESSAGE(de < de_tol, msg);
        TEST_ASSERT_DOUBLE_WITHIN_MESSAGE(w_tol, blocks[k].fraction, sw[k].weight, msg);
    }
}

/* ------------------------------------------------------------------------
 * Tests
 * ---------------------------------------------------------------------- */

/* (a) 200x200, bloques 50/30/20, modo uniforme. */
static void test_three_blocks_uniform(void)
{
    const int w = 200, h = 200, stride = w * 4;
    uint8_t *px = (uint8_t *)malloc((size_t)stride * (size_t)h);
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch sw[8];
    ce_image img;
    ce_palette_opts o = uniform_opts();
    int n, i, j;

    TEST_ASSERT_NOT_NULL(px);
    /* Los colores del test están separados. */
    for (i = 0; i < 3; ++i) {
        for (j = i + 1; j < 3; ++j) {
            const double de = ce_de2000(ce_srgb8_to_lab(BLOCKS3[i].rgb[0], BLOCKS3[i].rgb[1], BLOCKS3[i].rgb[2]),
                                        ce_srgb8_to_lab(BLOCKS3[j].rgb[0], BLOCKS3[j].rgb[1], BLOCKS3[j].rgb[2]));
            TEST_ASSERT_TRUE_MESSAGE(de > 15.0, "los colores de prueba deben distar > 15 dE00");
        }
    }
    fill_bands(px, w, h, stride, 4, BLOCKS3, 3);
    img = make_image(px, w, h, stride, CE_RGBA8, NULL);
    n = ce_palette_extract(ctx, &img, &o, sw, 8);
    TEST_ASSERT_TRUE(n >= 1);
    assert_palette_invariants(sw, n, o.max_colors);
    assert_blocks_recovered(sw, n, BLOCKS3, 3, 1.0, 0.02);
    /* Bloques puros: el Lab del swatch es exactamente el del color y el rgb
     * vuelve al original. */
    for (i = 0; i < 3; ++i) {
        TEST_ASSERT_EQUAL_UINT8(BLOCKS3[i].rgb[0], sw[i].rgb[0]);
        TEST_ASSERT_EQUAL_UINT8(BLOCKS3[i].rgb[1], sw[i].rgb[1]);
        TEST_ASSERT_EQUAL_UINT8(BLOCKS3[i].rgb[2], sw[i].rgb[2]);
    }
    printf("(a) uniforme: %d swatches; pesos %.4f %.4f %.4f\n", n, sw[0].weight, sw[1].weight, sw[2].weight);

    /* Con peso al centro (por defecto) el conjunto de colores es el mismo
     * (ΔE00 < 1) aunque los pesos cambien. */
    ce_palette_opts_default(&o);
    n = ce_palette_extract(ctx, &img, &o, sw, 8);
    assert_palette_invariants(sw, n, o.max_colors);
    TEST_ASSERT_EQUAL_INT(3, n);
    for (i = 0; i < 3; ++i) {
        const ce_lab want = ce_srgb8_to_lab(BLOCKS3[i].rgb[0], BLOCKS3[i].rgb[1], BLOCKS3[i].rgb[2]);
        TEST_ASSERT_TRUE(min_de_to_palette(want, sw, n) < 1.0);
    }
    printf("(a) centro:   %d swatches; pesos %.4f %.4f %.4f\n", n, sw[0].weight, sw[1].weight, sw[2].weight);
    free(px);
    free(mem);
}

/* (b) Barajado de píxeles (Fisher-Yates con LCG) en modo uniforme: bit-idéntico. */
static void test_shuffle_invariance_uniform(void)
{
    const int w = 200, h = 200, stride = w * 3;
    const size_t npix = (size_t)w * (size_t)h;
    uint8_t *px = (uint8_t *)malloc(npix * 3);
    uint8_t *shuffled = (uint8_t *)malloc(npix * 3);
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch a[8], b[8];
    ce_image img;
    ce_palette_opts o = uniform_opts();
    int na, nb;
    size_t i;

    TEST_ASSERT_NOT_NULL(px);
    TEST_ASSERT_NOT_NULL(shuffled);
    fill_bands(px, w, h, stride, 3, BLOCKS3, 3);
    memcpy(shuffled, px, npix * 3);
    for (i = npix - 1; i > 0; --i) {
        const size_t j = (size_t)lcg_next() % (i + 1);
        uint8_t t[3];
        memcpy(t, shuffled + i * 3, 3);
        memcpy(shuffled + i * 3, shuffled + j * 3, 3);
        memcpy(shuffled + j * 3, t, 3);
    }
    memset(a, 0, sizeof a);
    memset(b, 0, sizeof b);
    img = make_image(px, w, h, stride, CE_RGB8, NULL);
    na = ce_palette_extract(ctx, &img, &o, a, 8);
    img = make_image(shuffled, w, h, stride, CE_RGB8, NULL);
    nb = ce_palette_extract(ctx, &img, &o, b, 8);
    TEST_ASSERT_EQUAL_INT(na, nb);
    TEST_ASSERT_EQUAL_INT(3, na);
    TEST_ASSERT_EQUAL_MEMORY_MESSAGE(a, b, sizeof(ce_swatch) * (size_t)na,
                                     "barajar pixeles debe dar bytes identicos en modo uniforme");
    TEST_ASSERT_EQUAL_UINT64(ce_swatch_hash(a, na), ce_swatch_hash(b, nb));

    /* También con una imagen de ruido (muchos bins): sigue siendo exacto. */
    for (i = 0; i < npix * 3; ++i) {
        px[i] = (uint8_t)(lcg_next() % 256);
    }
    memcpy(shuffled, px, npix * 3);
    for (i = npix - 1; i > 0; --i) {
        const size_t j = (size_t)lcg_next() % (i + 1);
        uint8_t t[3];
        memcpy(t, shuffled + i * 3, 3);
        memcpy(shuffled + i * 3, shuffled + j * 3, 3);
        memcpy(shuffled + j * 3, t, 3);
    }
    img = make_image(px, w, h, stride, CE_RGB8, NULL);
    na = ce_palette_extract(ctx, &img, &o, a, 8);
    img = make_image(shuffled, w, h, stride, CE_RGB8, NULL);
    nb = ce_palette_extract(ctx, &img, &o, b, 8);
    TEST_ASSERT_EQUAL_INT(na, nb);
    assert_palette_invariants(a, na, o.max_colors);
    TEST_ASSERT_EQUAL_MEMORY(a, b, sizeof(ce_swatch) * (size_t)na);
    printf("(b) barajado: %d swatches, hash %016" PRIx64 " (bandas) / ruido %d swatches\n", 3,
           ce_swatch_hash(a, 0) ^ 0, na);
    free(px);
    free(shuffled);
    free(mem);
}

/* (c) Dos ejecuciones -> mismo hash y mismos bytes, con el mismo contexto y
 *     con otro contexto, con las opciones por defecto (peso al centro). */
static void test_determinism_two_runs(void)
{
    const int w = 160, h = 120, stride = w * 4 + 12;
    uint8_t *px = (uint8_t *)malloc((size_t)stride * (size_t)h);
    void *mem1, *mem2;
    ce_ctx *ctx1 = ctx_new(&mem1);
    ce_ctx *ctx2 = ctx_new(&mem2);
    ce_swatch a[8], b[8], c[8];
    ce_image img;
    int na, nb, nc;
    size_t i;

    TEST_ASSERT_NOT_NULL(px);
    for (i = 0; i < (size_t)stride * (size_t)h; ++i) {
        px[i] = (uint8_t)(lcg_next() % 256);
    }
    memset(a, 0, sizeof a);
    memset(b, 0, sizeof b);
    memset(c, 0, sizeof c);
    img = make_image(px, w, h, stride, CE_RGBA8, NULL);
    na = ce_palette_extract(ctx1, &img, NULL, a, 8);
    nb = ce_palette_extract(ctx1, &img, NULL, b, 8);
    nc = ce_palette_extract(ctx2, &img, NULL, c, 8);
    TEST_ASSERT_TRUE(na >= 1);
    TEST_ASSERT_EQUAL_INT(na, nb);
    TEST_ASSERT_EQUAL_INT(na, nc);
    assert_palette_invariants(a, na, 5);
    TEST_ASSERT_EQUAL_MEMORY(a, b, sizeof(ce_swatch) * (size_t)na);
    TEST_ASSERT_EQUAL_MEMORY(a, c, sizeof(ce_swatch) * (size_t)na);
    TEST_ASSERT_EQUAL_UINT64(ce_swatch_hash(a, na), ce_swatch_hash(b, nb));
    TEST_ASSERT_EQUAL_UINT64(ce_swatch_hash(a, na), ce_swatch_hash(c, nc));
    printf("(c) determinismo: %d swatches, hash %016" PRIx64 "\n", na, ce_swatch_hash(a, na));
    free(px);
    free(mem1);
    free(mem2);
}

/* (d) Máscara que anula el bloque C: desaparece y los otros dos se reparten
 *     50/30 -> 0.625/0.375. */
static void test_mask_removes_block(void)
{
    const int w = 200, h = 200, stride = w * 3;
    uint8_t *px = (uint8_t *)malloc((size_t)stride * (size_t)h);
    uint8_t *mask = (uint8_t *)malloc((size_t)w * (size_t)h);
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch sw[8];
    ce_image img;
    ce_palette_opts o = uniform_opts();
    ce_lab labC;
    int n, y, x;

    TEST_ASSERT_NOT_NULL(px);
    TEST_ASSERT_NOT_NULL(mask);
    fill_bands(px, w, h, stride, 3, BLOCKS3, 3);
    for (y = 0; y < h; ++y) {
        for (x = 0; x < w; ++x) {
            mask[y * w + x] = (y >= 160) ? 0 : 255; /* bloque C = filas 160..199 */
        }
    }
    img = make_image(px, w, h, stride, CE_RGB8, mask);
    n = ce_palette_extract(ctx, &img, &o, sw, 8);
    assert_palette_invariants(sw, n, o.max_colors);
    TEST_ASSERT_EQUAL_INT(2, n);
    labC = ce_srgb8_to_lab(BLOCKS3[2].rgb[0], BLOCKS3[2].rgb[1], BLOCKS3[2].rgb[2]);
    TEST_ASSERT_TRUE_MESSAGE(min_de_to_palette(labC, sw, n) > 5.0, "el color enmascarado no debe aparecer");
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, 0.625, sw[0].weight);
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, 0.375, sw[1].weight);
    TEST_ASSERT_TRUE(ce_de2000(ce_srgb8_to_lab(200, 30, 40), sw[0].lab) < 1e-9);
    TEST_ASSERT_TRUE(ce_de2000(ce_srgb8_to_lab(30, 60, 200), sw[1].lab) < 1e-9);

    /* Máscara parcial (128 en el bloque C): sigue presente con peso ~ 0.2*128/255
     * renormalizado = 0.1004/0.9004 -> 0.1115. */
    for (y = 160; y < h; ++y) {
        for (x = 0; x < w; ++x) mask[y * w + x] = 128;
    }
    n = ce_palette_extract(ctx, &img, &o, sw, 8);
    assert_palette_invariants(sw, n, o.max_colors);
    TEST_ASSERT_EQUAL_INT(3, n);
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, (0.2 * 128.0) / (0.8 * 255.0 + 0.2 * 128.0), sw[2].weight);
    printf("(d) mascara: bloque anulado desaparece; parcial peso=%.6f\n", sw[2].weight);
    free(px);
    free(mask);
    free(mem);
}

/* (e) 1x1 y 1xN. */
static void test_tiny_images(void)
{
    uint8_t px1[4] = {12, 200, 77, 9};
    uint8_t *pxn;
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch sw[8];
    ce_image img;
    ce_palette_opts o = uniform_opts();
    const int N = 37;
    int n, i;

    img = make_image(px1, 1, 1, 4, CE_RGBA8, NULL);
    n = ce_palette_extract(ctx, &img, &o, sw, 8);
    TEST_ASSERT_EQUAL_INT(1, n);
    assert_palette_invariants(sw, n, o.max_colors);
    TEST_ASSERT_EQUAL_DOUBLE(1.0, sw[0].weight);
    TEST_ASSERT_EQUAL_UINT8(12, sw[0].rgb[0]);
    TEST_ASSERT_EQUAL_UINT8(200, sw[0].rgb[1]);
    TEST_ASSERT_EQUAL_UINT8(77, sw[0].rgb[2]);
    /* Con peso al centro también (un píxel = el centro). */
    n = ce_palette_extract(ctx, &img, NULL, sw, 8);
    TEST_ASSERT_EQUAL_INT(1, n);
    TEST_ASSERT_EQUAL_DOUBLE(1.0, sw[0].weight);

    /* 1xN: dos colores, 25 + 12 píxeles. */
    pxn = (uint8_t *)malloc((size_t)N * 3);
    TEST_ASSERT_NOT_NULL(pxn);
    for (i = 0; i < N; ++i) {
        const uint8_t *c = (i < 25) ? BLOCKS3[0].rgb : BLOCKS3[1].rgb;
        memcpy(pxn + i * 3, c, 3);
    }
    img = make_image(pxn, 1, N, 3, CE_RGB8, NULL);
    n = ce_palette_extract(ctx, &img, &o, sw, 8);
    assert_palette_invariants(sw, n, o.max_colors);
    TEST_ASSERT_EQUAL_INT(2, n);
    TEST_ASSERT_DOUBLE_WITHIN(1e-12, 25.0 / 37.0, sw[0].weight);
    TEST_ASSERT_DOUBLE_WITHIN(1e-12, 12.0 / 37.0, sw[1].weight);
    /* Nx1 (fila) igual. */
    img = make_image(pxn, N, 1, N * 3, CE_RGB8, NULL);
    n = ce_palette_extract(ctx, &img, &o, sw, 8);
    TEST_ASSERT_EQUAL_INT(2, n);
    TEST_ASSERT_DOUBLE_WITHIN(1e-12, 25.0 / 37.0, sw[0].weight);
    /* cap = 1 recorta y renormaliza. */
    n = ce_palette_extract(ctx, &img, &o, sw, 1);
    TEST_ASSERT_EQUAL_INT(1, n);
    TEST_ASSERT_EQUAL_DOUBLE(1.0, sw[0].weight);
    printf("(e) 1x1 y 1x%d OK\n", N);
    free(pxn);
    free(mem);
}

/* (f) RGBA / RGBX / RGB con stride mayor que el mínimo: mismo resultado. */
static void test_formats_and_stride(void)
{
    const int w = 123, h = 77;
    const int strides[3] = {w * 4 + 5, w * 4 + 64, w * 3 + 17};
    const ce_pixel_format fmts[3] = {CE_RGBA8, CE_RGBX8, CE_RGB8};
    const int bpps[3] = {4, 4, 3};
    uint8_t *tight = (uint8_t *)malloc((size_t)w * 3 * (size_t)h);
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch ref[8], sw[8];
    ce_image img;
    ce_palette_opts o;
    int nref, n, k, y, x;

    TEST_ASSERT_NOT_NULL(tight);
    /* Imagen con textura: bandas + ruido leve, para que haya muchos bins. */
    fill_bands(tight, w, h, w * 3, 3, BLOCKS3, 3);
    for (y = 0; y < h; ++y) {
        for (x = 0; x < w; ++x) {
            uint8_t *p = tight + ((size_t)y * (size_t)w + (size_t)x) * 3;
            int c;
            for (c = 0; c < 3; ++c) {
                int v = p[c] + (int)(lcg_next() % 21) - 10;
                p[c] = (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v));
            }
        }
    }
    ce_palette_opts_default(&o); /* peso al centro: también debe ser exacto */
    memset(ref, 0, sizeof ref);
    img = make_image(tight, w, h, w * 3, CE_RGB8, NULL);
    nref = ce_palette_extract(ctx, &img, &o, ref, 8);
    assert_palette_invariants(ref, nref, o.max_colors);

    for (k = 0; k < 3; ++k) {
        uint8_t *px = (uint8_t *)malloc((size_t)strides[k] * (size_t)h);
        size_t i;
        TEST_ASSERT_NOT_NULL(px);
        for (i = 0; i < (size_t)strides[k] * (size_t)h; ++i) {
            px[i] = (uint8_t)lcg_next(); /* basura en alpha y relleno */
        }
        for (y = 0; y < h; ++y) {
            for (x = 0; x < w; ++x) {
                memcpy(px + (size_t)y * (size_t)strides[k] + (size_t)x * (size_t)bpps[k],
                       tight + ((size_t)y * (size_t)w + (size_t)x) * 3, 3);
            }
        }
        memset(sw, 0, sizeof sw);
        img = make_image(px, w, h, strides[k], fmts[k], NULL);
        n = ce_palette_extract(ctx, &img, &o, sw, 8);
        TEST_ASSERT_EQUAL_INT(nref, n);
        TEST_ASSERT_EQUAL_MEMORY_MESSAGE(ref, sw, sizeof(ce_swatch) * (size_t)n,
                                         "formato/stride distinto debe dar bytes identicos");
        free(px);
    }
    printf("(f) RGBA/RGBX/RGB con stride: %d swatches identicos\n", nref);
    free(tight);
    free(mem);
}

/* (g) Máscara toda a 0: un swatch con el color medio, sin NaN. */
static void test_all_weights_zero(void)
{
    const int w = 50, h = 40;
    uint8_t *px = (uint8_t *)malloc((size_t)w * 3 * (size_t)h);
    uint8_t *mask = (uint8_t *)calloc((size_t)w * (size_t)h, 1);
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch sw[8];
    ce_image img;
    ce_lab mean;
    int n;

    TEST_ASSERT_NOT_NULL(px);
    TEST_ASSERT_NOT_NULL(mask);
    fill_bands(px, w, h, w * 3, 3, BLOCKS3, 3);
    memset(sw, 0xAB, sizeof sw);
    img = make_image(px, w, h, w * 3, CE_RGB8, mask);
    n = ce_palette_extract(ctx, &img, NULL, sw, 8);
    TEST_ASSERT_EQUAL_INT(1, n);
    assert_palette_invariants(sw, n, 5);
    TEST_ASSERT_EQUAL_DOUBLE(1.0, sw[0].weight);
    /* Media sin ponderar: 0.5*A + 0.3*B + 0.2*C (h = 40 -> 20/12/8 filas). */
    mean = ce_srgb_to_lab((20.0 * 200 + 12.0 * 30 + 8.0 * 40) / 40.0 / 255.0,
                          (20.0 * 30 + 12.0 * 60 + 8.0 * 180) / 40.0 / 255.0,
                          (20.0 * 40 + 12.0 * 200 + 8.0 * 60) / 40.0 / 255.0);
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, mean.L, sw[0].lab.L);
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, mean.a, sw[0].lab.a);
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, mean.b, sw[0].lab.b);
    /* El segundo swatch no se toca. */
    TEST_ASSERT_EQUAL_UINT8(0xAB, ((unsigned char *)&sw[1])[0]);

    /* Sigma minúscula: la gaussiana se anula en todos los píxeles (w y h
     * pares: el centro cae entre píxeles) -> mismo fallback, sin NaN. */
    {
        ce_palette_opts o;
        ce_palette_opts_default(&o);
        o.center_sigma = 1e-9;
        img.mask = NULL;
        n = ce_palette_extract(ctx, &img, &o, sw, 8);
        TEST_ASSERT_EQUAL_INT(1, n);
        assert_palette_invariants(sw, n, 5);
    }
    printf("(g) pesos 0: 1 swatch #%02x%02x%02x\n", sw[0].rgb[0], sw[0].rgb[1], sw[0].rgb[2]);
    free(px);
    free(mask);
    free(mem);
}

/* (h) ce_dict_nearest_color: color exacto del diccionario -> índice y ΔE00 = 0;
 *     también a través de una paleta extraída de una imagen con ese color. */
static void test_dict_nearest_color(void)
{
    const int n_colors = ce_dict_num_colors();
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    uint8_t px[10 * 10 * 3];
    ce_swatch sw[8];
    ce_image img;
    ce_palette_opts o = uniform_opts();
    double de = 1.0;
    int i, n, idx;
    ce_lab nan_lab;

    for (i = 0; i < n_colors; ++i) {
        de = 1.0;
        idx = ce_dict_nearest_color(ce_dict_color_lab(i), &de);
        TEST_ASSERT_EQUAL_INT(i, idx);
        TEST_ASSERT_EQUAL_DOUBLE(0.0, de);
    }
    /* Paleta de una imagen del color 7 del diccionario. */
    {
        uint8_t rgb[3];
        TEST_ASSERT_EQUAL_INT(0, ce_dict_color_rgb(7, rgb));
        for (i = 0; i < 100; ++i) memcpy(px + i * 3, rgb, 3);
    }
    img = make_image(px, 10, 10, 30, CE_RGB8, NULL);
    n = ce_palette_extract(ctx, &img, &o, sw, 8);
    TEST_ASSERT_EQUAL_INT(1, n);
    de = 1.0;
    idx = ce_dict_nearest_color(sw[0].lab, &de);
    TEST_ASSERT_EQUAL_INT(7, idx);
    TEST_ASSERT_EQUAL_DOUBLE(0.0, de);
    /* Sin `de` y con NaN. */
    TEST_ASSERT_EQUAL_INT(7, ce_dict_nearest_color(sw[0].lab, NULL));
    nan_lab.L = NAN; nan_lab.a = 0.0; nan_lab.b = 0.0;
    TEST_ASSERT_EQUAL_INT(-1, ce_dict_nearest_color(nan_lab, &de));
    TEST_ASSERT_TRUE(isnan(de));
    printf("(h) nearest: %d colores del diccionario a dE00 = 0\n", n_colors);
    free(mem);
}

/* Downscale: 1024x1024 con bloques 4x4 constantes reduce (f = 4) a la misma
 * imagen 256x256 -> mismos bytes que extraer directamente de la reducida.
 * Además, bloques parciales del borde (1000x700, f = 4 -> 250x175). */
static void test_downscale_matches_reduced(void)
{
    const int W = 1024, H = 1024, w = 256, h = 256;
    uint8_t *small = (uint8_t *)malloc((size_t)w * 3 * (size_t)h);
    uint8_t *big = (uint8_t *)malloc((size_t)W * 4 * (size_t)H);
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch a[8], b[8];
    ce_image img;
    int na, nb, x, y;
    size_t i;

    TEST_ASSERT_NOT_NULL(small);
    TEST_ASSERT_NOT_NULL(big);
    for (i = 0; i < (size_t)w * 3 * (size_t)h; ++i) small[i] = (uint8_t)(lcg_next() % 256);
    for (y = 0; y < H; ++y) {
        for (x = 0; x < W; ++x) {
            const uint8_t *s = small + ((size_t)(y / 4) * (size_t)w + (size_t)(x / 4)) * 3;
            uint8_t *p = big + ((size_t)y * (size_t)W + (size_t)x) * 4;
            memcpy(p, s, 3);
            p[3] = (uint8_t)lcg_next();
        }
    }
    memset(a, 0, sizeof a);
    memset(b, 0, sizeof b);
    img = make_image(small, w, h, w * 3, CE_RGB8, NULL);
    na = ce_palette_extract(ctx, &img, NULL, a, 8);
    img = make_image(big, W, H, W * 4, CE_RGBA8, NULL);
    nb = ce_palette_extract(ctx, &img, NULL, b, 8);
    TEST_ASSERT_EQUAL_INT(na, nb);
    TEST_ASSERT_EQUAL_MEMORY_MESSAGE(a, b, sizeof(ce_swatch) * (size_t)na,
                                     "1024x1024 en bloques 4x4 debe reducir a la 256x256 exacta");
    /* Redondeo de la media: bloque 2x2 con (0,0,0),(1,1,1),(1,1,1),(1,1,1)
     * -> 3/4 = 0.75 -> 1; con (0,0,0)x2,(1,1,1)x2 -> 0.5 -> 1 (mitad arriba);
     * lo comprobamos por el color del único swatch. */
    {
        uint8_t q[2 * 2 * 3] = {0, 0, 0, 100, 100, 100, 100, 100, 100, 100, 100, 100};
        ce_palette_opts o = uniform_opts();
        o.max_side = 1;
        img = make_image(q, 2, 2, 6, CE_RGB8, NULL);
        na = ce_palette_extract(ctx, &img, &o, a, 8);
        TEST_ASSERT_EQUAL_INT(1, na);
        TEST_ASSERT_EQUAL_UINT8(75, a[0].rgb[0]); /* 300/4 = 75 exacto */
        q[3] = q[4] = q[5] = 0;                    /* 200/4 = 50 */
        na = ce_palette_extract(ctx, &img, &o, a, 8);
        TEST_ASSERT_EQUAL_UINT8(50, a[0].rgb[0]);
        q[9] = q[10] = q[11] = 101;                /* 201/4 = 50.25 -> 50 */
        na = ce_palette_extract(ctx, &img, &o, a, 8);
        TEST_ASSERT_EQUAL_UINT8(50, a[0].rgb[0]);
        q[9] = q[10] = q[11] = 102;                /* 202/4 = 50.5 -> 51 */
        na = ce_palette_extract(ctx, &img, &o, a, 8);
        TEST_ASSERT_EQUAL_UINT8(51, a[0].rgb[0]);
    }
    /* Bordes parciales: 1000x700 en bloques 4x4 de la 250x175. */
    {
        const int W2 = 1000, H2 = 700, w2 = 250, h2 = 175;
        for (y = 0; y < H2; ++y) {
            for (x = 0; x < W2; ++x) {
                const uint8_t *s = small + ((size_t)(y / 4) * (size_t)w + (size_t)(x / 4)) * 3;
                memcpy(big + ((size_t)y * (size_t)W2 + (size_t)x) * 3, s, 3);
            }
        }
        for (y = 0; y < h2; ++y) {
            memmove(small + (size_t)y * (size_t)w2 * 3, small + (size_t)y * (size_t)w * 3, (size_t)w2 * 3);
        }
        img = make_image(small, w2, h2, w2 * 3, CE_RGB8, NULL);
        na = ce_palette_extract(ctx, &img, NULL, a, 8);
        img = make_image(big, W2, H2, W2 * 3, CE_RGB8, NULL);
        nb = ce_palette_extract(ctx, &img, NULL, b, 8);
        TEST_ASSERT_EQUAL_INT(na, nb);
        TEST_ASSERT_EQUAL_MEMORY(a, b, sizeof(ce_swatch) * (size_t)na);
    }
    printf("downscale: 1024x1024 y 1000x700 coinciden con la reducida (%d swatches)\n", na);
    free(small);
    free(big);
    free(mem);
}

/* Regla de piel: un bloque de color piel (Chai-Ngan) desaparece con
 * skin_rule = 1 y está con skin_rule = 0. */
static void test_skin_rule(void)
{
    /* (224,172,140): Cb = 128-0.168736*224-0.331264*172+0.5*140 = 103.4;
     * Cr = 128+0.5*224-0.418688*172-0.081312*140 = 156.6 -> piel. */
    const block_spec blocks[2] = {{{30, 60, 200}, 0.6}, {{224, 172, 140}, 0.4}};
    const int w = 100, h = 100;
    uint8_t *px = (uint8_t *)malloc((size_t)w * 3 * (size_t)h);
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch sw[8];
    ce_image img;
    ce_palette_opts o = uniform_opts();
    const ce_lab skin = ce_srgb8_to_lab(224, 172, 140);
    int n;

    TEST_ASSERT_NOT_NULL(px);
    fill_bands(px, w, h, w * 3, 3, blocks, 2);
    img = make_image(px, w, h, w * 3, CE_RGB8, NULL);
    n = ce_palette_extract(ctx, &img, &o, sw, 8);
    TEST_ASSERT_EQUAL_INT(2, n);
    TEST_ASSERT_TRUE(min_de_to_palette(skin, sw, n) < 1e-9);
    o.skin_rule = 1;
    n = ce_palette_extract(ctx, &img, &o, sw, 8);
    assert_palette_invariants(sw, n, o.max_colors);
    TEST_ASSERT_EQUAL_INT(1, n);
    TEST_ASSERT_TRUE(min_de_to_palette(skin, sw, n) > 5.0);
    TEST_ASSERT_EQUAL_UINT8(30, sw[0].rgb[0]);
    printf("skin_rule: bloque piel anulado\n");
    free(px);
    free(mem);
}

/* Fusión y descarte: cuatro tonos de un mismo rojo (ΔE00 < 5 entre vecinos)
 * se fusionan en uno; un bloque del 2 % se descarta con min_weight 0.05 y
 * aparece con min_weight 0. */
static void test_merge_and_discard(void)
{
    const block_spec blocks[5] = {
        {{200, 30, 40}, 0.30}, {{205, 34, 44}, 0.28}, {{195, 26, 36}, 0.20},
        {{30, 60, 200}, 0.20}, {{40, 180, 60}, 0.02}
    };
    const int w = 100, h = 200;
    uint8_t *px = (uint8_t *)malloc((size_t)w * 3 * (size_t)h);
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch sw[8];
    ce_image img;
    ce_palette_opts o = uniform_opts();
    const ce_lab green = ce_srgb8_to_lab(40, 180, 60);
    int n;

    TEST_ASSERT_NOT_NULL(px);
    fill_bands(px, w, h, w * 3, 3, blocks, 5);
    img = make_image(px, w, h, w * 3, CE_RGB8, NULL);
    o.k_init = 8;
    n = ce_palette_extract(ctx, &img, &o, sw, 8);
    assert_palette_invariants(sw, n, o.max_colors);
    TEST_ASSERT_EQUAL_INT_MESSAGE(2, n, "3 rojos fusionados + azul; verde 2% descartado");
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, 0.78 / 0.98, sw[0].weight);
    TEST_ASSERT_TRUE(min_de_to_palette(green, sw, n) > 5.0);
    o.min_weight = 0.0;
    n = ce_palette_extract(ctx, &img, &o, sw, 8);
    assert_palette_invariants(sw, n, o.max_colors);
    TEST_ASSERT_EQUAL_INT(3, n);
    TEST_ASSERT_TRUE(min_de_to_palette(green, sw, n) < 1e-9);
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, 0.02, sw[2].weight);
    o.merge_de = 0.0;
    n = ce_palette_extract(ctx, &img, &o, sw, 8);
    TEST_ASSERT_EQUAL_INT(5, n);
    /* max_colors recorta y renormaliza. */
    o.max_colors = 2;
    n = ce_palette_extract(ctx, &img, &o, sw, 8);
    TEST_ASSERT_EQUAL_INT(2, n);
    TEST_ASSERT_DOUBLE_WITHIN(1e-12, 0.30 / 0.58, sw[0].weight);
    printf("fusion/descarte OK\n");
    free(px);
    free(mem);
}

/* Fusión de sombras (merge_light_de, experimento apagado por defecto): cuatro
 * tonos de un rosa palo que difieren sobre todo en L* (ΔE00 > 5 entre
 * vecinos, así que la fusión normal no los junta) + negro. Con
 * merge_light_de = 0 el resultado es bit a bit el de las opciones por
 * defecto; con 6 los rosas pasan a un swatch y el negro no se toca; un
 * azul con la misma L* que un rosa nunca se fusiona. */
static void test_merge_light_shades(void)
{
    const block_spec blocks[5] = {
        {{34, 37, 36}, 0.394}, {{180, 154, 162}, 0.227}, {{145, 122, 126}, 0.162},
        {{213, 184, 192}, 0.134}, {{107, 90, 87}, 0.083}
    };
    const block_spec blue_pink[2] = {{{180, 154, 162}, 0.5}, {{140, 160, 190}, 0.5}};
    const int w = 100, h = 500;
    uint8_t *px = (uint8_t *)malloc((size_t)w * 3 * (size_t)h);
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch base[8], off[8], on[8];
    ce_image img;
    ce_palette_opts o = uniform_opts();
    const ce_lab black = ce_srgb8_to_lab(34, 37, 36);
    int nb, noff, non, i;

    TEST_ASSERT_NOT_NULL(px);
    /* Los rosas vecinos distan > 5 ΔE00 (la fusión normal no actúa). */
    TEST_ASSERT_TRUE(ce_de2000(ce_srgb8_to_lab(180, 154, 162), ce_srgb8_to_lab(213, 184, 192)) > 5.0);
    TEST_ASSERT_TRUE(ce_de2000_k(ce_srgb8_to_lab(180, 154, 162), ce_srgb8_to_lab(213, 184, 192),
                                 CE_PALETTE_LIGHT_MERGE_KL, 1.0, 1.0) < 6.0);
    fill_bands(px, w, h, w * 3, 3, blocks, 5);
    img = make_image(px, w, h, w * 3, CE_RGB8, NULL);
    nb = ce_palette_extract(ctx, &img, &o, base, 8);
    o.merge_light_de = 0.0;
    noff = ce_palette_extract(ctx, &img, &o, off, 8);
    TEST_ASSERT_EQUAL_INT(5, nb);
    TEST_ASSERT_EQUAL_INT(nb, noff);
    TEST_ASSERT_EQUAL_HEX64(ce_swatch_hash(base, nb), ce_swatch_hash(off, noff));
    o.merge_light_de = -3.0; /* <= 0 también apaga */
    noff = ce_palette_extract(ctx, &img, &o, off, 8);
    TEST_ASSERT_EQUAL_HEX64(ce_swatch_hash(base, nb), ce_swatch_hash(off, noff));

    o.merge_light_de = 6.0;
    non = ce_palette_extract(ctx, &img, &o, on, 8);
    assert_palette_invariants(on, non, o.max_colors);
    printf("fusion de sombras (merge_light_de 6): %d -> %d swatches:", nb, non);
    for (i = 0; i < non; ++i) printf(" #%02x%02x%02x %.3f", on[i].rgb[0], on[i].rgb[1], on[i].rgb[2], on[i].weight);
    printf("\nLIGHT_MERGE_HASH=%016" PRIx64 "\n", ce_swatch_hash(on, non));
    /* Constante medida en nativo (Apple arm64): ASan y WASM (ce_libm.c) deben dar los mismos bits. */
    TEST_ASSERT_EQUAL_HEX64(0x701eaabfb2c0bebaULL, ce_swatch_hash(on, non));
    TEST_ASSERT_TRUE_MESSAGE(non >= 2 && non <= 3, "los rosas deben quedar en 1-2 swatches y el negro aparte");
    TEST_ASSERT_TRUE(min_de_to_palette(black, on, non) < 1e-9);
    TEST_ASSERT_TRUE(on[0].weight > 0.5); /* los rosas fusionados pesan más que el negro (39,4 %) */

    /* Azul y rosa con L* parecida: croma/tono distintos, no se fusionan. */
    fill_bands(px, w, h, w * 3, 3, blue_pink, 2);
    non = ce_palette_extract(ctx, &img, &o, on, 8);
    TEST_ASSERT_EQUAL_INT(2, non);
    free(px);
    free(mem);
}

/* Parser PNM: casos válidos (comentarios, espacios), y todos los rechazos. */
static void test_pnm_parser(void)
{
    static const uint8_t ok6[] = "P6\n2 1\n255\n\xff\x00\x00\x00\xff\x00";
    static const uint8_t ok5[] = "P5 # comentario\n\t2\r\n1 # otro\n255 \x80\x7f";
    static const uint8_t ws[] = "P6\n\n#c\n  2\n\n1 #c\n\f255\n\x01\x02\x03\x04\x05\x06";
    static const uint8_t trailing[] = "P6 1 1 255 \x01\x02\x03extra";
    ce_pnm_image im;

    memset(&im, 0, sizeof im);
    TEST_ASSERT_EQUAL_INT(CE_PNM_OK, ce_pnm_parse(ok6, sizeof ok6 - 1, &im));
    TEST_ASSERT_EQUAL_INT(6, im.type);
    TEST_ASSERT_EQUAL_INT(2, im.width);
    TEST_ASSERT_EQUAL_INT(1, im.height);
    TEST_ASSERT_EQUAL_INT(3, im.channels);
    TEST_ASSERT_EQUAL_size_t(6, im.data_len);
    TEST_ASSERT_EQUAL_PTR(ok6 + 11, im.data);
    TEST_ASSERT_EQUAL_UINT8(0xff, im.data[0]);

    TEST_ASSERT_EQUAL_INT(CE_PNM_OK, ce_pnm_parse(ok5, sizeof ok5 - 1, &im));
    TEST_ASSERT_EQUAL_INT(5, im.type);
    TEST_ASSERT_EQUAL_INT(1, im.channels);
    TEST_ASSERT_EQUAL_size_t(2, im.data_len);
    TEST_ASSERT_EQUAL_UINT8(0x80, im.data[0]);
    TEST_ASSERT_EQUAL_UINT8(0x7f, im.data[1]);

    TEST_ASSERT_EQUAL_INT(CE_PNM_OK, ce_pnm_parse(ws, sizeof ws - 1, &im));
    TEST_ASSERT_EQUAL_INT(2, im.width);
    TEST_ASSERT_EQUAL_UINT8(0x01, im.data[0]);
    TEST_ASSERT_EQUAL_UINT8(0x06, im.data[5]);

    TEST_ASSERT_EQUAL_INT(CE_PNM_OK, ce_pnm_parse(trailing, sizeof trailing - 1, &im));
    TEST_ASSERT_EQUAL_size_t(3, im.data_len);

    /* Rechazos: `im` no se toca. */
    memset(&im, 0x5A, sizeof im);
    {
        ce_pnm_image copy;
        static const uint8_t magic[] = "P3\n1 1\n255\n\x01\x02\x03";
        static const uint8_t nosep[] = "P61 1 255 \x01\x02\x03";
        static const uint8_t maxval[] = "P6\n1 1\n65535\n\x01\x02\x03\x04\x05\x06";
        static const uint8_t maxval2[] = "P6\n1 1\n254\n\x01\x02\x03";
        static const uint8_t zero[] = "P6\n0 1\n255\n";
        static const uint8_t huge[] = "P6\n16385 1\n255\n";
        static const uint8_t overflow[] = "P6\n99999999999999999999 1\n255\n";
        static const uint8_t trunc[] = "P6\n2 2\n255\n\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b";
        static const uint8_t nobody[] = "P6\n2 2\n255\n";
        static const uint8_t nonum[] = "P6\nab 1\n255\n";
        static const uint8_t neg[] = "P6\n-1 1\n255\n";
        static const uint8_t twosep[] = "P6 1 1 255"; /* sin separador tras maxval */
        static const uint8_t eof_hdr[] = "P6 1";
        memcpy(&copy, &im, sizeof im);
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_ARG, ce_pnm_parse(NULL, 10, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_ARG, ce_pnm_parse(ok6, sizeof ok6 - 1, NULL));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_MAGIC, ce_pnm_parse(ok6, 0, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_MAGIC, ce_pnm_parse(ok6, 1, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_MAGIC, ce_pnm_parse(magic, sizeof magic - 1, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_HEADER, ce_pnm_parse(nosep, sizeof nosep - 1, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_MAXVAL, ce_pnm_parse(maxval, sizeof maxval - 1, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_MAXVAL, ce_pnm_parse(maxval2, sizeof maxval2 - 1, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_DIMS, ce_pnm_parse(zero, sizeof zero - 1, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_DIMS, ce_pnm_parse(huge, sizeof huge - 1, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_HEADER, ce_pnm_parse(overflow, sizeof overflow - 1, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_TRUNCATED, ce_pnm_parse(trunc, sizeof trunc - 1, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_TRUNCATED, ce_pnm_parse(nobody, sizeof nobody - 1, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_HEADER, ce_pnm_parse(nonum, sizeof nonum - 1, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_HEADER, ce_pnm_parse(neg, sizeof neg - 1, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_HEADER, ce_pnm_parse(twosep, sizeof twosep - 1, &im));
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_HEADER, ce_pnm_parse(eof_hdr, sizeof eof_hdr - 1, &im));
        /* Cuerpo exacto justo al límite: ok con len exacta, truncado con len-1. */
        TEST_ASSERT_EQUAL_INT(CE_PNM_ERR_TRUNCATED, ce_pnm_parse(ok6, sizeof ok6 - 2, &im));
        TEST_ASSERT_EQUAL_MEMORY(&copy, &im, sizeof im);
    }
    TEST_ASSERT_EQUAL_STRING("cuerpo truncado", ce_pnm_strerror(CE_PNM_ERR_TRUNCATED));
    printf("pnm: parser OK\n");
}

/* Escribe los fixtures para los tests del CLI (ctest cli_palette_*) y los
 * vuelve a parsear: la paleta por el parser coincide con la extraída del
 * buffer original. */
static void test_write_fixtures_and_roundtrip(void)
{
    const int w = 200, h = 200;
    uint8_t *px = (uint8_t *)malloc((size_t)w * 3 * (size_t)h);
    uint8_t *mask = (uint8_t *)malloc((size_t)w * (size_t)h);
    uint8_t *file = NULL;
    size_t file_len, i;
    char path[1024];
    FILE *f;
    ce_pnm_image im;
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch a[8], b[8];
    ce_image img;
    ce_palette_opts o = uniform_opts();
    int na, nb, y;

    TEST_ASSERT_NOT_NULL(px);
    TEST_ASSERT_NOT_NULL(mask);
    fill_bands(px, w, h, w * 3, 3, BLOCKS3, 3);
    for (y = 0; y < h; ++y) memset(mask + (size_t)y * (size_t)w, (y >= 160) ? 0 : 255, (size_t)w);

    /* PPM. */
    snprintf(path, sizeof path, "%s/palette_3blocks.ppm", CE_TEST_OUT_DIR);
    f = fopen(path, "wb");
    TEST_ASSERT_NOT_NULL_MESSAGE(f, "no puedo escribir el fixture PPM");
    fprintf(f, "P6\n# fixture de test_palette (3 bloques 50/30/20)\n%d %d\n255\n", w, h);
    TEST_ASSERT_EQUAL_size_t((size_t)w * 3 * (size_t)h, fwrite(px, 1, (size_t)w * 3 * (size_t)h, f));
    fclose(f);
    /* PGM. */
    snprintf(path, sizeof path, "%s/palette_mask.pgm", CE_TEST_OUT_DIR);
    f = fopen(path, "wb");
    TEST_ASSERT_NOT_NULL(f);
    fprintf(f, "P5\n%d %d\n255\n", w, h);
    TEST_ASSERT_EQUAL_size_t((size_t)w * (size_t)h, fwrite(mask, 1, (size_t)w * (size_t)h, f));
    fclose(f);
    /* PPM truncado (la mitad del cuerpo). */
    snprintf(path, sizeof path, "%s/palette_truncated.ppm", CE_TEST_OUT_DIR);
    f = fopen(path, "wb");
    TEST_ASSERT_NOT_NULL(f);
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    fwrite(px, 1, (size_t)w * 3 * (size_t)h / 2, f);
    fclose(f);

    /* Releer el PPM y comparar con el buffer. */
    snprintf(path, sizeof path, "%s/palette_3blocks.ppm", CE_TEST_OUT_DIR);
    f = fopen(path, "rb");
    TEST_ASSERT_NOT_NULL(f);
    fseek(f, 0, SEEK_END);
    file_len = (size_t)ftell(f);
    fseek(f, 0, SEEK_SET);
    file = (uint8_t *)malloc(file_len);
    TEST_ASSERT_NOT_NULL(file);
    TEST_ASSERT_EQUAL_size_t(file_len, fread(file, 1, file_len, f));
    fclose(f);
    TEST_ASSERT_EQUAL_INT(CE_PNM_OK, ce_pnm_parse(file, file_len, &im));
    TEST_ASSERT_EQUAL_INT(w, im.width);
    TEST_ASSERT_EQUAL_INT(h, im.height);
    for (i = 0; i < im.data_len; ++i) {
        if (im.data[i] != px[i]) TEST_FAIL_MESSAGE("el cuerpo del PPM no coincide");
    }
    memset(a, 0, sizeof a);
    memset(b, 0, sizeof b);
    img = make_image(px, w, h, w * 3, CE_RGB8, mask);
    na = ce_palette_extract(ctx, &img, &o, a, 8);
    img = make_image(im.data, im.width, im.height, im.width * 3, CE_RGB8, mask);
    nb = ce_palette_extract(ctx, &img, &o, b, 8);
    TEST_ASSERT_EQUAL_INT(na, nb);
    TEST_ASSERT_EQUAL_MEMORY(a, b, sizeof(ce_swatch) * (size_t)na);
    printf("fixtures escritos en %s\n", CE_TEST_OUT_DIR);
    free(file);
    free(px);
    free(mask);
    free(mem);
}

static double now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1.0e6;
}

/* Rendimiento: 1024x1024 RGBA con textura (muchos bins), opciones por
 * defecto y k_init 64 como peor caso. Cota de 150 ms solo en nativo -O2. */
static void test_perf_1024(void)
{
    const int W = 1024, H = 1024, stride = W * 4;
    uint8_t *px = (uint8_t *)malloc((size_t)stride * (size_t)H);
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_swatch sw[8];
    ce_image img;
    ce_palette_opts o;
    double t0, best = HUGE_VAL, worst_k64 = 0.0;
    int rep, n, x, y;

    TEST_ASSERT_NOT_NULL(px);
    /* Gradiente + ruido: cubre miles de bins. */
    for (y = 0; y < H; ++y) {
        for (x = 0; x < W; ++x) {
            uint8_t *p = px + (size_t)y * (size_t)stride + (size_t)x * 4;
            p[0] = (uint8_t)((x / 4 + (int)(lcg_next() % 16)) & 255);
            p[1] = (uint8_t)((y / 4 + (int)(lcg_next() % 16)) & 255);
            p[2] = (uint8_t)(((x + y) / 8 + (int)(lcg_next() % 16)) & 255);
            p[3] = 255;
        }
    }
    img = make_image(px, W, H, stride, CE_RGBA8, NULL);
    ce_palette_opts_default(&o);
    for (rep = 0; rep < 5; ++rep) {
        double dt;
        t0 = now_ms();
        n = ce_palette_extract(ctx, &img, &o, sw, 8);
        dt = now_ms() - t0;
        TEST_ASSERT_TRUE(n >= 1);
        if (dt < best) best = dt;
    }
    assert_palette_invariants(sw, n, o.max_colors);
    o.k_init = CE_PALETTE_K_MAX;
    o.max_colors = CE_PALETTE_MAX_COLORS;
    for (rep = 0; rep < 3; ++rep) {
        double dt;
        t0 = now_ms();
        n = ce_palette_extract(ctx, &img, &o, sw, 8);
        dt = now_ms() - t0;
        TEST_ASSERT_TRUE(n >= 1);
        if (dt > worst_k64) worst_k64 = dt;
    }
    printf("PERF_1024_RGBA_MS=%.2f (mejor de 5, opciones por defecto); k_init=64: %.2f ms (peor de 3)\n",
           best, worst_k64);
#ifdef CE_PERF_GATE_MS
    TEST_ASSERT_TRUE_MESSAGE(best < (double)CE_PERF_GATE_MS, "1024x1024 RGBA debe extraerse en < 150 ms (nativo -O2)");
#endif
    free(px);
    free(mem);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_three_blocks_uniform);
    RUN_TEST(test_shuffle_invariance_uniform);
    RUN_TEST(test_determinism_two_runs);
    RUN_TEST(test_mask_removes_block);
    RUN_TEST(test_tiny_images);
    RUN_TEST(test_formats_and_stride);
    RUN_TEST(test_all_weights_zero);
    RUN_TEST(test_dict_nearest_color);
    RUN_TEST(test_downscale_matches_reduced);
    RUN_TEST(test_skin_rule);
    RUN_TEST(test_merge_and_discard);
    RUN_TEST(test_merge_light_shades);
    RUN_TEST(test_pnm_parser);
    RUN_TEST(test_write_fixtures_and_roundtrip);
    RUN_TEST(test_perf_1024);
    return UNITY_END();
}
