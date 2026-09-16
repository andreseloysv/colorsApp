/*
 * test_garment.c — paleta por prenda (ce_garment.c) y regiones de prenda
 * (ce_mask_garment_regions) con Unity. Requisito del usuario (CONTEXT §13):
 * "el pantalón es de un solo color; solo debería mostrar un color".
 *
 * Imágenes sintéticas deterministas (la transferencia sRGB es la del motor,
 * ce_srgb_decode/encode, así los bytes son iguales en nativo y WASM):
 *  (a) PANTALÓN ROSA 200x400: torso #2b2c2c y "pierna" #ddc0c8 sombreadas en
 *      luz lineal como un cilindro lambertiano (factor 0,45-1,0 a lo ancho), con
 *      6 pliegues oscuros del 55 % en la pierna (2 del 70 % en el torso) y un 3 %
 *      de brillos especulares; ruido ±2. Con el mapa de 2 regiones salen
 *      exactamente 2 swatches: el de abajo a ΔE00 < 4 de #ddc0c8 y el de arriba a
 *      ΔE00 < 6 de #2b2c2c. ce_palette_extract clásico da >= 3 tonos del rosa (se
 *      imprime cuántos).
 *  (a2) SOMBRA PROYECTADA CONTIGUA sobre media pierna de la misma imagen (1, 2, 3
 *      y 4 pasos de luz lineal, borde recto sin penumbra): sigue saliendo UN solo
 *      color abajo, a ΔE00 < 5 de #ddc0c8; la camisa de rayas con la misma sombra
 *      sigue dando 2 colores arriba.
 *  (b) CAMISA DE RAYAS azul marino / blanco (11 px, sombreada) y pantalón caqui:
 *      2 swatches en la región de arriba y 1 en la de abajo.
 *  (c) VESTIDO de un color arriba y abajo: se fusiona en la región 3 (1 swatch);
 *      y vestido azul marino con estampado blanco desenfocado (caso real de
 *      harness/people/02): región 3 con 2 swatches, azul marino y blanco, no un
 *      gris (límite de luminancia de la agrupación de tonos).
 *  (f) Los tres casos nuevos (ADR-011, segunda vuelta):
 *      (f1) SOMBRA ABIERTA DE EXTERIOR (la sombra se azulea, no es una escala de
 *      la luz: ganancias por canal derivadas de los iluminantes CIE de luz día
 *      FUERA del motor, ver SKY_SHADOW_GAIN) sobre media pierna del pantalón
 *      liso: UN color a ΔE00 < 5 del tono al sol; control con la camisa de rayas
 *      bajo la misma sombra: siguen siendo 2 colores.
 *      (f2) ESTAMPADO oscuro + motivo claro CON esa sombra (el motivo en sombra
 *      tiene la luminancia del fondo al sol): dos colores, ninguno el gris
 *      intermedio, y el estampado sobrevive en las dos regiones. Con enlace
 *      simple el motivo claro desaparecía (regresión medida en people/02).
 *      (f3) DEGRADADO DE COLOR (tie-dye magenta -> amarillo -> cian): dos colores
 *      separados por ΔE00 > 20, también con secondary_min_share 0,35 (ahí la
 *      regla del degradado es lo único que conserva el extremo), y control de que
 *      una prenda lisa con sombra sigue dando un color con ese mismo umbral.
 *  (d) Región sin píxeles con peso (máscara 0 en la pierna): sin swatch de esa
 *      región, pesos y cuotas finitos; mapa todo a 0 -> 1 swatch de reserva (con
 *      máscara válida, el color medio de la MÁSCARA, no el de la imagen entera);
 *      etiquetas > n_regions cuentan como fuera.
 *  (e) Determinismo (mismo ctx y ctx nuevo, memcmp) y hash de paridad
 *      GARMENT_HASH (swatches, capas de depuración y regiones de prenda) igual a
 *      una constante en nativo, ASan y WASM.
 * Además: geometría de ce_mask_garment_regions (mismo soporte que
 * ce_mask_clothing_regions, etiquetas, espejo exacto, persona sentada, errores y
 * alias), errores documentados sin escribir, capas de depuración coherentes,
 * ce_analyze_garments == ce_match sobre los swatches de prenda, mapa NULL ==
 * mapa de unos, la paleta real del tranvía como bandas planas (informativo),
 * tiempo de 1024x1024 RGBA con 2 regiones (GARMENTS_1024_MS, solo se imprime) y
 * fixtures para los tests del CLI.
 */
/* clock_gettime/CLOCK_MONOTONIC son POSIX: con -std=c11 estricto hay que pedirlos. */
#define _POSIX_C_SOURCE 200809L

#include "ce/ce.h"
#include "unity.h"

#include <time.h>
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma STDC FP_CONTRACT OFF

#ifndef CE_TEST_OUT_DIR
#error "CE_TEST_OUT_DIR debe definirse (directorio de salida de fixtures)"
#endif

void setUp(void) {}
void tearDown(void) {}

#define GW 200
#define GH 400
#define TORSO_ROWS 160

static uint64_t g_hash = 0xcbf29ce484222325ULL;
static uint64_t g_lcg = 20260916ULL;

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

static int lcg_noise(int amplitude)
{
    g_lcg = g_lcg * 6364136223846793005ULL + 1442695040888963407ULL;
    return (int)((g_lcg >> 33) % (uint64_t)(2 * amplitude + 1)) - amplitude;
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

static ce_image make_image(const uint8_t *px, int w, int h, const uint8_t *mask)
{
    ce_image img;
    img.pixels = px;
    img.width = w;
    img.height = h;
    img.stride_bytes = w * 3;
    img.fmt = CE_RGB8;
    img.mask = mask;
    return img;
}

static ce_lab hex_lab(unsigned rgb)
{
    return ce_srgb8_to_lab((uint8_t)(rgb >> 16), (uint8_t)(rgb >> 8), (uint8_t)rgb);
}

/* ------------------------------------------------------------------------
 * Sombreado sintético
 * ---------------------------------------------------------------------- */

typedef struct {
    int folds;             /* bandas horizontales oscuras */
    double fold_factor;
    double specular;       /* fracción de columnas con brillo */
    double light_x;        /* luz (light_x, 0, 1) */
} shade_spec;

/* Factor lambertiano de la columna x en [0,45, 1] (cilindro vertical). */
static double lambert(int x, int w, double light_x)
{
    const double u = ((double)x + 0.5) / (double)w * 2.0 - 1.0;
    const double nz = sqrt(1.0 - u * u > 0.0 ? 1.0 - u * u : 0.0);
    double l = (u * light_x + nz) / sqrt(light_x * light_x + 1.0);
    if (l < 0.0) l = 0.0;
    if (l > 1.0) l = 1.0;
    return 0.45 + 0.55 * l;
}

static uint8_t encode8(double lin)
{
    double v;
    if (lin < 0.0) lin = 0.0;
    if (lin > 1.0) lin = 1.0;
    v = ce_srgb_encode(lin) * 255.0 + 0.5;
    if (v >= 255.0) return 255;
    if (v < 0.0) return 0;
    return (uint8_t)v;
}

/* Rellena las filas [y0, y1) con el color de `color_at(y)` sombreado. `rgb_a` y
 * `rgb_b` alternan cada `stripe` filas (stripe 0 = liso con rgb_a). */
static void shade_rows(uint8_t *px, int w, int y0, int y1, unsigned rgb_a, unsigned rgb_b, int stripe,
                       const shade_spec *s)
{
    const int n_spec = (int)(s->specular * (double)w + 0.5);
    int best_col = 0, x, y, k;
    double best = -1.0;
    for (x = 0; x < w; ++x) {
        const double f = lambert(x, w, s->light_x);
        if (f > best) {
            best = f;
            best_col = x;
        }
    }
    for (y = y0; y < y1; ++y) {
        const unsigned rgb = (stripe > 0 && (((y - y0) / stripe) % 2) == 1) ? rgb_b : rgb_a;
        double fold = 1.0;
        for (k = 0; k < s->folds; ++k) {
            /* Pliegues repartidos a lo largo de la pieza, 4 filas cada uno. */
            const int fy = y0 + (y1 - y0) * (2 * k + 1) / (2 * s->folds) - 2;
            if (y >= fy && y < fy + 4) {
                fold = s->fold_factor;
            }
        }
        for (x = 0; x < w; ++x) {
            const double f = lambert(x, w, s->light_x) * fold;
            const int spec = n_spec > 0 && x >= best_col - n_spec / 2 && x < best_col - n_spec / 2 + n_spec;
            uint8_t *p = px + ((size_t)y * (size_t)w + (size_t)x) * 3u;
            int c;
            for (c = 0; c < 3; ++c) {
                const uint8_t v8 = (uint8_t)(rgb >> (16 - 8 * c));
                double lin = ce_srgb_decode((double)v8 / 255.0) * f;
                int v;
                if (spec) {
                    lin = lin + 0.6 * (1.0 - lin);
                }
                v = (int)encode8(lin) + lcg_noise(2);
                p[c] = (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v));
            }
        }
    }
}

static const shade_spec TORSO_SHADE = {2, 0.70, 0.0, -0.35};
static const shade_spec LEG_SHADE = {6, 0.55, 0.03, -0.35};

#define PINK 0xddc0c8u
#define BLACK 0x2b2c2cu
#define NAVY 0x1f2a44u
#define WHITE 0xf2f2eeu
#define KHAKI 0xa89060u
#define DRESS 0x4a7a5au

static void make_pants(uint8_t *px)
{
    g_lcg = 20260916ULL;
    shade_rows(px, GW, 0, TORSO_ROWS, BLACK, BLACK, 0, &TORSO_SHADE);
    shade_rows(px, GW, TORSO_ROWS, GH, PINK, PINK, 0, &LEG_SHADE);
}

static void make_stripes(uint8_t *px)
{
    g_lcg = 20260917ULL;
    shade_rows(px, GW, 0, TORSO_ROWS, NAVY, WHITE, 11, &TORSO_SHADE);
    shade_rows(px, GW, TORSO_ROWS, GH, KHAKI, KHAKI, 0, &LEG_SHADE);
}

static void make_dress(uint8_t *px)
{
    g_lcg = 20260918ULL;
    shade_rows(px, GW, 0, TORSO_ROWS, DRESS, DRESS, 0, &TORSO_SHADE);
    shade_rows(px, GW, TORSO_ROWS, GH, DRESS, DRESS, 0, &LEG_SHADE);
}

/* Vestido azul marino con motivos blancos de 10 px cada 16 px, desenfocado
 * (caja 3x3 en luz lineal) y sombreado como un cilindro con pliegues. */
static void make_print_dress(uint8_t *px)
{
    static double lin[GW * GH * 3], tmp[GW * GH * 3];
    static const unsigned navy = 0x141a2cu, white = 0xecebe6u;
    int x, y, c, k;
    g_lcg = 20260920ULL;
    for (y = 0; y < GH; ++y) {
        for (x = 0; x < GW; ++x) {
            const unsigned rgb = ((x % 16) < 10 && (y % 16) < 10) ? white : navy;
            for (c = 0; c < 3; ++c) {
                lin[((size_t)y * GW + (size_t)x) * 3u + (size_t)c] =
                    ce_srgb_decode((double)((rgb >> (16 - 8 * c)) & 0xFFu) / 255.0);
            }
        }
    }
    for (y = 0; y < GH; ++y) { /* horizontal */
        for (x = 0; x < GW; ++x) {
            for (c = 0; c < 3; ++c) {
                double sum = 0.0;
                for (k = -1; k <= 1; ++k) {
                    const int xx = x + k < 0 ? 0 : (x + k >= GW ? GW - 1 : x + k);
                    sum += lin[((size_t)y * GW + (size_t)xx) * 3u + (size_t)c];
                }
                tmp[((size_t)y * GW + (size_t)x) * 3u + (size_t)c] = sum / 3.0;
            }
        }
    }
    for (y = 0; y < GH; ++y) { /* vertical + sombreado */
        const int fold = (y % 50) >= 46;
        for (x = 0; x < GW; ++x) {
            const double f = lambert(x, GW, -0.35) * (fold ? 0.6 : 1.0);
            for (c = 0; c < 3; ++c) {
                double sum = 0.0;
                int v;
                for (k = -1; k <= 1; ++k) {
                    const int yy = y + k < 0 ? 0 : (y + k >= GH ? GH - 1 : y + k);
                    sum += tmp[((size_t)yy * GW + (size_t)x) * 3u + (size_t)c];
                }
                v = (int)encode8(sum / 3.0 * f) + lcg_noise(2);
                px[((size_t)y * GW + (size_t)x) * 3u + (size_t)c] = (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v));
            }
        }
    }
}

