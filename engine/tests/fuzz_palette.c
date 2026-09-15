/*
 * fuzz_palette.c — fuzz loop propio (Apple clang no trae libFuzzer) para las
 * entradas no confiables del motor (capa 2, máscaras y capas de depuración):
 *   (1) ce_palette_extract: dimensiones 0..300, stride aleatorio (a veces
 *       menor que el mínimo), formatos válidos e inválidos, máscaras,
 *       punteros nulos y opciones absurdas (k_init 0..64+, max_colors 0..16,
 *       sigma negativa, NaN, inf...);
 *   (2) ce_pnm_parse: cabeceras y cuerpos aleatorios, truncados o gigantes,
 *       y ficheros válidos mutados; los válidos pasan además por (1).
 *   (3) ce_mask_clothing_regions y ce_mask_cut_head: poses aleatorias (NaN,
 *       ±inf, fuera de imagen, confianzas absurdas, simetrías), opciones
 *       válidas e inválidas y dimensiones 0..512;
 *   (4) ce_skin_model_fit y ce_mask_exclude_skin: imágenes y máscaras de
 *       muestra aleatorias y modelos degenerados (covarianza singular o
 *       indefinida, n pequeño, NaN/inf, valores enormes o diminutos).
 * Tras cada extracción de (1) se leen además las capas de depuración
 * (ce_palette_debug_info, reduced/weight/label/cluster map con capacidades
 * aleatorias) y, a veces, ce_match_explain_combo contra ce_match.
 *
 * Uso: fuzz_palette [semilla] [segundos]   (por defecto 1 y 600).
 * PRNG xorshift64*. Cada buffer se reserva con malloc del tamaño exacto para
 * que ASan detecte cualquier lectura fuera de rango. Se compila con
 * -fsanitize=address,undefined vía CE_SANITIZE=ON (make fuzz) y también sin
 * sanitizers como humo de 2 s en ctest.
 *
 * Invariantes comprobadas en cada iteración:
 *   - errores exactamente donde el contrato los documenta (orden: ARG, CTX,
 *     imagen, OPTS), sin escribir en `out`;
 *   - con n >= 1: 1 <= n <= min(max_colors, cap); Σ weight = 1 +- 1e-9;
 *     pesos en (0, 1] y no crecientes; Lab finitos; rgb == Lab -> sRGB8;
 *   - determinismo: cada 8 casos se repite la llamada y se compara memcmp;
 *   - parser: éxito solo con dims en [1, 16384], maxval 255 y cuerpo dentro
 *     del buffer; error sin tocar la salida;
 *   - capas: etiquetas < n_swatches o NONE/DISCARDED, NONE <=> peso 0,
 *     buffers cortos -> CE_ERR_ARG sin escribir, CE_ERR_CTX tras una
 *     extracción fallida; explicación con el mismo score bit a bit;
 *   - máscaras: códigos de error documentados sin tocar la máscara; en éxito
 *     cada píxel queda igual o a 0 (regiones, piel) y el recuento coincide;
 *     CE_SKIN_GUARD sin tocar la máscara; determinismo cada 8 casos.
 * Salida: iteraciones de cada entrada e iteraciones/segundo; exit 1 si una
 * invariante falla (con la semilla y el número de caso para reproducir).
 */
/* clock_gettime/CLOCK_MONOTONIC son POSIX: con -std=c11 estricto (sin
 * extensiones) musl/Emscripten solo los declara si se pide explícitamente. */
#define _POSIX_C_SOURCE 200809L

#include "ce/ce.h"
#include "ce_pnm.h"

#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#pragma STDC FP_CONTRACT OFF

static uint64_t g_rng = 1;
static uint64_t g_case = 0;
static uint64_t g_seed = 1;

static uint64_t rnd64(void)
{
    uint64_t x = g_rng;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    g_rng = x;
    return x * 0x2545F4914F6CDD1DULL;
}

/* Entero uniforme en [0, n). */
static uint32_t rnd(uint32_t n)
{
    return (uint32_t)(rnd64() % n);
}

static double rnd_unit(void)
{
    return (double)(rnd64() >> 11) * (1.0 / 9007199254740992.0);
}

static void fail(const char *what)
{
    fprintf(stderr, "FUZZ FALLO: %s (semilla %" PRIu64 ", caso %" PRIu64 ")\n", what, g_seed, g_case);
    exit(1);
}

static double now_s(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1.0e9;
}

/* ------------------------------------------------------------------------
 * Entrada 1: ce_palette_extract
 * ---------------------------------------------------------------------- */

static int bpp_of(int fmt)
{
    return (fmt == CE_RGBA8 || fmt == CE_RGBX8) ? 4 : (fmt == CE_RGB8 ? 3 : 0);
}

/* Réplica de la validación documentada, para saber qué esperar. El orden es
 * el de ce.h: ARG (punteros/cap), CTX (contexto sin ce_ctx_init; `ctx_uninit`
 * lo indica porque el ctx es opaco), imagen (ARG/DIMS/FORMAT/STRIDE) y OPTS. */
