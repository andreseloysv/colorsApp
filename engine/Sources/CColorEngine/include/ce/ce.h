/*
 * ce.h — API pública del motor de color de colorsApp (capas 1, 2 y 3, máscaras
 * de ropa y piel, y capas de depuración).
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
 * libm portable (ce_libm.c): los mismos bits en nativo y en WASM
 *
 * El motor no llama a las funciones trascendentes de <math.h> (que difieren
 * entre la libm de Apple y la de musl/Emscripten en el último bit) sino a
 * estas copias de musl 1.2.6 compiladas con el propio motor, sin FMA. Con
 * FP_CONTRACT OFF todo lo demás son +, −, ×, ÷, sqrt y bits IEEE 754, así que
 * Lab, ΔE00, pesos, scores y hashes son bit a bit idénticos en Apple
 * arm64/x86_64 y WASM. Semántica de C11 (NaN, ±inf, ±0, subnormales);
 * error < 1 ulp (pow/exp 0,54 ulp; cbrt 0,67 ulp; sin/cos/atan2 ~0,5-1 ulp),
 * así que los resultados exactamente representables (2^10, cbrt(27), exp(0))
 * salen exactos.
 * ---------------------------------------------------------------------- */

/** Raíz cúbica (musl cbrt). */
double ce_cbrt(double x);

/** x^y (musl pow; camino sin FMA). */
double ce_pow(double x, double y);

/** e^x (musl exp). */
double ce_exp(double x);

/** atan2(y, x) en radianes, (-pi, pi] (musl atan2). */
double ce_atan2(double y, double x);

/** Seno y coseno en radianes, con reducción de argumento exacta para
 *  cualquier |x| finito (musl sin/cos). */
double ce_sin(double x);
double ce_cos(double x);

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
 * ce_palette.c). Capa 3: match contra el diccionario (ce_match.c).
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
    CE_ERR_OPTS = -6,            /**< opción fuera de rango o NaN (ce_palette_opts, ce_match_opts) */
    CE_ERR_NOT_IMPLEMENTED = -7, /**< reservado (ninguna función lo devuelve desde la fase 3) */
    CE_ERR_POSE = -8,            /**< ce_mask_clothing_regions: faltan hombros o caderas (ni por
                                      simetría) o la pose es degenerada; la máscara no se toca */
    CE_ERR_SKIN_SAMPLES = -9     /**< ce_skin_model_fit: < CE_SKIN_MIN_SAMPLES muestras de piel;
                                      ce_mask_exclude_skin: modelo con n < CE_SKIN_MIN_SAMPLES */
} ce_status;

/** Lado máximo (píxeles) de la imagen de entrada. */
#define CE_IMAGE_MAX_SIDE 16384
/** Lado máximo de la imagen reducida que guarda el contexto (opts.max_side <= 256). */
#define CE_PALETTE_MAX_SIDE 256
/** Máximo de centros iniciales (opts.k_init <= 64). */
#define CE_PALETTE_K_MAX 64
/** Máximo de swatches devueltos (opts.max_colors <= 8; == capacidad de ce_result). */
#define CE_PALETTE_MAX_COLORS 8
/** Máximo de candidatos del match (top_k <= 10; == capacidad de ce_result.hits). */
#define CE_MATCH_MAX_HITS 10

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
 *    Ngan (YCbCr JFIF: 77 <= Cb <= 127 y 133 <= Cr <= 173).
 *  - merge_light_de (0.0, EXPERIMENTO desactivado por defecto): tras la fusión
 *    por merge_de, fusiona iterativamente el par de centros más próximo
 *    mientras su ΔE00 con kL = CE_PALETTE_LIGHT_MERGE_KL (kC = kH = 1) sea
 *    < merge_light_de: tonos del mismo color que difieren sobre todo en
 *    luminosidad (sombras de una prenda) cuentan como un solo swatch. <= 0 =>
 *    sin esta fusión (resultado bit a bit igual que sin el campo). NaN => error.
 *    Medido en L2/L3 y en el caso real del pantalón rosa (engine/BENCHLOG.md);
 *    no se activa por defecto. Campo añadido al final del struct. */
typedef struct ce_palette_opts {
    int k_init;
    int max_iters;
    int max_colors;
    int max_side;
    double center_sigma;
    double merge_de;
    double min_weight;
    int skin_rule;
    double merge_light_de;
} ce_palette_opts;

/** kL de ΔE00 de la fusión de sombras (ce_palette_opts.merge_light_de): una
 *  diferencia de L* pesa un tercio frente a croma y tono. */
#define CE_PALETTE_LIGHT_MERGE_KL 3.0

/** Paso de la rejilla de exposición de ce_match (EV) y cota de exposure_ev_max. */
#define CE_MATCH_EV_STEP 0.5
#define CE_MATCH_EV_MAX_LIMIT 4.0

/** Opciones del match (ce_match_opts_default: kL 1, kC 1, kH 1,
 *  coverage_lambda 1.0, ambiguous_gap 1.0, exposure_ev_max 1.0,
 *  exposure_penalty 2.0, illuminant_search 0, illuminant_penalty 2.0). Las
 *  opciones reales deben ser finitas (NaN o ±inf => CE_ERR_OPTS):
 *  - kL, kC, kH: factores paramétricos de ΔE00 (<= 0 se trata como 1.0, como
 *    en ce_de2000_k; kL = 2 es el modo "textiles").
 *  - coverage_lambda (λ >= 0; negativo => CE_ERR_OPTS): peso del término de
 *    cobertura, ver ce_match. λ = 0 puntúa solo el ajuste de la paleta.
 *  - ambiguous_gap: `ambiguous` = 1 cuando hay >= 2 hits y
 *    score[1] - score[0] < gap; <= 0 => nunca ambiguo.
 *  - exposure_ev_max (en [0, CE_MATCH_EV_MAX_LIMIT]; fuera => CE_ERR_OPTS):
 *    hipótesis de exposición k · CE_MATCH_EV_STEP EV con |k · paso| <= máx
 *    (ganancia 2^EV en XYZ lineal aplicada a los swatches); 0 = solo la
 *    identidad. exposure_penalty (>= 0): ΔE añadido por EV de desviación.
 *  - illuminant_search (0 o 1; otro => CE_ERR_OPTS; por defecto 0 desde
 *    2026-09-15, ADR-009): 1 añade las hipótesis "la foto se tomó bajo A, D50,
 *    D75 o F2 sin balance de blancos" (Bradford X -> D65 sobre los swatches),
 *    combinadas con las de exposición. Las fotos de un teléfono ya llegan con
 *    balance de blancos: compensar una luz inexistente gira tonos (caso real:
 *    rosa palo + negro -> Nº 067 azul), así que queda como opción explícita.
 *    illuminant_penalty (>= 0): ΔE añadido a cada hipótesis con X != D65.
 *  Con exposure_ev_max = 0 e illuminant_search = 0 el score es exactamente el
 *  de la fase 3 (match v0). Calibrado en L3 (ver engine/README.md). */
typedef struct ce_match_opts {
    double kL;
    double kC;
    double kH;
    double coverage_lambda;
    double ambiguous_gap;
    double exposure_ev_max;
    double exposure_penalty;
    int illuminant_search;
    double illuminant_penalty;
} ce_match_opts;

/** Un candidato del match: id de combinación (1..348) y su score (menor = mejor, >= 0). */
typedef struct ce_hit {
    uint16_t combo_id;
    double score;
} ce_hit;

/** Resultado completo de ce_analyze: paleta (n_swatches >= 1), los
 *  CE_MATCH_MAX_HITS mejores candidatos (n_hits) y `ambiguous`. Las posiciones
 *  no usadas quedan a cero. */
