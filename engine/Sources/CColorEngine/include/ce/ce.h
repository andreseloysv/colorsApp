/*
 * ce.h — API pública del motor de color de colorsApp (capas 1 y 2; capa 3 declarada).
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

#include <stddef.h>
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

/* ========================================================================
 * Capa 2: contexto, imagen y extracción de paleta (ce_ctx.c, ce_image.c,
 * ce_palette.c). Capa 3 (ce_match / ce_analyze): declarada, stubs hasta F3.
 *
 * Reglas comunes: el motor no reserva memoria (el contexto lo aporta el
 * llamante), no tiene estáticos mutables ni RNG, nunca aborta y nunca lee
 * fuera del buffer de entrada. Todos los errores son códigos negativos de
 * `ce_status`; un resultado >= 0 es éxito.
 * ====================================================================== */

/** Códigos de error (negativos). CE_OK = 0. */
typedef enum ce_status {
    CE_OK = 0,
    CE_ERR_ARG = -1,             /**< puntero nulo obligatorio, o `cap` < 1 */
    CE_ERR_CTX = -2,             /**< contexto no inicializado con ce_ctx_init */
    CE_ERR_DIMS = -3,            /**< width/height fuera de [1, CE_IMAGE_MAX_SIDE] */
    CE_ERR_STRIDE = -4,          /**< stride_bytes < width*bpp o height*stride > INT_MAX */
    CE_ERR_FORMAT = -5,          /**< ce_pixel_format desconocido */
    CE_ERR_OPTS = -6,            /**< opción fuera de rango o NaN (ver ce_palette_opts) */
    CE_ERR_NOT_IMPLEMENTED = -7  /**< ce_match / ce_analyze hasta la fase 3 */
} ce_status;

/** Lado máximo (píxeles) de la imagen de entrada. */
#define CE_IMAGE_MAX_SIDE 16384
/** Lado máximo de la imagen reducida que guarda el contexto (opts.max_side <= 256). */
#define CE_PALETTE_MAX_SIDE 256
/** Máximo de centros iniciales (opts.k_init <= 64). */
#define CE_PALETTE_K_MAX 64
/** Máximo de swatches devueltos (opts.max_colors <= 8; == capacidad de ce_result). */
#define CE_PALETTE_MAX_COLORS 8

/** Contexto de trabajo opaco: memoria reservada por el llamante (ce_ctx_size,
 *  ce_ctx_init). Un contexto por tarea; no es compartible entre hilos. */
typedef struct ce_ctx ce_ctx;

/** Formato de píxel de entrada: 8 bits por canal, sRGB, alpha NO
 *  premultiplicada e ignorada. RGBA8 y RGBX8 ocupan 4 bytes por píxel
 *  (R,G,B,X); RGB8 ocupa 3. */
typedef enum ce_pixel_format {
    CE_RGBA8 = 0,
    CE_RGBX8 = 1,
    CE_RGB8 = 2
} ce_pixel_format;

/** Imagen de entrada (buffer del llamante, solo lectura).
 *  - `stride_bytes` >= width * bytes_por_pixel; height * stride_bytes <= INT_MAX.
 *  - `mask` opcional (NULL = sin máscara): width*height bytes, empaquetados sin
 *    stride, 0..255; multiplica el peso del píxel (0 anula, 255 = peso pleno). */
typedef struct ce_image {
    const uint8_t *pixels;
    int width;
    int height;
    int stride_bytes;
    ce_pixel_format fmt;
    const uint8_t *mask;
} ce_image;

/** Swatch de la paleta: Lab (D65), su sRGB8 (Lab -> sRGB8 con clamp) y su peso
 *  relativo. La suma de `weight` de una paleta es 1 (+- 1e-12). */
typedef struct ce_swatch {
    ce_lab lab;
    uint8_t rgb[3];
    double weight;
} ce_swatch;

/** Opciones de extracción (ce_palette_opts_default rellena los valores por
 *  defecto). Rangos válidos (fuera de ellos: CE_ERR_OPTS):
 *  - k_init      1..CE_PALETTE_K_MAX (6): cajas MMCQ = centros iniciales de Lloyd.
 *  - max_iters   0..1000 (20): iteraciones de Lloyd (0 = solo MMCQ).
 *  - max_colors  1..CE_PALETTE_MAX_COLORS (5): swatches devueltos como máximo.
 *  - max_side    1..CE_PALETTE_MAX_SIDE (256): lado mayor tras el box-downscale.
 *  - center_sigma (0.35): sigma = center_sigma * min(w, h) de la imagen
 *    REDUCIDA, en píxeles; <= 0 (o +inf) => peso uniforme 1.0 exacto. NaN => error.
 *  - merge_de   (5.0): se fusionan iterativamente los dos centros más próximos
 *    mientras su ΔE00 < merge_de; <= 0 => sin fusión. NaN => error.
 *  - min_weight (0.05): se descartan los centros con peso relativo < min_weight
 *    (siempre se conserva el más pesado); <= 0 => sin descarte. NaN => error.
 *  - skin_rule  (0): != 0 anula el peso de los píxeles de piel según Chai y
 *    Ngan (YCbCr JFIF: 77 <= Cb <= 127 y 133 <= Cr <= 173). */
typedef struct ce_palette_opts {
    int k_init;
    int max_iters;
    int max_colors;
    int max_side;
    double center_sigma;
    double merge_de;
    double min_weight;
    int skin_rule;
} ce_palette_opts;

/** Opciones del match (fase 3). kL, kC, kH de ΔE00; coverage_lambda pondera
 *  la cobertura de la combinación; ambiguous_gap marca `ambiguous` cuando
 *  score[1] - score[0] < gap. Valores iniciales: 1, 1, 1, 0.5, 1.0. */
