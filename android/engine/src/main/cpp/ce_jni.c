/*
 * ce_jni.c — Puente JNI del motor de color (C11) para Android.
 *
 * Solo adapta tipos entre Java/Kotlin y ce/ce.h: ninguna lógica de color vive
 * aquí (ni en Kotlin). La API Kotlin (EngineNative + ColorEngine) espeja
 * engine/Sources/ColorEngine/ColorEngine.swift.
 *
 * Convenciones del puente:
 *   - Las opciones viajan como double[] (o null = valores por defecto de C):
 *       palette[9]: k_init, max_iters, max_colors, max_side, center_sigma,
 *                   merge_de, min_weight, skin_rule, merge_light_de
 *       match[9]:   kL, kC, kH, coverage_lambda, ambiguous_gap,
 *                   exposure_ev_max, exposure_penalty, illuminant_search,
 *                   illuminant_penalty
 *       garment[6]: shade_kL, shade_merge_de, lit_low_pct, lit_high_pct,
 *                   secondary_min_share, max_colors_per_region
 *       region[7]:  min_confidence, torso_margin, limb_width,
 *                   include_upper_arms, include_forearms, include_legs,
 *                   include_lower_legs
 *       skin[2]:    max_mahalanobis, max_excluded_fraction
 *   - Los swatches viajan como double[] de 4 por swatch (L, a, b, weight) y
 *     su sRGB8 como int[] de 3 por swatch (r, g, b).
 *   - Las funciones devuelven el mismo código que su equivalente en C
 *     (conteo >= 0, CE_OK = 0, CE_SKIN_GUARD = 1 o error negativo CE_ERR_*).
 *   - El contexto ce_ctx lo reserva este puente (memoria alineada a 16):
 *     el motor en sí no reserva memoria, igual que en Swift.
 */
#pragma STDC FP_CONTRACT OFF

#include <jni.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "ce/ce.h"

/* ------------------------------------------------------------------ */
/* Ayudantes de lectura de arrays                                      */
/* ------------------------------------------------------------------ */

static int dbl_len(JNIEnv *env, jdoubleArray a) {
    return (a == NULL) ? 0 : (int)(*env)->GetArrayLength(env, a);
}

static void read_doubles(JNIEnv *env, jdoubleArray a, double *dst, int n) {
    if (a == NULL || n <= 0) return;
    (*env)->GetDoubleArrayRegion(env, a, 0, n, dst);
}

static void fill_palette_opts(JNIEnv *env, jdoubleArray a, ce_palette_opts *o) {
    ce_palette_opts_default(o);
    if (dbl_len(env, a) < 9) return;
    double v[9];
    read_doubles(env, a, v, 9);
    o->k_init = (int)v[0];
    o->max_iters = (int)v[1];
    o->max_colors = (int)v[2];
    o->max_side = (int)v[3];
    o->center_sigma = v[4];
    o->merge_de = v[5];
    o->min_weight = v[6];
    o->skin_rule = (int)v[7];
    o->merge_light_de = v[8];
}

static void fill_match_opts(JNIEnv *env, jdoubleArray a, ce_match_opts *o) {
    ce_match_opts_default(o);
    if (dbl_len(env, a) < 9) return;
    double v[9];
    read_doubles(env, a, v, 9);
    o->kL = v[0];
    o->kC = v[1];
    o->kH = v[2];
    o->coverage_lambda = v[3];
    o->ambiguous_gap = v[4];
    o->exposure_ev_max = v[5];
    o->exposure_penalty = v[6];
    o->illuminant_search = (int)v[7];
    o->illuminant_penalty = v[8];
}

static void fill_garment_opts(JNIEnv *env, jdoubleArray a, ce_garment_opts *o) {
    ce_garment_opts_default(o);
    if (dbl_len(env, a) < 6) return;
    double v[6];
    read_doubles(env, a, v, 6);
    o->shade_kL = v[0];
    o->shade_merge_de = v[1];
    o->lit_low_pct = v[2];
    o->lit_high_pct = v[3];
    o->secondary_min_share = v[4];
    o->max_colors_per_region = (int)v[5];
}

static void fill_region_opts(JNIEnv *env, jdoubleArray a, ce_region_opts *o) {
    ce_region_opts_default(o);
    if (dbl_len(env, a) < 7) return;
    double v[7];
    read_doubles(env, a, v, 7);
    o->min_confidence = v[0];
    o->torso_margin = v[1];
    o->limb_width = v[2];
    o->include_upper_arms = (int)v[3];
    o->include_forearms = (int)v[4];
    o->include_legs = (int)v[5];
    o->include_lower_legs = (int)v[6];
}

static void fill_skin_opts(JNIEnv *env, jdoubleArray a, ce_skin_opts *o) {
    ce_skin_opts_default(o);
    if (dbl_len(env, a) < 2) return;
    double v[2];
    read_doubles(env, a, v, 2);
    o->max_mahalanobis = v[0];
    o->max_excluded_fraction = v[1];
}

static void write_swatches(JNIEnv *env, const ce_swatch *sw, int n,
                           jdoubleArray out_labw, jintArray out_rgb) {
    if (out_labw != NULL) {
        double buf[CE_PALETTE_MAX_COLORS * 4];
        for (int i = 0; i < n; i++) {
            buf[i * 4 + 0] = sw[i].lab.L;
            buf[i * 4 + 1] = sw[i].lab.a;
            buf[i * 4 + 2] = sw[i].lab.b;
            buf[i * 4 + 3] = sw[i].weight;
        }
        (*env)->SetDoubleArrayRegion(env, out_labw, 0, n * 4, buf);
    }
    if (out_rgb != NULL) {
        jint buf[CE_PALETTE_MAX_COLORS * 3];
        for (int i = 0; i < n; i++) {
            buf[i * 3 + 0] = sw[i].rgb[0];
            buf[i * 3 + 1] = sw[i].rgb[1];
            buf[i * 3 + 2] = sw[i].rgb[2];
        }
        (*env)->SetIntArrayRegion(env, out_rgb, 0, n * 3, buf);
    }
}

