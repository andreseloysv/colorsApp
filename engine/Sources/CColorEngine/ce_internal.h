/*
 * ce_internal.h — layout del contexto y funciones internas compartidas por
 * ce_ctx.c, ce_image.c, ce_palette.c, ce_match.c y ce_debug.c. NO es API pública (no vive en include/).
 *
 * El contexto es un único bloque contiguo que aporta el llamante (ce_ctx_size /
 * ce_ctx_init): imagen reducida, pesos por píxel, histograma de 5 bits por
 * canal, caché Lab del diccionario, cajas MMCQ y centros de Lloyd. Todo lo que
 * escribe el motor está aquí; no hay estáticos mutables ni malloc.
 */
#ifndef CE_INTERNAL_H
#define CE_INTERNAL_H

#include "ce/ce.h"

#include <stddef.h>
#include <stdint.h>

/* Marca escrita por ce_ctx_init; ce_palette_extract la comprueba. */
#define CE_CTX_MAGIC 0x43454331u /* "CEC1" */

/* Imagen reducida: lado máximo fijo para dimensionar el contexto. */
#define CE_CTX_MAX_SIDE CE_PALETTE_MAX_SIDE
#define CE_CTX_MAX_PIXELS (CE_CTX_MAX_SIDE * CE_CTX_MAX_SIDE)

/* Histograma: 5 bits por canal => 32 x 32 x 32 = 32768 bins. */
#define CE_HIST_BITS 5
#define CE_HIST_SHIFT (8 - CE_HIST_BITS)
#define CE_HIST_SIDE (1 << CE_HIST_BITS)
#define CE_HIST_BINS (CE_HIST_SIDE * CE_HIST_SIDE * CE_HIST_SIDE)

/* Capacidad de la caché Lab del diccionario (159 colores en el Vol. 1). */
#define CE_CTX_DICT_CAP 256

/* Índice de bin a partir de coordenadas de bin (0..31). */
#define CE_HIST_INDEX(r, g, b) ((((r) << CE_HIST_BITS) | (g)) << CE_HIST_BITS | (b))

/* Un bin del histograma. Durante la acumulación `c` guarda Σw·r, Σw·g, Σw·b
 * (r, g, b en 0..255); tras la finalización guarda L, a, b del color medio
 * ponderado del bin. `count` cuenta píxeles con o sin peso; `center` es el
 * centro asignado por Lloyd (-1 si el bin no tiene peso). */
typedef struct ce_hist_bin {
    double wsum;
    double c[3];
    uint32_t count;
    int32_t center;
} ce_hist_bin;

/* Caja del median cut en coordenadas de bin (extremos inclusivos, ya
 * encogidos al menor paralelepípedo que contiene sus bins con peso). */
typedef struct ce_box {
    int lo[3];
    int hi[3];
    double wsum;    /* población ponderada */
    int volume;     /* Π (hi - lo + 1) */
    int splittable; /* algún eje con hi > lo */
} ce_box;

/* Centro de Lloyd / swatch antes de ordenar. */
typedef struct ce_center {
    ce_lab lab;
    double wsum;
    double sum[3];
} ce_center;

/* Estado de depuración de la última extracción (ce_debug.c lo lee). Se
 * rellena con contabilidad paralela (enteros y copias) que no altera ninguna
 * operación de coma flotante de la paleta: los goldens y la paridad no cambian.
 *  - clusters[]: centros de Lloyd no vacíos en orden de índice (compactados).
 *  - center_label[j]: etiqueta (swatch final, CE_LABEL_DISCARDED o
 *    CE_LABEL_NONE) del centro de Lloyd j ANTES de compactar, que es el índice
 *    que guarda ce_hist_bin.center.
 *  - center_cluster[j]: posición en clusters[] del centro j (CE_LABEL_NONE si
 *    estaba vacío). */
typedef struct ce_debug_state {
    int valid;
    int lloyd_iterations;
    int n_clusters;
    int n_swatches;
    double total_weight;
    double center_sigma_px;
    ce_cluster_debug clusters[CE_PALETTE_K_MAX];
    uint8_t center_label[CE_PALETTE_K_MAX];
    uint8_t center_cluster[CE_PALETTE_K_MAX];
} ce_debug_state;

