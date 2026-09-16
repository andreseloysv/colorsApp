/*
 * ce_mask.c — máscaras de ropa: regiones del cuerpo a partir de la pose
 * (ce_mask_clothing_regions), recorte de cabeza sin pose (ce_mask_cut_head) y
 * exclusión de piel con un modelo gaussiano adaptativo en CIELAB muestreado de
 * la cara de cada persona (ce_skin_model_fit, ce_mask_exclude_skin) y separación
 * de instancias que juntan a varias personas con semillas de cara o pose
 * (ce_mask_split_instance).
 *
 * Geometría: todo se evalúa en el centro de cada píxel (x + 0.5, y + 0.5),
 * sin antialiasing, con distancias al cuadrado relativas a un punto de
 * referencia (p − A, B − A): solo +, −, ×, ÷, sqrt y comparaciones, en orden
 * fijo. No hay funciones trascendentes (ni ce_libm hace falta), así que el
 * resultado es bit a bit igual en nativo y WASM. La piel usa el Lab de
 * ce_srgb8_to_lab (que sí pasa por ce_libm) calculado con una tabla por canal
 * bit a bit equivalente (ce_srgb8_xyz_table, ce_internal.h) y productos en
 * orden fijo.
 *
 * Reglas: C11, sin I/O, sin malloc, sin estáticos mutables, todo en double,
 * sin contracción FMA, recorridos en orden de índice, nunca aborta y nunca
 * modifica la máscara cuando devuelve un error.
 */
#include "ce_internal.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>

#pragma STDC FP_CONTRACT OFF

/* ------------------------------------------------------------------------
 * Regiones de ropa
 * ---------------------------------------------------------------------- */

void ce_region_opts_default(ce_region_opts *o)
{
    if (o == NULL) {
        return;
    }
    o->min_confidence = 0.3;
    o->torso_margin = 0.12;
    o->limb_width = 0.45;
    o->include_upper_arms = 1;
    o->include_forearms = 0;
    o->include_legs = 1;
    o->include_lower_legs = 1;
}

static int ce_flag_valid(int v)
{
    return v == 0 || v == 1;
}

static int ce_region_opts_valid(const ce_region_opts *o)
{
    /* Las comparaciones con NaN son falsas: NaN queda fuera de rango. */
    if (!(o->min_confidence >= 0.0 && o->min_confidence <= 1.0)) return 0;
    if (!(o->torso_margin >= 0.0 && o->torso_margin <= 1.0)) return 0;
    if (!(o->limb_width >= 0.0 && o->limb_width <= 2.0)) return 0;
    if (!ce_flag_valid(o->include_upper_arms) || !ce_flag_valid(o->include_forearms)) return 0;
    if (!ce_flag_valid(o->include_legs) || !ce_flag_valid(o->include_lower_legs)) return 0;
    return 1;
}

static int ce_dims_valid(int width, int height)
{
    return width >= 1 && height >= 1 && width <= CE_IMAGE_MAX_SIDE && height <= CE_IMAGE_MAX_SIDE;
}

typedef struct ce_pt {
    double x;
    double y;
} ce_pt;

/* Punto utilizable: confianza finita > 0 y >= min_confidence, coordenadas
 * finitas dentro de ±CE_POSE_COORD_MAX. */
static int ce_joint_ok(const ce_pose *pose, int j, double min_conf)
{
    const ce_keypoint *k = &pose->k[j];
    return isfinite(k->confidence) && k->confidence > 0.0 && k->confidence >= min_conf
        && isfinite(k->x) && isfinite(k->y)
        && fabs(k->x) <= CE_POSE_COORD_MAX && fabs(k->y) <= CE_POSE_COORD_MAX;
}

static ce_pt ce_joint_pt(const ce_pose *pose, int j)
{
    ce_pt p;
    p.x = pose->k[j].x;
    p.y = pose->k[j].y;
    return p;
}

/* Par izquierda/derecha con estimación por simetría puntual respecto a
 * `center` (cuello o raíz): falta = 2·center − otro. 0 ok, -1 si no se puede. */
static int ce_joint_pair(const ce_pose *pose, int left, int right, int center, double min_conf,
                         ce_pt *pl, ce_pt *pr)
{
    const int ol = ce_joint_ok(pose, left, min_conf);
    const int orr = ce_joint_ok(pose, right, min_conf);
    const int oc = ce_joint_ok(pose, center, min_conf);
    if (ol && orr) {
        *pl = ce_joint_pt(pose, left);
        *pr = ce_joint_pt(pose, right);
        return 0;
    }
    if (ol && oc) {
        const ce_pt c = ce_joint_pt(pose, center);
        *pl = ce_joint_pt(pose, left);
        pr->x = 2.0 * c.x - pl->x;
        pr->y = 2.0 * c.y - pl->y;
        return 0;
    }
    if (orr && oc) {
        const ce_pt c = ce_joint_pt(pose, center);
        *pr = ce_joint_pt(pose, right);
        pl->x = 2.0 * c.x - pr->x;
        pl->y = 2.0 * c.y - pr->y;
        return 0;
    }
    return -1;
}

