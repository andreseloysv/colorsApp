/*
 * ce_cli.c — CLI "ce" para probar el motor desde la línea de comandos.
 *
 *   ce version                      imprime la versión del motor
 *   ce lab R G B                    sRGB8 -> "L a b" (%.12f)
 *   ce de2000 L1 a1 b1 L2 a2 b2     ΔE00 (%.15e)
 *   ce de2000                       sin argumentos: lee de stdin líneas
 *                                   "L1 a1 b1 L2 a2 b2" y escribe ΔE00 (%.15e)
 *   ce convert                      lee de stdin líneas "R G B" (enteros 0-255)
 *                                   y escribe "L a b" con %.15e por línea
 *   ce dict --version               dict_version embebido (== dictionary.json)
 *   ce dict --list                  "id size" por línea, las 348 combinaciones
 *   ce dict --id N                  combinación N: tamaño y, por color, índice,
 *                                   hex, Lab (%.12f) y nombre
 *   ce palette img.ppm [--mask m.pgm] [--raw WxH] [opciones] [--json]
 *                                   paleta dominante (capa 2). Entrada P6
 *                                   binario maxval 255 (o .rgb crudo w*h*3 con
 *                                   --raw), máscara P5 de las mismas
 *                                   dimensiones. Con --json escribe el objeto
 *                                   del contrato (engine, dict_version, width,
 *                                   height, reduced_*, opts, swatches, hash);
 *                                   sin --json, una tabla.
 *   ce match img.ppm [opciones de palette] [--top K] [--kL F] [--kC F] [--kH F]
 *            [--coverage-lambda F] [--ambiguous-gap F] [--exposure-ev-max F]
 *            [--exposure-penalty F] [--illuminant-search 0|1] [--illuminant-penalty F] [--json]
 *                                   paleta + match contra el diccionario (capa
 *                                   3). Con --json: {engine, dict_version,
 *                                   file, width, height, reduced_*, opts:
 *                                   {palette, match}, swatches, hits: [{id,
 *                                   score, size, colors}], ambiguous, hash};
 *                                   `hash` = ce_result_hash de los K hits
 *                                   impresos (idéntico en nativo y WASM:
 *                                   ce_libm.c). --top K en 1..10 (defecto 3).
 *   ce analyze ...                  alias exacto de `ce match`.
 *   ce batch lista.txt [mismas opciones] [--json]
 *                                   una imagen por línea (vacías y '#'
 *                                   ignoradas); con --json una línea JSON por
 *                                   imagen (JSONL) con los mismos campos; un
 *                                   fichero ilegible produce {"file", "error"}
 *                                   y el proceso continúa. --mask/--raw se
 *                                   aplican a todas las imágenes.
 *
 * Salida: 0 ok, 1 error del motor (código negativo; en batch, si alguna
 * imagen falló por cualquier motivo), 2 uso o fichero inválido (en batch,
 * solo la propia lista).
 *
 * "convert" es la entrada del differential testing masivo contra el oráculo
 * Python (oracle/oracle/diff_oracle.py); "palette" la de la capa 2
 * (oracle/tests/test_l2_palette.py) y "match"/"batch" la de la capa 3
 * (oracle/tests/test_l3_match.py).
 */
#include "ce/ce.h"
#include "ce_pnm.h"

#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma STDC FP_CONTRACT OFF

/* Longitud máxima de una ruta en la lista del batch. */
#define CLI_PATH_MAX 4096

static int usage(void)
{
    fprintf(stderr,
            "uso:\n"
            "  ce version\n"
            "  ce lab R G B\n"
            "  ce de2000 L1 a1 b1 L2 a2 b2\n"
            "  ce de2000    (stdin: lineas \"L1 a1 b1 L2 a2 b2\" -> stdout: dE00)\n"
            "  ce convert   (stdin: lineas \"R G B\" -> stdout: \"L a b\")\n"
            "  ce dict --version | --list | --id N\n"
            "  ce palette <imagen.ppm> [--mask <mascara.pgm>] [--raw WxH]\n"
            "             [--center-sigma F] [--max-colors N] [--min-weight F] [--merge-de F]\n"
            "             [--k-init N] [--max-iters N] [--max-side N] [--skin-rule 0|1] [--json]\n"
            "  ce match|analyze <imagen.ppm> [opciones de palette] [--top K(1..10)]\n"
            "             [--kL F] [--kC F] [--kH F] [--coverage-lambda F] [--ambiguous-gap F]\n"
            "             [--exposure-ev-max F] [--exposure-penalty F] [--illuminant-search 0|1]\n"
            "             [--illuminant-penalty F] [--json]\n"
            "  ce batch <lista.txt> [mismas opciones que match] [--json]   (JSONL, una linea por imagen)\n");
    return 2;
}

