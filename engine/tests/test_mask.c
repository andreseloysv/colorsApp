/*
 * test_mask.c — máscaras de ropa y piel (ce_mask.c) con Unity.
 *
 *  (1) Pose sintética de frente en 200x400 con máscara de persona llena:
 *      nada por encima de la línea de hombros, nada en discos de radio
 *      0,15·sw alrededor de las muñecas (include_forearms = 0), sí el centro
 *      del torso y los puntos medios de los muslos; recuento igual al de un
 *      rasterizador de referencia INDEPENDIENTE escrito aquí (distancias con
 *      sqrt y proyección sobre el vector unitario, envolvente convexa por
 *      cadena monótona de Andrew, lado por normal orientada) y a la constante
 *      dorada que dio en la primera ejecución. También con antebrazos, sin
 *      piernas y con opciones no por defecto.
 *  (2) Invariancias exactas (coordenadas múltiplos de 1/4): espejo horizontal
 *      con L/R intercambiados y máscara espejada; traslación de 7 px; escala
 *      x2 de pose y dimensiones -> recuento x4 ±3 %.
 *  (3) CE_ERR_POSE sin caderas (máscara intacta, memcmp); estimación por
 *      simetría de una cadera (con la raíz) y de un hombro (con el cuello):
 *      mismo resultado exacto que con el punto real; sin el punto de simetría
 *      o bajo min_confidence -> CE_ERR_POSE; pose degenerada; CE_ERR_ARG.
 *  (4) ce_mask_cut_head: bbox y franja, redondeo, máscara vacía -> 0, errores.
 *  (5) Piel: cara + brazos desnudos (claro, medio, oscuro; ruido ±4) y torso
 *      rojo / azul marino / beige a ΔE00 ~6 de la piel clara. >= 95 % de los
 *      brazos fuera, < 5 % de rojo y azul; beige documentado (se imprime);
 *      prenda del color de la piel -> CE_SKIN_GUARD con la máscara intacta;
 *      < 50 muestras -> CE_ERR_SKIN_SAMPLES; modelos degenerados.
 *  (6) Determinismo: dos ejecuciones memcmp idénticas y hash FNV-1a de todas
 *      las máscaras y modelos igual a una constante (nativo, ASan y WASM).
 *  (7) Tiempos (solo se imprimen, sin cota): regiones en 1024x2048 y piel en
 *      1024x1024 con la máscara llena (MASK_REGIONS_MS, MASK_SKIN_MS).
 * Escribe además fixtures para los tests del CLI (regions, skin, batch con
 * máscaras por línea) en CE_TEST_OUT_DIR.
 */
/* clock_gettime/CLOCK_MONOTONIC son POSIX: con -std=c11 estricto hay que pedirlos. */
#define _POSIX_C_SOURCE 200809L

#include "ce/ce.h"
/* Solo para comprobar la tabla interna de Lab contra ce_srgb8_to_lab. */
#include "../Sources/CColorEngine/ce_internal.h"
#include "unity.h"

#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#pragma STDC FP_CONTRACT OFF

#ifndef CE_TEST_OUT_DIR
#error "CE_TEST_OUT_DIR debe definirse (directorio de salida de fixtures)"
#endif

void setUp(void) {}
void tearDown(void) {}

#define PW 200
#define PH 400

static uint64_t g_hash = 0xcbf29ce484222325ULL;

static uint64_t fnv_bytes(uint64_t h, const void *data, size_t n)
{
    const unsigned char *p = (const unsigned char *)data;
    size_t i;
    for (i = 0; i < n; ++i) {
        h ^= p[i];
        h *= 0x100000001b3ULL;
    }
    return h;
}

static void hash_mask(const uint8_t *m, size_t n, int count)
{
    const int64_t c = count;
    g_hash = fnv_bytes(g_hash, m, n);
    g_hash = fnv_bytes(g_hash, &c, sizeof c);
}

static int count_nonzero(const uint8_t *m, size_t n)
{
    size_t i;
    int c = 0;
    for (i = 0; i < n; ++i) c += (m[i] != 0);
    return c;
}

/* ------------------------------------------------------------------------
 * Pose de frente (L = izquierda de la persona = derecha de la imagen)
 * ---------------------------------------------------------------------- */

static void kp(ce_pose *p, int j, double x, double y, double c)
{
    p->k[j].x = x;
    p->k[j].y = y;
    p->k[j].confidence = c;
}

/* Persona de frente en 200x400 escalada por `s` y desplazada (ox, oy).
 * Coordenadas múltiplos de 1/4: todas las operaciones del motor son exactas. */
static void pose_front(ce_pose *p, double s, double ox, double oy)
{
    kp(p, CE_JOINT_NOSE, ox + s * 100.0, oy + s * 50.0, 0.9);
    kp(p, CE_JOINT_NECK, ox + s * 100.0, oy + s * 90.0, 0.9);
    kp(p, CE_JOINT_LSHOULDER, ox + s * 140.0, oy + s * 90.0, 0.9);
    kp(p, CE_JOINT_RSHOULDER, ox + s * 60.0, oy + s * 90.0, 0.9);
    kp(p, CE_JOINT_LELBOW, ox + s * 152.25, oy + s * 150.5, 0.8);
    kp(p, CE_JOINT_RELBOW, ox + s * 47.75, oy + s * 150.5, 0.8);
    kp(p, CE_JOINT_LWRIST, ox + s * 158.5, oy + s * 205.25, 0.7);
    kp(p, CE_JOINT_RWRIST, ox + s * 41.5, oy + s * 205.25, 0.7);
    kp(p, CE_JOINT_LHIP, ox + s * 124.0, oy + s * 210.0, 0.9);
    kp(p, CE_JOINT_RHIP, ox + s * 76.0, oy + s * 210.0, 0.9);
    kp(p, CE_JOINT_LKNEE, ox + s * 126.25, oy + s * 290.75, 0.8);
    kp(p, CE_JOINT_RKNEE, ox + s * 73.75, oy + s * 290.75, 0.8);
    kp(p, CE_JOINT_LANKLE, ox + s * 128.5, oy + s * 370.5, 0.8);
    kp(p, CE_JOINT_RANKLE, ox + s * 71.5, oy + s * 370.5, 0.8);
    kp(p, CE_JOINT_ROOT, ox + s * 100.0, oy + s * 210.0, 0.9);
}

/* ------------------------------------------------------------------------
 * Rasterizador de referencia independiente (solo para el test)
 * ---------------------------------------------------------------------- */

typedef struct { double x, y; } rp;

static rp jp(const ce_pose *p, int j)
{
    rp r;
    r.x = p->k[j].x;
    r.y = p->k[j].y;
    return r;
}

static int jok(const ce_pose *p, int j, double minc)
{
    return p->k[j].confidence > 0.0 && p->k[j].confidence >= minc;
}

/* Distancia euclídea punto-segmento por proyección sobre el vector unitario. */
static double ref_seg_dist(rp p, rp a, rp b)
{
    const double vx = b.x - a.x, vy = b.y - a.y;
    const double len = sqrt(vx * vx + vy * vy);
    double ux, uy, along;
    if (len == 0.0) {
        return sqrt((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y));
    }
    ux = vx / len;
    uy = vy / len;
    along = (p.x - a.x) * ux + (p.y - a.y) * uy;
    if (along <= 0.0) return sqrt((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y));
    if (along >= len) return sqrt((p.x - b.x) * (p.x - b.x) + (p.y - b.y) * (p.y - b.y));
    return fabs(ux * (p.y - a.y) - uy * (p.x - a.x));
}

static double ref_turn(rp o, rp a, rp b)
{
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}

