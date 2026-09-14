/*
 * test_math.c — tests de la capa 1 (matemática de color) con Unity.
 *
 * Los golden files (engine/tests/data/golden_*.tsv) los genera el oráculo Python
 * (oracle/oracle/gen_golden.py) con colour-science; el fichero de Sharma es
 * el test set oficial de CIEDE2000. La ruta del directorio de datos llega por
 * la macro CE_TEST_DATA_DIR (CMake).
 *
 * El mismo binario se ejecuta en nativo, con ASan/UBSan y en WebAssembly
 * (node + NODERAWFS). Al final imprime hashes FNV-1a de las salidas golden para
 * comparar plataformas (ver README).
 */
#include "ce/ce.h"
#include "unity.h"

#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#pragma STDC FP_CONTRACT OFF

#ifndef CE_TEST_DATA_DIR
#error "CE_TEST_DATA_DIR debe definirse (ruta a engine/tests/data)"
#endif

/* Paso del recorrido exhaustivo sRGB8 -> Lab -> sRGB8. 1 = los 16.777.216
 * colores. En WASM se puede pasar CE_ROUNDTRIP_STEP=16 (muestreo 1/16). */
#ifndef CE_ROUNDTRIP_STEP
#define CE_ROUNDTRIP_STEP 1
#endif

#define MAX_LINE 1024
#define TOL_GOLDEN 1e-9

/* ------------------------------------------------------------------------
 * Hash FNV-1a (64 bits) sobre bytes y sobre texto %.15e
 * ---------------------------------------------------------------------- */

static uint64_t g_hash_bits = 0xcbf29ce484222325ULL;
static uint64_t g_hash_text = 0xcbf29ce484222325ULL;

static uint64_t fnv1a_update(uint64_t h, const void *data, size_t n)
{
    const unsigned char *p = (const unsigned char *)data;
    size_t i;
    for (i = 0; i < n; ++i) {
        h ^= (uint64_t)p[i];
        h *= 0x100000001b3ULL;
    }
    return h;
}

static void hash_double(double v)
{
    char buf[64];
    int n;
    g_hash_bits = fnv1a_update(g_hash_bits, &v, sizeof v);
    n = snprintf(buf, sizeof buf, "%.15e", v);
    if (n > 0) {
        g_hash_text = fnv1a_update(g_hash_text, buf, (size_t)n);
    }
}

/* ------------------------------------------------------------------------
 * Lectura de TSV
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

/* Parsea hasta `max` doubles separados por blancos. Devuelve cuántos leyó. */
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

/* ------------------------------------------------------------------------
 * LCG propio (sin rand()) para pares aleatorios reproducibles
 * ---------------------------------------------------------------------- */

static uint64_t g_lcg = 20260914ULL;

static double lcg_uniform(double lo, double hi)
{
    /* Constantes de Knuth MMIX. Se usan los 53 bits altos. */
    g_lcg = g_lcg * 6364136223846793005ULL + 1442695040888963407ULL;
    return lo + (hi - lo) * ((double)(g_lcg >> 11) * (1.0 / 9007199254740992.0));
}

/* ------------------------------------------------------------------------
 * Tests
 * ---------------------------------------------------------------------- */

void setUp(void) {}
void tearDown(void) {}

static void test_version(void)
{
    TEST_ASSERT_EQUAL_STRING(CE_VERSION_STRING, ce_version());
}

/* 1. Sharma, Wu y Dalal: 34 pares, |ΔE - esperado| <= 1e-4, ambos órdenes. */
static void test_sharma_pairs(void)
{
    FILE *f = open_data("ciede2000testdata.txt");
    char line[MAX_LINE];
    int count = 0;
    while (fgets(line, sizeof line, f)) {
        double v[7];
        ce_lab l1, l2;
        double d12, d21;
        if (is_comment_or_blank(line)) {
            continue;
        }
        TEST_ASSERT_EQUAL_INT_MESSAGE(7, parse_doubles(line, v, 7), "fila de Sharma con columnas inesperadas");
        l1.L = v[0]; l1.a = v[1]; l1.b = v[2];
        l2.L = v[3]; l2.a = v[4]; l2.b = v[5];
        d12 = ce_de2000(l1, l2);
        d21 = ce_de2000(l2, l1);
        if (fabs(d12 - v[6]) > 1e-4 || fabs(d21 - v[6]) > 1e-4) {
            printf("Sharma par %d: esperado %.4f, ce(1,2)=%.6f ce(2,1)=%.6f\n", count + 1, v[6], d12, d21);
        }
        TEST_ASSERT_DOUBLE_WITHIN(1e-4, v[6], d12);
        TEST_ASSERT_DOUBLE_WITHIN(1e-4, v[6], d21);
        ++count;
    }
    fclose(f);
    TEST_ASSERT_EQUAL_INT_MESSAGE(34, count, "esperaba 34 pares de Sharma");
}