static void read_swatches(JNIEnv *env, jdoubleArray labw, int n, ce_swatch *sw) {
    double buf[CE_PALETTE_MAX_COLORS * 4];
    memset(buf, 0, sizeof buf);
    read_doubles(env, labw, buf, n * 4);
    for (int i = 0; i < n; i++) {
        sw[i].lab.L = buf[i * 4 + 0];
        sw[i].lab.a = buf[i * 4 + 1];
        sw[i].lab.b = buf[i * 4 + 2];
        sw[i].rgb[0] = 0;
        sw[i].rgb[1] = 0;
        sw[i].rgb[2] = 0;
        sw[i].weight = buf[i * 4 + 3];
    }
}

static void write_hits(JNIEnv *env, const ce_hit *hits, int n,
                       jintArray out_ids, jdoubleArray out_scores) {
    if (out_ids != NULL) {
        jint buf[CE_MATCH_MAX_HITS];
        for (int i = 0; i < n; i++) buf[i] = hits[i].combo_id;
        (*env)->SetIntArrayRegion(env, out_ids, 0, n, buf);
    }
    if (out_scores != NULL) {
        double buf[CE_MATCH_MAX_HITS];
        for (int i = 0; i < n; i++) buf[i] = hits[i].score;
        (*env)->SetDoubleArrayRegion(env, out_scores, 0, n, buf);
    }
}

typedef struct pinned_image {
    jbyte *pixels;
    jbyte *mask;
    ce_image img;
} pinned_image;

/* Fija pixels/mask (mask puede ser NULL) y rellena ce_image. 0 si pixels NULL. */
static int pin_image(JNIEnv *env, jbyteArray pixels, jint w, jint h, jint stride,
                     jint fmt, jbyteArray mask, pinned_image *out) {
    if (pixels == NULL) return 0;
    out->pixels = (*env)->GetByteArrayElements(env, pixels, NULL);
    if (out->pixels == NULL) return 0;
    out->mask = NULL;
    if (mask != NULL) {
        out->mask = (*env)->GetByteArrayElements(env, mask, NULL);
        if (out->mask == NULL) {
            (*env)->ReleaseByteArrayElements(env, pixels, out->pixels, JNI_ABORT);
            return 0;
        }
    }
    out->img.pixels = (const uint8_t *)out->pixels;
    out->img.width = w;
    out->img.height = h;
    out->img.stride_bytes = stride;
    out->img.fmt = (ce_pixel_format)fmt;
    out->img.mask = (const uint8_t *)out->mask;
    return 1;
}

static void unpin_image(JNIEnv *env, jbyteArray pixels, jbyteArray mask, pinned_image *p) {
    (*env)->ReleaseByteArrayElements(env, pixels, p->pixels, JNI_ABORT);
    if (mask != NULL && p->mask != NULL) {
        (*env)->ReleaseByteArrayElements(env, mask, p->mask, JNI_ABORT);
    }
}

/* ------------------------------------------------------------------ */
/* Versiones, diccionario y contexto                                   */
/* ------------------------------------------------------------------ */

JNIEXPORT jstring JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeVersion(JNIEnv *env, jclass clazz) {
    (void)clazz;
    return (*env)->NewStringUTF(env, ce_version());
}

JNIEXPORT jstring JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeDictVersion(JNIEnv *env, jclass clazz) {
    (void)clazz;
    return (*env)->NewStringUTF(env, ce_dict_version());
}

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeDictNumColors(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    return ce_dict_num_colors();
}

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeDictNumCombos(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    return ce_dict_num_combos();
}

JNIEXPORT jlong JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeContextSize(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    return (jlong)ce_ctx_size();
}

/* Reserva memoria alineada a 16 sin depender de aligned_alloc (API 28+). */
JNIEXPORT jlong JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeCreateContext(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    size_t size = ce_ctx_size();
    size_t total = size + 16u + sizeof(void *);
    void *raw = malloc(total);
    if (raw == NULL) return 0;
    uintptr_t addr = ((uintptr_t)raw + sizeof(void *) + 15u) & ~(uintptr_t)15u;
    void *mem = (void *)addr;
    ((void **)mem)[-1] = raw;
    ce_ctx *ctx = ce_ctx_init(mem, size);
    if (ctx == NULL) {
        free(raw);
        return 0;
    }
    return (jlong)(uintptr_t)ctx;
}

JNIEXPORT void JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeDestroyContext(JNIEnv *env, jclass clazz,
                                                                       jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0) return;
    void *mem = (void *)(uintptr_t)handle;
    free(((void **)mem)[-1]);
}