static double ce_cross(double ux, double uy, double vx, double vy)
{
    return ux * vy - uy * vx;
}

/* Segmento (o disco si d = 0) con radio: a = origen, d = b − a. */
typedef struct ce_capsule {
    ce_pt a;
    ce_pt d;
    double dd; /* d·d */
    double r2; /* radio² */
} ce_capsule;

static ce_capsule ce_capsule_make(ce_pt a, double dx, double dy, double radius)
{
    ce_capsule c;
    c.a = a;
    c.d.x = dx;
    c.d.y = dy;
    c.dd = dx * dx + dy * dy;
    c.r2 = radius * radius;
    return c;
}

/* Distancia al cuadrado de (px, py) al segmento. Relativa a `a`: con
 * operaciones exactas es invariante (bit a bit) a espejo y traslación. */
static double ce_capsule_dist2(const ce_capsule *s, double px, double py)
{
    const double qx = px - s->a.x;
    const double qy = py - s->a.y;
    double t = 0.0, ex, ey;
    if (s->dd > 0.0) {
        t = (qx * s->d.x + qy * s->d.y) / s->dd;
        if (t < 0.0) {
            t = 0.0;
        } else if (t > 1.0) {
            t = 1.0;
        }
    }
    ex = qx - t * s->d.x;
    ey = qy - t * s->d.y;
    return ex * ex + ey * ey;
}

static int ce_capsule_contains(const ce_capsule *s, double px, double py)
{
    return ce_capsule_dist2(s, px, py) <= s->r2;
}

/* Triángulo cerrado (bordes incluidos). Los degenerados (área 0) no tienen
 * interior: su contribución al torso llega por las distancias a los lados. */
static int ce_triangle_contains(ce_pt a, ce_pt b, ce_pt c, double px, double py)
{
    double c1, c2, c3;
    if (ce_cross(b.x - a.x, b.y - a.y, c.x - a.x, c.y - a.y) == 0.0) {
        return 0;
    }
    c1 = ce_cross(b.x - a.x, b.y - a.y, px - a.x, py - a.y);
    c2 = ce_cross(c.x - b.x, c.y - b.y, px - b.x, py - b.y);
    c3 = ce_cross(a.x - c.x, a.y - c.y, px - c.x, py - c.y);
    return (c1 >= 0.0 && c2 >= 0.0 && c3 >= 0.0) || (c1 <= 0.0 && c2 <= 0.0 && c3 <= 0.0);
}

#define CE_REGION_MAX_CAPSULES 8

typedef struct ce_region {
    ce_pt torso[4];                          /* LS, RS, RH, LH */
    ce_capsule torso_edges[6];               /* los 6 pares, radio = margen */
    ce_capsule limbs[CE_REGION_MAX_CAPSULES];
    int n_limbs;
    int n_arm_limbs;                         /* limbs[0..n_arm_limbs) son brazos; el resto, piernas */
    ce_pt hips2;                             /* LH + RH (2 · punto medio de caderas) */
    ce_pt axis2;                             /* (LH + RH) − (LS + RS) (2 · eje hombros -> caderas) */
    ce_capsule hands[2];
    int n_hands;
    ce_pt side_origin;                       /* LS */
    ce_pt side_dir;                          /* RS − LS */
    double side_sign;                        /* signo del lado de las caderas (±1) */
    double min_x, min_y, max_x, max_y;       /* bbox de torso ∪ cápsulas */
} ce_region;

static void ce_bbox_add(ce_region *r, ce_pt p, double radius)
{
    if (p.x - radius < r->min_x) r->min_x = p.x - radius;
    if (p.y - radius < r->min_y) r->min_y = p.y - radius;
    if (p.x + radius > r->max_x) r->max_x = p.x + radius;
    if (p.y + radius > r->max_y) r->max_y = p.y + radius;
}

static void ce_region_add_limb(ce_region *r, const ce_pose *pose, ce_pt a, int j_b, double min_conf,
                               double radius)
{
    ce_pt b;
    if (!ce_joint_ok(pose, j_b, min_conf) || r->n_limbs >= CE_REGION_MAX_CAPSULES) {
        return;
    }
    b = ce_joint_pt(pose, j_b);
    r->limbs[r->n_limbs++] = ce_capsule_make(a, b.x - a.x, b.y - a.y, radius);
    ce_bbox_add(r, a, radius);
    ce_bbox_add(r, b, radius);
}

