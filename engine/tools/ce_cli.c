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
 *                                   sin --json, una tabla. Salida: 0 ok, 1
 *                                   error del motor, 2 uso o fichero inválido.
 *
 * "convert" es la entrada del differential testing masivo contra el oráculo
 * Python (oracle/oracle/diff_oracle.py); "palette" la de la capa 2
 * (oracle/tests/test_l2_palette.py).
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
            "             [--k-init N] [--max-iters N] [--max-side N] [--skin-rule 0|1] [--json]\n");
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
 * ce palette
 * ---------------------------------------------------------------------- */

/* Lee un fichero completo a memoria (malloc). 0 ok, -1 error. */
static int read_file(const char *path, uint8_t **out, size_t *out_len)
{
    FILE *f = fopen(path, "rb");
    uint8_t *buf = NULL;
    size_t cap = 1u << 16, len = 0;
    if (f == NULL) {
        fprintf(stderr, "no puedo abrir %s\n", path);
        return -1;
    }
    buf = (uint8_t *)malloc(cap);
    if (buf == NULL) {
        fclose(f);
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
        fprintf(stderr, "error leyendo %s\n", path);
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
    printf("  \"opts\": {\"k_init\": %d, \"max_iters\": %d, \"max_colors\": %d, \"max_side\": %d, "
           "\"center_sigma\": %.17g, \"merge_de\": %.17g, \"min_weight\": %.17g, \"skin_rule\": %d},\n",
           o->k_init, o->max_iters, o->max_colors, o->max_side,
           o->center_sigma, o->merge_de, o->min_weight, o->skin_rule ? 1 : 0);
    printf("  \"swatches\": [\n");
    for (i = 0; i < n; ++i) {
        printf("    {\"rgb\": [%u, %u, %u], \"hex\": \"#%02x%02x%02x\", "
               "\"lab\": [%.17g, %.17g, %.17g], \"weight\": %.17g}%s\n",
               sw[i].rgb[0], sw[i].rgb[1], sw[i].rgb[2],
               sw[i].rgb[0], sw[i].rgb[1], sw[i].rgb[2],
               sw[i].lab.L, sw[i].lab.a, sw[i].lab.b, sw[i].weight,
               (i + 1 < n) ? "," : "");
    }
    printf("  ],\n");
    printf("  \"hash\": \"%016" PRIx64 "\"\n", ce_swatch_hash(sw, n));
    printf("}\n");
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

static int cmd_palette(int argc, char **argv)
{
    const char *img_path = NULL, *mask_path = NULL;
    int raw_w = 0, raw_h = 0, json = 0, i, n;
    uint8_t *img_buf = NULL, *mask_buf = NULL;
    size_t img_len = 0, mask_len = 0;
    ce_palette_opts opts;
    ce_image img;
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    void *mem = NULL;
    ce_ctx *ctx = NULL;
    int rc = 2;

    ce_palette_opts_default(&opts);
    for (i = 2; i < argc; ++i) {
        const char *a = argv[i];
        if (strcmp(a, "--json") == 0) {
            json = 1;
        } else if (strcmp(a, "--mask") == 0 && i + 1 < argc) {
            mask_path = argv[++i];
        } else if (strcmp(a, "--raw") == 0 && i + 1 < argc) {
            if (!parse_dims(argv[++i], &raw_w, &raw_h)) return usage();
        } else if (strcmp(a, "--center-sigma") == 0 && i + 1 < argc) {
            if (!parse_double(argv[++i], &opts.center_sigma)) return usage();
        } else if (strcmp(a, "--min-weight") == 0 && i + 1 < argc) {
            if (!parse_double(argv[++i], &opts.min_weight)) return usage();
        } else if (strcmp(a, "--merge-de") == 0 && i + 1 < argc) {
            if (!parse_double(argv[++i], &opts.merge_de)) return usage();
        } else if (strcmp(a, "--max-colors") == 0 && i + 1 < argc) {
            if (!parse_int_opt(argv[++i], &opts.max_colors)) return usage();
        } else if (strcmp(a, "--k-init") == 0 && i + 1 < argc) {
            if (!parse_int_opt(argv[++i], &opts.k_init)) return usage();
        } else if (strcmp(a, "--max-iters") == 0 && i + 1 < argc) {
            if (!parse_int_opt(argv[++i], &opts.max_iters)) return usage();
        } else if (strcmp(a, "--max-side") == 0 && i + 1 < argc) {
            if (!parse_int_opt(argv[++i], &opts.max_side)) return usage();
        } else if (strcmp(a, "--skin-rule") == 0 && i + 1 < argc) {
            if (!parse_int_opt(argv[++i], &opts.skin_rule)) return usage();
        } else if (a[0] == '-' && a[1] == '-') {
            return usage();
        } else if (img_path == NULL) {
            img_path = a;
        } else {
            return usage();
        }
    }
    if (img_path == NULL) {
        return usage();
    }

    if (read_file(img_path, &img_buf, &img_len) != 0) {
        return 2;
    }
    memset(&img, 0, sizeof img);
    img.fmt = CE_RGB8;
    if (raw_w > 0) {
        const size_t need = (size_t)raw_w * (size_t)raw_h * 3u;
        if (img_len != need) {
            fprintf(stderr, "%s: --raw %dx%d exige %zu bytes y el fichero tiene %zu\n",
                    img_path, raw_w, raw_h, need, img_len);
            goto done;
        }
        img.pixels = img_buf;
        img.width = raw_w;
        img.height = raw_h;
    } else {
        ce_pnm_image pnm;
        int prc = ce_pnm_parse(img_buf, img_len, &pnm);
        if (prc != CE_PNM_OK) {
            fprintf(stderr, "%s: %s\n", img_path, ce_pnm_strerror(prc));
            goto done;
        }
        if (pnm.type != 6) {
            fprintf(stderr, "%s: la imagen debe ser P6 (RGB)\n", img_path);
            goto done;
        }
        img.pixels = pnm.data;
        img.width = pnm.width;
        img.height = pnm.height;
    }
    img.stride_bytes = img.width * 3;

    if (mask_path != NULL) {
        ce_pnm_image pnm;
        int prc;
        if (read_file(mask_path, &mask_buf, &mask_len) != 0) {
            goto done;
        }
        prc = ce_pnm_parse(mask_buf, mask_len, &pnm);
        if (prc != CE_PNM_OK) {
            fprintf(stderr, "%s: %s\n", mask_path, ce_pnm_strerror(prc));
            goto done;
        }
        if (pnm.type != 5 || pnm.width != img.width || pnm.height != img.height) {
            fprintf(stderr, "%s: la mascara debe ser P5 de %dx%d\n", mask_path, img.width, img.height);
            goto done;
        }
        img.mask = pnm.data;
    }

    mem = aligned_alloc(16, ce_ctx_size());
    ctx = (mem != NULL) ? ce_ctx_init(mem, ce_ctx_size()) : NULL;
    if (ctx == NULL) {
        fprintf(stderr, "no puedo reservar el contexto (%zu bytes)\n", ce_ctx_size());
        rc = 1;
        goto done;
    }
    n = ce_palette_extract(ctx, &img, &opts, sw, CE_PALETTE_MAX_COLORS);
    if (n < 0) {
        fprintf(stderr, "ce_palette_extract: error %d\n", n);
        rc = 1;
        goto done;
    }
    if (json) {
        print_palette_json(&img, &opts, sw, n);
    } else {
        print_palette_text(&img, sw, n);
    }
    rc = 0;

done:
    free(mem);
    free(mask_buf);
    free(img_buf);
    return rc;
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
    return usage();
}
