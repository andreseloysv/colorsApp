/*
 * ce.h — API pública de la capa 1 del motor de color de colorsApp.
 *
 * Matemática de color pura en C11: sin I/O, sin reserva dinámica de memoria,
 * sin dependencias más allá de <math.h>. Todo en double. El mismo código se
 * compila a nativo (iOS/macOS) y a WebAssembly.
 *
 * Convenciones:
 *   - sRGB "codificado" = valores gamma sRGB en [0, 1] (IEC 61966-2-1).
 *   - sRGB8 = enteros 0..255; se normalizan como v / 255.0.
 *   - XYZ con Y del blanco = 1 (no 100). CIELAB con L en [0, 100].
 *   - Las matrices 3x3 se pasan como double[9] en orden de filas (row-major):
 *     m[0..2] es la primera fila.
 *
 * Decisiones numéricas (ver engine/README.md):
 *   - La matriz RGB->XYZ es la DERIVADA de los primarios sRGB (0.64,0.33),
 *     (0.30,0.60), (0.15,0.06) y del blanco D65 xy (0.3127, 0.3290), no la de
 *     cuatro decimales de la norma. Así (255,255,255) -> L = 100, a = b = 0.
 *   - CIELAB con epsilon = 216/24389 y kappa = 24389/27 exactos.
 *   - ΔE2000 según Sharma, Wu y Dalal (2005) con todas las correcciones de
 *     hue (h' en [0,360), Δh' y h̄' con los casos de C1'C2' = 0 y |Δh'| > 180).
 *   - Bradford: M = inv(CAT) · diag(RGB_dst / RGB_src) · CAT.
 */
#ifndef CE_CE_H
#define CE_CE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Versión del motor (semver). */
#define CE_VERSION_STRING "0.1.0"

/** Color en CIELAB (D65). L en [0, 100]; a y b sin acotar. */
typedef struct ce_lab {
    double L;
    double a;
    double b;
} ce_lab;

/** Tristímulos CIE XYZ con Y del blanco = 1. */
typedef struct ce_xyz {
    double X;
    double Y;
    double Z;
} ce_xyz;

/**
 * Iluminantes estándar (observador CIE 1931 2°, xy de CIE 015:2004):
 *   A   (0.44758, 0.40745)   incandescente
 *   D50 (0.34570, 0.35850)   luz de día horizonte / ICC
 *   D65 (0.31270, 0.32900)   luz de día mediodía / sRGB
 *   D75 (0.29903, 0.31488)   luz de día norte
 *   F2  (0.37210, 0.37510)   fluorescente blanco frío
 */
typedef enum ce_illuminant {
    CE_ILL_A = 0,
    CE_ILL_D50 = 1,
    CE_ILL_D65 = 2,
    CE_ILL_D75 = 3,
    CE_ILL_F2 = 4,
    CE_ILL_COUNT = 5
} ce_illuminant;

/** Cadena de versión del motor (estática, no liberar). */
const char *ce_version(void);

/* ------------------------------------------------------------------------
 * Funciones de transferencia sRGB (IEC 61966-2-1)
 * ---------------------------------------------------------------------- */

/** Decodifica un canal sRGB (codificado, 0..1) a lineal: c <= 0.04045 ?
 *  c/12.92 : ((c+0.055)/1.055)^2.4. No hace clamp. */
double ce_srgb_decode(double c);

/** Codifica un canal lineal a sRGB: c <= 0.0031308 ? 12.92c :
 *  1.055 c^(1/2.4) - 0.055. No hace clamp (valores negativos siguen la rama
 *  lineal; no produce NaN para entradas finitas). */
double ce_srgb_encode(double c);

/* ------------------------------------------------------------------------
 * sRGB <-> XYZ <-> CIELAB
 * ---------------------------------------------------------------------- */

/** sRGB codificado (0..1) -> XYZ (D65). */
ce_xyz ce_srgb_to_xyz(double r, double g, double b);

/** sRGB8 (0..255) -> XYZ (D65). */
ce_xyz ce_srgb8_to_xyz(uint8_t r, uint8_t g, uint8_t b);

/** sRGB codificado (0..1) -> CIELAB (D65). */
ce_lab ce_srgb_to_lab(double r, double g, double b);

/** sRGB8 (0..255) -> CIELAB (D65). */
ce_lab ce_srgb8_to_lab(uint8_t r, uint8_t g, uint8_t b);

/** XYZ (D65) -> CIELAB. */
ce_lab ce_xyz_to_lab(ce_xyz xyz);

/** CIELAB -> XYZ (D65). Inversa exacta de ce_xyz_to_lab. */
ce_xyz ce_lab_to_xyz(ce_lab lab);

/** XYZ (D65) -> sRGB codificado. Sin clamp: fuera de gamut puede devolver
 *  valores < 0 o > 1. */
void ce_xyz_to_srgb(ce_xyz xyz, double *r, double *g, double *b);