/* Envolvente convexa (cadena monótona de Andrew) de 4 puntos, CCW. */
static int ref_hull(rp pts[4], rp hull[8])
{
    rp s[4];
    int i, j, k = 0, t;
    memcpy(s, pts, sizeof s);
    for (i = 1; i < 4; ++i) {
        rp v = s[i];
        for (j = i - 1; j >= 0 && (s[j].x > v.x || (s[j].x == v.x && s[j].y > v.y)); --j) s[j + 1] = s[j];
        s[j + 1] = v;
    }
    for (i = 0; i < 4; ++i) {
        while (k >= 2 && ref_turn(hull[k - 2], hull[k - 1], s[i]) <= 0.0) --k;
        hull[k++] = s[i];
    }
    for (i = 2, t = k + 1; i >= 0; --i) {
        while (k >= t && ref_turn(hull[k - 2], hull[k - 1], s[i]) <= 0.0) --k;
        hull[k++] = s[i];
    }
    return k - 1;
}

/* Recuento de referencia sobre una máscara llena de w x h. Implementa la
 * semántica documentada en ce.h con otras fórmulas. Supone hombros y caderas
 * presentes. `out` recibe la máscara (255/0). */
static int ref_region_count(const ce_pose *p, const ce_region_opts *o, int w, int h, uint8_t *out)
{
    const double minc = o->min_confidence;
    rp ls = jp(p, CE_JOINT_LSHOULDER), rs = jp(p, CE_JOINT_RSHOULDER);
    rp lh = jp(p, CE_JOINT_LHIP), rh = jp(p, CE_JOINT_RHIP);
    rp quad[4], hull[8];
    const double sw = sqrt((ls.x - rs.x) * (ls.x - rs.x) + (ls.y - rs.y) * (ls.y - rs.y));
    const double margin = o->torso_margin * sw, limb_r = o->limb_width * sw / 2.0;
    double nx = -(rs.y - ls.y), ny = rs.x - ls.x;
    const double mhx = (lh.x + rh.x) / 2.0, mhy = (lh.y + rh.y) / 2.0;
    int nh, x, y, i, count = 0;
    rp seg_a[8], seg_b[8], hand_a[2], hand_b[2];
    double hand_r[2];
    int nseg = 0, nhand = 0;
    static const int limbs[8][3] = {
        {CE_JOINT_LSHOULDER, CE_JOINT_LELBOW, 0}, {CE_JOINT_RSHOULDER, CE_JOINT_RELBOW, 0},
        {CE_JOINT_LELBOW, CE_JOINT_LWRIST, 1}, {CE_JOINT_RELBOW, CE_JOINT_RWRIST, 1},
        {CE_JOINT_LHIP, CE_JOINT_LKNEE, 2}, {CE_JOINT_RHIP, CE_JOINT_RKNEE, 2},
        {CE_JOINT_LKNEE, CE_JOINT_LANKLE, 3}, {CE_JOINT_RKNEE, CE_JOINT_RANKLE, 3}};
    const int enabled[4] = {o->include_upper_arms, o->include_forearms, o->include_legs, o->include_lower_legs};

    if (nx * (mhx - ls.x) + ny * (mhy - ls.y) < 0.0) {
        nx = -nx;
        ny = -ny;
    }
    quad[0] = ls; quad[1] = rs; quad[2] = rh; quad[3] = lh;
    nh = ref_hull(quad, hull);
    for (i = 0; i < 8; ++i) {
        if (enabled[limbs[i][2]] && jok(p, limbs[i][0], minc) && jok(p, limbs[i][1], minc)) {
            seg_a[nseg] = jp(p, limbs[i][0]);
            seg_b[nseg] = jp(p, limbs[i][1]);
            ++nseg;
        }
    }
    for (i = 0; i < 2; ++i) {
        const int jw = i == 0 ? CE_JOINT_LWRIST : CE_JOINT_RWRIST;
        const int je = i == 0 ? CE_JOINT_LELBOW : CE_JOINT_RELBOW;
        if (!jok(p, jw, minc)) continue;
        hand_a[nhand] = jp(p, jw);
        if (jok(p, je, minc)) {
            const rp e = jp(p, je);
            const double len = sqrt((hand_a[nhand].x - e.x) * (hand_a[nhand].x - e.x) + (hand_a[nhand].y - e.y) * (hand_a[nhand].y - e.y));
            hand_b[nhand].x = hand_a[nhand].x + (hand_a[nhand].x - e.x) / len * 0.45 * sw;
            hand_b[nhand].y = hand_a[nhand].y + (hand_a[nhand].y - e.y) / len * 0.45 * sw;
            hand_r[nhand] = 0.2 * sw;
        } else {
            hand_b[nhand] = hand_a[nhand];
            hand_r[nhand] = 0.45 * sw;
        }
        ++nhand;
    }
    for (y = 0; y < h; ++y) {
        for (x = 0; x < w; ++x) {
            rp q;
            int in = 0, inside = 1;
            q.x = x + 0.5;
            q.y = y + 0.5;
            if (nx * (q.x - ls.x) + ny * (q.y - ls.y) < 0.0) {
                out[(size_t)y * (size_t)w + (size_t)x] = 0;
                continue;
            }
            for (i = 0; i < nhand && !in; ++i) {
                in = ref_seg_dist(q, hand_a[i], hand_b[i]) <= hand_r[i];
            }
            if (in) {
                out[(size_t)y * (size_t)w + (size_t)x] = 0;
                continue;
            }
            for (i = 0; i < nh; ++i) {
                if (ref_turn(hull[i], hull[i + 1], q) < 0.0) inside = 0;
            }
            in = inside;
            for (i = 0; i < nh && !in; ++i) {
                in = ref_seg_dist(q, hull[i], hull[i + 1]) <= margin;
            }
            for (i = 0; i < nseg && !in; ++i) {
                in = ref_seg_dist(q, seg_a[i], seg_b[i]) <= limb_r;
            }
            out[(size_t)y * (size_t)w + (size_t)x] = in ? 255 : 0;
            count += in;
        }
    }
    return count;
}

/* ------------------------------------------------------------------------
 * (1) Regiones: pose de frente
 * ---------------------------------------------------------------------- */

/* Recuentos dorados (primera ejecución, iguales al rasterizador de referencia). */
#define GOLDEN_DEFAULT 26012
#define GOLDEN_FOREARMS 28090
#define GOLDEN_TORSO_ONLY 7680 /* = área exacta del trapecio (80 + 48) / 2 · 120 */

static void run_front(const ce_region_opts *o, int golden, const char *label)
{
    static uint8_t m[PW * PH], ref[PW * PH];
    ce_pose pose;
    int n, nref, x, y;
    const double sw = 80.0;
    pose_front(&pose, 1.0, 0.0, 0.0);
    memset(m, 255, sizeof m);
    n = ce_mask_clothing_regions(&pose, o, m, PW, PH);
    nref = ref_region_count(&pose, o, PW, PH, ref);
    printf("regiones %s: %d pixeles (referencia %d)\n", label, n, nref);
    TEST_ASSERT_EQUAL_INT(nref, n);
    TEST_ASSERT_EQUAL_MEMORY(ref, m, sizeof m);
    TEST_ASSERT_EQUAL_INT(count_nonzero(m, sizeof m), n);
    if (golden > 0) {
        TEST_ASSERT_EQUAL_INT(golden, n);
    }
    for (y = 0; y < PH; ++y) {
        for (x = 0; x < PW; ++x) {
            const double cx = x + 0.5, cy = y + 0.5;
            const uint8_t v = m[(size_t)y * PW + (size_t)x];
            if (cy < 90.0) {
                TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, v, "pixel por encima de la linea de hombros");
            }
            if (!o->include_forearms) {
                const double dl = sqrt((cx - 158.5) * (cx - 158.5) + (cy - 205.25) * (cy - 205.25));
                const double dr = sqrt((cx - 41.5) * (cx - 41.5) + (cy - 205.25) * (cy - 205.25));
                if (dl <= 0.15 * sw || dr <= 0.15 * sw) {
                    TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, v, "pixel en el disco de la mano");
                }
            }
        }
    }
    TEST_ASSERT_EQUAL_UINT8(255, m[150 * PW + 100]); /* centro del torso */
    if (o->include_legs) {
        TEST_ASSERT_EQUAL_UINT8(255, m[250 * PW + 125]); /* muslo izquierdo */
        TEST_ASSERT_EQUAL_UINT8(255, m[250 * PW + 75]);  /* muslo derecho */
    }
    hash_mask(m, sizeof m, n);
}

