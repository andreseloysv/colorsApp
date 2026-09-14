/*
 * ce_dict_data.h: diccionario de Sanzo Wada embebido
 * (159 colores, 348 combinaciones).
 *
 * GENERADO por oracle.build_dictionary, no editar.
 * Regenerar: uv run --project oracle python -m oracle.build_dictionary --emit-c
 * Fuente: mattdesl/dictionary-of-colour-combinations 1.0.2 (MIT) (ver data/wada/README.md).
 *
 * Todo es `static const` para poder incluir este header desde un unico .c
 * (ce_dict.c); la API publica esta en ce/ce.h (ce_dict_*).
 * Solo sRGB8: el motor calcula Lab D65 en C; aqui no hay Lab.
 * Los indices de color de cada combinacion van en orden ascendente; las
 * posiciones mas alla de `size` valen CE_DICT_NONE.
 * (Comentarios sin acentos a proposito: el header es ASCII puro.)
 */
#ifndef CE_DICT_DATA_H
#define CE_DICT_DATA_H

#include <stdint.h>

#define CE_DICT_SCHEMA 1
#define CE_DICT_VERSION "fd95ac692777" /* = dict_version de dictionary.json */
#define CE_DICT_NUM_COLORS 159
#define CE_DICT_NUM_COMBOS 348
#define CE_DICT_MAX_COLORS 7 /* reserva para el Vol. 2 (3..7 colores) */
#define CE_DICT_NUM_SWATCHES 6 /* capitulos del libro, campo swatch 0..5 */
#define CE_DICT_NONE 0xFF /* relleno de ce_dict_combo.colors */

#if defined(__GNUC__) || defined(__clang__)
#define CE_DICT_UNUSED __attribute__((unused))
#else
#define CE_DICT_UNUSED
#endif