static void ce_region_add_hand(ce_region *r, const ce_pose *pose, int j_wrist, int j_elbow,
                               double min_conf, double sw)
{
    ce_pt w;
    if (!ce_joint_ok(pose, j_wrist, min_conf)) {
        return;
    }
    w = ce_joint_pt(pose, j_wrist);
    if (ce_joint_ok(pose, j_elbow, min_conf)) {
        const ce_pt e = ce_joint_pt(pose, j_elbow);
        const double dx = w.x - e.x;
        const double dy = w.y - e.y;
        const double len = sqrt(dx * dx + dy * dy);
        if (len > 0.0 && isfinite(len)) {
            const double hl = CE_HAND_LENGTH * sw;
            r->hands[r->n_hands++] = ce_capsule_make(w, hl * (dx / len), hl * (dy / len), CE_HAND_RADIUS * sw);
            return;
        }
    }
    r->hands[r->n_hands++] = ce_capsule_make(w, 0.0, 0.0, CE_HAND_LENGTH * sw);
}

/* Construye la región; 0 ok, CE_ERR_POSE si faltan hombros/caderas o la pose
 * es degenerada. */
static int ce_region_build(const ce_pose *pose, const ce_region_opts *o, ce_region *r)
{
    const double mc = o->min_confidence;
    ce_pt ls, rs, lh, rh;
    double sw2, sw, margin, limb_r, side_h;
    int a, b;

    if (ce_joint_pair(pose, CE_JOINT_LSHOULDER, CE_JOINT_RSHOULDER, CE_JOINT_NECK, mc, &ls, &rs) != 0
        || ce_joint_pair(pose, CE_JOINT_LHIP, CE_JOINT_RHIP, CE_JOINT_ROOT, mc, &lh, &rh) != 0) {
        return CE_ERR_POSE;
    }
    sw2 = (rs.x - ls.x) * (rs.x - ls.x) + (rs.y - ls.y) * (rs.y - ls.y);
    sw = sqrt(sw2);
    if (!(sw >= CE_POSE_MIN_SHOULDER_WIDTH) || !isfinite(sw)) {
        return CE_ERR_POSE;
    }
    r->side_origin = ls;
    r->side_dir.x = rs.x - ls.x;
    r->side_dir.y = rs.y - ls.y;
    /* 2·cross(RS − LS, punto medio de caderas − LS) sin calcular el punto medio. */
    side_h = ce_cross(r->side_dir.x, r->side_dir.y, lh.x - ls.x, lh.y - ls.y)
           + ce_cross(r->side_dir.x, r->side_dir.y, rh.x - ls.x, rh.y - ls.y);
    if (!(side_h != 0.0) || !isfinite(side_h)) {
        return CE_ERR_POSE;
    }
    r->side_sign = side_h > 0.0 ? 1.0 : -1.0;
    /* Corte arriba/abajo de ce_mask_garment_regions: recta perpendicular al eje
     * cuerpo (punto medio de hombros -> punto medio de caderas) por las caderas.
     * El eje no es nulo: side_h != 0 implica que las caderas no están sobre la
     * recta de hombros. Duplicado para no multiplicar por 0.5. */
    r->hips2.x = lh.x + rh.x;
    r->hips2.y = lh.y + rh.y;
    r->axis2.x = r->hips2.x - (ls.x + rs.x);
    r->axis2.y = r->hips2.y - (ls.y + rs.y);

    margin = o->torso_margin * sw;
    limb_r = o->limb_width * sw * 0.5;
    r->torso[0] = ls;
    r->torso[1] = rs;
    r->torso[2] = rh;
    r->torso[3] = lh;
    r->min_x = r->min_y = HUGE_VAL;
    r->max_x = r->max_y = -HUGE_VAL;
    {
        int e = 0;
        for (a = 0; a < 4; ++a) {
            ce_bbox_add(r, r->torso[a], margin);
            for (b = a + 1; b < 4; ++b) {
                r->torso_edges[e++] = ce_capsule_make(r->torso[a], r->torso[b].x - r->torso[a].x,
                                                      r->torso[b].y - r->torso[a].y, margin);
            }
        }
    }
    r->n_limbs = 0;
    if (o->include_upper_arms) {
        ce_region_add_limb(r, pose, ls, CE_JOINT_LELBOW, mc, limb_r);
        ce_region_add_limb(r, pose, rs, CE_JOINT_RELBOW, mc, limb_r);
    }
    if (o->include_forearms && ce_joint_ok(pose, CE_JOINT_LELBOW, mc)) {
        ce_region_add_limb(r, pose, ce_joint_pt(pose, CE_JOINT_LELBOW), CE_JOINT_LWRIST, mc, limb_r);
    }
    if (o->include_forearms && ce_joint_ok(pose, CE_JOINT_RELBOW, mc)) {
        ce_region_add_limb(r, pose, ce_joint_pt(pose, CE_JOINT_RELBOW), CE_JOINT_RWRIST, mc, limb_r);
    }
    r->n_arm_limbs = r->n_limbs;
    if (o->include_legs) {
        ce_region_add_limb(r, pose, lh, CE_JOINT_LKNEE, mc, limb_r);
        ce_region_add_limb(r, pose, rh, CE_JOINT_RKNEE, mc, limb_r);
    }
    if (o->include_lower_legs && ce_joint_ok(pose, CE_JOINT_LKNEE, mc)) {
        ce_region_add_limb(r, pose, ce_joint_pt(pose, CE_JOINT_LKNEE), CE_JOINT_LANKLE, mc, limb_r);
    }
    if (o->include_lower_legs && ce_joint_ok(pose, CE_JOINT_RKNEE, mc)) {
        ce_region_add_limb(r, pose, ce_joint_pt(pose, CE_JOINT_RKNEE), CE_JOINT_RANKLE, mc, limb_r);
    }
    r->n_hands = 0;
    ce_region_add_hand(r, pose, CE_JOINT_LWRIST, CE_JOINT_LELBOW, mc, sw);
    ce_region_add_hand(r, pose, CE_JOINT_RWRIST, CE_JOINT_RELBOW, mc, sw);
    return CE_OK;
}