/* Ganancias por canal en luz lineal sRGB de una SOMBRA ABIERTA de exterior: la
 * prenda pasa de sol + cielo a solo cielo, que es mucho más azul. Derivadas
 * FUERA del motor y en otro espacio (diagonal en sRGB lineal, no en conos de
 * Bradford, que es donde el motor modela la adaptación: el test no es
 * tautológico) con colour-science a partir de los iluminantes CIE de luz día:
 *   xy_cielo = CCT_to_xy_CIE_D(12000), xy_escena = CCT_to_xy_CIE_D(5500),
 *   g = RGB_lineal(xy_cielo) / RGB_lineal(xy_escena), normalizada a luminancia
 *   2^-2,5 (2,5 pasos: la caída típica de sol a sombra abierta).
 * El script está en oracle/oracle/garments.py (sky_shadow_gain, usado por la
 * familia "sombra_cielo" del bloque «prendas»). */
static const double SKY_SHADOW_GAIN[3] = {0.12225812, 0.17797109, 0.32558762};

/* Sombra abierta de exterior sobre las filas [y0, y1): multiplica la luz lineal
 * por SKY_SHADOW_GAIN (la sombra se azulea, no es una escala de la luz). */
static void sky_shadow_rows(uint8_t *px, int w, int y0, int y1)
{
    int x, y, c;
    for (y = y0; y < y1; ++y) {
        for (x = 0; x < w; ++x) {
            uint8_t *p = px + ((size_t)y * (size_t)w + (size_t)x) * 3u;
            for (c = 0; c < 3; ++c) {
                p[c] = encode8(ce_srgb_decode((double)p[c] / 255.0) * SKY_SHADOW_GAIN[c]);
            }
        }
    }
}

/* Sombra abierta de exterior con PENUMBRA: las filas [y0, y1) pasan del sol a la
 * sombra con una transición lineal de `penumbra` filas centrada en `edge` (fuera
 * de esa banda, sol arriba y sombra abajo). Una oclusión PARCIAL es una
 * combinación lineal de los dos iluminantes, así que los tonos de la penumbra
 * caen sobre el segmento entre el tono al sol y el tono en sombra: sin esta
 * banda el test no reproducía el fallo del usuario, porque el motor solo toma un
 * cluster por MEZCLA cuando existen esos tonos intermedios. */
static void sky_shadow_penumbra_rows(uint8_t *px, int w, int y0, int y1, int edge, int penumbra)
{
    int x, y, c;
    for (y = y0; y < y1; ++y) {
        double t = ((double)(y - edge) / (double)penumbra) + 0.5;
        if (t < 0.0) t = 0.0;
        if (t > 1.0) t = 1.0;
        for (x = 0; x < w; ++x) {
            uint8_t *p = px + ((size_t)y * (size_t)w + (size_t)x) * 3u;
            for (c = 0; c < 3; ++c) {
                const double lin = ce_srgb_decode((double)p[c] / 255.0);
                p[c] = encode8(lin * (1.0 - t + t * SKY_SHADOW_GAIN[c]));
            }
        }
    }
}

/* Degradado de color (tie-dye) en las filas [y0, y1): interpolación lineal en
 * luz lineal entre tres colores a lo alto, con el lambertiano del cilindro. */
static void tie_dye_rows(uint8_t *px, int w, int y0, int y1, const unsigned rgb[3])
{
    int x, y, c;
    for (y = y0; y < y1; ++y) {
        const double t = (double)(y - y0) / (double)(y1 - y0) * 2.0;
        const int k = (t < 1.0) ? 0 : 1;
        const double f = t - (double)k;
        for (x = 0; x < w; ++x) {
            const double lam = lambert(x, w, -0.35);
            uint8_t *p = px + ((size_t)y * (size_t)w + (size_t)x) * 3u;
            for (c = 0; c < 3; ++c) {
                const double a = ce_srgb_decode((double)((rgb[k] >> (16 - 8 * c)) & 0xFFu) / 255.0);
                const double b = ce_srgb_decode((double)((rgb[k + 1] >> (16 - 8 * c)) & 0xFFu) / 255.0);
                const int v = (int)encode8((a * (1.0 - f) + b * f) * lam) + lcg_noise(2);
                p[c] = (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v));
            }
        }
    }
}

/* Sombra proyectada CONTIGUA: multiplica la luz lineal de las filas [y0, y1) por
 * `factor` (potencias exactas de dos: los bytes salen iguales en nativo y WASM).
 * Borde recto y sin penumbra: el caso más duro para la agrupación de tonos. */
static void cast_shadow_rows(uint8_t *px, int w, int y0, int y1, double factor)
{
    int x, y, c;
    for (y = y0; y < y1; ++y) {
        for (x = 0; x < w; ++x) {
            uint8_t *p = px + ((size_t)y * (size_t)w + (size_t)x) * 3u;
            for (c = 0; c < 3; ++c) {
                p[c] = encode8(ce_srgb_decode((double)p[c] / 255.0) * factor);
            }
        }
    }
}

static void make_regions(uint8_t *reg)
{
    int y;
    for (y = 0; y < GH; ++y) {
        memset(reg + (size_t)y * GW, y < TORSO_ROWS ? 1 : 2, GW);
    }
}

/* ------------------------------------------------------------------------
 * Comprobaciones comunes
 * ---------------------------------------------------------------------- */

static void assert_garments_valid(const ce_garment_swatch *g, int n)
{
    double total = 0.0;
    int i;
    TEST_ASSERT_TRUE(n >= 1 && n <= CE_PALETTE_MAX_COLORS);
    for (i = 0; i < n; ++i) {
        uint8_t r, gg, b;
        TEST_ASSERT_TRUE(isfinite(g[i].swatch.lab.L) && isfinite(g[i].swatch.lab.a) && isfinite(g[i].swatch.lab.b));
        TEST_ASSERT_TRUE(isfinite(g[i].swatch.weight) && g[i].swatch.weight > 0.0 && g[i].swatch.weight <= 1.0 + 1e-12);
        TEST_ASSERT_TRUE(isfinite(g[i].region_share) && g[i].region_share > 0.0 && g[i].region_share <= 1.0 + 1e-12);
        TEST_ASSERT_TRUE(g[i].region >= CE_GARMENT_REGION_NONE && g[i].region <= CE_GARMENT_REGION_WHOLE);
        TEST_ASSERT_TRUE(g[i].n_merged_clusters >= 0 && g[i].n_merged_clusters <= CE_PALETTE_K_MAX);
        ce_lab_to_srgb8(g[i].swatch.lab, &r, &gg, &b);
        TEST_ASSERT_TRUE(r == g[i].swatch.rgb[0] && gg == g[i].swatch.rgb[1] && b == g[i].swatch.rgb[2]);
        if (i > 0) {
            TEST_ASSERT_TRUE(g[i].swatch.weight <= g[i - 1].swatch.weight);
        }
        total += g[i].swatch.weight;
    }
    TEST_ASSERT_DOUBLE_WITHIN(1e-12, 1.0, total);
}

/* Mismos bits en Lab, rgb y peso (sin comparar el relleno del struct). */
static void assert_swatch_bits_equal(const ce_swatch *a, const ce_swatch *b)
{
    TEST_ASSERT_EQUAL_MEMORY(&a->lab.L, &b->lab.L, sizeof(double));
    TEST_ASSERT_EQUAL_MEMORY(&a->lab.a, &b->lab.a, sizeof(double));
    TEST_ASSERT_EQUAL_MEMORY(&a->lab.b, &b->lab.b, sizeof(double));
    TEST_ASSERT_EQUAL_MEMORY(a->rgb, b->rgb, 3);
    TEST_ASSERT_EQUAL_MEMORY(&a->weight, &b->weight, sizeof(double));
}

static int count_region(const ce_garment_swatch *g, int n, int region)
{
    int i, c = 0;
    for (i = 0; i < n; ++i) c += (g[i].region == region);
    return c;
}

static int find_region(const ce_garment_swatch *g, int n, int region)
{
    int i;
    for (i = 0; i < n; ++i) {
        if (g[i].region == region) return i;
    }
    return -1;
}

static void print_garments(const char *title, const ce_garment_swatch *g, int n)
{
    int i;
    printf("%s: %d swatches de prenda:", title, n);
    for (i = 0; i < n; ++i) {
        printf(" [region %d #%02x%02x%02x w %.3f share %.3f clusters %d]", g[i].region, g[i].swatch.rgb[0],
               g[i].swatch.rgb[1], g[i].swatch.rgb[2], g[i].swatch.weight, g[i].region_share, g[i].n_merged_clusters);
    }
    printf("\n");
}

/* Añade al hash de paridad los swatches y todas las capas de la extracción. */
static void hash_result(ce_ctx *ctx, const ce_garment_swatch *g, int n)
{
    ce_palette_debug info;
    uint8_t *layer;
    size_t np;
    g_hash = fnv_bytes(g_hash, &n, sizeof n);
    {
        const uint64_t h = ce_garment_hash(g, n);
        g_hash = fnv_bytes(g_hash, &h, sizeof h);
    }
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_palette_debug_info(ctx, &info));
    np = (size_t)info.reduced_width * (size_t)info.reduced_height;
    layer = (uint8_t *)malloc(np);
    TEST_ASSERT_NOT_NULL(layer);
    TEST_ASSERT_EQUAL_INT((int)np, ce_debug_garment_map(ctx, layer, np));
    g_hash = fnv_bytes(g_hash, layer, np);
    TEST_ASSERT_EQUAL_INT((int)np, ce_debug_region_map(ctx, layer, np));
    g_hash = fnv_bytes(g_hash, layer, np);
    TEST_ASSERT_EQUAL_INT((int)np, ce_debug_cluster_map(ctx, layer, np));
    g_hash = fnv_bytes(g_hash, layer, np);
    free(layer);
    {
        int c;
        for (c = 0; c < info.n_clusters; ++c) {
            const ce_cluster_debug *cd = &info.clusters[c];
            g_hash = fnv_bytes(g_hash, &cd->lab.L, sizeof cd->lab.L);
            g_hash = fnv_bytes(g_hash, &cd->weight, sizeof cd->weight);
            g_hash = fnv_bytes(g_hash, &cd->fate, sizeof cd->fate);
            g_hash = fnv_bytes(g_hash, &cd->final_index, sizeof cd->final_index);
            g_hash = fnv_bytes(g_hash, &cd->group_head, sizeof cd->group_head);
        }
    }
}

/* ------------------------------------------------------------------------
 * (a) Pantalón rosa
 * ---------------------------------------------------------------------- */