static int expected_error(const ce_ctx *ctx, int ctx_uninit, const ce_image *img,
                          const ce_palette_opts *o, const ce_swatch *out, int cap)
{
    int bpp;
    if (ctx == NULL || img == NULL || out == NULL || cap < 1) return CE_ERR_ARG;
    if (ctx_uninit) return CE_ERR_CTX;
    if (img->pixels == NULL) return CE_ERR_ARG;
    if (img->width < 1 || img->height < 1 || img->width > CE_IMAGE_MAX_SIDE || img->height > CE_IMAGE_MAX_SIDE) return CE_ERR_DIMS;
    bpp = bpp_of((int)img->fmt);
    if (bpp == 0) return CE_ERR_FORMAT;
    if (img->stride_bytes < img->width * bpp) return CE_ERR_STRIDE;
    if ((long long)img->stride_bytes * img->height > 2147483647LL) return CE_ERR_STRIDE;
    if (o != NULL) {
        if (o->k_init < 1 || o->k_init > CE_PALETTE_K_MAX) return CE_ERR_OPTS;
        if (o->max_iters < 0 || o->max_iters > 1000) return CE_ERR_OPTS;
        if (o->max_colors < 1 || o->max_colors > CE_PALETTE_MAX_COLORS) return CE_ERR_OPTS;
        if (o->max_side < 1 || o->max_side > CE_PALETTE_MAX_SIDE) return CE_ERR_OPTS;
        if (isnan(o->center_sigma) || isnan(o->merge_de) || isnan(o->min_weight)) return CE_ERR_OPTS;
    }
    return CE_OK;
}

static double rnd_double_opt(double lo, double hi)
{
    switch (rnd(12)) {
    case 0: return NAN;
    case 1: return -1.0;
    case 2: return 0.0;
    case 3: return HUGE_VAL;
    case 4: return -HUGE_VAL;
    case 5: return 1e-300;
    case 6: return 1e300;
    default: return lo + (hi - lo) * rnd_unit();
    }
}

static void random_opts(ce_palette_opts *o)
{
    ce_palette_opts_default(o);
    if (rnd(4) == 0) {
        return; /* por defecto */
    }
    o->k_init = (int)rnd(66) - 1;               /* -1..64 */
    if (rnd(20) == 0) o->k_init = (int)rnd64();  /* absurdo */
    o->max_iters = (int)rnd(45) - 2;             /* -2..42 */
    if (rnd(20) == 0) o->max_iters = 100000;
    o->max_colors = (int)rnd(17);                /* 0..16 */
    o->max_side = (int)rnd(300) + 1;             /* 1..300 */
    if (rnd(10) == 0) o->max_side = 0;
    o->center_sigma = rnd_double_opt(-0.5, 2.0);
    o->merge_de = rnd_double_opt(-1.0, 40.0);
    o->min_weight = rnd_double_opt(-0.5, 1.5);
    o->skin_rule = (int)rnd(3) - 1;              /* -1, 0, 1 */
}

/* Rellena los canales RGB con distintos modos (ruido, bandas, degradado,
 * color plano) y basura en alpha/relleno. */
static void random_pixels(uint8_t *px, int w, int h, int stride, int bpp)
{
    const int mode = (int)rnd(4);
    uint8_t colors[6][3];
    int nc = 2 + (int)rnd(5), x, y, k;
    size_t i;
    const size_t total = (size_t)(h - 1) * (size_t)stride + (size_t)w * (size_t)bpp;
    for (i = 0; i < total; ++i) px[i] = (uint8_t)rnd64();
    for (k = 0; k < 6; ++k) {
        colors[k][0] = (uint8_t)rnd64();
        colors[k][1] = (uint8_t)rnd64();
        colors[k][2] = (uint8_t)rnd64();
    }
    if (mode == 0) return; /* ruido puro */
    for (y = 0; y < h; ++y) {
        for (x = 0; x < w; ++x) {
            uint8_t *p = px + (size_t)y * (size_t)stride + (size_t)x * (size_t)bpp;
            if (mode == 1) {
                const uint8_t *c = colors[(y * nc) / h];
                p[0] = c[0]; p[1] = c[1]; p[2] = c[2];
            } else if (mode == 2) {
                p[0] = (uint8_t)((x * 255) / (w > 1 ? w - 1 : 1));
                p[1] = (uint8_t)((y * 255) / (h > 1 ? h - 1 : 1));
                p[2] = (uint8_t)(128 + (int)rnd(8));
            } else {
                p[0] = colors[0][0]; p[1] = colors[0][1]; p[2] = colors[0][2];
            }
        }
    }
}

static void check_palette(const ce_swatch *sw, int n, int n_max, const unsigned char *sentinel, int cap_cells)
{
    double sum = 0.0;
    int i;
    if (n < 1 || n > n_max) fail("n fuera de [1, min(max_colors, cap)]");
    for (i = 0; i < n; ++i) {
        uint8_t r, g, b;
        if (!isfinite(sw[i].lab.L) || !isfinite(sw[i].lab.a) || !isfinite(sw[i].lab.b)) fail("Lab no finito");
        if (!(sw[i].weight > 0.0 && sw[i].weight <= 1.0)) fail("peso fuera de (0, 1]");
        if (i > 0 && sw[i - 1].weight < sw[i].weight) fail("pesos no ordenados");
        ce_lab_to_srgb8(sw[i].lab, &r, &g, &b);
        if (r != sw[i].rgb[0] || g != sw[i].rgb[1] || b != sw[i].rgb[2]) fail("rgb != Lab->sRGB8");
        sum += sw[i].weight;
    }
    if (fabs(sum - 1.0) > 1e-9) fail("suma de pesos != 1");
    /* Celdas más allá de n intactas. */
    for (i = n; i < cap_cells; ++i) {
        if (memcmp(&sw[i], sentinel, sizeof(ce_swatch)) != 0) fail("escritura mas alla de n");
    }
}