static void test_regions_front_pose(void)
{
    ce_region_opts o;
    ce_region_opts_default(&o);
    TEST_ASSERT_EQUAL_DOUBLE(0.3, o.min_confidence);
    TEST_ASSERT_EQUAL_DOUBLE(0.12, o.torso_margin);
    TEST_ASSERT_EQUAL_DOUBLE(0.45, o.limb_width);
    TEST_ASSERT_EQUAL_INT(1, o.include_upper_arms);
    TEST_ASSERT_EQUAL_INT(0, o.include_forearms);
    TEST_ASSERT_EQUAL_INT(1, o.include_legs);
    TEST_ASSERT_EQUAL_INT(1, o.include_lower_legs);
    run_front(&o, GOLDEN_DEFAULT, "por defecto");
    o.include_forearms = 1;
    run_front(&o, GOLDEN_FOREARMS, "con antebrazos");
    o.include_forearms = 0;
    o.include_upper_arms = 0;
    o.include_legs = 0;
    o.include_lower_legs = 0;
    o.torso_margin = 0.0;
    run_front(&o, GOLDEN_TORSO_ONLY, "solo torso sin margen");
    /* Máscara de persona parcial: min(máscara, región) conserva los valores. */
    {
        static uint8_t m[PW * PH];
        ce_pose pose;
        int i, n;
        ce_region_opts_default(&o);
        pose_front(&pose, 1.0, 0.0, 0.0);
        for (i = 0; i < PW * PH; ++i) m[i] = (uint8_t)(i % 3 == 0 ? 0 : 1 + (i % 250));
        n = ce_mask_clothing_regions(&pose, &o, m, PW, PH);
        TEST_ASSERT_EQUAL_INT(count_nonzero(m, sizeof m), n);
        TEST_ASSERT_EQUAL_UINT8(0, m[150 * PW + 99]);          /* 30099 % 3 == 0 */
        TEST_ASSERT_EQUAL_UINT8(1 + (30100 % 250), m[150 * PW + 100]);
        hash_mask(m, sizeof m, n);
    }
}

/* ------------------------------------------------------------------------
 * (2) Invariancias
 * ---------------------------------------------------------------------- */

static void mirror_pose(const ce_pose *in, ce_pose *out, int width)
{
    static const int swap[CE_JOINT_COUNT] = {
        CE_JOINT_NOSE, CE_JOINT_NECK, CE_JOINT_RSHOULDER, CE_JOINT_LSHOULDER, CE_JOINT_RELBOW, CE_JOINT_LELBOW,
        CE_JOINT_RWRIST, CE_JOINT_LWRIST, CE_JOINT_RHIP, CE_JOINT_LHIP, CE_JOINT_RKNEE, CE_JOINT_LKNEE,
        CE_JOINT_RANKLE, CE_JOINT_LANKLE, CE_JOINT_ROOT};
    int j;
    for (j = 0; j < CE_JOINT_COUNT; ++j) {
        out->k[swap[j]].x = (double)width - in->k[j].x;
        out->k[swap[j]].y = in->k[j].y;
        out->k[swap[j]].confidence = in->k[j].confidence;
    }
}

static void person_mask(uint8_t *m, int w, int h)
{
    int x, y;
    for (y = 0; y < h; ++y) {
        for (x = 0; x < w; ++x) {
            /* Asimétrica: valores y huecos dependen de x e y. */
            m[(size_t)y * (size_t)w + (size_t)x] = (uint8_t)(((x * 7 + y * 13) % 17 == 0) ? 0 : 1 + (x * 3 + y) % 255);
        }
    }
}

static void test_regions_invariance(void)
{
    static uint8_t a[PW * PH], b[PW * PH], t[(PW + 7) * (PH + 7)], big[2 * PW * 2 * PH];
    ce_region_opts o;
    ce_pose pose, mp, tp, bp;
    int na, nb, nt, nbig, x, y, j;
    double ratio;

    ce_region_opts_default(&o);
    o.include_forearms = 1; /* todas las cápsulas */
    pose_front(&pose, 1.0, 0.0, 0.0);
    /* Pose ligeramente girada para que el espejo no sea trivial. */
    pose.k[CE_JOINT_LSHOULDER].y = 86.25;
    pose.k[CE_JOINT_LHIP].y = 212.5;
    pose.k[CE_JOINT_NECK].y = 88.125;
    pose.k[CE_JOINT_ROOT].y = 211.25;

    person_mask(a, PW, PH);
    na = ce_mask_clothing_regions(&pose, &o, a, PW, PH);
    TEST_ASSERT_TRUE(na > 1000);

    /* Espejo. */
    mirror_pose(&pose, &mp, PW);
    for (y = 0; y < PH; ++y) {
        for (x = 0; x < PW; ++x) {
            b[(size_t)y * PW + (size_t)(PW - 1 - x)] = (uint8_t)(((x * 7 + y * 13) % 17 == 0) ? 0 : 1 + (x * 3 + y) % 255);
        }
    }
    nb = ce_mask_clothing_regions(&mp, &o, b, PW, PH);
    TEST_ASSERT_EQUAL_INT(na, nb);
    for (y = 0; y < PH; ++y) {
        for (x = 0; x < PW; ++x) {
            if (a[(size_t)y * PW + (size_t)x] != b[(size_t)y * PW + (size_t)(PW - 1 - x)]) {
                char msg[80];
                snprintf(msg, sizeof msg, "espejo distinto en (%d,%d)", x, y);
                TEST_FAIL_MESSAGE(msg);
            }
        }
    }

    /* Traslación de 7 px (imagen 207x407). */
    tp = pose;
    for (j = 0; j < CE_JOINT_COUNT; ++j) {
        tp.k[j].x += 7.0;
        tp.k[j].y += 7.0;
    }
    memset(t, 0, sizeof t);
    for (y = 0; y < PH; ++y) {
        for (x = 0; x < PW; ++x) {
            t[(size_t)(y + 7) * (PW + 7) + (size_t)(x + 7)] = (uint8_t)(((x * 7 + y * 13) % 17 == 0) ? 0 : 1 + (x * 3 + y) % 255);
        }
    }
    nt = ce_mask_clothing_regions(&tp, &o, t, PW + 7, PH + 7);
    TEST_ASSERT_EQUAL_INT(na, nt);
    for (y = 0; y < PH + 7; ++y) {
        for (x = 0; x < PW + 7; ++x) {
            const uint8_t want = (x >= 7 && y >= 7) ? a[(size_t)(y - 7) * PW + (size_t)(x - 7)] : 0;
            TEST_ASSERT_EQUAL_UINT8(want, t[(size_t)y * (PW + 7) + (size_t)x]);
        }
    }

    /* Escala x2: recuento ~x4 (±3 %) con máscara llena. */
    pose_front(&bp, 2.0, 0.0, 0.0);
    memset(big, 255, sizeof big);
    nbig = ce_mask_clothing_regions(&bp, &o, big, 2 * PW, 2 * PH);
    memset(a, 255, sizeof a);
    pose_front(&pose, 1.0, 0.0, 0.0);
    na = ce_mask_clothing_regions(&pose, &o, a, PW, PH);
    ratio = (double)nbig / (double)na;
    printf("escala x2: %d / %d = %.4f\n", nbig, na, ratio);
    TEST_ASSERT_TRUE(ratio >= 4.0 * 0.97 && ratio <= 4.0 * 1.03);
    hash_mask(big, sizeof big, nbig);
    hash_mask(b, sizeof b, nb);
    hash_mask(t, sizeof t, nt);
}

/* ------------------------------------------------------------------------
 * (3) Errores y estimación por simetría
 * ---------------------------------------------------------------------- */