/* Parsea un entero 0..255 estricto. */
static int parse_u8(const char *s, uint8_t *out)
{
    char *end;
    long v;
    errno = 0;
    v = strtol(s, &end, 10);
    if (errno != 0 || end == s || *end != '\0' || v < 0 || v > 255) {
        return 0;
    }
    *out = (uint8_t)v;
    return 1;
}

static int parse_double(const char *s, double *out)
{
    char *end;
    errno = 0;
    *out = strtod(s, &end);
    /* Se rechazan nan/inf: un oráculo mal formado no debe pasar desapercibido. */
    return errno == 0 && end != s && *end == '\0' && isfinite(*out);
}

static int cmd_lab(int argc, char **argv)
{
    uint8_t r, g, b;
    ce_lab lab;
    if (argc != 5 || !parse_u8(argv[2], &r) || !parse_u8(argv[3], &g) || !parse_u8(argv[4], &b)) {
        return usage();
    }
    lab = ce_srgb8_to_lab(r, g, b);
    printf("%.12f %.12f %.12f\n", lab.L, lab.a, lab.b);
    return 0;
}

static int cmd_de2000_stdin(void)
{
    char line[512];
    unsigned long lineno = 0;
    while (fgets(line, sizeof line, stdin)) {
        double v[6];
        ce_lab l1, l2;
        ++lineno;
        if (line[0] == '\n' || line[0] == '#' || line[0] == '\0') {
            continue;
        }
        if (sscanf(line, "%lf %lf %lf %lf %lf %lf", &v[0], &v[1], &v[2], &v[3], &v[4], &v[5]) != 6) {
            fprintf(stderr, "linea %lu invalida: %s", lineno, line);
            return 1;
        }
        l1.L = v[0]; l1.a = v[1]; l1.b = v[2];
        l2.L = v[3]; l2.a = v[4]; l2.b = v[5];
        printf("%.15e\n", ce_de2000(l1, l2));
    }
    return ferror(stdin) ? 1 : 0;
}

static int cmd_de2000(int argc, char **argv)
{
    double v[6];
    ce_lab l1, l2;
    int i;
    if (argc == 2) {
        return cmd_de2000_stdin();
    }
    if (argc != 8) {
        return usage();
    }
    for (i = 0; i < 6; ++i) {
        if (!parse_double(argv[2 + i], &v[i])) {
            return usage();
        }
    }
    l1.L = v[0]; l1.a = v[1]; l1.b = v[2];
    l2.L = v[3]; l2.a = v[4]; l2.b = v[5];
    printf("%.15e\n", ce_de2000(l1, l2));
    return 0;
}

static int cmd_convert(void)
{
    char line[256];
    unsigned long lineno = 0;
    while (fgets(line, sizeof line, stdin)) {
        long r, g, b;
        ce_lab lab;
        ++lineno;
        if (line[0] == '\n' || line[0] == '#' || line[0] == '\0') {
            continue;
        }
        if (sscanf(line, "%ld %ld %ld", &r, &g, &b) != 3
            || r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) {
            fprintf(stderr, "linea %lu invalida: %s", lineno, line);
            return 1;
        }
        lab = ce_srgb8_to_lab((uint8_t)r, (uint8_t)g, (uint8_t)b);
        printf("%.15e %.15e %.15e\n", lab.L, lab.a, lab.b);
    }
    return ferror(stdin) ? 1 : 0;
}

/* Imprime una combinación: cabecera "id N size S" y una línea por color con
 * índice, hex, Lab (%.12f) y nombre. */
static int print_combo(int id)
{
    uint8_t size = 0;
    uint8_t colors[CE_DICT_COMBO_MAX];
    int k;
    if (ce_dict_combo(id, &size, colors) != 0) {
        fprintf(stderr, "la combinacion %d no existe (ids 1..%d)\n", id, ce_dict_num_combos());
        return 1;
    }
    printf("id %d size %u\n", id, (unsigned)size);
    for (k = 0; k < (int)size && k < CE_DICT_COMBO_MAX; ++k) {
        uint8_t rgb[3];
        ce_lab lab;
        const int index = colors[k];
        if (ce_dict_color_rgb(index, rgb) != 0) {
            fprintf(stderr, "indice de color invalido %d en la combinacion %d\n", index, id);
            return 1;
        }
        lab = ce_dict_color_lab(index);
        printf("%3d #%02x%02x%02x %.12f %.12f %.12f %s\n", index, rgb[0], rgb[1], rgb[2],
               lab.L, lab.a, lab.b, ce_dict_color_name(index));
    }
    return 0;
}