/* Valores por defecto de todas las opciones, en el orden documentado arriba. */
#define NATIVE_DEFAULTS_COUNT 33
JNIEXPORT jdoubleArray JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeDefaults(JNIEnv *env, jclass clazz) {
    (void)clazz;
    ce_palette_opts po;
    ce_match_opts mo;
    ce_garment_opts go;
    ce_region_opts ro;
    ce_skin_opts so;
    ce_palette_opts_default(&po);
    ce_match_opts_default(&mo);
    ce_garment_opts_default(&go);
    ce_region_opts_default(&ro);
    ce_skin_opts_default(&so);
    double v[NATIVE_DEFAULTS_COUNT] = {
        (double)po.k_init, (double)po.max_iters, (double)po.max_colors, (double)po.max_side,
        po.center_sigma, po.merge_de, po.min_weight, (double)po.skin_rule, po.merge_light_de,
        mo.kL, mo.kC, mo.kH, mo.coverage_lambda, mo.ambiguous_gap,
        mo.exposure_ev_max, mo.exposure_penalty, (double)mo.illuminant_search, mo.illuminant_penalty,
        go.shade_kL, go.shade_merge_de, go.lit_low_pct, go.lit_high_pct,
        go.secondary_min_share, (double)go.max_colors_per_region,
        ro.min_confidence, ro.torso_margin, ro.limb_width,
        (double)ro.include_upper_arms, (double)ro.include_forearms,
        (double)ro.include_legs, (double)ro.include_lower_legs,
        so.max_mahalanobis, so.max_excluded_fraction,
    };
    jdoubleArray out = (*env)->NewDoubleArray(env, NATIVE_DEFAULTS_COUNT);
    if (out != NULL) (*env)->SetDoubleArrayRegion(env, out, 0, NATIVE_DEFAULTS_COUNT, v);
    return out;
}

/* ------------------------------------------------------------------ */
/* Matemática de color y diccionario (sin contexto salvo donde se dice) */
/* ------------------------------------------------------------------ */

JNIEXPORT jdoubleArray JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeSrgb8ToLab(JNIEnv *env, jclass clazz,
                                                                   jint r, jint g, jint b) {
    (void)clazz;
    ce_lab lab = ce_srgb8_to_lab((uint8_t)r, (uint8_t)g, (uint8_t)b);
    double v[3] = {lab.L, lab.a, lab.b};
    jdoubleArray out = (*env)->NewDoubleArray(env, 3);
    if (out != NULL) (*env)->SetDoubleArrayRegion(env, out, 0, 3, v);
    return out;
}

JNIEXPORT jintArray JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeLabToSrgb8(JNIEnv *env, jclass clazz,
                                                                   jdouble l, jdouble a, jdouble b) {
    (void)clazz;
    ce_lab lab = {l, a, b};
    uint8_t rgb[3];
    ce_lab_to_srgb8(lab, &rgb[0], &rgb[1], &rgb[2]);
    jint v[3] = {rgb[0], rgb[1], rgb[2]};
    jintArray out = (*env)->NewIntArray(env, 3);
    if (out != NULL) (*env)->SetIntArrayRegion(env, out, 0, 3, v);
    return out;
}

JNIEXPORT jdouble JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeDe2000(JNIEnv *env, jclass clazz,
                                                               jdouble l1, jdouble a1, jdouble b1,
                                                               jdouble l2, jdouble a2, jdouble b2) {
    (void)env;
    (void)clazz;
    ce_lab x = {l1, a1, b1};
    ce_lab y = {l2, a2, b2};
    return ce_de2000(x, y);
}

JNIEXPORT jdouble JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeDe2000K(JNIEnv *env, jclass clazz,
                                                                jdouble l1, jdouble a1, jdouble b1,
                                                                jdouble l2, jdouble a2, jdouble b2,
                                                                jdouble kl, jdouble kc, jdouble kh) {
    (void)env;
    (void)clazz;
    ce_lab x = {l1, a1, b1};
    ce_lab y = {l2, a2, b2};
    return ce_de2000_k(x, y, kl, kc, kh);
}

JNIEXPORT jdouble JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeDe76(JNIEnv *env, jclass clazz,
                                                             jdouble l1, jdouble a1, jdouble b1,
                                                             jdouble l2, jdouble a2, jdouble b2) {
    (void)env;
    (void)clazz;
    ce_lab x = {l1, a1, b1};
    ce_lab y = {l2, a2, b2};
    return ce_de76(x, y);
}

JNIEXPORT jintArray JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeDictColorRgb(JNIEnv *env, jclass clazz,
                                                                     jint index) {
    (void)clazz;
    uint8_t rgb[3];
    if (ce_dict_color_rgb(index, rgb) != 0) return (*env)->NewIntArray(env, 0);
    jint v[3] = {rgb[0], rgb[1], rgb[2]};
    jintArray out = (*env)->NewIntArray(env, 3);
    if (out != NULL) (*env)->SetIntArrayRegion(env, out, 0, 3, v);
    return out;
}

JNIEXPORT jstring JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeDictColorName(JNIEnv *env, jclass clazz,
                                                                      jint index) {
    (void)clazz;
    const char *name = ce_dict_color_name(index);
    return (name == NULL) ? NULL : (*env)->NewStringUTF(env, name);
}

JNIEXPORT jdoubleArray JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeDictColorLab(JNIEnv *env, jclass clazz,
                                                                     jint index) {
    (void)clazz;
    ce_lab lab = ce_dict_color_lab(index);
    double v[3] = {lab.L, lab.a, lab.b};
    jdoubleArray out = (*env)->NewDoubleArray(env, 3);
    if (out != NULL) (*env)->SetDoubleArrayRegion(env, out, 0, 3, v);
    return out;
}

JNIEXPORT jintArray JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeDictCombo(JNIEnv *env, jclass clazz,
                                                                  jint id) {
    (void)clazz;
    uint8_t size = 0;
    uint8_t colors[CE_DICT_COMBO_MAX];
    if (ce_dict_combo(id, &size, colors) != 0) return (*env)->NewIntArray(env, 0);
    jint v[CE_DICT_COMBO_MAX];
    for (int i = 0; i < size; i++) v[i] = colors[i];
    jintArray out = (*env)->NewIntArray(env, size);
    if (out != NULL) (*env)->SetIntArrayRegion(env, out, 0, size, v);
    return out;
}

