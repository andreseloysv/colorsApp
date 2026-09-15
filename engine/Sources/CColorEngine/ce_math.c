/*
 * ce_math.c — implementación de la capa 1 (matemática de color pura).
 *
 * Reglas: C11, sin I/O, sin malloc, todo en double, sin contracción FMA
 * (pragma abajo + -ffp-contract=off en el build) para que nativo y WASM
 * produzcan los mismos bits en las operaciones básicas. Las funciones
 * trascendentes (pow, cbrt, atan2, sin, cos, exp) no se toman de <math.h>
 * sino de ce_libm.c (copia de musl, sin FMA): así también ellas dan los
 * mismos bits en todas las plataformas. De <math.h> solo quedan sqrt y fabs,
 * exactos por IEEE 754. Ver README ("Determinismo nativo vs WASM").
 */
#include "ce/ce.h"

#include <math.h>
#include <stdint.h>

#pragma STDC FP_CONTRACT OFF

/* ------------------------------------------------------------------------
 * Constantes
 * ---------------------------------------------------------------------- */

/* Matriz RGB(lineal) -> XYZ DERIVADA de los primarios sRGB (0.64,0.33),
 * (0.30,0.60), (0.15,0.06) y del blanco D65 xy (0.3127, 0.3290). Obtenida con
 * colour-science 0.4.7 / numpy 2.5.3:
 *   cs = RGB_COLOURSPACE_sRGB.copy(); cs.use_derived_transformation_matrices(True)
 *   repr(cs.matrix_RGB_to_XYZ)   (oracle/oracle/reference.py, `python -m oracle.reference`)
 * NO es la matriz de cuatro decimales de IEC 61966-2-1. Sus filas suman
 * exactamente el blanco D65 (0.95045593, 1, 1.08905775). */
static const double CE_M_RGB_TO_XYZ[9] = {
    0.41239079926595934, 0.35758433938387796, 0.18048078840183432,
    0.2126390058715103,  0.7151686787677559,  0.07219231536073373,
    0.019330818715591825, 0.11919477979462595, 0.9505321522496608
};

/* Inversa de la anterior (np.linalg.inv, misma fuente). */
static const double CE_M_XYZ_TO_RGB[9] = {
    3.2409699419045226,  -1.537383177570094,  -0.49861076029300344,
    -0.9692436362808798,  1.8759675015077206,  0.041555057407175626,
    0.055630079696993635, -0.2039769588889765, 1.0569715142428784
};

/* Blanco de referencia D65 para CIELAB (CIE 015:2004, observador 2°). */
static const double CE_D65_X = 0.3127;
static const double CE_D65_Y = 0.3290;

/* Constantes CIELAB exactas (CIE 015:2004): epsilon = (6/29)^3, kappa = (29/3)^3. */
static const double CE_LAB_EPSILON = 216.0 / 24389.0;
static const double CE_LAB_KAPPA = 24389.0 / 27.0;

/* Umbrales de la curva sRGB (IEC 61966-2-1). */
static const double CE_SRGB_DECODE_THRESHOLD = 0.04045;
static const double CE_SRGB_ENCODE_THRESHOLD = 0.0031308;

/* Transformación de Bradford (Lam 1985), tal como la publica colour. */
static const double CE_CAT_BRADFORD[9] = {
    0.8951,  0.2664, -0.1614,
    -0.7502, 1.7135,  0.0367,
    0.0389, -0.0685,  1.0296
};

/* Iluminantes xy (CIE 015:2004, observador 2°), en el orden de ce_illuminant. */
static const double CE_ILLUMINANT_XY[CE_ILL_COUNT][2] = {
    {0.44758, 0.40745}, /* A   */
    {0.34570, 0.35850}, /* D50 */
    {0.31270, 0.32900}, /* D65 */
    {0.29903, 0.31488}, /* D75 */
    {0.37210, 0.37510}  /* F2  */
};

/* pi con la precisión de un double (igual que M_PI, que no es C11 estándar). */
static const double CE_PI = 3.14159265358979323846;

/* 25^7, usado en ΔE2000; exactamente representable en double. */
static const double CE_POW25_7 = 6103515625.0;