/* Capas de depuración tras una extracción correcta con `n` swatches. */
static void check_debug_layers(const ce_ctx *ctx, const ce_swatch *sw, int n)
{
    ce_palette_debug info;
    size_t np, cap, i;
    uint8_t *buf, *labels, *weights;
    int rc, c;
    if (ce_palette_debug_info(ctx, &info) != CE_OK) fail("debug_info tras extraccion valida");
    if (info.n_swatches != n) fail("debug n_swatches != n");
    if (info.n_clusters < 0 || info.n_clusters > CE_PALETTE_K_MAX) fail("debug n_clusters");
    if (!(info.zero_weight_fraction >= 0.0 && info.zero_weight_fraction <= 1.0)) fail("debug zero_weight_fraction");
    for (c = 0; c < info.n_clusters; ++c) {
        const ce_cluster_debug *cd = &info.clusters[c];
        if (cd->fate < CE_FATE_KEPT || cd->fate > CE_FATE_TRUNCATED) fail("debug fate");
        if ((cd->fate <= CE_FATE_MERGED) != (cd->final_index >= 0 && cd->final_index < n)) fail("debug final_index");
        if (cd->group_head < 0 || cd->group_head > c) fail("debug group_head");
        if (!(cd->weight > 0.0 && cd->weight <= 1.0)) fail("debug weight");
    }
    np = (size_t)info.reduced_width * (size_t)info.reduced_height;
    if (np < 1 || np > (size_t)CE_PALETTE_MAX_SIDE * CE_PALETTE_MAX_SIDE) fail("debug dims");
    cap = np * 3u + 1u;
    buf = (uint8_t *)malloc(cap);
    labels = (uint8_t *)malloc(np);
    weights = (uint8_t *)malloc(np);
    if (buf == NULL || labels == NULL || weights == NULL) fail("malloc");
    /* Capacidad aleatoria: corta -> CE_ERR_ARG sin escribir. */
    {
        const size_t short_cap = rnd((uint32_t)np);
        memset(buf, 0xA5, cap);
        rc = ce_debug_label_map(ctx, buf, short_cap);
        if (rc != CE_ERR_ARG) fail("label_map con cap corto");
        rc = ce_debug_reduced_rgb(ctx, buf, np * 3u - 1u);
        if (rc != CE_ERR_ARG) fail("reduced_rgb con cap corto");
        for (i = 0; i < cap; ++i) if (buf[i] != 0xA5) fail("escritura con cap corto");
    }
    if (ce_debug_reduced_rgb(ctx, buf, cap) != (int)(np * 3u)) fail("reduced_rgb");
    if (buf[np * 3u] != 0xA5) fail("reduced_rgb escribe de mas");
    if (ce_debug_weight_map(ctx, weights, np) != (int)np) fail("weight_map");
    if (ce_debug_label_map(ctx, labels, np) != (int)np) fail("label_map");
    if (ce_debug_cluster_map(ctx, buf, np) != (int)np) fail("cluster_map");
    for (i = 0; i < np; ++i) {
        const uint8_t l = labels[i];
        if (l != CE_LABEL_NONE && l != CE_LABEL_DISCARDED && l >= n) fail("etiqueta fuera de rango");
        if (l == CE_LABEL_NONE && buf[i] != CE_LABEL_NONE) fail("cluster_map != NONE con label NONE");
        if (l != CE_LABEL_NONE && buf[i] >= info.n_clusters) fail("cluster_map fuera de rango");
        if (l != CE_LABEL_NONE && info.clusters[buf[i]].final_index != (l == CE_LABEL_DISCARDED ? -1 : (int)l)) fail("label != final_index de su cluster");
        if (l == CE_LABEL_NONE && weights[i] != 0) fail("NONE con peso");
    }
    /* A veces: la explicación reproduce el score de ce_match. */
    if (g_case % 16 == 0) {
        ce_hit hits[3];
        ce_match_explain e;
        int k;
        if (ce_match(ctx, sw, n, NULL, hits, 3, NULL) != 3) fail("ce_match sobre la paleta extraida");
        for (k = 0; k < 3; ++k) {
            if (ce_match_explain_combo(ctx, sw, n, NULL, hits[k].combo_id, &e) != CE_OK) fail("explain");
            if (memcmp(&e.score, &hits[k].score, sizeof(double)) != 0) fail("explain score != ce_match");
        }
    }
    free(buf);
    free(labels);
    free(weights);
}