static void test_pink_pants(void)
{
    static uint8_t px[GW * GH * 3], reg[GW * GH];
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    const ce_image img = make_image(px, GW, GH, NULL);
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    const ce_lab pink = hex_lab(PINK), black = hex_lab(BLACK);
    int n, lower, upper, i, n_classic, pink_tones = 0;
    double de_lower, de_upper;

    make_pants(px);
    make_regions(reg);
    n = ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, CE_PALETTE_MAX_COLORS);
    print_garments("pantalon rosa (2 regiones)", g, n);
    assert_garments_valid(g, n);
    TEST_ASSERT_EQUAL_INT_MESSAGE(2, n, "el pantalón y la camiseta: exactamente 2 swatches");
    lower = find_region(g, n, CE_GARMENT_REGION_LOWER);
    upper = find_region(g, n, CE_GARMENT_REGION_UPPER);
    TEST_ASSERT_TRUE(lower >= 0 && upper >= 0);
    de_lower = ce_de2000(g[lower].swatch.lab, pink);
    de_upper = ce_de2000(g[upper].swatch.lab, black);
    printf("PINK_PANTS: abajo #%02x%02x%02x dE00 %.3f a #ddc0c8 (%d clusters agrupados); arriba #%02x%02x%02x dE00 %.3f a #2b2c2c\n",
           g[lower].swatch.rgb[0], g[lower].swatch.rgb[1], g[lower].swatch.rgb[2], de_lower, g[lower].n_merged_clusters,
           g[upper].swatch.rgb[0], g[upper].swatch.rgb[1], g[upper].swatch.rgb[2], de_upper);
    TEST_ASSERT_TRUE_MESSAGE(de_lower < 4.0, "tono iluminado del pantalón a ΔE00 < 4 de #ddc0c8");
    TEST_ASSERT_TRUE_MESSAGE(de_upper < 6.0, "camiseta a ΔE00 < 6 de #2b2c2c");
    TEST_ASSERT_TRUE(g[lower].n_merged_clusters >= 2);
    hash_result(ctx, g, n);

    /* Paleta clásica: los tonos del rosa salen como colores distintos. */
    n_classic = ce_palette_extract(ctx, &img, NULL, sw, CE_PALETTE_MAX_COLORS);
    TEST_ASSERT_TRUE(n_classic >= 1);
    printf("PINK_PANTS_CLASSIC: %d swatches:", n_classic);
    for (i = 0; i < n_classic; ++i) {
        /* Tono del rosa: lejos del negro y cerca del rosa tolerando L* (kL = 4). */
        const int is_pink = ce_de2000(sw[i].lab, black) > 10.0 && ce_de2000_k(sw[i].lab, pink, 4.0, 1.0, 1.0) < 12.0;
        pink_tones += is_pink;
        printf(" #%02x%02x%02x %.3f%s", sw[i].rgb[0], sw[i].rgb[1], sw[i].rgb[2], sw[i].weight, is_pink ? "(rosa)" : "");
    }
    printf("\nPINK_TONES_CLASSIC=%d\n", pink_tones);
    TEST_ASSERT_TRUE_MESSAGE(pink_tones >= 3, "ce_palette_extract clásico reparte el pantalón en >= 3 tonos");

    /* Cinturón negro de 16 filas (6,7 % de la pierna): las sombras del rosa son
     * sombras (s·rosa), no mezclas de rosa y negro, así que su peso no pasa al negro
     * y el pantalón sigue siendo un solo color. */
    {
        int y, x;
        for (y = TORSO_ROWS; y < TORSO_ROWS + 16; ++y) {
            for (x = 0; x < GW; ++x) {
                uint8_t *p = px + ((size_t)y * GW + (size_t)x) * 3u;
                p[0] = 0x1a;
                p[1] = 0x1a;
                p[2] = 0x1c;
            }
        }
        n = ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, CE_PALETTE_MAX_COLORS);
        print_garments("pantalon rosa con cinturón negro", g, n);
        assert_garments_valid(g, n);
        TEST_ASSERT_EQUAL_INT_MESSAGE(1, count_region(g, n, CE_GARMENT_REGION_LOWER), "el cinturón no añade un color");
        lower = find_region(g, n, CE_GARMENT_REGION_LOWER);
        TEST_ASSERT_TRUE(ce_de2000(g[lower].swatch.lab, pink) < 4.0);
        hash_result(ctx, g, n);
    }
    free(mem);
}

/* ------------------------------------------------------------------------
 * (a2) Sombra proyectada contigua sobre la prenda lisa
 * ---------------------------------------------------------------------- */

/* Sol contra sombra abierta: media pierna a 1-4 pasos menos de luz. Sin la regla
 * de sombra de la selección (CE_GARMENT_SHADE_S_MIN) el grupo oscuro salía como
 * un segundo color falso, que es justo lo que el usuario pidió eliminar
 * (CONTEXT §13). Control: la camisa de rayas con la misma sombra sigue dando dos
 * colores (un segundo color de verdad no es el primero con menos luz). */
static void test_cast_shadow(void)
{
    static uint8_t px[GW * GH * 3], reg[GW * GH];
    static const double FACTORS[4] = {0.5, 0.25, 0.125, 0.0625};
    static const int STOPS[4] = {1, 2, 3, 4};
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    const ce_image img = make_image(px, GW, GH, NULL);
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    const ce_lab pink = hex_lab(PINK);
    ce_palette_opts po;
    int k, n, lower, upper;

    /* Sin ponderación al centro: el peso de un color es su área, así que la mitad
     * en sombra pesa de verdad el 50 % de la pierna (con la gaussiana por defecto
     * los pies pesan poco y el grupo de sombra no llega a secondary_min_share). */
    ce_palette_opts_default(&po);
    po.center_sigma = 0.0;

    for (k = 0; k < 4; ++k) {
        double de;
        make_pants(px);
        make_regions(reg);
        cast_shadow_rows(px, GW, TORSO_ROWS + (GH - TORSO_ROWS) / 2, GH, FACTORS[k]);
        n = ce_palette_extract_garments(ctx, &img, reg, 2, &po, NULL, g, CE_PALETTE_MAX_COLORS);
        assert_garments_valid(g, n);
        lower = find_region(g, n, CE_GARMENT_REGION_LOWER);
        TEST_ASSERT_TRUE_MESSAGE(lower >= 0, "la pierna con sombra sigue teniendo color");
        de = ce_de2000(g[lower].swatch.lab, pink);
        printf("CAST_SHADOW: -%d pasos sobre media pierna -> %d color(es) abajo, #%02x%02x%02x dE00 %.2f a #ddc0c8 (%d clusters)\n",
               STOPS[k], count_region(g, n, CE_GARMENT_REGION_LOWER), g[lower].swatch.rgb[0], g[lower].swatch.rgb[1],
               g[lower].swatch.rgb[2], de, g[lower].n_merged_clusters);
        TEST_ASSERT_EQUAL_INT_MESSAGE(1, count_region(g, n, CE_GARMENT_REGION_LOWER),
                                      "una prenda lisa con sombra proyectada es un solo color");
        TEST_ASSERT_TRUE_MESSAGE(de < 5.0, "el tono iluminado sigue a ΔE00 < 5 de #ddc0c8");
        hash_result(ctx, g, n);
    }

    /* Control: prenda de verdad bicolor con la misma sombra proyectada. */
    make_stripes(px);
    make_regions(reg);
    cast_shadow_rows(px, GW, TORSO_ROWS / 2, TORSO_ROWS, 0.25);
    n = ce_palette_extract_garments(ctx, &img, reg, 2, &po, NULL, g, CE_PALETTE_MAX_COLORS);
    print_garments("rayas con sombra proyectada", g, n);
    assert_garments_valid(g, n);
    upper = count_region(g, n, CE_GARMENT_REGION_UPPER);
    printf("CAST_SHADOW_STRIPES: %d colores arriba (marino y blanco)\n", upper);
    TEST_ASSERT_EQUAL_INT_MESSAGE(2, upper, "la camisa de rayas con sombra sigue siendo bicolor");
    hash_result(ctx, g, n);
    free(mem);
}

/* ------------------------------------------------------------------------
 * (b) Camisa de rayas y (c) vestido
 * ---------------------------------------------------------------------- */

static void test_striped_shirt(void)
{
    static uint8_t px[GW * GH * 3], reg[GW * GH];
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    const ce_image img = make_image(px, GW, GH, NULL);
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    int n, i, navy = 0, white = 0;

    make_stripes(px);
    make_regions(reg);
    n = ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, CE_PALETTE_MAX_COLORS);
    print_garments("camisa de rayas", g, n);
    assert_garments_valid(g, n);
    TEST_ASSERT_EQUAL_INT_MESSAGE(2, count_region(g, n, CE_GARMENT_REGION_UPPER), "rayas: 2 colores arriba");
    TEST_ASSERT_EQUAL_INT_MESSAGE(1, count_region(g, n, CE_GARMENT_REGION_LOWER), "pantalón caqui: 1 color abajo");
    TEST_ASSERT_EQUAL_INT(0, count_region(g, n, CE_GARMENT_REGION_WHOLE));
    for (i = 0; i < n; ++i) {
        if (g[i].region != CE_GARMENT_REGION_UPPER) continue;
        printf("  rayas: #%02x%02x%02x dE00 marino %.2f blanco %.2f\n", g[i].swatch.rgb[0], g[i].swatch.rgb[1],
               g[i].swatch.rgb[2], ce_de2000(g[i].swatch.lab, hex_lab(NAVY)), ce_de2000(g[i].swatch.lab, hex_lab(WHITE)));
        navy += ce_de2000(g[i].swatch.lab, hex_lab(NAVY)) < 8.0;
        white += ce_de2000(g[i].swatch.lab, hex_lab(WHITE)) < 8.0;
    }
    TEST_ASSERT_TRUE_MESSAGE(navy == 1 && white == 1, "un swatch azul marino y otro blanco");
    hash_result(ctx, g, n);
    free(mem);
}

static void test_dress_fuses(void)
{
    static uint8_t px[GW * GH * 3], reg[GW * GH];
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    const ce_image img = make_image(px, GW, GH, NULL);
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    ce_palette_debug info;
    int n, c;

    make_dress(px);
    make_regions(reg);
    n = ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, CE_PALETTE_MAX_COLORS);
    print_garments("vestido", g, n);
    assert_garments_valid(g, n);
    TEST_ASSERT_EQUAL_INT_MESSAGE(1, n, "vestido: un solo color");
    TEST_ASSERT_EQUAL_INT_MESSAGE(CE_GARMENT_REGION_WHOLE, g[0].region, "arriba y abajo fusionados en la región 3");
    TEST_ASSERT_DOUBLE_WITHIN(1e-12, 1.0, g[0].region_share);
    printf("DRESS: #%02x%02x%02x dE00 %.3f a #4a7a5a\n", g[0].swatch.rgb[0], g[0].swatch.rgb[1], g[0].swatch.rgb[2],
           ce_de2000(g[0].swatch.lab, hex_lab(DRESS)));
    TEST_ASSERT_TRUE(ce_de2000(g[0].swatch.lab, hex_lab(DRESS)) < 4.0);
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_palette_debug_info(ctx, &info));
    for (c = 0; c < info.n_clusters; ++c) {
        TEST_ASSERT_TRUE(info.clusters[c].fate != CE_FATE_KEPT || info.clusters[c].final_index == 0);
    }
    hash_result(ctx, g, n);

    /* Vestido azul marino con estampado blanco desenfocado: los tonos de mezcla
     * del borde no encadenan el fondo con el motivo (dos colores, no un gris). */
    make_print_dress(px);
    n = ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, CE_PALETTE_MAX_COLORS);
    print_garments("vestido con estampado desenfocado", g, n);
    assert_garments_valid(g, n);
    TEST_ASSERT_EQUAL_INT_MESSAGE(2, n, "azul marino + estampado blanco: 2 swatches");
    TEST_ASSERT_EQUAL_INT(2, count_region(g, n, CE_GARMENT_REGION_WHOLE));
    {
        const double d_navy = ce_de2000(g[0].swatch.lab, hex_lab(0x141a2cu)) < ce_de2000(g[1].swatch.lab, hex_lab(0x141a2cu))
                                   ? ce_de2000(g[0].swatch.lab, hex_lab(0x141a2cu)) : ce_de2000(g[1].swatch.lab, hex_lab(0x141a2cu));
        const double d_white = ce_de2000(g[0].swatch.lab, hex_lab(0xecebe6u)) < ce_de2000(g[1].swatch.lab, hex_lab(0xecebe6u))
                                    ? ce_de2000(g[0].swatch.lab, hex_lab(0xecebe6u)) : ce_de2000(g[1].swatch.lab, hex_lab(0xecebe6u));
        printf("PRINT_DRESS: dE00 azul marino %.2f, blanco %.2f\n", d_navy, d_white);
        TEST_ASSERT_TRUE_MESSAGE(d_navy < 8.0 && d_white < 8.0, "un swatch azul marino y otro blanco");
    }
    hash_result(ctx, g, n);
    free(mem);
}

/* ------------------------------------------------------------------------
 * (f) Sombra azul de exterior, estampado con sombra y degradado de color
 * ---------------------------------------------------------------------- */

/* (f1) SOMBRA ABIERTA DE EXTERIOR sobre la prenda lisa: media pierna pasa de sol
 * + cielo a solo cielo (2,5 pasos y azuleo, ganancias derivadas fuera del motor:
 * ver SKY_SHADOW_GAIN). Con el modelo de escala pura la sombra azul NO es una
 * escala de la luz y el pantalón salía con dos colores (harness/people/06, el
 * vaquero al sol y a la sombra, y CONTEXT §13). Debe salir UN color a ΔE00 < 5
 * del tono al sol. Control: la camisa de rayas con la misma sombra azul sigue
 * dando dos colores. */