static void test_regions_errors_and_symmetry(void)
{
    static uint8_t full[PW * PH], m[PW * PH], before[PW * PH];
    ce_region_opts o, bad;
    ce_pose pose, p2;
    int n_full, n;

    ce_region_opts_default(&o);
    pose_front(&pose, 1.0, 0.0, 0.0);
    person_mask(full, PW, PH);
    memcpy(before, full, sizeof full);
    n_full = ce_mask_clothing_regions(&pose, &o, full, PW, PH);
    TEST_ASSERT_TRUE(n_full > 0);

    /* Sin caderas ni raíz: CE_ERR_POSE y máscara intacta. */
    p2 = pose;
    p2.k[CE_JOINT_LHIP].confidence = 0.0;
    p2.k[CE_JOINT_RHIP].confidence = 0.0;
    memcpy(m, before, sizeof m);
    TEST_ASSERT_EQUAL_INT(CE_ERR_POSE, ce_mask_clothing_regions(&p2, &o, m, PW, PH));
    TEST_ASSERT_EQUAL_MEMORY(before, m, sizeof m);
    /* Sin caderas pero con raíz: sigue sin poder estimarse (necesita una). */
    TEST_ASSERT_TRUE(p2.k[CE_JOINT_ROOT].confidence > 0.0);

    /* Una cadera ausente + raíz: RHIP = 2·ROOT − LHIP = (76, 210): idéntico. */
    p2 = pose;
    p2.k[CE_JOINT_RHIP].confidence = 0.0;
    p2.k[CE_JOINT_RHIP].x = 1e9; /* ignorado */
    memcpy(m, before, sizeof m);
    n = ce_mask_clothing_regions(&p2, &o, m, PW, PH);
    TEST_ASSERT_EQUAL_INT(n_full, n);
    TEST_ASSERT_EQUAL_MEMORY(full, m, sizeof m);
    /* Bajo min_confidence cuenta como ausente (0,2 < 0,3): igual. */
    p2.k[CE_JOINT_RHIP].confidence = 0.2;
    memcpy(m, before, sizeof m);
    TEST_ASSERT_EQUAL_INT(n_full, ce_mask_clothing_regions(&p2, &o, m, PW, PH));
    TEST_ASSERT_EQUAL_MEMORY(full, m, sizeof m);
    /* Sin la raíz ya no se puede estimar. */
    p2.k[CE_JOINT_ROOT].confidence = 0.0;
    memcpy(m, before, sizeof m);
    TEST_ASSERT_EQUAL_INT(CE_ERR_POSE, ce_mask_clothing_regions(&p2, &o, m, PW, PH));
    TEST_ASSERT_EQUAL_MEMORY(before, m, sizeof m);

    /* Un hombro ausente + cuello: LSHOULDER = 2·NECK − RSHOULDER = (140, 90). */
    p2 = pose;
    p2.k[CE_JOINT_LSHOULDER].confidence = -1.0;
    memcpy(m, before, sizeof m);
    TEST_ASSERT_EQUAL_INT(n_full, ce_mask_clothing_regions(&p2, &o, m, PW, PH));
    TEST_ASSERT_EQUAL_MEMORY(full, m, sizeof m);
    p2.k[CE_JOINT_NECK].confidence = NAN;
    memcpy(m, before, sizeof m);
    TEST_ASSERT_EQUAL_INT(CE_ERR_POSE, ce_mask_clothing_regions(&p2, &o, m, PW, PH));
    TEST_ASSERT_EQUAL_MEMORY(before, m, sizeof m);
    /* Hombro con coordenadas no finitas o absurdas = ausente (se estima). */
    p2 = pose;
    p2.k[CE_JOINT_RSHOULDER].x = HUGE_VAL;
    memcpy(m, before, sizeof m);
    TEST_ASSERT_EQUAL_INT(n_full, ce_mask_clothing_regions(&p2, &o, m, PW, PH));
    p2.k[CE_JOINT_RSHOULDER].x = 2.0 * CE_POSE_COORD_MAX;
    memcpy(m, before, sizeof m);
    TEST_ASSERT_EQUAL_INT(n_full, ce_mask_clothing_regions(&p2, &o, m, PW, PH));

    /* Pose degenerada: hombros juntos (sw < 1) o caderas sobre la línea de hombros. */
    p2 = pose;
    p2.k[CE_JOINT_LSHOULDER].x = 100.5;
    p2.k[CE_JOINT_RSHOULDER].x = 100.0;
    memcpy(m, before, sizeof m);
    TEST_ASSERT_EQUAL_INT(CE_ERR_POSE, ce_mask_clothing_regions(&p2, &o, m, PW, PH));
    TEST_ASSERT_EQUAL_MEMORY(before, m, sizeof m);
    p2 = pose;
    p2.k[CE_JOINT_LHIP].y = 90.0;
    p2.k[CE_JOINT_RHIP].y = 90.0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_POSE, ce_mask_clothing_regions(&p2, &o, m, PW, PH));
    TEST_ASSERT_EQUAL_MEMORY(before, m, sizeof m);
    /* Pose fuera de la imagen: 0 píxeles, sin error. */
    p2 = pose;
    {
        int j;
        for (j = 0; j < CE_JOINT_COUNT; ++j) p2.k[j].x += 5000.0;
    }
    memcpy(m, before, sizeof m);
    TEST_ASSERT_EQUAL_INT(0, ce_mask_clothing_regions(&p2, &o, m, PW, PH));
    TEST_ASSERT_EQUAL_INT(0, count_nonzero(m, sizeof m));

    /* CE_ERR_ARG sin tocar la máscara. */
    memcpy(m, before, sizeof m);
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_clothing_regions(NULL, &o, m, PW, PH));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_clothing_regions(&pose, NULL, m, PW, PH));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_clothing_regions(&pose, &o, NULL, PW, PH));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_clothing_regions(&pose, &o, m, 0, PH));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_clothing_regions(&pose, &o, m, PW, CE_IMAGE_MAX_SIDE + 1));
    bad = o; bad.min_confidence = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_clothing_regions(&pose, &bad, m, PW, PH));
    bad = o; bad.min_confidence = 1.5;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_clothing_regions(&pose, &bad, m, PW, PH));
    bad = o; bad.torso_margin = -0.1;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_clothing_regions(&pose, &bad, m, PW, PH));
    bad = o; bad.limb_width = HUGE_VAL;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_clothing_regions(&pose, &bad, m, PW, PH));
    bad = o; bad.include_legs = 2;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_clothing_regions(&pose, &bad, m, PW, PH));
    TEST_ASSERT_EQUAL_MEMORY(before, m, sizeof m);
    ce_region_opts_default(NULL); /* no aborta */
    hash_mask(full, sizeof full, n_full);
}

/* ------------------------------------------------------------------------
 * (4) Recorte de cabeza sin pose
 * ---------------------------------------------------------------------- */