static void fuzz_extract_once(ce_ctx *ctx, ce_ctx *ctx_zero)
{
    ce_image img;
    ce_palette_opts o, *op = &o;
    ce_swatch out[16];
    unsigned char sentinel[sizeof(ce_swatch)];
    uint8_t *px = NULL, *mask = NULL;
    int w = (int)rnd(301), h = (int)rnd(301);
    int fmt_i = (int)rnd(3), bpp, stride, cap, rc, want, n_max;
    size_t px_len;
    ce_ctx *use_ctx = ctx;

    if (rnd(25) == 0) fmt_i = (int)rnd(5) - 1; /* -1..3: inválidos -1 y 3 */
    if (rnd(50) == 0) w = CE_IMAGE_MAX_SIDE + (int)rnd(3) - 1; /* borde superior */
    if (rnd(50) == 0) h = -(int)rnd(5);
    bpp = bpp_of(fmt_i);
    if (bpp == 0) bpp = 4;
    stride = w * bpp;
    if (rnd(5) == 0) stride -= (int)rnd(9);         /* a veces menor que el mínimo */
    else stride += (int)rnd(65);                     /* relleno */
    if (rnd(100) == 0) stride = 2147483647;          /* height*stride desborda */
    if (rnd(100) == 0) stride = -(int)rnd(100);

    memset(sentinel, 0xC3, sizeof sentinel);
    memset(out, 0xC3, sizeof out);
    memset(&img, 0, sizeof img);
    img.width = w;
    img.height = h;
    img.stride_bytes = stride;
    img.fmt = (ce_pixel_format)fmt_i;

    /* Buffer del tamaño exacto solo cuando la imagen es válida; si no, 1 byte
     * (el motor no debe tocarlo). */
    if (w >= 1 && h >= 1 && w <= CE_IMAGE_MAX_SIDE && h <= CE_IMAGE_MAX_SIDE
        && bpp_of(fmt_i) != 0 && stride >= w * bpp && (long long)stride * h <= 2147483647LL) {
        px_len = (size_t)(h - 1) * (size_t)stride + (size_t)w * (size_t)bpp;
        px = (uint8_t *)malloc(px_len);
        if (px == NULL) fail("malloc");
        random_pixels(px, w, h, stride, bpp);
    } else {
        px = (uint8_t *)malloc(1);
        if (px == NULL) fail("malloc");
        px[0] = 0;
    }
    img.pixels = px;
    if (rnd(40) == 0) img.pixels = NULL;

    if (w >= 1 && h >= 1 && w <= CE_IMAGE_MAX_SIDE && h <= CE_IMAGE_MAX_SIDE && rnd(2) == 0) {
        const size_t mlen = (size_t)w * (size_t)h;
        size_t i;
        const int mode = (int)rnd(4);
        mask = (uint8_t *)malloc(mlen);
        if (mask == NULL) fail("malloc");
        for (i = 0; i < mlen; ++i) {
            mask[i] = (mode == 0) ? (uint8_t)rnd64() : (mode == 1) ? 0 : (mode == 2) ? 255 : (uint8_t)((i % 2) ? 255 : 0);
        }
        img.mask = mask;
    }

    random_opts(&o);
    if (rnd(6) == 0) op = NULL;
    cap = (int)rnd(12) - 1; /* -1..10 */
    if (rnd(30) == 0) use_ctx = ctx_zero;
    if (rnd(60) == 0) use_ctx = NULL;

    want = expected_error(use_ctx, use_ctx == ctx_zero, &img, op, out, cap);
    rc = ce_palette_extract(use_ctx, rnd(80) == 0 ? NULL : &img, op, rnd(80) == 0 ? NULL : out, cap);
    if (rc < 0) {
        int i;
        if (use_ctx == ctx && (rc == CE_ERR_DIMS || rc == CE_ERR_FORMAT || rc == CE_ERR_STRIDE || rc == CE_ERR_OPTS)) {
            ce_palette_debug info;
            if (ce_palette_debug_info(use_ctx, &info) != CE_ERR_CTX) fail("capas validas tras una extraccion fallida");
        }
        if (want == CE_OK && rc != CE_ERR_ARG) fail("error inesperado en entrada valida");
        if (want != CE_OK && rc != want && rc != CE_ERR_ARG) fail("codigo de error distinto del documentado");
        for (i = 0; i < 16; ++i) {
            if (memcmp(&out[i], sentinel, sizeof(ce_swatch)) != 0) fail("error con escritura en out");
        }
    } else if (rc == 0) {
        fail("rc == 0 (debe ser >= 1 o negativo)");
    } else {
        ce_palette_opts eff;
        if (want != CE_OK) fail("exito con entrada invalida");
        if (op == NULL) ce_palette_opts_default(&eff); else eff = *op;
        n_max = eff.max_colors < cap ? eff.max_colors : cap;
        check_palette(out, rc, n_max, sentinel, 16);
        check_debug_layers(use_ctx, out, rc);
        if (g_case % 8 == 0) {
            ce_swatch again[16];
            int rc2;
            memset(again, 0xC3, sizeof again);
            rc2 = ce_palette_extract(use_ctx, &img, op, again, cap);
            if (rc2 != rc || memcmp(out, again, sizeof(ce_swatch) * (size_t)rc) != 0) fail("no determinista");
        }
    }
    free(px);
    free(mask);
}

/* ------------------------------------------------------------------------
 * Entrada 2: ce_pnm_parse
 * ---------------------------------------------------------------------- */

static const char *rnd_ws(void)
{
    static const char *const ws[] = {" ", "\n", "\r\n", "\t", "  \n", "\n#c\n", " #x y z\n", "\f", "\v"};
    return ws[rnd(sizeof ws / sizeof ws[0])];
}