static void test_sky_shadow(void)
{
    static uint8_t px[GW * GH * 3], reg[GW * GH];
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    const ce_image img = make_image(px, GW, GH, NULL);
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    const ce_lab pink = hex_lab(PINK);
    ce_palette_opts po;
    int n, lower, upper;
    double de;

    ce_palette_opts_default(&po);
    po.center_sigma = 0.0;

    make_pants(px);
    make_regions(reg);
    sky_shadow_rows(px, GW, TORSO_ROWS + (GH - TORSO_ROWS) / 2, GH);
    n = ce_palette_extract_garments(ctx, &img, reg, 2, &po, NULL, g, CE_PALETTE_MAX_COLORS);
    print_garments("pantalon liso con sombra azul de exterior", g, n);
    assert_garments_valid(g, n);
    lower = find_region(g, n, CE_GARMENT_REGION_LOWER);
    TEST_ASSERT_TRUE_MESSAGE(lower >= 0, "la pierna con sombra azul sigue teniendo color");
    de = ce_de2000(g[lower].swatch.lab, pink);
    printf("SKY_SHADOW: %d color(es) abajo, #%02x%02x%02x dE00 %.2f a #ddc0c8 (%d clusters)\n",
           count_region(g, n, CE_GARMENT_REGION_LOWER), g[lower].swatch.rgb[0], g[lower].swatch.rgb[1],
           g[lower].swatch.rgb[2], de, g[lower].n_merged_clusters);
    TEST_ASSERT_EQUAL_INT_MESSAGE(1, count_region(g, n, CE_GARMENT_REGION_LOWER),
                                  "una prenda lisa al sol y a la sombra azul es un solo color");
    TEST_ASSERT_TRUE_MESSAGE(de < 5.0, "el tono iluminado sigue a ΔE00 < 5 del tono al sol");
    hash_result(ctx, g, n);

    /* (f1b) EL CASO DEL USUARIO, con PENUMBRA y la sombra cubriendo el 60 % de la
     * pierna: es la configuración con la que el verificador demostró que el
     * pantalón seguía saliendo con DOS colores (32 escenas de 32). La penumbra
     * crea clusters intermedios que caen sobre el segmento luz-sombra; el motor
     * los tomaba por una MEZCLA de dos colores distintos y el veto de mezcla
     * bloqueaba el modelo de cielo, que es el único camino por el que pueden
     * agruparse. Barrido de cobertura 40-80 % y penumbra 6-24 filas. */
    {
        static const int COVER[4] = {40, 55, 65, 70};
        static const int PEN[4] = {6, 12, 18, 24};
        int k;
        for (k = 0; k < 4; ++k) {
            const int leg = GH - TORSO_ROWS;
            const int edge = TORSO_ROWS + leg * (100 - COVER[k]) / 100;
            make_pants(px);
            make_regions(reg);
            sky_shadow_penumbra_rows(px, GW, TORSO_ROWS, GH, edge, PEN[k]);
            n = ce_palette_extract_garments(ctx, &img, reg, 2, &po, NULL, g, CE_PALETTE_MAX_COLORS);
            assert_garments_valid(g, n);
            lower = find_region(g, n, CE_GARMENT_REGION_LOWER);
            TEST_ASSERT_TRUE(lower >= 0);
            de = ce_de2000(g[lower].swatch.lab, pink);
            printf("SKY_SHADOW_PENUMBRA cobertura %d%% penumbra %d: %d color(es) abajo, #%02x%02x%02x dE00 %.2f\n",
                   COVER[k], PEN[k], count_region(g, n, CE_GARMENT_REGION_LOWER), g[lower].swatch.rgb[0],
                   g[lower].swatch.rgb[1], g[lower].swatch.rgb[2], de);
            TEST_ASSERT_EQUAL_INT_MESSAGE(1, count_region(g, n, CE_GARMENT_REGION_LOWER),
                                          "sombra azul con penumbra: la prenda lisa sigue siendo UN color");
            TEST_ASSERT_TRUE_MESSAGE(de < 5.0, "el tono iluminado sigue a ΔE00 < 5 del tono al sol");
            hash_result(ctx, g, n);
        }
    }

    /* (f1b') LÍMITE MEDIDO Y DOCUMENTADO (ce.h, ADR-011): cuando la sombra azul
     * cubre MÁS del ~70 % de la prenda, el tono iluminado deja de pesar lo
     * suficiente (CE_GARMENT_LIT_CORE_FRACTION) y el color que se devuelve es el
     * tono EN SOMBRA. Sigue siendo UN color —el requisito del usuario—, pero el
     * hex es el de la sombra. El test fija el límite para que avise si cambia. */
    {
        const int leg = GH - TORSO_ROWS;
        make_pants(px);
        make_regions(reg);
        sky_shadow_penumbra_rows(px, GW, TORSO_ROWS, GH, TORSO_ROWS + leg * 20 / 100, 18);
        n = ce_palette_extract_garments(ctx, &img, reg, 2, &po, NULL, g, CE_PALETTE_MAX_COLORS);
        assert_garments_valid(g, n);
        lower = find_region(g, n, CE_GARMENT_REGION_LOWER);
        TEST_ASSERT_TRUE(lower >= 0);
        de = ce_de2000(g[lower].swatch.lab, pink);
        printf("SKY_SHADOW_80: %d color(es) abajo, #%02x%02x%02x dE00 %.2f al tono al sol (límite conocido)\n",
               count_region(g, n, CE_GARMENT_REGION_LOWER), g[lower].swatch.rgb[0], g[lower].swatch.rgb[1],
               g[lower].swatch.rgb[2], de);
        TEST_ASSERT_EQUAL_INT_MESSAGE(1, count_region(g, n, CE_GARMENT_REGION_LOWER),
                                      "con el 80 % en sombra sigue siendo UN color");
        TEST_ASSERT_TRUE_MESSAGE(de > 5.0, "límite conocido: con > ~70 % en sombra se devuelve el tono EN SOMBRA");
        hash_result(ctx, g, n);
    }

    /* (f1c) SOMBRA NEUTRA PROFUNDA (3 pasos) con penumbra: el tono iluminado no
     * puede oscurecerse por absorber la sombra (CE_GARMENT_LIT_Y_RATIO). */
    {
        int y, x, c;
        make_pants(px);
        make_regions(reg);
        for (y = TORSO_ROWS + (GH - TORSO_ROWS) * 2 / 5; y < GH; ++y) {
            double t = ((double)(y - (TORSO_ROWS + (GH - TORSO_ROWS) * 2 / 5)) / 12.0);
            if (t > 1.0) t = 1.0;
            for (x = 0; x < GW; ++x) {
                uint8_t *p = px + ((size_t)y * GW + (size_t)x) * 3u;
                for (c = 0; c < 3; ++c) {
                    p[c] = encode8(ce_srgb_decode((double)p[c] / 255.0) * (1.0 - t + t * 0.125));
                }
            }
        }
        n = ce_palette_extract_garments(ctx, &img, reg, 2, &po, NULL, g, CE_PALETTE_MAX_COLORS);
        assert_garments_valid(g, n);
        lower = find_region(g, n, CE_GARMENT_REGION_LOWER);
        TEST_ASSERT_TRUE(lower >= 0);
        de = ce_de2000(g[lower].swatch.lab, pink);
        printf("DEEP_SHADOW_LIT: %d color(es) abajo, #%02x%02x%02x dE00 %.2f a #ddc0c8 (sombra neutra de 3 pasos)\n",
               count_region(g, n, CE_GARMENT_REGION_LOWER), g[lower].swatch.rgb[0], g[lower].swatch.rgb[1],
               g[lower].swatch.rgb[2], de);
        TEST_ASSERT_EQUAL_INT_MESSAGE(1, count_region(g, n, CE_GARMENT_REGION_LOWER), "sombra de 3 pasos: un color");
        TEST_ASSERT_TRUE_MESSAGE(de < 5.0, "el tono iluminado no se oscurece con una sombra de 3 pasos");
        hash_result(ctx, g, n);
    }

    /* Control: prenda de verdad bicolor bajo la misma sombra azul. */
    make_stripes(px);
    make_regions(reg);
    sky_shadow_rows(px, GW, TORSO_ROWS / 2, TORSO_ROWS);
    n = ce_palette_extract_garments(ctx, &img, reg, 2, &po, NULL, g, CE_PALETTE_MAX_COLORS);
    print_garments("rayas con sombra azul de exterior", g, n);
    assert_garments_valid(g, n);
    upper = count_region(g, n, CE_GARMENT_REGION_UPPER);
    printf("SKY_SHADOW_STRIPES: %d colores arriba (marino y blanco)\n", upper);
    TEST_ASSERT_EQUAL_INT_MESSAGE(2, upper, "la camisa de rayas con sombra azul sigue siendo bicolor");
    hash_result(ctx, g, n);
    free(mem);
}

/* (f2) ESTAMPADO OSCURO + MOTIVO CLARO CON SOMBRA (caso de harness/people/02, un
 * vestido azul marino con estampado blanco desenfocado, con media prenda en
 * sombra azul): el motivo claro en sombra se solapa en luminancia con el fondo
 * oscuro al sol, así que con enlace simple los tonos intermedios encadenaban el
 * marino con el blanco y el estampado DESAPARECÍA (o el vestido se partía en dos
 * regiones). Deben salir los dos colores, y ninguno puede ser el gris intermedio. */
static void test_print_dress_shadow(void)
{
    static uint8_t px[GW * GH * 3], reg[GW * GH];
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    const ce_image img = make_image(px, GW, GH, NULL);
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    const ce_lab navy = hex_lab(0x141a2cu), white = hex_lab(0xecebe6u);
    ce_palette_opts po;
    int n, i, n_navy = 0, n_white = 0, n_gray = 0, r;
    double d_navy = 1e9, d_white = 1e9;

    ce_palette_opts_default(&po);
    po.center_sigma = 0.0;

    /* (a) Toda la prenda como una región (el caso de la región 3 de people/02):
     * el motivo claro en sombra tiene la luminancia del fondo oscuro al sol. */
    make_print_dress(px);
    sky_shadow_rows(px, GW, GH / 2, GH);
    n = ce_palette_extract_garments(ctx, &img, NULL, 0, &po, NULL, g, CE_PALETTE_MAX_COLORS);
    print_garments("estampado marino/blanco con sombra azul (una región)", g, n);
    assert_garments_valid(g, n);
    for (i = 0; i < n; ++i) {
        const double dn = ce_de2000(g[i].swatch.lab, navy);
        const double dw = ce_de2000(g[i].swatch.lab, white);
        if (dn < d_navy) d_navy = dn;
        if (dw < d_white) d_white = dw;
        n_navy += dn < 12.0;
        n_white += dw < 12.0;
        n_gray += (dn >= 12.0 && dw >= 12.0);
    }
    printf("PRINT_SHADOW: %d swatches, dE00 mínimo al marino %.2f y al blanco %.2f (intermedios %d)\n",
           n, d_navy, d_white, n_gray);
    TEST_ASSERT_EQUAL_INT_MESSAGE(2, n, "el estampado con sombra sigue dando dos colores, no uno");
    TEST_ASSERT_TRUE_MESSAGE(n_navy == 1 && n_white == 1, "un swatch azul marino y otro blanco");
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, n_gray, "ningún swatch es el gris intermedio de la cadena");
    hash_result(ctx, g, n);

    /* (b) Con el mapa de dos regiones: el estampado sobrevive arriba (al sol) y
     * abajo (en sombra), y los dos colores de cada región son colores distintos
     * de verdad (no el mismo gris dos veces). */
    make_regions(reg);
    n = ce_palette_extract_garments(ctx, &img, reg, 2, &po, NULL, g, CE_PALETTE_MAX_COLORS);
    print_garments("estampado marino/blanco con sombra azul (dos regiones)", g, n);
    assert_garments_valid(g, n);
    for (r = CE_GARMENT_REGION_UPPER; r <= CE_GARMENT_REGION_LOWER; ++r) {
        int a = -1, b = -1;
        for (i = 0; i < n; ++i) {
            if (g[i].region != r) continue;
            if (a < 0) a = i;
            else if (b < 0) b = i;
        }
        TEST_ASSERT_EQUAL_INT_MESSAGE(2, count_region(g, n, r), "el estampado sobrevive en las dos regiones");
        printf("PRINT_SHADOW_REGION%d: #%02x%02x%02x y #%02x%02x%02x, dE00 %.2f\n", r, g[a].swatch.rgb[0],
               g[a].swatch.rgb[1], g[a].swatch.rgb[2], g[b].swatch.rgb[0], g[b].swatch.rgb[1], g[b].swatch.rgb[2],
               ce_de2000(g[a].swatch.lab, g[b].swatch.lab));
        TEST_ASSERT_TRUE_MESSAGE(ce_de2000(g[a].swatch.lab, g[b].swatch.lab) > 25.0,
                                 "los dos colores de la región son colores distintos de verdad");
    }
    hash_result(ctx, g, n);

    /* (c) La misma prenda con la sombra azul CON PENUMBRA sobre el 60 %: los tonos
     * de la penumbra del fondo oscuro y los del motivo claro llenan el hueco de
     * luminancia entre los dos colores. Es el caso que puede encadenar por
     * transitividad (fondo oscuro -> penumbra -> motivo claro) si la agrupación
     * no controla la cadena: con enlace completo y estrella de sombra el par
     * extremo marino/blanco tiene que ser él mismo el mismo material, y no lo es
     * (s = 0,012 < CE_GARMENT_SHADE_S_MIN). */
    {
        int i2;
        double dn_min = 1e9, dw_min = 1e9;
        int navy_n = 0, white_n = 0, gray_n = 0;
        make_print_dress(px);
        sky_shadow_penumbra_rows(px, GW, 0, GH, GH * 2 / 5, 20);
        n = ce_palette_extract_garments(ctx, &img, NULL, 0, &po, NULL, g, CE_PALETTE_MAX_COLORS);
        print_garments("estampado marino/blanco con sombra azul y penumbra (60 %)", g, n);
        assert_garments_valid(g, n);
        for (i2 = 0; i2 < n; ++i2) {
            const double dn = ce_de2000(g[i2].swatch.lab, navy);
            const double dw = ce_de2000(g[i2].swatch.lab, white);
            if (dn < dn_min) dn_min = dn;
            if (dw < dw_min) dw_min = dw;
            navy_n += dn < 14.0;
            white_n += dw < 14.0;
            gray_n += (dn >= 14.0 && dw >= 14.0);
        }
        printf("PRINT_PENUMBRA: %d swatches, dE00 mínimo al marino %.2f y al blanco %.2f (intermedios %d)\n",
               n, dn_min, dw_min, gray_n);
        TEST_ASSERT_EQUAL_INT_MESSAGE(2, n, "el estampado con penumbra sigue dando dos colores");
        TEST_ASSERT_TRUE_MESSAGE(navy_n == 1 && white_n == 1, "un swatch marino y otro blanco, no el gris de la cadena");
        TEST_ASSERT_EQUAL_INT_MESSAGE(0, gray_n, "ningún swatch es un tono intermedio de la penumbra");
        hash_result(ctx, g, n);
    }
    free(mem);
}