/* 2. Blanco y negro. */
static void test_white_black(void)
{
    ce_lab w = ce_srgb8_to_lab(255, 255, 255);
    ce_lab k = ce_srgb8_to_lab(0, 0, 0);
    printf("blanco: L=%.17g a=%.17g b=%.17g\n", w.L, w.a, w.b);
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, 100.0, w.L);
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, 0.0, w.a);
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, 0.0, w.b);
    TEST_ASSERT_DOUBLE_WITHIN(1e-12, 0.0, k.L);
    TEST_ASSERT_DOUBLE_WITHIN(1e-12, 0.0, k.a);
    TEST_ASSERT_DOUBLE_WITHIN(1e-12, 0.0, k.b);
}

/* 3. golden_lab.tsv: |ΔL|,|Δa|,|Δb| <= 1e-9 frente al oráculo estricto. */
static void test_golden_lab(void)
{
    FILE *f = open_data("golden_lab.tsv");
    char line[MAX_LINE];
    int count = 0;
    int bad = 0;
    double max_err = 0.0;
    while (fgets(line, sizeof line, f)) {
        double v[6];
        ce_lab lab;
        double e;
        if (is_comment_or_blank(line)) {
            continue;
        }
        TEST_ASSERT_EQUAL_INT(6, parse_doubles(line, v, 6));
        lab = ce_srgb8_to_lab((uint8_t)v[0], (uint8_t)v[1], (uint8_t)v[2]);
        hash_double(lab.L);
        hash_double(lab.a);
        hash_double(lab.b);
        e = fabs(lab.L - v[3]);
        if (fabs(lab.a - v[4]) > e) e = fabs(lab.a - v[4]);
        if (fabs(lab.b - v[5]) > e) e = fabs(lab.b - v[5]);
        if (e > max_err) max_err = e;
        if (e > TOL_GOLDEN) {
            if (bad < 5) {
                printf("golden_lab fila %d rgb=(%g,%g,%g): ce=(%.15e,%.15e,%.15e) esperado=(%.15e,%.15e,%.15e)\n",
                       count + 1, v[0], v[1], v[2], lab.L, lab.a, lab.b, v[3], v[4], v[5]);
            }
            ++bad;
        }
        ++count;
    }
    fclose(f);
    printf("golden_lab: %d filas, max error %.3e\n", count, max_err);
    TEST_ASSERT_TRUE_MESSAGE(count >= 2000, "golden_lab.tsv con pocas filas");
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, bad, "filas de golden_lab fuera de tolerancia");
}

/* 4. golden_de2000.tsv: |Δ| <= 1e-9. */
static void test_golden_de2000(void)
{
    FILE *f = open_data("golden_de2000.tsv");
    char line[MAX_LINE];
    int count = 0;
    int bad = 0;
    double max_err = 0.0;
    while (fgets(line, sizeof line, f)) {
        double v[7];
        ce_lab l1, l2;
        double d, e;
        if (is_comment_or_blank(line)) {
            continue;
        }
        TEST_ASSERT_EQUAL_INT(7, parse_doubles(line, v, 7));
        l1.L = v[0]; l1.a = v[1]; l1.b = v[2];
        l2.L = v[3]; l2.a = v[4]; l2.b = v[5];
        d = ce_de2000(l1, l2);
        hash_double(d);
        e = fabs(d - v[6]);
        if (e > max_err) max_err = e;
        if (e > TOL_GOLDEN) {
            if (bad < 5) {
                printf("golden_de2000 fila %d: ce=%.15e esperado=%.15e\n", count + 1, d, v[6]);
            }
            ++bad;
        }
        ++count;
    }
    fclose(f);
    printf("golden_de2000: %d filas, max error %.3e\n", count, max_err);
    TEST_ASSERT_TRUE_MESSAGE(count >= 2000, "golden_de2000.tsv con pocas filas");
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, bad, "filas de golden_de2000 fuera de tolerancia");
}