static void test_cut_head(void)
{
    static uint8_t m[PW * PH], before[PW * PH];
    int x, y, n;

    memset(m, 0, sizeof m);
    for (y = 100; y < 300; ++y) {
        for (x = 50; x < 150; ++x) m[(size_t)y * PW + (size_t)x] = 200;
    }
    memcpy(before, m, sizeof m);
    /* bbox filas 100..299 (H = 200), fraction 0,25 -> c = 50: filas 100..149 a 0. */
    n = ce_mask_cut_head(m, PW, PH, 0.25);
    TEST_ASSERT_EQUAL_INT(150 * 100, n);
    for (y = 0; y < PH; ++y) {
        for (x = 0; x < PW; ++x) {
            const uint8_t want = (y >= 150 && y < 300 && x >= 50 && x < 150) ? 200 : 0;
            TEST_ASSERT_EQUAL_UINT8(want, m[(size_t)y * PW + (size_t)x]);
        }
    }
    hash_mask(m, sizeof m, n);
    /* fraction 0: sin cambios. */
    memcpy(m, before, sizeof m);
    TEST_ASSERT_EQUAL_INT(200 * 100, ce_mask_cut_head(m, PW, PH, 0.0));
    TEST_ASSERT_EQUAL_MEMORY(before, m, sizeof m);
    /* Redondeo: H = 7, fraction 0,5 -> floor(3,5 + 0,5) = 4 filas. */
    memset(m, 0, sizeof m);
    for (y = 10; y < 17; ++y) m[(size_t)y * PW + 3] = 1;
    TEST_ASSERT_EQUAL_INT(3, ce_mask_cut_head(m, PW, PH, 0.5));
    TEST_ASSERT_EQUAL_UINT8(0, m[13 * PW + 3]);
    TEST_ASSERT_EQUAL_UINT8(1, m[14 * PW + 3]);
    /* fraction 0,3 sobre H = 7 -> floor(2,6) = 2. */
    memset(m, 0, sizeof m);
    for (y = 10; y < 17; ++y) m[(size_t)y * PW + 3] = 1;
    TEST_ASSERT_EQUAL_INT(5, ce_mask_cut_head(m, PW, PH, 0.3));
    /* Máscara vacía: 0 sin error. */
    memset(m, 0, sizeof m);
    TEST_ASSERT_EQUAL_INT(0, ce_mask_cut_head(m, PW, PH, 0.2));
    /* Errores sin tocar. */
    memcpy(m, before, sizeof m);
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_cut_head(NULL, PW, PH, 0.2));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_cut_head(m, 0, PH, 0.2));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_cut_head(m, PW, PH, 0.6));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_cut_head(m, PW, PH, -0.01));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_cut_head(m, PW, PH, NAN));
    TEST_ASSERT_EQUAL_MEMORY(before, m, sizeof m);
}

/* ------------------------------------------------------------------------
 * (5) Piel adaptativa
 * ---------------------------------------------------------------------- */

#define SK_STRIDE (PW * 4 + 12)

typedef struct {
    int x0, y0, x1, y1; /* [x0, x1) x [y0, y1) */
} rect;

static const rect R_FACE = {70, 20, 130, 80};
static const rect R_ARM_L = {40, 100, 52, 300};
static const rect R_ARM_R = {148, 100, 160, 300};
static const rect R_RED = {60, 100, 140, 167};
static const rect R_NAVY = {60, 167, 140, 234};
static const rect R_BEIGE = {60, 234, 140, 300};

static const uint8_t GARMENT_RED[3] = {190, 30, 40};
static const uint8_t GARMENT_NAVY[3] = {30, 40, 90};
static const uint8_t GARMENT_BEIGE[3] = {228, 192, 150};

static uint64_t g_noise = 1;

static int noise4(void)
{
    g_noise = g_noise * 6364136223846793005ULL + 1442695040888963407ULL;
    return (int)((g_noise >> 33) % 9u) - 4; /* -4..4 */
}

static uint8_t clamp8(int v)
{
    return (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v));
}

static void fill_rect(uint8_t *px, const rect *r, const uint8_t *c)
{
    int x, y, ch;
    for (y = r->y0; y < r->y1; ++y) {
        for (x = r->x0; x < r->x1; ++x) {
            uint8_t *p = px + (size_t)y * SK_STRIDE + (size_t)x * 4u;
            for (ch = 0; ch < 3; ++ch) p[ch] = clamp8((int)c[ch] + noise4());
        }
    }
}

static void mask_rect(uint8_t *m, const rect *r, uint8_t v)
{
    int x, y;
    for (y = r->y0; y < r->y1; ++y) {
        for (x = r->x0; x < r->x1; ++x) m[(size_t)y * PW + (size_t)x] = v;
    }
}

static int rect_kept(const uint8_t *m, const rect *r)
{
    int x, y, c = 0;
    for (y = r->y0; y < r->y1; ++y) {
        for (x = r->x0; x < r->x1; ++x) c += m[(size_t)y * PW + (size_t)x] != 0;
    }
    return c;
}

static int rect_area(const rect *r)
{
    return (r->x1 - r->x0) * (r->y1 - r->y0);
}

/* Imagen RGBA (stride con relleno, alpha basura) de la persona con piel `skin`. */
static void skin_scene(uint8_t *px, const uint8_t *skin, uint64_t seed, int skin_torso)
{
    static const uint8_t GRAY[3] = {128, 128, 128};
    const rect all = {0, 0, PW, PH};
    size_t i;
    g_noise = seed;
    for (i = 0; i < (size_t)SK_STRIDE * PH; ++i) px[i] = (uint8_t)(i * 31u);
    fill_rect(px, &all, GRAY);
    fill_rect(px, &R_FACE, skin);
    fill_rect(px, &R_ARM_L, skin);
    fill_rect(px, &R_ARM_R, skin);
    fill_rect(px, &R_RED, skin_torso ? skin : GARMENT_RED);
    fill_rect(px, &R_NAVY, skin_torso ? skin : GARMENT_NAVY);
    fill_rect(px, &R_BEIGE, skin_torso ? skin : GARMENT_BEIGE);
}

static ce_image rgba_image(const uint8_t *px)
{
    ce_image img;
    img.pixels = px;
    img.width = PW;
    img.height = PH;
    img.stride_bytes = SK_STRIDE;
    img.fmt = CE_RGBA8;
    img.mask = NULL;
    return img;
}

static void hash_model(const ce_skin_model *m)
{
    const int64_t n = m->n;
    g_hash = fnv_bytes(g_hash, &m->mean.L, sizeof(double));
    g_hash = fnv_bytes(g_hash, &m->mean.a, sizeof(double));
    g_hash = fnv_bytes(g_hash, &m->mean.b, sizeof(double));
    g_hash = fnv_bytes(g_hash, m->cov, sizeof m->cov);
    g_hash = fnv_bytes(g_hash, m->inv_cov, sizeof m->inv_cov);
    g_hash = fnv_bytes(g_hash, &n, sizeof n);
}

static void clothes_mask(uint8_t *m)
{
    memset(m, 0, (size_t)PW * PH);
    mask_rect(m, &R_ARM_L, 255);
    mask_rect(m, &R_ARM_R, 255);
    mask_rect(m, &R_RED, 255);
    mask_rect(m, &R_NAVY, 255);
    mask_rect(m, &R_BEIGE, 255);
}