/* ------------------------------------------------------------------------
 * Utilidades internas
 * ---------------------------------------------------------------------- */

const char *ce_version(void)
{
    return CE_VERSION_STRING;
}

/* XYZ (Y = 1) a partir de xy, con el mismo orden de operaciones que
 * colour.xyY_to_XYZ: Y_y = Y / y; X = x * Y_y; Z = (1 - (x + y)) * Y_y. */
static ce_xyz ce_xy_to_xyz(double x, double y)
{
    const double y_inv = 1.0 / y;
    ce_xyz w;
    w.X = x * y_inv;
    w.Y = 1.0;
    w.Z = (1.0 - (x + y)) * y_inv;
    return w;
}

/* v' = m · v, con m row-major. Suma en orden fijo (izquierda a derecha). */
static void ce_mat3_mul_vec(const double m[9], const double v[3], double out[3])
{
    out[0] = m[0] * v[0] + m[1] * v[1] + m[2] * v[2];
    out[1] = m[3] * v[0] + m[4] * v[1] + m[5] * v[2];
    out[2] = m[6] * v[0] + m[7] * v[1] + m[8] * v[2];
}

/* c = a · b (3x3, row-major). */
static void ce_mat3_mul(const double a[9], const double b[9], double c[9])
{
    int i, j;
    for (i = 0; i < 3; ++i) {
        for (j = 0; j < 3; ++j) {
            c[i * 3 + j] = a[i * 3 + 0] * b[0 * 3 + j]
                         + a[i * 3 + 1] * b[1 * 3 + j]
                         + a[i * 3 + 2] * b[2 * 3 + j];
        }
    }
}

/* Inversa 3x3 por adjunta / determinante. La matriz de Bradford es regular. */
static void ce_mat3_inverse(const double m[9], double inv[9])
{
    const double a = m[0], b = m[1], c = m[2];
    const double d = m[3], e = m[4], f = m[5];
    const double g = m[6], h = m[7], k = m[8];

    const double A = e * k - f * h;
    const double B = -(d * k - f * g);
    const double C = d * h - e * g;
    const double det = a * A + b * B + c * C;
    const double inv_det = 1.0 / det;

    inv[0] = A * inv_det;
    inv[1] = (c * h - b * k) * inv_det;
    inv[2] = (b * f - c * e) * inv_det;
    inv[3] = B * inv_det;
    inv[4] = (a * k - c * g) * inv_det;
    inv[5] = (c * d - a * f) * inv_det;
    inv[6] = C * inv_det;
    inv[7] = (b * g - a * h) * inv_det;
    inv[8] = (a * e - b * d) * inv_det;
}

/* Función f(t) de CIELAB con epsilon/kappa exactos. t = X/Xn etc. */
static double ce_lab_f(double t)
{
    if (t > CE_LAB_EPSILON) {
        return ce_cbrt(t);
    }
    return (CE_LAB_KAPPA * t + 16.0) / 116.0;
}

/* Inversa de ce_lab_f. */
static double ce_lab_f_inv(double ft)
{
    const double ft3 = ft * ft * ft;
    if (ft3 > CE_LAB_EPSILON) {
        return ft3;
    }
    return (116.0 * ft - 16.0) / CE_LAB_KAPPA;
}

static double ce_deg2rad(double deg)
{
    return deg * (CE_PI / 180.0);
}

static double ce_rad2deg(double rad)
{
    return rad * (180.0 / CE_PI);
}

/* x^7 por multiplicaciones (sin pow), determinista entre plataformas. */
static double ce_pow7(double x)
{
    const double x2 = x * x;
    const double x4 = x2 * x2;
    return x4 * x2 * x;
}

/* Ángulo de tono h' en grados dentro de [0, 360). Sharma 2005, ec. (7) y (14):
 * atan2 de cuatro cuadrantes, +360 si es negativo, y h' = 0 si a' = b = 0. */
static double ce_hue_deg(double a, double b)
{
    double h;
    if (a == 0.0 && b == 0.0) {
        return 0.0;
    }
    h = ce_rad2deg(ce_atan2(b, a));
    if (h < 0.0) {
        h += 360.0;
    }
    return h;
}