static int ce_region_contains(const ce_region *r, double px, double py)
{
    const double s = ce_cross(r->side_dir.x, r->side_dir.y, px - r->side_origin.x, py - r->side_origin.y);
    int i;
    if (r->side_sign > 0.0 ? !(s >= 0.0) : !(s <= 0.0)) {
        return 0; /* por encima de la línea de hombros */
    }
    for (i = 0; i < r->n_hands; ++i) {
        if (ce_capsule_contains(&r->hands[i], px, py)) {
            return 0;
        }
    }
    if (ce_triangle_contains(r->torso[0], r->torso[1], r->torso[2], px, py)
        || ce_triangle_contains(r->torso[0], r->torso[2], r->torso[3], px, py)
        || ce_triangle_contains(r->torso[0], r->torso[1], r->torso[3], px, py)
        || ce_triangle_contains(r->torso[1], r->torso[2], r->torso[3], px, py)) {
        return 1;
    }
    for (i = 0; i < 6; ++i) {
        if (ce_capsule_contains(&r->torso_edges[i], px, py)) {
            return 1;
        }
    }
    for (i = 0; i < r->n_limbs; ++i) {
        if (ce_capsule_contains(&r->limbs[i], px, py)) {
            return 1;
        }
    }
    return 0;
}

/* Etiqueta de prenda de ce_mask_garment_regions: 0 fuera de la región de ropa
 * (mismos predicados que ce_region_contains), 2 = abajo, 1 = arriba. Abajo:
 * p está en una cápsula de pierna y no en el torso ni en un brazo, o p está
 * en el torso o en una pierna y más allá de la recta de corte (perpendicular
 * al eje hombros -> caderas por el punto medio de las caderas):
 * (2p − (LH + RH)) · ((LH + RH) − (LS + RS)) > 0. Sobre la recta: arriba. Un
 * muslo en horizontal (persona sentada) sigue siendo "abajo" porque la cápsula
 * de pierna fuera del torso no depende del corte. */
static int ce_region_label(const ce_region *r, double px, double py)
{
    const double s = ce_cross(r->side_dir.x, r->side_dir.y, px - r->side_origin.x, py - r->side_origin.y);
    int i, torso = 0, arm = 0, leg = 0;
    if (r->side_sign > 0.0 ? !(s >= 0.0) : !(s <= 0.0)) {
        return 0;
    }
    for (i = 0; i < r->n_hands; ++i) {
        if (ce_capsule_contains(&r->hands[i], px, py)) {
            return 0;
        }
    }
    if (ce_triangle_contains(r->torso[0], r->torso[1], r->torso[2], px, py)
        || ce_triangle_contains(r->torso[0], r->torso[2], r->torso[3], px, py)
        || ce_triangle_contains(r->torso[0], r->torso[1], r->torso[3], px, py)
        || ce_triangle_contains(r->torso[1], r->torso[2], r->torso[3], px, py)) {
        torso = 1;
    }
    for (i = 0; !torso && i < 6; ++i) {
        if (ce_capsule_contains(&r->torso_edges[i], px, py)) {
            torso = 1;
        }
    }
    for (i = 0; i < r->n_limbs; ++i) {
        if (ce_capsule_contains(&r->limbs[i], px, py)) {
            if (i < r->n_arm_limbs) {
                arm = 1;
            } else {
                leg = 1;
            }
        }
    }
    if (!torso && !arm && !leg) {
        return 0;
    }
    if (leg && !torso && !arm) {
        return 2;
    }
    if (torso || leg) {
        const double qx = (px + px) - r->hips2.x;
        const double qy = (py + py) - r->hips2.y;
        if (qx * r->axis2.x + qy * r->axis2.y > 0.0) {
            return 2;
        }
    }
    return 1;
}