static const char *rnd_number(char *buf, size_t cap)
{
    switch (rnd(12)) {
    case 0: snprintf(buf, cap, "0"); break;
    case 1: snprintf(buf, cap, "-1"); break;
    case 2: snprintf(buf, cap, "16385"); break;
    case 3: snprintf(buf, cap, "99999999999999999999"); break;
    case 4: snprintf(buf, cap, "abc"); break;
    case 5: snprintf(buf, cap, ""); break;
    case 6: snprintf(buf, cap, "16384"); break;
    default: snprintf(buf, cap, "%u", 1u + rnd(40)); break;
    }
    return buf;
}

static void check_pnm_result(const uint8_t *buf, size_t len, const ce_pnm_image *im, int rc,
                             const ce_pnm_image *before)
{
    if (rc == CE_PNM_OK) {
        if (im->width < 1 || im->height < 1 || im->width > CE_PNM_MAX_SIDE || im->height > CE_PNM_MAX_SIDE) fail("pnm dims");
        if ((im->type != 5 && im->type != 6) || im->channels != (im->type == 6 ? 3 : 1)) fail("pnm tipo");
        if (im->data_len != (size_t)im->width * (size_t)im->height * (size_t)im->channels) fail("pnm data_len");
        if (im->data < buf || im->data_len > len || (size_t)(im->data - buf) > len - im->data_len) fail("pnm cuerpo fuera del buffer");
    } else {
        if (rc < CE_PNM_ERR_TRUNCATED || rc > CE_PNM_ERR_ARG) fail("pnm codigo desconocido");
        if (memcmp(im, before, sizeof *im) != 0) fail("pnm error con escritura en out");
    }
}

static void fuzz_pnm_once(ce_ctx *ctx)
{
    uint8_t *buf = NULL;
    size_t len = 0, cap = 0;
    char header[256], nw[32], nh[32], nm[32];
    ce_pnm_image im, before;
    int rc, mode = (int)rnd(5);

    if (mode == 0) {
        len = rnd(96);
        buf = (uint8_t *)malloc(len ? len : 1);
        if (buf == NULL) fail("malloc");
        for (cap = 0; cap < len; ++cap) buf[cap] = (uint8_t)rnd64();
        if (len >= 2 && rnd(2) == 0) { buf[0] = 'P'; buf[1] = (rnd(2) ? '6' : '5'); }
    } else {
        const int valid = (mode >= 3);
        const char *magic = rnd(2) ? "P6" : "P5";
        const int ch = (magic[1] == '6') ? 3 : 1;
        long w, h;
        size_t need, body;
        if (valid) {
            snprintf(nw, sizeof nw, "%u", 1u + rnd(48));
            snprintf(nh, sizeof nh, "%u", 1u + rnd(48));
            snprintf(nm, sizeof nm, "255");
        } else {
            rnd_number(nw, sizeof nw);
            rnd_number(nh, sizeof nh);
            if (rnd(3) == 0) rnd_number(nm, sizeof nm); else snprintf(nm, sizeof nm, "255");
        }
        snprintf(header, sizeof header, "%s%s%s%s%s%s%s%s", magic, rnd_ws(), nw, rnd_ws(), nh, rnd_ws(), nm,
                 (valid || rnd(4)) ? "\n" : "");
        w = strtol(nw, NULL, 10);
        h = strtol(nh, NULL, 10);
        need = (w > 0 && h > 0 && w <= 16384 && h <= 16384) ? (size_t)w * (size_t)h * (size_t)ch : 0;
        body = need;
        if (!valid || rnd(4) == 0) {
            /* truncado, exacto o con sobrantes */
            switch (rnd(3)) {
            case 0: body = need > 0 ? rnd((uint32_t)need) : 0; break;
            case 1: body = need + rnd(16); break;
            default: break;
            }
        }
        len = strlen(header) + body;
        buf = (uint8_t *)malloc(len ? len : 1);
        if (buf == NULL) fail("malloc");
        memcpy(buf, header, strlen(header));
        for (cap = 0; cap < body; ++cap) buf[strlen(header) + cap] = (uint8_t)rnd64();
        if (mode == 4) {
            /* mutación de un fichero válido */
            int k, nmut = 1 + (int)rnd(4);
            for (k = 0; k < nmut && len > 0; ++k) buf[rnd((uint32_t)len)] = (uint8_t)rnd64();
            if (rnd(3) == 0 && len > 0) len -= rnd((uint32_t)len);
        }
    }

    memset(&im, 0x5A, sizeof im);
    before = im;
    rc = ce_pnm_parse(buf, len, &im);
    check_pnm_result(buf, len, &im, rc, &before);
    if (rc == CE_PNM_OK && im.type == 6) {
        /* Integración: la imagen parseada pasa por el motor (como el CLI). */
        ce_image img;
        ce_swatch out[8];
        ce_palette_opts o;
        unsigned char sentinel[sizeof(ce_swatch)];
        int n;
        memset(sentinel, 0xC3, sizeof sentinel);
        memset(out, 0xC3, sizeof out);
        img.pixels = im.data;
        img.width = im.width;
        img.height = im.height;
        img.stride_bytes = im.width * 3;
        img.fmt = CE_RGB8;
        img.mask = NULL;
        random_opts(&o);
        n = ce_palette_extract(ctx, &img, &o, out, 8);
        if (n >= 1) {
            check_palette(out, n, o.max_colors < 8 ? o.max_colors : 8, sentinel, 8);
        } else if (n != CE_ERR_OPTS) {
            fail("imagen PNM valida rechazada por el motor");
        }
    }
    free(buf);
}