static void test_skin_tones(void)
{
    static const uint8_t TONES[3][3] = {{236, 198, 172}, {198, 145, 110}, {110, 72, 50}};
    static const char *const NAMES[3] = {"clara", "media", "oscura"};
    static uint8_t px[SK_STRIDE * PH], sample[PW * PH], m[PW * PH], m2[PW * PH];
    const ce_lab light = ce_srgb8_to_lab(TONES[0][0], TONES[0][1], TONES[0][2]);
    const ce_lab beige = ce_srgb8_to_lab(GARMENT_BEIGE[0], GARMENT_BEIGE[1], GARMENT_BEIGE[2]);
    const double de_beige = ce_de2000(light, beige);
    int t;

    printf("beige (228,192,150) a dE00 %.3f de la piel clara\n", de_beige);
    TEST_ASSERT_TRUE(de_beige > 5.0 && de_beige < 7.0);
    ce_skin_opts_default(NULL);

    for (t = 0; t < 3; ++t) {
        ce_image img;
        ce_skin_model model;
        ce_skin_opts so;
        int rc, arms, red, navy, beige_kept;
        double f_arms, f_red, f_navy, f_beige;

        skin_scene(px, TONES[t], 1000u + (uint64_t)t, 0);
        img = rgba_image(px);
        memset(sample, 0, sizeof sample);
        mask_rect(sample, &R_FACE, 255);
        TEST_ASSERT_EQUAL_INT(CE_OK, ce_skin_model_fit(&img, sample, &model));
        TEST_ASSERT_EQUAL_INT(rect_area(&R_FACE), model.n);
        TEST_ASSERT_TRUE(ce_de2000(model.mean, ce_srgb8_to_lab(TONES[t][0], TONES[t][1], TONES[t][2])) < 1.0);
        TEST_ASSERT_TRUE(model.cov[0] > CE_SKIN_COV_EPSILON && model.cov[4] > CE_SKIN_COV_EPSILON);
        TEST_ASSERT_EQUAL_DOUBLE(model.cov[1], model.cov[3]);
        {
            /* cov · inv_cov = I (±1e-9). */
            int i, j, k;
            for (i = 0; i < 3; ++i) {
                for (j = 0; j < 3; ++j) {
                    double s = 0.0;
                    for (k = 0; k < 3; ++k) s += model.cov[i * 3 + k] * model.inv_cov[k * 3 + j];
                    TEST_ASSERT_TRUE(fabs(s - (i == j ? 1.0 : 0.0)) < 1e-9);
                }
            }
        }
        hash_model(&model);

        /* Medición con la salvaguarda desactivada (max_excluded_fraction 1). */
        ce_skin_opts_default(&so);
        TEST_ASSERT_EQUAL_DOUBLE(2.5, so.max_mahalanobis);
        TEST_ASSERT_EQUAL_DOUBLE(0.35, so.max_excluded_fraction);
        so.max_excluded_fraction = 1.0;
        clothes_mask(m);
        rc = ce_mask_exclude_skin(&img, &model, &so, m);
        TEST_ASSERT_EQUAL_INT(CE_OK, rc);
        arms = rect_kept(m, &R_ARM_L) + rect_kept(m, &R_ARM_R);
        red = rect_kept(m, &R_RED);
        navy = rect_kept(m, &R_NAVY);
        beige_kept = rect_kept(m, &R_BEIGE);
        f_arms = 1.0 - (double)arms / (double)(2 * rect_area(&R_ARM_L));
        f_red = 1.0 - (double)red / (double)rect_area(&R_RED);
        f_navy = 1.0 - (double)navy / (double)rect_area(&R_NAVY);
        f_beige = 1.0 - (double)beige_kept / (double)rect_area(&R_BEIGE);
        printf("piel %s: brazos eliminados %.2f %%, rojo %.2f %%, azul marino %.2f %%, beige %.2f %%\n",
               NAMES[t], 100.0 * f_arms, 100.0 * f_red, 100.0 * f_navy, 100.0 * f_beige);
        TEST_ASSERT_TRUE_MESSAGE(f_arms >= 0.95, "brazos: < 95 % eliminados");
        TEST_ASSERT_TRUE_MESSAGE(f_red < 0.05, "prenda roja: >= 5 % eliminada");
        TEST_ASSERT_TRUE_MESSAGE(f_navy < 0.05, "prenda azul marino: >= 5 % eliminada");
        hash_mask(m, sizeof m, count_nonzero(m, sizeof m));

        /* Con las opciones por defecto (salvaguarda 35 %): brazos = 4800 de
         * 20800 px (23 %); si la beige también cae, la salvaguarda salta. */
        ce_skin_opts_default(&so);
        clothes_mask(m2);
        rc = ce_mask_exclude_skin(&img, &model, &so, m2);
        printf("piel %s con salvaguarda por defecto: rc %d\n", NAMES[t], rc);
        if (rc == CE_OK) {
            TEST_ASSERT_EQUAL_MEMORY(m, m2, sizeof m);
        } else {
            TEST_ASSERT_EQUAL_INT(CE_SKIN_GUARD, rc);
        }

        /* Guardia: el torso entero del color de la piel -> CE_SKIN_GUARD intacta. */
        skin_scene(px, TONES[t], 2000u + (uint64_t)t, 1);
        clothes_mask(m);
        memcpy(m2, m, sizeof m);
        ce_skin_opts_default(&so);
        TEST_ASSERT_EQUAL_INT(CE_SKIN_GUARD, ce_mask_exclude_skin(&img, &model, &so, m));
        TEST_ASSERT_EQUAL_MEMORY(m2, m, sizeof m);
        /* Sin salvaguarda se vacía casi entera. */
        so.max_excluded_fraction = 1.0;
        TEST_ASSERT_EQUAL_INT(CE_OK, ce_mask_exclude_skin(&img, &model, &so, m));
        TEST_ASSERT_TRUE(count_nonzero(m, sizeof m) < 20800 / 10);
    }
}

static void test_skin_errors(void)
{
    static const uint8_t SKIN[3] = {198, 145, 110};
    static uint8_t px[SK_STRIDE * PH], sample[PW * PH], m[PW * PH], before[PW * PH];
    ce_image img;
    ce_skin_model model, bad, sentinel;
    ce_skin_opts so;
    int i;

    skin_scene(px, SKIN, 77u, 0);
    img = rgba_image(px);
    ce_skin_opts_default(&so);

    /* 49 muestras >= 128 (y muchas a 127): CE_ERR_SKIN_SAMPLES sin escribir. */
    memset(sample, 127, sizeof sample);
    for (i = 0; i < 49; ++i) sample[30 * PW + 80 + (i % 40) + (i / 40) * PW] = 128;
    memset(&model, 0x5A, sizeof model);
    memset(&sentinel, 0x5A, sizeof sentinel);
    TEST_ASSERT_EQUAL_INT(CE_ERR_SKIN_SAMPLES, ce_skin_model_fit(&img, sample, &model));
    TEST_ASSERT_EQUAL_MEMORY(&sentinel, &model, sizeof model);
    /* 50 exactas: vale. */
    sample[60 * PW + 100] = 255;
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_skin_model_fit(&img, sample, &model));
    TEST_ASSERT_EQUAL_INT(50, model.n);
    /* Errores de argumentos e imagen. */
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_skin_model_fit(NULL, sample, &model));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_skin_model_fit(&img, NULL, &model));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_skin_model_fit(&img, sample, NULL));
    {
        ce_image b = img;
        b.stride_bytes = PW * 4 - 1;
        TEST_ASSERT_EQUAL_INT(CE_ERR_STRIDE, ce_skin_model_fit(&b, sample, &model));
        b = img;
        b.width = 0;
        TEST_ASSERT_EQUAL_INT(CE_ERR_DIMS, ce_skin_model_fit(&b, sample, &model));
        b = img;
        b.fmt = (ce_pixel_format)7;
        TEST_ASSERT_EQUAL_INT(CE_ERR_FORMAT, ce_skin_model_fit(&b, sample, &model));
    }
    /* Muestra plana (sin ruido): covarianza = ε·I, inversa = I/ε; excluye el color exacto. */
    {
        static uint8_t flat[PW * 4 * 10];
        uint8_t fs[PW * 10], fm[PW * 10];
        ce_image fi;
        ce_skin_model fmdl;
        for (i = 0; i < PW * 10; ++i) {
            flat[i * 4] = SKIN[0];
            flat[i * 4 + 1] = SKIN[1];
            flat[i * 4 + 2] = SKIN[2];
            fs[i] = 255;
            fm[i] = (i % 2) ? 255 : 0;
        }
        fi.pixels = flat;
        fi.width = PW;
        fi.height = 10;
        fi.stride_bytes = PW * 4;
        fi.fmt = CE_RGBX8;
        fi.mask = NULL;
        TEST_ASSERT_EQUAL_INT(CE_OK, ce_skin_model_fit(&fi, fs, &fmdl));
        /* La media de 2000 valores iguales puede no ser exacta: residuos ~1e-28. */
        TEST_ASSERT_TRUE(fabs(fmdl.cov[0] - CE_SKIN_COV_EPSILON) < 1e-12);
        TEST_ASSERT_TRUE(fabs(fmdl.cov[1]) < 1e-12);
        TEST_ASSERT_TRUE(fabs(fmdl.inv_cov[0] - 1.0 / CE_SKIN_COV_EPSILON) < 1e-12);
        so.max_excluded_fraction = 1.0;
        TEST_ASSERT_EQUAL_INT(CE_OK, ce_mask_exclude_skin(&fi, &fmdl, &so, fm));
        TEST_ASSERT_EQUAL_INT(0, count_nonzero(fm, sizeof fm));
        ce_skin_opts_default(&so);
    }

    /* Modelos degenerados y opciones inválidas: sin tocar la máscara. */
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_skin_model_fit(&img, sample, &model));
    clothes_mask(m);
    memcpy(before, m, sizeof m);
    bad = model;
    bad.n = 10;
    TEST_ASSERT_EQUAL_INT(CE_ERR_SKIN_SAMPLES, ce_mask_exclude_skin(&img, &bad, &so, m));
    bad = model;
    bad.inv_cov[4] = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_exclude_skin(&img, &bad, &so, m));
    bad = model;
    bad.mean.a = HUGE_VAL;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_exclude_skin(&img, &bad, &so, m));
    bad = model;
    memset(bad.inv_cov, 0, sizeof bad.inv_cov); /* singular */
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_exclude_skin(&img, &bad, &so, m));
    bad = model;
    for (i = 0; i < 9; ++i) bad.inv_cov[i] = -model.inv_cov[i]; /* definida negativa */
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_exclude_skin(&img, &bad, &so, m));
    bad = model;
    bad.inv_cov[1] = 1e6; /* parte simétrica indefinida */
    bad.inv_cov[3] = 1e6;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_exclude_skin(&img, &bad, &so, m));
    so.max_mahalanobis = NAN;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_exclude_skin(&img, &model, &so, m));
    so.max_mahalanobis = -1.0;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_exclude_skin(&img, &model, &so, m));
    ce_skin_opts_default(&so);
    so.max_excluded_fraction = 1.5;
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_exclude_skin(&img, &model, &so, m));
    ce_skin_opts_default(&so);
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_exclude_skin(NULL, &model, &so, m));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_exclude_skin(&img, NULL, &so, m));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_exclude_skin(&img, &model, NULL, m));
    TEST_ASSERT_EQUAL_INT(CE_ERR_ARG, ce_mask_exclude_skin(&img, &model, &so, NULL));
    TEST_ASSERT_EQUAL_MEMORY(before, m, sizeof m);
    /* Umbral 0 y máscara vacía: 0 sin cambios. */
    so.max_mahalanobis = 0.0;
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_mask_exclude_skin(&img, &model, &so, m));
    TEST_ASSERT_EQUAL_MEMORY(before, m, sizeof m);
    memset(m, 0, sizeof m);
    ce_skin_opts_default(&so);
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_mask_exclude_skin(&img, &model, &so, m));
    TEST_ASSERT_EQUAL_INT(0, count_nonzero(m, sizeof m));
}