/* Límite entero conservador de una coordenada: v acotado a [lo, hi]. */
static int ce_clamp_int(double v, int lo, int hi)
{
    if (!(v > (double)lo)) {
        return lo;
    }
    if (v > (double)hi) {
        return hi;
    }
    return (int)v;
}

int ce_mask_clothing_regions(const ce_pose *pose, const ce_region_opts *o, uint8_t *inout_mask,
                             int width, int height)
{
    ce_region r;
    int rc, x, y, x0, x1, y0, y1, count = 0;

    if (pose == NULL || o == NULL || inout_mask == NULL) {
        return CE_ERR_ARG;
    }
    if (!ce_dims_valid(width, height) || !ce_region_opts_valid(o)) {
        return CE_ERR_ARG;
    }
    rc = ce_region_build(pose, o, &r);
    if (rc != CE_OK) {
        return rc;
    }
    /* bbox conservadora (±2 px) de torso ∪ cápsulas; fuera no hay región. */
    x0 = ce_clamp_int(r.min_x - 2.0, 0, width - 1);
    x1 = ce_clamp_int(r.max_x + 2.0, 0, width - 1);
    y0 = ce_clamp_int(r.min_y - 2.0, 0, height - 1);
    y1 = ce_clamp_int(r.max_y + 2.0, 0, height - 1);
    if (!(r.max_x + 2.0 >= 0.0) || !(r.max_y + 2.0 >= 0.0) || !(r.min_x - 2.0 <= (double)width)
        || !(r.min_y - 2.0 <= (double)height)) {
        x0 = 1; /* bbox fuera de la imagen: región vacía */
        x1 = 0;
    }
    for (y = 0; y < height; ++y) {
        const uint8_t *row_end = inout_mask + ((size_t)y + 1u) * (size_t)width;
        uint8_t *m = inout_mask + (size_t)y * (size_t)width;
        const int row_in = (y >= y0 && y <= y1);
        const double py = (double)y + 0.5;
        for (x = 0; m < row_end; ++x, ++m) {
            if (*m == 0) {
                continue;
            }
            if (row_in && x >= x0 && x <= x1 && ce_region_contains(&r, (double)x + 0.5, py)) {
                ++count;
            } else {
                *m = 0;
            }
        }
    }
    return count;
}

int ce_mask_garment_regions(const ce_pose *pose, const ce_region_opts *o, const uint8_t *person_mask,
                            int width, int height, uint8_t *regions_out)
{
    ce_region r;
    int rc, x, y, x0, x1, y0, y1, count = 0;

    if (pose == NULL || o == NULL || person_mask == NULL || regions_out == NULL) {
        return CE_ERR_ARG;
    }
    if (!ce_dims_valid(width, height) || !ce_region_opts_valid(o)) {
        return CE_ERR_ARG;
    }
    rc = ce_region_build(pose, o, &r);
    if (rc != CE_OK) {
        return rc;
    }
    /* Misma bbox conservadora que ce_mask_clothing_regions. */
    x0 = ce_clamp_int(r.min_x - 2.0, 0, width - 1);
    x1 = ce_clamp_int(r.max_x + 2.0, 0, width - 1);
    y0 = ce_clamp_int(r.min_y - 2.0, 0, height - 1);
    y1 = ce_clamp_int(r.max_y + 2.0, 0, height - 1);
    if (!(r.max_x + 2.0 >= 0.0) || !(r.max_y + 2.0 >= 0.0) || !(r.min_x - 2.0 <= (double)width)
        || !(r.min_y - 2.0 <= (double)height)) {
        x0 = 1;
        x1 = 0;
    }
    for (y = 0; y < height; ++y) {
        const size_t row = (size_t)y * (size_t)width;
        const int row_in = (y >= y0 && y <= y1);
        const double py = (double)y + 0.5;
        for (x = 0; x < width; ++x) {
            /* Se lee la máscara antes de escribir: regions_out puede ser person_mask. */
            const uint8_t m = person_mask[row + (size_t)x];
            int label = 0;
            if (m != 0 && row_in && x >= x0 && x <= x1) {
                label = ce_region_label(&r, (double)x + 0.5, py);
            }
            regions_out[row + (size_t)x] = (uint8_t)label;
            count += (label != 0);
        }
    }
    return count;
}

