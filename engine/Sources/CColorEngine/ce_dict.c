/*
 * ce_dict.c — diccionario de Sanzo Wada embebido (accesores de solo lectura).
 *
 * Único TU que incluye ce_dict_data.h (generado por oracle.build_dictionary,
 * `make dict`). Reglas del motor: C11, sin I/O, sin malloc, sin estáticos
 * mutables; las tablas son `static const`. El Lab de cada color se calcula con
 * ce_srgb8_to_lab, la misma función que procesa la foto, para que diccionario
 * y entrada compartan bits en cada plataforma (nativo y WASM).
 *
 * La versión del diccionario (CE_DICT_VERSION) es el sha256 corto del JSON
 * canónico de colores + combinaciones; la app la cruza con el `dict_version`
 * de dictionary.json del bundle.
 */
#include "ce/ce.h"
#include "ce_dict_data.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>

#pragma STDC FP_CONTRACT OFF

/* Las constantes públicas de ce.h deben coincidir con las del header generado. */
_Static_assert(CE_DICT_COMBO_MAX == CE_DICT_MAX_COLORS,
               "CE_DICT_COMBO_MAX (ce.h) debe ser igual a CE_DICT_MAX_COLORS (ce_dict_data.h)");
_Static_assert(CE_DICT_NO_COLOR == CE_DICT_NONE,
               "CE_DICT_NO_COLOR (ce.h) debe ser igual a CE_DICT_NONE (ce_dict_data.h)");
_Static_assert(sizeof(ce_dict_data_rgb) / sizeof(ce_dict_data_rgb[0]) == CE_DICT_NUM_COLORS,
               "tabla rgb con tamano inesperado");
_Static_assert(sizeof(ce_dict_data_names) / sizeof(ce_dict_data_names[0]) == CE_DICT_NUM_COLORS,
               "tabla de nombres con tamano inesperado");
_Static_assert(sizeof(ce_dict_data_swatch) / sizeof(ce_dict_data_swatch[0]) == CE_DICT_NUM_COLORS,
               "tabla swatch con tamano inesperado");
_Static_assert(sizeof(ce_dict_data_combos) / sizeof(ce_dict_data_combos[0]) == CE_DICT_NUM_COMBOS,
               "tabla de combinaciones con tamano inesperado");
_Static_assert(CE_DICT_NUM_COLORS < CE_DICT_NONE, "los indices de color deben caber en uint8_t sin chocar con CE_DICT_NONE");

const char *ce_dict_version(void)
{
    return CE_DICT_VERSION;
}

int ce_dict_num_colors(void)
{
    return CE_DICT_NUM_COLORS;
}

int ce_dict_num_combos(void)
{
    return CE_DICT_NUM_COMBOS;
}

static int color_in_range(int index)
{
    return index >= 0 && index < CE_DICT_NUM_COLORS;
}

int ce_dict_color_rgb(int index, uint8_t rgb[3])
{
    if (!color_in_range(index)) {
        return -1;
    }
    if (rgb != NULL) {
        rgb[0] = ce_dict_data_rgb[index][0];
        rgb[1] = ce_dict_data_rgb[index][1];
        rgb[2] = ce_dict_data_rgb[index][2];
    }
    return 0;
}

const char *ce_dict_color_name(int index)
{
    return color_in_range(index) ? ce_dict_data_names[index] : NULL;
}

ce_lab ce_dict_color_lab(int index)
{
    if (!color_in_range(index)) {
        ce_lab invalid;
        invalid.L = NAN;
        invalid.a = NAN;
        invalid.b = NAN;
        return invalid;
    }
    return ce_srgb8_to_lab(ce_dict_data_rgb[index][0], ce_dict_data_rgb[index][1], ce_dict_data_rgb[index][2]);
}

/* La tabla generada va ordenada por id (1..N), así que el acceso es directo;
 * si algún día el generador cambiara el orden, se recorre linealmente. */
static const ce_dict_data_combo *find_combo(int id)
{
    int i;
    if (id < 1 || id > CE_DICT_NUM_COMBOS) {
        return NULL;
    }
    if (ce_dict_data_combos[id - 1].id == (uint16_t)id) {
        return &ce_dict_data_combos[id - 1];
    }
    for (i = 0; i < CE_DICT_NUM_COMBOS; ++i) {
        if (ce_dict_data_combos[i].id == (uint16_t)id) {
            return &ce_dict_data_combos[i];
        }
    }
    return NULL;
}

int ce_dict_combo(int id, uint8_t *size, uint8_t colors[CE_DICT_COMBO_MAX])
{
    const ce_dict_data_combo *combo = find_combo(id);
    int k;
    if (combo == NULL) {
        return -1;
    }
    if (size != NULL) {
        *size = combo->size;
    }
    if (colors != NULL) {
        for (k = 0; k < CE_DICT_COMBO_MAX; ++k) {
            colors[k] = combo->colors[k];
        }
    }
    return 0;
}