/* ------------------------------------------------------------------------
 * Entrada 3: regiones de ropa y recorte de cabeza
 * ---------------------------------------------------------------------- */

static double rnd_coord(int side)
{
    switch (rnd(16)) {
    case 0: return NAN;
    case 1: return HUGE_VAL;
    case 2: return -HUGE_VAL;
    case 3: return 1e300;
    case 4: return -1e7;
    case 5: return (double)side + 1000.0 * rnd_unit();
    case 6: return -50.0 * rnd_unit();
    case 7: return CE_POSE_COORD_MAX * (rnd(2) ? 1.0 : -1.0);
    default: return ((double)side + 40.0) * rnd_unit() - 20.0;
    }
}

static double rnd_conf(void)
{
    switch (rnd(10)) {
    case 0: return NAN;
    case 1: return 0.0;
    case 2: return -1.0;
    case 3: return 1e9;
    case 4: return HUGE_VAL;
    case 5: return 0.29999999999999999;
    default: return rnd_unit();
    }
}

static void random_region_opts(ce_region_opts *o)
{
    ce_region_opts_default(o);
    if (rnd(3) == 0) return;
    o->min_confidence = rnd(8) == 0 ? rnd_double_opt(-1.0, 2.0) : rnd_unit();
    o->torso_margin = rnd(8) == 0 ? rnd_double_opt(-1.0, 2.0) : rnd_unit();
    o->limb_width = rnd(8) == 0 ? rnd_double_opt(-1.0, 3.0) : 2.0 * rnd_unit();
    o->include_upper_arms = rnd(10) == 0 ? (int)rnd(5) - 2 : (int)rnd(2);
    o->include_forearms = rnd(10) == 0 ? (int)rnd(5) - 2 : (int)rnd(2);
    o->include_legs = rnd(10) == 0 ? (int)rnd(5) - 2 : (int)rnd(2);
    o->include_lower_legs = rnd(10) == 0 ? (int)rnd(5) - 2 : (int)rnd(2);
}

static void fuzz_regions_once(void)
{
    ce_pose pose;
    ce_region_opts o;
    int w = (int)rnd(513), h = (int)rnd(513), j, rc;
    const int valid_dims = (w >= 1 && h >= 1);
    size_t n = valid_dims ? (size_t)w * (size_t)h : 1u, i;
    uint8_t *m = (uint8_t *)malloc(n), *orig = (uint8_t *)malloc(n);
    const int mode = (int)rnd(3);

    if (m == NULL || orig == NULL) fail("malloc");
    for (i = 0; i < n; ++i) {
        orig[i] = (mode == 0) ? (uint8_t)rnd64() : (mode == 1) ? 255 : (uint8_t)(rnd(4) ? 255 : 0);
    }
    memcpy(m, orig, n);
    /* Pose plausible escalada a la imagen con perturbaciones. */
    for (j = 0; j < CE_JOINT_COUNT; ++j) {
        pose.k[j].x = ((double)w + 1.0) * rnd_unit();
        pose.k[j].y = ((double)h + 1.0) * rnd_unit();
        pose.k[j].confidence = 0.5 + 0.5 * rnd_unit();
        if (rnd(6) == 0) pose.k[j].x = rnd_coord(w);
        if (rnd(6) == 0) pose.k[j].y = rnd_coord(h);
        if (rnd(5) == 0) pose.k[j].confidence = rnd_conf();
    }
    if (rnd(4) == 0) {
        /* Simetría exacta: una cadera o un hombro reflejado por la raíz / cuello. */
        pose.k[CE_JOINT_RHIP].confidence = 0.0;
        pose.k[CE_JOINT_LSHOULDER].confidence = rnd(2) ? 0.0 : pose.k[CE_JOINT_LSHOULDER].confidence;
    }
    random_region_opts(&o);

    rc = ce_mask_clothing_regions(rnd(100) == 0 ? NULL : &pose, rnd(100) == 0 ? NULL : &o, m, w, h);
    if (rc < 0) {
        if (rc != CE_ERR_ARG && rc != CE_ERR_POSE) fail("regiones: codigo de error no documentado");
        if (!valid_dims && rc != CE_ERR_ARG) fail("regiones: dims invalidas sin CE_ERR_ARG");
        if (memcmp(m, orig, n) != 0) fail("regiones: error con la mascara modificada");
    } else {
        int count = 0;
        if (!valid_dims) fail("regiones: exito con dims invalidas");
        for (i = 0; i < n; ++i) {
            if (m[i] != 0 && m[i] != orig[i]) fail("regiones: pixel distinto de min(mascara, region)");
            count += m[i] != 0;
        }
        if (count != rc) fail("regiones: recuento");
        if (g_case % 8 == 0) {
            uint8_t *again = (uint8_t *)malloc(n);
            if (again == NULL) fail("malloc");
            memcpy(again, orig, n);
            if (ce_mask_clothing_regions(&pose, &o, again, w, h) != rc || memcmp(again, m, n) != 0) fail("regiones no deterministas");
            free(again);
        }
    }
    /* Recorte de cabeza sobre la misma máscara. */
    {
        const double fr = rnd(6) == 0 ? rnd_double_opt(-1.0, 1.0) : 0.5 * rnd_unit();
        memcpy(orig, m, n);
        rc = ce_mask_cut_head(rnd(100) == 0 ? NULL : m, w, h, fr);
        if (rc < 0) {
            if (rc != CE_ERR_ARG) fail("cut_head: codigo no documentado");
            if (memcmp(m, orig, n) != 0) fail("cut_head: error con la mascara modificada");
        } else {
            int count = 0;
            if (!valid_dims) fail("cut_head: exito con dims invalidas");
            for (i = 0; i < n; ++i) {
                if (m[i] != 0 && m[i] != orig[i]) fail("cut_head: pixel cambiado");
                count += m[i] != 0;
            }
            if (count != rc) fail("cut_head: recuento");
        }
    }
    free(m);
    free(orig);
}