static int cmd_dict(int argc, char **argv)
{
    if (argc == 3 && strcmp(argv[2], "--version") == 0) {
        printf("%s\n", ce_dict_version());
        return 0;
    }
    if (argc == 3 && strcmp(argv[2], "--list") == 0) {
        int id;
        const int n = ce_dict_num_combos();
        for (id = 1; id <= n; ++id) {
            uint8_t size = 0;
            if (ce_dict_combo(id, &size, NULL) != 0) {
                fprintf(stderr, "hueco en los ids del diccionario: %d\n", id);
                return 1;
            }
            printf("%d %u\n", id, (unsigned)size);
        }
        return 0;
    }
    if (argc == 4 && strcmp(argv[2], "--id") == 0) {
        char *end;
        long id;
        errno = 0;
        id = strtol(argv[3], &end, 10);
        if (errno != 0 || end == argv[3] || *end != '\0' || id > INT_MAX || id < INT_MIN) {
            return usage();
        }
        return print_combo((int)id);
    }
    return usage();
}

/* ------------------------------------------------------------------------
 * Ficheros, opciones y carga de imágenes (compartido por palette/match/batch)
 * ---------------------------------------------------------------------- */

/* Lee un fichero completo a memoria (malloc). 0 ok; -1 error con el motivo
 * (sin ruta ni salto de línea) en `err`. */
static int read_file(const char *path, uint8_t **out, size_t *out_len, char *err, size_t err_len)
{
    FILE *f = fopen(path, "rb");
    uint8_t *buf = NULL;
    size_t cap = 1u << 16, len = 0;
    if (f == NULL) {
        snprintf(err, err_len, "no puedo abrir el fichero (%s)", strerror(errno));
        return -1;
    }
    buf = (uint8_t *)malloc(cap);
    if (buf == NULL) {
        fclose(f);
        snprintf(err, err_len, "sin memoria");
        return -1;
    }
    for (;;) {
        size_t got;
        if (len == cap) {
            uint8_t *nb;
            cap *= 2;
            nb = (uint8_t *)realloc(buf, cap);
            if (nb == NULL) {
                free(buf);
                fclose(f);
                snprintf(err, err_len, "sin memoria");
                return -1;
            }
            buf = nb;
        }
        got = fread(buf + len, 1, cap - len, f);
        len += got;
        if (got == 0) {
            break;
        }
    }
    if (ferror(f)) {
        snprintf(err, err_len, "error de lectura (%s)", strerror(errno));
        free(buf);
        fclose(f);
        return -1;
    }
    fclose(f);
    *out = buf;
    *out_len = len;
    return 0;
}

static int parse_int_opt(const char *s, int *out)
{
    char *end;
    long v;
    errno = 0;
    v = strtol(s, &end, 10);
    if (errno != 0 || end == s || *end != '\0' || v > INT_MAX || v < INT_MIN) {
        return 0;
    }
    *out = (int)v;
    return 1;
}

/* "WxH" -> w, h. */
static int parse_dims(const char *s, int *w, int *h)
{
    char *end;
    long a, b;
    errno = 0;
    a = strtol(s, &end, 10);
    if (errno != 0 || end == s || *end != 'x') return 0;
    s = end + 1;
    b = strtol(s, &end, 10);
    if (errno != 0 || end == s || *end != '\0') return 0;
    if (a < 1 || b < 1 || a > CE_IMAGE_MAX_SIDE || b > CE_IMAGE_MAX_SIDE) return 0;
    *w = (int)a;
    *h = (int)b;
    return 1;
}

/* Opciones comunes de palette / match / analyze / batch. */
typedef struct cli_opts {
    ce_palette_opts palette;
    ce_match_opts match;
    int top;               /* 1..CE_MATCH_MAX_HITS (match/batch) */
    int json;
    const char *input;     /* imagen (palette/match) o lista (batch) */
    const char *mask_path; /* opcional */
    int raw_w, raw_h;      /* > 0 con --raw */
} cli_opts;