/* sRGB de 8 bits por canal, indexado por indice de color (0..CE_DICT_NUM_COLORS-1). */
CE_DICT_UNUSED static const uint8_t ce_dict_data_rgb[CE_DICT_NUM_COLORS][3] = {
    {249, 193, 206}, /*   0 Hermosa Pink */
    {248, 182, 186}, /*   1 Corinthian Pink */
    {224, 179, 182}, /*   2 Cameo Pink */
    {209, 176, 167}, /*   3 Fawn */
    {181, 147, 146}, /*   4 Light Brown Drab */
    {245, 142, 132}, /*   5 Coral Red */
    {246, 145, 126}, /*   6 Fresh Color */
    {244, 128, 103}, /*   7 Grenadine Pink */
    {243, 127, 148}, /*   8 Eosine Pink */
    {242, 114, 145}, /*   9 Spinel Red */
    {212, 109, 122}, /*  10 Old Rose */
    {226,  98,  94}, /*  11 Eugenia Red | A */
    {218,  82,  93}, /*  12 Eugenia Red | B */
    {187, 113,  37}, /*  13 Raw Sienna */
    {197,  97,  39}, /*  14 Vinaceous Tawny */
    {235,  83,  36}, /*  15 Jasper Red */
    {227,  31,  38}, /*  16 Spectrum Red */
    {221,  64,  39}, /*  17 Red Orange */
    {197,  83,  71}, /*  18 Etruscan Red */
    {174,  82,  36}, /*  19 Burnt Sienna */
    {171,  84,  77}, /*  20 Ochre Red */
    {203,  47,  67}, /*  21 Scarlet */
    {204,  18,  54}, /*  22 Carmine */
    {197,  60, 105}, /*  23 Indian Lake */
    {183,  63, 116}, /*  24 Rosolanc Purple */
    {183,  31,  87}, /*  25 Pomegranite Purple */
    {169,  65,  81}, /*  26 Hydrangea Red */
    {168,  66,  34}, /*  27 Brick Red */
    {166,  44,  55}, /*  28 Carmine Red */
    {171,  36,  57}, /*  29 Pompeian Red */
    {167,  33,  68}, /*  30 Red */
    {124,  66,  38}, /*  31 Brown */
    {121,  51,  39}, /*  32 Hay's Russet */
    {130,  36,  31}, /*  33 Vandyke Red */
    {125,  19,  58}, /*  34 Pansy Purple */
    {128,  38,  38}, /*  35 Pale Burnt Lake */
    {100,  45,  94}, /*  36 Violet Red */
    {109,  65,  69}, /*  37 Vistoris Lake */
    {245, 236, 194}, /*  38 Sulpher Yellow */
    {255, 239, 174}, /*  39 Pale Lemon Yellow */
    {251, 230, 160}, /*  40 Naples Yellow */
    {235, 211, 162}, /*  41 Ivory Buff */
    {253, 212, 189}, /*  42 Seashell Pink */
    {252, 199, 155}, /*  43 Light Pinkish Cinnamon */
    {238, 180, 128}, /*  44 Pinkish Cinnamon */
    {253, 197, 126}, /*  45 Cinnamon Buff */
    {253, 191, 104}, /*  46 Cream Yellow */
    {243, 162,  87}, /*  47 Golden Yellow */
    {238, 167, 140}, /*  48 Vinaceous Cinnamon */
    {216, 163, 123}, /*  49 Ochraceous Salmon */
    {197, 165, 110}, /*  50 Isabella Color */
    {197, 159, 107}, /*  51 Maple */
    {193, 196, 148}, /*  52 Olive Buff */
    {194, 174, 147}, /*  53 Ecru */
    {255, 242,   0}, /*  54 Yellow */
    {248, 237,  67}, /*  55 Lemon Yellow */
    {255, 221,   0}, /*  56 Apricot Yellow */
    {202, 179,  86}, /*  57 Pyrite Yellow */
    {214, 180,  62}, /*  58 Olive Ocher */
    {226, 181,  64}, /*  59 Yellow Ocher */
    {252, 179,  21}, /*  60 Orange Yellow */
    {249, 157,  27}, /*  61 Yellow Orange */
    {246, 140,  80}, /*  62 Apricot Orange */
    {243, 116,  32}, /*  63 Orange */
    {241,  90,  48}, /*  64 Peach Red */
    {217, 102,  41}, /*  65 English Red */
    {194, 117,  68}, /*  66 Cinnamon Rufous */
    {193, 107,  39}, /*  67 Orange Rufous */
    {193, 159,  44}, /*  68 Sulphine Yellow */
    {188, 137,  43}, /*  69 Khaki */
    {178, 183,  62}, /*  70 Citron Yellow */
    {176, 159,  54}, /*  71 Citrine */
    {150, 135,  77}, /*  72 Buffy Citrine */
    {139, 131,  91}, /*  73 Dark Citrine */
    {132, 128,  97}, /*  74 Light Grayish Olive */
    {132, 135,  94}, /*  75 Krongbergs Green */
    {131, 126,  49}, /*  76 Olive */
    {152, 111,  45}, /*  77 Orange Citrine */
    {163, 103,  82}, /*  78 Sudan Brown */
    {107, 113,  64}, /*  79 Olive Green */
    {128, 110,  75}, /*  80 Light Brownish Olive */
    { 99,  90,  58}, /*  81 Deep Grayish Olive */
    {113,  80,  47}, /*  82 Pale Raw Umber */
    {100,  75,  30}, /*  83 Sepia */
    {118,  44,  25}, /*  84 Madder Brown */
    {101,  53,  20}, /*  85 Mars Brown Tobacco */
    { 75,  51,  23}, /*  86 Vandyke Brown */
    {181, 222, 204}, /*  87 Turquoise Green */
    {180, 205, 194}, /*  88 Glaucous Green */
    {183, 194, 169}, /*  89 Dark Greenish Glaucous */
    {175, 212, 114}, /*  90 Yellow Green */
    {199, 209,  79}, /*  91 Light Green Yellow */
    {135, 197,  64}, /*  92 Night Green */
    {166, 161,  89}, /*  93 Olive Yellow */
    {112, 147, 144}, /*  94 Artemesia Green */
    {109, 126, 119}, /*  95 Andover Green */
    {143, 160, 113}, /*  96 Rainette Green */
    {113, 148, 112}, /*  97 Chromium Green */
    {100, 143, 123}, /*  98 Pistachio Green */
    {  0, 180, 155}, /*  99 Sea Green */
    {  0, 151, 141}, /* 100 Benzol Green */
    {  0, 144, 138}, /* 101 Light Porcelain Green */
    { 72, 155, 110}, /* 102 Green */
    {  0, 148, 101}, /* 103 Dull Viridian Green */
    {129, 146,  56}, /* 104 Oil Green */
    { 26, 116,  68}, /* 105 Diamine Green */
    { 67, 119,  66}, /* 106 Cossack Green */
    { 85,  88,  50}, /* 107 Lincoln Green */
    { 66,  83,  62}, /* 108 Blackish Olive */
    { 37,  49,  34}, /* 109 Deep Slate Olive */
    {188, 228, 229}, /* 110 Nile Blue */
    {167, 212, 228}, /* 111 Pale King's Blue */
    {165, 200, 209}, /* 112 Light Glaucous Blue */
    {151, 172, 200}, /* 113 Salvia Blue */
    {150, 209, 170}, /* 114 Cobalt Green */
    {120, 205, 208}, /* 115 Calamine BLue */
    { 98, 198, 191}, /* 116 Venice Green */
    {  0, 147, 165}, /* 117 Cerulian Blue */
    {  0, 147, 155}, /* 118 Peacock Blue */
    {  9, 145, 151}, /* 119 Green Blue */
    { 90, 130, 179}, /* 120 Olympic Blue */
    {  0, 110, 184}, /* 121 Blue */
    {  0, 113, 144}, /* 122 Antwarp Blue */
    {  0,  91, 141}, /* 123 Helvetia Blue */
    { 84, 112, 118}, /* 124 Dark Medici Blue */
    {  0,  79,  70}, /* 125 Dusky Green */
    { 28,  66, 134}, /* 126 Deep Lyons Blue */
    { 64,  69, 106}, /* 127 Violet Blue */
    {  6,  79, 110}, /* 128 Vandar Poel's Blue */
    { 18,  53,  78}, /* 129 Dark Tyrian Blue */
    { 30,  14,  63}, /* 130 Dull Violet Black */
    {  5,  18,  48}, /* 131 Deep Indigo */
    { 17,  47,  44}, /* 132 Deep Slate Green */
    {181, 177, 216}, /* 133 Grayish Lavender - A */
    {192, 169, 179}, /* 134 Grayish Lavender - B */
    {202, 146, 168}, /* 135 Laelia Pink */
    {185, 132, 175}, /* 136 Lilac */
    {191,  88, 146}, /* 137 Eupatorium Purple */
    {154, 114, 170}, /* 138 Light Mauve */
    {163, 106, 165}, /* 139 Aconite Violet */
    {128, 113, 158}, /* 140 Dull Blue Violet */
    {102,  98, 156}, /* 141 Dark Soft Violet */
    {100,  80, 161}, /* 142 Blue Violet */
    {132,  86,  91}, /* 143 Purple Drab */
    {112, 114, 124}, /* 144 Deep Violet / Plumbeous */
    {140,  76,  98}, /* 145 Veronia Purple */
    {112,  67,  87}, /* 146 Dark Slate Purple */
    {122,  68,  86}, /* 147 Taupe Brown */
    {113,  59,  76}, /* 148 Violet Carmine */
    { 79,  64, 134}, /* 149 Violet */
    { 89,  37, 106}, /* 150 Red Violet */
    { 80,  19,  69}, /* 151 Cotinga Purple */
    { 78,  29,  76}, /* 152 Dusky Madder Violet */
    {255, 255, 255}, /* 153 White */
    {182, 191, 193}, /* 154 Neutral Gray */
    {162, 176, 173}, /* 155 Mineral Gray */
    {161, 163, 154}, /* 156 Warm Gray */
    { 52,  69,  76}, /* 157 Slate Color */
    { 17,  19,  20}, /* 158 Black */
};