/* La tabla por canal que usa la piel da el mismo Lab que ce_srgb8_to_lab en
 * los 16.777.216 colores (memcmp de los tres doubles). */
static void test_skin_lab_table_exhaustive(void)
{
    static ce_srgb8_xyz_table tab;
    long bad = 0;
    int r, g, b;
    ce_srgb8_xyz_table_init(&tab);
    for (r = 0; r < 256; ++r) {
        for (g = 0; g < 256; ++g) {
            for (b = 0; b < 256; ++b) {
                const ce_lab a = ce_srgb8_to_lab_table(&tab, (uint8_t)r, (uint8_t)g, (uint8_t)b);
                const ce_lab c = ce_srgb8_to_lab((uint8_t)r, (uint8_t)g, (uint8_t)b);
                bad += memcmp(&a.L, &c.L, sizeof(double)) != 0 || memcmp(&a.a, &c.a, sizeof(double)) != 0
                    || memcmp(&a.b, &c.b, sizeof(double)) != 0;
            }
        }
    }
    printf("tabla Lab de piel: %ld diferencias en 16777216 colores\n", bad);
    TEST_ASSERT_EQUAL_INT(0, (int)bad);
}

/* ------------------------------------------------------------------------
 * (6) Determinismo y paridad
 * ---------------------------------------------------------------------- */

static void test_determinism(void)
{
    static const uint8_t SKIN[3] = {236, 198, 172};
    static uint8_t a[PW * PH], b[PW * PH], px[SK_STRIDE * PH], sample[PW * PH];
    ce_region_opts o;
    ce_skin_opts so;
    ce_skin_model m1, m2;
    ce_pose pose;
    ce_image img;
    int na, nb;

    ce_region_opts_default(&o);
    pose_front(&pose, 1.0, 0.0, 0.0);
    person_mask(a, PW, PH);
    person_mask(b, PW, PH);
    na = ce_mask_clothing_regions(&pose, &o, a, PW, PH);
    nb = ce_mask_clothing_regions(&pose, &o, b, PW, PH);
    TEST_ASSERT_EQUAL_INT(na, nb);
    TEST_ASSERT_EQUAL_MEMORY(a, b, sizeof a);

    skin_scene(px, SKIN, 4242u, 0);
    img = rgba_image(px);
    memset(sample, 0, sizeof sample);
    mask_rect(sample, &R_FACE, 255);
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_skin_model_fit(&img, sample, &m1));
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_skin_model_fit(&img, sample, &m2));
    /* Campo a campo: el relleno final del struct no está definido. */
    TEST_ASSERT_EQUAL_MEMORY(&m1.mean, &m2.mean, sizeof m1.mean);
    TEST_ASSERT_EQUAL_MEMORY(m1.cov, m2.cov, sizeof m1.cov);
    TEST_ASSERT_EQUAL_MEMORY(m1.inv_cov, m2.inv_cov, sizeof m1.inv_cov);
    TEST_ASSERT_EQUAL_INT(m1.n, m2.n);
    ce_skin_opts_default(&so);
    clothes_mask(a);
    clothes_mask(b);
    TEST_ASSERT_EQUAL_INT(ce_mask_exclude_skin(&img, &m1, &so, a), ce_mask_exclude_skin(&img, &m2, &so, b));
    TEST_ASSERT_EQUAL_MEMORY(a, b, sizeof a);
    hash_mask(a, sizeof a, count_nonzero(a, sizeof a));
}

/* Constante medida en nativo (Apple arm64): el mismo test en WASM (node) y con
 * ASan/UBSan debe dar exactamente este valor (regiones y piel bit-idénticas). */
#define CE_MASK_PARITY_HASH 0x36160cbd7630fb2bULL

static void test_parity_hash(void)
{
    printf("MASK_HASH=%016" PRIx64 "\n", g_hash);
    TEST_ASSERT_EQUAL_HEX64(CE_MASK_PARITY_HASH, g_hash);
}

/* ------------------------------------------------------------------------
 * (7) Tiempos
 * ---------------------------------------------------------------------- */

static double now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1.0e6;
}

static void test_timing(void)
{
    const int rw = 1024, rh = 2048, sw = 1024, sh = 1024;
    uint8_t *m = (uint8_t *)malloc((size_t)rw * (size_t)rh);
    uint8_t *px = (uint8_t *)malloc((size_t)sw * (size_t)sh * 4u);
    uint8_t *sample = (uint8_t *)malloc((size_t)sw * (size_t)sh);
    uint8_t *sm = (uint8_t *)malloc((size_t)sw * (size_t)sh);
    ce_pose pose;
    ce_region_opts o;
    ce_skin_model model;
    ce_skin_opts so;
    ce_image img;
    double t0, regions_ms, fit_ms, skin_ms;
    size_t i;
    int n;
    TEST_ASSERT_NOT_NULL(m);
    TEST_ASSERT_NOT_NULL(px);
    TEST_ASSERT_NOT_NULL(sample);
    TEST_ASSERT_NOT_NULL(sm);
    memset(m, 255, (size_t)rw * (size_t)rh);
    pose_front(&pose, 5.12, 0.0, 0.0);
    ce_region_opts_default(&o);
    o.include_forearms = 1;
    t0 = now_ms();
    n = ce_mask_clothing_regions(&pose, &o, m, rw, rh);
    regions_ms = now_ms() - t0;
    TEST_ASSERT_TRUE(n > 0);

    g_noise = 31337u;
    for (i = 0; i < (size_t)sw * (size_t)sh; ++i) {
        px[i * 4] = clamp8(198 + 6 * noise4());
        px[i * 4 + 1] = clamp8(145 + 6 * noise4());
        px[i * 4 + 2] = clamp8(110 + 6 * noise4());
        px[i * 4 + 3] = 255;
        sample[i] = (i % 97 == 0) ? 255 : 0;
        sm[i] = 255;
    }
    img.pixels = px;
    img.width = sw;
    img.height = sh;
    img.stride_bytes = sw * 4;
    img.fmt = CE_RGBA8;
    img.mask = NULL;
    t0 = now_ms();
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_skin_model_fit(&img, sample, &model));
    fit_ms = now_ms() - t0;
    ce_skin_opts_default(&so);
    so.max_excluded_fraction = 1.0; /* peor caso: dos pasadas completas */
    t0 = now_ms();
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_mask_exclude_skin(&img, &model, &so, sm));
    skin_ms = now_ms() - t0;
    printf("MASK_REGIONS_MS=%.2f (1024x2048, %d px) MASK_SKIN_FIT_MS=%.2f (%d muestras) MASK_SKIN_MS=%.2f (1024x1024, quedan %d px)\n",
           regions_ms, n, fit_ms, model.n, skin_ms, count_nonzero(sm, (size_t)sw * (size_t)sh));
    free(m);
    free(px);
    free(sample);
    free(sm);
}