/* (f3) DEGRADADO DE COLOR (tie-dye): la pierna pasa de magenta a amarillo y a
 * cian. No puede colapsar a un solo color: los tonos intermedios son la prueba
 * de una variación de tono CONTINUA y los extremos se conservan
 * (CE_GARMENT_GRADIENT_MIN_SHARE). */
static void test_tie_dye(void)
{
    static uint8_t px[GW * GH * 3], reg[GW * GH];
    static const unsigned RAMP[3] = {0xd81b8cu, 0xf2d21au, 0x17c8d8u};
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    const ce_image img = make_image(px, GW, GH, NULL);
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    ce_palette_opts po;
    int n, i, lower_n, first = -1, second = -1;
    double spread;

    ce_palette_opts_default(&po);
    po.center_sigma = 0.0;

    g_lcg = 20260921ULL;
    shade_rows(px, GW, 0, TORSO_ROWS, BLACK, BLACK, 0, &TORSO_SHADE);
    tie_dye_rows(px, GW, TORSO_ROWS, GH, RAMP);
    make_regions(reg);
    n = ce_palette_extract_garments(ctx, &img, reg, 2, &po, NULL, g, CE_PALETTE_MAX_COLORS);
    print_garments("tie-dye magenta -> amarillo -> cian", g, n);
    assert_garments_valid(g, n);
    lower_n = count_region(g, n, CE_GARMENT_REGION_LOWER);
    for (i = 0; i < n; ++i) {
        if (g[i].region != CE_GARMENT_REGION_LOWER) continue;
        if (first < 0) first = i;
        else if (second < 0) second = i;
    }
    TEST_ASSERT_TRUE_MESSAGE(lower_n >= 2, "un degradado de color no colapsa a un solo color");
    spread = ce_de2000(g[first].swatch.lab, g[second].swatch.lab);
    printf("TIE_DYE: %d colores abajo, #%02x%02x%02x y #%02x%02x%02x, dE00 entre ellos %.2f\n", lower_n,
           g[first].swatch.rgb[0], g[first].swatch.rgb[1], g[first].swatch.rgb[2], g[second].swatch.rgb[0],
           g[second].swatch.rgb[1], g[second].swatch.rgb[2], spread);
    TEST_ASSERT_TRUE_MESSAGE(spread > 20.0, "los dos colores del degradado son colores distintos de verdad");
    hash_result(ctx, g, n);

    /* La regla del degradado (CE_GARMENT_GRADIENT_MIN_SHARE) es lo que conserva el
     * extremo cuando su cuota no llega a secondary_min_share: con 0,35 el segundo
     * color solo sobrevive por ser extremo de una variación de tono continua
     * (medido: sin la regla sale 1 color desde 0,30). Control: la prenda lisa con
     * sombra proyectada sigue dando UN color con el mismo umbral, así que la regla
     * no reabre los segundos colores falsos. */
    {
        ce_garment_opts go;
        ce_garment_opts_default(&go);
        go.secondary_min_share = 0.35;
        n = ce_palette_extract_garments(ctx, &img, reg, 2, &po, &go, g, CE_PALETTE_MAX_COLORS);
        assert_garments_valid(g, n);
        printf("TIE_DYE_STRICT: %d colores abajo con secondary_min_share 0,35\n",
               count_region(g, n, CE_GARMENT_REGION_LOWER));
        TEST_ASSERT_EQUAL_INT_MESSAGE(2, count_region(g, n, CE_GARMENT_REGION_LOWER),
                                      "el extremo del degradado sobrevive a secondary_min_share 0,35");
        hash_result(ctx, g, n);

        /* El degradado con una SOMBRA AZUL con penumbra encima sigue conservando sus
         * extremos: la regla de sombra agrupa la luz con su sombra, pero no
         * colapsa una variación de tono continua. */
        g_lcg = 20260921ULL;
        shade_rows(px, GW, 0, TORSO_ROWS, BLACK, BLACK, 0, &TORSO_SHADE);
        tie_dye_rows(px, GW, TORSO_ROWS, GH, RAMP);
        make_regions(reg);
        sky_shadow_penumbra_rows(px, GW, TORSO_ROWS, GH, TORSO_ROWS + (GH - TORSO_ROWS) * 2 / 5, 16);
        n = ce_palette_extract_garments(ctx, &img, reg, 2, &po, NULL, g, CE_PALETTE_MAX_COLORS);
        assert_garments_valid(g, n);
        printf("TIE_DYE_SKY: %d colores abajo (degradado con sombra azul y penumbra)\n",
               count_region(g, n, CE_GARMENT_REGION_LOWER));
        TEST_ASSERT_TRUE_MESSAGE(count_region(g, n, CE_GARMENT_REGION_LOWER) >= 2,
                                 "el degradado con sombra azul no colapsa a un solo color");
        hash_result(ctx, g, n);

        make_pants(px);
        make_regions(reg);
        cast_shadow_rows(px, GW, TORSO_ROWS + (GH - TORSO_ROWS) / 2, GH, 0.125);
        n = ce_palette_extract_garments(ctx, &img, reg, 2, &po, &go, g, CE_PALETTE_MAX_COLORS);
        assert_garments_valid(g, n);
        printf("TIE_DYE_CONTROL: %d color(es) abajo (pantalón liso con sombra, mismo umbral)\n",
               count_region(g, n, CE_GARMENT_REGION_LOWER));
        TEST_ASSERT_EQUAL_INT_MESSAGE(1, count_region(g, n, CE_GARMENT_REGION_LOWER),
                                      "la sombra de una prenda lisa no es un degradado de color");
        hash_result(ctx, g, n);
    }
    free(mem);
}

/* ------------------------------------------------------------------------
 * (d) Regiones sin peso
 * ---------------------------------------------------------------------- */

static void test_empty_region(void)
{
    static uint8_t px[GW * GH * 3], reg[GW * GH], mask[GW * GH];
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_image img;
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    int n, y;

    make_pants(px);
    make_regions(reg);
    for (y = 0; y < GH; ++y) {
        memset(mask + (size_t)y * GW, y < TORSO_ROWS ? 255 : 0, GW);
    }
    img = make_image(px, GW, GH, mask);
    n = ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, CE_PALETTE_MAX_COLORS);
    print_garments("pierna con máscara 0", g, n);
    assert_garments_valid(g, n);
    TEST_ASSERT_EQUAL_INT(0, count_region(g, n, CE_GARMENT_REGION_LOWER));
    TEST_ASSERT_EQUAL_INT(0, count_region(g, n, CE_GARMENT_REGION_WHOLE));
    TEST_ASSERT_EQUAL_INT(1, n);
    TEST_ASSERT_EQUAL_INT(CE_GARMENT_REGION_UPPER, g[0].region);
    TEST_ASSERT_DOUBLE_WITHIN(1e-12, 1.0, g[0].region_share);
    hash_result(ctx, g, n);

    /* Ninguna región con peso: 1 swatch de reserva (color medio), sin NaN. */
    memset(reg, 0, sizeof reg);
    img = make_image(px, GW, GH, NULL);
    n = ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, CE_PALETTE_MAX_COLORS);
    assert_garments_valid(g, n);
    TEST_ASSERT_EQUAL_INT(1, n);
    TEST_ASSERT_EQUAL_INT(CE_GARMENT_REGION_NONE, g[0].region);
    TEST_ASSERT_EQUAL_INT(0, g[0].n_merged_clusters);
    {
        ce_palette_debug info;
        static uint8_t layer[GW * GH];
        size_t i, np;
        TEST_ASSERT_EQUAL_INT(CE_OK, ce_palette_debug_info(ctx, &info));
        TEST_ASSERT_EQUAL_INT(0, info.n_clusters);
        np = (size_t)info.reduced_width * (size_t)info.reduced_height;
        TEST_ASSERT_EQUAL_INT((int)np, ce_debug_garment_map(ctx, layer, sizeof layer));
        for (i = 0; i < np; ++i) TEST_ASSERT_EQUAL_UINT8(CE_LABEL_NONE, layer[i]);
    }
    hash_result(ctx, g, n);

    /* Máscara VÁLIDA y mapa de regiones sin peso (desalineado): el color de reserva
     * es el medio de la MÁSCARA, nunca el de toda la imagen (fondo incluido). */
    {
        ce_swatch whole[CE_PALETTE_MAX_COLORS];
        ce_lab mask_mean;
        uint64_t sr = 0, sg = 0, sb = 0, sm = 0;
        int x;
        for (y = 0; y < GH; ++y) {
            memset(mask + (size_t)y * GW, y < TORSO_ROWS ? 255 : 0, GW);
        }
        for (y = 0; y < GH; ++y) {
            for (x = 0; x < GW; ++x) {
                const uint8_t *q = px + ((size_t)y * GW + (size_t)x) * 3u;
                const uint64_t m = mask[(size_t)y * GW + (size_t)x];
                if (m == 0u) continue;
                sr += m * q[0];
                sg += m * q[1];
                sb += m * q[2];
                sm += m;
            }
        }
        mask_mean = ce_srgb_to_lab((double)sr / (double)sm / 255.0, (double)sg / (double)sm / 255.0,
                                   (double)sb / (double)sm / 255.0);
        memset(reg, 0, sizeof reg);
        img = make_image(px, GW, GH, mask);
        n = ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, CE_PALETTE_MAX_COLORS);
        assert_garments_valid(g, n);
        TEST_ASSERT_EQUAL_INT(1, n);
        TEST_ASSERT_EQUAL_INT(CE_GARMENT_REGION_NONE, g[0].region);
        printf("EMPTY_MAP_WITH_MASK: reserva #%02x%02x%02x dE00 %.3f a la media de la máscara\n",
               g[0].swatch.rgb[0], g[0].swatch.rgb[1], g[0].swatch.rgb[2],
               ce_de2000(g[0].swatch.lab, mask_mean));
        TEST_ASSERT_DOUBLE_WITHIN(1e-9, mask_mean.L, g[0].swatch.lab.L);
        TEST_ASSERT_DOUBLE_WITHIN(1e-9, mask_mean.a, g[0].swatch.lab.a);
        TEST_ASSERT_DOUBLE_WITHIN(1e-9, mask_mean.b, g[0].swatch.lab.b);
        hash_result(ctx, g, n);
        /* Y es distinto del color medio de toda la imagen (lo que devolvía antes). */
        TEST_ASSERT_TRUE(ce_palette_extract(ctx, &img, NULL, whole, CE_PALETTE_MAX_COLORS) >= 1);
        img = make_image(px, GW, GH, NULL);
    }

    /* Etiquetas mayores que n_regions cuentan como fuera: 2 con n_regions 1. */
    make_regions(reg);
    n = ce_palette_extract_garments(ctx, &img, reg, 1, NULL, NULL, g, CE_PALETTE_MAX_COLORS);
    assert_garments_valid(g, n);
    TEST_ASSERT_EQUAL_INT(n, count_region(g, n, CE_GARMENT_REGION_UPPER));
    TEST_ASSERT_TRUE(ce_de2000(g[0].swatch.lab, hex_lab(BLACK)) < 6.0);
    hash_result(ctx, g, n);
    free(mem);
}