typedef struct ce_match_opts {
    double kL;
    double kC;
    double kH;
    double coverage_lambda;
    double ambiguous_gap;
} ce_match_opts;

/** Un candidato del match: id de combinación (1..348) y su score (menor = mejor). */
typedef struct ce_hit {
    uint16_t combo_id;
    double score;
} ce_hit;

/** Resultado completo de ce_analyze. */
typedef struct ce_result {
    ce_swatch swatches[CE_PALETTE_MAX_COLORS];
    int n_swatches;
    ce_hit hits[10];
    int n_hits;
    int ambiguous;
} ce_result;

/** Bytes que necesita un contexto (múltiplo de 16; <= 2 MiB, acotado por
 *  test_ctx_size_budget). */
size_t ce_ctx_size(void);

/** Inicializa un contexto en `mem` (alineado a 16 bytes, `size` >=
 *  ce_ctx_size()). Construye la caché Lab del diccionario. Devuelve NULL si
 *  `mem` es NULL, no está alineado a 16 o `size` es insuficiente. */
ce_ctx *ce_ctx_init(void *mem, size_t size);

/** Opciones por defecto: k_init 6, max_iters 20, max_colors 5, max_side 256,
 *  center_sigma 0.35, merge_de 5.0, min_weight 0.05, skin_rule 0. */
void ce_palette_opts_default(ce_palette_opts *o);

/** Opciones de match por defecto (ver ce_match_opts). */
void ce_match_opts_default(ce_match_opts *o);

/** Dimensiones de la imagen reducida: factor entero f = ceil(max(w,h)/max_side),
 *  rw = ceil(w/f), rh = ceil(h/f). CE_ERR_DIMS si algún argumento es < 1. */
int ce_reduced_dims(int width, int height, int max_side, int *rw, int *rh);

/**
 * Extrae la paleta dominante de `img` (algoritmo determinista, sin RNG):
 *  1. box-downscale entero hasta que el lado mayor <= max_side (media entera
 *     redondeada por bloque; los bloques parciales del borde promedian los
 *     píxeles existentes); la máscara se reduce igual.
 *  2. peso por píxel = gaussiana al centro (o 1.0 exacto si uniforme) x máscara
 *     x regla de piel opcional. La máscara entra como factor entero 0..255
 *     (equivale a mask/255 salvo una escala global que la normalización final
 *     elimina; así las sumas son exactas en modo uniforme).
 *  3. histograma de 5 bits por canal (32768 bins) acumulado en double; el
 *     color del bin es la media ponderada (sin cuantizar) y su Lab se calcula
 *     con ce_srgb_to_lab. En modo uniforme sin máscara las sumas son enteras
 *     y exactas: el resultado es bit-idéntico bajo barajado de píxeles.
 *  4. median cut modificado (Heckbert/Leptonica: el 85 % de los cortes por
 *     población, el resto por población x volumen; eje más largo, corte a
 *     partir de la mediana de población) hasta k_init cajas.
 *  5. Lloyd ponderado en Lab (asignación por ΔE76 al cuadrado, empates al
 *     centro de índice menor, bins en orden de índice) <= max_iters.
 *  6. fusión del par de centros más próximo mientras ΔE00 < merge_de;
 *     descarte de centros con peso < min_weight (el más pesado siempre queda).
 *  7. orden por peso descendente (desempate por L, a, b, índice), recorte a
 *     min(max_colors, cap) y renormalización a suma 1.
 * Si el peso total es 0 (p. ej. máscara toda a 0) devuelve 1 swatch con el
 * color medio (sin ponderar) de la imagen reducida y weight 1.
 *
 * `o` NULL usa ce_palette_opts_default. Escribe como máximo min(max_colors, cap)
 * swatches en `out` y devuelve su número (>= 1), o un código negativo
 * (CE_ERR_ARG, CE_ERR_CTX, CE_ERR_DIMS, CE_ERR_FORMAT, CE_ERR_STRIDE,
 * CE_ERR_OPTS) sin escribir nada.
 */
int ce_palette_extract(ce_ctx *ctx, const ce_image *img, const ce_palette_opts *o,
                       ce_swatch *out, int cap);

/** Fase 3. Hoy devuelve CE_ERR_NOT_IMPLEMENTED sin tocar las salidas. */
int ce_match(const ce_ctx *ctx, const ce_swatch *sw, int n, const ce_match_opts *o,
             ce_hit *out, int top_k, int *ambiguous);

/** Fase 3. Hoy devuelve CE_ERR_NOT_IMPLEMENTED sin tocar las salidas. */
int ce_analyze(ce_ctx *ctx, const ce_image *img, const ce_palette_opts *po,
               const ce_match_opts *mo, ce_result *out);

/** Índice del color del diccionario más cercano a `lab` por ΔE00 (empates al
 *  índice menor); escribe la distancia en `de` si no es NULL. Sin contexto
 *  (159 llamadas a ce_dict_color_lab). Devuelve -1 (y de = NaN) si `lab`
 *  contiene NaN. */
int ce_dict_nearest_color(ce_lab lab, double *de);

/** FNV-1a de 64 bits sobre los bytes de (L, a, b, weight) de cada swatch, en
 *  orden. Solo para comparar ejecuciones en la MISMA plataforma (los bits de
 *  libm difieren entre nativo y WASM). */
uint64_t ce_swatch_hash(const ce_swatch *sw, int n);

/** FNV-1a de un ce_result: ce_swatch_hash de sus swatches, luego (combo_id,
 *  score) de cada hit y `ambiguous`. Misma plataforma solamente. */
uint64_t ce_result_hash(const ce_result *r);

#ifdef __cplusplus
}
#endif

#endif /* CE_CE_H */