int ce_mask_cut_head(uint8_t *inout_mask, int width, int height, double fraction)
{
    int y, x, first = -1, last = -1, cut, count = 0;
    if (inout_mask == NULL || !ce_dims_valid(width, height)) {
        return CE_ERR_ARG;
    }
    if (!(fraction >= 0.0 && fraction <= 0.5)) {
        return CE_ERR_ARG;
    }
    for (y = 0; y < height; ++y) {
        const uint8_t *m = inout_mask + (size_t)y * (size_t)width;
        for (x = 0; x < width; ++x) {
            if (m[x] != 0) {
                if (first < 0) first = y;
                last = y;
                break;
            }
        }
    }
    if (first < 0) {
        return 0;
    }
    /* c = floor(fraction·H + 0.5) con H <= 16384 y fraction <= 0.5: cabe en int. */
    cut = (int)(fraction * (double)(last - first + 1) + 0.5);
    for (y = first; y < first + cut; ++y) {
        uint8_t *m = inout_mask + (size_t)y * (size_t)width;
        for (x = 0; x < width; ++x) {
            m[x] = 0;
        }
    }
    for (y = first + cut; y <= last; ++y) {
        const uint8_t *m = inout_mask + (size_t)y * (size_t)width;
        for (x = 0; x < width; ++x) {
            count += (m[x] != 0);
        }
    }
    return count;
}

/* ------------------------------------------------------------------------
 * Piel adaptativa
 * ---------------------------------------------------------------------- */

void ce_skin_opts_default(ce_skin_opts *o)
{
    if (o == NULL) {
        return;
    }
    o->max_mahalanobis = 2.5;
    o->max_excluded_fraction = 0.35;
}

void ce_srgb8_xyz_table_init(ce_srgb8_xyz_table *t)
{
    int v;
    for (v = 0; v < 256; ++v) {
        t->t[0][v] = ce_srgb8_to_xyz((uint8_t)v, 0, 0);
        t->t[1][v] = ce_srgb8_to_xyz(0, (uint8_t)v, 0);
        t->t[2][v] = ce_srgb8_to_xyz(0, 0, (uint8_t)v);
    }
}

ce_lab ce_srgb8_to_lab_table(const ce_srgb8_xyz_table *t, uint8_t r, uint8_t g, uint8_t b)
{
    ce_xyz xyz;
    xyz.X = t->t[0][r].X + t->t[1][g].X + t->t[2][b].X;
    xyz.Y = t->t[0][r].Y + t->t[1][g].Y + t->t[2][b].Y;
    xyz.Z = t->t[0][r].Z + t->t[1][g].Z + t->t[2][b].Z;
    return ce_xyz_to_lab(xyz);
}

/* Lab del píxel (x, y) de una imagen validada (== ce_srgb8_to_lab). */
static ce_lab ce_pixel_lab(const ce_image *img, int bpp, int x, int y, const ce_srgb8_xyz_table *tab)
{
    const uint8_t *p = img->pixels + (size_t)y * (size_t)img->stride_bytes + (size_t)x * (size_t)bpp;
    return ce_srgb8_to_lab_table(tab, p[0], p[1], p[2]);
}

/* Inversa 3x3 por adjuntos (row-major). 0 ok; -1 si el determinante no es
 * finito y positivo (la covarianza regularizada es definida positiva). */
static int ce_mat3_inverse_spd(const double m[9], double inv[9])
{
    const double a = m[0], b = m[1], c = m[2];
    const double d = m[3], e = m[4], f = m[5];
    const double g = m[6], h = m[7], i = m[8];
    const double A = e * i - f * h;
    const double B = -(d * i - f * g);
    const double C = d * h - e * g;
    const double det = a * A + b * B + c * C;
    if (!(det > 0.0) || !isfinite(det)) {
        return -1;
    }
    inv[0] = A / det;
    inv[1] = -(b * i - c * h) / det;
    inv[2] = (b * f - c * e) / det;
    inv[3] = B / det;
    inv[4] = (a * i - c * g) / det;
    inv[5] = -(a * f - c * d) / det;
    inv[6] = C / det;
    inv[7] = -(a * h - b * g) / det;
    inv[8] = (a * e - b * d) / det;
    return 0;
}

