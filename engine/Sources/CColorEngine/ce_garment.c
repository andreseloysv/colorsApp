/*
 * ce_garment.c — paleta por prenda: un color por prenda lisa (requisito del
 * usuario, CONTEXT §13: "el pantalón es de un solo color").
 *
 * Por región de prenda (mapa de ce_mask_garment_regions: 1 arriba, 2 abajo):
 * histograma, MMCQ y Lloyd como ce_palette_extract con solo los píxeles de la
 * región; los centros que son el mismo color con distinta luz se agrupan por
 * distancia sobre "compatible" (ΔE00 con kL = shade_kL < shade_merge_de, o las
 * fusiones de ce_palette_opts, sin superar el límite de luminancia
 * CE_GARMENT_SHADE_MIN_RATIO; o bien el mismo material con distinta luz —sombra
 * neutra c ≈ s·a o sombra cromática de exterior c ≈ s·(a + w·S·a), acotadas por
 * CE_GARMENT_SHADE_S_MIN—), con la cadena controlada por ENLACE COMPLETO o por
 * ESTRELLA DE SOMBRA alrededor del tono más luminoso (nada se encadena por
 * transitividad), y cada grupo se representa con su tono iluminado (media en Lab
 * de los bins de color entre los percentiles lit_low_pct y lit_high_pct de L* de
 * su NÚCLEO: peso >= CE_GARMENT_LIT_CORE_FRACTION del mayor y, de esos, el nivel
 * de luz de arriba, CE_GARMENT_LIT_Y_RATIO). Un segundo color solo si pesa
 * >= secondary_min_share en su región (o >= CE_GARMENT_GRADIENT_MIN_SHARE si es
 * el extremo de un degradado de color) y no es agrupable con el primero. Si
 * arriba y abajo son agrupables (vestido, mono) se recalcula con la unión como
 * prenda entera (región 3). Contrato completo en ce.h.
 *
 * Determinismo: bins en orden de índice, uniones por distancia ascendente con
 * empates por índice, sin RNG ni estáticos mutables;
 * ΔE00 y Lab pasan por ce_libm (mismos bits en nativo y WASM). Sin malloc: el
 * estado vive en el contexto (región por píxel reducido, cluster por píxel e
 * histograma de L*).
 *
 * Reglas: C11, sin I/O, sin malloc, todo en double, sin contracción FMA.
 */
#include "ce_internal.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>

#pragma STDC FP_CONTRACT OFF

_Static_assert(CE_GARMENT_MAX_REGIONS >= 1 && CE_GARMENT_MAX_REGIONS <= 7,
               "las etiquetas de región deben caber en la máscara de bits de selección");
_Static_assert(CE_PALETTE_K_MAX <= 64, "los miembros de un color son una máscara de 64 bits");
_Static_assert(CE_PALETTE_K_MAX <= 127, "hist_center es int8_t");

/* Destino de un grupo durante la selección (interno). */
#define CE_GROUP_NONE (-1)      /* aún sin decidir */
#define CE_GROUP_DISCARDED (-2) /* cuota < min_weight o < secondary_min_share */
#define CE_GROUP_TRUNCATED (-3) /* sin hueco (max_colors_per_region) */
#define CE_GROUP_MIXTURE (-4)   /* tono de mezcla entre otros dos grupos (borde de estampado) */

/* Por qué se pueden unir dos clusters (valores de ctx->shade_ok). */
#define CE_GARMENT_PAIR_GROUPABLE 1u /* ΔE00(kL = shade_kL) u otra fusión: con límite de luminancia */
#define CE_GARMENT_PAIR_SHADE 2u     /* mismo material con distinta luz: sin límite de luminancia */



void ce_garment_opts_default(ce_garment_opts *o)
{
    if (o == NULL) {
        return;
    }
    /* Calibrados en engine/BENCHLOG.md ("Paleta por prenda"): centro de la meseta
     * kL 3 × shade_merge_de 5,5-7 (114/115 composiciones con los colores exactos,
     * 0 fusiones erróneas, rayas intactas) y percentiles 0,75-0,95 (ΔE00 al tono
     * iluminado verdadero p50 0,31 / p90 1,51 frente a 0,49 / 3,27 con 0,60-0,90,
     * dejando fuera el 5 % más claro por los especulares). */
    o->shade_kL = 3.0;
    o->shade_merge_de = 6.5;
    o->lit_low_pct = 0.75;
    o->lit_high_pct = 0.95;
    o->secondary_min_share = 0.25;
    o->max_colors_per_region = 2;
}

static int ce_garment_opts_valid(const ce_garment_opts *o)
{
    /* Las comparaciones con NaN son falsas: NaN queda fuera de rango. */
    if (!(isfinite(o->shade_kL) && o->shade_kL > 0.0)) return 0;
    if (!isfinite(o->shade_merge_de)) return 0;
    if (!(o->lit_low_pct >= 0.0 && o->lit_low_pct <= 1.0)) return 0;
    if (!(o->lit_high_pct >= o->lit_low_pct && o->lit_high_pct <= 1.0)) return 0;
    if (!(o->secondary_min_share >= 0.0 && o->secondary_min_share <= 1.0)) return 0;
    if (o->max_colors_per_region < 1 || o->max_colors_per_region > CE_PALETTE_MAX_COLORS) return 0;
    return 1;
}

/* "Agrupable": el mismo color con distinta luz (ver ce_garment_opts). */
static int ce_garment_groupable(ce_lab a, ce_lab b, const ce_palette_opts *po, const ce_garment_opts *go)
{
    if (po->merge_de > 0.0 && ce_de2000(a, b) < po->merge_de) {
        return 1;
    }
    if (go->shade_merge_de > 0.0 && ce_de2000_k(a, b, go->shade_kL, 1.0, 1.0) < go->shade_merge_de) {
        return 1;
    }
    if (po->merge_light_de > 0.0
        && ce_de2000_k(a, b, CE_PALETTE_LIGHT_MERGE_KL, 1.0, 1.0) < po->merge_light_de) {
        return 1;
    }
    return 0;
}

/* "Fusionable" (arriba y abajo son la misma prenda): se comparan TONOS
 * ILUMINADOS, que ya no tienen sombras, así que no se vuelve a tolerar L*:
 * ΔE00 (kL = kC = kH = 1) < shade_merge_de, o < merge_de. Con la tolerancia a
 * L* de la agrupación (kL = shade_kL) una camiseta azul marino y un vaquero
 * (ΔE00 16,8) se fusionaban: barrido en engine/BENCHLOG.md. */
static int ce_garment_fusable_pair(ce_lab a, ce_lab b, const ce_palette_opts *po, const ce_garment_opts *go)
{
    const double d = ce_de2000(a, b);
    return (po->merge_de > 0.0 && d < po->merge_de) || (go->shade_merge_de > 0.0 && d < go->shade_merge_de);
}

/* Núcleo de un conjunto de clusters para el TONO ILUMINADO, en dos filtros:
 *
 *  (1) PESO: los que pesan >= CE_GARMENT_LIT_CORE_FRACTION veces el más pesado del
 *      conjunto. Deja fuera los brillos especulares y los tonos de borde de un
 *      estampado (pocos píxeles, más claros que el fondo oscuro), que si no
 *      desplazarían el tono del color oscuro.
 *  (2) NIVEL DE LUZ: de esos, los que están a menos de un paso de luz del más
 *      luminoso (Y con suelo >= CE_GARMENT_LIT_Y_RATIO veces la mayor). Sin este
 *      filtro, una prenda con media sombra encima mete la sombra en el histograma
 *      y los percentiles lit_low_pct..lit_high_pct del grupo entero caen dentro
 *      del tono de la sombra: el tono iluminado se oscurecía ~1 ΔE00 por cada paso
 *      de sombra (tabla en engine/BENCHLOG.md).
 *
 * El núcleo nunca queda vacío: el cluster más pesado cumple los dos filtros. */
