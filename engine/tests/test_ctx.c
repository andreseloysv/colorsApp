/*
 * test_ctx.c — tests del contexto (ce_ctx.c) y de la validación de entrada
 * (ce_image.c) con Unity.
 *
 * - test_ctx_size_budget: ce_ctx_size() <= 2 MiB y múltiplo de 16 (el mismo
 *   binario corre en nativo, ASan y WASM: la cota se comprueba en los dos
 *   targets del plan).
 * - ce_ctx_init: NULL con memoria NULL, tamaño insuficiente o desalineada;
 *   válido con el tamaño exacto; dos contextos independientes.
 * - Opciones por defecto y códigos de error de ce_palette_extract
 *   (CE_ERR_ARG, CE_ERR_CTX, CE_ERR_DIMS, CE_ERR_FORMAT, CE_ERR_STRIDE,
 *   CE_ERR_OPTS) sin escribir en la salida; errores de argumentos de la capa
 *   3 (ce_match / ce_analyze) y ce_result_hash (la batería completa de la
 *   capa 3 vive en test_match.c).
 */
#include "ce/ce.h"
#include "unity.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma STDC FP_CONTRACT OFF

#define CTX_BUDGET_BYTES (2u * 1024u * 1024u)

void setUp(void) {}
void tearDown(void) {}

static void *alloc_ctx_mem(size_t size)
{
    /* aligned_alloc exige size múltiplo de la alineación; ce_ctx_size() ya lo es. */
    void *mem = aligned_alloc(16, (size + 15u) & ~(size_t)15u);
    TEST_ASSERT_NOT_NULL(mem);
    return mem;
}

/* 1. Presupuesto: <= 2 MiB, múltiplo de 16, no trivial. */
static void test_ctx_size_budget(void)
{
    const size_t size = ce_ctx_size();
    printf("ce_ctx_size=%zu bytes (%.3f MiB, presupuesto %u)\n", size,
           (double)size / (1024.0 * 1024.0), CTX_BUDGET_BYTES);
    TEST_ASSERT_TRUE_MESSAGE(size <= CTX_BUDGET_BYTES, "ce_ctx_size() supera 2 MiB");
    TEST_ASSERT_TRUE_MESSAGE(size % 16u == 0u, "ce_ctx_size() no es multiplo de 16");
    /* Al menos la imagen reducida + pesos + histograma (orden de magnitud). */
    TEST_ASSERT_TRUE(size > 1500000u);
}

/* 2. ce_ctx_init: rechazos y aceptación. */
static void test_ctx_init_validation(void)
{
    const size_t size = ce_ctx_size();
    unsigned char *mem = (unsigned char *)alloc_ctx_mem(size + 64);
    ce_ctx *ctx;

    TEST_ASSERT_NULL(ce_ctx_init(NULL, size));
    TEST_ASSERT_NULL(ce_ctx_init(mem, size - 1));
    TEST_ASSERT_NULL(ce_ctx_init(mem, 0));
    TEST_ASSERT_NULL_MESSAGE(ce_ctx_init(mem + 8, size), "memoria alineada a 8 pero no a 16 debe rechazarse");
    TEST_ASSERT_NULL(ce_ctx_init(mem + 1, size));

    ctx = ce_ctx_init(mem, size);
    TEST_ASSERT_NOT_NULL(ctx);
    TEST_ASSERT_EQUAL_PTR(mem, ctx);
    /* Tamaño mayor que el necesario también vale. */
    TEST_ASSERT_NOT_NULL(ce_ctx_init(mem, size + 64));
    free(mem);
}

