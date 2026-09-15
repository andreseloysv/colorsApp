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
 *   ce palette|match|analyze ... --debug-dir DIR
 *                                   además de la salida normal (idéntica),
 *                                   escribe las capas de depuración en DIR
 *                                   (lo crea si no existe): reduced.ppm,
 *                                   weights.pgm, labels.pgm (índices crudos),
 *                                   labels.ppm (color del swatch; NONE negro,
 *                                   DISCARDED gris 128), clusters.pgm/.ppm
 *                                   (cluster de Lloyd antes de fusionar),
 *                                   swatch_<k>.pgm (255 donde el píxel
 *                                   alimenta el swatch k), mask.pgm (máscara
 *                                   reducida, con --mask) y debug.json
 *                                   (palette_debug, clusters con su destino,
 *                                   recuentos por etiqueta y, en match, la
 *                                   explicación ce_match_explain_combo de los
 *                                   top-K).
 *   ce batch lista.txt [mismas opciones] [--json]
 *                                   una entrada por línea (vacías y '#'
 *                                   ignoradas): "imagen.ppm [mascara.pgm]"
 *                                   separadas por espacio o tabulador; rutas
 *                                   con espacios entre comillas dobles. La
 *                                   máscara de la línea gana a --mask. Con
 *                                   --json una línea JSON por imagen (JSONL)
 *                                   con los campos de match más "mask"
 *                                   (ruta o null) tras "file"; una entrada
 *                                   ilegible produce {"file", "mask", "error"}
 *                                   y el proceso continúa. --raw se aplica a
 *                                   todas las imágenes.
 *   ce regions --size WxH --mask in.pgm --pose pose.txt --out out.pgm
 *            [--min-confidence F] [--torso-margin F] [--limb-width F]
 *            [--upper-arms 0|1] [--forearms 0|1] [--legs 0|1] [--lower-legs 0|1]
 *                                   ce_mask_clothing_regions. pose.txt: 15
 *                                   líneas de datos "x y confidence" en el
 *                                   orden de ce_joint (vacías y '#'
 *                                   ignoradas). Imprime {"pixels", "mask_pixels"}.
 *                                   CE_ERR_POSE: exit 1 sin escribir --out.
 *   ce skin --image img.ppm --sample sample.pgm --mask in.pgm --out out.pgm
 *            [--max-mahalanobis F] [--max-excluded F]
 *                                   ce_skin_model_fit + ce_mask_exclude_skin.
 *                                   Imprime {"excluded", "guard", "mask_pixels",
 *                                   "candidates", "model"}; con la salvaguarda
 *                                   escribe la máscara intacta (excluded 0).
 *   ce cut-head --mask in.pgm --fraction F --out out.pgm
 *                                   ce_mask_cut_head; imprime {"pixels"}.
 *
 * Salida: 0 ok, 1 error del motor (código negativo; en batch, si alguna
 * imagen falló por cualquier motivo), 2 uso o fichero inválido (en batch,
 * solo la propia lista; también si no se pueden escribir las capas).
 *
 * "convert" es la entrada del differential testing masivo contra el oráculo
 * Python (oracle/oracle/diff_oracle.py); "palette" la de la capa 2
 * (oracle/tests/test_l2_palette.py) y "match"/"batch" la de la capa 3
 * (oracle/tests/test_l3_match.py).
 */
/* mkdir (POSIX) para --debug-dir: con -std=c11 estricto hay que pedirlo. */
#define _POSIX_C_SOURCE 200809L

#include "ce/ce.h"
#include "ce_pnm.h"