static uint64_t ce_garment_core(const ce_ctx *ctx, const int *center_of_local, uint64_t members, int n_local)
{
    double wmax = 0.0, ymax = 0.0;
    uint64_t core = 0u, wcore = 0u;
    int l;
    for (l = 0; l < n_local; ++l) {
        if (((members >> l) & 1u) != 0u && ctx->centers[center_of_local[l]].wsum > wmax) {
            wmax = ctx->centers[center_of_local[l]].wsum;
        }
    }
    for (l = 0; l < n_local; ++l) {
        if (((members >> l) & 1u) != 0u
            && !(ctx->centers[center_of_local[l]].wsum < CE_GARMENT_LIT_CORE_FRACTION * wmax)) {
            const double y = ce_lab_to_xyz(ctx->centers[center_of_local[l]].lab).Y + CE_GARMENT_SHADE_Y_FLOOR;
            wcore |= (uint64_t)1u << l;
            if (y > ymax) {
                ymax = y;
            }
        }
    }
    for (l = 0; l < n_local; ++l) {
        if (((wcore >> l) & 1u) != 0u
            && !(ce_lab_to_xyz(ctx->centers[center_of_local[l]].lab).Y + CE_GARMENT_SHADE_Y_FLOOR
                 < CE_GARMENT_LIT_Y_RATIO * ymax)) {
            core |= (uint64_t)1u << l;
        }
    }
    return core;
}

/* c es el color `a` escalado en luz lineal: c ≈ s·a en XYZ (s de mínimos
 * cuadrados, acotada a [smin, 1/smin]) a ΔE00 < tol. Es el modelo físico de una
 * sombra: la misma reflectancia con menos luz. */
static int ce_garment_scaled_fit(ce_xyz c, ce_lab clab, ce_xyz a, double smin, double tol)
{
    const double aa = a.X * a.X + a.Y * a.Y + a.Z * a.Z;
    double sc;
    ce_xyz m;
    if (!(aa > 0.0)) {
        return 0;
    }
    sc = (c.X * a.X + c.Y * a.Y + c.Z * a.Z) / aa;
    if (!(sc >= smin && sc <= 1.0 / smin)) {
        return 0;
    }
    m.X = sc * a.X;
    m.Y = sc * a.Y;
    m.Z = sc * a.Z;
    return ce_de2000(clab, ce_xyz_to_lab(m)) < tol;
}

/* c es el color `a` con otra cantidad de luz dentro del límite de luminancia de
 * la agrupación de tonos. Una mezcla con el negro es indistinguible de una
 * sombra: se trata como sombra. */
static int ce_garment_is_shade_of(ce_xyz c, ce_lab clab, ce_xyz a)
{
    return ce_garment_scaled_fit(c, clab, a, CE_GARMENT_SHADE_MIN_RATIO, CE_GARMENT_MIXTURE_DE);
}

/* Cambio de iluminante sol -> cielo en XYZ: S = M⁻¹·diag(g−1)·M con M el CAT de
 * Bradford y g el blanco de cielo (CIE D 12000 K) sobre el de escena (CIE D
 * 5500 K) en conos, normalizado al canal M. Derivada con colour-science; la
 * recalcula y compara a 1e-9 oracle/tests/test_garments.py::test_sky_matrix.
 * Row-major. */
static const double CE_GARMENT_SKY_M[9] = {
    -0.108448483922, -0.041594534799, 0.140178512850,
    -0.048088512866, -0.017183406768, 0.045840298474,
     0.028381857168, -0.047968733215, 0.725192613222
};

/* Dirección del azuleo de la sombra para la luz `a`: S·a (orden de suma fijo). */
static ce_xyz ce_garment_sky_dir(ce_xyz a)
{
    ce_xyz u;
    u.X = CE_GARMENT_SKY_M[0] * a.X + CE_GARMENT_SKY_M[1] * a.Y + CE_GARMENT_SKY_M[2] * a.Z;
    u.Y = CE_GARMENT_SKY_M[3] * a.X + CE_GARMENT_SKY_M[4] * a.Y + CE_GARMENT_SKY_M[5] * a.Z;
    u.Z = CE_GARMENT_SKY_M[6] * a.X + CE_GARMENT_SKY_M[7] * a.Y + CE_GARMENT_SKY_M[8] * a.Z;
    return u;
}

/* SOMBRA CROMÁTICA DE EXTERIOR (modelo (2) de ce.h): c es la luz `a` bajo la
 * sombra abierta, donde solo llega el cielo azul: c ≈ s·(a + w·S·a) con (s, α =
 * s·w) de mínimos cuadrados (dos incógnitas, tres ecuaciones: el residuo sigue
 * discriminando), s en [CE_GARMENT_SHADE_S_MIN, 1] y la intensidad de la
 * adaptación w acotada por la física (nunca más azul que la sombra abierta, y el
 * azuleo no crece si la luminancia apenas cae). `a` debe ser el más luminoso. */
static int ce_garment_sky_fit(ce_xyz c, ce_lab clab, ce_xyz a)
{
    const ce_xyz u = ce_garment_sky_dir(a);
    const double aa = a.X * a.X + a.Y * a.Y + a.Z * a.Z;
    const double au = a.X * u.X + a.Y * u.Y + a.Z * u.Z;
    const double uu = u.X * u.X + u.Y * u.Y + u.Z * u.Z;
    const double ca = c.X * a.X + c.Y * a.Y + c.Z * a.Z;
    const double cu = c.X * u.X + c.Y * u.Y + c.Z * u.Z;
    const double det = aa * uu - au * au;
    double s, alpha, w, wmax;
    ce_xyz m;

    if (!(det > 0.0)) {
        return 0; /* u paralelo a a (o a nulo): sin información cromática */
    }
    s = (ca * uu - cu * au) / det;
    alpha = (aa * cu - au * ca) / det;
    if (!(s >= CE_GARMENT_SHADE_S_MIN && s <= 1.0)) {
        return 0;
    }
    w = alpha / s;
    wmax = CE_GARMENT_SKY_W_SLOPE * (1.0 - s) / s;
    if (wmax > CE_GARMENT_SKY_W_MAX) {
        wmax = CE_GARMENT_SKY_W_MAX;
    }
    if (!(w >= 0.0 && w <= wmax)) {
        return 0;
    }
    m.X = s * a.X + alpha * u.X;
    m.Y = s * a.Y + alpha * u.Y;
    m.Z = s * a.Z + alpha * u.Z;
    if (!(m.X > 0.0 && m.Y > 0.0 && m.Z > 0.0)) {
        return 0;
    }
    return ce_de2000(clab, ce_xyz_to_lab(m)) < CE_GARMENT_SHADE_LIT_DE;
}

/* Los dos colores son el mismo tejido con distinta luz: sombra neutra (escala
 * pura en XYZ, los dos sentidos en orden fijo) o sombra cromática de exterior
 * (adaptación parcial al cielo, solo del más luminoso al más oscuro). Los dos
 * modelos con la misma tolerancia y el mismo límite de profundidad; contrato y
 * límites conocidos en ce.h (CE_GARMENT_SHADE_S_MIN). */
static int ce_garment_same_material(ce_lab a, ce_lab b)
{
    const ce_xyz ax = ce_lab_to_xyz(a);
    const ce_xyz bx = ce_lab_to_xyz(b);
    if (ce_garment_scaled_fit(bx, b, ax, CE_GARMENT_SHADE_S_MIN, CE_GARMENT_SHADE_LIT_DE)
        || ce_garment_scaled_fit(ax, a, bx, CE_GARMENT_SHADE_S_MIN, CE_GARMENT_SHADE_LIT_DE)) {
        return 1;
    }
    return (ax.Y >= bx.Y) ? ce_garment_sky_fit(bx, b, ax) : ce_garment_sky_fit(ax, a, bx);
}

/* Los dos tonos iluminados se separan de verdad en croma y tono (no es una
 * sombra, que solo cambia L*): extremos de un degradado de color. */
