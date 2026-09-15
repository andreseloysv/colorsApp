/*
 * fuzz_palette.c — fuzz loop propio (Apple clang no trae libFuzzer) para las
 * dos entradas no confiables de la capa 2:
 *   (1) ce_palette_extract: dimensiones 0..300, stride aleatorio (a veces
 *       menor que el mínimo), formatos válidos e inválidos, máscaras,
 *       punteros nulos y opciones absurdas (k_init 0..64+, max_colors 0..16,
 *       sigma negativa, NaN, inf...);
 *   (2) ce_pnm_parse: cabeceras y cuerpos aleatorios, truncados o gigantes,
 *       y ficheros válidos mutados; los válidos pasan además por (1).
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
 *     del buffer; error sin tocar la salida.
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
 * main
 * ---------------------------------------------------------------------- */

int main(int argc, char **argv)
{
    double seconds = 600.0, t0, elapsed, last_report;
    uint64_t it_extract = 0, it_pnm = 0;
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
        if ((g_case & 63) == 0) {
            now = now_s();
            if (now - t0 >= seconds) break;
            if (now - last_report >= 60.0) {
                printf("  %.0f s: extract %" PRIu64 " it, pnm %" PRIu64 " it\n", now - t0, it_extract, it_pnm);
                fflush(stdout);
                last_report = now;
            }
        }
    }
    elapsed = now_s() - t0;
    printf("fuzz_palette OK: %.1f s, extract %" PRIu64 " it (%.0f it/s), pnm %" PRIu64 " it (%.0f it/s), 0 fallos\n",
           elapsed, it_extract, (double)it_extract / elapsed, it_pnm, (double)it_pnm / elapsed);
    free(mem);
    free(mem_zero);
    return 0;
}