int ce_skin_model_fit(const ce_image *img, const uint8_t *sample_mask, ce_skin_model *out)
{
    ce_srgb8_xyz_table tab;
    double sL = 0.0, sa = 0.0, sb = 0.0;
    double cLL = 0.0, cLa = 0.0, cLb = 0.0, caa = 0.0, cab = 0.0, cbb = 0.0;
    double mean[3], cov[9], inv[9], nd;
    int rc, bpp, x, y, k;
    long long n = 0;

    if (img == NULL || sample_mask == NULL || out == NULL) {
        return CE_ERR_ARG;
    }
    rc = ce_image_validate(img);
    if (rc != CE_OK) {
        return rc;
    }
    bpp = ce_image_bpp(img->fmt);
    ce_srgb8_xyz_table_init(&tab);

    for (y = 0; y < img->height; ++y) {
        const uint8_t *sm = sample_mask + (size_t)y * (size_t)img->width;
        for (x = 0; x < img->width; ++x) {
            if (sm[x] >= CE_SKIN_SAMPLE_THRESHOLD) {
                const ce_lab lab = ce_pixel_lab(img, bpp, x, y, &tab);
                sL += lab.L;
                sa += lab.a;
                sb += lab.b;
                ++n;
            }
        }
    }
    if (n < CE_SKIN_MIN_SAMPLES) {
        return CE_ERR_SKIN_SAMPLES;
    }
    nd = (double)n;
    mean[0] = sL / nd;
    mean[1] = sa / nd;
    mean[2] = sb / nd;

    for (y = 0; y < img->height; ++y) {
        const uint8_t *sm = sample_mask + (size_t)y * (size_t)img->width;
        for (x = 0; x < img->width; ++x) {
            if (sm[x] >= CE_SKIN_SAMPLE_THRESHOLD) {
                const ce_lab lab = ce_pixel_lab(img, bpp, x, y, &tab);
                const double vL = lab.L - mean[0];
                const double va = lab.a - mean[1];
                const double vb = lab.b - mean[2];
                cLL += vL * vL;
                cLa += vL * va;
                cLb += vL * vb;
                caa += va * va;
                cab += va * vb;
                cbb += vb * vb;
            }
        }
    }
    cov[0] = cLL / nd + CE_SKIN_COV_EPSILON;
    cov[1] = cLa / nd;
    cov[2] = cLb / nd;
    cov[3] = cov[1];
    cov[4] = caa / nd + CE_SKIN_COV_EPSILON;
    cov[5] = cab / nd;
    cov[6] = cov[2];
    cov[7] = cov[5];
    cov[8] = cbb / nd + CE_SKIN_COV_EPSILON;
    if (ce_mat3_inverse_spd(cov, inv) != 0) {
        return CE_ERR_SKIN_SAMPLES; /* inalcanzable con ε > 0: defensa */
    }
    out->mean.L = mean[0];
    out->mean.a = mean[1];
    out->mean.b = mean[2];
    for (k = 0; k < 9; ++k) {
        out->cov[k] = cov[k];
        out->inv_cov[k] = inv[k];
    }
    out->n = n > 2147483647LL ? 2147483647 : (int)n;
    return CE_OK;
}

/* Modelo utilizable: valores finitos, n suficiente y parte simétrica de
 * inv_cov definida positiva (Sylvester), así d² >= 0. */
static int ce_skin_model_check(const ce_skin_model *m)
{
    double s[9], m2, m3;
    int k;
    if (!isfinite(m->mean.L) || !isfinite(m->mean.a) || !isfinite(m->mean.b)) {
        return CE_ERR_ARG;
    }
    for (k = 0; k < 9; ++k) {
        if (!isfinite(m->inv_cov[k])) {
            return CE_ERR_ARG;
        }
    }
    if (m->n < CE_SKIN_MIN_SAMPLES) {
        return CE_ERR_SKIN_SAMPLES;
    }
    s[0] = m->inv_cov[0];
    s[4] = m->inv_cov[4];
    s[8] = m->inv_cov[8];
    s[1] = s[3] = 0.5 * m->inv_cov[1] + 0.5 * m->inv_cov[3];
    s[2] = s[6] = 0.5 * m->inv_cov[2] + 0.5 * m->inv_cov[6];
    s[5] = s[7] = 0.5 * m->inv_cov[5] + 0.5 * m->inv_cov[7];
    m2 = s[0] * s[4] - s[1] * s[3];
    m3 = s[0] * (s[4] * s[8] - s[5] * s[7]) - s[1] * (s[3] * s[8] - s[5] * s[6])
       + s[2] * (s[3] * s[7] - s[4] * s[6]);
    if (!(s[0] > 0.0) || !(m2 > 0.0) || !(m3 > 0.0)) {
        return CE_ERR_ARG;
    }
    return CE_OK;
}

/* ------------------------------------------------------------------------
 * Separación de instancias fusionadas
 * ---------------------------------------------------------------------- */

/* Umbral de "dentro" de la máscara de instancia (el de la cobertura en SubjectKit). */
#define CE_SPLIT_INSIDE 128u

static int ce_split_coord_ok(double v)
{
    return isfinite(v) && fabs(v) <= CE_POSE_COORD_MAX;
}