static int ce_garment_hue_apart(ce_lab a, ce_lab b)
{
    return ce_de2000_k(a, b, CE_GARMENT_HUE_KL, 1.0, 1.0) >= CE_GARMENT_GRADIENT_HUE_DE;
}

/* Bit más bajo de una máscara de miembros (la máscara nunca es 0 aquí). */
static int ce_lowest_bit(uint64_t m)
{
    int i = 0;
    while (((m >> i) & 1u) == 0u) {
        ++i;
    }
    return i;
}

/* Enlace COMPLETO: todos los pares cruzados de los dos grupos son compatibles.
 * `compat[u]` tiene el bit v si el par (u, v) puede ser el mismo color. */
static int ce_garment_clique(const uint64_t *compat, uint64_t mi, uint64_t mj)
{
    uint64_t m = mi;
    while (m != 0u) {
        const int u = ce_lowest_bit(m);
        if ((compat[u] & mj) != mj) {
            return 0;
        }
        m &= m - 1u;
    }
    return 1;
}

/* ESTRELLA DE SOMBRA alrededor del TONO MÁS LUMINOSO del conjunto (empate: índice
 * menor): todos los demás miembros son el MISMO MATERIAL con distinta luz que ese
 * ancla (`same_mat`). Es el segundo camino para unir dos grupos, y es el físico:
 * una prenda bajo una sola luz tiene UN tono al sol y el resto son ese tono con
 * menos luz, así que todo el grupo se explica con un único iluminante. Hace falta
 * porque el modelo de sombra se define desde la LUZ: dos penumbras intermedias de
 * la misma rampa (una sombra azul con su transición) no siempre se ajustan entre
 * ELLAS —la cota del azuleo, CE_GARMENT_SKY_W_SLOPE·(1−s)/s, supone que `a` es el
 * tono al sol— aunque las dos se ajusten perfectamente al tono al sol. No encadena
 * por transitividad: no basta una cadena de vecinos, todo miembro tiene que ser una
 * sombra del MISMO ancla (el fondo marino de un estampado no es una sombra de su
 * motivo blanco, s = 0,012 < CE_GARMENT_SHADE_S_MIN, así que nunca entran juntos). */
static int ce_garment_shade_star(const ce_xyz *cxyz, const uint64_t *same_mat, uint64_t members)
{
    uint64_t m = members;
    int anchor = -1;
    while (m != 0u) {
        const int u = ce_lowest_bit(m);
        if (anchor < 0 || cxyz[u].Y > cxyz[anchor].Y) {
            anchor = u;
        }
        m &= m - 1u;
    }
    if (anchor < 0) {
        return 0;
    }
    return (same_mat[anchor] & members) == (members & ~((uint64_t)1u << anchor));
}

/* Media de los píxeles con máscara > 0 de la imagen ORIGINAL, ponderada por la
 * máscara, en orden de índice y con acumuladores enteros (mismos bits en nativo y
 * WASM). Reserva cuando la máscara tiene píxeles pero el mapa de regiones no cubre
 * ninguno: la media de toda la reducida (ce_palette_fallback_mean) devolvería el
 * color del FONDO, que es justo el fallo del que se quejó el usuario (CONTEXT §12).
 * Devuelve 0 (sin escribir) si no hay máscara o no tiene píxeles > 0. */
static int ce_garment_mask_mean(const ce_image *img, ce_swatch *out)
{
    const int bpp = ce_image_bpp(img->fmt);
    const size_t stride = (size_t)img->stride_bytes;
    uint64_t sr = 0, sg = 0, sb = 0, sm = 0;
    int x, y;
    if (img->mask == NULL) {
        return 0;
    }
    for (y = 0; y < img->height; ++y) {
        const uint8_t *row = img->pixels + (size_t)y * stride;
        const uint8_t *mrow = img->mask + (size_t)y * (size_t)img->width;
        for (x = 0; x < img->width; ++x) {
            const uint64_t m = (uint64_t)mrow[x];
            const uint8_t *p = row + (size_t)x * (size_t)bpp;
            if (m == 0u) {
                continue;
            }
            sr += m * (uint64_t)p[0];
            sg += m * (uint64_t)p[1];
            sb += m * (uint64_t)p[2];
            sm += m;
        }
    }
    if (sm == 0u) {
        return 0;
    }
    out->lab = ce_srgb_to_lab((double)sr / (double)sm / 255.0, (double)sg / (double)sm / 255.0,
                              (double)sb / (double)sm / 255.0);
    ce_lab_to_srgb8(out->lab, &out->rgb[0], &out->rgb[1], &out->rgb[2]);
    out->weight = 1.0;
    return 1;
}

/* El cluster `l` no llega al peso mínimo `wmin` (peso propio más el recibido de
 * tonos de mezcla): no puede ser EXTREMO de una mezcla. Los dos extremos de un
 * borde son áreas de verdad de la prenda; un cluster de cuatro píxeles de borde o
 * de ruido no lo es, y tomarlo por extremo convertía la sombra entera en "mezcla"
 * (y su peso en el de un color falso). */
static int ce_garment_thin(const ce_ctx *ctx, const int *center_of_local, const double *extra, int l, double wmin)
{
    return ctx->centers[center_of_local[l]].wsum + extra[l] < wmin;
}

/* Un tramo de luminancias [lo, hi] puede ser el mismo tejido con luz y sombra. */
static int ce_garment_span_ok(double lo, double hi)
{
    return !(lo < CE_GARMENT_SHADE_MIN_RATIO * hi);
}

/* Un color elegido de una región. */
typedef struct ce_garment_color {
    ce_lab lab;       /* tono iluminado (se recalcula al absorber otro grupo) */
    ce_lab anchor;    /* tono iluminado del PRIMER grupo del color, que nunca cambia */
    double wsum;      /* peso de sus clusters */
    uint64_t members; /* clusters locales de la pasada (bits 0..63) */
    int head;         /* cluster local de índice menor */
    double y_lo;      /* luminancia con suelo mínima y máxima de sus clusters */
    double y_hi;
} ce_garment_color;

/* Resultado de una pasada (una región o la unión). */
typedef struct ce_garment_region {
    int region;       /* CE_GARMENT_REGION_* de la salida */
    double total;     /* Σ pesos de sus píxeles */
    int n;            /* colores elegidos */
    int n_clusters;   /* clusters registrados en dbg.clusters desde c0 */
    ce_garment_color colors[CE_PALETTE_MAX_COLORS];
} ce_garment_region;

/* Bin de L* (ancho 100 / CE_GARMENT_L_BINS) del histograma del tono iluminado. */
static int ce_garment_lbin(double L)
{
    const double v = L * ((double)CE_GARMENT_L_BINS / 100.0);
    if (!(v > 0.0)) {
        return 0;
    }
    if (v >= (double)(CE_GARMENT_L_BINS - 1)) {
        return CE_GARMENT_L_BINS - 1;
    }
    return (int)v;
}

static int ce_popcount64(uint64_t v)
{
    int n = 0;
    while (v != 0u) {
        v &= v - 1u;
        ++n;
    }
    return n;
}

/* Tono iluminado de los clusters `members` (locales) con el histograma vivo de
 * la pasada: percentiles lit_low_pct..lit_high_pct de L* ponderados y media en
 * Lab de los bins de color dentro de ese intervalo. */