static ce_illuminant illuminant_from_name(const char *name)
{
    if (strcmp(name, "A") == 0) return CE_ILL_A;
    if (strcmp(name, "D50") == 0) return CE_ILL_D50;
    if (strcmp(name, "D65") == 0) return CE_ILL_D65;
    if (strcmp(name, "D75") == 0) return CE_ILL_D75;
    if (strcmp(name, "F2") == 0) return CE_ILL_F2;
    TEST_FAIL_MESSAGE("iluminante desconocido en golden_bradford.tsv");
    return CE_ILL_D65;
}

/* 5. golden_bradford.tsv: |Δ| <= 1e-9, y D65->D50 coincide con el ejemplo de
 * colour a 1e-7. */
static void test_golden_bradford(void)
{
    FILE *f = open_data("golden_bradford.tsv");
    char line[MAX_LINE];
    int count = 0;
    int bad = 0;
    double max_err = 0.0;
    while (fgets(line, sizeof line, f)) {
        char from[16], to[16];
        double v[6];
        double m[9];
        ce_xyz in, out;
        double e;
        int consumed = 0;
        if (is_comment_or_blank(line)) {
            continue;
        }
        TEST_ASSERT_EQUAL_INT(2, sscanf(line, "%15s %15s%n", from, to, &consumed));
        TEST_ASSERT_EQUAL_INT(6, parse_doubles(line + consumed, v, 6));
        ce_bradford_matrix(illuminant_from_name(from), illuminant_from_name(to), m);
        in.X = v[0]; in.Y = v[1]; in.Z = v[2];
        out = ce_xyz_adapt(in, m);
        hash_double(out.X);
        hash_double(out.Y);
        hash_double(out.Z);
        e = fabs(out.X - v[3]);
        if (fabs(out.Y - v[4]) > e) e = fabs(out.Y - v[4]);
        if (fabs(out.Z - v[5]) > e) e = fabs(out.Z - v[5]);
        if (e > max_err) max_err = e;
        if (e > TOL_GOLDEN) {
            if (bad < 5) {
                printf("golden_bradford fila %d %s->%s: ce=(%.15e,%.15e,%.15e) esperado=(%.15e,%.15e,%.15e)\n",
                       count + 1, from, to, out.X, out.Y, out.Z, v[3], v[4], v[5]);
            }
            ++bad;
        }
        ++count;
    }
    fclose(f);
    printf("golden_bradford: %d filas, max error %.3e\n", count, max_err);
    TEST_ASSERT_TRUE_MESSAGE(count >= 80, "golden_bradford.tsv con pocas filas");
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, bad, "filas de golden_bradford fuera de tolerancia");
}

static void test_bradford_d65_to_d50_example(void)
{
    /* Ejemplo documentado de colour.adaptation.matrix_chromatic_adaptation_VonKries
     * (transform='Bradford', D65 -> D50, xy de CIE 015:2004). Nota: el
     * elemento [2][2] es 0.7518742 con estos blancos; 0.7521316 corresponde a
     * los blancos de Lindbloom (0.95047/1.08883, 0.96422/0.82521). */
    static const double expected[9] = {
        1.0479297, 0.0229468, -0.0501922,
        0.0296278, 0.9904344, -0.0170738,
        -0.0092430, 0.0150551, 0.7518742
    };
    double m[9];
    int i;
    ce_bradford_matrix(CE_ILL_D65, CE_ILL_D50, m);
    for (i = 0; i < 9; ++i) {
        TEST_ASSERT_DOUBLE_WITHIN(1e-7, expected[i], m[i]);
    }
    /* Identidad cuando origen y destino coinciden. */
    ce_bradford_matrix(CE_ILL_D65, CE_ILL_D65, m);
    for (i = 0; i < 9; ++i) {
        TEST_ASSERT_DOUBLE_WITHIN(1e-14, (i % 4 == 0) ? 1.0 : 0.0, m[i]);
    }
}

