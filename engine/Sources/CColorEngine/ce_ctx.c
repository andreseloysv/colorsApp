/*
 * ce_ctx.c — contexto de trabajo reservado por el llamante.
 *
 * ce_ctx_size() devuelve los bytes necesarios (múltiplo de 16, <= 2 MiB por
 * _Static_assert y por test_ctx_size_budget); ce_ctx_init() lo inicializa en
 * memoria del llamante alineada a 16 y construye la caché Lab del diccionario
 * con ce_dict_color_lab (misma función que procesa la foto). Sin estáticos
 * mutables, sin malloc, sin I/O.
 */
#include "ce_internal.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>

#pragma STDC FP_CONTRACT OFF

/* Cota dura del plan (§5): el contexto cabe en 2 MiB. */
_Static_assert(sizeof(struct ce_ctx) <= 2u * 1024u * 1024u,
               "ce_ctx supera los 2 MiB del presupuesto");
_Static_assert(CE_CTX_DICT_CAP >= 159, "la cache Lab debe cubrir el Vol. 1 (159 colores)");

size_t ce_ctx_size(void)
{
    /* Redondeado a múltiplo de 16 para que aligned_alloc(16, ce_ctx_size())
     * sea válido tal cual en C11. */
    return (sizeof(struct ce_ctx) + 15u) & ~(size_t)15u;
}

ce_ctx *ce_ctx_init(void *mem, size_t size)
{
    ce_ctx *ctx;
    unsigned char *bytes;
    size_t i;
    int n, k;

    if (mem == NULL || size < ce_ctx_size() || ((uintptr_t)mem & 15u) != 0) {
        return NULL;
    }
    /* Se limpia todo el bloque: sin <string.h> por la regla "solo <math.h>";
     * el compilador lo convierte en memset. */
    bytes = (unsigned char *)mem;
    for (i = 0; i < sizeof(struct ce_ctx); ++i) {
        bytes[i] = 0;
    }
    ctx = (ce_ctx *)mem;

    n = ce_dict_num_colors();
    if (n > CE_CTX_DICT_CAP) {
        n = CE_CTX_DICT_CAP;
    }
    for (k = 0; k < n; ++k) {
        ctx->dict_lab[k] = ce_dict_color_lab(k);
    }
    ctx->dict_n = n;
    ctx->reduced_w = 0;
    ctx->reduced_h = 0;
    ctx->magic = CE_CTX_MAGIC;
    return ctx;
}