/* 3. Opciones por defecto del contrato. */
static void test_opts_default(void)
{
    ce_palette_opts o;
    ce_match_opts m;
    memset(&o, 0x55, sizeof o);
    ce_palette_opts_default(&o);
    TEST_ASSERT_EQUAL_INT(6, o.k_init);
    TEST_ASSERT_EQUAL_INT(20, o.max_iters);
    TEST_ASSERT_EQUAL_INT(5, o.max_colors);
    TEST_ASSERT_EQUAL_INT(256, o.max_side);
    TEST_ASSERT_EQUAL_DOUBLE(0.35, o.center_sigma);
    TEST_ASSERT_EQUAL_DOUBLE(5.0, o.merge_de);
    TEST_ASSERT_EQUAL_DOUBLE(0.05, o.min_weight);
    TEST_ASSERT_EQUAL_INT(0, o.skin_rule);
    TEST_ASSERT_EQUAL_DOUBLE(0.0, o.merge_light_de); /* experimento de fusión de sombras: apagado */
    ce_match_opts_default(&m);
    TEST_ASSERT_EQUAL_DOUBLE(1.0, m.kL);
    TEST_ASSERT_EQUAL_DOUBLE(1.0, m.kC);
    TEST_ASSERT_EQUAL_DOUBLE(1.0, m.kH);
    TEST_ASSERT_EQUAL_DOUBLE(1.0, m.coverage_lambda);
    TEST_ASSERT_EQUAL_DOUBLE(1.0, m.ambiguous_gap);
    TEST_ASSERT_EQUAL_DOUBLE(1.0, m.exposure_ev_max);
    TEST_ASSERT_EQUAL_DOUBLE(2.0, m.exposure_penalty);
    /* ADR-009 (2026-09-15): la hipótesis de iluminante queda como opción, no por defecto. */
    TEST_ASSERT_EQUAL_INT(0, m.illuminant_search);
    TEST_ASSERT_EQUAL_DOUBLE(2.0, m.illuminant_penalty);
    /* NULL no revienta. */
    ce_palette_opts_default(NULL);
    ce_match_opts_default(NULL);
}

/* Imagen 4x4 RGBA válida para las pruebas de validación. */
static void fill_small(uint8_t *px, int w, int h, int stride, int bpp)
{
    int x, y;
    for (y = 0; y < h; ++y) {
        for (x = 0; x < w; ++x) {
            uint8_t *p = px + y * stride + x * bpp;
            p[0] = 200; p[1] = 30; p[2] = 40;
            if (bpp == 4) p[3] = 255;
        }
    }
}

