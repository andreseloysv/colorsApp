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
 *
 * "convert" es la entrada del differential testing masivo contra el oráculo
 * Python (oracle/oracle/diff_oracle.py).
 */
#include "ce/ce.h"

#include <errno.h>
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
            "  ce convert   (stdin: lineas \"R G B\" -> stdout: \"L a b\")\n");
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
    return usage();
}