JNIEXPORT jdoubleArray JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeNearestColor(JNIEnv *env, jclass clazz,
                                                                     jdouble l, jdouble a, jdouble b) {
    (void)clazz;
    ce_lab lab = {l, a, b};
    double de = 0.0;
    int idx = ce_dict_nearest_color(lab, &de);
    double v[2] = {(double)idx, de};
    jdoubleArray out = (*env)->NewDoubleArray(env, 2);
    if (out != NULL) (*env)->SetDoubleArrayRegion(env, out, 0, 2, v);
    return out;
}

JNIEXPORT jintArray JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeReducedDims(JNIEnv *env, jclass clazz,
                                                                    jint w, jint h, jint max_side) {
    (void)clazz;
    int rw = 0;
    int rh = 0;
    if (ce_reduced_dims(w, h, max_side, &rw, &rh) != CE_OK) return (*env)->NewIntArray(env, 0);
    jint v[2] = {rw, rh};
    jintArray out = (*env)->NewIntArray(env, 2);
    if (out != NULL) (*env)->SetIntArrayRegion(env, out, 0, 2, v);
    return out;
}

/* ------------------------------------------------------------------ */
/* Paleta, match y análisis                                            */
/* ------------------------------------------------------------------ */

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeExtractPalette(
    JNIEnv *env, jclass clazz, jlong handle, jbyteArray pixels, jint w, jint h, jint stride,
    jint fmt, jbyteArray mask, jdoubleArray palette_opts, jdoubleArray out_labw, jintArray out_rgb) {
    (void)clazz;
    pinned_image p;
    if (handle == 0 || !pin_image(env, pixels, w, h, stride, fmt, mask, &p)) return CE_ERR_ARG;
    ce_palette_opts po;
    fill_palette_opts(env, palette_opts, &po);
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    int n = ce_palette_extract((ce_ctx *)(uintptr_t)handle, &p.img, &po, sw, CE_PALETTE_MAX_COLORS);
    unpin_image(env, pixels, mask, &p);
    if (n >= 0) write_swatches(env, sw, n, out_labw, out_rgb);
    return n;
}

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeMatch(
    JNIEnv *env, jclass clazz, jlong handle, jdoubleArray sw_labw, jint n_sw,
    jdoubleArray match_opts, jint top_k, jintArray out_ids, jdoubleArray out_scores,
    jintArray out_meta) {
    (void)clazz;
    if (handle == 0 || n_sw < 1 || n_sw > CE_PALETTE_MAX_COLORS) return CE_ERR_ARG;
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    read_swatches(env, sw_labw, n_sw, sw);
    ce_match_opts mo;
    fill_match_opts(env, match_opts, &mo);
    ce_hit hits[CE_MATCH_MAX_HITS];
    int ambiguous = 0;
    int n = ce_match((const ce_ctx *)(uintptr_t)handle, sw, n_sw, &mo, hits, top_k, &ambiguous);
    if (n >= 0) {
        write_hits(env, hits, n, out_ids, out_scores);
        if (out_meta != NULL) {
            jint meta[1] = {ambiguous};
            (*env)->SetIntArrayRegion(env, out_meta, 0, 1, meta);
        }
    }
    return n;
}

static void write_result(JNIEnv *env, const ce_result *r, jdoubleArray out_labw, jintArray out_rgb,
                         jintArray out_ids, jdoubleArray out_scores, jintArray out_meta,
                         jlongArray out_hash) {
    write_swatches(env, r->swatches, r->n_swatches, out_labw, out_rgb);
    write_hits(env, r->hits, r->n_hits, out_ids, out_scores);
    if (out_meta != NULL) {
        jint meta[3] = {r->n_swatches, r->n_hits, r->ambiguous};
        (*env)->SetIntArrayRegion(env, out_meta, 0, 3, meta);
    }
    if (out_hash != NULL) {
        uint64_t hash = ce_result_hash(r);
        jlong v[1] = {(jlong)hash};
        (*env)->SetLongArrayRegion(env, out_hash, 0, 1, v);
    }
}

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeAnalyze(
    JNIEnv *env, jclass clazz, jlong handle, jbyteArray pixels, jint w, jint h, jint stride,
    jint fmt, jbyteArray mask, jdoubleArray palette_opts, jdoubleArray match_opts,
    jdoubleArray out_labw, jintArray out_rgb, jintArray out_ids, jdoubleArray out_scores,
    jintArray out_meta, jlongArray out_hash) {
    (void)clazz;
    pinned_image p;
    if (handle == 0 || !pin_image(env, pixels, w, h, stride, fmt, mask, &p)) return CE_ERR_ARG;
    ce_palette_opts po;
    ce_match_opts mo;
    fill_palette_opts(env, palette_opts, &po);
    fill_match_opts(env, match_opts, &mo);
    ce_result r;
    int n = ce_analyze((ce_ctx *)(uintptr_t)handle, &p.img, &po, &mo, &r);
    unpin_image(env, pixels, mask, &p);
    if (n >= 0) write_result(env, &r, out_labw, out_rgb, out_ids, out_scores, out_meta, out_hash);
    return n;
}

