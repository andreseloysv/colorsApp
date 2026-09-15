/*
 * ce_internal.h — layout del contexto y funciones internas compartidas por
 * ce_ctx.c, ce_image.c y ce_palette.c. NO es API pública (no vive en include/).
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

struct ce_ctx {
    uint32_t magic;
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

#endif /* CE_INTERNAL_H */