static ce_lab ce_garment_lit(ce_ctx *ctx, const int8_t *local_of_center, uint64_t members,
                             const ce_garment_opts *go)
{
    double *lh = ctx->lit_hist;
    double total = 0.0, acc = 0.0, target_lo, target_hi, sw = 0.0, sL = 0.0, sa = 0.0, sb = 0.0;
    int b, i, blo = -1, bhi = -1;
    ce_lab out;

    for (b = 0; b < CE_GARMENT_L_BINS; ++b) {
        lh[b] = 0.0;
    }
    for (i = 0; i < CE_HIST_BINS; ++i) {
        const ce_hist_bin *bin = &ctx->hist[i];
        const int c = ctx->hist_center[i];
        int l;
        if (!(bin->wsum > 0.0) || c < 0 || c >= CE_PALETTE_K_MAX) {
            continue;
        }
        l = local_of_center[c];
        if (l < 0 || ((members >> l) & 1u) == 0u) {
            continue;
        }
        lh[ce_garment_lbin(bin->c[0])] += bin->wsum;
    }
    for (b = 0; b < CE_GARMENT_L_BINS; ++b) {
        total += lh[b];
    }
    /* h <= 1 => h · total <= total: la suma acumulada (mismo orden que total)
     * siempre alcanza target_hi en el último bin no vacío. */
    target_lo = go->lit_low_pct * total;
    target_hi = go->lit_high_pct * total;
    for (b = 0; b < CE_GARMENT_L_BINS; ++b) {
        if (!(lh[b] > 0.0)) {
            continue;
        }
        acc += lh[b];
        if (blo < 0 && acc >= target_lo) {
            blo = b;
        }
        if (acc >= target_hi) {
            bhi = b;
            break;
        }
    }
    if (bhi < 0) {
        bhi = CE_GARMENT_L_BINS - 1; /* inalcanzable con total > 0 */
    }
    if (blo < 0 || blo > bhi) {
        blo = bhi;
    }
    for (i = 0; i < CE_HIST_BINS; ++i) {
        const ce_hist_bin *bin = &ctx->hist[i];
        const int c = ctx->hist_center[i];
        int l, lb;
        if (!(bin->wsum > 0.0) || c < 0 || c >= CE_PALETTE_K_MAX) {
            continue;
        }
        l = local_of_center[c];
        if (l < 0 || ((members >> l) & 1u) == 0u) {
            continue;
        }
        lb = ce_garment_lbin(bin->c[0]);
        if (lb < blo || lb > bhi) {
            continue;
        }
        sw += bin->wsum;
        sL += bin->wsum * bin->c[0];
        sa += bin->wsum * bin->c[1];
        sb += bin->wsum * bin->c[2];
    }
    if (sw > 0.0) {
        out.L = sL / sw;
        out.a = sa / sw;
        out.b = sb / sw;
    } else {
        out.L = 0.0; /* inalcanzable: todo cluster no vacío tiene bins */
        out.a = 0.0;
        out.b = 0.0;
    }
    return out;
}

static int ce_uf_find(int *parent, int x)
{
    while (parent[x] != x) {
        x = parent[x];
    }
    return x;
}

/*
 * Una pasada: región(es) `sel` (bits de etiqueta), etiqueta de salida
 * `region_out`, k centros iniciales, clusters registrados desde `c0` en
 * dbg.clusters. `cluster_code[c0 + l]` recibe `pass_code + color` (o -1) para
 * que el llamante asigne el índice final tras ordenar.
 */
