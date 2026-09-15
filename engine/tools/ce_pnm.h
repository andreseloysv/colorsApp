/*
 * ce_pnm.h — parser mínimo de PPM (P6) y PGM (P5) binarios, maxval 255.
 *
 * Vive en tools/ (fuera del target SPM): es entrada NO confiable (dimensiones
 * y tamaño tomados del fichero), por eso lo comparten el CLI y el fuzz loop
 * (tests/fuzz_palette.c). Nunca lee fuera de [buf, buf + len) ni reserva
 * memoria: `data` apunta dentro del buffer del llamante.
 */
#ifndef CE_PNM_H
#define CE_PNM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Lado máximo admitido (2^14). */
#define CE_PNM_MAX_SIDE 16384

enum {
    CE_PNM_OK = 0,
    CE_PNM_ERR_ARG = -1,       /**< buf o out NULL */
    CE_PNM_ERR_MAGIC = -2,     /**< no empieza por "P5" o "P6" */
    CE_PNM_ERR_HEADER = -3,    /**< cabecera mal formada (token no numérico, sin separador) */
    CE_PNM_ERR_DIMS = -4,      /**< width/height <= 0 o > CE_PNM_MAX_SIDE, o desbordan */
    CE_PNM_ERR_MAXVAL = -5,    /**< maxval != 255 */
    CE_PNM_ERR_TRUNCATED = -6  /**< cuerpo más corto que width*height*canales */
};

typedef struct ce_pnm_image {
    int type;            /**< 5 (P5, gris) o 6 (P6, RGB) */
    int width;
    int height;
    int channels;        /**< 1 o 3 */
    const uint8_t *data; /**< primer byte del cuerpo, dentro de buf */
    size_t data_len;     /**< width * height * channels */
} ce_pnm_image;

/** Parsea `buf[0..len)`. Cabecera: "P6"|"P5", separadores (espacios, tabs,
 *  CR, LF, VT, FF) y comentarios '#' hasta fin de línea en cualquier posición
 *  entre tokens, width, height, maxval (== 255) y UN solo byte separador
 *  antes del cuerpo. Los bytes sobrantes tras el cuerpo se ignoran.
 *  Devuelve CE_PNM_OK y rellena `out`, o un código negativo sin tocar `out`. */
int ce_pnm_parse(const uint8_t *buf, size_t len, ce_pnm_image *out);

/** Texto estático del código de error. */
const char *ce_pnm_strerror(int code);

#ifdef __cplusplus
}
#endif

#endif /* CE_PNM_H */