/* Clamp a [0, 1]; NaN -> 0. */
static double ce_clamp01(double c)
{
    if (!(c > 0.0)) {
        return 0.0;
    }
    if (c > 1.0) {
        return 1.0;
    }
    return c;
}

/* ------------------------------------------------------------------------
 * Curva sRGB
 * ---------------------------------------------------------------------- */

double ce_srgb_decode(double c)
{
    if (c <= CE_SRGB_DECODE_THRESHOLD) {
        return c / 12.92;
    }
    return ce_pow((c + 0.055) / 1.055, 2.4);
}

double ce_srgb_encode(double c)
{
    if (c <= CE_SRGB_ENCODE_THRESHOLD) {
        return 12.92 * c;
    }
    return 1.055 * ce_pow(c, 1.0 / 2.4) - 0.055;
}

/* ------------------------------------------------------------------------
 * sRGB <-> XYZ <-> CIELAB
 * ---------------------------------------------------------------------- */

ce_xyz ce_lab_white(void)
{
    return ce_xy_to_xyz(CE_D65_X, CE_D65_Y);
}

ce_xyz ce_srgb_to_xyz(double r, double g, double b)
{
    double lin[3];
    double out[3];
    ce_xyz xyz;
    lin[0] = ce_srgb_decode(r);
    lin[1] = ce_srgb_decode(g);
    lin[2] = ce_srgb_decode(b);
    ce_mat3_mul_vec(CE_M_RGB_TO_XYZ, lin, out);
    xyz.X = out[0];
    xyz.Y = out[1];
    xyz.Z = out[2];
    return xyz;
}

ce_xyz ce_srgb8_to_xyz(uint8_t r, uint8_t g, uint8_t b)
{
    return ce_srgb_to_xyz((double)r / 255.0, (double)g / 255.0, (double)b / 255.0);
}

ce_lab ce_xyz_to_lab(ce_xyz xyz)
{
    const ce_xyz w = ce_lab_white();
    const double fx = ce_lab_f(xyz.X / w.X);
    const double fy = ce_lab_f(xyz.Y / w.Y);
    const double fz = ce_lab_f(xyz.Z / w.Z);
    ce_lab lab;
    lab.L = 116.0 * fy - 16.0;
    lab.a = 500.0 * (fx - fy);
    lab.b = 200.0 * (fy - fz);
    return lab;
}

ce_xyz ce_lab_to_xyz(ce_lab lab)
{
    const ce_xyz w = ce_lab_white();
    const double fy = (lab.L + 16.0) / 116.0;
    const double fx = lab.a / 500.0 + fy;
    const double fz = fy - lab.b / 200.0;
    ce_xyz xyz;
    xyz.X = ce_lab_f_inv(fx) * w.X;
    /* Para Y se usa L directamente (CIE 015:2004): evita el cubo de fy cuando
     * L está en la zona lineal y hace la inversa exacta. */
    xyz.Y = (lab.L > CE_LAB_KAPPA * CE_LAB_EPSILON) ? fy * fy * fy : lab.L / CE_LAB_KAPPA;
    xyz.Y *= w.Y;
    xyz.Z = ce_lab_f_inv(fz) * w.Z;
    return xyz;
}

ce_lab ce_srgb_to_lab(double r, double g, double b)
{
    return ce_xyz_to_lab(ce_srgb_to_xyz(r, g, b));
}

ce_lab ce_srgb8_to_lab(uint8_t r, uint8_t g, uint8_t b)
{
    return ce_xyz_to_lab(ce_srgb8_to_xyz(r, g, b));
}

void ce_xyz_to_srgb(ce_xyz xyz, double *r, double *g, double *b)
{
    double in[3];
    double lin[3];
    in[0] = xyz.X;
    in[1] = xyz.Y;
    in[2] = xyz.Z;
    ce_mat3_mul_vec(CE_M_XYZ_TO_RGB, in, lin);
    *r = ce_srgb_encode(lin[0]);
    *g = ce_srgb_encode(lin[1]);
    *b = ce_srgb_encode(lin[2]);
}

void ce_lab_to_srgb(ce_lab lab, double *r, double *g, double *b)
{
    ce_xyz_to_srgb(ce_lab_to_xyz(lab), r, g, b);
}