/* Nombres en ingles del libro (nomenclatura de Ridgway), tal cual en el fuente. */
CE_DICT_UNUSED static const char *const ce_dict_data_names[CE_DICT_NUM_COLORS] = {
    "Hermosa Pink", /* 0 */
    "Corinthian Pink", /* 1 */
    "Cameo Pink", /* 2 */
    "Fawn", /* 3 */
    "Light Brown Drab", /* 4 */
    "Coral Red", /* 5 */
    "Fresh Color", /* 6 */
    "Grenadine Pink", /* 7 */
    "Eosine Pink", /* 8 */
    "Spinel Red", /* 9 */
    "Old Rose", /* 10 */
    "Eugenia Red | A", /* 11 */
    "Eugenia Red | B", /* 12 */
    "Raw Sienna", /* 13 */
    "Vinaceous Tawny", /* 14 */
    "Jasper Red", /* 15 */
    "Spectrum Red", /* 16 */
    "Red Orange", /* 17 */
    "Etruscan Red", /* 18 */
    "Burnt Sienna", /* 19 */
    "Ochre Red", /* 20 */
    "Scarlet", /* 21 */
    "Carmine", /* 22 */
    "Indian Lake", /* 23 */
    "Rosolanc Purple", /* 24 */
    "Pomegranite Purple", /* 25 */
    "Hydrangea Red", /* 26 */
    "Brick Red", /* 27 */
    "Carmine Red", /* 28 */
    "Pompeian Red", /* 29 */
    "Red", /* 30 */
    "Brown", /* 31 */
    "Hay's Russet", /* 32 */
    "Vandyke Red", /* 33 */
    "Pansy Purple", /* 34 */
    "Pale Burnt Lake", /* 35 */
    "Violet Red", /* 36 */
    "Vistoris Lake", /* 37 */
    "Sulpher Yellow", /* 38 */
    "Pale Lemon Yellow", /* 39 */
    "Naples Yellow", /* 40 */
    "Ivory Buff", /* 41 */
    "Seashell Pink", /* 42 */
    "Light Pinkish Cinnamon", /* 43 */
    "Pinkish Cinnamon", /* 44 */
    "Cinnamon Buff", /* 45 */
    "Cream Yellow", /* 46 */
    "Golden Yellow", /* 47 */
    "Vinaceous Cinnamon", /* 48 */
    "Ochraceous Salmon", /* 49 */
    "Isabella Color", /* 50 */
    "Maple", /* 51 */
    "Olive Buff", /* 52 */
    "Ecru", /* 53 */
    "Yellow", /* 54 */
    "Lemon Yellow", /* 55 */
    "Apricot Yellow", /* 56 */
    "Pyrite Yellow", /* 57 */
    "Olive Ocher", /* 58 */
    "Yellow Ocher", /* 59 */
    "Orange Yellow", /* 60 */
    "Yellow Orange", /* 61 */
    "Apricot Orange", /* 62 */
    "Orange", /* 63 */
    "Peach Red", /* 64 */
    "English Red", /* 65 */
    "Cinnamon Rufous", /* 66 */
    "Orange Rufous", /* 67 */
    "Sulphine Yellow", /* 68 */
    "Khaki", /* 69 */
    "Citron Yellow", /* 70 */
    "Citrine", /* 71 */
    "Buffy Citrine", /* 72 */
    "Dark Citrine", /* 73 */
    "Light Grayish Olive", /* 74 */
    "Krongbergs Green", /* 75 */
    "Olive", /* 76 */
    "Orange Citrine", /* 77 */
    "Sudan Brown", /* 78 */
    "Olive Green", /* 79 */
    "Light Brownish Olive", /* 80 */
    "Deep Grayish Olive", /* 81 */
    "Pale Raw Umber", /* 82 */
    "Sepia", /* 83 */
    "Madder Brown", /* 84 */
    "Mars Brown Tobacco", /* 85 */
    "Vandyke Brown", /* 86 */
    "Turquoise Green", /* 87 */
    "Glaucous Green", /* 88 */
    "Dark Greenish Glaucous", /* 89 */
    "Yellow Green", /* 90 */
    "Light Green Yellow", /* 91 */
    "Night Green", /* 92 */
    "Olive Yellow", /* 93 */
    "Artemesia Green", /* 94 */
    "Andover Green", /* 95 */
    "Rainette Green", /* 96 */
    "Chromium Green", /* 97 */
    "Pistachio Green", /* 98 */
    "Sea Green", /* 99 */
    "Benzol Green", /* 100 */
    "Light Porcelain Green", /* 101 */
    "Green", /* 102 */
    "Dull Viridian Green", /* 103 */
    "Oil Green", /* 104 */
    "Diamine Green", /* 105 */
    "Cossack Green", /* 106 */
    "Lincoln Green", /* 107 */
    "Blackish Olive", /* 108 */
    "Deep Slate Olive", /* 109 */
    "Nile Blue", /* 110 */
    "Pale King's Blue", /* 111 */
    "Light Glaucous Blue", /* 112 */
    "Salvia Blue", /* 113 */
    "Cobalt Green", /* 114 */
    "Calamine BLue", /* 115 */
    "Venice Green", /* 116 */
    "Cerulian Blue", /* 117 */
    "Peacock Blue", /* 118 */
    "Green Blue", /* 119 */
    "Olympic Blue", /* 120 */
    "Blue", /* 121 */
    "Antwarp Blue", /* 122 */
    "Helvetia Blue", /* 123 */
    "Dark Medici Blue", /* 124 */
    "Dusky Green", /* 125 */
    "Deep Lyons Blue", /* 126 */
    "Violet Blue", /* 127 */
    "Vandar Poel's Blue", /* 128 */
    "Dark Tyrian Blue", /* 129 */
    "Dull Violet Black", /* 130 */
    "Deep Indigo", /* 131 */
    "Deep Slate Green", /* 132 */
    "Grayish Lavender - A", /* 133 */
    "Grayish Lavender - B", /* 134 */
    "Laelia Pink", /* 135 */
    "Lilac", /* 136 */
    "Eupatorium Purple", /* 137 */
    "Light Mauve", /* 138 */
    "Aconite Violet", /* 139 */
    "Dull Blue Violet", /* 140 */
    "Dark Soft Violet", /* 141 */
    "Blue Violet", /* 142 */
    "Purple Drab", /* 143 */
    "Deep Violet / Plumbeous", /* 144 */
    "Veronia Purple", /* 145 */
    "Dark Slate Purple", /* 146 */
    "Taupe Brown", /* 147 */
    "Violet Carmine", /* 148 */
    "Violet", /* 149 */
    "Red Violet", /* 150 */
    "Cotinga Purple", /* 151 */
    "Dusky Madder Violet", /* 152 */
    "White", /* 153 */
    "Neutral Gray", /* 154 */
    "Mineral Gray", /* 155 */
    "Warm Gray", /* 156 */
    "Slate Color", /* 157 */
    "Black", /* 158 */
};