/* Parsea argv[2..]. `with_match` admite además --top/--kL/--kC/--kH/
 * --coverage-lambda/--ambiguous-gap/--exposure-ev-max/--exposure-penalty/
 * --illuminant-search/--illuminant-penalty. Devuelve 0 o -1 (error de uso). */
static int parse_cli_opts(int argc, char **argv, int with_match, cli_opts *o)
{
    int i;
    memset(o, 0, sizeof *o);
    ce_palette_opts_default(&o->palette);
    ce_match_opts_default(&o->match);
    o->top = 3;
    for (i = 2; i < argc; ++i) {
        const char *a = argv[i];
        const char *v = (i + 1 < argc) ? argv[i + 1] : NULL;
        if (strcmp(a, "--json") == 0) {
            o->json = 1;
        } else if (strcmp(a, "--mask") == 0 && v) {
            o->mask_path = v; ++i;
        } else if (strcmp(a, "--raw") == 0 && v) {
            if (!parse_dims(v, &o->raw_w, &o->raw_h)) return -1;
            ++i;
        } else if (strcmp(a, "--center-sigma") == 0 && v) {
            if (!parse_double(v, &o->palette.center_sigma)) return -1;
            ++i;
        } else if (strcmp(a, "--min-weight") == 0 && v) {
            if (!parse_double(v, &o->palette.min_weight)) return -1;
            ++i;
        } else if (strcmp(a, "--merge-de") == 0 && v) {
            if (!parse_double(v, &o->palette.merge_de)) return -1;
            ++i;
        } else if (strcmp(a, "--max-colors") == 0 && v) {
            if (!parse_int_opt(v, &o->palette.max_colors)) return -1;
            ++i;
        } else if (strcmp(a, "--k-init") == 0 && v) {
            if (!parse_int_opt(v, &o->palette.k_init)) return -1;
            ++i;
        } else if (strcmp(a, "--max-iters") == 0 && v) {
            if (!parse_int_opt(v, &o->palette.max_iters)) return -1;
            ++i;
        } else if (strcmp(a, "--max-side") == 0 && v) {
            if (!parse_int_opt(v, &o->palette.max_side)) return -1;
            ++i;
        } else if (strcmp(a, "--skin-rule") == 0 && v) {
            if (!parse_int_opt(v, &o->palette.skin_rule)) return -1;
            ++i;
        } else if (with_match && strcmp(a, "--top") == 0 && v) {
            if (!parse_int_opt(v, &o->top) || o->top < 1 || o->top > CE_MATCH_MAX_HITS) return -1;
            ++i;
        } else if (with_match && strcmp(a, "--kL") == 0 && v) {
            if (!parse_double(v, &o->match.kL)) return -1;
            ++i;
        } else if (with_match && strcmp(a, "--kC") == 0 && v) {
            if (!parse_double(v, &o->match.kC)) return -1;
            ++i;
        } else if (with_match && strcmp(a, "--kH") == 0 && v) {
            if (!parse_double(v, &o->match.kH)) return -1;
            ++i;
        } else if (with_match && strcmp(a, "--coverage-lambda") == 0 && v) {
            if (!parse_double(v, &o->match.coverage_lambda)) return -1;
            ++i;
        } else if (with_match && strcmp(a, "--ambiguous-gap") == 0 && v) {
            if (!parse_double(v, &o->match.ambiguous_gap)) return -1;
            ++i;
        } else if (with_match && strcmp(a, "--exposure-ev-max") == 0 && v) {
            if (!parse_double(v, &o->match.exposure_ev_max)) return -1;
            ++i;
        } else if (with_match && strcmp(a, "--exposure-penalty") == 0 && v) {
            if (!parse_double(v, &o->match.exposure_penalty)) return -1;
            ++i;
        } else if (with_match && strcmp(a, "--illuminant-search") == 0 && v) {
            if (!parse_int_opt(v, &o->match.illuminant_search)) return -1;
            ++i;
        } else if (with_match && strcmp(a, "--illuminant-penalty") == 0 && v) {
            if (!parse_double(v, &o->match.illuminant_penalty)) return -1;
            ++i;
        } else if (a[0] == '-' && a[1] == '-') {
            return -1;
        } else if (o->input == NULL) {
            o->input = a;
        } else {
            return -1;
        }
    }
    return o->input == NULL ? -1 : 0;
}

/* Imagen cargada: buffers propios (malloc) + ce_image que apunta dentro. */
typedef struct loaded_image {
    uint8_t *img_buf;
    uint8_t *mask_buf;
    ce_image img;
} loaded_image;

