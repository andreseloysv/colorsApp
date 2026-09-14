/*
 * test_dict.c — tests del diccionario de Wada embebido (ce_dict.c) con Unity.
 *
 * Comprueba las invariantes del diccionario desde la API pública (159 colores,
 * 348 combinaciones con ids 1..348 sin huecos, histograma 120/120/108, índices
 * válidos y ascendentes, relleno CE_DICT_NO_COLOR) y cruza el Lab de los 159
 * colores con engine/tests/data/golden_wada_lab.tsv (oráculo Python,
 * oracle/oracle/gen_golden.py) a 1e-9. La cabecera del golden lleva el
 * dict_version con el que se generó: debe coincidir con ce_dict_version().
 *
 * El mismo binario corre en nativo, con ASan/UBSan y en WebAssembly.
 */
#include "ce/ce.h"
#include "unity.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma STDC FP_CONTRACT OFF

#ifndef CE_TEST_DATA_DIR
#error "CE_TEST_DATA_DIR debe definirse (ruta a engine/tests/data)"
#endif

#define MAX_LINE 1024
#define TOL_GOLDEN 1e-9
#define EXPECTED_COLORS 159
#define EXPECTED_COMBOS 348
#define DICT_VERSION_LEN 12

void setUp(void) {}
void tearDown(void) {}

/* ------------------------------------------------------------------------
 * Utilidades de lectura
 * ---------------------------------------------------------------------- */

static FILE *open_data(const char *name)
{
    char path[1024];
    FILE *f;
    snprintf(path, sizeof path, "%s/%s", CE_TEST_DATA_DIR, name);
    f = fopen(path, "r");
    if (!f) {
        printf("no puedo abrir %s\n", path);
    }
    TEST_ASSERT_NOT_NULL_MESSAGE(f, "fichero de datos no encontrado");
    return f;
}

static int parse_doubles(const char *line, double *out, int max)
{
    const char *p = line;
    int n = 0;
    while (n < max) {
        char *end;
        double v;
        while (*p == ' ' || *p == '\t') {
            ++p;
        }
        if (*p == '\0' || *p == '\n' || *p == '\r') {
            break;
        }
        v = strtod(p, &end);
        if (end == p) {
            break;
        }
        out[n++] = v;
        p = end;
    }
    return n;
}

static int is_comment_or_blank(const char *line)
{
    while (*line == ' ' || *line == '\t') {
        ++line;
    }
    return *line == '#' || *line == '\n' || *line == '\r' || *line == '\0';
}

/* Extrae el valor de una cabecera "# dict_version: xxxx" en `out` (cap bytes).
 * Devuelve 1 si la línea era esa cabecera. */
static int parse_version_header(const char *line, char *out, size_t cap)
{
    static const char key[] = "# dict_version:";
    const char *p;
    size_t n = 0;
    if (strncmp(line, key, sizeof key - 1) != 0) {
        return 0;
    }
    p = line + sizeof key - 1;
    while (*p == ' ' || *p == '\t') {
        ++p;
    }
    while (*p && *p != '\n' && *p != '\r' && *p != ' ' && *p != '\t' && n + 1 < cap) {
        out[n++] = *p++;
    }
    out[n] = '\0';
    return 1;
}

/* ------------------------------------------------------------------------
 * Tests
 * ---------------------------------------------------------------------- */

