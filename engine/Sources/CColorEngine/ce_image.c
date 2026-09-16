/*
 * ce_image.c — validación de la imagen de entrada, box-downscale entero y
 * pesos por píxel (gaussiana al centro, máscara, regla de piel).
 *
 * Reglas: C11, sin I/O, sin malloc, todo en double, sin contracción FMA. La
 * única función trascendente es la exponencial de la gaussiana, tomada de
 * ce_libm.c (ce_exp, mismos bits en nativo y WASM); el resto son enteros y
 * +, ×, ÷.
 * Nunca se lee fuera de [pixels, pixels + height*stride): el stride y las
 * dimensiones se validan antes y las lecturas usan siempre y*stride + x*bpp
 * con x < width, y < height.
 */
#include "ce_internal.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>

#pragma STDC FP_CONTRACT OFF

/* INT_MAX sin <limits.h> (freestanding igualmente, pero así queda explícito). */
#define CE_INT_MAX_LL 2147483647LL

int ce_image_bpp(ce_pixel_format fmt)
{
    switch (fmt) {
    case CE_RGBA8:
    case CE_RGBX8:
        return 4;
    case CE_RGB8:
        return 3;
    default:
        return 0;
    }
}

int ce_image_validate(const ce_image *img)
{
    int bpp;
    if (img == NULL || img->pixels == NULL) {
        return CE_ERR_ARG;
    }
    if (img->width < 1 || img->height < 1
        || img->width > CE_IMAGE_MAX_SIDE || img->height > CE_IMAGE_MAX_SIDE) {
        return CE_ERR_DIMS;
    }
    bpp = ce_image_bpp(img->fmt);
    if (bpp == 0) {
        return CE_ERR_FORMAT;
    }
    /* width * bpp <= 65536: no desborda int. */
    if (img->stride_bytes < img->width * bpp) {
        return CE_ERR_STRIDE;
    }
    /* height * stride <= INT_MAX: los offsets caben en int y en size_t de 32
     * bits (WASM). */
    if ((long long)img->stride_bytes * (long long)img->height > CE_INT_MAX_LL) {
        return CE_ERR_STRIDE;
    }
    return CE_OK;
}

int ce_reduced_dims(int width, int height, int max_side, int *rw, int *rh)
{
    int m, f;
    if (width < 1 || height < 1 || max_side < 1 || rw == NULL || rh == NULL) {
        return CE_ERR_DIMS;
    }
    m = width > height ? width : height;
    f = (m + max_side - 1) / max_side; /* ceil(m / max_side) >= 1 */
    *rw = (width + f - 1) / f;
    *rh = (height + f - 1) / f;
    return CE_OK;
}

/* Media entera con redondeo al más cercano (mitades hacia arriba):
 * (sum + n/2) / n. Para n impar la mitad exacta no existe; para n par
 * sum == k*n + n/2 sube. */
static uint8_t ce_round_div(uint64_t sum, uint64_t n)
{
    return (uint8_t)((sum + n / 2u) / n);
}

void ce_image_reduce(ce_ctx *ctx, const ce_image *img, int max_side)
{
    const int bpp = ce_image_bpp(img->fmt);
    const int w = img->width;
    const int h = img->height;
    const size_t stride = (size_t)img->stride_bytes;
    int rw = 0, rh = 0, f, ry, rx;

    if (max_side > CE_CTX_MAX_SIDE) {
        max_side = CE_CTX_MAX_SIDE;
    }
    (void)ce_reduced_dims(w, h, max_side, &rw, &rh);
    f = ((w > h ? w : h) + max_side - 1) / max_side;
    ctx->reduced_w = rw;
    ctx->reduced_h = rh;

    for (ry = 0; ry < rh; ++ry) {
        const int y0 = ry * f;
        const int y1 = (y0 + f < h) ? y0 + f : h;
        for (rx = 0; rx < rw; ++rx) {
            const int x0 = rx * f;
            const int x1 = (x0 + f < w) ? x0 + f : w;
            const size_t o = (size_t)ry * (size_t)rw + (size_t)rx;
            uint64_t sr = 0, sg = 0, sb = 0, sm = 0;
            uint64_t n = (uint64_t)(y1 - y0) * (uint64_t)(x1 - x0);
            int x, y;
            for (y = y0; y < y1; ++y) {
                const uint8_t *row = img->pixels + (size_t)y * stride;
                for (x = x0; x < x1; ++x) {
                    const uint8_t *p = row + (size_t)x * (size_t)bpp;
                    sr += p[0];
                    sg += p[1];
                    sb += p[2];
                }
                if (img->mask != NULL) {
                    const uint8_t *mrow = img->mask + (size_t)y * (size_t)w;
                    for (x = x0; x < x1; ++x) {
                        sm += mrow[x];
                    }
                }
            }
            ctx->reduced[o * 3 + 0] = ce_round_div(sr, n);
            ctx->reduced[o * 3 + 1] = ce_round_div(sg, n);
            ctx->reduced[o * 3 + 2] = ce_round_div(sb, n);
            /* Sin máscara: 1.0 exacto (sumas enteras exactas en el histograma).
             * Con máscara: factor entero 0..255 (la escala global se cancela al
             * normalizar los pesos de la paleta). */
            ctx->weights[o] = (img->mask != NULL) ? (double)ce_round_div(sm, n) : 1.0;
        }
    }
}