/* ------------------------------------------------------------------------
 * (e) Determinismo
 * ---------------------------------------------------------------------- */

static void test_determinism(void)
{
    static uint8_t px[GW * GH * 3], reg[GW * GH];
    void *mem1, *mem2;
    ce_ctx *c1 = ctx_new(&mem1), *c2 = ctx_new(&mem2);
    const ce_image img = make_image(px, GW, GH, NULL);
    ce_garment_swatch a[CE_PALETTE_MAX_COLORS], b[CE_PALETTE_MAX_COLORS], c[CE_PALETTE_MAX_COLORS];
    int na, nb, nc;
    ce_swatch dummy[CE_PALETTE_MAX_COLORS];

    make_stripes(px);
    make_regions(reg);
    memset(a, 0, sizeof a);
    memset(b, 0, sizeof b);
    memset(c, 0, sizeof c);
    na = ce_palette_extract_garments(c1, &img, reg, 2, NULL, NULL, a, CE_PALETTE_MAX_COLORS);
    /* Una extracción clásica en medio no deja estado que cambie la siguiente. */
    TEST_ASSERT_TRUE(ce_palette_extract(c1, &img, NULL, dummy, CE_PALETTE_MAX_COLORS) >= 1);
    nb = ce_palette_extract_garments(c1, &img, reg, 2, NULL, NULL, b, CE_PALETTE_MAX_COLORS);
    nc = ce_palette_extract_garments(c2, &img, reg, 2, NULL, NULL, c, CE_PALETTE_MAX_COLORS);
    TEST_ASSERT_EQUAL_INT(na, nb);
    TEST_ASSERT_EQUAL_INT(na, nc);
    TEST_ASSERT_EQUAL_MEMORY(a, b, sizeof a);
    TEST_ASSERT_EQUAL_MEMORY(a, c, sizeof a);
    TEST_ASSERT_EQUAL_HEX64(ce_garment_hash(a, na), ce_garment_hash(c, nc));
    free(mem1);
    free(mem2);
}

/* ------------------------------------------------------------------------
 * Regiones de prenda (ce_mask_garment_regions)
 * ---------------------------------------------------------------------- */

static void kp(ce_pose *p, int j, double x, double y, double c)
{
    p->k[j].x = x;
    p->k[j].y = y;
    p->k[j].confidence = c;
}

/* La misma pose de frente de test_mask.c (coordenadas múltiplos de 1/4). */
static void pose_front(ce_pose *p, double ox)
{
    kp(p, CE_JOINT_NOSE, ox + 100.0, 50.0, 0.9);
    kp(p, CE_JOINT_NECK, ox + 100.0, 90.0, 0.9);
    kp(p, CE_JOINT_LSHOULDER, ox + 140.0, 90.0, 0.9);
    kp(p, CE_JOINT_RSHOULDER, ox + 60.0, 90.0, 0.9);
    kp(p, CE_JOINT_LELBOW, ox + 152.25, 150.5, 0.8);
    kp(p, CE_JOINT_RELBOW, ox + 47.75, 150.5, 0.8);
    kp(p, CE_JOINT_LWRIST, ox + 158.5, 205.25, 0.7);
    kp(p, CE_JOINT_RWRIST, ox + 41.5, 205.25, 0.7);
    kp(p, CE_JOINT_LHIP, ox + 124.0, 210.0, 0.9);
    kp(p, CE_JOINT_RHIP, ox + 76.0, 210.0, 0.9);
    kp(p, CE_JOINT_LKNEE, ox + 126.25, 290.75, 0.8);
    kp(p, CE_JOINT_RKNEE, ox + 73.75, 290.75, 0.8);
    kp(p, CE_JOINT_LANKLE, ox + 128.5, 370.5, 0.8);
    kp(p, CE_JOINT_RANKLE, ox + 71.5, 370.5, 0.8);
    kp(p, CE_JOINT_ROOT, ox + 100.0, 210.0, 0.9);
}

static void test_garment_regions_geometry(void)
{
    static uint8_t person[GW * GH], cloth[GW * GH], regions[GW * GH], mirror_regions[GW * GH], alias[GW * GH];
    static uint8_t mirror_person[GW * GH];
    ce_pose pose, mirror;
    ce_region_opts o;
    int i, n, n_cloth, upper = 0, lower = 0, x, y;

    ce_region_opts_default(&o);
    pose_front(&pose, 0.0);
    for (i = 0; i < GW * GH; ++i) person[i] = (uint8_t)(1 + (i * 37) % 255); /* máscara > 0 no binaria */
    memcpy(cloth, person, sizeof cloth);
    n_cloth = ce_mask_clothing_regions(&pose, &o, cloth, GW, GH);
    n = ce_mask_garment_regions(&pose, &o, person, GW, GH, regions);
    TEST_ASSERT_TRUE(n > 0);
    TEST_ASSERT_EQUAL_INT_MESSAGE(n_cloth, n, "mismo número de píxeles que ce_mask_clothing_regions");
    for (i = 0; i < GW * GH; ++i) {
        TEST_ASSERT_TRUE_MESSAGE((regions[i] != 0) == (cloth[i] != 0), "mismo soporte que ce_mask_clothing_regions");
        TEST_ASSERT_TRUE(regions[i] <= 2);
        upper += regions[i] == 1;
        lower += regions[i] == 2;
    }
    printf("GARMENT_REGIONS: %d px (arriba %d, abajo %d)\n", n, upper, lower);
    TEST_ASSERT_EQUAL_UINT8(1, regions[150 * GW + 100]); /* pecho */
    TEST_ASSERT_EQUAL_UINT8(1, regions[120 * GW + 146]); /* brazo superior izquierdo */
    TEST_ASSERT_EQUAL_UINT8(2, regions[250 * GW + 125]); /* muslo izquierdo */
    TEST_ASSERT_EQUAL_UINT8(2, regions[340 * GW + 73]);  /* espinilla derecha */
    TEST_ASSERT_EQUAL_UINT8(2, regions[215 * GW + 100]); /* margen del torso bajo las caderas */
    TEST_ASSERT_EQUAL_UINT8(0, regions[60 * GW + 100]);  /* cabeza */
    for (y = 0; y < 200; ++y) {
        for (x = 70; x < 130; ++x) {
            if (regions[y * GW + x] == 2) {
                TEST_FAIL_MESSAGE("nada del torso por encima del corte de caderas es 'abajo'");
            }
        }
    }

    /* Alias: regions_out == person_mask da el mismo resultado. */
    memcpy(alias, person, sizeof alias);
    TEST_ASSERT_EQUAL_INT(n, ce_mask_garment_regions(&pose, &o, alias, GW, GH, alias));
    TEST_ASSERT_EQUAL_MEMORY(regions, alias, sizeof alias);

    /* Espejo horizontal exacto con L/R intercambiados (ancho par: x -> W − x). */
    mirror = pose;
    for (i = 0; i < CE_JOINT_COUNT; ++i) mirror.k[i].x = (double)GW - pose.k[i].x;
    {
        static const int pairs[][2] = {{CE_JOINT_LSHOULDER, CE_JOINT_RSHOULDER}, {CE_JOINT_LELBOW, CE_JOINT_RELBOW},
                                       {CE_JOINT_LWRIST, CE_JOINT_RWRIST},       {CE_JOINT_LHIP, CE_JOINT_RHIP},
                                       {CE_JOINT_LKNEE, CE_JOINT_RKNEE},         {CE_JOINT_LANKLE, CE_JOINT_RANKLE}};
        size_t k;
        for (k = 0; k < sizeof pairs / sizeof pairs[0]; ++k) {
            const ce_keypoint t = mirror.k[pairs[k][0]];
            mirror.k[pairs[k][0]] = mirror.k[pairs[k][1]];
            mirror.k[pairs[k][1]] = t;
        }
    }
    for (y = 0; y < GH; ++y) {
        for (x = 0; x < GW; ++x) mirror_person[y * GW + x] = person[y * GW + (GW - 1 - x)];
    }
    TEST_ASSERT_EQUAL_INT(n, ce_mask_garment_regions(&mirror, &o, mirror_person, GW, GH, mirror_regions));
    for (y = 0; y < GH; ++y) {
        for (x = 0; x < GW; ++x) {
            TEST_ASSERT_EQUAL_UINT8(regions[y * GW + x], mirror_regions[y * GW + (GW - 1 - x)]);
        }
    }

    /* Persona sentada: muslos en horizontal a la altura de las caderas -> abajo. */
    {
        ce_pose sit = pose;
        sit.k[CE_JOINT_LWRIST].confidence = 0.0; /* sin manos que recorten el regazo */
        sit.k[CE_JOINT_RWRIST].confidence = 0.0;
        kp(&sit, CE_JOINT_LKNEE, 184.0, 214.0, 0.8);
        kp(&sit, CE_JOINT_RKNEE, 136.0, 214.0, 0.8);
        kp(&sit, CE_JOINT_LANKLE, 186.0, 300.0, 0.8);
        kp(&sit, CE_JOINT_RANKLE, 138.0, 300.0, 0.8);
        memset(person, 255, sizeof person);
        TEST_ASSERT_TRUE(ce_mask_garment_regions(&sit, &o, person, GW, GH, regions) > 0);
        TEST_ASSERT_EQUAL_UINT8(2, regions[212 * GW + 170]); /* muslo izquierdo en horizontal */
        TEST_ASSERT_EQUAL_UINT8(2, regions[260 * GW + 185]); /* espinilla */
        TEST_ASSERT_EQUAL_UINT8(1, regions[150 * GW + 100]); /* pecho */
    }

    /* Errores: no escriben. */
    memset(regions, 7, sizeof regions);
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_garment_regions(NULL, &o, person, GW, GH, regions));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_garment_regions(&pose, NULL, person, GW, GH, regions));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_garment_regions(&pose, &o, NULL, GW, GH, regions));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_garment_regions(&pose, &o, person, GW, GH, NULL));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_garment_regions(&pose, &o, person, 0, GH, regions));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_garment_regions(&pose, &o, person, GW, CE_IMAGE_MAX_SIDE + 1, regions));
    o.limb_width = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_garment_regions(&pose, &o, person, GW, GH, regions));
    ce_region_opts_default(&o);
    pose.k[CE_JOINT_LHIP].confidence = 0.0;
    pose.k[CE_JOINT_RHIP].confidence = 0.0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_POSE, ce_mask_garment_regions(&pose, &o, person, GW, GH, regions));
    for (i = 0; i < GW * GH; ++i) TEST_ASSERT_EQUAL_UINT8(7, regions[i]);

    /* Hash de paridad de la geometría. */
    pose_front(&pose, 0.25);
    memset(person, 255, sizeof person);
    n = ce_mask_garment_regions(&pose, &o, person, GW, GH, regions);
    g_hash = fnv_bytes(g_hash, regions, sizeof regions);
    g_hash = fnv_bytes(g_hash, &n, sizeof n);
}

/* ------------------------------------------------------------------------
 * Errores, capas y consistencia
 * ---------------------------------------------------------------------- */

static void test_errors_do_not_write(void)
{
    static uint8_t px[GW * GH * 3], reg[GW * GH];
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    unsigned char zero_ctx[64];
    ce_image img = make_image(px, GW, GH, NULL);
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS], sentinel[CE_PALETTE_MAX_COLORS];
    ce_garment_opts go;
    ce_palette_opts po;
    ce_match_opts mo;
    ce_result res, res_sentinel;
    uint8_t layer[16];

    make_pants(px);
    make_regions(reg);
    memset(sentinel, 0xA5, sizeof sentinel);
    memcpy(g, sentinel, sizeof g);
    memset(zero_ctx, 0, sizeof zero_ctx);