static void write_garments(JNIEnv *env, const ce_garment_swatch *g, int n,
                           jdoubleArray out_labw, jintArray out_rgb,
                           jdoubleArray out_share, jintArray out_ints) {
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    for (int i = 0; i < n; i++) sw[i] = g[i].swatch;
    write_swatches(env, sw, n, out_labw, out_rgb);
    if (out_share != NULL) {
        double buf[CE_PALETTE_MAX_COLORS];
        for (int i = 0; i < n; i++) buf[i] = g[i].region_share;
        (*env)->SetDoubleArrayRegion(env, out_share, 0, n, buf);
    }
    if (out_ints != NULL) {
        jint buf[CE_PALETTE_MAX_COLORS * 2];
        for (int i = 0; i < n; i++) {
            buf[i * 2 + 0] = g[i].region;
            buf[i * 2 + 1] = g[i].n_merged_clusters;
        }
        (*env)->SetIntArrayRegion(env, out_ints, 0, n * 2, buf);
    }
}

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeExtractGarments(
    JNIEnv *env, jclass clazz, jlong handle, jbyteArray pixels, jint w, jint h, jint stride,
    jint fmt, jbyteArray mask, jbyteArray region_map, jint n_regions, jdoubleArray palette_opts,
    jdoubleArray garment_opts, jdoubleArray out_labw, jintArray out_rgb,
    jdoubleArray out_share, jintArray out_ints) {
    (void)clazz;
    pinned_image p;
    if (handle == 0 || !pin_image(env, pixels, w, h, stride, fmt, mask, &p)) return CE_ERR_ARG;
    jbyte *regions = NULL;
    if (region_map != NULL) {
        regions = (*env)->GetByteArrayElements(env, region_map, NULL);
        if (regions == NULL) {
            unpin_image(env, pixels, mask, &p);
            return CE_ERR_ARG;
        }
    }
    ce_palette_opts po;
    ce_garment_opts go;
    fill_palette_opts(env, palette_opts, &po);
    fill_garment_opts(env, garment_opts, &go);
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    int n = ce_palette_extract_garments((ce_ctx *)(uintptr_t)handle, &p.img,
                                        (const uint8_t *)regions, n_regions, &po, &go, g,
                                        CE_PALETTE_MAX_COLORS);
    if (region_map != NULL) (*env)->ReleaseByteArrayElements(env, region_map, regions, JNI_ABORT);
    unpin_image(env, pixels, mask, &p);
    if (n >= 0) write_garments(env, g, n, out_labw, out_rgb, out_share, out_ints);
    return n;
}

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeAnalyzeGarments(
    JNIEnv *env, jclass clazz, jlong handle, jbyteArray pixels, jint w, jint h, jint stride,
    jint fmt, jbyteArray mask, jbyteArray region_map, jint n_regions, jdoubleArray palette_opts,
    jdoubleArray garment_opts, jdoubleArray match_opts, jdoubleArray out_labw, jintArray out_rgb,
    jdoubleArray out_share, jintArray out_ints, jintArray out_ids, jdoubleArray out_scores,
    jintArray out_meta, jlongArray out_hash) {
    (void)clazz;
    pinned_image p;
    if (handle == 0 || !pin_image(env, pixels, w, h, stride, fmt, mask, &p)) return CE_ERR_ARG;
    jbyte *regions = NULL;
    if (region_map != NULL) {
        regions = (*env)->GetByteArrayElements(env, region_map, NULL);
        if (regions == NULL) {
            unpin_image(env, pixels, mask, &p);
            return CE_ERR_ARG;
        }
    }
    ce_palette_opts po;
    ce_garment_opts go;
    ce_match_opts mo;
    fill_palette_opts(env, palette_opts, &po);
    fill_garment_opts(env, garment_opts, &go);
    fill_match_opts(env, match_opts, &mo);
    ce_result r;
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    int n = ce_analyze_garments((ce_ctx *)(uintptr_t)handle, &p.img, (const uint8_t *)regions,
                                n_regions, &po, &go, &mo, &r, g, CE_PALETTE_MAX_COLORS);
    if (region_map != NULL) (*env)->ReleaseByteArrayElements(env, region_map, regions, JNI_ABORT);
    unpin_image(env, pixels, mask, &p);
    if (n >= 0) {
        write_garments(env, g, r.n_swatches, out_labw, out_rgb, out_share, out_ints);
        write_hits(env, r.hits, r.n_hits, out_ids, out_scores);
        if (out_meta != NULL) {
            jint meta[3] = {r.n_swatches, r.n_hits, r.ambiguous};
            (*env)->SetIntArrayRegion(env, out_meta, 0, 3, meta);
        }
        if (out_hash != NULL) {
            uint64_t hash = ce_result_hash(&r);
            jlong v[1] = {(jlong)hash};
            (*env)->SetLongArrayRegion(env, out_hash, 0, 1, v);
        }
    }
    return n;
}