static void free_image(loaded_image *li)
{
    free(li->img_buf);
    free(li->mask_buf);
    li->img_buf = NULL;
    li->mask_buf = NULL;
}

/* Carga `path` (P6, o crudo con --raw) y la máscara opcional. 0 ok; -1 con el
 * motivo en `err` (sin la ruta, sin salto de línea) y sin buffers vivos. */
static int load_image(const char *path, const cli_opts *o, loaded_image *li, char *err, size_t err_len)
{
    size_t img_len = 0, mask_len = 0;
    memset(li, 0, sizeof *li);
    li->img.fmt = CE_RGB8;
    if (read_file(path, &li->img_buf, &img_len, err, err_len) != 0) {
        return -1;
    }
    if (o->raw_w > 0) {
        const size_t need = (size_t)o->raw_w * (size_t)o->raw_h * 3u;
        if (img_len != need) {
            snprintf(err, err_len, "--raw %dx%d exige %zu bytes y el fichero tiene %zu",
                     o->raw_w, o->raw_h, need, img_len);
            free_image(li);
            return -1;
        }
        li->img.pixels = li->img_buf;
        li->img.width = o->raw_w;
        li->img.height = o->raw_h;
    } else {
        ce_pnm_image pnm;
        const int prc = ce_pnm_parse(li->img_buf, img_len, &pnm);
        if (prc != CE_PNM_OK) {
            snprintf(err, err_len, "%s", ce_pnm_strerror(prc));
            free_image(li);
            return -1;
        }
        if (pnm.type != 6) {
            snprintf(err, err_len, "la imagen debe ser P6 (RGB)");
            free_image(li);
            return -1;
        }
        li->img.pixels = pnm.data;
        li->img.width = pnm.width;
        li->img.height = pnm.height;
    }
    li->img.stride_bytes = li->img.width * 3;

    if (o->mask_path != NULL) {
        ce_pnm_image pnm;
        char merr[256];
        int prc;
        if (read_file(o->mask_path, &li->mask_buf, &mask_len, merr, sizeof merr) != 0) {
            snprintf(err, err_len, "mascara %s: %s", o->mask_path, merr);
            free_image(li);
            return -1;
        }
        prc = ce_pnm_parse(li->mask_buf, mask_len, &pnm);
        if (prc != CE_PNM_OK) {
            snprintf(err, err_len, "mascara %s: %s", o->mask_path, ce_pnm_strerror(prc));
            free_image(li);
            return -1;
        }
        if (pnm.type != 5 || pnm.width != li->img.width || pnm.height != li->img.height) {
            snprintf(err, err_len, "mascara %s: debe ser P5 de %dx%d", o->mask_path,
                     li->img.width, li->img.height);
            free_image(li);
            return -1;
        }
        li->img.mask = pnm.data;
    }
    return 0;
}

/* Contexto del motor en memoria alineada (aligned_alloc). NULL si falla. */
static ce_ctx *new_ctx(void **mem)
{
    ce_ctx *ctx;
    *mem = aligned_alloc(16, ce_ctx_size());
    ctx = (*mem != NULL) ? ce_ctx_init(*mem, ce_ctx_size()) : NULL;
    if (ctx == NULL) {
        fprintf(stderr, "no puedo reservar el contexto (%zu bytes)\n", ce_ctx_size());
        free(*mem);
        *mem = NULL;
    }
    return ctx;
}

/* ------------------------------------------------------------------------
 * JSON
 * ---------------------------------------------------------------------- */

/* Cadena JSON con comillas y escapes (\" \\ y controles como \uXXXX). */
static void print_json_string(const char *s)
{
    putchar('"');
    for (; *s; ++s) {
        const unsigned char c = (unsigned char)*s;
        if (c == '"') {
            fputs("\\\"", stdout);
        } else if (c == '\\') {
            fputs("\\\\", stdout);
        } else if (c == '\n') {
            fputs("\\n", stdout);
        } else if (c == '\r') {
            fputs("\\r", stdout);
        } else if (c == '\t') {
            fputs("\\t", stdout);
        } else if (c < 0x20) {
            printf("\\u%04x", (unsigned)c);
        } else {
            putchar((int)c);
        }
    }
    putchar('"');
}