#define EXPECT_ERR(code, call)                                   \
    do {                                                         \
        memcpy(g, sentinel, sizeof g);                           \
        TEST_ASSERT_EQUAL_INT(code, call);                       \
        TEST_ASSERT_EQUAL_MEMORY(sentinel, g, sizeof g);         \
    } while (0)
    EXPECT_ERR(CE_ERR_ARG, ce_palette_extract_garments(NULL, &img, reg, 2, NULL, NULL, g, 8));
    EXPECT_ERR(CE_ERR_ARG, ce_palette_extract_garments(ctx, NULL, reg, 2, NULL, NULL, g, 8));
    EXPECT_ERR(CE_ERR_ARG, ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, NULL, 8));
    EXPECT_ERR(CE_ERR_ARG, ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, 0));
    EXPECT_ERR(CE_ERR_ARG, ce_palette_extract_garments(ctx, &img, reg, 0, NULL, NULL, g, 8));
    EXPECT_ERR(CE_ERR_ARG, ce_palette_extract_garments(ctx, &img, reg, CE_GARMENT_MAX_REGIONS + 1, NULL, NULL, g, 8));
    EXPECT_ERR(CE_ERR_CTX, ce_palette_extract_garments((ce_ctx *)(void *)zero_ctx, &img, reg, 2, NULL, NULL, g, 8));
    img.width = 0;
    EXPECT_ERR(CE_ERR_DIMS, ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, 8));
    img = make_image(px, GW, GH, NULL);
    img.stride_bytes = GW * 3 - 1;
    EXPECT_ERR(CE_ERR_STRIDE, ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, 8));
    img = make_image(px, GW, GH, NULL);
    img.fmt = (ce_pixel_format)9;
    EXPECT_ERR(CE_ERR_FORMAT, ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, 8));
    img = make_image(px, GW, GH, NULL);
    /* Tras un error las capas no son válidas. */
    TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_debug_garment_map(ctx, layer, sizeof layer));
    ce_palette_opts_default(&po);
    po.k_init = 0;
    EXPECT_ERR(CE_ERR_OPTS, ce_palette_extract_garments(ctx, &img, reg, 2, &po, NULL, g, 8));
    ce_garment_opts_default(&go);
    go.shade_kL = 0.0;
    EXPECT_ERR(CE_ERR_OPTS, ce_palette_extract_garments(ctx, &img, reg, 2, NULL, &go, g, 8));
    ce_garment_opts_default(&go);
    go.shade_kL = NAN;
    EXPECT_ERR(CE_ERR_OPTS, ce_palette_extract_garments(ctx, &img, reg, 2, NULL, &go, g, 8));
    ce_garment_opts_default(&go);
    go.shade_merge_de = INFINITY;
    EXPECT_ERR(CE_ERR_OPTS, ce_palette_extract_garments(ctx, &img, reg, 2, NULL, &go, g, 8));
    ce_garment_opts_default(&go);
    go.lit_low_pct = 0.99; /* > lit_high_pct por defecto (0,95) */
    EXPECT_ERR(CE_ERR_OPTS, ce_palette_extract_garments(ctx, &img, reg, 2, NULL, &go, g, 8));
    ce_garment_opts_default(&go);
    go.lit_high_pct = 1.5;
    EXPECT_ERR(CE_ERR_OPTS, ce_palette_extract_garments(ctx, &img, reg, 2, NULL, &go, g, 8));
    ce_garment_opts_default(&go);
    go.secondary_min_share = -0.1;
    EXPECT_ERR(CE_ERR_OPTS, ce_palette_extract_garments(ctx, &img, reg, 2, NULL, &go, g, 8));
    ce_garment_opts_default(&go);
    go.max_colors_per_region = 0;
    EXPECT_ERR(CE_ERR_OPTS, ce_palette_extract_garments(ctx, &img, reg, 2, NULL, &go, g, 8));
    go.max_colors_per_region = CE_PALETTE_MAX_COLORS + 1;
    EXPECT_ERR(CE_ERR_OPTS, ce_palette_extract_garments(ctx, &img, reg, 2, NULL, &go, g, 8));
#undef EXPECT_ERR

    /* ce_analyze_garments: opciones de match validadas antes de extraer. */
    memset(&res_sentinel, 0x5A, sizeof res_sentinel);
    res = res_sentinel;
    ce_match_opts_default(&mo);
    mo.coverage_lambda = -1.0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_OPTS, ce_analyze_garments(ctx, &img, reg, 2, NULL, NULL, &mo, &res, g, 8));
    TEST_ASSERT_EQUAL_MEMORY(&res_sentinel, &res, sizeof res);
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_analyze_garments(ctx, &img, reg, 2, NULL, NULL, NULL, &res, g, 0));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_analyze_garments(ctx, &img, reg, 3, NULL, NULL, NULL, &res, g, 8));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_analyze_garments(ctx, &img, reg, 2, NULL, NULL, NULL, NULL, g, 8));
    TEST_ASSERT_EQUAL_MEMORY(&res_sentinel, &res, sizeof res);
    /* Tras una extracción clásica, las capas de prenda dan CE_ERR_CTX. */
    {
        ce_swatch sw[CE_PALETTE_MAX_COLORS];
        TEST_ASSERT_TRUE(ce_palette_extract(ctx, &img, NULL, sw, CE_PALETTE_MAX_COLORS) >= 1);
        TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_debug_garment_map(ctx, layer, sizeof layer));
        TEST_ASSERT_EQUAL_INT(CE_ERR_CTX, ce_debug_region_map(ctx, layer, sizeof layer));
    }
    free(mem);
}

static void test_debug_layers_consistent(void)
{
    static uint8_t px[GW * GH * 3], reg[GW * GH];
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    const ce_image img = make_image(px, GW, GH, NULL);
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    ce_palette_debug info;
    uint8_t *gmap, *rmap, *lmap, *cmap, *wmap;
    size_t np, i;
    int n, c, counts[CE_PALETTE_MAX_COLORS] = {0};

    make_stripes(px);
    make_regions(reg);
    n = ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, CE_PALETTE_MAX_COLORS);
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_palette_debug_info(ctx, &info));
    TEST_ASSERT_EQUAL_INT(n, info.n_swatches);
    TEST_ASSERT_TRUE(info.n_clusters >= n && info.n_clusters <= CE_PALETTE_K_MAX);
    np = (size_t)info.reduced_width * (size_t)info.reduced_height;
    gmap = (uint8_t *)malloc(np);
    rmap = (uint8_t *)malloc(np);
    lmap = (uint8_t *)malloc(np);
    cmap = (uint8_t *)malloc(np);
    wmap = (uint8_t *)malloc(np);
    TEST_ASSERT_TRUE(gmap && rmap && lmap && cmap && wmap);
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_debug_garment_map(ctx, gmap, np - 1));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_debug_region_map(ctx, NULL, np));
    TEST_ASSERT_EQUAL_INT((int)np, ce_debug_garment_map(ctx, gmap, np));
    TEST_ASSERT_EQUAL_INT((int)np, ce_debug_region_map(ctx, rmap, np));
    TEST_ASSERT_EQUAL_INT((int)np, ce_debug_label_map(ctx, lmap, np));
    TEST_ASSERT_EQUAL_INT((int)np, ce_debug_cluster_map(ctx, cmap, np));
    TEST_ASSERT_EQUAL_INT((int)np, ce_debug_weight_map(ctx, wmap, np));
    for (i = 0; i < np; ++i) {
        const int row = (int)(i / (size_t)info.reduced_width);
        TEST_ASSERT_EQUAL_UINT8(row * 2 < TORSO_ROWS ? CE_GARMENT_REGION_UPPER : CE_GARMENT_REGION_LOWER, rmap[i]);
        if (gmap[i] != CE_LABEL_NONE) {
            TEST_ASSERT_TRUE(gmap[i] < n);
            TEST_ASSERT_EQUAL_INT(g[gmap[i]].region, rmap[i]);
            ++counts[gmap[i]];
        }
        TEST_ASSERT_TRUE(lmap[i] == gmap[i] || (lmap[i] == CE_LABEL_DISCARDED && gmap[i] == CE_LABEL_NONE));
        if (cmap[i] == CE_LABEL_NONE) {
            TEST_ASSERT_EQUAL_UINT8(CE_LABEL_NONE, gmap[i]);
        } else {
            TEST_ASSERT_TRUE(cmap[i] < info.n_clusters);
            c = info.clusters[cmap[i]].final_index;
            TEST_ASSERT_EQUAL_INT(c >= 0 ? c : CE_LABEL_NONE, gmap[i]);
        }
    }
    for (c = 0; c < n; ++c) TEST_ASSERT_TRUE(counts[c] > 0);
    for (c = 0; c < info.n_clusters; ++c) {
        const ce_cluster_debug *cd = &info.clusters[c];
        TEST_ASSERT_TRUE(cd->group_head >= 0 && cd->group_head < info.n_clusters);
        TEST_ASSERT_TRUE(cd->fate >= CE_FATE_KEPT && cd->fate <= CE_FATE_TRUNCATED);
        TEST_ASSERT_TRUE((cd->fate <= CE_FATE_MERGED) == (cd->final_index >= 0));
        if (cd->fate == CE_FATE_KEPT) TEST_ASSERT_EQUAL_INT(c, cd->group_head);
        if (cd->final_index >= 0) {
            TEST_ASSERT_EQUAL_INT(info.clusters[cd->group_head].final_index, cd->final_index);
        }
    }
    free(gmap);
    free(rmap);
    free(lmap);
    free(cmap);
    free(wmap);
    free(mem);
}

static void test_analyze_and_null_map(void)
{
    static uint8_t px[GW * GH * 3], reg[GW * GH], ones[GW * GH], mask[GW * GH];
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_image img = make_image(px, GW, GH, NULL);
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS], g_null[CE_PALETTE_MAX_COLORS], g_ones[CE_PALETTE_MAX_COLORS];
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    ce_hit hits[CE_MATCH_MAX_HITS];
    ce_result res, res2;
    int rc, n, amb, i, n_null, n_ones;

    make_pants(px);
    make_regions(reg);
    rc = ce_analyze_garments(ctx, &img, reg, 2, NULL, NULL, NULL, &res, g, CE_PALETTE_MAX_COLORS);
    TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, rc);
    n = res.n_swatches;
    TEST_ASSERT_EQUAL_INT(2, n);
    for (i = 0; i < n; ++i) {
        assert_swatch_bits_equal(&g[i].swatch, &res.swatches[i]);
        sw[i] = res.swatches[i];
    }
    for (i = n; i < CE_PALETTE_MAX_COLORS; ++i) TEST_ASSERT_EQUAL_DOUBLE(0.0, res.swatches[i].weight);
    TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, ce_match(ctx, sw, n, NULL, hits, CE_MATCH_MAX_HITS, &amb));
    for (i = 0; i < CE_MATCH_MAX_HITS; ++i) {
        TEST_ASSERT_EQUAL_UINT16(hits[i].combo_id, res.hits[i].combo_id);
        TEST_ASSERT_EQUAL_MEMORY(&hits[i].score, &res.hits[i].score, sizeof(double));
    }
    printf("PINK_PANTS_MATCH: top-3 %u %.4f, %u %.4f, %u %.4f\n", res.hits[0].combo_id, res.hits[0].score,
           res.hits[1].combo_id, res.hits[1].score, res.hits[2].combo_id, res.hits[2].score);
    /* garments NULL: mismo resultado (campo a campo: el relleno de los structs no cuenta). */
    TEST_ASSERT_EQUAL_INT(rc, ce_analyze_garments(ctx, &img, reg, 2, NULL, NULL, NULL, &res2, NULL, 0));
    TEST_ASSERT_EQUAL_INT(res.n_swatches, res2.n_swatches);
    TEST_ASSERT_EQUAL_INT(res.n_hits, res2.n_hits);
    TEST_ASSERT_EQUAL_INT(res.ambiguous, res2.ambiguous);
    TEST_ASSERT_EQUAL_HEX64(ce_result_hash(&res), ce_result_hash(&res2));
    {
        const uint64_t h = ce_result_hash(&res);
        g_hash = fnv_bytes(g_hash, &h, sizeof h);
    }

    /* Mapa NULL == mapa de unos con n_regions 1 (con máscara, mismos pesos): mismos
     * swatches bit a bit; solo cambia la región (0 frente a 1). */
    for (i = 0; i < GW * GH; ++i) {
        ones[i] = 1;
        mask[i] = (uint8_t)(128 + (i % 128));
    }
    img = make_image(px, GW, GH, mask);
    n_null = ce_palette_extract_garments(ctx, &img, NULL, 7, NULL, NULL, g_null, CE_PALETTE_MAX_COLORS);
    n_ones = ce_palette_extract_garments(ctx, &img, ones, 1, NULL, NULL, g_ones, CE_PALETTE_MAX_COLORS);
    TEST_ASSERT_EQUAL_INT(n_null, n_ones);
    for (i = 0; i < n_null; ++i) {
        assert_swatch_bits_equal(&g_null[i].swatch, &g_ones[i].swatch);
        TEST_ASSERT_EQUAL_INT(CE_GARMENT_REGION_NONE, g_null[i].region);
        TEST_ASSERT_EQUAL_INT(CE_GARMENT_REGION_UPPER, g_ones[i].region);
        TEST_ASSERT_EQUAL_INT(g_null[i].n_merged_clusters, g_ones[i].n_merged_clusters);
    }
    print_garments("sin mapa (una región)", g_null, n_null);
    hash_result(ctx, g_ones, n_ones);
    free(mem);
}