/* ------------------------------------------------------------------ */
/* Explicación del match y capas de depuración                         */
/* ------------------------------------------------------------------ */

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeExplain(
    JNIEnv *env, jclass clazz, jlong handle, jdoubleArray sw_labw, jint n_sw,
    jdoubleArray match_opts, jint combo_id, jdoubleArray out_main, jintArray out_ints,
    jintArray out_ps_idx, jdoubleArray out_ps_de, jintArray out_pc_idx,
    jintArray out_pc_sw, jdoubleArray out_pc_de) {
    (void)clazz;
    if (handle == 0 || n_sw < 1 || n_sw > CE_PALETTE_MAX_COLORS) return CE_ERR_ARG;
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    read_swatches(env, sw_labw, n_sw, sw);
    ce_match_opts mo;
    fill_match_opts(env, match_opts, &mo);
    ce_match_explain ex;
    int rc = ce_match_explain_combo((const ce_ctx *)(uintptr_t)handle, sw, n_sw, &mo,
                                    combo_id, &ex);
    if (rc != CE_OK) return rc;
    if (out_main != NULL) {
        double v[5] = {ex.score, ex.fit_term, ex.coverage_term, ex.hypothesis_penalty,
                       ex.exposure_ev};
        (*env)->SetDoubleArrayRegion(env, out_main, 0, 5, v);
    }
    if (out_ints != NULL) {
        jint v[3] = {ex.illuminant, ex.n_swatches, ex.combo_size};
        (*env)->SetIntArrayRegion(env, out_ints, 0, 3, v);
    }
    if (out_ps_idx != NULL) {
        jint v[CE_PALETTE_MAX_COLORS];
        for (int i = 0; i < ex.n_swatches; i++) v[i] = ex.per_swatch[i].nearest_color_index;
        (*env)->SetIntArrayRegion(env, out_ps_idx, 0, ex.n_swatches, v);
    }
    if (out_ps_de != NULL) {
        double v[CE_PALETTE_MAX_COLORS];
        for (int i = 0; i < ex.n_swatches; i++) v[i] = ex.per_swatch[i].de;
        (*env)->SetDoubleArrayRegion(env, out_ps_de, 0, ex.n_swatches, v);
    }
    if (out_pc_idx != NULL) {
        jint v[CE_DICT_MAX_COLORS];
        for (int i = 0; i < ex.combo_size; i++) v[i] = ex.per_color[i].color_index;
        (*env)->SetIntArrayRegion(env, out_pc_idx, 0, ex.combo_size, v);
    }
    if (out_pc_sw != NULL) {
        jint v[CE_DICT_MAX_COLORS];
        for (int i = 0; i < ex.combo_size; i++) v[i] = ex.per_color[i].nearest_swatch;
        (*env)->SetIntArrayRegion(env, out_pc_sw, 0, ex.combo_size, v);
    }
    if (out_pc_de != NULL) {
        double v[CE_DICT_MAX_COLORS];
        for (int i = 0; i < ex.combo_size; i++) v[i] = ex.per_color[i].de;
        (*env)->SetDoubleArrayRegion(env, out_pc_de, 0, ex.combo_size, v);
    }
    return CE_OK;
}

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativePaletteDebugInfo(
    JNIEnv *env, jclass clazz, jlong handle, jintArray out_ints, jdoubleArray out_dbls,
    jdoubleArray out_cl_labw, jintArray out_cl_rgb, jintArray out_cl_ints) {
    (void)clazz;
    if (handle == 0) return CE_ERR_ARG;
    ce_palette_debug d;
    int rc = ce_palette_debug_info((const ce_ctx *)(uintptr_t)handle, &d);
    if (rc != CE_OK) return rc;
    if (out_ints != NULL) {
        jint v[5] = {d.reduced_width, d.reduced_height, d.n_clusters, d.lloyd_iterations,
                     d.n_swatches};
        (*env)->SetIntArrayRegion(env, out_ints, 0, 5, v);
    }
    if (out_dbls != NULL) {
        double v[3] = {d.total_weight, d.zero_weight_fraction, d.center_sigma_px};
        (*env)->SetDoubleArrayRegion(env, out_dbls, 0, 3, v);
    }
    if (out_cl_labw != NULL) {
        double v[CE_PALETTE_K_MAX * 4];
        for (int i = 0; i < d.n_clusters; i++) {
            v[i * 4 + 0] = d.clusters[i].lab.L;
            v[i * 4 + 1] = d.clusters[i].lab.a;
            v[i * 4 + 2] = d.clusters[i].lab.b;
            v[i * 4 + 3] = d.clusters[i].weight;
        }
        (*env)->SetDoubleArrayRegion(env, out_cl_labw, 0, d.n_clusters * 4, v);
    }
    if (out_cl_rgb != NULL) {
        jint v[CE_PALETTE_K_MAX * 3];
        for (int i = 0; i < d.n_clusters; i++) {
            v[i * 3 + 0] = d.clusters[i].rgb[0];
            v[i * 3 + 1] = d.clusters[i].rgb[1];
            v[i * 3 + 2] = d.clusters[i].rgb[2];
        }
        (*env)->SetIntArrayRegion(env, out_cl_rgb, 0, d.n_clusters * 3, v);
    }
    if (out_cl_ints != NULL) {
        jint v[CE_PALETTE_K_MAX * 3];
        for (int i = 0; i < d.n_clusters; i++) {
            v[i * 3 + 0] = d.clusters[i].fate;
            v[i * 3 + 1] = d.clusters[i].final_index;
            v[i * 3 + 2] = d.clusters[i].group_head;
        }
        (*env)->SetIntArrayRegion(env, out_cl_ints, 0, d.n_clusters * 3, v);
    }
    return CE_OK;
}

/* kind: 0 reduced_rgb, 1 weight, 2 label, 3 cluster, 4 garment, 5 region. */
JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeDebugMap(JNIEnv *env, jclass clazz,
                                                                 jlong handle, jint kind,
                                                                 jbyteArray out) {
    (void)clazz;
    if (handle == 0 || out == NULL) return CE_ERR_ARG;
    const ce_ctx *ctx = (const ce_ctx *)(uintptr_t)handle;
    size_t cap = (size_t)(*env)->GetArrayLength(env, out);
    jbyte *buf = (*env)->GetByteArrayElements(env, out, NULL);
    if (buf == NULL) return CE_ERR_ARG;
    int n;
    switch (kind) {
        case 0: n = ce_debug_reduced_rgb(ctx, (uint8_t *)buf, cap); break;
        case 1: n = ce_debug_weight_map(ctx, (uint8_t *)buf, cap); break;
        case 2: n = ce_debug_label_map(ctx, (uint8_t *)buf, cap); break;
        case 3: n = ce_debug_cluster_map(ctx, (uint8_t *)buf, cap); break;
        case 4: n = ce_debug_garment_map(ctx, (uint8_t *)buf, cap); break;
        case 5: n = ce_debug_region_map(ctx, (uint8_t *)buf, cap); break;
        default: n = CE_ERR_ARG; break;
    }
    (*env)->ReleaseByteArrayElements(env, out, buf, (n >= 0) ? 0 : JNI_ABORT);
    return n;
}