static void print_palette_opts_json(const ce_palette_opts *o)
{
    printf("{\"k_init\": %d, \"max_iters\": %d, \"max_colors\": %d, \"max_side\": %d, "
           "\"center_sigma\": %.17g, \"merge_de\": %.17g, \"min_weight\": %.17g, \"skin_rule\": %d}",
           o->k_init, o->max_iters, o->max_colors, o->max_side,
           o->center_sigma, o->merge_de, o->min_weight, o->skin_rule ? 1 : 0);
}

static void print_match_opts_json(const ce_match_opts *o, int top)
{
    printf("{\"kL\": %.17g, \"kC\": %.17g, \"kH\": %.17g, \"coverage_lambda\": %.17g, "
           "\"ambiguous_gap\": %.17g, \"exposure_ev_max\": %.17g, \"exposure_penalty\": %.17g, "
           "\"illuminant_search\": %d, \"illuminant_penalty\": %.17g, \"top\": %d}",
           o->kL, o->kC, o->kH, o->coverage_lambda, o->ambiguous_gap, o->exposure_ev_max,
           o->exposure_penalty, o->illuminant_search ? 1 : 0, o->illuminant_penalty, top);
}

static void print_swatch_json(const ce_swatch *s)
{
    printf("{\"rgb\": [%u, %u, %u], \"hex\": \"#%02x%02x%02x\", "
           "\"lab\": [%.17g, %.17g, %.17g], \"weight\": %.17g}",
           s->rgb[0], s->rgb[1], s->rgb[2], s->rgb[0], s->rgb[1], s->rgb[2],
           s->lab.L, s->lab.a, s->lab.b, s->weight);
}

static void print_hit_json(const ce_hit *h)
{
    uint8_t size = 0;
    uint8_t colors[CE_DICT_COMBO_MAX];
    int k;
    if (ce_dict_combo((int)h->combo_id, &size, colors) != 0) {
        size = 0;
    }
    printf("{\"id\": %u, \"score\": %.17g, \"size\": %u, \"colors\": [", (unsigned)h->combo_id,
           h->score, (unsigned)size);
    for (k = 0; k < (int)size; ++k) {
        printf("%s%u", k ? ", " : "", (unsigned)colors[k]);
    }
    printf("]}");
}

static void print_palette_json(const ce_image *img, const ce_palette_opts *o,
                               const ce_swatch *sw, int n)
{
    int rw = 0, rh = 0, i;
    (void)ce_reduced_dims(img->width, img->height, o->max_side, &rw, &rh);
    printf("{\n");
    printf("  \"engine\": \"%s\",\n", ce_version());
    printf("  \"dict_version\": \"%s\",\n", ce_dict_version());
    printf("  \"width\": %d,\n  \"height\": %d,\n", img->width, img->height);
    printf("  \"reduced_width\": %d,\n  \"reduced_height\": %d,\n", rw, rh);
    printf("  \"opts\": ");
    print_palette_opts_json(o);
    printf(",\n");
    printf("  \"swatches\": [\n");
    for (i = 0; i < n; ++i) {
        printf("    ");
        print_swatch_json(&sw[i]);
        printf("%s\n", (i + 1 < n) ? "," : "");
    }
    printf("  ],\n");
    printf("  \"hash\": \"%016" PRIx64 "\"\n", ce_swatch_hash(sw, n));
    printf("}\n");
}

/* Objeto del contrato de `ce match`; `pretty` = varias líneas (match) o una
 * sola (batch, JSONL). Imprime los `top` primeros hits y `hash` sobre ellos. */
static void print_result_json(const char *file, const ce_image *img, const cli_opts *o,
                              const ce_result *r, int pretty)
{
    const char *sep = pretty ? ",\n  " : ", ";
    const char *aopen = pretty ? "[\n    " : "[";
    const char *asep = pretty ? ",\n    " : ", ";
    const char *aclose = pretty ? "\n  ]" : "]";
    ce_result truncated = *r;
    int rw = 0, rh = 0, i, n_hits;

    n_hits = (o->top < r->n_hits) ? o->top : r->n_hits;
    truncated.n_hits = n_hits;
    (void)ce_reduced_dims(img->width, img->height, o->palette.max_side, &rw, &rh);
    printf(pretty ? "{\n  " : "{");
    printf("\"engine\": \"%s\"%s", ce_version(), sep);
    printf("\"dict_version\": \"%s\"%s", ce_dict_version(), sep);
    printf("\"file\": ");
    print_json_string(file);
    printf("%s", sep);
    printf("\"width\": %d%s\"height\": %d%s", img->width, sep, img->height, sep);
    printf("\"reduced_width\": %d%s\"reduced_height\": %d%s", rw, sep, rh, sep);
    printf("\"opts\": {\"palette\": ");
    print_palette_opts_json(&o->palette);
    printf(", \"match\": ");
    print_match_opts_json(&o->match, o->top);
    printf("}%s", sep);
    printf("\"swatches\": %s", aopen);
    for (i = 0; i < r->n_swatches; ++i) {
        if (i) printf("%s", asep);
        print_swatch_json(&r->swatches[i]);
    }
    printf("%s%s", aclose, sep);
    printf("\"hits\": %s", aopen);
    for (i = 0; i < n_hits; ++i) {
        if (i) printf("%s", asep);
        print_hit_json(&r->hits[i]);
    }
    printf("%s%s", aclose, sep);
    printf("\"ambiguous\": %d%s", r->ambiguous ? 1 : 0, sep);
    printf("\"hash\": \"%016" PRIx64 "\"", ce_result_hash(&truncated));
    printf(pretty ? "\n}\n" : "}\n");
}