void ce_lab_to_srgb8(ce_lab lab, uint8_t *r, uint8_t *g, uint8_t *b)
{
    double rr, gg, bb;
    ce_lab_to_srgb(lab, &rr, &gg, &bb);
    /* clamp + redondeo half-up; el truncado de [0.5, 255.5] cae en 0..255. */
    *r = (uint8_t)(ce_clamp01(rr) * 255.0 + 0.5);
    *g = (uint8_t)(ce_clamp01(gg) * 255.0 + 0.5);
    *b = (uint8_t)(ce_clamp01(bb) * 255.0 + 0.5);
}

/* ------------------------------------------------------------------------
 * Diferencias de color
 * ---------------------------------------------------------------------- */

double ce_de76(ce_lab lab1, ce_lab lab2)
{
    const double dL = lab1.L - lab2.L;
    const double da = lab1.a - lab2.a;
    const double db = lab1.b - lab2.b;
    return sqrt(dL * dL + da * da + db * db);
}

double ce_de2000(ce_lab lab1, ce_lab lab2)
{
    return ce_de2000_k(lab1, lab2, 1.0, 1.0, 1.0);
}

/* Implementación de CIEDE2000 siguiendo la numeración de ecuaciones de
 * Sharma, Wu y Dalal (2005), "The CIEDE2000 color-difference formula:
 * implementation notes, supplementary test data, and mathematical
 * observations", Color Res. Appl. 30(1):21-30. */
double ce_de2000_k(ce_lab lab1, ce_lab lab2, double kL, double kC, double kH)
{
    /* Precondición documentada: factores > 0. Un valor no positivo o NaN se trata
     * como 1.0 para no dividir por cero (!(k > 0) también captura NaN). */
    if (!(kL > 0.0)) kL = 1.0;
    if (!(kC > 0.0)) kC = 1.0;
    if (!(kH > 0.0)) kH = 1.0;

    const double L1 = lab1.L, a1 = lab1.a, b1 = lab1.b;
    const double L2 = lab2.L, a2 = lab2.a, b2 = lab2.b;

    /* (2)-(3): croma ab y su media. */
    const double C1ab = sqrt(a1 * a1 + b1 * b1);
    const double C2ab = sqrt(a2 * a2 + b2 * b2);
    const double Cab_bar = (C1ab + C2ab) / 2.0;

    /* (4): G. */
    const double Cab_bar7 = ce_pow7(Cab_bar);
    const double G = 0.5 * (1.0 - sqrt(Cab_bar7 / (Cab_bar7 + CE_POW25_7)));

    /* (5)-(7): a', C', h'. */
    const double a1p = (1.0 + G) * a1;
    const double a2p = (1.0 + G) * a2;
    const double C1p = sqrt(a1p * a1p + b1 * b1);
    const double C2p = sqrt(a2p * a2p + b2 * b2);
    const double h1p = ce_hue_deg(a1p, b1);
    const double h2p = ce_hue_deg(a2p, b2);

    /* (8)-(9): ΔL' y ΔC' con signo. */
    const double dLp = L2 - L1;
    const double dCp = C2p - C1p;

    /* (10): Δh' con los casos de croma nula y de |Δ| > 180. */
    const double C12 = C1p * C2p;
    double dhp;
    if (C12 == 0.0) {
        dhp = 0.0;
    } else {
        dhp = h2p - h1p;
        if (dhp > 180.0) {
            dhp -= 360.0;
        } else if (dhp < -180.0) {
            dhp += 360.0;
        }
    }

    /* (11): ΔH' con signo. */
    const double dHp = 2.0 * sqrt(C12) * ce_sin(ce_deg2rad(dhp / 2.0));

    /* (12)-(14): medias L̄', C̄', h̄'. */
    const double Lp_bar = (L1 + L2) / 2.0;
    const double Cp_bar = (C1p + C2p) / 2.0;
    double hp_bar;
    if (C12 == 0.0) {
        hp_bar = h1p + h2p;
    } else {
        const double hsum = h1p + h2p;
        if (fabs(h1p - h2p) <= 180.0) {
            hp_bar = hsum / 2.0;
        } else if (hsum < 360.0) {
            hp_bar = (hsum + 360.0) / 2.0;
        } else {
            hp_bar = (hsum - 360.0) / 2.0;
        }
    }

    /* (15): T. */
    const double T = 1.0
                   - 0.17 * ce_cos(ce_deg2rad(hp_bar - 30.0))
                   + 0.24 * ce_cos(ce_deg2rad(2.0 * hp_bar))
                   + 0.32 * ce_cos(ce_deg2rad(3.0 * hp_bar + 6.0))
                   - 0.20 * ce_cos(ce_deg2rad(4.0 * hp_bar - 63.0));

    /* (16): Δθ. */
    const double dtheta_arg = (hp_bar - 275.0) / 25.0;
    const double dtheta = 30.0 * ce_exp(-(dtheta_arg * dtheta_arg));

    /* (17): R_C. */
    const double Cp_bar7 = ce_pow7(Cp_bar);
    const double RC = 2.0 * sqrt(Cp_bar7 / (Cp_bar7 + CE_POW25_7));

    /* (18)-(20): S_L, S_C, S_H. */
    const double Lp_bar_m50 = Lp_bar - 50.0;
    const double Lp_bar_m50_sq = Lp_bar_m50 * Lp_bar_m50;
    const double SL = 1.0 + (0.015 * Lp_bar_m50_sq) / sqrt(20.0 + Lp_bar_m50_sq);
    const double SC = 1.0 + 0.045 * Cp_bar;
    const double SH = 1.0 + 0.015 * Cp_bar * T;

    /* (21): R_T. */
    const double RT = -ce_sin(ce_deg2rad(2.0 * dtheta)) * RC;

    /* (22): ΔE00. */
    {
        const double tL = dLp / (kL * SL);
        const double tC = dCp / (kC * SC);
        const double tH = dHp / (kH * SH);
        return sqrt(tL * tL + tC * tC + tH * tH + RT * tC * tH);
    }
}