/* ------------------------------------------------------------------ */
/* Máscaras: pose, piel y separación de instancias                     */
/* ------------------------------------------------------------------ */

static void read_pose(JNIEnv *env, jdoubleArray a, ce_pose *pose) {
    double v[CE_JOINT_COUNT * 3];
    memset(v, 0, sizeof v);
    int n = dbl_len(env, a);
    if (n > CE_JOINT_COUNT * 3) n = CE_JOINT_COUNT * 3;
    read_doubles(env, a, v, n);
    for (int i = 0; i < CE_JOINT_COUNT; i++) {
        pose->k[i].x = v[i * 3 + 0];
        pose->k[i].y = v[i * 3 + 1];
        pose->k[i].confidence = v[i * 3 + 2];
    }
}

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeClothingRegions(
    JNIEnv *env, jclass clazz, jdoubleArray pose_arr, jdoubleArray region_opts,
    jbyteArray mask, jint w, jint h) {
    (void)clazz;
    if (mask == NULL) return CE_ERR_ARG;
    ce_pose pose;
    read_pose(env, pose_arr, &pose);
    ce_region_opts ro;
    fill_region_opts(env, region_opts, &ro);
    jbyte *m = (*env)->GetByteArrayElements(env, mask, NULL);
    if (m == NULL) return CE_ERR_ARG;
    int n = ce_mask_clothing_regions(&pose, &ro, (uint8_t *)m, w, h);
    (*env)->ReleaseByteArrayElements(env, mask, m, (n >= 0) ? 0 : JNI_ABORT);
    return n;
}

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeGarmentRegions(
    JNIEnv *env, jclass clazz, jdoubleArray pose_arr, jdoubleArray region_opts,
    jbyteArray person_mask, jint w, jint h, jbyteArray regions_out) {
    (void)clazz;
    if (person_mask == NULL || regions_out == NULL) return CE_ERR_ARG;
    ce_pose pose;
    read_pose(env, pose_arr, &pose);
    ce_region_opts ro;
    fill_region_opts(env, region_opts, &ro);
    jbyte *pm = (*env)->GetByteArrayElements(env, person_mask, NULL);
    if (pm == NULL) return CE_ERR_ARG;
    jbyte *rm = (*env)->GetByteArrayElements(env, regions_out, NULL);
    if (rm == NULL) {
        (*env)->ReleaseByteArrayElements(env, person_mask, pm, JNI_ABORT);
        return CE_ERR_ARG;
    }
    int n = ce_mask_garment_regions(&pose, &ro, (const uint8_t *)pm, w, h, (uint8_t *)rm);
    (*env)->ReleaseByteArrayElements(env, regions_out, rm, (n >= 0) ? 0 : JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, person_mask, pm, JNI_ABORT);
    return n;
}

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeCutHead(JNIEnv *env, jclass clazz,
                                                                jbyteArray mask, jint w, jint h,
                                                                jdouble fraction) {
    (void)clazz;
    if (mask == NULL) return CE_ERR_ARG;
    jbyte *m = (*env)->GetByteArrayElements(env, mask, NULL);
    if (m == NULL) return CE_ERR_ARG;
    int n = ce_mask_cut_head((uint8_t *)m, w, h, fraction);
    (*env)->ReleaseByteArrayElements(env, mask, m, (n >= 0) ? 0 : JNI_ABORT);
    return n;
}

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeSkinFit(
    JNIEnv *env, jclass clazz, jbyteArray pixels, jint w, jint h, jint stride, jint fmt,
    jbyteArray sample_mask, jdoubleArray out_model, jintArray out_n) {
    (void)clazz;
    pinned_image p;
    if (!pin_image(env, pixels, w, h, stride, fmt, NULL, &p)) return CE_ERR_ARG;
    if (sample_mask == NULL) {
        unpin_image(env, pixels, NULL, &p);
        return CE_ERR_ARG;
    }
    jbyte *sm = (*env)->GetByteArrayElements(env, sample_mask, NULL);
    if (sm == NULL) {
        unpin_image(env, pixels, NULL, &p);
        return CE_ERR_ARG;
    }
    ce_skin_model model;
    int rc = ce_skin_model_fit(&p.img, (const uint8_t *)sm, &model);
    (*env)->ReleaseByteArrayElements(env, sample_mask, sm, JNI_ABORT);
    unpin_image(env, pixels, NULL, &p);
    if (rc != CE_OK) return rc;
    if (out_model != NULL) {
        double v[21];
        v[0] = model.mean.L;
        v[1] = model.mean.a;
        v[2] = model.mean.b;
        memcpy(&v[3], model.cov, sizeof model.cov);
        memcpy(&v[12], model.inv_cov, sizeof model.inv_cov);
        (*env)->SetDoubleArrayRegion(env, out_model, 0, 21, v);
    }
    if (out_n != NULL) {
        jint v[1] = {model.n};
        (*env)->SetIntArrayRegion(env, out_n, 0, 1, v);
    }
    return CE_OK;
}

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeExcludeSkin(
    JNIEnv *env, jclass clazz, jbyteArray pixels, jint w, jint h, jint stride, jint fmt,
    jdoubleArray model_arr, jint model_n, jdoubleArray skin_opts, jbyteArray mask) {
    (void)clazz;
    pinned_image p;
    if (!pin_image(env, pixels, w, h, stride, fmt, NULL, &p)) return CE_ERR_ARG;
    if (mask == NULL || dbl_len(env, model_arr) < 21) {
        unpin_image(env, pixels, NULL, &p);
        return CE_ERR_ARG;
    }
    double v[21];
    read_doubles(env, model_arr, v, 21);
    ce_skin_model model;
    model.mean.L = v[0];
    model.mean.a = v[1];
    model.mean.b = v[2];
    memcpy(model.cov, &v[3], sizeof model.cov);
    memcpy(model.inv_cov, &v[12], sizeof model.inv_cov);
    model.n = model_n;
    ce_skin_opts so;
    fill_skin_opts(env, skin_opts, &so);
    jbyte *m = (*env)->GetByteArrayElements(env, mask, NULL);
    if (m == NULL) {
        unpin_image(env, pixels, NULL, &p);
        return CE_ERR_ARG;
    }
    int rc = ce_mask_exclude_skin(&p.img, &model, &so, (uint8_t *)m);
    (*env)->ReleaseByteArrayElements(env, mask, m, (rc >= 0) ? 0 : JNI_ABORT);
    unpin_image(env, pixels, NULL, &p);
    return rc;
}