void ce_image_reduce_regions(ce_ctx *ctx, const ce_image *img, const uint8_t *region_map, int n_regions,
                             int max_side)
{
    const int bpp = ce_image_bpp(img->fmt);
    const int w = img->width;
    const int h = img->height;
    const size_t stride = (size_t)img->stride_bytes;
    int rw = 0, rh = 0, f, ry, rx;

    if (region_map == NULL) {
        size_t i, n;
        ce_image_reduce(ctx, img, max_side);
        n = (size_t)ctx->reduced_w * (size_t)ctx->reduced_h;
        for (i = 0; i < n; ++i) {
            ctx->region_label[i] = 1;
        }
        return;
    }
    if (max_side > CE_CTX_MAX_SIDE) {
        max_side = CE_CTX_MAX_SIDE;
    }
    if (n_regions < 1) {
        n_regions = 1;
    }
    if (n_regions > CE_GARMENT_MAX_REGIONS) {
        n_regions = CE_GARMENT_MAX_REGIONS;
    }
    (void)ce_reduced_dims(w, h, max_side, &rw, &rh);
    f = ((w > h ? w : h) + max_side - 1) / max_side;
    ctx->reduced_w = rw;
    ctx->reduced_h = rh;

    for (ry = 0; ry < rh; ++ry) {
        const int y0 = ry * f;
        const int y1 = (y0 + f < h) ? y0 + f : h;
        for (rx = 0; rx < rw; ++rx) {
            const int x0 = rx * f;
            const int x1 = (x0 + f < w) ? x0 + f : w;
            const size_t o = (size_t)ry * (size_t)rw + (size_t)rx;
            uint64_t sr = 0, sg = 0, sb = 0, sm = 0;
            uint64_t per_label[CE_GARMENT_MAX_REGIONS + 1] = {0};
            uint64_t best_sum = 0;
            const uint64_t n = (uint64_t)(y1 - y0) * (uint64_t)(x1 - x0);
            int x, y, k, best = 0;
            for (y = y0; y < y1; ++y) {
                const uint8_t *row = img->pixels + (size_t)y * stride;
                const uint8_t *lrow = region_map + (size_t)y * (size_t)w;
                const uint8_t *mrow = (img->mask != NULL) ? img->mask + (size_t)y * (size_t)w : NULL;
                for (x = x0; x < x1; ++x) {
                    const uint8_t *p = row + (size_t)x * (size_t)bpp;
                    const int label = lrow[x];
                    sr += p[0];
                    sg += p[1];
                    sb += p[2];
                    if (label >= 1 && label <= n_regions) {
                        const uint64_t em = (mrow != NULL) ? (uint64_t)mrow[x] : 255u;
                        sm += em;
                        per_label[label] += em;
                    }
                }
            }
            for (k = 1; k <= n_regions; ++k) {
                if (per_label[k] > best_sum) { /* estricto: en empate gana la menor */
                    best_sum = per_label[k];
                    best = k;
                }
            }
            ctx->reduced[o * 3 + 0] = ce_round_div(sr, n);
            ctx->reduced[o * 3 + 1] = ce_round_div(sg, n);
            ctx->reduced[o * 3 + 2] = ce_round_div(sb, n);
            ctx->weights[o] = (double)ce_round_div(sm, n);
            ctx->region_label[o] = (uint8_t)best;
        }
    }
}

void ce_image_apply_center_weight(ce_ctx *ctx, double sigma_px)
{
    const int rw = ctx->reduced_w;
    const int rh = ctx->reduced_h;
    const double cx = (double)(rw - 1) / 2.0;
    const double cy = (double)(rh - 1) / 2.0;
    double denom;
    int x, y;
    if (!(sigma_px > 0.0) || !isfinite(sigma_px)) {
        return; /* uniforme */
    }
    denom = 2.0 * sigma_px * sigma_px;
    for (y = 0; y < rh; ++y) {
        const double dy = (double)y - cy;
        for (x = 0; x < rw; ++x) {
            const double dx = (double)x - cx;
            const double d2 = dx * dx + dy * dy;
            ctx->weights[(size_t)y * (size_t)rw + (size_t)x] *= ce_exp(-(d2 / denom));
        }
    }
}

/* Chai y Ngan (1999): piel si 77 <= Cb <= 127 y 133 <= Cr <= 173, con la
 * conversión YCbCr de JFIF (rango completo):
 *   Cb = 128 - 0.168736 R - 0.331264 G + 0.5 B
 *   Cr = 128 + 0.5 R - 0.418688 G - 0.081312 B
 * Se compara en double sin redondear (solo +, ×: determinista). */
static int ce_is_skin(uint8_t r8, uint8_t g8, uint8_t b8)
{
    const double r = (double)r8, g = (double)g8, b = (double)b8;
    const double cb = 128.0 - 0.168736 * r - 0.331264 * g + 0.5 * b;
    const double cr = 128.0 + 0.5 * r - 0.418688 * g - 0.081312 * b;
    return cb >= 77.0 && cb <= 127.0 && cr >= 133.0 && cr <= 173.0;
}

void ce_image_apply_skin_rule(ce_ctx *ctx)
{
    const size_t n = (size_t)ctx->reduced_w * (size_t)ctx->reduced_h;
    size_t i;
    for (i = 0; i < n; ++i) {
        const uint8_t *p = ctx->reduced + i * 3;
        if (ce_is_skin(p[0], p[1], p[2])) {
            ctx->weights[i] = 0.0;
        }
    }
}