int ce_mask_split_instance(const uint8_t *mask, int width, int height, const ce_person_seed *seeds,
                           int n_seeds, uint8_t *labels_out)
{
    ce_capsule axes[CE_SPLIT_MAX_SEEDS];
    double half[CE_SPLIT_MAX_SEEDS];
    int used[CE_SPLIT_MAX_SEEDS];
    int k, x, y, n_used = 0;

    if (mask == NULL || seeds == NULL || labels_out == NULL) {
        return CE_ERR_ARG;
    }
    if (!ce_dims_valid(width, height) || n_seeds < 1 || n_seeds > CE_SPLIT_MAX_SEEDS) {
        return CE_ERR_ARG;
    }
    for (k = 0; k < n_seeds; ++k) {
        const ce_person_seed *s = &seeds[k];
        ce_pt a;
        if (!ce_split_coord_ok(s->x0) || !ce_split_coord_ok(s->y0) || !ce_split_coord_ok(s->x1)
            || !ce_split_coord_ok(s->y1)) {
            return CE_ERR_ARG;
        }
        /* NaN falla las dos comparaciones. */
        if (!(s->half_width > 0.0 && s->half_width <= CE_POSE_COORD_MAX)) {
            return CE_ERR_ARG;
        }
        a.x = s->x0;
        a.y = s->y0;
        axes[k] = ce_capsule_make(a, s->x1 - s->x0, s->y1 - s->y0, 0.0);
        half[k] = s->half_width;
        used[k] = 0;
    }
    /* Distancias <= ~3·2^20 px y half_width > 0: cada cociente es finito o
     * +inf (half_width diminuto), nunca NaN; argmin estricto = empate al
     * índice menor. */
    for (y = 0; y < height; ++y) {
        const double py = (double)y + 0.5;
        const size_t row = (size_t)y * (size_t)width;
        for (x = 0; x < width; ++x) {
            const size_t i = row + (size_t)x;
            const double px = (double)x + 0.5;
            double best_q;
            int best = 0;
            if (mask[i] < CE_SPLIT_INSIDE) {
                labels_out[i] = 0;
                continue;
            }
            best_q = sqrt(ce_capsule_dist2(&axes[0], px, py)) / half[0];
            for (k = 1; k < n_seeds; ++k) {
                const double q = sqrt(ce_capsule_dist2(&axes[k], px, py)) / half[k];
                if (q < best_q) {
                    best_q = q;
                    best = k;
                }
            }
            labels_out[i] = (uint8_t)(best + 1);
            used[best] = 1;
        }
    }
    for (k = 0; k < n_seeds; ++k) {
        n_used += used[k];
    }
    return n_used;
}

/* d² de Mahalanobis <= umbral² (NaN o inf: no es piel). */
static int ce_is_skin_lab(const ce_skin_model *m, ce_lab lab, double thr2)
{
    const double *A = m->inv_cov;
    const double vL = lab.L - m->mean.L;
    const double va = lab.a - m->mean.a;
    const double vb = lab.b - m->mean.b;
    const double d2 = vL * (A[0] * vL + A[1] * va + A[2] * vb)
                    + va * (A[3] * vL + A[4] * va + A[5] * vb)
                    + vb * (A[6] * vL + A[7] * va + A[8] * vb);
    return d2 <= thr2;
}

int ce_mask_exclude_skin(const ce_image *img, const ce_skin_model *m, const ce_skin_opts *o,
                         uint8_t *inout_mask)
{
    ce_srgb8_xyz_table tab;
    double thr2;
    long long mask_pixels = 0, excluded = 0;
    int rc, bpp, x, y;

    if (img == NULL || m == NULL || o == NULL || inout_mask == NULL) {
        return CE_ERR_ARG;
    }
    rc = ce_image_validate(img);
    if (rc != CE_OK) {
        return rc;
    }
    if (!(o->max_mahalanobis >= 0.0) || !isfinite(o->max_mahalanobis)
        || !(o->max_excluded_fraction >= 0.0 && o->max_excluded_fraction <= 1.0)) {
        return CE_ERR_ARG;
    }
    rc = ce_skin_model_check(m);
    if (rc != CE_OK) {
        return rc;
    }
    bpp = ce_image_bpp(img->fmt);
    thr2 = o->max_mahalanobis * o->max_mahalanobis;
    ce_srgb8_xyz_table_init(&tab);

    /* Pasada 1: cuenta (sin tocar la máscara). */
    for (y = 0; y < img->height; ++y) {
        const uint8_t *mk = inout_mask + (size_t)y * (size_t)img->width;
        for (x = 0; x < img->width; ++x) {
            if (mk[x] != 0) {
                ++mask_pixels;
                if (ce_is_skin_lab(m, ce_pixel_lab(img, bpp, x, y, &tab), thr2)) {
                    ++excluded;
                }
            }
        }
    }
    if (excluded == 0) {
        return CE_OK;
    }
    if ((double)excluded > o->max_excluded_fraction * (double)mask_pixels) {
        return CE_SKIN_GUARD;
    }
    /* Pasada 2: anula (mismas operaciones, mismo orden). */
    for (y = 0; y < img->height; ++y) {
        uint8_t *mk = inout_mask + (size_t)y * (size_t)img->width;
        for (x = 0; x < img->width; ++x) {
            if (mk[x] != 0 && ce_is_skin_lab(m, ce_pixel_lab(img, bpp, x, y, &tab), thr2)) {
                mk[x] = 0;
            }
        }
    }
    return CE_OK;
}