JNIEXPORT jint JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeSplitInstance(
    JNIEnv *env, jclass clazz, jbyteArray mask, jint w, jint h, jdoubleArray seeds_arr,
    jint n_seeds, jbyteArray labels_out) {
    (void)clazz;
    if (mask == NULL || labels_out == NULL || n_seeds < 1 || n_seeds > CE_SPLIT_MAX_SEEDS) {
        return CE_ERR_ARG;
    }
    double v[CE_SPLIT_MAX_SEEDS * 5];
    memset(v, 0, sizeof v);
    read_doubles(env, seeds_arr, v, n_seeds * 5);
    ce_person_seed seeds[CE_SPLIT_MAX_SEEDS];
    for (int i = 0; i < n_seeds; i++) {
        seeds[i].x0 = v[i * 5 + 0];
        seeds[i].y0 = v[i * 5 + 1];
        seeds[i].x1 = v[i * 5 + 2];
        seeds[i].y1 = v[i * 5 + 3];
        seeds[i].half_width = v[i * 5 + 4];
    }
    jbyte *m = (*env)->GetByteArrayElements(env, mask, NULL);
    if (m == NULL) return CE_ERR_ARG;
    jbyte *lb = (*env)->GetByteArrayElements(env, labels_out, NULL);
    if (lb == NULL) {
        (*env)->ReleaseByteArrayElements(env, mask, m, JNI_ABORT);
        return CE_ERR_ARG;
    }
    int n = ce_mask_split_instance((const uint8_t *)m, w, h, seeds, n_seeds, (uint8_t *)lb);
    (*env)->ReleaseByteArrayElements(env, labels_out, lb, (n >= 0) ? 0 : JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, mask, m, JNI_ABORT);
    return n;
}

/* ------------------------------------------------------------------ */
/* Hashes FNV-1a (comparables entre plataformas)                       */
/* ------------------------------------------------------------------ */

JNIEXPORT jlong JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeSwatchHash(JNIEnv *env, jclass clazz,
                                                                   jdoubleArray sw_labw,
                                                                   jint n_sw) {
    (void)clazz;
    if (n_sw < 0 || n_sw > CE_PALETTE_MAX_COLORS) return 0;
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    read_swatches(env, sw_labw, n_sw, sw);
    return (jlong)ce_swatch_hash(sw, n_sw);
}

JNIEXPORT jlong JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeGarmentHash(
    JNIEnv *env, jclass clazz, jdoubleArray sw_labw, jdoubleArray share, jintArray ints,
    jint n_sw) {
    (void)clazz;
    if (n_sw < 0 || n_sw > CE_PALETTE_MAX_COLORS) return 0;
    ce_garment_swatch g[CE_PALETTE_MAX_COLORS];
    ce_swatch sw[CE_PALETTE_MAX_COLORS];
    read_swatches(env, sw_labw, n_sw, sw);
    double sh[CE_PALETTE_MAX_COLORS];
    memset(sh, 0, sizeof sh);
    read_doubles(env, share, sh, n_sw);
    jint iv[CE_PALETTE_MAX_COLORS * 2];
    memset(iv, 0, sizeof iv);
    if (ints != NULL) (*env)->GetIntArrayRegion(env, ints, 0, n_sw * 2, iv);
    for (int i = 0; i < n_sw; i++) {
        g[i].swatch = sw[i];
        g[i].region_share = sh[i];
        g[i].region = iv[i * 2 + 0];
        g[i].n_merged_clusters = iv[i * 2 + 1];
    }
    return (jlong)ce_garment_hash(g, n_sw);
}

JNIEXPORT jlong JNICALL
Java_com_andreseloy_colorsapp_engine_EngineNative_nativeResultHash(
    JNIEnv *env, jclass clazz, jdoubleArray sw_labw, jint n_sw, jintArray hit_ids,
    jdoubleArray hit_scores, jint n_hits, jint ambiguous) {
    (void)clazz;
    if (n_sw < 0 || n_sw > CE_PALETTE_MAX_COLORS || n_hits < 0 || n_hits > CE_MATCH_MAX_HITS) {
        return 0;
    }
    ce_result r;
    memset(&r, 0, sizeof r);
    read_swatches(env, sw_labw, n_sw, r.swatches);
    r.n_swatches = n_sw;
    jint ids[CE_MATCH_MAX_HITS];
    memset(ids, 0, sizeof ids);
    if (hit_ids != NULL) (*env)->GetIntArrayRegion(env, hit_ids, 0, n_hits, ids);
    double scores[CE_MATCH_MAX_HITS];
    memset(scores, 0, sizeof scores);
    read_doubles(env, hit_scores, scores, n_hits);
    for (int i = 0; i < n_hits; i++) {
        r.hits[i].combo_id = (uint16_t)ids[i];
        r.hits[i].score = scores[i];
    }
    r.n_hits = n_hits;
    r.ambiguous = ambiguous;
    return (jlong)ce_result_hash(&r);
}