static void ce_garment_pass(ce_ctx *ctx, unsigned sel, int region_out, int k, int c0, int pass_code,
                            const ce_palette_opts *po, const ce_garment_opts *go, ce_garment_region *res,
                            int *cluster_code, int *lloyd_iterations)
{
    int8_t local_of_center[CE_PALETTE_K_MAX];
    int center_of_local[CE_PALETTE_K_MAX];
    int parent[CE_PALETTE_K_MAX];
    uint64_t compat[CE_PALETTE_K_MAX];   /* pares que pueden ser el mismo color (enlace completo) */
    uint64_t same_mat[CE_PALETTE_K_MAX]; /* pares que son el mismo material con distinta luz */
    uint64_t gmask[CE_PALETTE_K_MAX];    /* miembros del grupo, por raíz */
    uint64_t mix_link[CE_PALETTE_K_MAX]; /* extremos unidos por un tono de mezcla (degradado) */
    double y_lo[CE_PALETTE_K_MAX], y_hi[CE_PALETTE_K_MAX]; /* por raíz de grupo */
    double extra[CE_PALETTE_K_MAX];                         /* peso recibido de tonos de mezcla */
    ce_xyz cxyz[CE_PALETTE_K_MAX];
    int group_state[CE_PALETTE_K_MAX]; /* por cabeza: color elegido o CE_GROUP_* */
    int order[CE_PALETTE_K_MAX];
    double gw[CE_PALETTE_K_MAX];
    const size_t npx = (size_t)ctx->reduced_w * (size_t)ctx->reduced_h;
    double total, group_total = 0.0;
    int nboxes, it, j, i, l, n_local = 0, n_groups = 0;
    size_t p;

    res->region = region_out;
    res->total = 0.0;
    res->n = 0;
    res->n_clusters = 0;
    for (j = 0; j < CE_PALETTE_K_MAX; ++j) {
        local_of_center[j] = -1;
    }

    ce_hist_clear(ctx);
    ce_hist_accumulate_labels(ctx, sel);
    total = ce_hist_finalize(ctx);
    nboxes = (total > 0.0) ? ce_mmcq(ctx, k) : 0;
    if (nboxes < 1) {
        for (p = 0; p < npx; ++p) {
            const unsigned label = ctx->region_label[p];
            if (label <= 7u && ((sel >> label) & 1u) != 0u) {
                ctx->pixel_cluster[p] = (uint8_t)CE_LABEL_NONE;
            }
        }
        return;
    }
    res->total = total;
    ce_assign_from_boxes(ctx, nboxes);
    ce_lloyd_update(ctx, nboxes);
    for (it = 0; it < po->max_iters; ++it) {
        if (!ce_lloyd_assign(ctx, nboxes)) {
            break;
        }
        ce_lloyd_update(ctx, nboxes);
    }
    *lloyd_iterations += it;

    /* Centros no vacíos en orden de índice -> clusters locales y de depuración. */
    for (j = 0; j < nboxes && c0 + n_local < CE_PALETTE_K_MAX; ++j) {
        const ce_center *ce = &ctx->centers[j];
        ce_cluster_debug *cd;
        if (!(ce->wsum > 0.0)) {
            continue;
        }
        local_of_center[j] = (int8_t)n_local;
        center_of_local[n_local] = j;
        cd = &ctx->dbg.clusters[c0 + n_local];
        cd->lab = ce->lab;
        ce_lab_to_srgb8(ce->lab, &cd->rgb[0], &cd->rgb[1], &cd->rgb[2]);
        cd->weight = ce->wsum; /* se normaliza al final */
        cd->fate = CE_FATE_DISCARDED;
        cd->final_index = -1;
        cd->group_head = c0 + n_local;
        ctx->garment.cluster_region[c0 + n_local] = (uint8_t)region_out;
        cluster_code[c0 + n_local] = -1;
        ++n_local;
    }
    res->n_clusters = n_local;

    /* Tonos de mezcla (por cluster): un cluster cuyo centro (XYZ lineal) está a
     * ΔE00 < CE_GARMENT_MIXTURE_DE de t·A + (1 − t)·B, con t en
     * [CE_GARMENT_MIXTURE_T_MIN, 1 − CE_GARMENT_MIXTURE_T_MIN], son píxeles del
     * borde entre dos colores (estampado desenfocado): no entra en ningún grupo y
     * su peso pasa a A (t) y a B (1 − t). A y B tienen que ser colores DISTINTOS
     * (ni el mismo material bajo los dos modelos de sombra —`same_mat`—, ni un par
     * dentro del límite de luminancia con croma y tono a ΔE00(kL =
     * CE_GARMENT_HUE_KL) < shade_merge_de), no ser sombras del propio cluster
     * (ce_garment_is_shade_of) y pesar >= min_weight de la región
     * (ce_garment_thin). Clusters en orden de peso ascendente (empate: índice
     * menor); entre los pares aún no marcados, el de menor ΔE00 (empates: índices
     * menores). Contrato completo en ce.h (CE_GARMENT_MIXTURE_DE). */
    for (l = 0; l < n_local; ++l) {
        const ce_lab lab = ctx->centers[center_of_local[l]].lab;
        parent[l] = l;
        gw[l] = 0.0;
        extra[l] = 0.0;
        group_state[l] = CE_GROUP_NONE;
        cxyz[l] = ce_lab_to_xyz(lab);
        y_lo[l] = y_hi[l] = cxyz[l].Y + CE_GARMENT_SHADE_Y_FLOOR;
        compat[l] = (uint64_t)1u << l;
        same_mat[l] = 0u;
        gmask[l] = (uint64_t)1u << l;
        mix_link[l] = 0u;
    }
    /* Mismo material con distinta luz, para TODOS los pares y una sola vez: lo usan
     * el paso 3a (un par así nunca son los dos extremos de una mezcla: lo que hay
     * entre la luz y la sombra es penumbra, el mismo tejido con luz intermedia) y
     * el paso 3b (compatibilidad sin límite de luminancia). Simétrico por
     * construcción (ce_garment_same_material ordena por luminancia). */
    if (go->shade_merge_de > 0.0) {
        for (i = 0; i < n_local; ++i) {
            for (j = i + 1; j < n_local; ++j) {
                if (ce_garment_same_material(ctx->centers[center_of_local[i]].lab,
                                             ctx->centers[center_of_local[j]].lab)) {
                    same_mat[i] |= (uint64_t)1u << j;
                    same_mat[j] |= (uint64_t)1u << i;
                }
            }
        }
    }
    if (CE_GARMENT_MIXTURE_DE > 0.0) {
        int visit[CE_PALETTE_K_MAX];
        int v;
        for (l = 0; l < n_local; ++l) {
            int pos = l;
            while (pos > 0 && ctx->centers[center_of_local[l]].wsum < ctx->centers[center_of_local[visit[pos - 1]]].wsum) {
                visit[pos] = visit[pos - 1];
                --pos;
            }
            visit[pos] = l;
        }
        for (v = 0; v < n_local; ++v) {
            const int c = visit[v];
            const ce_lab clab = ctx->centers[center_of_local[c]].lab;
            int ba = -1, bb = -1, a, b;
            double best_de = 0.0, best_t = 0.0;
            /* c es una sombra de ese cluster (escala pura dentro del límite de
             * luminancia): entonces c no es una mezcla, es el mismo tejido con
             * menos luz, y ese cluster no puede ser su extremo. */
            uint64_t shade_of = 0u;
            for (a = 0; a < n_local; ++a) {
                if (a != c && ce_garment_is_shade_of(cxyz[c], clab, cxyz[a])) {
                    shade_of |= (uint64_t)1u << a;
                }
            }
            for (a = 0; a < n_local; ++a) {
                if (a == c || group_state[a] == CE_GROUP_MIXTURE || ((shade_of >> a) & 1u) != 0u
                    || ce_garment_thin(ctx, center_of_local, extra, a, po->min_weight * total)) {
                    continue;
                }
                for (b = a + 1; b < n_local; ++b) {
                    double dx, dy, dz, dd, t, de;
                    ce_xyz m;
                    if (b == c || group_state[b] == CE_GROUP_MIXTURE || ((shade_of >> b) & 1u) != 0u
                        || ce_garment_thin(ctx, center_of_local, extra, b, po->min_weight * total)) {
                        continue;
                    }
                    if (((same_mat[a] >> b) & 1u) != 0u
                        || (ce_garment_span_ok(y_lo[a] < y_lo[b] ? y_lo[a] : y_lo[b], y_lo[a] > y_lo[b] ? y_lo[a] : y_lo[b])
                            && ce_de2000_k(ctx->centers[center_of_local[a]].lab, ctx->centers[center_of_local[b]].lab,
                                           CE_GARMENT_HUE_KL, 1.0, 1.0) < go->shade_merge_de)) {
                        continue; /* A y B son el mismo color con distinta luz: lo que hay entre
                                   * ellos es PENUMBRA (la misma tela con luz intermedia), no el
                                   * borde entre dos colores. Sin esto, la penumbra de una sombra
                                   * CROMÁTICA —que sí cae sobre el segmento A-B, porque una
                                   * oclusión parcial es una combinación lineal de los dos
                                   * iluminantes— se tomaba por mezcla y su mix_link vetaba el
                                   * único camino por el que el modelo de cielo puede agrupar. */
                    }
                    dx = cxyz[a].X - cxyz[b].X;
                    dy = cxyz[a].Y - cxyz[b].Y;
                    dz = cxyz[a].Z - cxyz[b].Z;
                    dd = dx * dx + dy * dy + dz * dz;
                    if (!(dd > 0.0)) {
                        continue;
                    }
                    t = ((cxyz[c].X - cxyz[b].X) * dx + (cxyz[c].Y - cxyz[b].Y) * dy + (cxyz[c].Z - cxyz[b].Z) * dz) / dd;
                    if (!(t >= CE_GARMENT_MIXTURE_T_MIN && t <= 1.0 - CE_GARMENT_MIXTURE_T_MIN)) {
                        continue;
                    }
                    m.X = cxyz[b].X + t * dx;
                    m.Y = cxyz[b].Y + t * dy;
                    m.Z = cxyz[b].Z + t * dz;
                    de = ce_de2000(clab, ce_xyz_to_lab(m));
                    if (de < CE_GARMENT_MIXTURE_DE && (ba < 0 || de < best_de)) {
                        ba = a;
                        bb = b;
                        best_de = de;
                        best_t = t;
                    }
                }
            }
            if (ba >= 0) {
                const double w = ctx->centers[center_of_local[c]].wsum + extra[c];
                extra[ba] += best_t * w;
                extra[bb] += (1.0 - best_t) * w;
                extra[c] = 0.0;
                group_state[c] = CE_GROUP_MIXTURE;
                /* A y B son los extremos de una variación de tono CONTINUA. */
                mix_link[ba] |= (uint64_t)1u << bb;
                mix_link[bb] |= (uint64_t)1u << ba;
            }
        }
    }

    /* Grupos sobre los pares "compatibles" de clusters que no son mezcla, en orden
     * de distancia (ΔE00 con kL = shade_kL; empates por i y luego j). Compatible =
     * "agrupable" (CE_GARMENT_PAIR_GROUPABLE, con el límite de luminancia al unir) o
     * el mismo material con distinta luz (CE_GARMENT_PAIR_SHADE: sombra neutra o
     * cromática, sin límite de luminancia porque una sombra proyectada de 4 pasos
     * oscurece 16 veces la luz lineal, pero acotada por CE_GARMENT_SHADE_S_MIN). Dos
     * grupos se unen si pasan UNO de los dos controles de cadena: ENLACE COMPLETO
     * (todos sus pares cruzados son compatibles) o ESTRELLA DE SOMBRA (todos los
     * miembros son el mismo material que el más luminoso de la unión). Ninguno
     * encadena por transitividad: con enlace simple, los tonos intermedios de un
     * estampado desenfocado unían un azul marino con su estampado blanco
     * (harness/people/02); con enlace completo el par extremo marino/blanco tiene
     * que ser compatible él mismo y con la estrella el marino tendría que ser una
     * sombra del blanco. La raíz es el índice menor. Distancias y pares en el
     * contexto (ctx->shade_dist, shade_ok). */
    for (i = 0; i < n_local; ++i) {
        for (j = i + 1; j < n_local; ++j) {
            const ce_lab a = ctx->centers[center_of_local[i]].lab;
            const ce_lab b = ctx->centers[center_of_local[j]].lab;
            uint8_t ok = 0u;
            if (group_state[i] != CE_GROUP_MIXTURE && group_state[j] != CE_GROUP_MIXTURE) {
                /* El límite de luminancia del par es condición del enlace "agrupable"
                 * (la unión de dos grupos vuelve a comprobarlo con el rango entero):
                 * sin esto, un par que solo comparte croma y tono —la fusión por luz
                 * de ce_palette_opts— entraba en la camarilla y dejaba que el fondo
                 * oscuro de un estampado se uniera con el motivo claro. */
                if (ce_garment_groupable(a, b, po, go)
                    && ce_garment_span_ok(y_lo[i] < y_lo[j] ? y_lo[i] : y_lo[j],
                                          y_hi[i] > y_hi[j] ? y_hi[i] : y_hi[j])) {
                    ok = CE_GARMENT_PAIR_GROUPABLE;
                } else if (go->shade_merge_de > 0.0 && ((mix_link[i] >> j) & 1u) == 0u
                           && ((same_mat[i] >> j) & 1u) != 0u) {
                    ok = CE_GARMENT_PAIR_SHADE; /* sombra: sin límite de luminancia */
                }
            }
            ctx->shade_ok[i * CE_PALETTE_K_MAX + j] = ok;
            ctx->shade_dist[i * CE_PALETTE_K_MAX + j] = ce_de2000_k(a, b, go->shade_kL, 1.0, 1.0);
            if (ok) {
                compat[i] |= (uint64_t)1u << j;
                compat[j] |= (uint64_t)1u << i;
            }
        }
    }
    for (;;) {
        int bi = -1, bj = -1;
        double best = 0.0;
        for (i = 0; i < n_local; ++i) {
            for (j = i + 1; j < n_local; ++j) {
                const double d = ctx->shade_dist[i * CE_PALETTE_K_MAX + j];
                const uint8_t ok = ctx->shade_ok[i * CE_PALETTE_K_MAX + j];
                int ri, rj;
                if (!ok || (bi >= 0 && !(d < best))) {
                    continue;
                }
                ri = ce_uf_find(parent, i);
                rj = ce_uf_find(parent, j);
                if (ri == rj
                    || (ok == CE_GARMENT_PAIR_GROUPABLE
                        && !ce_garment_span_ok(y_lo[ri] < y_lo[rj] ? y_lo[ri] : y_lo[rj],
                                               y_hi[ri] > y_hi[rj] ? y_hi[ri] : y_hi[rj]))
                    || !(ce_garment_clique(compat, gmask[ri], gmask[rj])
                         || ce_garment_shade_star(cxyz, same_mat, gmask[ri] | gmask[rj]))) {
                    continue;
                }
                bi = ri;
                bj = rj;
                best = d;
            }
        }
        if (bi < 0) {
            break;
        }
        {
            const int root = bi < bj ? bi : bj;
            const int other = bi < bj ? bj : bi;
            parent[other] = root;
            if (y_lo[other] < y_lo[root]) y_lo[root] = y_lo[other];
            if (y_hi[other] > y_hi[root]) y_hi[root] = y_hi[other];
            gmask[root] |= gmask[other];
            gmask[other] = 0u;
        }
    }
    for (l = 0; l < n_local; ++l) {
        parent[l] = ce_uf_find(parent, l);
        if (group_state[l] != CE_GROUP_MIXTURE) {
            gw[parent[l]] += ctx->centers[center_of_local[l]].wsum + extra[l];
        }
    }

    for (l = 0; l < n_local; ++l) {
        if (parent[l] == l && group_state[l] != CE_GROUP_MIXTURE) {
            int pos = n_groups++;
            /* Inserción: peso desc, cabeza asc (las cabezas llegan en orden asc). */
            while (pos > 0 && gw[l] > gw[order[pos - 1]]) {
                order[pos] = order[pos - 1];
                --pos;
            }
            order[pos] = l;
            group_total += gw[l];
        }
    }

    /* Selección de colores. */
    for (i = 0; i < n_groups; ++i) {
        const int h = order[i];
        const double share = gw[h] / group_total;
        uint64_t members = 0u;
        ce_lab lit;
        int s, found = -1;
        for (l = 0; l < n_local; ++l) {
            if (parent[l] == h) {
                members |= (uint64_t)1u << l;
            }
        }
        if (i > 0 && po->min_weight > 0.0 && share < po->min_weight) {
            group_state[h] = CE_GROUP_DISCARDED;
            continue;
        }
        lit = ce_garment_lit(ctx, local_of_center, ce_garment_core(ctx, center_of_local, members, n_local), go);
        for (s = 0; s < res->n; ++s) {
            const ce_garment_color *c = &res->colors[s];
            uint64_t mixed = 0u, mn = members;
            int ok_now, ok_anchor;
            while (mn != 0u) {
                mixed |= mix_link[ce_lowest_bit(mn)] & c->members;
                mn &= mn - 1u;
            }
            /* Contra el tono ACTUAL del color (que ya incluye lo absorbido) y contra
             * su ANCLA (el tono del primer grupo, que no se mueve): así los grupos
             * absorbidos forman una estrella alrededor del ancla y el tono no puede
             * ir derivando de uno en uno hasta el otro extremo de un estampado. */
            ok_now = (ce_garment_groupable(lit, c->lab, po, go)
                      && ce_garment_span_ok(y_lo[h] < c->y_lo ? y_lo[h] : c->y_lo,
                                            y_hi[h] > c->y_hi ? y_hi[h] : c->y_hi))
                     || (go->shade_merge_de > 0.0 && mixed == 0u && ce_garment_same_material(lit, c->lab));
            ok_anchor = ce_garment_groupable(lit, c->anchor, po, go)
                        || (go->shade_merge_de > 0.0 && mixed == 0u && ce_garment_same_material(lit, c->anchor));
            if (ok_now && ok_anchor) {
                found = s;
                break;
            }
        }
        if (found >= 0) {
            ce_garment_color *c = &res->colors[found];
            c->members |= members;
            c->wsum += gw[h];
            if (h < c->head) {
                c->head = h;
            }
            if (y_lo[h] < c->y_lo) c->y_lo = y_lo[h];
            if (y_hi[h] > c->y_hi) c->y_hi = y_hi[h];
            c->lab = ce_garment_lit(ctx, local_of_center, ce_garment_core(ctx, center_of_local, c->members, n_local), go);
            group_state[h] = found;
        } else {
            /* Cuota mínima de un color más: la normal, o la del EXTREMO DE UN
             * DEGRADADO de color (ver CE_GARMENT_GRADIENT_MIN_SHARE) cuando algún
             * cluster suyo y alguno de un color ya elegido son los dos extremos de
             * un tono de mezcla (variación de tono continua) y los dos tonos
             * iluminados se separan en croma y tono. */
            double min_share = go->secondary_min_share, mix_w = 0.0;
            uint64_t mm = members;
            while (mm != 0u) {
                mix_w += extra[ce_lowest_bit(mm)];
                mm &= mm - 1u;
            }
            /* Masa de tonos de mezcla del grupo: en un degradado de verdad los
             * tonos intermedios son buena parte de la prenda; en el borde de dos
             * prendas distintas son cuatro píxeles. */
            if (gw[h] > 0.0 && mix_w >= CE_GARMENT_GRADIENT_MIX_FRACTION * gw[h]) {
                for (s = 0; s < res->n && min_share > CE_GARMENT_GRADIENT_MIN_SHARE; ++s) {
                    const ce_garment_color *c = &res->colors[s];
                    uint64_t m = members;
                    while (m != 0u) {
                        const int u = ce_lowest_bit(m);
                        if ((mix_link[u] & c->members) != 0u && ce_garment_hue_apart(lit, c->lab)) {
                            min_share = CE_GARMENT_GRADIENT_MIN_SHARE;
                            break;
                        }
                        m &= m - 1u;
                    }
                }
            }
            if (res->n == 0 || (share >= min_share && res->n < go->max_colors_per_region)) {
                ce_garment_color *c = &res->colors[res->n];
                c->lab = lit;
                c->anchor = lit;
                c->wsum = gw[h];
                c->members = members;
                c->head = h;
                c->y_lo = y_lo[h];
                c->y_hi = y_hi[h];
                group_state[h] = res->n;
                ++res->n;
            } else {
                group_state[h] = (share >= min_share) ? CE_GROUP_TRUNCATED : CE_GROUP_DISCARDED;
            }
        }
    }

    /* Destino de cada cluster (el índice final lo pone el llamante). */
    for (l = 0; l < n_local; ++l) {
        ce_cluster_debug *cd = &ctx->dbg.clusters[c0 + l];
        const int st = group_state[parent[l]];
        if (st >= 0) {
            const int head = res->colors[st].head;
            cd->fate = (l == head) ? CE_FATE_KEPT : CE_FATE_MERGED;
            cd->group_head = c0 + head;
            cluster_code[c0 + l] = pass_code + st;
        } else {
            cd->fate = (st == CE_GROUP_TRUNCATED) ? CE_FATE_TRUNCATED : CE_FATE_DISCARDED;
            cd->group_head = c0 + parent[l];
        }
    }

    /* Cluster de cada píxel reducido de la pasada. */
    for (p = 0; p < npx; ++p) {
        const unsigned label = ctx->region_label[p];
        const uint8_t *px = ctx->reduced + p * 3u;
        int idx, c;
        if (label > 7u || ((sel >> label) & 1u) == 0u) {
            continue;
        }
        if (!(ctx->weights[p] > 0.0)) {
            ctx->pixel_cluster[p] = (uint8_t)CE_LABEL_NONE;
            continue;
        }
        idx = CE_HIST_INDEX(px[0] >> CE_HIST_SHIFT, px[1] >> CE_HIST_SHIFT, px[2] >> CE_HIST_SHIFT);
        c = ctx->hist_center[idx];
        l = (c >= 0 && c < CE_PALETTE_K_MAX) ? local_of_center[c] : -1;
        ctx->pixel_cluster[p] = (l >= 0) ? (uint8_t)(c0 + l) : (uint8_t)CE_LABEL_NONE;
    }
}