/* 4. Códigos de error y ausencia de escritura en `out`. */
static void test_extract_errors(void)
{
    const size_t size = ce_ctx_size();
    void *mem = alloc_ctx_mem(size);
    ce_ctx *ctx = ce_ctx_init(mem, size);
    uint8_t px[4 * 4 * 4];
    ce_image img;
    ce_palette_opts o;
    ce_swatch out[8];
    ce_swatch sentinel[8];
    int rc;

    TEST_ASSERT_NOT_NULL(ctx);
    fill_small(px, 4, 4, 16, 4);
    memset(out, 0xAB, sizeof out);
    memcpy(sentinel, out, sizeof out);
    img.pixels = px;
    img.width = 4;
    img.height = 4;
    img.stride_bytes = 16;
    img.fmt = CE_RGBA8;
    img.mask = NULL;
    ce_palette_opts_default(&o);

    /* Caso base en verde. */
    rc = ce_palette_extract(ctx, &img, &o, out, 8);
    TEST_ASSERT_EQUAL_INT(1, rc);
    memset(out, 0xAB, sizeof out);

    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_palette_extract(NULL, &img, &o, out, 8));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_palette_extract(ctx, NULL, &o, out, 8));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_palette_extract(ctx, &img, &o, NULL, 8));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_palette_extract(ctx, &img, &o, out, 0));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_palette_extract(ctx, &img, &o, out, -3));

    /* Contexto no inicializado (memoria a cero). */
    {
        void *raw = alloc_ctx_mem(size);
        memset(raw, 0, size);
        TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_palette_extract((ce_ctx *)raw, &img, &o, out, 8));
        free(raw);
    }

    /* Imagen. */
    img.pixels = NULL;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_palette_extract(ctx, &img, &o, out, 8));
    img.pixels = px;
    img.width = 0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_DIMS, ce_palette_extract(ctx, &img, &o, out, 8));
    img.width = 4;
    img.height = -1;
    TEST_ASSERT_EQUAL_INT(CE_ERR_DIMS, ce_palette_extract(ctx, &img, &o, out, 8));
    img.height = CE_IMAGE_MAX_SIDE + 1;
    TEST_ASSERT_EQUAL_INT(CE_ERR_DIMS, ce_palette_extract(ctx, &img, &o, out, 8));
    img.height = 4;
    img.fmt = (ce_pixel_format)3;
    TEST_ASSERT_EQUAL_INT(CE_ERR_FORMAT, ce_palette_extract(ctx, &img, &o, out, 8));
    img.fmt = (ce_pixel_format)-1;
    TEST_ASSERT_EQUAL_INT(CE_ERR_FORMAT, ce_palette_extract(ctx, &img, &o, out, 8));
    img.fmt = CE_RGBA8;
    img.stride_bytes = 15;
    TEST_ASSERT_EQUAL_INT(CE_ERR_STRIDE, ce_palette_extract(ctx, &img, &o, out, 8));
    img.stride_bytes = 0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_STRIDE, ce_palette_extract(ctx, &img, &o, out, 8));
    img.stride_bytes = 2147483647;
    TEST_ASSERT_EQUAL_INT_MESSAGE(CE_ERR_STRIDE, ce_palette_extract(ctx, &img, &o, out, 8),
                                  "height*stride > INT_MAX debe rechazarse");
    img.stride_bytes = 16;
    img.fmt = CE_RGB8; /* 4*3 = 12 <= 16: válido con stride mayor que el mínimo */
    /* El buffer se rellena de nuevo como RGB8 (bpp 3): reinterpretar los bytes
     * RGBA como RGB8 daría 4 colores distintos, no 1. */
    fill_small(px, 4, 4, 16, 3);
    TEST_ASSERT_EQUAL_INT(1, ce_palette_extract(ctx, &img, &o, out, 8));
    memset(out, 0xAB, sizeof out);
    img.fmt = CE_RGBA8;
    fill_small(px, 4, 4, 16, 4);

    /* Opciones. */
    ce_palette_opts_default(&o); o.k_init = 0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_palette_extract(ctx, &img, &o, out, 8));
    ce_palette_opts_default(&o); o.k_init = CE_PALETTE_K_MAX + 1;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_palette_extract(ctx, &img, &o, out, 8));
    ce_palette_opts_default(&o); o.max_colors = 0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_palette_extract(ctx, &img, &o, out, 8));
    ce_palette_opts_default(&o); o.max_colors = CE_PALETTE_MAX_COLORS + 1;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_palette_extract(ctx, &img, &o, out, 8));
    ce_palette_opts_default(&o); o.max_iters = -1;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_palette_extract(ctx, &img, &o, out, 8));
    ce_palette_opts_default(&o); o.max_side = 0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_palette_extract(ctx, &img, &o, out, 8));
    ce_palette_opts_default(&o); o.max_side = CE_PALETTE_MAX_SIDE + 1;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_palette_extract(ctx, &img, &o, out, 8));
    ce_palette_opts_default(&o); o.center_sigma = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_palette_extract(ctx, &img, &o, out, 8));
    ce_palette_opts_default(&o); o.merge_de = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_palette_extract(ctx, &img, &o, out, 8));
    ce_palette_opts_default(&o); o.min_weight = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_palette_extract(ctx, &img, &o, out, 8));
    ce_palette_opts_default(&o); o.merge_light_de = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_palette_extract(ctx, &img, &o, out, 8));
    /* Ningún error escribió en la salida. */
    TEST_ASSERT_EQUAL_MEMORY(sentinel, out, sizeof out);

    /* Valores "absurdos" pero definidos: sigma negativa (uniforme), merge 0,
     * min_weight >= 1 (queda el más pesado), skin_rule 7. */
    ce_palette_opts_default(&o);
    o.center_sigma = -1.0; o.merge_de = 0.0; o.min_weight = 1.5; o.skin_rule = 7;
    TEST_ASSERT_EQUAL_INT(1, ce_palette_extract(ctx, &img, &o, out, 8));
    TEST_ASSERT_EQUAL_DOUBLE(1.0, out[0].weight);
    /* Opciones NULL = por defecto. */
    TEST_ASSERT_EQUAL_INT(1, ce_palette_extract(ctx, &img, NULL, out, 8));

    free(mem);
}

/* 5. Capa 3: errores de argumentos sin tocar las salidas; un swatch a cero
 *    (Lab 0, peso 0) es una entrada válida; ce_result_hash. */