/* 6. Round-trip exhaustivo sRGB8 -> Lab -> sRGB8. */
static void test_roundtrip_exhaustive(void)
{
    clock_t t0 = clock();
    uint32_t idx;
    uint64_t checked = 0;
    uint64_t bad = 0;
    int first_bad_reported = 0;
    for (idx = 0; idx < 16777216u; idx += CE_ROUNDTRIP_STEP) {
        const uint8_t r = (uint8_t)(idx >> 16);
        const uint8_t g = (uint8_t)(idx >> 8);
        const uint8_t b = (uint8_t)idx;
        uint8_t r2, g2, b2;
        ce_lab lab = ce_srgb8_to_lab(r, g, b);
        ce_lab_to_srgb8(lab, &r2, &g2, &b2);
        ++checked;
        if (r != r2 || g != g2 || b != b2) {
            if (!first_bad_reported) {
                printf("round-trip falla: (%u,%u,%u) -> Lab(%.15e,%.15e,%.15e) -> (%u,%u,%u)\n",
                       r, g, b, lab.L, lab.a, lab.b, r2, g2, b2);
                first_bad_reported = 1;
            }
            ++bad;
        }
    }
    {
        double secs = (double)(clock() - t0) / (double)CLOCKS_PER_SEC;
        printf("round-trip: %" PRIu64 " colores (paso %d) en %.3f s, %" PRIu64 " fallos\n",
               checked, (int)CE_ROUNDTRIP_STEP, secs, bad);
    }
    TEST_ASSERT_EQUAL_UINT64(0, bad);
}

/* 7. Propiedades: ΔE(x,x) = 0, ΔE >= 0, simetría en 1000 pares (LCG propio). */
static void test_de2000_properties(void)
{
    int i;
    for (i = 0; i < 1000; ++i) {
        ce_lab x, y;
        double dxy, dyx;
        x.L = lcg_uniform(0.0, 100.0);
        x.a = lcg_uniform(-128.0, 128.0);
        x.b = lcg_uniform(-128.0, 128.0);
        y.L = lcg_uniform(0.0, 100.0);
        y.a = lcg_uniform(-128.0, 128.0);
        y.b = lcg_uniform(-128.0, 128.0);
        TEST_ASSERT_EQUAL_DOUBLE(0.0, ce_de2000(x, x));
        TEST_ASSERT_EQUAL_DOUBLE(0.0, ce_de2000(y, y));
        dxy = ce_de2000(x, y);
        dyx = ce_de2000(y, x);
        TEST_ASSERT_TRUE(dxy >= 0.0);
        TEST_ASSERT_TRUE(dyx >= 0.0);
        /* La fórmula es simétrica; las operaciones se ejecutan en el mismo
         * orden salvo la suma h1'+h2' (conmutativa en IEEE), así que se exige
         * igualdad exacta. */
        TEST_ASSERT_EQUAL_DOUBLE(dxy, dyx);
        TEST_ASSERT_TRUE(ce_de76(x, y) >= 0.0);
        TEST_ASSERT_EQUAL_DOUBLE(ce_de76(x, y), ce_de76(y, x));
    }
    /* kL = kC = kH = 1 coincide con ce_de2000. */
    {
        ce_lab x = {50.0, 2.6772, -79.7751};
        ce_lab y = {50.0, 0.0, -82.7485};
        TEST_ASSERT_EQUAL_DOUBLE(ce_de2000(x, y), ce_de2000_k(x, y, 1.0, 1.0, 1.0));
        TEST_ASSERT_TRUE(ce_de2000_k(x, y, 2.0, 1.0, 1.0) <= ce_de2000(x, y));
    }

    /* Factores paramétricos no positivos o NaN se tratan como 1.0: nunca inf/NaN. */
    {
        const ce_lab p = {50.0, 10.0, -20.0}, q = {55.0, -5.0, 12.0};
        const double ref = ce_de2000(p, q);
        TEST_ASSERT_DOUBLE_WITHIN(1e-12, ref, ce_de2000_k(p, q, 0.0, 0.0, 0.0));
        TEST_ASSERT_DOUBLE_WITHIN(1e-12, ref, ce_de2000_k(p, q, -1.0, 1.0, 1.0));
        TEST_ASSERT_DOUBLE_WITHIN(1e-12, 0.0, ce_de2000_k(p, p, 0.0, 0.0, 0.0));
        TEST_ASSERT_DOUBLE_WITHIN(1e-12, ref, ce_de2000_k(p, q, 0.0 / 0.0, 1.0, 1.0));
    }
}