/* Arriba y abajo son la misma prenda: cada color de una región es agrupable
 * con alguno de la otra, en los dos sentidos. */
static int ce_garment_fusable(const ce_garment_region *a, const ce_garment_region *b, const ce_palette_opts *po,
                              const ce_garment_opts *go)
{
    int i, j;
    for (i = 0; i < a->n; ++i) {
        int any = 0;
        for (j = 0; j < b->n && !any; ++j) {
            any = ce_garment_fusable_pair(a->colors[i].lab, b->colors[j].lab, po, go);
        }
        if (!any) {
            return 0;
        }
    }
    for (j = 0; j < b->n; ++j) {
        int any = 0;
        for (i = 0; i < a->n && !any; ++i) {
            any = ce_garment_fusable_pair(b->colors[j].lab, a->colors[i].lab, po, go);
        }
        if (!any) {
            return 0;
        }
    }
    return 1;
}

#define CE_GARMENT_PASS_CODE 16 /* código de color = pasada · 16 + color (color < 8) */

int ce_palette_extract_garments(ce_ctx *ctx, const ce_image *img, const uint8_t *region_map, int n_regions,
                                const ce_palette_opts *po, const ce_garment_opts *go,
                                ce_garment_swatch *out, int cap)
{
    ce_palette_opts pdef;
    ce_garment_opts gdef;
    ce_garment_region reg[CE_GARMENT_MAX_REGIONS];
    int cluster_code[CE_PALETTE_K_MAX];
    int cand_pass[CE_GARMENT_MAX_REGIONS * CE_PALETTE_MAX_COLORS];
    int cand_color[CE_GARMENT_MAX_REGIONS * CE_PALETTE_MAX_COLORS];
    double cand_w[CE_GARMENT_MAX_REGIONS * CE_PALETTE_MAX_COLORS];
    int rc, n_passes, r, k, lloyd = 0, c0 = 0, n_max, n_cand = 0, n_out, i, j, c;
    size_t p, npx;
    double sigma_px = 0.0, grand = 0.0, wsum_out = 0.0, cluster_wsum = 0.0;

    if (ctx == NULL || img == NULL || out == NULL || cap < 1) {
        return CE_ERR_ARG;
    }
    if (region_map != NULL && (n_regions < 1 || n_regions > CE_GARMENT_MAX_REGIONS)) {
        return CE_ERR_ARG;
    }
    if (ctx->magic != CE_CTX_MAGIC) {
        return CE_ERR_CTX;
    }
    /* Cualquier llamada invalida las capas de depuración anteriores. */
    ctx->dbg.valid = 0;
    ctx->dbg.garment = 0;
    rc = ce_image_validate(img);
    if (rc != CE_OK) {
        return rc;
    }
    if (po == NULL) {
        ce_palette_opts_default(&pdef);
        po = &pdef;
    }
    if (go == NULL) {
        ce_garment_opts_default(&gdef);
        go = &gdef;
    }
    if (!ce_palette_opts_valid(po) || !ce_garment_opts_valid(go)) {
        return CE_ERR_OPTS;
    }
    n_max = po->max_colors < cap ? po->max_colors : cap;
    if (n_max > CE_PALETTE_MAX_COLORS) {
        n_max = CE_PALETTE_MAX_COLORS;
    }

    /* 1. Reducción con regiones y pesos (como ce_palette_extract). */
    ce_image_reduce_regions(ctx, img, region_map, n_regions, po->max_side);
    if (po->center_sigma > 0.0) {
        const int m = ctx->reduced_w < ctx->reduced_h ? ctx->reduced_w : ctx->reduced_h;
        const double sigma = po->center_sigma * (double)m;
        ce_image_apply_center_weight(ctx, sigma);
        if (sigma > 0.0 && isfinite(sigma)) {
            sigma_px = sigma;
        }
    }
    if (po->skin_rule != 0) {
        ce_image_apply_skin_rule(ctx);
    }
    npx = (size_t)ctx->reduced_w * (size_t)ctx->reduced_h;
    for (p = 0; p < npx; ++p) {
        ctx->pixel_cluster[p] = (uint8_t)CE_LABEL_NONE;
    }
    for (c = 0; c < CE_PALETTE_K_MAX; ++c) {
        cluster_code[c] = -1;
        ctx->garment.cluster_region[c] = 0;
    }
    ctx->garment.has_map = (region_map != NULL);
    ctx->garment.fused = 0;

    /* 2-5. Una pasada por región. */
    n_passes = (region_map != NULL) ? n_regions : 1;
    k = CE_PALETTE_K_MAX / n_passes;
    if (po->k_init < k) {
        k = po->k_init;
    }
    for (r = 1; r <= n_passes; ++r) {
        ce_garment_pass(ctx, 1u << r, (region_map != NULL) ? r : CE_GARMENT_REGION_NONE, k, c0,
                        (r - 1) * CE_GARMENT_PASS_CODE, po, go, &reg[r - 1], cluster_code, &lloyd);
        c0 += reg[r - 1].n_clusters;
        grand += reg[r - 1].total;
    }

    /* 6. Misma prenda arriba y abajo: se recalcula con la unión. */
    if (region_map != NULL && n_passes == 2 && reg[0].n > 0 && reg[1].n > 0
        && ce_garment_fusable(&reg[0], &reg[1], po, go)) {
        for (c = 0; c < CE_PALETTE_K_MAX; ++c) {
            cluster_code[c] = -1;
            ctx->garment.cluster_region[c] = 0;
        }
        ce_garment_pass(ctx, (1u << CE_GARMENT_REGION_UPPER) | (1u << CE_GARMENT_REGION_LOWER),
                        CE_GARMENT_REGION_WHOLE, po->k_init, 0, 0, po, go, &reg[0], cluster_code, &lloyd);
        c0 = reg[0].n_clusters;
        grand = reg[0].total;
        n_passes = 1;
        ctx->garment.fused = 1;
    }

    if (!(grand > 0.0)) {
        /* Ninguna región con peso: color medio de la máscara si la hay (nunca el del
         * fondo) y, sin máscara, el de la reducida como ce_palette_extract. */
        if (!ce_garment_mask_mean(img, &out[0].swatch)) {
            (void)ce_palette_fallback_mean(ctx, &out[0].swatch);
        }
        out[0].region = CE_GARMENT_REGION_NONE;
        out[0].region_share = 1.0;
        out[0].n_merged_clusters = 0;
        ctx->dbg.n_clusters = 0;
        for (c = 0; c < CE_PALETTE_K_MAX; ++c) {
            ce_cluster_debug *cd = &ctx->dbg.clusters[c];
            cd->lab.L = cd->lab.a = cd->lab.b = 0.0;
            cd->rgb[0] = cd->rgb[1] = cd->rgb[2] = 0;
            cd->weight = 0.0;
            cd->fate = 0;
            cd->final_index = 0;
            cd->group_head = 0;
        }
        ctx->dbg.lloyd_iterations = lloyd;
        ctx->dbg.n_swatches = 1;
        ctx->dbg.total_weight = 0.0;
        ctx->dbg.center_sigma_px = sigma_px;
        ctx->dbg.garment = 1;
        ctx->dbg.valid = 1;
        return 1;
    }

    /* 7. Pesos finales, orden (peso desc, pasada asc, color asc) y recorte. */
    for (r = 0; r < n_passes; ++r) {
        double sel_total = 0.0;
        const double region_share = reg[r].total / grand;
        for (j = 0; j < reg[r].n; ++j) {
            sel_total += reg[r].colors[j].wsum;
        }
        for (j = 0; j < reg[r].n; ++j) {
            const double w = region_share * (reg[r].colors[j].wsum / sel_total);
            int pos = n_cand++;
            while (pos > 0 && w > cand_w[pos - 1]) {
                cand_w[pos] = cand_w[pos - 1];
                cand_pass[pos] = cand_pass[pos - 1];
                cand_color[pos] = cand_color[pos - 1];
                --pos;
            }
            cand_w[pos] = w;
            cand_pass[pos] = r;
            cand_color[pos] = j;
        }
    }
    n_out = n_cand < n_max ? n_cand : n_max;
    for (i = 0; i < n_out; ++i) {
        wsum_out += cand_w[i];
    }
    for (i = 0; i < n_out; ++i) {
        const ce_garment_region *g = &reg[cand_pass[i]];
        const ce_garment_color *col = &g->colors[cand_color[i]];
        out[i].swatch.lab = col->lab;
        ce_lab_to_srgb8(col->lab, &out[i].swatch.rgb[0], &out[i].swatch.rgb[1], &out[i].swatch.rgb[2]);
        out[i].swatch.weight = cand_w[i] / wsum_out;
        out[i].region = g->region;
        out[i].region_share = g->total / grand;
        out[i].n_merged_clusters = ce_popcount64(col->members);
    }

    /* Capas de depuración: índice final de cada cluster y pesos normalizados. */
    for (c = 0; c < c0; ++c) {
        cluster_wsum += ctx->dbg.clusters[c].weight;
    }
    for (c = 0; c < c0; ++c) {
        ce_cluster_debug *cd = &ctx->dbg.clusters[c];
        int fi = -1;
        cd->weight = cluster_wsum > 0.0 ? cd->weight / cluster_wsum : 0.0;
        if (cluster_code[c] >= 0) {
            for (i = 0; i < n_out; ++i) {
                if (cand_pass[i] * CE_GARMENT_PASS_CODE + cand_color[i] == cluster_code[c]) {
                    fi = i;
                    break;
                }
            }
            if (fi < 0) {
                cd->fate = CE_FATE_TRUNCATED; /* recortado por max_colors / cap */
            }
        }
        cd->final_index = fi;
    }
    for (c = c0; c < CE_PALETTE_K_MAX; ++c) {
        ce_cluster_debug *cd = &ctx->dbg.clusters[c];
        cd->lab.L = cd->lab.a = cd->lab.b = 0.0;
        cd->rgb[0] = cd->rgb[1] = cd->rgb[2] = 0;
        cd->weight = 0.0;
        cd->fate = 0;
        cd->final_index = 0;
        cd->group_head = 0;
    }
    ctx->dbg.n_clusters = c0;
    ctx->dbg.lloyd_iterations = lloyd;
    ctx->dbg.n_swatches = n_out;
    ctx->dbg.total_weight = grand;
    ctx->dbg.center_sigma_px = sigma_px;
    ctx->dbg.garment = 1;
    ctx->dbg.valid = 1;
    return n_out;
}