struct ce_ctx {
    uint32_t magic;
    ce_debug_state dbg;
    int reduced_w;
    int reduced_h;
    int dict_n;                               /* colores cacheados en dict_lab */
    ce_lab dict_lab[CE_CTX_DICT_CAP];
    ce_box boxes[CE_PALETTE_K_MAX];
    ce_center centers[CE_PALETTE_K_MAX];
    double axis_partial[CE_HIST_SIDE];        /* sumas parciales del corte */
    uint8_t reduced[CE_CTX_MAX_PIXELS * 3];   /* imagen reducida, RGB8 empaquetado */
    double weights[CE_CTX_MAX_PIXELS];        /* peso por píxel reducido */
    ce_hist_bin hist[CE_HIST_BINS];
};

/* ---- ce_image.c ---------------------------------------------------------- */

/* Bytes por píxel del formato, o 0 si es desconocido. */
int ce_image_bpp(ce_pixel_format fmt);

/* Valida punteros, dimensiones, formato y stride (códigos de ce_status). */
int ce_image_validate(const ce_image *img);

/* Box-downscale entero de la imagen (y de la máscara, si la hay) a
 * ctx->reduced / ctx->weights; fija reduced_w/reduced_h. Sin máscara el peso
 * inicial es 1.0 exacto; con máscara es la media entera del bloque (0..255).
 * Precondición: imagen validada y 1 <= max_side <= CE_CTX_MAX_SIDE. */
void ce_image_reduce(ce_ctx *ctx, const ce_image *img, int max_side);

/* Multiplica los pesos por la gaussiana al centro con sigma en píxeles de la
 * imagen reducida. sigma no finita o <= 0: no hace nada (uniforme). */
void ce_image_apply_center_weight(ce_ctx *ctx, double sigma_px);

/* Anula el peso de los píxeles de piel (Chai y Ngan, YCbCr JFIF). */
void ce_image_apply_skin_rule(ce_ctx *ctx);

/* ---- ce_mask.c ----------------------------------------------------------- */

/* Tabla por canal de ce_srgb8_to_xyz: t[0][v] = XYZ de (v,0,0), t[1][v] de
 * (0,v,0), t[2][v] de (0,0,v). Como ce_mat3_mul_vec suma en orden fijo
 * ((m0·r + m1·g) + m2·b) y un término con canal 0 vale ±0 exacto, X =
 * (t0.X + t1.X) + t2.X es bit a bit el X de ce_srgb8_to_xyz(r, g, b) (igual Y,
 * Z); test_mask.c lo comprueba en los 16,7 M colores. 18 KiB: vive en la pila
 * de la función que la usa. */
typedef struct ce_srgb8_xyz_table {
    ce_xyz t[3][256];
} ce_srgb8_xyz_table;

void ce_srgb8_xyz_table_init(ce_srgb8_xyz_table *t);

/* == ce_srgb8_to_lab(r, g, b) bit a bit, sin las tres potencias por píxel. */
ce_lab ce_srgb8_to_lab_table(const ce_srgb8_xyz_table *t, uint8_t r, uint8_t g, uint8_t b);

/* ---- ce_match.c (compartido con ce_debug.c: ce_match_explain_combo) ------ */

/* Iluminantes hipotéticos distintos de D65, en orden de evaluación. */
#define CE_MATCH_N_ILLS 4
/* Máximo de pasos de exposición a cada lado (|EV| <= CE_MATCH_EV_MAX_LIMIT). */
#define CE_MATCH_MAX_STEPS ((int)(CE_MATCH_EV_MAX_LIMIT / CE_MATCH_EV_STEP + 0.5))

/* 1 si las opciones de match son válidas (ver ce_match_opts). */
int ce_match_opts_valid(const ce_match_opts *o);

/* 1 si los n swatches tienen Lab finito y peso finito >= 0. */
int ce_match_swatches_valid(const ce_swatch *sw, int n);

/* Iluminante hipotético `ill` (0..CE_MATCH_N_ILLS-1): A, D50, D75, F2. */
ce_illuminant ce_match_hyp_illuminant(int ill);

/* Hipótesis de adaptación (Bradford opcional `m` y ganancia en XYZ lineal). */
ce_lab ce_match_adapt_lab(ce_lab lab, const double *m, double gain);

#endif /* CE_INTERNAL_H */