/* ------------------------------------------------------------------------
 * Fixtures para los tests del CLI
 * ---------------------------------------------------------------------- */

static void write_file(const char *name, const char *header, const uint8_t *data, size_t n)
{
    char path[1024];
    FILE *f;
    snprintf(path, sizeof path, "%s/%s", CE_TEST_OUT_DIR, name);
    f = fopen(path, "wb");
    TEST_ASSERT_NOT_NULL_MESSAGE(f, path);
    if (header != NULL) fputs(header, f);
    TEST_ASSERT_EQUAL_size_t(n, fwrite(data, 1, n, f));
    TEST_ASSERT_EQUAL_INT(0, fclose(f));
}

static void test_write_cli_fixtures(void)
{
    static const uint8_t SKIN[3] = {198, 145, 110};
    static uint8_t px[SK_STRIDE * PH], rgb[PW * PH * 3], person[PW * PH], clothes[PW * PH], face[PW * PH];
    static uint8_t reg[PW * PH], skin_out[PW * PH];
    char text[4096];
    char header[64];
    ce_pose pose;
    ce_region_opts o;
    ce_skin_opts so;
    ce_skin_model model;
    ce_image img;
    int i, n_regions, rc_skin, n_before, n_after;
    size_t len = 0;

    skin_scene(px, SKIN, 99u, 0);
    for (i = 0; i < PW * PH; ++i) {
        const size_t o4 = (size_t)(i / PW) * SK_STRIDE + (size_t)(i % PW) * 4u;
        rgb[i * 3] = px[o4];
        rgb[i * 3 + 1] = px[o4 + 1];
        rgb[i * 3 + 2] = px[o4 + 2];
    }
    memset(person, 0, sizeof person);
    mask_rect(person, &R_FACE, 255);
    clothes_mask(clothes);
    for (i = 0; i < PW * PH; ++i) person[i] = person[i] | clothes[i];
    memset(face, 0, sizeof face);
    mask_rect(face, &R_FACE, 255);

    snprintf(header, sizeof header, "P6\n%d %d\n255\n", PW, PH);
    write_file("mask_person.ppm", header, rgb, sizeof rgb);
    write_file("mask person copy.ppm", header, rgb, sizeof rgb);
    snprintf(header, sizeof header, "P5\n%d %d\n255\n", PW, PH);
    write_file("mask_person.pgm", header, person, sizeof person);
    write_file("mask_clothes.pgm", header, clothes, sizeof clothes);
    write_file("mask clothes copy.pgm", header, clothes, sizeof clothes);
    write_file("mask_face.pgm", header, face, sizeof face);

    pose_front(&pose, 1.0, 0.0, 0.0);
    len = 0;
    for (i = 0; i < CE_JOINT_COUNT; ++i) {
        len += (size_t)snprintf(text + len, sizeof text - len, "%.17g %.17g %.17g\n",
                                pose.k[i].x, pose.k[i].y, pose.k[i].confidence);
    }
    write_file("mask_pose.txt", NULL, (const uint8_t *)text, len);
    pose.k[CE_JOINT_LHIP].confidence = 0.0;
    pose.k[CE_JOINT_RHIP].confidence = 0.0;
    len = 0;
    len += (size_t)snprintf(text + len, sizeof text - len, "# pose sin caderas (CE_ERR_POSE)\n");
    for (i = 0; i < CE_JOINT_COUNT; ++i) {
        len += (size_t)snprintf(text + len, sizeof text - len, "%.17g\t%.17g\t%.17g\n",
                                pose.k[i].x, pose.k[i].y, pose.k[i].confidence);
    }
    write_file("mask_pose_nohips.txt", NULL, (const uint8_t *)text, len);

    /* Resultados esperados de la API para comparar con el CLI. */
    pose_front(&pose, 1.0, 0.0, 0.0);
    ce_region_opts_default(&o);
    memcpy(reg, person, sizeof reg);
    n_regions = ce_mask_clothing_regions(&pose, &o, reg, PW, PH);
    TEST_ASSERT_TRUE(n_regions > 0);
    snprintf(header, sizeof header, "P5\n%d %d\n255\n", PW, PH);
    write_file("mask_expected_regions.pgm", header, reg, sizeof reg);
    img.pixels = rgb;
    img.width = PW;
    img.height = PH;
    img.stride_bytes = PW * 3;
    img.fmt = CE_RGB8;
    img.mask = NULL;
    TEST_ASSERT_EQUAL_INT(CE_OK, ce_skin_model_fit(&img, face, &model));
    ce_skin_opts_default(&so);
    memcpy(skin_out, clothes, sizeof skin_out);
    n_before = count_nonzero(skin_out, sizeof skin_out);
    rc_skin = ce_mask_exclude_skin(&img, &model, &so, skin_out);
    n_after = count_nonzero(skin_out, sizeof skin_out);
    TEST_ASSERT_EQUAL_INT(CE_OK, rc_skin);
    write_file("mask_expected_skin.pgm", header, skin_out, sizeof skin_out);
    len = (size_t)snprintf(text, sizeof text,
                           "{\"regions_pixels\": %d, \"skin_excluded\": %d, \"skin_guard\": 0, \"skin_mask_pixels\": %d}\n",
                           n_regions, n_before - n_after, n_before);
    write_file("mask_expected.json", NULL, (const uint8_t *)text, len);

    /* Lista del batch: sin máscara, con máscara, rutas con espacios entre
     * comillas y tabulador, máscara inexistente. */
    len = (size_t)snprintf(text, sizeof text,
                           "# batch con mascaras por linea\n"
                           "%s/mask_person.ppm\n"
                           "%s/mask_person.ppm %s/mask_clothes.pgm\n"
                           "\"%s/mask person copy.ppm\"\t\"%s/mask clothes copy.pgm\"\n"
                           "%s/mask_person.ppm %s/does_not_exist_mask.pgm\n",
                           CE_TEST_OUT_DIR, CE_TEST_OUT_DIR, CE_TEST_OUT_DIR, CE_TEST_OUT_DIR, CE_TEST_OUT_DIR,
                           CE_TEST_OUT_DIR, CE_TEST_OUT_DIR);
    write_file("mask_batch_list.txt", NULL, (const uint8_t *)text, len);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_regions_front_pose);
    RUN_TEST(test_regions_invariance);
    RUN_TEST(test_regions_errors_and_symmetry);
    RUN_TEST(test_cut_head);
    RUN_TEST(test_skin_tones);
    RUN_TEST(test_skin_errors);
    RUN_TEST(test_skin_lab_table_exhaustive);
    RUN_TEST(test_determinism);
    RUN_TEST(test_parity_hash);
    RUN_TEST(test_timing);
    RUN_TEST(test_write_cli_fixtures);
    return UNITY_END();
}