int ce_analyze_garments(ce_ctx *ctx, const ce_image *img, const uint8_t *region_map, int n_regions,
                        const ce_palette_opts *po, const ce_garment_opts *go, const ce_match_opts *mo,
                        ce_result *out, ce_garment_swatch *garments, int cap)
{
    ce_match_opts def;
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    int n, rc, i;
    const int gcap = (garments == NULL) ? CE_PALETTE_MAX_COLORS : (cap < CE_PALETTE_MAX_COLORS ? cap : CE_PALETTE_MAX_COLORS);

    if (ctx == NULL || img == NULL || out == NULL || (garments != NULL && cap < 1)) {
        return CE_ERR_ARG;
    }
    if (region_map != NULL && (n_regions < 1 || n_regions > CE_GARMENT_MAX_REGIONS)) {
        return CE_ERR_ARG;
    }
    if (ctx->magic != CE_CTX_MAGIC) {
        return CE_ERR_CTX;
    }
    ctx->dbg.valid = 0;
    ctx->dbg.garment = 0;
    if (mo == NULL) {
        ce_match_opts_default(&def);
        mo = &def;
    }
    if (!ce_match_opts_valid(mo)) {
        return CE_ERR_OPTS;
    }
    n = ce_palette_extract_garments(ctx, img, region_map, n_regions, po, go, g, gcap);
    if (n < 0) {
        return n;
    }
    for (i = 0; i < CE_PALETTE_MAX_COLORS; ++i) {
        if (i < n) {
            out->swatches[i] = g[i].swatch;
        } else {
            out->swatches[i].lab.L = 0.0;
            out->swatches[i].lab.a = 0.0;
            out->swatches[i].lab.b = 0.0;
            out->swatches[i].rgb[0] = 0;
            out->swatches[i].rgb[1] = 0;
            out->swatches[i].rgb[2] = 0;
            out->swatches[i].weight = 0.0;
        }
    }
    out->n_swatches = n;
    rc = ce_match(ctx, out->swatches, n, mo, out->hits, CE_MATCH_MAX_HITS, &out->ambiguous);
    if (rc < 0) {
        /* Inalcanzable con swatches válidos; `out` queda vacío y coherente. */
        out->n_swatches = 0;
        out->n_hits = 0;
        out->ambiguous = 0;
        return rc;
    }
    out->n_hits = rc;
    for (i = rc; i < CE_MATCH_MAX_HITS; ++i) {
        out->hits[i].combo_id = 0;
        out->hits[i].score = 0.0;
    }
    if (garments != NULL) {
        for (i = 0; i < n; ++i) {
            garments[i] = g[i];
        }
    }
    return rc;
}