/* ------------------------------------------------------------------------
 * Entrada 4: piel adaptativa con modelos degenerados
 * ---------------------------------------------------------------------- */

static double rnd_model_value(double typical)
{
    switch (rnd(14)) {
    case 0: return NAN;
    case 1: return HUGE_VAL;
    case 2: return -HUGE_VAL;
    case 3: return 1e300;
    case 4: return -1e300;
    case 5: return 1e-300;
    case 6: return 0.0;
    default: return typical * (2.0 * rnd_unit() - 1.0);
    }
}

static void fuzz_skin_once(ce_ctx *ctx)
{
    ce_image img;
    ce_skin_model model;
    ce_skin_opts so;
    int w = (int)rnd(129), h = (int)rnd(129), fmt_i = (int)rnd(3), bpp, stride, rc, k;
    size_t px_len, n, i;
    uint8_t *px, *sample, *m, *orig;
    int valid_img;

    (void)ctx;
    if (rnd(30) == 0) fmt_i = 5;
    bpp = bpp_of(fmt_i) ? bpp_of(fmt_i) : 4;
    stride = w * bpp + (rnd(4) == 0 ? (int)rnd(9) - 4 : 0);
    valid_img = w >= 1 && h >= 1 && bpp_of(fmt_i) != 0 && stride >= w * bpp;
    px_len = valid_img ? (size_t)(h - 1) * (size_t)stride + (size_t)w * (size_t)bpp : 1u;
    n = (w >= 1 && h >= 1) ? (size_t)w * (size_t)h : 1u;
    px = (uint8_t *)malloc(px_len);
    sample = (uint8_t *)malloc(n);
    m = (uint8_t *)malloc(n);
    orig = (uint8_t *)malloc(n);
    if (px == NULL || sample == NULL || m == NULL || orig == NULL) fail("malloc");
    if (valid_img) {
        random_pixels(px, w, h, stride, bpp);
    } else {
        px[0] = 0;
    }
    {
        const int smode = (int)rnd(4);
        for (i = 0; i < n; ++i) {
            sample[i] = smode == 0 ? (uint8_t)rnd64() : smode == 1 ? 255 : smode == 2 ? (uint8_t)(rnd(64) == 0 ? 200 : 0) : 127;
            orig[i] = rnd(3) ? 255 : (uint8_t)rnd64();
        }
    }
    memcpy(m, orig, n);
    img.pixels = px;
    img.width = w;
    img.height = h;
    img.stride_bytes = stride;
    img.fmt = (ce_pixel_format)fmt_i;
    img.mask = NULL;

    memset(&model, 0, sizeof model);
    rc = ce_skin_model_fit(&img, sample, &model);
    if (rc != CE_OK && rc != CE_ERR_ARG && rc != CE_ERR_DIMS && rc != CE_ERR_FORMAT && rc != CE_ERR_STRIDE
        && rc != CE_ERR_SKIN_SAMPLES) {
        fail("skin_fit: codigo no documentado");
    }
    if (rc == CE_OK) {
        if (model.n < CE_SKIN_MIN_SAMPLES) fail("skin_fit: n < minimo");
        for (k = 0; k < 9; ++k) {
            if (!isfinite(model.cov[k]) || !isfinite(model.inv_cov[k])) fail("skin_fit: no finito");
        }
        if (!(model.cov[0] >= CE_SKIN_COV_EPSILON)) fail("skin_fit: sin regularizar");
    }
    if (rc != CE_OK || rnd(3) == 0) {
        /* Modelo degenerado o arbitrario. */
        const int kind = (int)rnd(6);
        model.mean.L = rnd(8) ? 100.0 * rnd_unit() : rnd_model_value(100.0);
        model.mean.a = rnd(8) ? 80.0 * (2.0 * rnd_unit() - 1.0) : rnd_model_value(80.0);
        model.mean.b = rnd(8) ? 80.0 * (2.0 * rnd_unit() - 1.0) : rnd_model_value(80.0);
        model.n = (int)rnd(120) - 5;
        for (k = 0; k < 9; ++k) model.inv_cov[k] = 0.0;
        if (kind == 0) {
            const double v[3] = {rnd_unit(), rnd_unit(), rnd_unit()}; /* rango 1: singular */
            for (k = 0; k < 9; ++k) model.inv_cov[k] = v[k / 3] * v[k % 3];
        } else if (kind == 1) {
            for (k = 0; k < 9; ++k) model.inv_cov[k] = rnd_model_value(1.0);
        } else if (kind == 2) {
            model.inv_cov[0] = model.inv_cov[4] = model.inv_cov[8] = rnd(2) ? 1e300 : 1e-300;
        } else if (kind == 3) {
            model.inv_cov[0] = model.inv_cov[4] = model.inv_cov[8] = -1.0;
        } else {
            model.inv_cov[0] = 0.1 + rnd_unit();
            model.inv_cov[4] = 0.1 + rnd_unit();
            model.inv_cov[8] = 0.1 + rnd_unit();
            model.inv_cov[1] = model.inv_cov[3] = 0.05 * rnd_unit();
        }
    }
    ce_skin_opts_default(&so);
    if (rnd(3) == 0) {
        so.max_mahalanobis = rnd(6) == 0 ? rnd_double_opt(-1.0, 1e3) : 10.0 * rnd_unit();
        so.max_excluded_fraction = rnd(6) == 0 ? rnd_double_opt(-1.0, 2.0) : rnd_unit();
    }
    rc = ce_mask_exclude_skin(rnd(100) == 0 ? NULL : &img, &model, &so, rnd(100) == 0 ? NULL : m);
    if (rc < 0 || rc == CE_SKIN_GUARD) {
        if (rc < 0 && rc != CE_ERR_ARG && rc != CE_ERR_DIMS && rc != CE_ERR_FORMAT && rc != CE_ERR_STRIDE
            && rc != CE_ERR_SKIN_SAMPLES) {
            fail("exclude_skin: codigo no documentado");
        }
        if (memcmp(m, orig, n) != 0) fail("exclude_skin: error/guardia con la mascara modificada");
    } else if (rc == CE_OK) {
        if (!valid_img) fail("exclude_skin: exito con imagen invalida");
        for (i = 0; i < n; ++i) {
            if (m[i] != 0 && m[i] != orig[i]) fail("exclude_skin: pixel cambiado a un valor distinto de 0");
        }
        if (g_case % 8 == 0) {
            uint8_t *again = (uint8_t *)malloc(n);
            if (again == NULL) fail("malloc");
            memcpy(again, orig, n);
            if (ce_mask_exclude_skin(&img, &model, &so, again) != CE_OK || memcmp(again, m, n) != 0) fail("exclude_skin no determinista");
            free(again);
        }
    } else {
        fail("exclude_skin: codigo positivo no documentado");
    }
    free(px);
    free(sample);
    free(m);
    free(orig);
}