static void test_match_arg_errors(void)
{
    const size_t size = ce_ctx_size();
    void *mem = alloc_ctx_mem(size);
    ce_ctx *ctx = ce_ctx_init(mem, size);
    ce_result res;
    ce_hit hits[CE_MATCH_MAX_HITS];
    ce_swatch sw[1];
    ce_match_opts mo;
    int ambiguous = 42;
    memset(&res, 0x77, sizeof res);
    memset(hits, 0x77, sizeof hits);
    memset(sw, 0, sizeof sw);
    ce_match_opts_default(&mo);
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(NULL, sw, 1, &mo, hits, 3, &ambiguous));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, 0, &mo, hits, 3, &ambiguous));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_match(ctx, sw, 1, &mo, hits, CE_MATCH_MAX_HITS + 1, &ambiguous));
    TEST_ASSERT_EQUAL_INT(42, ambiguous);
    TEST_ASSERT_EQUAL_UINT8(0x77, ((unsigned char *)hits)[0]);
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_analyze(ctx, NULL, NULL, NULL, &res));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_analyze(NULL, NULL, NULL, NULL, &res));
    TEST_ASSERT_EQUAL_UINT8(0x77, ((unsigned char *)&res)[0]);
    /* Entrada válida mínima: 3 hits ordenados, ambiguous 0|1. */
    TEST_ASSERT_EQUAL_INT(3, ce_match(ctx, sw, 1, &mo, hits, 3, &ambiguous));
    TEST_ASSERT_TRUE(ambiguous == 0 || ambiguous == 1);
    TEST_ASSERT_TRUE(hits[0].score <= hits[1].score && hits[1].score <= hits[2].score);
    /* ce_result_hash es determinista y sensible al contenido. */
    memset(&res, 0, sizeof res);
    res.n_swatches = 1;
    res.swatches[0].lab.L = 50.0;
    res.swatches[0].weight = 1.0;
    {
        const uint64_t h1 = ce_result_hash(&res);
        uint64_t h2;
        res.swatches[0].lab.L = 50.5;
        h2 = ce_result_hash(&res);
        TEST_ASSERT_NOT_EQUAL_UINT64(h1, h2);
        TEST_ASSERT_EQUAL_UINT64(h2, ce_result_hash(&res));
    }
    free(mem);
}

/* 6. ce_reduced_dims: factor entero y ceil. */
static void test_reduced_dims(void)
{
    int rw = 0, rh = 0;
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_reduced_dims(1024, 1024, 256, &rw, &rh));
    TEST_ASSERT_EQUAL_INT(256, rw);
    TEST_ASSERT_EQUAL_INT(256, rh);
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_reduced_dims(1000, 700, 256, &rw, &rh));
    TEST_ASSERT_EQUAL_INT(250, rw); /* f = ceil(1000/256) = 4 */
    TEST_ASSERT_EQUAL_INT(175, rh);
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_reduced_dims(257, 3, 256, &rw, &rh));
    TEST_ASSERT_EQUAL_INT(129, rw); /* f = 2, ceil(257/2) */
    TEST_ASSERT_EQUAL_INT(2, rh);
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_reduced_dims(200, 200, 256, &rw, &rh));
    TEST_ASSERT_EQUAL_INT(200, rw);
    TEST_ASSERT_EQUAL_INT(200, rh);
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_reduced_dims(16384, 16384, 1, &rw, &rh));
    TEST_ASSERT_EQUAL_INT(1, rw);
    TEST_ASSERT_EQUAL_INT(1, rh);
    TEST_ASSERT_EQUAL_INT(CE_ERR_DIMS, ce_reduced_dims(0, 10, 256, &rw, &rh));
    TEST_ASSERT_EQUAL_INT(CE_ERR_DIMS, ce_reduced_dims(10, 10, 0, &rw, &rh));
    TEST_ASSERT_EQUAL_INT(CE_ERR_DIMS, ce_reduced_dims(10, 10, 256, NULL, &rh));
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_ctx_size_budget);
    RUN_TEST(test_ctx_init_validation);
    RUN_TEST(test_opts_default);
    RUN_TEST(test_extract_errors);
    RUN_TEST(test_match_arg_errors);
    RUN_TEST(test_reduced_dims);
    return UNITY_END();
}