/** CIELAB -> sRGB codificado. Sin clamp (ver ce_xyz_to_srgb). */
void ce_lab_to_srgb(ce_lab lab, double *r, double *g, double *b);

/** CIELAB -> sRGB8: clamp a [0, 1] y redondeo al entero más cercano
 *  (mitades hacia arriba). NaN se trata como 0. */
void ce_lab_to_srgb8(ce_lab lab, uint8_t *r, uint8_t *g, uint8_t *b);

/** Blanco de referencia del Lab (D65, Y = 1): Xn = x/y, Yn = 1, Zn = (1-x-y)/y. */
ce_xyz ce_lab_white(void);

/* ------------------------------------------------------------------------
 * Diferencias de color
 * ---------------------------------------------------------------------- */

/** ΔE*ab (CIE 1976): distancia euclídea en Lab. */
double ce_de76(ce_lab lab1, ce_lab lab2);

/** ΔE00 (CIEDE2000, Sharma/Wu/Dalal 2005) con kL = kC = kH = 1. Simétrica. */
double ce_de2000(ce_lab lab1, ce_lab lab2);

/** ΔE00 con factores paramétricos kL, kC, kH (p. ej. kL = 2 para textiles).
 *  Precondición: kL, kC, kH > 0. Un factor no positivo o NaN se trata como 1.0
 *  (nunca divide por cero). */
double ce_de2000_k(ce_lab lab1, ce_lab lab2, double kL, double kC, double kH);

/* ------------------------------------------------------------------------
 * Adaptación cromática (Bradford)
 * ---------------------------------------------------------------------- */

/** XYZ (Y = 1) del blanco de un iluminante. Fuera de rango devuelve D65. */
ce_xyz ce_illuminant_white(ce_illuminant illuminant);

/** Matriz 3x3 (row-major en m[9]) de adaptación de Bradford de `from` a `to`:
 *  M = inv(CAT_BRADFORD) · diag(RGB_to / RGB_from) · CAT_BRADFORD. */
void ce_bradford_matrix(ce_illuminant from, ce_illuminant to, double m[9]);

/** Aplica una matriz 3x3 (row-major) a XYZ: XYZ' = m · XYZ. */
ce_xyz ce_xyz_adapt(ce_xyz xyz, const double m[9]);

/* ------------------------------------------------------------------------
 * Diccionario de Sanzo Wada embebido (ce_dict.c + ce_dict_data.h generado)
 *
 * Solo sRGB8 en las tablas; el Lab de cada color se calcula con
 * ce_srgb8_to_lab, la misma función que procesa la foto. Los índices de color
 * van de 0 a ce_dict_num_colors()-1 y los ids de combinación (número de
 * lámina) de 1 a ce_dict_num_combos() sin huecos. Ninguna función hace I/O ni
 * reserva memoria; las tablas son `static const`.
 * ---------------------------------------------------------------------- */

/** Capacidad de `colors` en ce_dict_combo (reserva para el Vol. 2: 2..7 colores). */
#define CE_DICT_COMBO_MAX 7

/** Relleno de las posiciones de `colors` a partir de `size`. */
#define CE_DICT_NO_COLOR 0xFF

/** Versión del diccionario: sha256 corto (12 hex) del JSON canónico de
 *  colores + combinaciones de data/wada/dictionary.json tras aplicar
 *  overrides. La app debe comprobar que coincide con el `dict_version` del
 *  JSON que lleva en el bundle. Cadena estática, no liberar. */
const char *ce_dict_version(void);

/** Número de colores del diccionario (159 en el Vol. 1). */
int ce_dict_num_colors(void);

/** Número de combinaciones (348 en el Vol. 1). */
int ce_dict_num_combos(void);

/** sRGB8 del color `index`. Devuelve 0 y escribe `rgb` (si no es NULL), o -1
 *  si `index` está fuera de rango (no escribe nada). */
int ce_dict_color_rgb(int index, uint8_t rgb[3]);

/** Nombre en inglés del color (nomenclatura de Ridgway, tal cual en el fuente).
 *  Cadena estática; NULL si `index` está fuera de rango. */
const char *ce_dict_color_name(int index);

/** CIELAB (D65) del color, calculado con ce_srgb8_to_lab. Fuera de rango
 *  devuelve NaN en las tres componentes. */
ce_lab ce_dict_color_lab(int index);

/** Combinación `id` (1..ce_dict_num_combos()). Devuelve 0 y escribe `size`
 *  (2..CE_DICT_COMBO_MAX) y `colors` (índices ascendentes; posiciones >= size
 *  a CE_DICT_NO_COLOR) cuando no son NULL; -1 si la combinación no existe. */
int ce_dict_combo(int id, uint8_t *size, uint8_t colors[CE_DICT_COMBO_MAX]);

#ifdef __cplusplus
}
#endif

#endif /* CE_CE_H */