/* Paleta real de la foto del tranvía como bandas planas (informativo): el
 * pantalón sale como un color. */
static void test_real_pants_palette_bands(void)
{
    static uint8_t px[GW * GH * 3], reg[GW * GH];
    static const unsigned pants[4] = {0xb49aa2u, 0x917a7eu, 0xd5b8c0u, 0x6b5a57u};
    static const double share[4] = {0.227, 0.162, 0.134, 0.083};
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    const ce_image img = make_image(px, GW, GH, NULL);
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    double total = 0.0, acc = 0.0;
    int x, y, k, n, lower, x0 = 0;

    for (k = 0; k < 4; ++k) total += share[k];
    g_lcg = 20260919ULL;
    for (k = 0; k < 4; ++k) {
        int x1;
        acc += share[k];
        x1 = (k == 3) ? GW : (int)(acc / total * GW + 0.5);
        for (y = TORSO_ROWS; y < GH; ++y) {
            for (x = x0; x < x1; ++x) {
                uint8_t *p = px + ((size_t)y * GW + (size_t)x) * 3u;
                int c;
                for (c = 0; c < 3; ++c) {
                    const int v = (int)((pants[k] >> (16 - 8 * c)) & 0xFFu) + lcg_noise(2);
                    p[c] = (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v));
                }
            }
        }
        x0 = x1;
    }
    for (y = 0; y < TORSO_ROWS; ++y) {
        for (x = 0; x < GW; ++x) {
            uint8_t *p = px + ((size_t)y * GW + (size_t)x) * 3u;
            p[0] = 0x22;
            p[1] = 0x25;
            p[2] = 0x24;
        }
    }
    make_regions(reg);
    n = ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, CE_PALETTE_MAX_COLORS);
    print_garments("paleta real del tranvía en bandas", g, n);
    assert_garments_valid(g, n);
    TEST_ASSERT_EQUAL_INT_MESSAGE(1, count_region(g, n, CE_GARMENT_REGION_LOWER), "los 4 tonos del pantalón: 1 color");
    lower = find_region(g, n, CE_GARMENT_REGION_LOWER);
    printf("REAL_PANTS_BANDS: abajo #%02x%02x%02x dE00 %.2f a #ddc0c8 y %.2f a #d5b8c0 (%d clusters)\n",
           g[lower].swatch.rgb[0], g[lower].swatch.rgb[1], g[lower].swatch.rgb[2],
           ce_de2000(g[lower].swatch.lab, hex_lab(PINK)), ce_de2000(g[lower].swatch.lab, hex_lab(0xd5b8c0u)),
           g[lower].n_merged_clusters);
    hash_result(ctx, g, n);
    free(mem);
}

/* Tiempo de la paleta por prenda en 1024x1024 RGBA (se imprime, sin cota). */
static void test_timing_1024(void)
{
    const int w = 1024, h = 1024;
    uint8_t *px = (uint8_t *)malloc((size_t)w * (size_t)h * 4u);
    uint8_t *reg = (uint8_t *)malloc((size_t)w * (size_t)h);
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    ce_image img;
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    double best = 1e30, best_classic = 1e30;
    int x, y, k, n = 0;
    TEST_ASSERT_TRUE(px != NULL && reg != NULL);
    g_lcg = 7ULL;
    for (y = 0; y < h; ++y) {
        for (x = 0; x < w; ++x) {
            uint8_t *p = px + ((size_t)y * (size_t)w + (size_t)x) * 4u;
            const double f = lambert(x % 256, 256, -0.35);
            const unsigned rgb = y < h * 2 / 5 ? BLACK : PINK;
            int c;
            for (c = 0; c < 3; ++c) {
                const int v = (int)encode8(ce_srgb_decode((double)((rgb >> (16 - 8 * c)) & 0xFFu) / 255.0) * f) + lcg_noise(3);
                p[c] = (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v));
            }
            p[3] = 255;
            reg[(size_t)y * (size_t)w + (size_t)x] = y < h * 2 / 5 ? 1 : 2;
        }
    }
    img.pixels = px;
    img.width = w;
    img.height = h;
    img.stride_bytes = w * 4;
    img.fmt = CE_RGBA8;
    img.mask = NULL;
    for (k = 0; k < 5; ++k) {
        struct timespec t0, t1, t2;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        n = ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, CE_PALETTE_MAX_COLORS);
        clock_gettime(CLOCK_MONOTONIC, &t1);
        TEST_ASSERT_TRUE(ce_palette_extract(ctx, &img, NULL, sw, CE_PALETTE_MAX_COLORS) >= 1);
        clock_gettime(CLOCK_MONOTONIC, &t2);
        {
            const double ms = (double)(t1.tv_sec - t0.tv_sec) * 1e3 + (double)(t1.tv_nsec - t0.tv_nsec) / 1e6;
            const double ms_c = (double)(t2.tv_sec - t1.tv_sec) * 1e3 + (double)(t2.tv_nsec - t1.tv_nsec) / 1e6;
            if (ms < best) best = ms;
            if (ms_c < best_classic) best_classic = ms_c;
        }
    }
    TEST_ASSERT_EQUAL_INT(2, n);
    printf("GARMENTS_1024_MS=%.2f (1024x1024 RGBA, 2 regiones, mejor de 5); ce_palette_extract %.2f ms; ctx %zu bytes\n",
           best, best_classic, ce_ctx_size());
    free(px);
    free(reg);
    free(mem);
}

/* ------------------------------------------------------------------------
 * Paridad y fixtures del CLI
 * ---------------------------------------------------------------------- */

/* Constante medida en nativo (Apple arm64): ASan y WASM deben dar los mismos bits. */
#define CE_GARMENT_PARITY_HASH 0x2f33620fa4322acbULL

static void test_parity_hash(void)
{
    printf("GARMENT_HASH=%016" PRIx64 "\n", g_hash);
    TEST_ASSERT_EQUAL_HEX64(CE_GARMENT_PARITY_HASH, g_hash);
}

static void write_file(const char *name, const char *header, const uint8_t *data, size_t n)
{
    char path[1024];
    FILE *f;
    snprintf(path, sizeof path, "%s/%s", CE_TEST_OUT_DIR, name);
    f = fopen(path, "wb");
    TEST_ASSERT_NOT_NULL_MESSAGE(f, path);
    if (header != NULL) fputs(header, f);
    TEST_ASSERT_EQUAL_size_t(n, fwrite(data, 1, n, f));
    TEST_ASSERT_EQUAL_INT(0, fclose(f));
}

static void test_write_cli_fixtures(void)
{
    static uint8_t px[GW * GH * 3], reg[GW * GH], stripes[GW * GH * 3], person[GW * GH], gregions[GW * GH];
    char header[64], text[4096];
    void *mem;
    ce_ctx *ctx = ctx_new(&mem);
    const ce_image img = make_image(px, GW, GH, NULL);
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    ce_result res;
    ce_pose pose;
    ce_region_opts o;
    uint64_t h_pants, h_match, h_stripes;
    int n, n_regions, i;
    size_t len;

    make_pants(px);
    make_regions(reg);
    make_stripes(stripes);
    snprintf(header, sizeof header, "P6\n%d %d\n255\n", GW, GH);
    write_file("garment_pants.ppm", header, px, sizeof px);
    write_file("garment_stripes.ppm", header, stripes, sizeof stripes);
    {
        static uint8_t dress[GW * GH * 3];
        make_dress(dress);
        write_file("garment_dress.ppm", header, dress, sizeof dress);
        make_print_dress(dress);
        write_file("garment_print_dress.ppm", header, dress, sizeof dress);
    }
    snprintf(header, sizeof header, "P5\n%d %d\n255\n", GW, GH);
    write_file("garment_regions.pgm", header, reg, sizeof reg);
    n = ce_palette_extract_garments(ctx, &img, reg, 2, NULL, NULL, g, CE_PALETTE_MAX_COLORS);
    h_pants = ce_garment_hash(g, n);
    TEST_ASSERT_EQUAL_INT(CE_MATCH_MAX_HITS, ce_analyze_garments(ctx, &img, reg, 2, NULL, NULL, NULL, &res, NULL, 0));
    res.n_hits = 3;
    h_match = ce_result_hash(&res);
    {
        const ce_image simg = make_image(stripes, GW, GH, NULL);
        n = ce_palette_extract_garments(ctx, &simg, reg, 2, NULL, NULL, g, CE_PALETTE_MAX_COLORS);
        h_stripes = ce_garment_hash(g, n);
    }
    /* Pose de frente y regiones de prenda esperadas. */
    pose_front(&pose, 0.0);
    len = 0;
    for (i = 0; i < CE_JOINT_COUNT; ++i) {
        len += (size_t)snprintf(text + len, sizeof text - len, "%.17g %.17g %.17g\n", pose.k[i].x, pose.k[i].y,
                                pose.k[i].confidence);
    }
    write_file("garment_pose.txt", NULL, (const uint8_t *)text, len);
    memset(person, 255, sizeof person);
    ce_region_opts_default(&o);
    n_regions = ce_mask_garment_regions(&pose, &o, person, GW, GH, gregions);
    TEST_ASSERT_TRUE(n_regions > 0);
    write_file("garment_person.pgm", header, person, sizeof person);
    write_file("garment_expected_regions.pgm", header, gregions, sizeof gregions);
    len = (size_t)snprintf(text, sizeof text,
                           "{\"pants_hash\": \"%016" PRIx64 "\", \"pants_match_result_hash\": \"%016" PRIx64 "\", "
                           "\"pants_top1\": %u, \"stripes_hash\": \"%016" PRIx64 "\", \"garment_regions_pixels\": %d}\n",
                           h_pants, h_match, (unsigned)res.hits[0].combo_id, h_stripes, n_regions);
    write_file("garment_expected.json", NULL, (const uint8_t *)text, len);
    len = (size_t)snprintf(text, sizeof text,
                           "# batch --garments: imagen [mascara|-] [regiones]\n"
                           "%s/garment_pants.ppm - %s/garment_regions.pgm\n"
                           "%s/garment_stripes.ppm\t-\t%s/garment_regions.pgm\n"
                           "%s/garment_pants.ppm\n"
                           "%s/garment_pants.ppm - %s/does_not_exist_regions.pgm\n",
                           CE_TEST_OUT_DIR, CE_TEST_OUT_DIR, CE_TEST_OUT_DIR, CE_TEST_OUT_DIR, CE_TEST_OUT_DIR,
                           CE_TEST_OUT_DIR, CE_TEST_OUT_DIR);
    write_file("garment_batch_list.txt", NULL, (const uint8_t *)text, len);
    free(mem);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_pink_pants);
    RUN_TEST(test_cast_shadow);
    RUN_TEST(test_striped_shirt);
    RUN_TEST(test_dress_fuses);
    RUN_TEST(test_sky_shadow);
    RUN_TEST(test_print_dress_shadow);
    RUN_TEST(test_tie_dye);
    RUN_TEST(test_empty_region);
    RUN_TEST(test_determinism);
    RUN_TEST(test_garment_regions_geometry);
    RUN_TEST(test_errors_do_not_write);
    RUN_TEST(test_debug_layers_consistent);
    RUN_TEST(test_analyze_and_null_map);
    RUN_TEST(test_real_pants_palette_bands);
    RUN_TEST(test_parity_hash);
    RUN_TEST(test_timing_1024);
    RUN_TEST(test_write_cli_fixtures);
    return UNITY_END();
}