/* ------------------------------------------------------------------------
 * Adaptación cromática (Bradford)
 * ---------------------------------------------------------------------- */

ce_xyz ce_illuminant_white(ce_illuminant illuminant)
{
    int idx = (int)illuminant;
    if (idx < 0 || idx >= (int)CE_ILL_COUNT) {
        idx = (int)CE_ILL_D65;
    }
    return ce_xy_to_xyz(CE_ILLUMINANT_XY[idx][0], CE_ILLUMINANT_XY[idx][1]);
}

void ce_bradford_matrix(ce_illuminant from, ce_illuminant to, double m[9])
{
    const ce_xyz ws = ce_illuminant_white(from);
    const ce_xyz wd = ce_illuminant_white(to);
    double src[3], dst[3];
    double rgb_s[3], rgb_d[3];
    double cat_inv[9];
    double scaled[9];
    int i, j;

    src[0] = ws.X; src[1] = ws.Y; src[2] = ws.Z;
    dst[0] = wd.X; dst[1] = wd.Y; dst[2] = wd.Z;

    /* Respuestas de cono (Bradford) de ambos blancos. */
    ce_mat3_mul_vec(CE_CAT_BRADFORD, src, rgb_s);
    ce_mat3_mul_vec(CE_CAT_BRADFORD, dst, rgb_d);

    /* inv(CAT) · diag(rgb_d / rgb_s): escala la columna j de inv(CAT). */
    ce_mat3_inverse(CE_CAT_BRADFORD, cat_inv);
    for (i = 0; i < 3; ++i) {
        for (j = 0; j < 3; ++j) {
            scaled[i * 3 + j] = cat_inv[i * 3 + j] * (rgb_d[j] / rgb_s[j]);
        }
    }

    /* · CAT */
    ce_mat3_mul(scaled, CE_CAT_BRADFORD, m);
}

ce_xyz ce_xyz_adapt(ce_xyz xyz, const double m[9])
{
    double in[3];
    double out[3];
    ce_xyz res;
    in[0] = xyz.X;
    in[1] = xyz.Y;
    in[2] = xyz.Z;
    ce_mat3_mul_vec(m, in, out);
    res.X = out[0];
    res.Y = out[1];
    res.Z = out[2];
    return res;
}