static uint64_t ce_fnv1a_int32(uint64_t h, int v)
{
    const uint32_t u = (uint32_t)v;
    unsigned char b[4];
    b[0] = (unsigned char)(u & 0xFFu);
    b[1] = (unsigned char)((u >> 8) & 0xFFu);
    b[2] = (unsigned char)((u >> 16) & 0xFFu);
    b[3] = (unsigned char)((u >> 24) & 0xFFu);
    return ce_fnv1a_bytes(h, b, 4);
}

uint64_t ce_garment_hash(const ce_garment_swatch *g, int n)
{
    uint64_t h = 0xcbf29ce484222325ULL;
    int i;
    if (g == NULL || n < 0) {
        n = 0;
    }
    for (i = 0; i < n; ++i) {
        h = ce_fnv1a_double(h, g[i].swatch.lab.L);
        h = ce_fnv1a_double(h, g[i].swatch.lab.a);
        h = ce_fnv1a_double(h, g[i].swatch.lab.b);
        h = ce_fnv1a_double(h, g[i].swatch.weight);
        h = ce_fnv1a_double(h, g[i].region_share);
        h = ce_fnv1a_int32(h, g[i].region);
        h = ce_fnv1a_int32(h, g[i].n_merged_clusters);
    }
    return h;
}