static void print_palette_text(const ce_image *img, const ce_swatch *sw, int n)
{
    int i;
    printf("%dx%d: %d swatches\n", img->width, img->height, n);
    for (i = 0; i < n; ++i) {
        printf("#%02x%02x%02x  L=%9.4f a=%9.4f b=%9.4f  weight=%.6f\n",
               sw[i].rgb[0], sw[i].rgb[1], sw[i].rgb[2],
               sw[i].lab.L, sw[i].lab.a, sw[i].lab.b, sw[i].weight);
    }
}

static void print_result_text(const char *file, const ce_image *img, const cli_opts *o,
                              const ce_result *r)
{
    int i, k;
    const int n_hits = (o->top < r->n_hits) ? o->top : r->n_hits;
    printf("%s\n", file);
    print_palette_text(img, r->swatches, r->n_swatches);
    for (i = 0; i < n_hits; ++i) {
        uint8_t size = 0, colors[CE_DICT_COMBO_MAX];
        printf("#%d id %3u score %9.4f", i + 1, (unsigned)r->hits[i].combo_id, r->hits[i].score);
        if (ce_dict_combo((int)r->hits[i].combo_id, &size, colors) == 0) {
            printf("  size %u  colors", (unsigned)size);
            for (k = 0; k < (int)size; ++k) {
                uint8_t rgb[3] = {0, 0, 0};
                (void)ce_dict_color_rgb(colors[k], rgb);
                printf(" %u(#%02x%02x%02x)", (unsigned)colors[k], rgb[0], rgb[1], rgb[2]);
            }
        }
        printf("\n");
    }
    printf("ambiguous: %d\n", r->ambiguous ? 1 : 0);
}

/* ------------------------------------------------------------------------
 * ce palette
 * ---------------------------------------------------------------------- */

static int cmd_palette(int argc, char **argv)
{
    cli_opts o;
    loaded_image li;
    char err[512];
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    void *mem = NULL;
    ce_ctx *ctx;
    int n, rc = 2;

    if (parse_cli_opts(argc, argv, 0, &o) != 0) {
        return usage();
    }
    if (load_image(o.input, &o, &li, err, sizeof err) != 0) {
        fprintf(stderr, "%s: %s\n", o.input, err);
        return 2;
    }
    ctx = new_ctx(&mem);
    if (ctx == NULL) {
        rc = 1;
        goto done;
    }
    n = ce_palette_extract(ctx, &li.img, &o.palette, sw, CE_PALETTE_MAX_COLORS);
    if (n < 0) {
        fprintf(stderr, "ce_palette_extract: error %d\n", n);
        rc = 1;
        goto done;
    }
    if (o.json) {
        print_palette_json(&li.img, &o.palette, sw, n);
    } else {
        print_palette_text(&li.img, sw, n);
    }
    rc = 0;

done:
    free(mem);
    free_image(&li);
    return rc;
}

/* ------------------------------------------------------------------------
 * ce match / analyze / batch
 * ---------------------------------------------------------------------- */