/* Inversas: Lab -> XYZ -> Lab y XYZ -> sRGB -> XYZ. */
static void test_inverse_consistency(void)
{
    int i;
    for (i = 0; i < 200; ++i) {
        ce_lab lab, back;
        ce_xyz xyz, xyz2;
        double r, g, b;
        lab.L = lcg_uniform(0.0, 100.0);
        lab.a = lcg_uniform(-100.0, 100.0);
        lab.b = lcg_uniform(-100.0, 100.0);
        xyz = ce_lab_to_xyz(lab);
        back = ce_xyz_to_lab(xyz);
        TEST_ASSERT_DOUBLE_WITHIN(1e-10, lab.L, back.L);
        TEST_ASSERT_DOUBLE_WITHIN(1e-10, lab.a, back.a);
        TEST_ASSERT_DOUBLE_WITHIN(1e-10, lab.b, back.b);
        r = lcg_uniform(0.0, 1.0);
        g = lcg_uniform(0.0, 1.0);
        b = lcg_uniform(0.0, 1.0);
        xyz = ce_srgb_to_xyz(r, g, b);
        {
            double r2, g2, b2;
            ce_xyz_to_srgb(xyz, &r2, &g2, &b2);
            TEST_ASSERT_DOUBLE_WITHIN(1e-12, r, r2);
            TEST_ASSERT_DOUBLE_WITHIN(1e-12, g, g2);
            TEST_ASSERT_DOUBLE_WITHIN(1e-12, b, b2);
            xyz2 = ce_srgb_to_xyz(r2, g2, b2);
            TEST_ASSERT_DOUBLE_WITHIN(1e-12, xyz.X, xyz2.X);
            TEST_ASSERT_DOUBLE_WITHIN(1e-12, xyz.Y, xyz2.Y);
            TEST_ASSERT_DOUBLE_WITHIN(1e-12, xyz.Z, xyz2.Z);
        }
    }
    /* El blanco Lab es el blanco D65 con Y = 1 y la matriz lo reproduce. */
    {
        ce_xyz w = ce_lab_white();
        ce_xyz w2 = ce_srgb_to_xyz(1.0, 1.0, 1.0);
        TEST_ASSERT_DOUBLE_WITHIN(1e-15, 0.9504559270516716, w.X);
        TEST_ASSERT_DOUBLE_WITHIN(0.0, 1.0, w.Y);
        TEST_ASSERT_DOUBLE_WITHIN(1e-15, 1.0890577507598784, w.Z);
        TEST_ASSERT_DOUBLE_WITHIN(1e-15, w.X, w2.X);
        TEST_ASSERT_DOUBLE_WITHIN(1e-15, w.Y, w2.Y);
        TEST_ASSERT_DOUBLE_WITHIN(1e-15, w.Z, w2.Z);
    }
}

/* 8. Hash de determinismo cruzado (se imprime para comparar nativo vs wasm). */
static void test_print_hashes(void)
{
    printf("HASH_GOLDEN_BITS=%016" PRIx64 "\n", g_hash_bits);
    printf("HASH_GOLDEN_TEXT=%016" PRIx64 "\n", g_hash_text);
    TEST_ASSERT_NOT_EQUAL_UINT64(0xcbf29ce484222325ULL, g_hash_bits);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_version);
    RUN_TEST(test_sharma_pairs);
    RUN_TEST(test_white_black);
    RUN_TEST(test_golden_lab);
    RUN_TEST(test_golden_de2000);
    RUN_TEST(test_golden_bradford);
    RUN_TEST(test_bradford_d65_to_d50_example);
    RUN_TEST(test_inverse_consistency);
    RUN_TEST(test_de2000_properties);
    RUN_TEST(test_roundtrip_exhaustive);
    RUN_TEST(test_print_hashes);
    return UNITY_END();
}