typedef struct ce_result {
    ce_swatch swatches[CE_PALETTE_MAX_COLORS];
    int n_swatches;
    ce_hit hits[CE_MATCH_MAX_HITS];
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
 *  center_sigma 0.35, merge_de 5.0, min_weight 0.05, skin_rule 0,
 *  merge_light_de 0.0 (fusión de sombras desactivada). */
void ce_palette_opts_default(ce_palette_opts *o);

/** Opciones de match por defecto: kL 1, kC 1, kH 1, coverage_lambda 1.0,
 *  ambiguous_gap 1.0, exposure_ev_max 1.0, exposure_penalty 2.0,
 *  illuminant_search 0, illuminant_penalty 2.0 (ver ce_match_opts; la
 *  hipótesis de iluminante sigue disponible con illuminant_search = 1). */
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
 *  6. fusión del par de centros más próximo mientras ΔE00 < merge_de; si
 *     merge_light_de > 0, fusión de sombras (ΔE00 con kL =
 *     CE_PALETTE_LIGHT_MERGE_KL < merge_light_de); descarte de centros con
 *     peso < min_weight (el más pesado siempre queda).
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

/**
 * Capa 3: puntúa las 348 combinaciones del diccionario (sin poda) frente a
 * los `n` swatches `sw` (1..CE_PALETTE_MAX_COLORS; Lab finito, peso finito
 * >= 0, se usan tal cual: la paleta ya suma 1) y escribe en `out` los `top_k`
 * (1..CE_MATCH_MAX_HITS) mejores. Score de una combinación C = {c_j} bajo una
 * hipótesis de adaptación h (ganancia de exposición 2^EV en XYZ lineal y/o
 * Bradford X -> D65, aplicadas a los swatches; ver ce_match_opts):
 *
 *   score_h = Σ_i w_i · min_j ΔE00(h(s_i), c_j) + λ · (1/|C|) · Σ_j min_i ΔE00(c_j, h(s_i))
 *           + exposure_penalty · |EV| + illuminant_penalty · [X != D65]
 *   score   = min_h score_h        (la identidad siempre está y va primero)
 *
 * con ΔE00 = ce_de2000_k(kL, kC, kH) sobre la caché Lab del contexto y
 * λ = coverage_lambda. Con exposure_ev_max = 0 e illuminant_search = 0 queda
 * la fórmula de la fase 3 (match v0), bit a bit. Menor es mejor; orden por
 * score ascendente y desempate por id ascendente (comparación exacta de
 * doubles; con ce_libm.c los scores son bit a bit idénticos en nativo y WASM).
 * Si `ambiguous` no es NULL recibe 1 cuando hay >= 2 hits y out[1].score -
 * out[0].score < ambiguous_gap, 0 en otro caso. `o` NULL usa
 * ce_match_opts_default.
 *
 * Devuelve el número de hits escritos (== top_k, porque hay 348 candidatos) o
 * un código negativo sin escribir nada: CE_ERR_ARG (punteros nulos, n fuera
 * de 1..8, top_k fuera de 1..10, Lab o peso no finito o peso negativo),
 * CE_ERR_CTX, CE_ERR_OPTS (opción NaN/±inf, λ < 0, exposure_ev_max fuera de
 * [0, CE_MATCH_EV_MAX_LIMIT], penalización < 0, illuminant_search != 0/1).
 * Nunca aborta.
 */
int ce_match(const ce_ctx *ctx, const ce_swatch *sw, int n, const ce_match_opts *o,
             ce_hit *out, int top_k, int *ambiguous);

/**
 * Capa 3: ce_palette_extract (cap CE_PALETTE_MAX_COLORS) + ce_match (top_k
 * CE_MATCH_MAX_HITS) en un solo contexto. `po`/`mo` NULL usan los valores por
 * defecto. Devuelve n_hits (> 0) y rellena `out` por completo (posiciones no
 * usadas a cero), o un código negativo sin escribir nada: los de
 * ce_palette_extract (imagen, opciones de paleta) y CE_ERR_ARG / CE_ERR_CTX /
 * CE_ERR_OPTS (opciones de match, validadas antes de extraer).
 */
int ce_analyze(ce_ctx *ctx, const ce_image *img, const ce_palette_opts *po,
               const ce_match_opts *mo, ce_result *out);

/** Índice del color del diccionario más cercano a `lab` por ΔE00 (empates al
 *  índice menor); escribe la distancia en `de` si no es NULL. Sin contexto
 *  (159 llamadas a ce_dict_color_lab). Devuelve -1 (y de = NaN) si `lab`
 *  contiene NaN. */
int ce_dict_nearest_color(ce_lab lab, double *de);

/** FNV-1a de 64 bits sobre los bytes de (L, a, b, weight) de cada swatch, en
 *  orden. Desde la fase 5 (ce_libm.c) el motor produce los mismos bits en
 *  nativo y en WASM, así que el hash es comparable entre plataformas y entre
 *  ejecuciones (`make parity` lo exige igual en las 20 fixtures). */
uint64_t ce_swatch_hash(const ce_swatch *sw, int n);

/** FNV-1a de un ce_result: ce_swatch_hash de sus n_swatches swatches, luego
 *  (combo_id, score) de cada uno de sus n_hits hits y `ambiguous`. Igual que
 *  ce_swatch_hash, idéntico en nativo y WASM sobre los mismos píxeles. El CLI
 *  (`ce match --top K`) y el wrapper Swift lo calculan con n_hits = K, es
 *  decir, sobre lo que devuelven. */
uint64_t ce_result_hash(const ce_result *r);

/* ========================================================================
 * Máscaras: regiones de ropa por pose, exclusión de piel adaptativa y
 * separación de instancias que juntan a varias personas (ce_mask.c). La
 * plataforma (Vision en iOS, MediaPipe en la web) aporta la máscara de la
 * persona, los puntos de la pose, las caras y la muestra de piel de la
 * cara; la geometría y la estadística viven aquí para que iOS y WASM
 * produzcan los mismos bits. Sin malloc, sin estáticos mutables, recorridos
 * en orden de índice. Las regiones y el recorte de cabeza solo usan +, −, ×, ÷,
 * sqrt y comparaciones; la piel usa además el Lab del motor (ce_srgb8_to_lab,
 * que pasa por ce_libm). El resultado es bit a bit igual en nativo y WASM
 * (test_mask: MASK_HASH y SPLIT_HASH; make parity: tests/layers_parity.js).
 *
 * Todas las máscaras son width*height bytes empaquetados sin stride, fila a
 * fila desde arriba-izquierda, 0..255 (0 = fuera).
 * ====================================================================== */

/** Código positivo de ce_mask_exclude_skin: la salvaguarda saltó (se habría
 *  excluido más de max_excluded_fraction de la máscara: prenda parecida a la
 *  piel) y la máscara NO se modificó. */
#define CE_SKIN_GUARD 1

/** Articulaciones de la pose, en el orden de VNHumanBodyPoseObservation
 *  (cuello = punto medio de los hombros; raíz = punto medio de las caderas). */
typedef enum ce_joint {
    CE_JOINT_NOSE = 0,
    CE_JOINT_NECK,
    CE_JOINT_LSHOULDER,
    CE_JOINT_RSHOULDER,
    CE_JOINT_LELBOW,
    CE_JOINT_RELBOW,
    CE_JOINT_LWRIST,
    CE_JOINT_RWRIST,
    CE_JOINT_LHIP,
    CE_JOINT_RHIP,
    CE_JOINT_LKNEE,
    CE_JOINT_RKNEE,
    CE_JOINT_LANKLE,
    CE_JOINT_RANKLE,
    CE_JOINT_ROOT,
    CE_JOINT_COUNT
} ce_joint;

/** Punto de la pose en píxeles de la máscara (origen arriba-izquierda, x a la
 *  derecha, y hacia abajo; el centro del píxel (i, j) es (i + 0.5, j + 0.5)).
 *  confidence <= 0 significa ausente. */
typedef struct ce_keypoint {
    double x;
    double y;
    double confidence;
} ce_keypoint;

typedef struct ce_pose {
    ce_keypoint k[CE_JOINT_COUNT];
} ce_pose;

/** Cota de |x| e |y| de un punto utilizable (píxeles); por encima el punto se
 *  trata como ausente (evita desbordes con coordenadas absurdas). */
#define CE_POSE_COORD_MAX 1048576.0
/** Mano (siempre excluida): cápsula desde la muñeca hasta muñeca +
 *  CE_HAND_LENGTH·sw en la dirección codo -> muñeca, de radio CE_HAND_RADIUS·sw
 *  (sw = ancho de hombros); sin codo, disco de radio CE_HAND_LENGTH·sw
 *  centrado en la muñeca. Antropometría: la mano mide ~0,47 sw de largo. */
#define CE_HAND_LENGTH 0.45
#define CE_HAND_RADIUS 0.2
/** Ancho de hombros mínimo (píxeles) de una pose utilizable. */
#define CE_POSE_MIN_SHOULDER_WIDTH 1.0

/** Opciones de ce_mask_clothing_regions (rangos; fuera => CE_ERR_ARG):
 *  - min_confidence [0, 1] (0.3): un punto cuenta si confidence > 0,
 *    confidence >= min_confidence y x, y finitos con |x|, |y| <= CE_POSE_COORD_MAX.
 *  - torso_margin [0, 1] (0.12): expansión del torso, en anchos de hombros.
 *  - limb_width [0, 2] (0.45): ANCHO total de las cápsulas de brazos y
 *    piernas en anchos de hombros (radio = limb_width·sw/2).
 *  - include_upper_arms (1), include_forearms (0), include_legs (1),
 *    include_lower_legs (1): 0 o 1. */
typedef struct ce_region_opts {
    double min_confidence;
    double torso_margin;
    double limb_width;
    int include_upper_arms;
    int include_forearms;
    int include_legs;
    int include_lower_legs;
} ce_region_opts;

/** min_confidence 0.3, torso_margin 0.12, limb_width 0.45, include_upper_arms 1,
 *  include_forearms 0, include_legs 1, include_lower_legs 1. */
void ce_region_opts_default(ce_region_opts *o);

/**
 * Recorta la máscara de una persona a su ropa según la pose.
 *
 * `inout_mask` entra con la máscara de la persona y sale con
 * min(máscara, región) donde región(p) (evaluada en el centro de cada píxel,
 * sin antialiasing, 255 dentro y 0 fuera) es:
 *
 *   lado(p) ∧ ¬mano(p) ∧ (torso(p) ∨ cápsulas(p))
 *
 *  - Hombros LS, RS y caderas LH, RH: si falta uno solo de los hombros se
 *    estima por simetría puntual respecto al cuello, S_falta = 2·NECK − S_otro
 *    (Vision define el cuello como su punto medio); si falta una sola cadera,
 *    H_falta = 2·ROOT − H_otra. Sin el punto de simetría, o con los dos
 *    ausentes: CE_ERR_POSE. También CE_ERR_POSE si sw = |LS − RS| <
 *    CE_POSE_MIN_SHOULDER_WIDTH o si el punto medio de las caderas cae sobre
 *    la recta de los hombros (pose degenerada).
 *  - lado(p): p está en el semiplano de la recta LS–RS que contiene el punto
 *    medio de las caderas, o sobre la recta. Excluye la cabeza (y cualquier
 *    cosa por encima de la línea de hombros, también los brazos levantados).
 *  - torso(p): distancia de p a la envolvente convexa de {LS, RS, RH, LH}
 *    <= torso_margin·sw (dentro de la envolvente, distancia 0).
 *  - cápsulas(p): distancia de p al segmento <= limb_width·sw/2 para
 *    hombro->codo (include_upper_arms), codo->muñeca (include_forearms),
 *    cadera->rodilla (include_legs) y rodilla->tobillo (include_lower_legs),
 *    solo si los dos extremos existen (las caderas y hombros estimados valen).
 *  - mano(p): ver CE_HAND_LENGTH / CE_HAND_RADIUS, para cada muñeca presente
 *    aunque include_forearms = 0.
 *
 * Todo se calcula relativo a los puntos (p − A, B − A) con +, −, ×, ÷ y sqrt:
 * con coordenadas cuyas operaciones son exactas (p. ej. múltiplos de 1/64 de
 * magnitud moderada) el resultado es exactamente invariante a espejo
 * horizontal (con L/R intercambiados) y a traslaciones enteras; con
 * coordenadas arbitrarias solo pueden cambiar píxeles cuyo centro está a
 * ~1e-12 px de un borde.
 *
 * Devuelve el número de píxeles > 0 resultantes (>= 0), o CE_ERR_ARG (punteros
 * nulos, width/height fuera de [1, CE_IMAGE_MAX_SIDE], opciones no finitas o
 * fuera de rango) o CE_ERR_POSE; con error la máscara no se modifica.
 */
int ce_mask_clothing_regions(const ce_pose *pose, const ce_region_opts *o, uint8_t *inout_mask,
                             int width, int height);

/**
 * Fallback sin pose: anula la franja superior del bbox de los píxeles > 0.
 * Con y0..y1 las filas primera y última con algún píxel > 0 y H = y1 − y0 + 1,
 * pone a 0 las filas y0 .. y0 + c − 1 con c = floor(fraction·H + 0.5).
 * `fraction` en [0, 0.5]. Devuelve los píxeles > 0 resultantes (máscara vacía:
 * 0 sin error) o CE_ERR_ARG (máscara nula, dimensiones fuera de
 * [1, CE_IMAGE_MAX_SIDE], fraction NaN o fuera de rango) sin tocar la máscara.
 */
int ce_mask_cut_head(uint8_t *inout_mask, int width, int height, double fraction);

/**
 * Regiones de prenda de una persona para ce_palette_extract_garments: la misma
 * geometría que ce_mask_clothing_regions (mismos predicados lado ∧ ¬mano ∧
 * (torso ∨ cápsulas), así que los píxeles > 0 de `regions_out` son exactamente
 * los que conserva ce_mask_clothing_regions con la misma máscara) repartida en
 * dos etiquetas:
 *
 *   regions_out[p] = 0 si person_mask[p] == 0 o p no está en la región de ropa;
 *                    2 (CE_GARMENT_REGION_LOWER, "abajo": caderas a tobillos) si
 *                      p está en una cápsula de pierna (cadera->rodilla,
 *                      rodilla->tobillo) y no en el torso ni en un brazo, o si p
 *                      está en el torso o en una pierna y más allá de la recta de
 *                      corte: (2p − (LH + RH)) · ((LH + RH) − (LS + RS)) > 0
 *                      (perpendicular al eje hombros -> caderas por el punto medio
 *                      de las caderas; hombros y caderas estimados por simetría
 *                      como en ce_mask_clothing_regions);
 *                    1 (CE_GARMENT_REGION_UPPER, "arriba": torso y brazos
 *                      superiores, y antebrazos si include_forearms) en otro caso.
 *
 * Una pierna fuera del torso es "abajo" aunque no cruce el corte (muslos en
 * horizontal de una persona sentada). Solo +, −, ×, ÷, sqrt y comparaciones:
 * bit a bit igual en nativo y WASM e invariante a espejo con coordenadas
 * exactas, como ce_mask_clothing_regions. `regions_out` puede ser el mismo
 * buffer que `person_mask` (cada píxel se lee antes de escribirse).
 *
 * Devuelve los píxeles con etiqueta 1 o 2 (>= 0), o sin escribir nada
 * CE_ERR_ARG (punteros nulos, dimensiones fuera de [1, CE_IMAGE_MAX_SIDE],
 * opciones inválidas) o CE_ERR_POSE (mismos casos que ce_mask_clothing_regions).
 */
int ce_mask_garment_regions(const ce_pose *pose, const ce_region_opts *o, const uint8_t *person_mask,
                            int width, int height, uint8_t *regions_out);

/** Muestras mínimas de ce_skin_model_fit y umbral de la máscara de muestra. */
#define CE_SKIN_MIN_SAMPLES 50
#define CE_SKIN_SAMPLE_THRESHOLD 128
/** Regularización de la covarianza (unidades Lab al cuadrado): cov + ε·I.
 *  Pone un suelo de 1 ΔE*ab de desviación típica en cada eje, así una muestra
 *  plana (covarianza singular) sigue siendo invertible y no excluye solo el
 *  color exacto. */
#define CE_SKIN_COV_EPSILON 1.0

/** Modelo gaussiano de piel en CIELAB: media, covarianza regularizada y su
 *  inversa (row-major, 3x3) y número de muestras. */
typedef struct ce_skin_model {
    ce_lab mean;
    double cov[9];
    double inv_cov[9];
    int n;
} ce_skin_model;

/**
 * Ajusta el modelo de piel con los píxeles de `img` cuya `sample_mask`
 * (width*height bytes) vale >= CE_SKIN_SAMPLE_THRESHOLD (p. ej. las mejillas
 * de la cara). Lab bit a bit igual a ce_srgb8_to_lab (calculado con una tabla
 * por canal, ver ce_internal.h); media y covarianza poblacional
 * (dividida por n) acumuladas en orden de índice en dos pasadas; covarianza
 * + CE_SKIN_COV_EPSILON·I invertida por adjuntos. img->mask se ignora.
 * Devuelve CE_OK y escribe `out`, o sin escribir: CE_ERR_ARG (punteros),
 * los errores de imagen de ce_palette_extract (CE_ERR_DIMS, CE_ERR_FORMAT,
 * CE_ERR_STRIDE) o CE_ERR_SKIN_SAMPLES (< CE_SKIN_MIN_SAMPLES muestras).
 */
int ce_skin_model_fit(const ce_image *img, const uint8_t *sample_mask, ce_skin_model *out);

/** Opciones de ce_mask_exclude_skin: max_mahalanobis finito >= 0 (2.5);
 *  max_excluded_fraction en [0, 1] (0.35). Fuera de rango => CE_ERR_ARG. */
typedef struct ce_skin_opts {
    double max_mahalanobis;
    double max_excluded_fraction;
} ce_skin_opts;

/** max_mahalanobis 2.5, max_excluded_fraction 0.35. */
void ce_skin_opts_default(ce_skin_opts *o);

/**
 * Pone a 0 los píxeles con máscara > 0 cuyo Lab (ce_srgb8_to_lab) está a
 * distancia de Mahalanobis <= max_mahalanobis del modelo (d² = vᵀ·inv_cov·v
 * con v = Lab − media, comparada con max_mahalanobis²). Cuenta primero (orden
 * de índice): si excluidos > max_excluded_fraction · píxeles > 0 de la
 * máscara, NO la modifica y devuelve CE_SKIN_GUARD (1); si no, la modifica y
 * devuelve CE_OK (0). La máscara tiene las dimensiones de `img` (img->mask se
 * ignora). Errores sin tocar la máscara: CE_ERR_ARG (punteros, opciones, modelo
 * con valores no finitos o inv_cov cuya parte simétrica no es definida
 * positiva), errores de imagen, CE_ERR_SKIN_SAMPLES (m->n < CE_SKIN_MIN_SAMPLES).
 */
int ce_mask_exclude_skin(const ce_image *img, const ce_skin_model *m, const ce_skin_opts *o,
                         uint8_t *inout_mask);

/** Semillas máximas de ce_mask_split_instance. */
#define CE_SPLIT_MAX_SEEDS 8

/** Semilla de una persona para separar una instancia fusionada: eje del
 *  cuerpo en píxeles de la máscara (mismo marco que ce_keypoint), de arriba
 *  (x0, y0: cuello o base de la cara) a abajo (x1, y1: punto medio de las
 *  caderas o extrapolado), y semiancho del cuerpo `half_width` (> 0, píxeles).
 *  Un eje degenerado (x0, y0) == (x1, y1) vale como un punto. */
typedef struct ce_person_seed {
    double x0, y0, x1, y1;
    double half_width;
} ce_person_seed;

/**
 * Separa una máscara de instancia que junta a varias personas (Vision fusiona
 * a las que se tocan o se solapan) usando una semilla por persona.
 *
 * Para cada píxel con mask >= 128 escribe en `labels_out` 1 + argmin_k de
 * d_k / half_width_k, con d_k la distancia euclídea del centro del píxel
 * (x + 0.5, y + 0.5) al segmento de la semilla k (proyección acotada a
 * [0, 1], calculada relativa a (x0, y0) con +, −, ×, ÷ y sqrt en orden fijo,
 * como las cápsulas de ce_mask_clothing_regions); empate (cocientes iguales)
 * por el índice menor. El resto de píxeles recibe 0. Recorrido en orden de
 * índice; con coordenadas cuyas operaciones son exactas (p. ej. múltiplos de
 * 1/4) el resultado es exactamente equivariante a espejo horizontal
 * (conservando el índice de cada semilla) y a traslaciones enteras.
 *
 * `labels_out` (width*height bytes) puede ser el mismo buffer que `mask`
 * (cada píxel se lee antes de escribirse), pero no solaparse parcialmente.
 *
 * Devuelve el número de etiquetas con al menos un píxel (0..n_seeds; 0 con
 * la máscara vacía), o CE_ERR_ARG sin escribir nada: punteros nulos,
 * width/height fuera de [1, CE_IMAGE_MAX_SIDE], n_seeds fuera de
 * [1, CE_SPLIT_MAX_SEEDS], coordenadas no finitas o con |v| >
 * CE_POSE_COORD_MAX, half_width no finito, <= 0 o > CE_POSE_COORD_MAX.
 */
int ce_mask_split_instance(const uint8_t *mask, int width, int height, const ce_person_seed *seeds,
                           int n_seeds, uint8_t *labels_out);

/* ========================================================================
 * Paleta por prenda (ce_garment.c): un color por prenda lisa.
 *
 * Una foto de ropa real reparte el mismo tejido en luces, sombras y pliegues;
 * ce_palette_extract los devuelve como colores distintos (caso real: un
 * pantalón rosa palo en 4 swatches). Aquí la paleta se calcula POR REGIÓN DE
 * PRENDA (mapa de ce_mask_garment_regions: 1 arriba, 2 abajo), los clusters
 * que son el mismo color con distinta luz se agrupan y cada grupo se
 * representa con su TONO ILUMINADO (percentiles altos de L*, sin especulares),
 * que es como el usuario percibe la prenda. Sin malloc, sin RNG, en orden de
 * índice y con ce_libm: mismos bits en nativo y WASM.
 * ====================================================================== */

/** Regiones de prenda (valores de ce_garment_swatch.region y del mapa de
 *  ce_mask_garment_regions). CE_GARMENT_MAX_REGIONS: máximo de n_regions. */
#define CE_GARMENT_REGION_NONE 0
#define CE_GARMENT_REGION_UPPER 1
#define CE_GARMENT_REGION_LOWER 2
#define CE_GARMENT_REGION_WHOLE 3
#define CE_GARMENT_MAX_REGIONS 2

/** Límite físico de la agrupación de tonos: dos clusters (o dos grupos) solo
 *  pueden ser el mismo tejido con luz y sombra si la menor de sus luminancias
 *  con suelo (Y + CE_GARMENT_SHADE_Y_FLOOR, blanco Y = 1) es >= 
 *  CE_GARMENT_SHADE_MIN_RATIO veces la mayor (una sombra que oscurece la luz
 *  lineal más de 5 veces no se tolera). Evita que los tonos intermedios de un
 *  estampado desenfocado encadenen el fondo oscuro con el motivo claro (vestido
 *  azul marino con estampado blanco de harness/people/02 salía como un gris).
 *  Calibrado en engine/BENCHLOG.md. */
#define CE_GARMENT_SHADE_MIN_RATIO 0.2
#define CE_GARMENT_SHADE_Y_FLOOR 0.01

/** Núcleo del tono iluminado: el tono de un grupo se calcula con los clusters que
 *  pasan DOS filtros, en este orden:
 *   (1) PESO: pesan >= CE_GARMENT_LIT_CORE_FRACTION veces el más pesado del grupo.
 *       Deja fuera los brillos especulares y los tonos de borde de un estampado
 *       (pocos píxeles, más claros que el fondo oscuro), que si no desplazarían el
 *       tono iluminado del color oscuro.
 *   (2) NIVEL DE LUZ: de esos, los que están a menos de UN PASO de luz del más
 *       luminoso (Y con suelo >= CE_GARMENT_LIT_Y_RATIO veces la mayor). Un grupo
 *       puede contener varios niveles de luz (la prenda al sol y la misma prenda en
 *       sombra); el TONO ILUMINADO es el del nivel de arriba. Sin este filtro, los
 *       percentiles lit_low_pct..lit_high_pct se calculan sobre el grupo ENTERO y,
 *       cuanto más grande es la sombra, más caen dentro de ella: medido, el tono se
 *       oscurecía ~1 ΔE00 por cada paso de sombra y con 3 pasos se salía del
 *       objetivo ΔE00 < 5 (tabla en engine/BENCHLOG.md, "Paleta por prenda").
 *  LÍMITE MEDIDO: el filtro (1) va antes que el (2), así que cuando la sombra cubre
 *  MÁS del ~70 % de la prenda el nivel iluminado ya no pesa lo suficiente y el color
 *  que se devuelve es el TONO EN SOMBRA (sigue siendo UN color, que es el requisito
 *  del usuario, pero el hex es el de la sombra). Fijado por el test
 *  SKY_SHADOW_80 de engine/tests/test_garment.c. */
#define CE_GARMENT_LIT_CORE_FRACTION 0.35
#define CE_GARMENT_LIT_Y_RATIO 0.5

/** Tonos de mezcla: un cluster cuyo centro (XYZ lineal) está a ΔE00 <
 *  CE_GARMENT_MIXTURE_DE de t·A + (1 − t)·B, con t en [CE_GARMENT_MIXTURE_T_MIN,
 *  1 − CE_GARMENT_MIXTURE_T_MIN], son píxeles del BORDE entre dos colores
 *  (estampado desenfocado): no entra en ningún grupo y su peso se reparte entre A
 *  (t) y B (1 − t). Los dos extremos A y B tienen que cumplir TODO esto:
 *   - no ser el mismo color con distinta luz: ni el mismo material bajo los dos
 *     modelos de sombra (ver CE_GARMENT_SHADE_S_MIN), ni un par dentro del límite
 *     de luminancia con croma y tono a ΔE00(kL = CE_GARMENT_HUE_KL) <
 *     shade_merge_de. Lo que hay entre la luz y su sombra es PENUMBRA —la misma
 *     tela con luz intermedia—, no el borde entre dos colores. Es literal: una
 *     oclusión PARCIAL es una combinación lineal de los dos iluminantes, así que
 *     los tonos de la penumbra de una sombra CROMÁTICA caen sobre el segmento
 *     A-B y, sin esta condición, se tomaban por mezcla y su marca vetaba el único
 *     camino por el que el modelo de cielo puede agrupar (el pantalón liso al sol
 *     y a la sombra azul salía SIEMPRE con dos colores).
 *   - no ser una sombra del propio cluster (s·A en XYZ con s dentro del límite de
 *     luminancia, a ΔE00 < CE_GARMENT_MIXTURE_DE: una mezcla con el negro es una
 *     sombra).
 *   - pesar >= min_weight de la región (peso propio más el ya recibido de otras
 *     mezclas): los dos extremos de un borde son áreas de verdad de la prenda; un
 *     cluster de cuatro píxeles de borde o de ruido no lo es, y tomarlo por extremo
 *     convertía la sombra entera en "mezcla" y su peso en el de un color falso. */
#define CE_GARMENT_MIXTURE_DE 3.0
#define CE_GARMENT_MIXTURE_T_MIN 0.05
#define CE_GARMENT_HUE_KL 1000.0

/** DEGRADADO DE COLOR dentro de una prenda (tie-dye, degradado teñido, estampado
 *  desenfocado): los tonos de mezcla del paso 3 son justamente la prueba de que
 *  hay una variación de tono CONTINUA entre dos colores de la región, así que un
 *  segundo color unido al primero por tonos de mezcla es un EXTREMO del
 *  degradado, no un tono suelto, y se conserva con una cuota menor:
 *  CE_GARMENT_GRADIENT_MIN_SHARE en vez de secondary_min_share, siempre que
 *  (a) los dos tonos iluminados se separen de verdad en croma y tono (ΔE00(kL =
 *  CE_GARMENT_HUE_KL) >= CE_GARMENT_GRADIENT_HUE_DE, que ninguna sombra cumple:
 *  una sombra solo cambia L*) y (b) los tonos de mezcla sean buena parte del
 *  grupo candidato (>= CE_GARMENT_GRADIENT_MIX_FRACTION de su peso): en un
 *  degradado de verdad los tonos intermedios son tela, en el borde entre dos
 *  prendas distintas son cuatro píxeles. Medido (engine/BENCHLOG.md): tie-dye
 *  magenta -> amarillo -> cian, fracción de mezcla 0,41-0,48 y ΔE00 de tono
 *  36-46; el borde de la persona de al lado en harness/people/03, 0,16 y 8,7. */
#define CE_GARMENT_GRADIENT_MIN_SHARE 0.10
#define CE_GARMENT_GRADIENT_HUE_DE 12.0
#define CE_GARMENT_GRADIENT_MIX_FRACTION 0.25

/** MISMO MATERIAL CON DISTINTA LUZ (`ce_garment_same_material`, la regla física
 *  que usan la agrupación del paso 3 y la selección del paso 5). Dos colores a
 *  (el más luminoso: la LUZ) y c (el más oscuro: la SOMBRA) son el mismo tejido
 *  si se cumple uno de los dos modelos, los dos con la misma tolerancia
 *  CE_GARMENT_SHADE_LIT_DE y el mismo límite de profundidad
 *  CE_GARMENT_SHADE_S_MIN:
 *
 *  (1) SOMBRA NEUTRA (escala pura): c ≈ s·a en XYZ lineal, s de mínimos
 *      cuadrados en [CE_GARMENT_SHADE_S_MIN, 1/CE_GARMENT_SHADE_S_MIN], a ΔE00 <
 *      CE_GARMENT_SHADE_LIT_DE. Es la misma reflectancia con menos fotones del
 *      MISMO iluminante (interior, día nublado, sombra propia de un pliegue).
 *  (2) SOMBRA CROMÁTICA DE EXTERIOR (dos iluminantes): al sol la prenda recibe
 *      sol + cielo y en la sombra solo el cielo, que es mucho más azul, así que
 *      la sombra NO es una escala de la luz: se azulea (harness/people/06, el
 *      vaquero liso al sol y a la sombra, necesitaba tolerancia 5,75 con el
 *      modelo (1)). Se modela como adaptación parcial hacia el cielo:
 *          c ≈ s·(a + w·S·a),
 *      con S = M⁻¹·diag(g−1)·M la matriz del cambio de iluminante en conos de
 *      Bradford (M = CAT de Bradford, g = blanco de cielo CIE D 12000 K sobre
 *      blanco de escena CIE D 5500 K, normalizado al canal M) y (s, w·s) de
 *      mínimos cuadrados: DOS incógnitas y tres ecuaciones, así que el residuo
 *      sigue discriminando. `w` es la INTENSIDAD de la adaptación, estimada de
 *      la propia imagen (del par), no fijada: w = 0 es el modelo (1) y w = 1 es
 *      sombra abierta completa (solo cielo). Se acota como manda la física:
 *      0 <= w <= min(CE_GARMENT_SKY_W_MAX, CE_GARMENT_SKY_W_SLOPE·(1−s)/s), es
 *      decir el azuleo no puede superar el de la sombra abierta ni crecer si la
 *      luminancia apenas cae (con una fracción de cielo <= 0,35 del total,
 *      w = f/(1−f)·(1−s)/s). Nunca al revés: una sombra no se vuelve más
 *      amarilla (w >= 0).
 *
 *  LÍMITES CONOCIDOS, medidos (engine/BENCHLOG.md "Paleta por prenda"), que son
 *  la contrapartida deliberada del requisito "un color por prenda lisa"
 *  (ADR-011) y NO solo el caso de dos neutros:
 *  - el modelo (1) une CUALQUIER par que comparta cromaticidad, por saturado que
 *    sea (escalar en XYZ conserva xy): un tinte y su propia sombra, o dos tintes
 *    del mismo tono a distinta claridad (blanco + gris medio, beige + marrón,
 *    rosa palo + malva, crema + tierra). Una prenda bicolor TONAL sale con un
 *    solo color. En el diccionario de Wada hay pares así (ver ADR-011 y
 *    oracle/oracle/garments.py, familia "bicolor_tonal"): si los dos caen en la
 *    misma región de prenda, esa combinación no se puede acertar.
 *  - el modelo (2) añade los pares azul claro / azul oscuro que cumplen el
 *    azuleo acotado (una camisa celeste bajo una chaqueta vaquera en la MISMA
 *    región saldría como un color).
 *  - el daño está acotado por tres cosas: CE_GARMENT_SHADE_S_MIN (ninguna sombra
 *    oscurece más de ~4,6 pasos de luz lineal: el marino y su estampado blanco de
 *    harness/people/02 están a s = 0,012 y ya no se unen), el control de la cadena
 *    del paso 3 (enlace COMPLETO o ESTRELLA alrededor del tono más luminoso: en los
 *    dos casos nada se encadena por transitividad, ver el paso 3 de
 *    ce_palette_extract_garments) y el VETO DE MEZCLA: dos colores unidos por un
 *    tono de mezcla (hay píxeles que son la combinación de los dos, es decir un
 *    borde de estampado o de rayas) nunca son el mismo material con distinta luz,
 *    por bien que ajusten al modelo. OJO: la penumbra de una sombra NO cuenta como
 *    tono de mezcla, porque un par que es el mismo material no puede ser extremo de
 *    una mezcla (ver CE_GARMENT_MIXTURE_DE); el veto solo protege a los pares que
 *    los dos modelos consideran colores distintos.
 *  - MEDIDO (oracle/oracle/garments.py, familia informativa "bicolor_tonal", y
 *    engine/BENCHLOG.md): de 10 pares ambiguos a propósito (5 por el modelo (1) y 5
 *    por el (2)) se conserva 1. Las familias de gate del bloque «prendas» rechazan
 *    los pares con same_material_residual < 5 para medir lo que dicen medir y no
 *    este límite. */
#define CE_GARMENT_SHADE_S_MIN 0.04
#define CE_GARMENT_SHADE_LIT_DE 3.0
#define CE_GARMENT_SKY_W_MAX 1.15
#define CE_GARMENT_SKY_W_SLOPE 0.54

/** Opciones de la paleta por prenda (ce_garment_opts_default rellena los valores
 *  por defecto, calibrados en engine/BENCHLOG.md "Paleta por prenda": shade_kL 3,
 *  shade_merge_de 6,5, lit_low_pct 0,75, lit_high_pct 0,95, secondary_min_share
 *  0,25, max_colors_per_region 2). Rangos (fuera de ellos o NaN/±inf: CE_ERR_OPTS):
 *  - shade_kL (> 0, finito): kL de ΔE00 al agrupar tonos de luz/sombra.
 *  - shade_merge_de (finito; <= 0 = sin agrupar por sombra): dos clusters (o dos
 *    tonos iluminados) son "agrupables" si ΔE00(kL = shade_kL, kC = kH = 1) <
 *    shade_merge_de, o si ΔE00 < merge_de, o si merge_light_de > 0 y ΔE00(kL =
 *    CE_PALETTE_LIGHT_MERGE_KL) < merge_light_de (las fusiones de ce_palette_opts
 *    se conservan).
 *  - lit_low_pct <= lit_high_pct, ambos en [0, 1]: percentiles de L* (ponderados
 *    por peso) del tono iluminado del grupo.
 *  - secondary_min_share en [0, 1]: cuota mínima en su región de un segundo
 *    color (prenda bicolor: rayas, estampado, bloques).
 *  - max_colors_per_region en 1..CE_PALETTE_MAX_COLORS. */
typedef struct ce_garment_opts {
    double shade_kL;
    double shade_merge_de;
    double lit_low_pct;
    double lit_high_pct;
    double secondary_min_share;
    int max_colors_per_region;
} ce_garment_opts;

/** shade_kL 3.0, shade_merge_de 6.5, lit_low_pct 0.75, lit_high_pct 0.95,
 *  secondary_min_share 0.25, max_colors_per_region 2. */
void ce_garment_opts_default(ce_garment_opts *o);

/** Swatch de prenda: el ce_swatch (Lab del tono iluminado, sRGB8, peso final),
 *  la región (CE_GARMENT_REGION_*: 1 arriba, 2 abajo, 3 prenda entera cuando
 *  arriba y abajo se fusionaron, 0 sin mapa de regiones), la cuota de esa región
 *  sobre el ÁREA CUBIERTA POR EL MAPA (0..1; las cuotas de las regiones suman 1, así
 *  que solo coinciden con su cuota en la máscara cuando el mapa cubre toda la
 *  máscara, como hace SubjectKit) y cuántos clusters de Lloyd se agruparon en él. */
typedef struct ce_garment_swatch {
    ce_swatch swatch;
    int region;
    double region_share;
    int n_merged_clusters;
} ce_garment_swatch;

/**
 * Paleta por prenda. `region_map` (width*height bytes, sin stride): 0 = fuera,
 * 1..n_regions = región (valores > n_regions cuentan como fuera); NULL = una
 * sola región con toda la imagen (region 0 en la salida; n_regions se ignora).
 * img->mask sigue aplicándose (máscara de sujeto) y `po` como en
 * ce_palette_extract (NULL = defaults; max_colors acota el total de swatches).
 *
 *  1. Box-downscale como ce_palette_extract con la máscara efectiva
 *     em(p) = máscara(p) (255 sin máscara) si p está en una región y 0 si no;
 *     cada bloque toma la región con mayor Σ em (empates: la menor). Pesos por
 *     píxel con la gaussiana y la regla de piel de `po`.
 *  2. Por región (en orden 1..n_regions), con solo sus píxeles: histograma,
 *     MMCQ y Lloyd como ce_palette_extract, con k = min(k_init,
 *     CE_PALETTE_K_MAX / n_regions).
 *  3. Tonos de mezcla (ver CE_GARMENT_MIXTURE_DE): clusters en el borde entre
 *     dos colores de un estampado desenfocado; no entran en ningún grupo y su
 *     peso pasa a los dos extremos. Grupos sobre los demás centros de Lloyd no
 *     vacíos. Dos centros son COMPATIBLES si son "agrupables" (ver
 *     ce_garment_opts) o si son el mismo material con distinta luz (ver
 *     CE_GARMENT_SHADE_S_MIN) y no son los dos extremos de un tono de mezcla
 *     (veto de mezcla). Se une repetidamente el par compatible de grupos
 *     distintos con menor ΔE00(kL = shade_kL) (empates: i y luego j menores)
 *     siempre que (a) si el par se une por "agrupable" y no por sombra, la unión
 *     respete además el límite de luminancia (menor Y +
 *     CE_GARMENT_SHADE_Y_FLOOR >= CE_GARMENT_SHADE_MIN_RATIO · mayor) y (b) la
 *     unión pase UNO de los dos controles de cadena:
 *       - ENLACE COMPLETO: todos los pares cruzados de los dos grupos son
 *         compatibles (cada grupo es una camarilla), o
 *       - ESTRELLA DE SOMBRA: todos los miembros de la unión son el mismo material
 *         con distinta luz que el MÁS LUMINOSO de la unión (empate: índice menor).
 *     Hasta que no queda ninguno; cabeza del grupo = centro de índice menor.
 *     Ninguno de los dos controles encadena por transitividad: con enlace simple
 *     bastaba una cadena de pares vecinos y los tonos intermedios de un estampado
 *     desenfocado unían el fondo oscuro con el motivo claro (el vestido azul marino
 *     con estampado blanco de harness/people/02 salía como un gris, o partía el
 *     vestido en dos regiones); con el enlace completo el par extremo marino/blanco
 *     tiene que ser compatible él mismo, y con la estrella todo el grupo tiene que
 *     ser una sombra del MISMO tono iluminado (el marino no es una sombra del
 *     blanco: s = 0,012 < CE_GARMENT_SHADE_S_MIN). La estrella hace falta porque el
 *     modelo de sombra se define desde la LUZ: dos penumbras intermedias de la misma
 *     rampa no siempre se ajustan entre ELLAS (la cota del azuleo,
 *     CE_GARMENT_SKY_W_SLOPE·(1−s)/s, supone que el color de referencia es el tono
 *     al sol) aunque las dos se ajusten perfectamente al tono al sol.
 *     Orden de grupos por peso desc (desempate: cabeza menor). Los grupos con
 *     cuota < min_weight en la región se descartan (el más pesado siempre queda).
 *  4. Tono iluminado de un conjunto de clusters (solo su NÚCLEO: los que pesan >=
 *     CE_GARMENT_LIT_CORE_FRACTION veces el mayor y, de esos, los que están a menos
 *     de un paso de luz del más luminoso, CE_GARMENT_LIT_Y_RATIO): histograma de L* (bins de 0,1)
 *     de los bins de color del histograma de la región ponderado por peso; q(p) =
 *     primer bin de L* no vacío con suma acumulada >= p · total; media ponderada
 *     en Lab de los bins de color con L* en [q(lit_low_pct), q(lit_high_pct)].
 *  5. Selección en orden: el primer grupo es el color principal; cada grupo
 *     siguiente cuyo tono iluminado es agrupable con el de un color ya elegido (y
 *     cuya unión respeta el límite de luminancia) O es ese color con otra cantidad
 *     de luz (sombra: ver CE_GARMENT_SHADE_S_MIN, sin límite de luminancia, solo
 *     con shade_merge_de > 0 y con el mismo veto de mezcla del paso 3) se suma a
 *     ese color (el primero que cumpla; su tono se recalcula con la unión);
 *     si no, es un color más solo si quedan huecos (max_colors_per_region) y su
 *     cuota en la región >= secondary_min_share, o >= CE_GARMENT_GRADIENT_MIN_SHARE
 *     cuando es el EXTREMO DE UN DEGRADADO de color (ver
 *     CE_GARMENT_GRADIENT_MIN_SHARE): algún cluster suyo y alguno del color ya
 *     elegido son los dos extremos de un tono de mezcla del paso 3 y los dos tonos
 *     iluminados se separan en croma y tono. Cuota de cada color en la región =
 *     su peso / peso de los colores elegidos.
 *  6. Con n_regions == 2, si las dos regiones tienen color y cada color de una es
 *     FUSIONABLE con alguno de la otra (misma prenda: vestido, mono), se repiten
 *     2-5 con la unión de las dos regiones (k = min(k_init, CE_PALETTE_K_MAX)) y
 *     sus colores salen con region = CE_GARMENT_REGION_WHOLE. Fusionable compara
 *     tonos iluminados, ya sin sombras, sin volver a tolerar L*: ΔE00 (kL = kC =
 *     kH = 1) < shade_merge_de, o ΔE00 < merge_de. OJO: se comparan los tonos
 *     iluminados ESTIMADOS (percentiles de L* de cada región), no los colores
 *     verdaderos, así que la promesa es sobre la estimación: un par de prendas
 *     cuyo ΔE00 REAL esté a menos de ~1 de shade_merge_de puede caer a cualquiera
 *     de los dos lados según la luz y la textura (curva de la banda medida en
 *     engine/BENCHLOG.md, familia "banda_fusion" del bloque «prendas» de L2).
 *     Fuera de esa banda el comportamiento sí es el esperado: a ΔE00 real >=
 *     shade_merge_de + 1,5 no se observan fusiones.
 *  7. region_share = peso de la región / peso de TODAS las regiones (no de la
 *     máscara: con un mapa parcial las cuotas siguen sumando 1); peso final =
 *     region_share × cuota del color en la región. Orden por peso desc
 *     (desempate: región, luego orden dentro de la región), recorte a
 *     min(po->max_colors, cap) y renormalización a suma 1.
 * Una región sin píxeles con peso no produce swatches (ni NaN). Si ninguna tiene
 * peso devuelve 1 swatch de reserva con region 0, region_share 1, weight 1 y
 * n_merged_clusters 0: el color medio de los píxeles con máscara > 0 de la imagen
 * ORIGINAL (ponderado por la máscara, acumuladores enteros) si img->mask no es NULL
 * y tiene píxeles, y si no el color medio (sin ponderar) de la imagen reducida, como
 * ce_palette_extract. Con una máscara válida y un mapa de regiones desalineado el
 * color de reserva es el de la persona, nunca el del fondo (CONTEXT §12).
 *
 * Devuelve el número de swatches (>= 1) o, sin escribir nada: CE_ERR_ARG (ctx,
 * img u out nulos, cap < 1, region_map no nulo con n_regions fuera de
 * 1..CE_GARMENT_MAX_REGIONS), CE_ERR_CTX, errores de imagen (CE_ERR_DIMS,
 * CE_ERR_FORMAT, CE_ERR_STRIDE) o CE_ERR_OPTS (`po` o `go` inválidas; go NULL =
 * ce_garment_opts_default). Deja en el contexto las capas de depuración
 * (ce_palette_debug_info: clusters de todas las regiones con su grupo en
 * group_head y su swatch de prenda en final_index; ce_debug_garment_map,
 * ce_debug_region_map, ce_debug_label_map y ce_debug_cluster_map).
 */
int ce_palette_extract_garments(ce_ctx *ctx, const ce_image *img, const uint8_t *region_map, int n_regions,
                                const ce_palette_opts *po, const ce_garment_opts *go,
                                ce_garment_swatch *out, int cap);

/**
 * ce_palette_extract_garments + ce_match con los swatches de prenda (el match no
 * cambia). `garments` puede ser NULL (entonces `cap` se ignora); si no, recibe
 * los mismos swatches que out->swatches con su región (cap >= 1; se extraen
 * min(cap, CE_PALETTE_MAX_COLORS)). Devuelve n_hits (> 0) y rellena `out` como
 * ce_analyze (posiciones no usadas a cero), o un código negativo sin escribir
 * nada: los de ce_palette_extract_garments y CE_ERR_OPTS con opciones de match
 * inválidas (validadas antes de extraer).
 */
int ce_analyze_garments(ce_ctx *ctx, const ce_image *img, const uint8_t *region_map, int n_regions,
                        const ce_palette_opts *po, const ce_garment_opts *go, const ce_match_opts *mo,
                        ce_result *out, ce_garment_swatch *garments, int cap);

/** FNV-1a de 64 bits de los swatches de prenda, en orden: los bytes de (L, a, b,
 *  weight, region_share) en double y (region, n_merged_clusters) en 4 bytes
 *  little-endian. Mismos bits en nativo y WASM. */
uint64_t ce_garment_hash(const ce_garment_swatch *g, int n);

/* ========================================================================
 * Capas de depuración (ce_debug.c): lectura del estado que deja en el
 * contexto la última ce_palette_extract / ce_analyze completada, para ver cada
 * etapa del pipeline (imagen reducida, peso por píxel, qué píxeles alimentan
 * cada swatch, clusters fusionados o descartados) y explicar el score de una
 * combinación. Sin malloc: buffers del llamante. Cualquier llamada a
 * ce_palette_extract invalida el estado anterior (aunque falle).
 * ====================================================================== */

/** Etiqueta de un píxel reducido con peso 0 (máscara, piel o fuera del sujeto). */
#define CE_LABEL_NONE 255
/** Etiqueta de un píxel de un cluster descartado (por min_weight o por el
 *  recorte a max_colors / cap). */
#define CE_LABEL_DISCARDED 254

/** Destino de un cluster de Lloyd (ce_cluster_debug.fate). */
#define CE_FATE_KEPT 0      /**< representante de su grupo: es el swatch final_index */
#define CE_FATE_MERGED 1    /**< fusionado (ΔE00 < merge_de) en el swatch final_index */
#define CE_FATE_DISCARDED 2 /**< su grupo pesaba < min_weight: descartado */
#define CE_FATE_TRUNCATED 3 /**< su grupo sobrevivió al descarte pero quedó fuera
                                 del recorte a min(max_colors, cap) (extensión) */

/** Cluster de Lloyd (tras converger, antes de fusionar), en el orden de las
 *  cajas MMCQ sin los centros vacíos. */
typedef struct ce_cluster_debug {
    ce_lab lab;       /**< centro de Lloyd antes de la fusión */
    uint8_t rgb[3];   /**< Lab -> sRGB8 */
    double weight;    /**< peso del cluster / peso total (antes de fusionar y descartar); en
                       *   [0, 1]: un cluster registrado siempre tiene peso > 0, pero la división
                       *   puede DESBORDAR A CERO cuando su peso es subnormal frente al total (con
                       *   un `center_sigma` muy pequeño la gaussiana reparte pesos de 1e-302 junto a
                       *   otros de 0,5; caso del fuzz, semilla 20260916) */
    int fate;         /**< CE_FATE_* */
    int final_index;  /**< índice del swatch en la paleta devuelta (fate 0 o 1), -1 si no */
    int group_head;   /**< extensión: índice (en clusters[]) del representante de su
                           grupo de fusión (== el propio índice si no se fusionó) */
} ce_cluster_debug;

typedef struct ce_palette_debug {
    int reduced_width, reduced_height;
    int n_clusters;                                  /**< 0 con la paleta de reserva (peso total 0) */
    ce_cluster_debug clusters[CE_PALETTE_K_MAX];     /**< posiciones >= n_clusters a cero */
    int lloyd_iterations;                            /**< rondas de Lloyd con cambios de asignación */
    double total_weight;                             /**< Σ pesos de la imagen reducida */
    double zero_weight_fraction;                     /**< píxeles reducidos con peso 0 / total */
    double center_sigma_px;                          /**< sigma de la gaussiana usada (0 = uniforme) */
    int n_swatches;                                  /**< swatches devueltos por la extracción */
} ce_palette_debug;

/** Resumen de la última extracción. CE_OK, CE_ERR_ARG (punteros) o CE_ERR_CTX
 *  (contexto sin inicializar o sin extracción válida). */
int ce_palette_debug_info(const ce_ctx *ctx, ce_palette_debug *out);

/** Imagen reducida RGB8 (reduced_width*reduced_height*3 bytes). Devuelve los
 *  bytes escritos, CE_ERR_ARG (puntero nulo o cap insuficiente, sin escribir)
 *  o CE_ERR_CTX. */
int ce_debug_reduced_rgb(const ce_ctx *ctx, uint8_t *out_rgb, size_t cap);

/** Peso final por píxel reducido (máscara x gaussiana x regla de piel)
 *  escalado al máximo: v = floor(w / w_max · 255 + 0.5) (0 si w_max = 0; un
 *  peso positivo muy pequeño puede dar 0). reduced_width*reduced_height bytes.
 *  Devuelve los bytes escritos, CE_ERR_ARG o CE_ERR_CTX. */
int ce_debug_weight_map(const ce_ctx *ctx, uint8_t *out, size_t cap);

/** Índice del swatch final (orden de la paleta devuelta) al que alimenta cada
 *  píxel reducido: píxel -> bin del histograma -> centro de Lloyd -> grupo de
 *  fusión -> swatch; CE_LABEL_NONE si su peso es 0, CE_LABEL_DISCARDED si su
 *  cluster se descartó o se recortó. Devuelve los bytes escritos, CE_ERR_ARG o
 *  CE_ERR_CTX. */
int ce_debug_label_map(const ce_ctx *ctx, uint8_t *out, size_t cap);

/** Extensión: índice del cluster de Lloyd (posición en
 *  ce_palette_debug.clusters) de cada píxel reducido, o CE_LABEL_NONE si su
 *  peso es 0. Devuelve los bytes escritos, CE_ERR_ARG o CE_ERR_CTX. */
int ce_debug_cluster_map(const ce_ctx *ctx, uint8_t *out, size_t cap);

/** Paleta por prenda: índice del swatch de prenda (orden de la salida de
 *  ce_palette_extract_garments) al que alimenta cada píxel reducido, o
 *  CE_LABEL_NONE (peso 0, fuera de las regiones o grupo descartado).
 *  reduced_width*reduced_height bytes. Devuelve los bytes escritos, CE_ERR_ARG
 *  (puntero nulo o cap insuficiente) o CE_ERR_CTX (la última extracción no fue
 *  una ce_palette_extract_garments completada). Tras una extracción por prendas
 *  ce_debug_label_map da lo mismo con CE_LABEL_DISCARDED en los grupos
 *  descartados y ce_debug_cluster_map el índice en ce_palette_debug.clusters. */
int ce_debug_garment_map(const ce_ctx *ctx, uint8_t *out, size_t cap);

/** Paleta por prenda: región de cada píxel reducido tras el downscale
 *  (CE_GARMENT_REGION_UPPER/LOWER, CE_GARMENT_REGION_WHOLE si se fusionaron,
 *  CE_GARMENT_REGION_NONE sin mapa) o CE_LABEL_NONE fuera de las regiones.
 *  Mismos códigos que ce_debug_garment_map. */
int ce_debug_region_map(const ce_ctx *ctx, uint8_t *out, size_t cap);

/** Capacidad de ce_match_explain.per_color (== CE_DICT_COMBO_MAX). Misma
 *  lista de reemplazo que la definición de ce_dict_data.h (redefinición
 *  idéntica, permitida por C11 6.10.3p2). */
#define CE_DICT_MAX_COLORS 7

/** Swatch i de la paleta frente a la combinación, bajo la hipótesis ganadora. */
typedef struct ce_swatch_explain {
    int nearest_color_index; /**< índice de color del diccionario (0..158) más cercano de la
                                  combinación (empates: el primero en orden ascendente) */
    double de;               /**< su ΔE00 (kL, kC, kH de las opciones) */
} ce_swatch_explain;

/** Color j de la combinación frente a la paleta, bajo la hipótesis ganadora. */
typedef struct ce_color_explain {
    int color_index;         /**< índice de color del diccionario */
    int nearest_swatch;      /**< swatch más cercano (empates: el de índice menor) */
    double de;
} ce_color_explain;

typedef struct ce_match_explain {
    uint16_t combo_id;
    double score;              /**< bit a bit el score de ce_match para esta combinación */
    double fit_term;           /**< Σ_i w_i · min_j ΔE00 */
    double coverage_term;      /**< λ · (1/|C|) · Σ_j min_i ΔE00 */
    double hypothesis_penalty; /**< exposure_penalty·|EV| + illuminant_penalty·[X != D65] */
    double exposure_ev;        /**< EV de la hipótesis ganadora */
    int illuminant;            /**< -1 sin adaptación de iluminante, o el ce_illuminant X */
    int n_swatches;
    ce_swatch_explain per_swatch[CE_PALETTE_MAX_COLORS];
    int combo_size;
    ce_color_explain per_color[CE_DICT_MAX_COLORS];
} ce_match_explain;

/**
 * Explica el score de la combinación `combo_id` frente a los swatches `sw`:
 * recorre las mismas hipótesis en el mismo orden que ce_match, con las mismas
 * operaciones, y se queda con la primera de score mínimo. score ==
 * fit_term + coverage_term + hypothesis_penalty evaluado en ese orden (bit a
 * bit, salvo el caso inalcanzable de un score NaN, que ce_match convierte en
 * HUGE_VAL). No necesita una extracción previa (usa la caché Lab del
 * contexto). Devuelve CE_OK o, sin escribir, los errores de ce_match
 * (CE_ERR_ARG también con combo_id fuera de 1..ce_dict_num_combos()).
 */
int ce_match_explain_combo(const ce_ctx *ctx, const ce_swatch *sw, int n, const ce_match_opts *o,
                           int combo_id, ce_match_explain *out);

#ifdef __cplusplus
}
#endif

#endif /* CE_CE_H */