static int cmd_match(int argc, char **argv)
{
    cli_opts o;
    loaded_image li;
    char err[512];
    ce_result res;
    void *mem = NULL;
    ce_ctx *ctx;
    int rc = 2, n;

    if (parse_cli_opts(argc, argv, 1, &o) != 0) {
        return usage();
    }
    if (load_image(o.input, &o, &li, err, sizeof err) != 0) {
        fprintf(stderr, "%s: %s\n", o.input, err);
        return 2;
    }
    ctx = new_ctx(&mem);
    if (ctx == NULL) {
        rc = 1;
        goto done;
    }
    n = ce_analyze(ctx, &li.img, &o.palette, &o.match, &res);
    if (n < 0) {
        fprintf(stderr, "ce_analyze: error %d\n", n);
        rc = 1;
        goto done;
    }
    if (o.json) {
        print_result_json(o.input, &li.img, &o, &res, 1);
    } else {
        print_result_text(o.input, &li.img, &o, &res);
    }
    rc = 0;

done:
    free(mem);
    free_image(&li);
    return rc;
}

/* Línea de error del batch: {"file": ..., "error": ...} (o texto). */
static void print_batch_error(const char *file, const char *msg, int json)
{
    if (json) {
        printf("{\"file\": ");
        print_json_string(file);
        printf(", \"error\": ");
        print_json_string(msg);
        printf("}\n");
    } else {
        printf("%s\terror\t%s\n", file, msg);
    }
    fflush(stdout);
}

static int cmd_batch(int argc, char **argv)
{
    cli_opts o;
    char err[512];
    uint8_t *list = NULL;
    size_t list_len = 0, pos = 0;
    void *mem = NULL;
    ce_ctx *ctx;
    int failed = 0, total = 0;

    if (parse_cli_opts(argc, argv, 1, &o) != 0) {
        return usage();
    }
    if (read_file(o.input, &list, &list_len, err, sizeof err) != 0) {
        fprintf(stderr, "%s: %s\n", o.input, err);
        return 2;
    }
    ctx = new_ctx(&mem);
    if (ctx == NULL) {
        free(list);
        return 1;
    }
    while (pos < list_len) {
        char path[CLI_PATH_MAX];
        size_t start = pos, end, n;
        loaded_image li;
        ce_result res;
        int rc;
        while (pos < list_len && list[pos] != '\n') {
            ++pos;
        }
        end = pos;
        if (pos < list_len) {
            ++pos; /* salta el '\n' */
        }
        /* Recorta espacios, tabs y CR a ambos lados. */
        while (start < end && (list[start] == ' ' || list[start] == '\t' || list[start] == '\r')) ++start;
        while (end > start && (list[end - 1] == ' ' || list[end - 1] == '\t' || list[end - 1] == '\r')) --end;
        n = end - start;
        if (n == 0 || list[start] == '#') {
            continue;
        }
        if (n >= sizeof path) {
            n = sizeof path - 1;
        }
        memcpy(path, list + start, n);
        path[n] = '\0';
        ++total;
        if (load_image(path, &o, &li, err, sizeof err) != 0) {
            print_batch_error(path, err, o.json);
            ++failed;
            continue;
        }
        rc = ce_analyze(ctx, &li.img, &o.palette, &o.match, &res);
        if (rc < 0) {
            snprintf(err, sizeof err, "ce_analyze: error %d", rc);
            print_batch_error(path, err, o.json);
            ++failed;
            free_image(&li);
            continue;
        }
        if (o.json) {
            print_result_json(path, &li.img, &o, &res, 0);
        } else {
            printf("%s\t%u\t%.17g\t%d\n", path, (unsigned)res.hits[0].combo_id, res.hits[0].score,
                   res.ambiguous ? 1 : 0);
        }
        fflush(stdout);
        free_image(&li);
    }
    if (failed > 0) {
        fprintf(stderr, "batch: %d de %d imagenes fallaron\n", failed, total);
    }
    free(mem);
    free(list);
    return failed > 0 ? 1 : 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        return usage();
    }
    if (strcmp(argv[1], "version") == 0) {
        printf("%s\n", ce_version());
        return 0;
    }
    if (strcmp(argv[1], "lab") == 0) {
        return cmd_lab(argc, argv);
    }
    if (strcmp(argv[1], "de2000") == 0) {
        return cmd_de2000(argc, argv);
    }
    if (strcmp(argv[1], "convert") == 0) {
        return cmd_convert();
    }
    if (strcmp(argv[1], "dict") == 0) {
        return cmd_dict(argc, argv);
    }
    if (strcmp(argv[1], "palette") == 0) {
        return cmd_palette(argc, argv);
    }
    if (strcmp(argv[1], "match") == 0 || strcmp(argv[1], "analyze") == 0) {
        return cmd_match(argc, argv);
    }
    if (strcmp(argv[1], "batch") == 0) {
        return cmd_batch(argc, argv);
    }
    return usage();
}