/* Capitulo del libro (0..CE_DICT_NUM_SWATCHES-1) de cada color. */
CE_DICT_UNUSED static const uint8_t ce_dict_data_swatch[CE_DICT_NUM_COLORS] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, /* 0.. */
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, /* 16.. */
    0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, /* 32.. */
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, /* 48.. */
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, /* 64.. */
    1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, /* 80.. */
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, /* 96.. */
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, /* 112.. */
    3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, /* 128.. */
    4, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, /* 144.. */
};

typedef struct {
    uint16_t id;                         /* 1..CE_DICT_NUM_COMBOS, numero de lamina */
    uint8_t size;                        /* colores usados: 2..CE_DICT_MAX_COLORS */
    uint8_t colors[CE_DICT_MAX_COLORS];  /* indices ascendentes; CE_DICT_NONE de relleno */
} ce_dict_data_combo;

CE_DICT_UNUSED static const ce_dict_data_combo ce_dict_data_combos[CE_DICT_NUM_COMBOS] = {
    {  1, 2, { 65, 117, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {  2, 2, { 61, 129, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {  3, 2, { 13,  39, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {  4, 2, { 50, 150, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {  5, 2, {106, 128, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {  6, 2, {  7, 131, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {  7, 2, { 63,  88, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {  8, 2, { 66, 133, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {  9, 2, { 36, 140, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 10, 2, { 66,  73, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 11, 2, { 41, 155, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 12, 2, { 50, 119, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 13, 2, { 13, 145, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 14, 2, {  9,  40, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 15, 2, {100, 133, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 16, 2, { 33, 111, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 17, 2, { 12,  99, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 18, 2, {  3, 152, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 19, 2, { 85,  92, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 20, 2, {115, 135, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 21, 2, {  7,  99, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 22, 2, { 54, 126, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 23, 2, { 45, 138, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 24, 2, { 83, 145, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 25, 2, { 18, 110, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 26, 2, { 47,  82, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 27, 2, {  1, 157, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 28, 2, { 84, 131, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 29, 2, { 75, 113, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 30, 2, { 29, 155, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 31, 2, { 17,  39, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 32, 2, { 49,  92, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 33, 2, { 13, 157, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 34, 2, {  8, 154, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 35, 2, {  4,  28, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 36, 2, { 68,  87, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 37, 2, { 27, 150, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 38, 2, {105, 126, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 39, 2, { 22, 123, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 40, 2, { 14,  70, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 41, 2, { 73, 115, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 42, 2, { 59, 149, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 43, 2, {  1, 139, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 44, 2, {101, 120, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 45, 2, { 42,  55, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 46, 2, { 63, 158, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 47, 2, { 18, 134, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 48, 2, { 24, 123, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 49, 2, {111, 121, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 50, 2, { 41, 152, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 51, 2, { 28, 121, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 52, 2, { 38, 158, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 53, 2, { 61, 152, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 54, 2, {100, 112, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 55, 2, { 10, 153, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 56, 2, {134, 149, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 57, 2, {147, 157, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 58, 2, { 32,  99, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 59, 2, {  8,  71, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 60, 2, { 39, 129, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 61, 2, { 91, 151, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 62, 2, { 54, 158, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 63, 2, { 37, 117, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 64, 2, {139, 141, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 65, 2, { 68, 115, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 66, 2, { 58,  79, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 67, 2, {120, 129, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 68, 2, {  4,  54, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 69, 2, {156, 158, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 70, 2, { 13, 107, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 71, 2, { 29,  49, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 72, 2, { 38, 111, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 73, 2, { 82,  96, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 74, 2, { 87, 119, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 75, 2, {111, 127, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 76, 2, { 39, 156, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 77, 2, { 12, 128, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 78, 2, { 44, 116, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 79, 2, { 84, 119, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 80, 2, { 38, 138, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 81, 2, { 47, 156, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 82, 2, { 32, 152, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 83, 2, { 52, 127, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 84, 2, { 42, 132, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 85, 2, { 14, 122, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 86, 2, { 13,  99, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 87, 2, {  1,  70, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 88, 2, { 42, 121, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 89, 2, { 61, 127, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 90, 2, {  8, 139, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 91, 2, { 37,  67, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 92, 2, {  5, 100, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 93, 2, { 71, 112, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 94, 2, { 41, 125, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 95, 2, { 32, 130, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 96, 2, { 59,  76, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 97, 2, {  1,  18, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 98, 2, { 84, 127, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    { 99, 2, { 39, 117, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {100, 2, { 72, 140, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {101, 2, {  2, 126, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {102, 2, { 41,  67, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {103, 2, { 66, 152, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {104, 2, { 28,  38, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {105, 2, {  2,  97, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {106, 2, {122, 130, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {107, 2, { 56,  74, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {108, 2, {  8,  27, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {109, 2, { 39, 108, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {110, 2, { 31,  86, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {111, 2, { 39,  90, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {112, 2, {  7, 158, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {113, 2, { 42,  86, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {114, 2, { 60, 122, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {115, 2, { 40,  64, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {116, 2, {  2, 142, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {117, 2, { 22, 158, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {118, 2, { 59,  86, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {119, 2, {112, 129, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {120, 2, {  2,  29, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}},
    {121, 3, { 31,  49, 107, 0xFF, 0xFF, 0xFF, 0xFF}},
    {122, 3, { 22,  46, 100, 0xFF, 0xFF, 0xFF, 0xFF}},
    {123, 3, {  5,  55, 147, 0xFF, 0xFF, 0xFF, 0xFF}},
    {124, 3, { 35,  59,  93, 0xFF, 0xFF, 0xFF, 0xFF}},
    {125, 3, {  3, 117, 127, 0xFF, 0xFF, 0xFF, 0xFF}},
    {126, 3, { 41,  59, 126, 0xFF, 0xFF, 0xFF, 0xFF}},
    {127, 3, { 45,  98, 141, 0xFF, 0xFF, 0xFF, 0xFF}},
    {128, 3, {  1, 116, 138, 0xFF, 0xFF, 0xFF, 0xFF}},
    {129, 3, { 56,  69, 113, 0xFF, 0xFF, 0xFF, 0xFF}},
    {130, 3, { 13,  28, 149, 0xFF, 0xFF, 0xFF, 0xFF}},
    {131, 3, { 13,  65, 118, 0xFF, 0xFF, 0xFF, 0xFF}},
    {132, 3, { 38,  47,  71, 0xFF, 0xFF, 0xFF, 0xFF}},
    {133, 3, { 33,  71,  99, 0xFF, 0xFF, 0xFF, 0xFF}},
    {134, 3, {  8, 138, 150, 0xFF, 0xFF, 0xFF, 0xFF}},
    {135, 3, { 38, 106, 113, 0xFF, 0xFF, 0xFF, 0xFF}},
    {136, 3, { 21, 103, 150, 0xFF, 0xFF, 0xFF, 0xFF}},
    {137, 3, { 18,  45,  98, 0xFF, 0xFF, 0xFF, 0xFF}},
    {138, 3, { 47,  55, 116, 0xFF, 0xFF, 0xFF, 0xFF}},
    {139, 3, {113, 131, 154, 0xFF, 0xFF, 0xFF, 0xFF}},
    {140, 3, { 47, 122, 157, 0xFF, 0xFF, 0xFF, 0xFF}},
    {141, 3, { 63,  90, 129, 0xFF, 0xFF, 0xFF, 0xFF}},
    {142, 3, { 26,  68, 113, 0xFF, 0xFF, 0xFF, 0xFF}},
    {143, 3, {121, 136, 156, 0xFF, 0xFF, 0xFF, 0xFF}},
    {144, 3, { 24,  63, 158, 0xFF, 0xFF, 0xFF, 0xFF}},
    {145, 3, { 31,  70, 130, 0xFF, 0xFF, 0xFF, 0xFF}},
    {146, 3, { 69,  81, 105, 0xFF, 0xFF, 0xFF, 0xFF}},
    {147, 3, {  9,  33,  87, 0xFF, 0xFF, 0xFF, 0xFF}},
    {148, 3, { 58,  60, 117, 0xFF, 0xFF, 0xFF, 0xFF}},
    {149, 3, { 58,  63, 132, 0xFF, 0xFF, 0xFF, 0xFF}},
    {150, 3, { 42,  70,  88, 0xFF, 0xFF, 0xFF, 0xFF}},
    {151, 3, { 38,  61, 128, 0xFF, 0xFF, 0xFF, 0xFF}},
    {152, 3, { 18,  32, 112, 0xFF, 0xFF, 0xFF, 0xFF}},
    {153, 3, {  8,  60,  70, 0xFF, 0xFF, 0xFF, 0xFF}},
    {154, 3, { 22,  54, 121, 0xFF, 0xFF, 0xFF, 0xFF}},
    {155, 3, { 15, 100, 131, 0xFF, 0xFF, 0xFF, 0xFF}},
    {156, 3, { 58, 114, 149, 0xFF, 0xFF, 0xFF, 0xFF}},
    {157, 3, { 34,  58, 120, 0xFF, 0xFF, 0xFF, 0xFF}},
    {158, 3, { 55,  66,  92, 0xFF, 0xFF, 0xFF, 0xFF}},
    {159, 3, { 69, 115, 133, 0xFF, 0xFF, 0xFF, 0xFF}},
    {160, 3, { 68,  82, 124, 0xFF, 0xFF, 0xFF, 0xFF}},
    {161, 3, { 31,  44, 123, 0xFF, 0xFF, 0xFF, 0xFF}},
    {162, 3, { 10,  96, 136, 0xFF, 0xFF, 0xFF, 0xFF}},
    {163, 3, { 56,  87, 122, 0xFF, 0xFF, 0xFF, 0xFF}},
    {164, 3, { 17,  60, 149, 0xFF, 0xFF, 0xFF, 0xFF}},
    {165, 3, {  2,   9,  37, 0xFF, 0xFF, 0xFF, 0xFF}},
    {166, 3, {  7,  40, 132, 0xFF, 0xFF, 0xFF, 0xFF}},
    {167, 3, { 53, 111, 128, 0xFF, 0xFF, 0xFF, 0xFF}},
    {168, 3, { 55, 128, 145, 0xFF, 0xFF, 0xFF, 0xFF}},
    {169, 3, {  1,  39, 156, 0xFF, 0xFF, 0xFF, 0xFF}},
    {170, 3, { 24,  60, 150, 0xFF, 0xFF, 0xFF, 0xFF}},
    {171, 3, { 35,  61,  88, 0xFF, 0xFF, 0xFF, 0xFF}},
    {172, 3, { 66, 122, 150, 0xFF, 0xFF, 0xFF, 0xFF}},
    {173, 3, { 55,  84,  87, 0xFF, 0xFF, 0xFF, 0xFF}},
    {174, 3, {  1, 134, 147, 0xFF, 0xFF, 0xFF, 0xFF}},
    {175, 3, { 44,  52, 142, 0xFF, 0xFF, 0xFF, 0xFF}},
    {176, 3, {  0,  42, 115, 0xFF, 0xFF, 0xFF, 0xFF}},
    {177, 3, { 35,  72, 133, 0xFF, 0xFF, 0xFF, 0xFF}},
    {178, 3, { 41, 112, 119, 0xFF, 0xFF, 0xFF, 0xFF}},
    {179, 3, { 17,  47, 126, 0xFF, 0xFF, 0xFF, 0xFF}},
    {180, 3, { 45, 138, 154, 0xFF, 0xFF, 0xFF, 0xFF}},
    {181, 3, { 28, 149, 151, 0xFF, 0xFF, 0xFF, 0xFF}},
    {182, 3, { 13,  86, 131, 0xFF, 0xFF, 0xFF, 0xFF}},
    {183, 3, {144, 145, 150, 0xFF, 0xFF, 0xFF, 0xFF}},
    {184, 3, {  9,  41,  74, 0xFF, 0xFF, 0xFF, 0xFF}},
    {185, 3, {  4,  18,  39, 0xFF, 0xFF, 0xFF, 0xFF}},
    {186, 3, { 32,  49, 121, 0xFF, 0xFF, 0xFF, 0xFF}},
    {187, 3, {123, 134, 139, 0xFF, 0xFF, 0xFF, 0xFF}},
    {188, 3, { 96, 113, 114, 0xFF, 0xFF, 0xFF, 0xFF}},
    {189, 3, { 55, 109, 116, 0xFF, 0xFF, 0xFF, 0xFF}},
    {190, 3, { 41,  65, 158, 0xFF, 0xFF, 0xFF, 0xFF}},
    {191, 3, {  4,  59, 121, 0xFF, 0xFF, 0xFF, 0xFF}},
    {192, 3, { 46,  86, 144, 0xFF, 0xFF, 0xFF, 0xFF}},
    {193, 3, {  7,  40, 101, 0xFF, 0xFF, 0xFF, 0xFF}},
    {194, 3, { 15,  42, 120, 0xFF, 0xFF, 0xFF, 0xFF}},
    {195, 3, {  9,  39, 154, 0xFF, 0xFF, 0xFF, 0xFF}},
    {196, 3, { 70, 111, 142, 0xFF, 0xFF, 0xFF, 0xFF}},
    {197, 3, {  8, 141, 154, 0xFF, 0xFF, 0xFF, 0xFF}},
    {198, 3, { 19,  56, 102, 0xFF, 0xFF, 0xFF, 0xFF}},
    {199, 3, { 20,  80, 126, 0xFF, 0xFF, 0xFF, 0xFF}},
    {200, 3, { 28,  52,  97, 0xFF, 0xFF, 0xFF, 0xFF}},
    {201, 3, {  7,  76, 114, 0xFF, 0xFF, 0xFF, 0xFF}},
    {202, 3, { 87, 114, 157, 0xFF, 0xFF, 0xFF, 0xFF}},
    {203, 3, { 39,  48, 107, 0xFF, 0xFF, 0xFF, 0xFF}},
    {204, 3, { 24,  66, 112, 0xFF, 0xFF, 0xFF, 0xFF}},
    {205, 3, { 35,  48, 149, 0xFF, 0xFF, 0xFF, 0xFF}},
    {206, 3, {  1,  47,  66, 0xFF, 0xFF, 0xFF, 0xFF}},
    {207, 3, { 78,  88, 158, 0xFF, 0xFF, 0xFF, 0xFF}},
    {208, 3, { 38, 119, 122, 0xFF, 0xFF, 0xFF, 0xFF}},
    {209, 3, { 41,  61, 113, 0xFF, 0xFF, 0xFF, 0xFF}},
    {210, 3, { 45,  55, 107, 0xFF, 0xFF, 0xFF, 0xFF}},
    {211, 3, { 62,  93, 131, 0xFF, 0xFF, 0xFF, 0xFF}},
    {212, 3, { 29,  77, 113, 0xFF, 0xFF, 0xFF, 0xFF}},
    {213, 3, { 48,  56, 111, 0xFF, 0xFF, 0xFF, 0xFF}},
    {214, 3, { 41,  78, 149, 0xFF, 0xFF, 0xFF, 0xFF}},
    {215, 3, { 46, 121, 137, 0xFF, 0xFF, 0xFF, 0xFF}},
    {216, 3, { 15, 102, 158, 0xFF, 0xFF, 0xFF, 0xFF}},
    {217, 3, { 35,  49, 105, 0xFF, 0xFF, 0xFF, 0xFF}},
    {218, 3, {123, 133, 144, 0xFF, 0xFF, 0xFF, 0xFF}},
    {219, 3, { 15,  97, 125, 0xFF, 0xFF, 0xFF, 0xFF}},
    {220, 3, { 25,  49, 139, 0xFF, 0xFF, 0xFF, 0xFF}},
    {221, 3, { 28, 154, 158, 0xFF, 0xFF, 0xFF, 0xFF}},
    {222, 3, { 59,  61,  67, 0xFF, 0xFF, 0xFF, 0xFF}},
    {223, 3, {  4,  49,  87, 0xFF, 0xFF, 0xFF, 0xFF}},
    {224, 3, {  9, 124, 147, 0xFF, 0xFF, 0xFF, 0xFF}},
    {225, 3, { 22, 125, 146, 0xFF, 0xFF, 0xFF, 0xFF}},
    {226, 3, { 37,  46, 149, 0xFF, 0xFF, 0xFF, 0xFF}},
    {227, 3, {  0, 112, 117, 0xFF, 0xFF, 0xFF, 0xFF}},
    {228, 3, { 28,  39, 154, 0xFF, 0xFF, 0xFF, 0xFF}},
    {229, 3, { 47, 109, 154, 0xFF, 0xFF, 0xFF, 0xFF}},
    {230, 3, {  7,  87, 114, 0xFF, 0xFF, 0xFF, 0xFF}},
    {231, 3, {  2,  32, 120, 0xFF, 0xFF, 0xFF, 0xFF}},
    {232, 3, { 22,  44, 131, 0xFF, 0xFF, 0xFF, 0xFF}},
    {233, 3, { 28,  72, 127, 0xFF, 0xFF, 0xFF, 0xFF}},
    {234, 3, { 45,  82, 111, 0xFF, 0xFF, 0xFF, 0xFF}},
    {235, 3, { 41,  61, 134, 0xFF, 0xFF, 0xFF, 0xFF}},
    {236, 3, { 69, 126, 143, 0xFF, 0xFF, 0xFF, 0xFF}},
    {237, 3, { 28,  84, 113, 0xFF, 0xFF, 0xFF, 0xFF}},
    {238, 3, { 49, 151, 156, 0xFF, 0xFF, 0xFF, 0xFF}},
    {239, 3, {  4,  57,  88, 0xFF, 0xFF, 0xFF, 0xFF}},
    {240, 3, {  6,  54, 117, 0xFF, 0xFF, 0xFF, 0xFF}},
    {241, 4, { 17,  39,  50, 124, 0xFF, 0xFF, 0xFF}},
    {242, 4, {  8,  19, 105, 158, 0xFF, 0xFF, 0xFF}},
    {243, 4, { 13,  41,  79, 157, 0xFF, 0xFF, 0xFF}},
    {244, 4, {  4,  14,  95, 122, 0xFF, 0xFF, 0xFF}},
    {245, 4, { 28, 104, 129, 157, 0xFF, 0xFF, 0xFF}},
    {246, 4, {  1,  27,  38,  45, 0xFF, 0xFF, 0xFF}},
    {247, 4, { 13,  56, 100, 126, 0xFF, 0xFF, 0xFF}},
    {248, 4, {  8,  69, 133, 146, 0xFF, 0xFF, 0xFF}},
    {249, 4, { 32,  53,  58, 124, 0xFF, 0xFF, 0xFF}},
    {250, 4, { 57,  64,  99, 110, 0xFF, 0xFF, 0xFF}},
    {251, 4, { 30,  54, 105, 157, 0xFF, 0xFF, 0xFF}},
    {252, 4, { 12,  13,  68, 119, 0xFF, 0xFF, 0xFF}},
    {253, 4, { 55,  62, 151, 157, 0xFF, 0xFF, 0xFF}},
    {254, 4, {  1,  38,  76, 135, 0xFF, 0xFF, 0xFF}},
    {255, 4, { 13,  57, 115, 158, 0xFF, 0xFF, 0xFF}},
    {256, 4, { 48,  63, 103, 158, 0xFF, 0xFF, 0xFF}},
    {257, 4, { 16,  60, 121, 139, 0xFF, 0xFF, 0xFF}},
    {258, 4, { 35,  44,  76, 122, 0xFF, 0xFF, 0xFF}},
    {259, 4, { 55, 119, 123, 156, 0xFF, 0xFF, 0xFF}},
    {260, 4, { 10,  48,  88,  99, 0xFF, 0xFF, 0xFF}},
    {261, 4, { 30,  39, 115, 156, 0xFF, 0xFF, 0xFF}},
    {262, 4, { 12,  41,  71, 106, 0xFF, 0xFF, 0xFF}},
    {263, 4, { 19,  44,  87, 157, 0xFF, 0xFF, 0xFF}},
    {264, 4, {  1,  17,  89, 117, 0xFF, 0xFF, 0xFF}},
    {265, 4, { 10,  56,  93, 130, 0xFF, 0xFF, 0xFF}},
    {266, 4, { 16,  41,  96, 100, 0xFF, 0xFF, 0xFF}},
    {267, 4, { 46,  61, 100, 121, 0xFF, 0xFF, 0xFF}},
    {268, 4, {  4,  13, 109, 110, 0xFF, 0xFF, 0xFF}},
    {269, 4, { 13,  35, 139, 158, 0xFF, 0xFF, 0xFF}},
    {270, 4, { 12,  38,  79, 106, 0xFF, 0xFF, 0xFF}},
    {271, 4, { 25, 114, 119, 132, 0xFF, 0xFF, 0xFF}},
    {272, 4, { 39,  63,  87, 113, 0xFF, 0xFF, 0xFF}},
    {273, 4, {  0,  34,  78, 154, 0xFF, 0xFF, 0xFF}},
    {274, 4, { 64,  73, 120, 138, 0xFF, 0xFF, 0xFF}},
    {275, 4, { 18,  53,  84, 147, 0xFF, 0xFF, 0xFF}},
    {276, 4, {  8,  42,  90, 158, 0xFF, 0xFF, 0xFF}},
    {277, 4, {  9,  24,  76, 130, 0xFF, 0xFF, 0xFF}},
    {278, 4, { 46,  58, 106, 125, 0xFF, 0xFF, 0xFF}},
    {279, 4, { 13,  48,  53, 129, 0xFF, 0xFF, 0xFF}},
    {280, 4, { 12, 107, 135, 147, 0xFF, 0xFF, 0xFF}},
    {281, 4, { 39, 100, 114, 122, 0xFF, 0xFF, 0xFF}},
    {282, 4, { 12,  51, 114, 136, 0xFF, 0xFF, 0xFF}},
    {283, 4, { 20,  35,  97, 116, 0xFF, 0xFF, 0xFF}},
    {284, 4, { 11,  56,  99, 125, 0xFF, 0xFF, 0xFF}},
    {285, 4, {  4,  19,  64,  87, 0xFF, 0xFF, 0xFF}},
    {286, 4, { 19,  60, 118, 127, 0xFF, 0xFF, 0xFF}},
    {287, 4, {  8,  57, 111, 115, 0xFF, 0xFF, 0xFF}},
    {288, 4, { 61,  83, 147, 158, 0xFF, 0xFF, 0xFF}},
    {289, 4, { 55,  91, 127, 130, 0xFF, 0xFF, 0xFF}},
    {290, 4, { 37,  39, 107, 114, 0xFF, 0xFF, 0xFF}},
    {291, 4, { 91,  99, 114, 115, 0xFF, 0xFF, 0xFF}},
    {292, 4, { 39,  44,  50,  53, 0xFF, 0xFF, 0xFF}},
    {293, 4, { 13,  87,  94, 102, 0xFF, 0xFF, 0xFF}},
    {294, 4, { 38,  46, 106, 113, 0xFF, 0xFF, 0xFF}},
    {295, 4, { 46,  54, 121, 130, 0xFF, 0xFF, 0xFF}},
    {296, 4, { 38,  49,  82, 157, 0xFF, 0xFF, 0xFF}},
    {297, 4, { 19,  61,  79, 127, 0xFF, 0xFF, 0xFF}},
    {298, 4, { 13,  55,  64, 158, 0xFF, 0xFF, 0xFF}},
    {299, 4, { 23,  48, 104, 122, 0xFF, 0xFF, 0xFF}},
    {300, 4, {  7,  46,  87, 115, 0xFF, 0xFF, 0xFF}},
    {301, 4, { 16,  41,  96, 139, 0xFF, 0xFF, 0xFF}},
    {302, 4, { 46,  53, 110, 122, 0xFF, 0xFF, 0xFF}},
    {303, 4, { 40,  64, 109, 154, 0xFF, 0xFF, 0xFF}},
    {304, 4, { 32,  46,  73, 100, 0xFF, 0xFF, 0xFF}},
    {305, 4, { 44,  56,  70,  87, 0xFF, 0xFF, 0xFF}},
    {306, 4, { 55, 100, 103, 110, 0xFF, 0xFF, 0xFF}},
    {307, 4, { 22, 133, 139, 151, 0xFF, 0xFF, 0xFF}},
    {308, 4, {  3,  21,  65, 114, 0xFF, 0xFF, 0xFF}},
    {309, 4, { 47,  62, 127, 128, 0xFF, 0xFF, 0xFF}},
    {310, 4, { 38,  44,  76, 109, 0xFF, 0xFF, 0xFF}},
    {311, 4, { 29,  46,  89,  91, 0xFF, 0xFF, 0xFF}},
    {312, 4, { 19,  61,  94, 123, 0xFF, 0xFF, 0xFF}},
    {313, 4, { 22,  54, 105, 158, 0xFF, 0xFF, 0xFF}},
    {314, 4, {  8,  32, 126, 152, 0xFF, 0xFF, 0xFF}},
    {315, 4, {  7,  38,  47, 137, 0xFF, 0xFF, 0xFF}},
    {316, 4, { 33, 103, 149, 150, 0xFF, 0xFF, 0xFF}},
    {317, 4, { 43,  53,  55,  87, 0xFF, 0xFF, 0xFF}},
    {318, 4, { 80, 108, 125, 132, 0xFF, 0xFF, 0xFF}},
    {319, 4, { 13,  56,  61, 106, 0xFF, 0xFF, 0xFF}},
    {320, 4, {  5,  38, 104, 112, 0xFF, 0xFF, 0xFF}},
    {321, 4, {  4,  38, 109, 113, 0xFF, 0xFF, 0xFF}},
    {322, 4, { 16,  27, 137, 142, 0xFF, 0xFF, 0xFF}},
    {323, 4, { 45,  70,  84, 158, 0xFF, 0xFF, 0xFF}},
    {324, 4, { 29, 120, 139, 154, 0xFF, 0xFF, 0xFF}},
    {325, 4, { 12,  40,  59, 132, 0xFF, 0xFF, 0xFF}},
    {326, 4, { 38,  64,  90,  92, 0xFF, 0xFF, 0xFF}},
    {327, 4, {  8,  13,  53, 134, 0xFF, 0xFF, 0xFF}},
    {328, 4, { 27,  62,  86, 101, 0xFF, 0xFF, 0xFF}},
    {329, 4, { 46, 134, 151, 157, 0xFF, 0xFF, 0xFF}},
    {330, 4, { 52, 110, 113, 119, 0xFF, 0xFF, 0xFF}},
    {331, 4, { 23, 130, 138, 149, 0xFF, 0xFF, 0xFF}},
    {332, 4, {  5,  21, 109, 125, 0xFF, 0xFF, 0xFF}},
    {333, 4, { 19,  55, 114, 121, 0xFF, 0xFF, 0xFF}},
    {334, 4, { 42,  76,  90, 122, 0xFF, 0xFF, 0xFF}},
    {335, 4, { 33,  61, 149, 157, 0xFF, 0xFF, 0xFF}},
    {336, 4, {  8,  32,  39, 108, 0xFF, 0xFF, 0xFF}},
    {337, 4, { 37, 135, 148, 158, 0xFF, 0xFF, 0xFF}},
    {338, 4, { 28,  60, 125, 134, 0xFF, 0xFF, 0xFF}},
    {339, 4, { 49,  65, 112, 127, 0xFF, 0xFF, 0xFF}},
    {340, 4, { 64,  99, 154, 158, 0xFF, 0xFF, 0xFF}},
    {341, 4, {  7, 106, 109, 112, 0xFF, 0xFF, 0xFF}},
    {342, 4, {  1,  46,  77, 109, 0xFF, 0xFF, 0xFF}},
    {343, 4, { 19,  41,  81, 128, 0xFF, 0xFF, 0xFF}},
    {344, 4, { 45, 126, 139, 158, 0xFF, 0xFF, 0xFF}},
    {345, 4, { 32, 110, 116, 142, 0xFF, 0xFF, 0xFF}},
    {346, 4, { 24,  87,  91,  95, 0xFF, 0xFF, 0xFF}},
    {347, 4, { 93,  99, 123, 136, 0xFF, 0xFF, 0xFF}},
    {348, 4, { 52, 106, 109, 151, 0xFF, 0xFF, 0xFF}},
};

#endif /* CE_DICT_DATA_H */