/* ------------------------------------------------------------------------
 * main
 * ---------------------------------------------------------------------- */

int main(int argc, char **argv)
{
    double seconds = 600.0, t0, elapsed, last_report;
    uint64_t it_extract = 0, it_pnm = 0, it_regions = 0, it_skin = 0;
    void *mem, *mem_zero;
    ce_ctx *ctx, *ctx_zero;

    if (argc > 1) g_seed = strtoull(argv[1], NULL, 10);
    if (argc > 2) seconds = strtod(argv[2], NULL);
    if (g_seed == 0) g_seed = 1;
    g_rng = g_seed * 0x9E3779B97F4A7C15ULL;
    if (g_rng == 0) g_rng = 1;

    mem = aligned_alloc(16, ce_ctx_size());
    mem_zero = aligned_alloc(16, ce_ctx_size());
    if (mem == NULL || mem_zero == NULL) fail("aligned_alloc del contexto");
    ctx = ce_ctx_init(mem, ce_ctx_size());
    if (ctx == NULL) fail("ce_ctx_init");
    memset(mem_zero, 0, ce_ctx_size());
    ctx_zero = (ce_ctx *)mem_zero; /* no inicializado: debe dar CE_ERR_CTX */

    printf("fuzz_palette: semilla %" PRIu64 ", %.0f s, ctx %zu bytes\n", g_seed, seconds, ce_ctx_size());
    fflush(stdout);
    t0 = now_s();
    last_report = t0;
    for (;;) {
        double now;
        ++g_case;
        fuzz_extract_once(ctx, ctx_zero);
        ++it_extract;
        ++g_case;
        fuzz_pnm_once(ctx);
        ++it_pnm;
        ++g_case;
        fuzz_regions_once();
        ++it_regions;
        ++g_case;
        fuzz_skin_once(ctx);
        ++it_skin;
        if ((g_case & 63) == 0) {
            now = now_s();
            if (now - t0 >= seconds) break;
            if (now - last_report >= 60.0) {
                printf("  %.0f s: extract %" PRIu64 " it, pnm %" PRIu64 " it, regions %" PRIu64 " it, skin %" PRIu64 " it\n",
                       now - t0, it_extract, it_pnm, it_regions, it_skin);
                fflush(stdout);
                last_report = now;
            }
        }
    }
    elapsed = now_s() - t0;
    printf("fuzz_palette OK: %.1f s, extract %" PRIu64 " it (%.0f it/s), pnm %" PRIu64 " it (%.0f it/s), "
           "regions %" PRIu64 " it, skin %" PRIu64 " it, 0 fallos\n",
           elapsed, it_extract, (double)it_extract / elapsed, it_pnm, (double)it_pnm / elapsed, it_regions, it_skin);
    free(mem);
    free(mem_zero);
    return 0;
}