/* 1. Tamaños y formato de la versión (12 hex en minúsculas). */
static void test_counts_and_version(void)
{
    const char *v = ce_dict_version();
    size_t i;
    TEST_ASSERT_EQUAL_INT(EXPECTED_COLORS, ce_dict_num_colors());
    TEST_ASSERT_EQUAL_INT(EXPECTED_COMBOS, ce_dict_num_combos());
    TEST_ASSERT_NOT_NULL(v);
    TEST_ASSERT_EQUAL_size_t(DICT_VERSION_LEN, strlen(v));
    for (i = 0; i < strlen(v); ++i) {
        const char c = v[i];
        TEST_ASSERT_TRUE_MESSAGE((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'),
                                 "dict_version debe ser hex en minusculas");
    }
    printf("dict_version=%s\n", v);
}

/* 2. ids 1..348 sin huecos, histograma 120/120/108, índices válidos y
 *    ascendentes, relleno CE_DICT_NO_COLOR, todo color usado al menos una vez. */
static void test_combos_invariants(void)
{
    int hist[CE_DICT_COMBO_MAX + 1] = {0};
    int used[EXPECTED_COLORS] = {0};
    int id, k, slots = 0;
    uint8_t size, colors[CE_DICT_COMBO_MAX];

    TEST_ASSERT_EQUAL_INT(-1, ce_dict_combo(0, &size, colors));
    TEST_ASSERT_EQUAL_INT(-1, ce_dict_combo(-1, &size, colors));
    TEST_ASSERT_EQUAL_INT(-1, ce_dict_combo(EXPECTED_COMBOS + 1, &size, colors));
    TEST_ASSERT_EQUAL_INT(-1, ce_dict_combo(1000000, NULL, NULL));

    for (id = 1; id <= EXPECTED_COMBOS; ++id) {
        memset(colors, 0xAA, sizeof colors);
        size = 0;
        TEST_ASSERT_EQUAL_INT_MESSAGE(0, ce_dict_combo(id, &size, colors), "hueco en los ids");
        TEST_ASSERT_TRUE(size >= 2 && size <= CE_DICT_COMBO_MAX);
        hist[size]++;
        for (k = 0; k < CE_DICT_COMBO_MAX; ++k) {
            if (k < (int)size) {
                TEST_ASSERT_TRUE_MESSAGE(colors[k] < EXPECTED_COLORS, "indice de color fuera de rango");
                if (k > 0) {
                    TEST_ASSERT_TRUE_MESSAGE(colors[k] > colors[k - 1], "indices no ascendentes / repetidos");
                }
                used[colors[k]] = 1;
                ++slots;
            } else {
                TEST_ASSERT_EQUAL_UINT8_MESSAGE(CE_DICT_NO_COLOR, colors[k], "relleno distinto de CE_DICT_NO_COLOR");
            }
        }
        /* NULL en las salidas: solo comprueba existencia. */
        TEST_ASSERT_EQUAL_INT(0, ce_dict_combo(id, NULL, NULL));
    }
    TEST_ASSERT_EQUAL_INT(120, hist[2]);
    TEST_ASSERT_EQUAL_INT(120, hist[3]);
    TEST_ASSERT_EQUAL_INT(108, hist[4]);
    TEST_ASSERT_EQUAL_INT(0, hist[5] + hist[6] + hist[7]);
    TEST_ASSERT_EQUAL_INT(1032, slots);
    for (k = 0; k < EXPECTED_COLORS; ++k) {
        TEST_ASSERT_TRUE_MESSAGE(used[k], "color sin ninguna combinacion");
    }
    printf("combos: %d/%d/%d, %d slots\n", hist[2], hist[3], hist[4], slots);
}

/* 3. Accesores de color: rango, NULL, NaN, y ce_dict_color_lab == ce_srgb8_to_lab bit a bit. */
static void test_color_accessors(void)
{
    uint8_t rgb[3];
    ce_lab lab;
    int i;
    const int bad[] = {-1, EXPECTED_COLORS, EXPECTED_COLORS + 1, 1000000, -1000000};
    for (i = 0; i < (int)(sizeof bad / sizeof bad[0]); ++i) {
        rgb[0] = rgb[1] = rgb[2] = 7;
        TEST_ASSERT_EQUAL_INT(-1, ce_dict_color_rgb(bad[i], rgb));
        TEST_ASSERT_EQUAL_UINT8(7, rgb[0]); /* no escribe nada fuera de rango */
        TEST_ASSERT_NULL(ce_dict_color_name(bad[i]));
        lab = ce_dict_color_lab(bad[i]);
        TEST_ASSERT_TRUE(isnan(lab.L) && isnan(lab.a) && isnan(lab.b));
    }
    TEST_ASSERT_EQUAL_INT(0, ce_dict_color_rgb(0, NULL));
    TEST_ASSERT_EQUAL_INT(0, ce_dict_color_rgb(0, rgb));
    TEST_ASSERT_EQUAL_UINT8(249, rgb[0]);
    TEST_ASSERT_EQUAL_UINT8(193, rgb[1]);
    TEST_ASSERT_EQUAL_UINT8(206, rgb[2]);
    TEST_ASSERT_EQUAL_STRING("Hermosa Pink", ce_dict_color_name(0));
    for (i = 0; i < EXPECTED_COLORS; ++i) {
        ce_lab direct;
        const char *name = ce_dict_color_name(i);
        TEST_ASSERT_NOT_NULL(name);
        TEST_ASSERT_TRUE_MESSAGE(name[0] != '\0', "nombre vacio");
        TEST_ASSERT_EQUAL_INT(0, ce_dict_color_rgb(i, rgb));
        lab = ce_dict_color_lab(i);
        direct = ce_srgb8_to_lab(rgb[0], rgb[1], rgb[2]);
        /* Misma función, mismos bits. */
        TEST_ASSERT_EQUAL_MEMORY(&direct, &lab, sizeof lab);
        TEST_ASSERT_TRUE(lab.L >= 0.0 && lab.L <= 100.0);
    }
}

/* 4. golden_wada_lab.tsv: dict_version de la cabecera == ce_dict_version();
 *    rgb de cada fila == tabla; Lab a 1e-9 del oráculo; 159 filas. */
static void test_golden_wada_lab(void)
{
    FILE *f = open_data("golden_wada_lab.tsv");
    char line[MAX_LINE];
    char version[64] = "";
    int count = 0;
    int bad = 0;
    double max_err = 0.0;
    while (fgets(line, sizeof line, f)) {
        double v[7];
        uint8_t rgb[3];
        ce_lab lab;
        double e;
        int index;
        if (parse_version_header(line, version, sizeof version)) {
            continue;
        }
        if (is_comment_or_blank(line)) {
            continue;
        }
        TEST_ASSERT_EQUAL_INT(7, parse_doubles(line, v, 7));
        index = (int)v[0];
        TEST_ASSERT_EQUAL_INT_MESSAGE(count, index, "filas del golden fuera de orden");
        TEST_ASSERT_EQUAL_INT(0, ce_dict_color_rgb(index, rgb));
        TEST_ASSERT_EQUAL_UINT8((uint8_t)v[1], rgb[0]);
        TEST_ASSERT_EQUAL_UINT8((uint8_t)v[2], rgb[1]);
        TEST_ASSERT_EQUAL_UINT8((uint8_t)v[3], rgb[2]);
        lab = ce_dict_color_lab(index);
        e = fabs(lab.L - v[4]);
        if (fabs(lab.a - v[5]) > e) e = fabs(lab.a - v[5]);
        if (fabs(lab.b - v[6]) > e) e = fabs(lab.b - v[6]);
        if (e > max_err) max_err = e;
        if (e > TOL_GOLDEN) {
            if (bad < 5) {
                printf("golden_wada_lab %d %s: ce=(%.15e,%.15e,%.15e) esperado=(%.15e,%.15e,%.15e)\n",
                       index, ce_dict_color_name(index), lab.L, lab.a, lab.b, v[4], v[5], v[6]);
            }
            ++bad;
        }
        ++count;
    }
    fclose(f);
    printf("golden_wada_lab: %d filas, max error %.3e, dict_version %s\n", count, max_err, version);
    TEST_ASSERT_TRUE_MESSAGE(version[0] != '\0', "golden_wada_lab.tsv sin cabecera '# dict_version:'");
    TEST_ASSERT_EQUAL_STRING_MESSAGE(version, ce_dict_version(),
                                     "dict_version del golden != ce_dict_version(): regenera con make dict && make golden");
    TEST_ASSERT_EQUAL_INT_MESSAGE(EXPECTED_COLORS, count, "golden_wada_lab.tsv debe tener 159 filas");
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, bad, "filas de golden_wada_lab fuera de tolerancia");
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_counts_and_version);
    RUN_TEST(test_combos_invariants);
    RUN_TEST(test_color_accessors);
    RUN_TEST(test_golden_wada_lab);
    return UNITY_END();
}
