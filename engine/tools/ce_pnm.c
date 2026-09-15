/*
 * ce_pnm.c — parser de P6/P5 binarios (ver ce_pnm.h). Cada acceso a buf pasa
 * por el índice `i < len`; los enteros se acumulan con tope para no
 * desbordar; el tamaño del cuerpo se calcula en size_t tras acotar los lados
 * a CE_PNM_MAX_SIDE (16384^2 * 3 < 2^31, cabe también en size_t de 32 bits).
 */
#include "ce_pnm.h"

#include <stddef.h>
#include <stdint.h>

#pragma STDC FP_CONTRACT OFF

/* Tope de un token numérico: por encima de esto es basura seguro. */
#define CE_PNM_MAX_TOKEN 100000000L

typedef struct {
    const uint8_t *p;
    size_t n;
    size_t i;
} ce_pnm_reader;

static int ce_pnm_is_space(uint8_t c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

/* Salta separadores y comentarios. Devuelve cuántos bytes consumió. */
static size_t ce_pnm_skip(ce_pnm_reader *r)
{
    const size_t start = r->i;
    while (r->i < r->n) {
        if (ce_pnm_is_space(r->p[r->i])) {
            r->i++;
        } else if (r->p[r->i] == '#') {
            while (r->i < r->n && r->p[r->i] != '\n' && r->p[r->i] != '\r') {
                r->i++;
            }
        } else {
            break;
        }
    }
    return r->i - start;
}

/* Lee un entero decimal sin signo. Error si no hay dígitos o supera el tope. */
static int ce_pnm_read_uint(ce_pnm_reader *r, long *out)
{
    long v = 0;
    size_t digits = 0;
    while (r->i < r->n && r->p[r->i] >= '0' && r->p[r->i] <= '9') {
        v = v * 10 + (r->p[r->i] - '0');
        if (v > CE_PNM_MAX_TOKEN) {
            return CE_PNM_ERR_HEADER;
        }
        r->i++;
        digits++;
    }
    if (digits == 0) {
        return CE_PNM_ERR_HEADER;
    }
    *out = v;
    return CE_PNM_OK;
}

int ce_pnm_parse(const uint8_t *buf, size_t len, ce_pnm_image *out)
{
    ce_pnm_reader r;
    long w, h, maxval;
    int type, channels, rc;
    size_t need;

    if (buf == NULL || out == NULL) {
        return CE_PNM_ERR_ARG;
    }
    if (len < 2 || buf[0] != 'P' || (buf[1] != '5' && buf[1] != '6')) {
        return CE_PNM_ERR_MAGIC;
    }
    type = buf[1] - '0';
    channels = (type == 6) ? 3 : 1;
    r.p = buf;
    r.n = len;
    r.i = 2;

    if (ce_pnm_skip(&r) == 0) {
        return CE_PNM_ERR_HEADER; /* "P6" debe ir seguido de separador o comentario */
    }
    if ((rc = ce_pnm_read_uint(&r, &w)) != CE_PNM_OK) return rc;
    if (ce_pnm_skip(&r) == 0) return CE_PNM_ERR_HEADER;
    if ((rc = ce_pnm_read_uint(&r, &h)) != CE_PNM_OK) return rc;
    if (ce_pnm_skip(&r) == 0) return CE_PNM_ERR_HEADER;
    if ((rc = ce_pnm_read_uint(&r, &maxval)) != CE_PNM_OK) return rc;
    /* Exactamente un byte separador entre maxval y el cuerpo (norma PNM). */
    if (r.i >= r.n || !ce_pnm_is_space(r.p[r.i])) {
        return CE_PNM_ERR_HEADER;
    }
    r.i++;

    if (w <= 0 || h <= 0 || w > CE_PNM_MAX_SIDE || h > CE_PNM_MAX_SIDE) {
        return CE_PNM_ERR_DIMS;
    }
    if (maxval != 255) {
        return CE_PNM_ERR_MAXVAL;
    }
    need = (size_t)w * (size_t)h * (size_t)channels;
    if (r.n - r.i < need) {
        return CE_PNM_ERR_TRUNCATED;
    }
    out->type = type;
    out->width = (int)w;
    out->height = (int)h;
    out->channels = channels;
    out->data = buf + r.i;
    out->data_len = need;
    return CE_PNM_OK;
}

const char *ce_pnm_strerror(int code)
{
    switch (code) {
    case CE_PNM_OK: return "ok";
    case CE_PNM_ERR_ARG: return "argumento nulo";
    case CE_PNM_ERR_MAGIC: return "no es P5 ni P6 binario";
    case CE_PNM_ERR_HEADER: return "cabecera mal formada";
    case CE_PNM_ERR_DIMS: return "dimensiones fuera de [1, 16384]";
    case CE_PNM_ERR_MAXVAL: return "maxval distinto de 255";
    case CE_PNM_ERR_TRUNCATED: return "cuerpo truncado";
    default: return "error desconocido";
    }
}