#include <sys/stat.h>
#include <sys/types.h>

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
            "  ce palette|match|analyze ... --debug-dir <DIR>   (capas de depuracion en DIR)\n"
            "  ce batch <lista.txt> [mismas opciones que match] [--json]   (JSONL; lineas \"imagen [mascara]\")\n"
            "  ce regions --size WxH --mask <in.pgm> --pose <pose.txt> --out <out.pgm>\n"
            "             [--min-confidence F] [--torso-margin F] [--limb-width F]\n"
            "             [--upper-arms 0|1] [--forearms 0|1] [--legs 0|1] [--lower-legs 0|1]\n"
            "  ce skin --image <img.ppm> --sample <muestra.pgm> --mask <in.pgm> --out <out.pgm>\n"
            "             [--max-mahalanobis F] [--max-excluded F]\n"
            "  ce cut-head --mask <in.pgm> --fraction F --out <out.pgm>\n");
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
    const char *debug_dir; /* opcional: --debug-dir (palette/match/analyze) */
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
        } else if (strcmp(a, "--debug-dir") == 0 && v) {
            o->debug_dir = v; ++i;
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
static int load_image(const char *path, const char *mask_path, const cli_opts *o, loaded_image *li,
                      char *err, size_t err_len)
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

    if (mask_path != NULL) {
        ce_pnm_image pnm;
        char merr[256];
        int prc;
        if (read_file(mask_path, &li->mask_buf, &mask_len, merr, sizeof merr) != 0) {
            snprintf(err, err_len, "mascara %s: %s", mask_path, merr);
            free_image(li);
            return -1;
        }
        prc = ce_pnm_parse(li->mask_buf, mask_len, &pnm);
        if (prc != CE_PNM_OK) {
            snprintf(err, err_len, "mascara %s: %s", mask_path, ce_pnm_strerror(prc));
            free_image(li);
            return -1;
        }
        if (pnm.type != 5 || pnm.width != li->img.width || pnm.height != li->img.height) {
            snprintf(err, err_len, "mascara %s: debe ser P5 de %dx%d", mask_path,
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
static void print_result_json(const char *file, const char *mask, int with_mask, const ce_image *img,
                              const cli_opts *o, const ce_result *r, int pretty)
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
    if (with_mask) {
        printf("\"mask\": ");
        if (mask != NULL) {
            print_json_string(mask);
        } else {
            printf("null");
        }
        printf("%s", sep);
    }
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
 * Capas de depuración (--debug-dir)
 * ---------------------------------------------------------------------- */

/* Crea `dir` (un nivel) si no existe. 0 ok; -1 con el motivo en err. */
static int ensure_dir(const char *dir, char *err, size_t err_len)
{
    struct stat st;
    if (stat(dir, &st) == 0) {
        if (S_ISDIR(st.st_mode)) {
            return 0;
        }
        snprintf(err, err_len, "%s existe y no es un directorio", dir);
        return -1;
    }
    if (mkdir(dir, 0777) != 0 && errno != EEXIST) {
        snprintf(err, err_len, "no puedo crear %s (%s)", dir, strerror(errno));
        return -1;
    }
    return 0;
}

/* Escribe un P5 (channels 1) o P6 (channels 3). 0 ok; -1 con el motivo. */
static int write_pnm_file(const char *path, int channels, int w, int h, const uint8_t *data,
                          char *err, size_t err_len)
{
    const size_t n = (size_t)w * (size_t)h * (size_t)channels;
    FILE *f = fopen(path, "wb");
    int ok;
    if (f == NULL) {
        snprintf(err, err_len, "no puedo escribir %s (%s)", path, strerror(errno));
        return -1;
    }
    ok = fprintf(f, "P%d\n%d %d\n255\n", channels == 3 ? 6 : 5, w, h) > 0;
    ok = ok && fwrite(data, 1, n, f) == n;
    ok = (fclose(f) == 0) && ok;
    if (!ok) {
        snprintf(err, err_len, "error al escribir %s", path);
        return -1;
    }
    return 0;
}

static int write_pnm_in(const char *dir, const char *name, int channels, int w, int h, const uint8_t *data,
                        char *err, size_t err_len)
{
    char path[CLI_PATH_MAX + 64];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    return write_pnm_file(path, channels, w, h, data, err, err_len);
}

static const char *fate_name(int fate)
{
    switch (fate) {
    case CE_FATE_KEPT: return "kept";
    case CE_FATE_MERGED: return "merged";
    case CE_FATE_DISCARDED: return "discarded";
    case CE_FATE_TRUNCATED: return "truncated";
    default: return "unknown";
    }
}

static const char *illuminant_name(int ill)
{
    switch (ill) {
    case -1: return "none";
    case CE_ILL_A: return "A";
    case CE_ILL_D50: return "D50";
    case CE_ILL_D65: return "D65";
    case CE_ILL_D75: return "D75";
    case CE_ILL_F2: return "F2";
    default: return "unknown";
    }
}

static void fprint_json_string(FILE *f, const char *s)
{
    fputc('"', f);
    for (; *s; ++s) {
        const unsigned char c = (unsigned char)*s;
        if (c == '"' || c == '\\') {
            fputc('\\', f);
            fputc((int)c, f);
        } else if (c < 0x20) {
            fprintf(f, "\\u%04x", (unsigned)c);
        } else {
            fputc((int)c, f);
        }
    }
    fputc('"', f);
}

static void fprint_rgb_json(FILE *f, const uint8_t *rgb)
{
    fprintf(f, "\"rgb\": [%u, %u, %u], \"hex\": \"#%02x%02x%02x\"", rgb[0], rgb[1], rgb[2], rgb[0], rgb[1], rgb[2]);
}

/* Máscara reducida exactamente como la reduce el motor: la misma caja entera
 * con redondeo (ce_image_reduce) aplicada a una imagen gris con la máscara en
 * los tres canales, leída de vuelta con ce_debug_reduced_rgb. */
static int reduce_mask_like_engine(const ce_image *img, int max_side, uint8_t **out, int *rw, int *rh)
{
    const size_t n = (size_t)img->width * (size_t)img->height;
    uint8_t *gray = (uint8_t *)malloc(n * 3u);
    uint8_t *rgb = NULL;
    void *mem = NULL;
    ce_ctx *ctx;
    ce_image g;
    ce_palette_opts o;
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    ce_palette_debug info;
    size_t i, nr;
    int rc = -1;
    *out = NULL;
    if (gray == NULL) return -1;
    for (i = 0; i < n; ++i) {
        gray[i * 3] = gray[i * 3 + 1] = gray[i * 3 + 2] = img->mask[i];
    }
    ctx = new_ctx(&mem);
    if (ctx == NULL) goto done;
    g.pixels = gray;
    g.width = img->width;
    g.height = img->height;
    g.stride_bytes = img->width * 3;
    g.fmt = CE_RGB8;
    g.mask = NULL;
    ce_palette_opts_default(&o);
    o.max_side = max_side;
    o.center_sigma = 0.0;
    if (ce_palette_extract(ctx, &g, &o, sw, CE_PALETTE_MAX_COLORS) < 1) goto done;
    if (ce_palette_debug_info(ctx, &info) != CE_OK) goto done;
    nr = (size_t)info.reduced_width * (size_t)info.reduced_height;
    rgb = (uint8_t *)malloc(nr * 3u);
    *out = (uint8_t *)malloc(nr);
    if (rgb == NULL || *out == NULL) goto done;
    if (ce_debug_reduced_rgb(ctx, rgb, nr * 3u) != (int)(nr * 3u)) goto done;
    for (i = 0; i < nr; ++i) (*out)[i] = rgb[i * 3];
    *rw = info.reduced_width;
    *rh = info.reduced_height;
    rc = 0;
done:
    if (rc != 0) {
        free(*out);
        *out = NULL;
    }
    free(rgb);
    free(gray);
    free(mem);
    return rc;
}

/* Escribe todas las capas de la última extracción de `ctx` en `dir`.
 * `res` NULL = ce palette (sin match). 0 ok; -1 con el motivo en err. */
static int write_debug_dir(const char *dir, const char *file, const ce_ctx *ctx, const ce_image *img,
                           const cli_opts *o, const ce_swatch *sw, int n, const ce_result *res,
                           char *err, size_t err_len)
{
    ce_palette_debug info;
    uint8_t *reduced = NULL, *weights = NULL, *labels = NULL, *clusters = NULL, *color = NULL, *plane = NULL;
    uint8_t *rmask = NULL;
    size_t np, i;
    int rc = -1, k, c, rmw = 0, rmh = 0;
    long label_px[CE_PALETTE_MAX_COLORS] = {0}, cluster_px[CE_PALETTE_K_MAX] = {0};
    long none_px = 0, discarded_px = 0;
    char path[CLI_PATH_MAX + 64];
    FILE *f = NULL;

    if (ensure_dir(dir, err, err_len) != 0) return -1;
    if (ce_palette_debug_info(ctx, &info) != CE_OK) {
        snprintf(err, err_len, "ce_palette_debug_info: el contexto no tiene una extraccion valida");
        return -1;
    }
    np = (size_t)info.reduced_width * (size_t)info.reduced_height;
    reduced = (uint8_t *)malloc(np * 3u);
    weights = (uint8_t *)malloc(np);
    labels = (uint8_t *)malloc(np);
    clusters = (uint8_t *)malloc(np);
    color = (uint8_t *)malloc(np * 3u);
    plane = (uint8_t *)malloc(np);
    if (!reduced || !weights || !labels || !clusters || !color || !plane) {
        snprintf(err, err_len, "sin memoria");
        goto done;
    }
    if (ce_debug_reduced_rgb(ctx, reduced, np * 3u) < 0 || ce_debug_weight_map(ctx, weights, np) < 0
        || ce_debug_label_map(ctx, labels, np) < 0 || ce_debug_cluster_map(ctx, clusters, np) < 0) {
        snprintf(err, err_len, "capas de depuracion: error del motor");
        goto done;
    }
    for (i = 0; i < np; ++i) {
        if (labels[i] == CE_LABEL_NONE) ++none_px;
        else if (labels[i] == CE_LABEL_DISCARDED) ++discarded_px;
        else if (labels[i] < n) ++label_px[labels[i]];
        if (clusters[i] < info.n_clusters) ++cluster_px[clusters[i]];
    }
    if (write_pnm_in(dir, "reduced.ppm", 3, info.reduced_width, info.reduced_height, reduced, err, err_len) != 0
        || write_pnm_in(dir, "weights.pgm", 1, info.reduced_width, info.reduced_height, weights, err, err_len) != 0
        || write_pnm_in(dir, "labels.pgm", 1, info.reduced_width, info.reduced_height, labels, err, err_len) != 0
        || write_pnm_in(dir, "clusters.pgm", 1, info.reduced_width, info.reduced_height, clusters, err, err_len) != 0) {
        goto done;
    }
    for (i = 0; i < np; ++i) {
        const uint8_t l = labels[i];
        uint8_t rgb[3] = {0, 0, 0};
        if (l == CE_LABEL_DISCARDED) {
            rgb[0] = rgb[1] = rgb[2] = 128;
        } else if (l < n) {
            memcpy(rgb, sw[l].rgb, 3);
        }
        memcpy(color + i * 3u, rgb, 3);
    }
    if (write_pnm_in(dir, "labels.ppm", 3, info.reduced_width, info.reduced_height, color, err, err_len) != 0) goto done;
    for (i = 0; i < np; ++i) {
        uint8_t rgb[3] = {0, 0, 0};
        if (clusters[i] < info.n_clusters) memcpy(rgb, info.clusters[clusters[i]].rgb, 3);
        memcpy(color + i * 3u, rgb, 3);
    }
    if (write_pnm_in(dir, "clusters.ppm", 3, info.reduced_width, info.reduced_height, color, err, err_len) != 0) goto done;
    for (k = 0; k < n; ++k) {
        char name[32];
        for (i = 0; i < np; ++i) plane[i] = (labels[i] == k) ? 255 : 0;
        snprintf(name, sizeof name, "swatch_%d.pgm", k);
        if (write_pnm_in(dir, name, 1, info.reduced_width, info.reduced_height, plane, err, err_len) != 0) goto done;
    }
    if (img->mask != NULL) {
        if (reduce_mask_like_engine(img, o->palette.max_side, &rmask, &rmw, &rmh) != 0) {
            snprintf(err, err_len, "no puedo reducir la mascara");
            goto done;
        }
        if (write_pnm_in(dir, "mask.pgm", 1, rmw, rmh, rmask, err, err_len) != 0) goto done;
    }

    snprintf(path, sizeof path, "%s/debug.json", dir);
    f = fopen(path, "wb");
    if (f == NULL) {
        snprintf(err, err_len, "no puedo escribir %s (%s)", path, strerror(errno));
        goto done;
    }
    fprintf(f, "{\n  \"engine\": \"%s\",\n  \"dict_version\": \"%s\",\n  \"file\": ", ce_version(), ce_dict_version());
    fprint_json_string(f, file);
    fprintf(f, ",\n  \"mask\": ");
    if (o->mask_path != NULL) fprint_json_string(f, o->mask_path); else fprintf(f, "null");
    fprintf(f, ",\n  \"width\": %d,\n  \"height\": %d,\n  \"reduced_width\": %d,\n  \"reduced_height\": %d,\n",
            img->width, img->height, info.reduced_width, info.reduced_height);
    fprintf(f, "  \"layers\": {\"reduced\": \"reduced.ppm\", \"weights\": \"weights.pgm\", \"labels\": \"labels.pgm\", "
               "\"labels_color\": \"labels.ppm\", \"clusters\": \"clusters.pgm\", \"clusters_color\": \"clusters.ppm\", "
               "\"swatches\": [");
    for (k = 0; k < n; ++k) fprintf(f, "%s\"swatch_%d.pgm\"", k ? ", " : "", k);
    fprintf(f, "], \"mask\": %s},\n", img->mask != NULL ? "\"mask.pgm\"" : "null");
    fprintf(f, "  \"label_values\": {\"none\": %d, \"discarded\": %d},\n", CE_LABEL_NONE, CE_LABEL_DISCARDED);
    fprintf(f, "  \"palette_debug\": {\"lloyd_iterations\": %d, \"total_weight\": %.17g, \"zero_weight_fraction\": %.17g, "
               "\"center_sigma_px\": %.17g, \"n_swatches\": %d, \"n_clusters\": %d,\n    \"clusters\": [",
            info.lloyd_iterations, info.total_weight, info.zero_weight_fraction, info.center_sigma_px,
            info.n_swatches, info.n_clusters);
    for (c = 0; c < info.n_clusters; ++c) {
        const ce_cluster_debug *cd = &info.clusters[c];
        fprintf(f, "%s\n      {\"index\": %d, ", c ? "," : "", c);
        fprint_rgb_json(f, cd->rgb);
        fprintf(f, ", \"lab\": [%.17g, %.17g, %.17g], \"weight\": %.17g, \"fate\": %d, \"fate_name\": \"%s\", "
                   "\"final_index\": ", cd->lab.L, cd->lab.a, cd->lab.b, cd->weight, cd->fate, fate_name(cd->fate));
        if (cd->final_index >= 0) fprintf(f, "%d", cd->final_index); else fprintf(f, "null");
        fprintf(f, ", \"group_head\": %d, \"pixels\": %ld}", cd->group_head, cluster_px[c]);
    }
    fprintf(f, "%s]},\n  \"swatches\": [", info.n_clusters ? "\n    " : "");
    for (k = 0; k < n; ++k) {
        fprintf(f, "%s\n    {\"index\": %d, ", k ? "," : "", k);
        fprint_rgb_json(f, sw[k].rgb);
        fprintf(f, ", \"lab\": [%.17g, %.17g, %.17g], \"weight\": %.17g, \"pixels\": %ld, \"layer\": \"swatch_%d.pgm\"}",
                sw[k].lab.L, sw[k].lab.a, sw[k].lab.b, sw[k].weight, label_px[k], k);
    }
    fprintf(f, "\n  ],\n  \"label_counts\": {\"none\": %ld, \"discarded\": %ld},\n", none_px, discarded_px);
    fprintf(f, "  \"opts\": {\"palette\": ");
    {
        /* print_palette_opts_json escribe en stdout: se replica en f. */
        const ce_palette_opts *po = &o->palette;
        fprintf(f, "{\"k_init\": %d, \"max_iters\": %d, \"max_colors\": %d, \"max_side\": %d, "
                   "\"center_sigma\": %.17g, \"merge_de\": %.17g, \"min_weight\": %.17g, \"skin_rule\": %d}",
                po->k_init, po->max_iters, po->max_colors, po->max_side, po->center_sigma, po->merge_de,
                po->min_weight, po->skin_rule ? 1 : 0);
    }
    if (res == NULL) {
        fprintf(f, ", \"match\": null},\n  \"hits\": null,\n  \"ambiguous\": null,\n  \"explain\": null\n}\n");
    } else {
        const ce_match_opts *mo = &o->match;
        const int top = (o->top < res->n_hits) ? o->top : res->n_hits;
        int h;
        fprintf(f, ", \"match\": {\"kL\": %.17g, \"kC\": %.17g, \"kH\": %.17g, \"coverage_lambda\": %.17g, "
                   "\"ambiguous_gap\": %.17g, \"exposure_ev_max\": %.17g, \"exposure_penalty\": %.17g, "
                   "\"illuminant_search\": %d, \"illuminant_penalty\": %.17g, \"top\": %d}},\n",
                mo->kL, mo->kC, mo->kH, mo->coverage_lambda, mo->ambiguous_gap, mo->exposure_ev_max,
                mo->exposure_penalty, mo->illuminant_search ? 1 : 0, mo->illuminant_penalty, o->top);
        fprintf(f, "  \"hits\": [");
        for (h = 0; h < top; ++h) {
            fprintf(f, "%s{\"id\": %u, \"score\": %.17g}", h ? ", " : "", (unsigned)res->hits[h].combo_id,
                    res->hits[h].score);
        }
        fprintf(f, "],\n  \"ambiguous\": %d,\n  \"explain\": [", res->ambiguous ? 1 : 0);
        for (h = 0; h < top; ++h) {
            ce_match_explain e;
            int j;
            if (ce_match_explain_combo(ctx, res->swatches, res->n_swatches, mo, res->hits[h].combo_id, &e) != CE_OK) {
                snprintf(err, err_len, "ce_match_explain_combo: error");
                goto done;
            }
            fprintf(f, "%s\n    {\"rank\": %d, \"id\": %u, \"score\": %.17g, \"score_equals_match\": %s, "
                       "\"fit_term\": %.17g, \"coverage_term\": %.17g, \"hypothesis_penalty\": %.17g, "
                       "\"exposure_ev\": %.17g, \"illuminant\": %d, \"illuminant_name\": \"%s\",\n      \"per_swatch\": [",
                    h ? "," : "", h + 1, (unsigned)e.combo_id, e.score,
                    memcmp(&e.score, &res->hits[h].score, sizeof(double)) == 0 ? "true" : "false",
                    e.fit_term, e.coverage_term, e.hypothesis_penalty, e.exposure_ev, e.illuminant,
                    illuminant_name(e.illuminant));
            for (j = 0; j < e.n_swatches; ++j) {
                uint8_t rgb[3] = {0, 0, 0};
                (void)ce_dict_color_rgb(e.per_swatch[j].nearest_color_index, rgb);
                fprintf(f, "%s{\"swatch\": %d, \"nearest_color\": %d, \"nearest_color_hex\": \"#%02x%02x%02x\", \"de\": %.17g}",
                        j ? ", " : "", j, e.per_swatch[j].nearest_color_index, rgb[0], rgb[1], rgb[2], e.per_swatch[j].de);
            }
            fprintf(f, "],\n      \"per_color\": [");
            for (j = 0; j < e.combo_size; ++j) {
                uint8_t rgb[3] = {0, 0, 0};
                const char *name = ce_dict_color_name(e.per_color[j].color_index);
                (void)ce_dict_color_rgb(e.per_color[j].color_index, rgb);
                fprintf(f, "%s{\"color\": %d, \"hex\": \"#%02x%02x%02x\", \"name\": ", j ? ", " : "",
                        e.per_color[j].color_index, rgb[0], rgb[1], rgb[2]);
                fprint_json_string(f, name != NULL ? name : "");
                fprintf(f, ", \"nearest_swatch\": %d, \"de\": %.17g}", e.per_color[j].nearest_swatch, e.per_color[j].de);
            }
            fprintf(f, "]}");
        }
        fprintf(f, "%s]\n}\n", top ? "\n  " : "");
    }
    if (fclose(f) != 0) {
        f = NULL;
        snprintf(err, err_len, "error al escribir %s", path);
        goto done;
    }
    f = NULL;
    rc = 0;
done:
    if (f != NULL) fclose(f);
    free(reduced);
    free(weights);
    free(labels);
    free(clusters);
    free(color);
    free(plane);
    free(rmask);
    return rc;
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
    if (load_image(o.input, o.mask_path, &o, &li, err, sizeof err) != 0) {
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
    if (o.debug_dir != NULL
        && write_debug_dir(o.debug_dir, o.input, ctx, &li.img, &o, sw, n, NULL, err, sizeof err) != 0) {
        fprintf(stderr, "--debug-dir: %s\n", err);
        rc = 2;
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
    if (load_image(o.input, o.mask_path, &o, &li, err, sizeof err) != 0) {
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
    if (o.debug_dir != NULL
        && write_debug_dir(o.debug_dir, o.input, ctx, &li.img, &o, res.swatches, res.n_swatches, &res, err,
                           sizeof err) != 0) {
        fprintf(stderr, "--debug-dir: %s\n", err);
        rc = 2;
        goto done;
    }
    if (o.json) {
        print_result_json(o.input, NULL, 0, &li.img, &o, &res, 1);
    } else {
        print_result_text(o.input, &li.img, &o, &res);
    }
    rc = 0;

done:
    free(mem);
    free_image(&li);
    return rc;
}

/* Línea de error del batch: {"file": ..., "mask": ..., "error": ...} (o texto). */
static void print_batch_error(const char *file, const char *mask, const char *msg, int json)
{
    if (json) {
        printf("{\"file\": ");
        print_json_string(file);
        printf(", \"mask\": ");
        if (mask != NULL) {
            print_json_string(mask);
        } else {
            printf("null");
        }
        printf(", \"error\": ");
        print_json_string(msg);
        printf("}\n");
    } else {
        printf("%s\terror\t%s\n", file, msg);
    }
    fflush(stdout);
}

/* Divide una entrada de la lista (ya recortada, sin '\n') en 1 o 2 rutas:
 * separadas por espacios o tabuladores; una ruta entre comillas dobles puede
 * contener espacios (sin escapes). Devuelve el número de rutas, o -1 con el
 * motivo en `why` (y en `p1` lo que se pudo leer, para el campo "file"). */
static int split_list_entry(const uint8_t *line, size_t n, char paths[2][CLI_PATH_MAX], const char **why)
{
    size_t i = 0;
    int count = 0;
    paths[0][0] = '\0';
    paths[1][0] = '\0';
    while (i < n) {
        size_t start, end, len;
        while (i < n && (line[i] == ' ' || line[i] == '\t')) ++i;
        if (i >= n) break;
        if (count == 2) {
            *why = "la entrada tiene mas de dos rutas (imagen [mascara]; use comillas para rutas con espacios)";
            return -1;
        }
        if (line[i] == '"') {
            start = ++i;
            while (i < n && line[i] != '"') ++i;
            if (i >= n) {
                *why = "comillas sin cerrar";
                return -1;
            }
            end = i++;
            if (i < n && line[i] != ' ' && line[i] != '\t') {
                *why = "caracteres tras las comillas de cierre";
                return -1;
            }
        } else {
            start = i;
            while (i < n && line[i] != ' ' && line[i] != '\t') {
                if (line[i] == '"') {
                    *why = "comillas en mitad de una ruta";
                    return -1;
                }
                ++i;
            }
            end = i;
        }
        len = end - start;
        if (len == 0) {
            *why = "ruta vacia";
            return -1;
        }
        if (len >= CLI_PATH_MAX) {
            *why = "ruta demasiado larga";
            return -1;
        }
        memcpy(paths[count], line + start, len);
        paths[count][len] = '\0';
        ++count;
    }
    if (count == 0) {
        *why = "entrada vacia";
        return -1;
    }
    return count;
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

    if (parse_cli_opts(argc, argv, 1, &o) != 0 || o.debug_dir != NULL) {
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
        char paths[2][CLI_PATH_MAX];
        size_t start = pos, end, n;
        loaded_image li;
        ce_result res;
        const char *why = NULL;
        const char *path, *mask;
        int rc, np;
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
        ++total;
        np = split_list_entry(list + start, n, paths, &why);
        if (np < 0) {
            char raw[CLI_PATH_MAX];
            const size_t rn = n < sizeof raw - 1 ? n : sizeof raw - 1;
            memcpy(raw, list + start, rn);
            raw[rn] = '\0';
            print_batch_error(raw, NULL, why, o.json);
            ++failed;
            continue;
        }
        path = paths[0];
        mask = (np == 2) ? paths[1] : o.mask_path; /* la máscara de la línea gana */
        if (load_image(path, mask, &o, &li, err, sizeof err) != 0) {
            print_batch_error(path, mask, err, o.json);
            ++failed;
            continue;
        }
        rc = ce_analyze(ctx, &li.img, &o.palette, &o.match, &res);
        if (rc < 0) {
            snprintf(err, sizeof err, "ce_analyze: error %d", rc);
            print_batch_error(path, mask, err, o.json);
            ++failed;
            free_image(&li);
            continue;
        }
        if (o.json) {
            print_result_json(path, mask, 1, &li.img, &o, &res, 0);
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

/* ------------------------------------------------------------------------
 * ce regions / skin / cut-head (máscaras)
 * ---------------------------------------------------------------------- */

/* Carga un PGM (P5) completo. 0 ok; -1 con el motivo. `buf` queda a cargo
 * del llamante (free). */
static int load_pgm(const char *path, uint8_t **buf, const uint8_t **data, int *w, int *h, char *err, size_t err_len)
{
    size_t len = 0;
    ce_pnm_image pnm;
    int prc;
    *buf = NULL;
    if (read_file(path, buf, &len, err, err_len) != 0) {
        return -1;
    }
    prc = ce_pnm_parse(*buf, len, &pnm);
    if (prc != CE_PNM_OK || pnm.type != 5) {
        snprintf(err, err_len, "%s", prc != CE_PNM_OK ? ce_pnm_strerror(prc) : "debe ser P5 (gris)");
        free(*buf);
        *buf = NULL;
        return -1;
    }
    *data = pnm.data;
    *w = pnm.width;
    *h = pnm.height;
    return 0;
}

/* Lee 15 líneas de datos "x y confidence" (vacías y '#' ignoradas). */
static int load_pose(const char *path, ce_pose *pose, char *err, size_t err_len)
{
    uint8_t *buf = NULL;
    size_t len = 0, pos = 0;
    int count = 0;
    if (read_file(path, &buf, &len, err, err_len) != 0) {
        return -1;
    }
    while (pos < len) {
        char line[512];
        size_t start = pos, n;
        char *p, *end;
        double v[3];
        int k;
        while (pos < len && buf[pos] != '\n') ++pos;
        n = pos - start;
        if (pos < len) ++pos;
        if (n >= sizeof line) {
            snprintf(err, err_len, "linea de pose demasiado larga");
            free(buf);
            return -1;
        }
        memcpy(line, buf + start, n);
        line[n] = '\0';
        p = line;
        while (*p == ' ' || *p == '\t' || *p == '\r') ++p;
        if (*p == '\0' || *p == '#') continue;
        for (k = 0; k < 3; ++k) {
            errno = 0;
            v[k] = strtod(p, &end);
            if (end == p) {
                snprintf(err, err_len, "linea de pose %d: se esperaban 3 numeros \"x y confidence\"", count + 1);
                free(buf);
                return -1;
            }
            p = end;
        }
        while (*p == ' ' || *p == '\t' || *p == '\r') ++p;
        if (*p != '\0') {
            snprintf(err, err_len, "linea de pose %d: sobran caracteres", count + 1);
            free(buf);
            return -1;
        }
        if (count >= CE_JOINT_COUNT) {
            snprintf(err, err_len, "la pose tiene mas de %d puntos", CE_JOINT_COUNT);
            free(buf);
            return -1;
        }
        pose->k[count].x = v[0];
        pose->k[count].y = v[1];
        pose->k[count].confidence = v[2];
        ++count;
    }
    free(buf);
    if (count != CE_JOINT_COUNT) {
        snprintf(err, err_len, "la pose tiene %d puntos (se esperaban %d en el orden de ce_joint)", count, CE_JOINT_COUNT);
        return -1;
    }
    return 0;
}

static int count_mask(const uint8_t *m, size_t n)
{
    size_t i;
    int c = 0;
    for (i = 0; i < n; ++i) c += m[i] != 0;
    return c;
}

static int parse_flag01(const char *s, int *out)
{
    return parse_int_opt(s, out) && (*out == 0 || *out == 1);
}

static int cmd_regions(int argc, char **argv)
{
    const char *mask_path = NULL, *pose_path = NULL, *out_path = NULL;
    int size_w = 0, size_h = 0, i, w, h, rc, n_in;
    ce_region_opts ro;
    ce_pose pose;
    uint8_t *buf = NULL, *m = NULL;
    const uint8_t *data;
    char err[512];

    ce_region_opts_default(&ro);
    for (i = 2; i < argc; i += 2) {
        const char *a = argv[i];
        const char *v = (i + 1 < argc) ? argv[i + 1] : NULL;
        if (v == NULL) return usage();
        if (strcmp(a, "--size") == 0) {
            if (!parse_dims(v, &size_w, &size_h)) return usage();
        } else if (strcmp(a, "--mask") == 0) {
            mask_path = v;
        } else if (strcmp(a, "--pose") == 0) {
            pose_path = v;
        } else if (strcmp(a, "--out") == 0) {
            out_path = v;
        } else if (strcmp(a, "--min-confidence") == 0) {
            if (!parse_double(v, &ro.min_confidence)) return usage();
        } else if (strcmp(a, "--torso-margin") == 0) {
            if (!parse_double(v, &ro.torso_margin)) return usage();
        } else if (strcmp(a, "--limb-width") == 0) {
            if (!parse_double(v, &ro.limb_width)) return usage();
        } else if (strcmp(a, "--upper-arms") == 0) {
            if (!parse_flag01(v, &ro.include_upper_arms)) return usage();
        } else if (strcmp(a, "--forearms") == 0) {
            if (!parse_flag01(v, &ro.include_forearms)) return usage();
        } else if (strcmp(a, "--legs") == 0) {
            if (!parse_flag01(v, &ro.include_legs)) return usage();
        } else if (strcmp(a, "--lower-legs") == 0) {
            if (!parse_flag01(v, &ro.include_lower_legs)) return usage();
        } else {
            return usage();
        }
    }
    if (mask_path == NULL || pose_path == NULL || out_path == NULL || size_w < 1) {
        return usage();
    }
    if (load_pgm(mask_path, &buf, &data, &w, &h, err, sizeof err) != 0) {
        fprintf(stderr, "%s: %s\n", mask_path, err);
        return 2;
    }
    if (w != size_w || h != size_h) {
        fprintf(stderr, "%s: la mascara es %dx%d y --size dice %dx%d\n", mask_path, w, h, size_w, size_h);
        free(buf);
        return 2;
    }
    if (load_pose(pose_path, &pose, err, sizeof err) != 0) {
        fprintf(stderr, "%s: %s\n", pose_path, err);
        free(buf);
        return 2;
    }
    m = (uint8_t *)malloc((size_t)w * (size_t)h);
    if (m == NULL) {
        free(buf);
        return 1;
    }
    memcpy(m, data, (size_t)w * (size_t)h);
    n_in = count_mask(m, (size_t)w * (size_t)h);
    rc = ce_mask_clothing_regions(&pose, &ro, m, w, h);
    if (rc < 0) {
        fprintf(stderr, "ce_mask_clothing_regions: error %d%s\n", rc,
                rc == CE_ERR_POSE ? " (CE_ERR_POSE: faltan hombros o caderas o la pose es degenerada)" : "");
        free(m);
        free(buf);
        return 1;
    }
    if (write_pnm_file(out_path, 1, w, h, m, err, sizeof err) != 0) {
        fprintf(stderr, "%s\n", err);
        free(m);
        free(buf);
        return 2;
    }
    printf("{\"pixels\": %d, \"mask_pixels\": %d}\n", rc, n_in);
    free(m);
    free(buf);
    return 0;
}

static int cmd_skin(int argc, char **argv)
{
    const char *image_path = NULL, *sample_path = NULL, *mask_path = NULL, *out_path = NULL;
    ce_skin_opts so, measure;
    ce_skin_model model;
    cli_opts dummy;
    loaded_image li;
    uint8_t *sbuf = NULL, *mbuf = NULL, *m = NULL, *probe = NULL;
    const uint8_t *sdata, *mdata;
    int i, sw, sh, mw, mh, rc = 2, frc, n_in, n_out, n_cand, k;
    size_t np;
    char err[512];

    ce_skin_opts_default(&so);
    for (i = 2; i < argc; i += 2) {
        const char *a = argv[i];
        const char *v = (i + 1 < argc) ? argv[i + 1] : NULL;
        if (v == NULL) return usage();
        if (strcmp(a, "--image") == 0) {
            image_path = v;
        } else if (strcmp(a, "--sample") == 0) {
            sample_path = v;
        } else if (strcmp(a, "--mask") == 0) {
            mask_path = v;
        } else if (strcmp(a, "--out") == 0) {
            out_path = v;
        } else if (strcmp(a, "--max-mahalanobis") == 0) {
            if (!parse_double(v, &so.max_mahalanobis)) return usage();
        } else if (strcmp(a, "--max-excluded") == 0) {
            if (!parse_double(v, &so.max_excluded_fraction)) return usage();
        } else {
            return usage();
        }
    }
    if (image_path == NULL || sample_path == NULL || mask_path == NULL || out_path == NULL) {
        return usage();
    }
    memset(&dummy, 0, sizeof dummy);
    if (load_image(image_path, NULL, &dummy, &li, err, sizeof err) != 0) {
        fprintf(stderr, "%s: %s\n", image_path, err);
        return 2;
    }
    if (load_pgm(sample_path, &sbuf, &sdata, &sw, &sh, err, sizeof err) != 0) {
        fprintf(stderr, "%s: %s\n", sample_path, err);
        goto done;
    }
    if (load_pgm(mask_path, &mbuf, &mdata, &mw, &mh, err, sizeof err) != 0) {
        fprintf(stderr, "%s: %s\n", mask_path, err);
        goto done;
    }
    if (sw != li.img.width || sh != li.img.height || mw != li.img.width || mh != li.img.height) {
        fprintf(stderr, "la muestra y la mascara deben ser P5 de %dx%d\n", li.img.width, li.img.height);
        goto done;
    }
    np = (size_t)mw * (size_t)mh;
    m = (uint8_t *)malloc(np);
    probe = (uint8_t *)malloc(np);
    if (m == NULL || probe == NULL) {
        rc = 1;
        goto done;
    }
    frc = ce_skin_model_fit(&li.img, sdata, &model);
    if (frc != CE_OK) {
        fprintf(stderr, "ce_skin_model_fit: error %d%s\n", frc,
                frc == CE_ERR_SKIN_SAMPLES ? " (CE_ERR_SKIN_SAMPLES: menos de 50 muestras >= 128)" : "");
        rc = 1;
        goto done;
    }
    memcpy(m, mdata, np);
    n_in = count_mask(m, np);
    /* Candidatos sin salvaguarda (solo informativo). */
    memcpy(probe, mdata, np);
    measure = so;
    measure.max_excluded_fraction = 1.0;
    frc = ce_mask_exclude_skin(&li.img, &model, &measure, probe);
    if (frc < 0) {
        fprintf(stderr, "ce_mask_exclude_skin: error %d\n", frc);
        rc = 1;
        goto done;
    }
    n_cand = n_in - count_mask(probe, np);
    frc = ce_mask_exclude_skin(&li.img, &model, &so, m);
    if (frc < 0) {
        fprintf(stderr, "ce_mask_exclude_skin: error %d\n", frc);
        rc = 1;
        goto done;
    }
    n_out = count_mask(m, np);
    if (write_pnm_file(out_path, 1, mw, mh, m, err, sizeof err) != 0) {
        fprintf(stderr, "%s\n", err);
        goto done;
    }
    printf("{\"excluded\": %d, \"guard\": %d, \"mask_pixels\": %d, \"candidates\": %d, \"model\": {\"n\": %d, "
           "\"mean\": [%.17g, %.17g, %.17g], \"cov\": [",
           n_in - n_out, frc == CE_SKIN_GUARD ? 1 : 0, n_in, n_cand, model.n, model.mean.L, model.mean.a, model.mean.b);
    for (k = 0; k < 9; ++k) printf("%s%.17g", k ? ", " : "", model.cov[k]);
    printf("], \"inv_cov\": [");
    for (k = 0; k < 9; ++k) printf("%s%.17g", k ? ", " : "", model.inv_cov[k]);
    printf("]}}\n");
    rc = 0;
done:
    free(m);
    free(probe);
    free(sbuf);
    free(mbuf);
    free_image(&li);
    return rc;
}

static int cmd_cut_head(int argc, char **argv)
{
    const char *mask_path = NULL, *out_path = NULL;
    double fraction = -1.0;
    uint8_t *buf = NULL, *m;
    const uint8_t *data;
    int i, w, h, rc;
    char err[512];
    for (i = 2; i < argc; i += 2) {
        const char *a = argv[i];
        const char *v = (i + 1 < argc) ? argv[i + 1] : NULL;
        if (v == NULL) return usage();
        if (strcmp(a, "--mask") == 0) {
            mask_path = v;
        } else if (strcmp(a, "--out") == 0) {
            out_path = v;
        } else if (strcmp(a, "--fraction") == 0) {
            if (!parse_double(v, &fraction)) return usage();
        } else {
            return usage();
        }
    }
    if (mask_path == NULL || out_path == NULL) return usage();
    if (load_pgm(mask_path, &buf, &data, &w, &h, err, sizeof err) != 0) {
        fprintf(stderr, "%s: %s\n", mask_path, err);
        return 2;
    }
    m = (uint8_t *)malloc((size_t)w * (size_t)h);
    if (m == NULL) {
        free(buf);
        return 1;
    }
    memcpy(m, data, (size_t)w * (size_t)h);
    rc = ce_mask_cut_head(m, w, h, fraction);
    if (rc < 0) {
        fprintf(stderr, "ce_mask_cut_head: error %d\n", rc);
        free(m);
        free(buf);
        return 1;
    }
    if (write_pnm_file(out_path, 1, w, h, m, err, sizeof err) != 0) {
        fprintf(stderr, "%s\n", err);
        free(m);
        free(buf);
        return 2;
    }
    printf("{\"pixels\": %d}\n", rc);
    free(m);
    free(buf);
    return 0;
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
    if (strcmp(argv[1], "regions") == 0) {
        return cmd_regions(argc, argv);
    }
    if (strcmp(argv[1], "skin") == 0) {
        return cmd_skin(argc, argv);
    }
    if (strcmp(argv[1], "cut-head") == 0) {
        return cmd_cut_head(argc, argv);
    }
    return usage();
}
