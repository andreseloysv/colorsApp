"""Icono ChromaSol: C octogonal de cristal facetado sobre fondo verde azulado.

Recrea `reference/target.png` sin la hoja (la esquina superior derecha sigue
como cristal limpio, como en `reference/leafless_variant_A.png`).

Uso:
    blender -b --factory-startup --python-exit-code 1 -P build_icon.py -- [--preview|--final]
    opciones extra tras `--`: --res N --samples N --out ruta.png --no-blend

La silueta de la C está trazada en coordenadas de píxel de la referencia
(1024x1024) y se proyecta con cámara ortográfica, así que el contorno del
render coincide con el de la imagen objetivo. Ajustes finos por entorno:
ICON_BG_STRENGTH, ICON_CARD_WHITE, ICON_CARD_GOLD, ICON_IOR, ICON_ROUGHNESS,
ICON_GLARE, ICON_SEED (ver README.md).
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

# ---------------------------------------------------------------------------
# Parámetros
# ---------------------------------------------------------------------------

def _env(name, default):
    return float(os.environ.get(name, default))


P = {
    # Encuadre: la ortográfica abarca ORTHO unidades de mundo en 1024 px.
    "ortho": 4.2,
    # Geometría de la C (en píxeles equivalentes salvo indicación). Los
    # biseles son estrechos y nítidos como en el objetivo (la ronda 1 los
    # hacía de 44 px y se leía como un marco liso); las aristas interiores
    # llevan un factor mayor (EDGE_RIDGE_SCALE) porque en el objetivo las
    # barras blanca superior e inferior del hueco proyectan más ancho.
    "inset_ridge_px": 13.0,     # primera fila de facetas del bisel frontal
    "inset_table_px": 27.0,     # borde de la cara frontal
    "inset_back_px": 26.0,      # primera fila del bisel trasero
    "inset_back2_px": 52.0,    # borde de la cara trasera (doble bisel)
    "y_outer_front": -0.02,     # anillo exterior (máximo ancho), lado cámara
    "y_ridge": -0.135,
    "y_table": -0.20,           # cara frontal (hacia cámara, -Y)
    "y_outer_back": 0.08,       # anillo exterior, lado fondo
    "y_back": 0.20,             # primera fila trasera
    "y_back2": 0.30,            # cara trasera
    "facet_lift": 0.016,        # levanta los puntos medios del anillo ridge
    # Cristal.
    "ior": _env("ICON_IOR", 1.52),
    "roughness": _env("ICON_ROUGHNESS", 0.02),
    # Fondo (colores sRGB 0-255 medidos en la referencia).
    "bg_top": (28, 64, 62),
    "bg_mid": (40, 84, 66),
    "bg_bottom": (50, 106, 70),
    "bg_glow_center_uv": (0.50, 0.20),   # v desde abajo; brillo bajo la C
    "bg_glow_radius": 0.68,
    "bg_glow_rgb": (46, 54, 26),
    "bg_strength": _env("ICON_BG_STRENGTH", 1.35),
    "bg_y": 3.0,
    # Tarjetas emisivas (invisibles a cámara): pintan los brillos del bisel.
    "card_white": _env("ICON_CARD_WHITE", 1.0),
    "card_gold": _env("ICON_CARD_GOLD", 1.0),
    # Partículas.
    "seed": int(_env("ICON_SEED", 7)),
    "sparkles": int(_env("ICON_SPARKLES", 320)),
    "sparkle_strength": _env("ICON_SPARKLE_STRENGTH", 1.0),
    # Render.
    "glare": _env("ICON_GLARE", 1.0),
}

# Silueta de la C en píxeles (x derecha, y abajo), medida sobre
# leafless_variant_A.png / target.png (ver compare.py). Un solo lazo:
# contorno exterior + hueco interior.
OUTLINE_PX = [
    (358, 170), (682, 170),          # borde superior
    (814, 302), (814, 388),          # terminal superior (derecha)
    (660, 434),                      # punta inferior del terminal superior
    (604, 376), (472, 376),          # borde interior superior
    (442, 406), (442, 642),          # pared interior izquierda
    (470, 671), (600, 671),          # borde interior inferior
    (672, 597),                      # punta del terminal inferior
    (814, 654), (814, 734),          # terminal inferior (derecha)
    (678, 866), (358, 866),          # borde inferior
    (209, 708), (209, 329),          # borde izquierdo
]

# Factor de ancho del bisel frontal por arista de OUTLINE_PX (la arista i
# va del punto i al i+1), uno para la fila ridge y otro para la mesa.
# Aristas del hueco interior: 5 (barra superior), 6 y 8 (chaflanes), 7
# (pared izquierda), 9 (barra inferior), 4 y 10 (diagonales a las puntas).
# Medido en perfiles de brillo del objetivo (columna x=540 y fila y=520):
# junto al hueco va una fila de cristal claro grisáceo (~22 px, con el
# filo dorado en el borde) y ENCIMA el núcleo blanco quemado (~18 px);
# en la pared izquierda la línea blanca está a ~40 px del hueco. Por eso
# la fila blanca es la segunda (ridge->mesa) y la pegada al hueco es
# cristal claro. El bisel exterior sigue estrecho: una línea nítida.
EDGE_RIDGE_SCALE = [
    1.0, 1.0, 1.0, 1.0, 1.40, 1.70, 1.55, 1.25, 1.55, 1.70, 1.40,
    1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
]
# La pared izquierda (arista 7) va casi sin factor: empinada, refleja el
# hueco oscuro y se lee como cristal claro verdoso con solo el filo
# blanco de la junta y el dorado del borde, no como una banda blanca.
EDGE_TABLE_SCALE = [
    1.0, 1.0, 1.0, 1.0, 1.30, 1.35, 1.40, 1.30, 1.40, 1.35, 1.30,
    1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
]

PX = P["ortho"] / 1024.0  # unidades de mundo por píxel


def px_to_world(x_px, y_px):
    """Píxel (origen arriba-izquierda) -> mundo (x derecha, z arriba)."""
    return ((x_px - 512.0) * PX, (512.0 - y_px) * PX)


# ---------------------------------------------------------------------------
# Geometría 2D: desplazamiento (inset) de polígono simple
# ---------------------------------------------------------------------------

def _signed_area(pts):
    a = 0.0
    for i in range(len(pts)):
        x0, z0 = pts[i]
        x1, z1 = pts[(i + 1) % len(pts)]
        a += x0 * z1 - x1 * z0
    return 0.5 * a


def _line_intersect(p, d, q, e):
    """Intersección de las rectas p+t*d y q+s*e (2D)."""
    cross = d[0] * e[1] - d[1] * e[0]
    if abs(cross) < 1e-12:
        return q
    t = ((q[0] - p[0]) * e[1] - (q[1] - p[1]) * e[0]) / cross
    return (p[0] + t * d[0], p[1] + t * d[1])


def offset_polygon(pts, dist):
    """Polígono desplazado hacia el interior. `dist` puede ser un escalar
    (todas las aristas igual) o una lista con una distancia por arista
    (bisel más ancho en las aristas interiores que en las exteriores)."""
    n = len(pts)
    dists = list(dist) if isinstance(dist, (list, tuple)) else [dist] * n
    inward = 1.0 if _signed_area(pts) > 0 else -1.0  # CCW: interior a la izq.
    lines = []
    for i in range(n):
        a = pts[i]
        b = pts[(i + 1) % n]
        ex, ez = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(ex, ez)
        ex, ez = ex / ln, ez / ln
        nx, nz = -ez * inward, ex * inward  # normal hacia el interior
        lines.append(((a[0] + nx * dists[i], a[1] + nz * dists[i]), (ex, ez)))
    out = []
    for i in range(n):
        # evita vértices disparados en esquinas agudas
        max_miter = 2.4 * max(dists[i - 1], dists[i])
        p, d = lines[i - 1]
        q, e = lines[i]
        cand = _line_intersect(p, d, q, e)
        vx, vz = cand[0] - pts[i][0], cand[1] - pts[i][1]
        ln = math.hypot(vx, vz)
        if ln > max_miter:
            cand = (pts[i][0] + vx * max_miter / ln, pts[i][1] + vz * max_miter / ln)
        out.append(cand)
    return out


def subdivide_pattern(base_pts):
    """Fracciones de subdivisión por arista, según su longitud (misma para
    todos los anillos, para que compartan topología). Devuelve además qué
    índices expandidos son vértices originales de esquina."""
    n = len(base_pts)
    fractions = []
    for i in range(n):
        a, b = base_pts[i], base_pts[(i + 1) % n]
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        if ln > 0.85:
            fractions.append([0.36, 0.68])
        elif ln > 0.45:
            fractions.append([0.5])
        else:
            fractions.append([])
    return fractions


def expand_ring(pts, fractions):
    """Inserta los puntos intermedios de cada arista. Devuelve
    (pts, es_esquina, arista): `arista[k]` es la arista base a la que
    pertenece el segmento que empieza en el punto k."""
    out, is_corner, seg_edge = [], [], []
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        out.append(a)
        is_corner.append(True)
        seg_edge.append(i)
        for f in fractions[i]:
            out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
            is_corner.append(False)
            seg_edge.append(i)
    return out, is_corner, seg_edge


def _tri_normal(verts, tri):
    a, b, c = (Vector(verts[k]) for k in tri)
    return (b - a).cross(c - a)


def _orient_outward_xz(verts, tri, out2d):
    n = _tri_normal(verts, tri)
    return tri if n.x * out2d[0] + n.z * out2d[1] >= 0 else (tri[0], tri[2], tri[1])


def _cumlen(pts):
    out = [0.0]
    for i in range(1, len(pts)):
        out.append(out[-1] + math.dist(pts[i - 1], pts[i]))
    total = out[-1] or 1.0
    return [v / total for v in out]


def strip_triangles(chain, ridge, verts):
    """Triangula la banda entre dos polilíneas (listas de índices de
    vértice) que comparten extremos, avanzando por longitud de arco.
    Devuelve triángulos orientados hacia la cámara (-Y)."""
    def pts(idxs):
        return [(verts[i][0], verts[i][2]) for i in idxs]
    fc, fr = _cumlen(pts(chain)), _cumlen(pts(ridge))
    tris = []
    i = j = 0
    while i < len(chain) - 1 or j < len(ridge) - 1:
        if j >= len(ridge) - 1 or (i < len(chain) - 1 and fc[i + 1] <= fr[j + 1]):
            tris.append((chain[i], chain[i + 1], ridge[j]))
            i += 1
        else:
            tris.append((chain[i], ridge[j + 1], ridge[j]))
            j += 1
    oriented = []
    for a, b, c in tris:
        va, vb, vc = (Vector(verts[k]) for k in (a, b, c))
        n = (vb - va).cross(vc - va)
        oriented.append((a, b, c) if n.y <= 0 else (a, c, b))
    return oriented


# Arista central que recorre el trazo de la C en la cara frontal:
# (x_px, y_px, cuánto asoma hacia la cámara). Trazada leyendo las líneas
# de faceta del objetivo: quedan pocos vértices, así las dos bandas entre
# el contorno y esta arista se triangulan en triángulos GRANDES (en abanico
# desde cada vértice), como las facetas del objetivo, y la altura alterna
# (alto/bajo) inclina cada triángulo distinto para que recoja las tarjetas
# de estudio de forma diferente: destellos blancos en unos, refracción
# oscura en los vecinos. En la ronda 1 la arista asomaba 0,018 uniforme y
# la cara se leía como un marco liso.
FRONT_RIDGE_PX = [
    (705, 305, 0.048), (605, 275, 0.028), (470, 263, 0.050), (345, 288, 0.030),
    (322, 430, 0.047), (320, 600, 0.028), (345, 752, 0.048), (470, 770, 0.028),
    (600, 730, 0.045), (695, 692, 0.030),
]


def build_crystal_mesh():
    """Sólido cerrado: anillos frontal (bisel en 2 filas), pared lateral y
    bisel trasero, cerrados por la cara frontal y la trasera."""
    base = [px_to_world(x, y) for x, y in OUTLINE_PX]
    fracs = subdivide_pattern(base)
    # Bisel frontal con ancho por arista (interiores más anchas, ver
    # EDGE_RIDGE_SCALE / EDGE_TABLE_SCALE); el trasero sigue uniforme.
    ridge_dists = [P["inset_ridge_px"] * PX * s for s in EDGE_RIDGE_SCALE]
    table_dists = [P["inset_table_px"] * PX * s for s in EDGE_TABLE_SCALE]
    rings_def = [
        (base, P["y_outer_front"], 0.0),
        (offset_polygon(base, ridge_dists), P["y_ridge"], P["facet_lift"]),
        (offset_polygon(base, table_dists), P["y_table"], 0.0),
        (base, P["y_outer_back"], 0.0),
        (offset_polygon(base, P["inset_back_px"] * PX), P["y_back"], 0.0),
        (offset_polygon(base, P["inset_back2_px"] * PX), P["y_back2"], 0.0),
    ]
    # Orden de anillos de delante (cámara, -Y) hacia atrás (+Y):
    # mesa -> ridge -> exterior frontal -> exterior trasero -> biseles traseros.
    order = [2, 1, 0, 3, 4, 5]
    verts, ring_starts, ring_counts = [], [], []
    expanded_rings = []  # (puntos 2D, es_esquina, y) por anillo, en orden
    seg_edges = []
    # Inclinación por faceta: los puntos medios de los anillos frontales se
    # desplazan en Y (profundidad; la cámara es ortográfica a lo largo de Y,
    # así que la silueta no cambia) con un patrón determinista de 3 alturas.
    # Sin esto, los dos triángulos de cada segmento del bisel son coplanares
    # y la cara se lee como un marco liso; con esto cada triángulo tiene su
    # propia normal y recoge las tarjetas de forma distinta (facetas del
    # objetivo). Amplitud por posición en `order`: mesa y ridge inclinan;
    # la cintura y el trasero quedan limpios.
    tilt_amp = {0: 0.010, 1: 0.009}
    for r_pos, idx in enumerate(order):
        pts2d, y, lift = rings_def[idx]
        expanded, is_corner, seg_edge = expand_ring(pts2d, fracs)
        seg_edges = seg_edge  # igual para todos los anillos
        expanded_rings.append((expanded, is_corner, y))
        ring_starts.append(len(verts))
        ring_counts.append(len(expanded))
        for k, ((x, z), corner) in enumerate(zip(expanded, is_corner)):
            dy = 0.0 if corner else -lift  # los puntos medios asoman hacia cámara
            if r_pos == 1 and not corner and seg_edge[k] in (5, 9):
                dy = 0.0  # barras interiores planas: encendido blanco uniforme
            if not corner and r_pos in tilt_amp:
                amp = tilt_amp[r_pos]
                if r_pos == 1 and not 4 <= seg_edge[k] <= 10:
                    amp = 0.0  # bisel exterior limpio, sin escamas
                if seg_edge[k] in (5, 7, 9):
                    amp = 0.0  # barras y pared izquierda sin inclinación extra
                if r_pos == 0 and not 4 <= seg_edge[k] <= 10:
                    amp *= 0.5
                dy += ((seg_edge[k] * 7 + k * 3 + r_pos * 5) % 3 - 1) * amp
                # Destello central de la barra inferior: el punto medio de
                # la mesa en la arista 9 asoma un poco más, así su
                # triángulo central es el que en el objetivo lanza el
                # fogonazo blanco alargado. La superior enciende uniforme.
                if r_pos == 0 and seg_edge[k] == 9:
                    dy -= 0.012
            verts.append((x, y + dy, z))
    # Dirección exterior (en el plano XZ) de cada arista base: sirve para
    # orientar las facetas de las bandas sin depender de bmesh.
    sign = 1.0 if _signed_area(base) > 0 else -1.0
    outward = []
    for i in range(len(base)):
        a, b = base[i], base[(i + 1) % len(base)]
        ex, ez = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(ex, ez)
        outward.append((ez * sign / ln, -ex * sign / ln))  # -sign * normal izq.

    faces = []
    # 0=bisel exterior, 1=caras, 2=interior claro (cristal limpio: se ve el
    # verde a través), 3=barra blanca superior, 4=barra blanca inferior.
    # Sin ningún material crema ni emisivo (era el fallo de la ronda 1):
    # el blanco, el dorado y las líneas oscuras salen de geometría +
    # cristal + filos finos.
    face_mats = []
    # Banda entre anillos consecutivos: dos triángulos por segmento,
    # diagonal alterna para que se lean facetas triangulares.
    for r in range(len(order) - 1):
        a0, b0, m = ring_starts[r], ring_starts[r + 1], ring_counts[r]
        for i in range(m):
            j = (i + 1) % m
            out2d = outward[seg_edges[i]]
            edge = seg_edges[i]
            if r == 0:  # mesa->ridge: el núcleo blanco es solo horizontal
                if edge == 5:
                    mat = 3
                elif edge == 9:
                    mat = 4
                elif edge == 7:
                    mat = 0  # pared izquierda con el glossy del bisel: gris claro
                elif 4 <= edge <= 10:
                    mat = 2
                else:
                    mat = 0
            elif r == 1 and 4 <= edge <= 10:  # pegada al hueco: cristal claro
                mat = 0 if edge == 7 else 2
            else:
                mat = 0
            if (i + r) % 2 == 0:
                tris = ((a0 + i, a0 + j, b0 + j), (a0 + i, b0 + j, b0 + i))
            else:
                tris = ((a0 + i, a0 + j, b0 + i), (a0 + j, b0 + j, b0 + i))
            for tri in tris:
                faces.append(_orient_outward_xz(verts, tri, out2d))
                face_mats.append(mat)
    # Cara trasera: n-gono plano, orientado hacia +Y (método de Newell).
    back = tuple(ring_starts[-1] + i for i in range(ring_counts[-1]))
    ny = 0.0
    for i in range(len(back)):
        a = verts[back[i]]
        b = verts[back[(i + 1) % len(back)]]
        ny += a[2] * b[0] - b[2] * a[0]  # componente y de Newell
    # Se busca normal +Y (hacia atrás): si Newell da negativa, se invierte.
    if ny < 0:
        back = tuple(reversed(back))
    faces.append(back)
    face_mats.append(1)

    # Cara frontal facetada: dos bandas entre el contorno de la mesa y una
    # arista central que asoma hacia la cámara (las grandes facetas de la
    # referencia). Los extremos de la arista nacen en el centro de los
    # cantos de cada terminal (aristas 2->3 y 12->13 del trazado).
    table_pts, table_is_corner, y_table = expanded_rings[0]
    start = ring_starts[0]
    corners = [i for i, c in enumerate(table_is_corner) if c]  # esquina k -> índice
    m = ring_counts[0]

    def edge_mid(c_a, c_b, lift=0.0):
        a, b = table_pts[corners[c_a]], table_pts[corners[c_b]]
        verts.append(((a[0] + b[0]) / 2, y_table - lift, (a[1] + b[1]) / 2))
        return len(verts) - 1

    # Los extremos de los brazos asoman como una punta de pirámide baja:
    # en el objetivo cada terminal cierra con triángulos grandes que
    # convergen en un vértice con destello (y chispas doradas en el filo).
    end_top = edge_mid(2, 3, lift=0.045)
    end_bottom = edge_mid(12, 13, lift=0.045)
    ridge = [end_top]
    for x_px, y_px, lift in FRONT_RIDGE_PX:
        x, z = px_to_world(x_px, y_px)
        verts.append((x, y_table - lift, z))
        ridge.append(len(verts) - 1)
    ridge.append(end_bottom)

    def walk(a, b, step):
        idxs, i = [], a
        while True:
            idxs.append(start + i)
            if i == b:
                break
            i = (i + step) % m
        return idxs

    # Cadena exterior: de la esquina 2 hacia atrás (0, 17, ...) hasta la 13.
    outer_chain = [end_top] + walk(corners[2], corners[13], -1) + [end_bottom]
    # Cadena interior: de la esquina 3 hacia delante (4 ... 12).
    inner_chain = [end_top] + walk(corners[3], corners[12], +1) + [end_bottom]
    cap_faces = strip_triangles(outer_chain, ridge, verts)
    cap_faces += strip_triangles(inner_chain, ridge, verts)
    faces.extend(cap_faces)
    face_mats.extend([1] * len(cap_faces))

    mesh = bpy.data.meshes.new("CrystalC")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    # Sin recalc de bmesh: las caras ya vienen orientadas a mano (el recalc
    # se cuelga con las uniones en T de la cara facetada).
    for poly, mat in zip(mesh.polygons, face_mats):
        poly.use_smooth = False
        poly.material_index = mat
    return mesh


# ---------------------------------------------------------------------------
# Materiales y fondo
# ---------------------------------------------------------------------------

def _srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _lerp3(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def make_background_image(size=512):
    """Degradado vertical medido de la referencia + brillo radial suave bajo
    la C + viñeta ligera en esquinas. Se genera en lineal (Non-Color)."""
    img = bpy.data.images.new("BackgroundTex", width=size, height=size,
                              alpha=False, float_buffer=True)
    try:
        img.colorspace_settings.name = 'Non-Color'
    except Exception:
        pass
    top, mid, bottom = P["bg_top"], P["bg_mid"], P["bg_bottom"]
    gx, gy = P["bg_glow_center_uv"]  # gy desde abajo
    pixels = [0.0] * (size * size * 4)
    for row in range(size):  # row 0 = parte inferior de la imagen
        v = row / (size - 1)
        g = 1.0 - v  # 0 arriba ... 1 abajo
        base = _lerp3(top, mid, g / 0.55) if g < 0.55 else _lerp3(mid, bottom, (g - 0.55) / 0.45)
        for col in range(size):
            u = col / (size - 1)
            d = math.hypot(u - gx, (v - gy) * 0.9)
            glow = max(0.0, 1.0 - d / P["bg_glow_radius"]) ** 2
            r = base[0] + P["bg_glow_rgb"][0] * glow
            gg = base[1] + P["bg_glow_rgb"][1] * glow
            b = base[2] + P["bg_glow_rgb"][2] * glow
            dc = math.hypot(u - 0.5, v - 0.5)
            vig = 1.0 - 0.16 * max(0.0, dc - 0.45) / 0.35
            i = (row * size + col) * 4
            pixels[i] = _srgb_to_linear(max(0.0, min(255.0, r * vig)))
            pixels[i + 1] = _srgb_to_linear(max(0.0, min(255.0, gg * vig)))
            pixels[i + 2] = _srgb_to_linear(max(0.0, min(255.0, b * vig)))
            pixels[i + 3] = 1.0
    img.pixels = pixels
    img.update()
    return img


def make_background(scene):
    img = make_background_image()
    mat = bpy.data.materials.new("Background")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.remove(nodes["Principled BSDF"])
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = 'Linear'
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = P["bg_strength"]
    mat.node_tree.links.new(tex.outputs["Color"], emit.inputs["Color"])
    mat.node_tree.links.new(emit.outputs[0], nodes["Material Output"].inputs[0])
    # Plano exacto del encuadre ortográfico, en el plano XZ tras la C.
    size = P["ortho"]
    mesh = bpy.data.meshes.new("BackgroundPlane")
    mesh.from_pydata(
        [(-size / 2, P["bg_y"], -size / 2), (size / 2, P["bg_y"], -size / 2),
         (size / 2, P["bg_y"], size / 2), (-size / 2, P["bg_y"], size / 2)],
        [], [(0, 1, 2, 3)])
    uv = mesh.uv_layers.new(name="UV")
    for loop_uv, (u, v) in zip(uv.data, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        loop_uv.uv = (u, v)
    mesh.update()
    obj = bpy.data.objects.new("Background", mesh)
    scene.collection.objects.link(obj)
    mesh.materials.append(mat)
    obj.visible_shadow = False
    return obj


def make_crystal_material():
    mat = bpy.data.materials.new("Crystal")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.remove(nodes["Principled BSDF"])
    glass = nodes.new("ShaderNodeBsdfGlass")
    glass.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    glass.inputs["Roughness"].default_value = P["roughness"]
    glass.inputs["IOR"].default_value = P["ior"]
    glass.distribution = 'GGX'
    mat.node_tree.links.new(glass.outputs[0], nodes["Material Output"].inputs["Surface"])
    # Absorción volumétrica leve: oscurece el fondo a través del cristal
    # (cuerpo ahumado verdoso de la referencia, no una ventana perfecta).
    # Más baja que en la ronda 1: el objetivo deja ver el verde limpio a
    # través de las facetas, no un cuerpo lechoso.
    density = _env("ICON_ABSORB", 0.22)
    if density > 0:
        vol = nodes.new("ShaderNodeVolumeAbsorption")
        vol.inputs["Color"].default_value = (0.62, 0.86, 0.80, 1.0)
        vol.inputs["Density"].default_value = density
        mat.node_tree.links.new(vol.outputs[0], nodes["Material Output"].inputs["Volume"])
    return mat


def make_bevel_material():
    """Facetas del bisel: cristal + una parte de brillo especular. Sin ella
    un Glass puro a 45° apenas refleja (Fresnel ~8 %) y el bisel se ve como
    una ventana; la referencia tiene facetas plateadas casi opacas."""
    mat = bpy.data.materials.new("CrystalBevel")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.remove(nodes["Principled BSDF"])
    glass = nodes.new("ShaderNodeBsdfGlass")
    glass.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    glass.inputs["Roughness"].default_value = 0.03
    glass.inputs["IOR"].default_value = P["ior"]
    glass.distribution = 'GGX'
    glossy = nodes.new("ShaderNodeBsdfGlossy")
    glossy.inputs["Color"].default_value = (0.97, 0.99, 0.99, 1.0)
    glossy.inputs["Roughness"].default_value = 0.05
    glossy.distribution = 'GGX'
    mix = nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = _env("ICON_BEVEL_GLOSS", 0.12)
    mat.node_tree.links.new(glass.outputs[0], mix.inputs[1])
    mat.node_tree.links.new(glossy.outputs[0], mix.inputs[2])
    mat.node_tree.links.new(mix.outputs[0], nodes["Material Output"].inputs["Surface"])
    return mat


def _glass_only(mat, color, roughness):
    """Deja el material como Glass puro (sin glossy, sin emisión)."""
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.remove(nodes["Principled BSDF"])
    glass = nodes.new("ShaderNodeBsdfGlass")
    glass.inputs["Color"].default_value = color + (1.0,)
    glass.inputs["Roughness"].default_value = roughness
    glass.inputs["IOR"].default_value = P["ior"]
    glass.distribution = 'GGX'
    mat.node_tree.links.new(glass.outputs[0],
                            nodes["Material Output"].inputs["Surface"])
    return glass


def make_inner_clear_material():
    """Bisel interior de cristal CLARO (pared izquierda y diagonales del
    hueco): Glass puro, sin tinte cálido y sin emisión. A través de él se
    ve el fondo verde, como en el objetivo. Sustituye al material crema
    con emisión de la ronda 1, que pintaba una banda opaca continua."""
    mat = bpy.data.materials.new("CrystalInnerClear")
    _glass_only(mat, (1.0, 1.0, 1.0), 0.02)
    return mat


def make_inner_white_material(name, color, gloss_fac, gloss_rough, env_name):
    """Barra especular blanca del hueco (superior o inferior): cristal con
    una parte alta de glossy blanco y nítido. La barra no emite: brilla
    porque su faceta refleja hacia la cámara la tarjeta blanca frontal
    puesta al otro lado del hueco (ver add_light_cards); el halo cálido lo
    dan el filo dorado del borde y el bloom, no el material."""
    mat = bpy.data.materials.new(name)
    glass = _glass_only(mat, (1.0, 1.0, 1.0), 0.02)
    nodes = mat.node_tree.nodes
    glossy = nodes.new("ShaderNodeBsdfGlossy")
    glossy.inputs["Color"].default_value = color + (1.0,)
    glossy.inputs["Roughness"].default_value = gloss_rough
    glossy.distribution = 'GGX'
    mix = nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = _env(env_name, gloss_fac)
    mat.node_tree.links.new(glass.outputs[0], mix.inputs[1])
    mat.node_tree.links.new(glossy.outputs[0], mix.inputs[2])
    # _glass_only ya enlazó el Glass a la salida: se sustituye por la mezcla.
    out = nodes["Material Output"].inputs["Surface"]
    for link in list(mat.node_tree.links):
        if link.to_socket == out:
            mat.node_tree.links.remove(link)
    mat.node_tree.links.new(mix.outputs[0], out)
    return mat



def make_emission_material(name, color, strength):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.remove(nodes["Principled BSDF"])
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = color + (1.0,)
    emit.inputs["Strength"].default_value = strength
    mat.node_tree.links.new(emit.outputs[0], nodes["Material Output"].inputs[0])
    return mat


def _look_rotation(location, target):
    direction = Vector(target) - Vector(location)
    return direction.to_track_quat('Z', 'Y').to_euler()


def add_card(scene, name, location, size, color, strength, target=(0, 0, 0)):
    """Plano emisivo invisible a cámara que se refleja en el cristal."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([(-0.5, -0.5, 0), (0.5, -0.5, 0), (0.5, 0.5, 0), (-0.5, 0.5, 0)],
                     [], [(0, 1, 2, 3)])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    obj.location = location
    obj.scale = (size[0], size[1], 1.0)
    obj.rotation_euler = _look_rotation(location, target)
    mesh.materials.append(make_emission_material(name + "Mat", color, strength))
    obj.visible_camera = False
    obj.visible_shadow = False
    return obj


def add_card_facing(scene, name, location, size, color, strength, normal):
    """Tarjeta emisiva con normal explícita (para reflejos calculados)."""
    target = tuple(location[i] + normal[i] for i in range(3))
    return add_card(scene, name, location, size, color, strength, target=target)


def add_light_cards(scene):
    w = P["card_white"]
    g = P["card_gold"]
    white = (1.0, 1.0, 1.0)
    warm = (1.0, 0.97, 0.90)
    gold = (1.0, 0.68, 0.30)
    # Marco de estudio en el plano de la C: los biseles a 45° reflejan lo que
    # tienen justo enfrente en su dirección (arriba, izquierda, derecha,
    # abajo), así que las tarjetas rodean la letra mirando hacia dentro.
    # Capa ancha (plateado general) + tira fina (línea blanca nítida).
    add_card_facing(scene, "TopFrame", (0.05, -0.10, 2.05), (3.4, 1.5), white, 2.5 * w, (0, 0, -1))
    add_card_facing(scene, "TopLine", (0.05, -0.10, 1.62), (2.7, 0.20), white, 4.5 * w, (0, 0, -1))
    add_card_facing(scene, "LeftFrame", (-2.05, -0.10, 0.0), (1.5, 3.4), white, 2.5 * w, (1, 0, 0))
    add_card_facing(scene, "LeftLine", (-1.68, -0.10, 0.0), (0.20, 2.8), white, 6.5 * w, (1, 0, 0))
    add_card_facing(scene, "RightFrame", (2.10, -0.10, 0.15), (1.2, 2.8), white, 1.9 * w, (-1, 0, 0))
    add_card_facing(scene, "BottomFrame", (0.05, -0.10, -2.05), (3.3, 1.3), warm, 2.2 * w, (0, 0, 1))
    # Suave frontal alto-izquierdo: velo muy débil en la cara frontal (si
    # sube, la cara se lava a gris lechoso; en el objetivo es verde oscuro
    # transparente con destellos sueltos, no un velo uniforme).
    add_card(scene, "FrontSoft", (-1.9, -3.6, 1.9), (1.8, 1.2), white, 0.18 * w)
    add_card(scene, "FrontTopRight", (1.8, -3.2, 2.2), (1.3, 0.7), white, 0.25 * w)
    # Tarjeta neutra y débil delante del hueco (la cálida fuerte de la
    # ronda 1 teñía de crema todo el bisel interior; ya no hace falta).
    add_card(scene, "FrontVoid", (0.45, -1.8, 0.10), (1.0, 1.0),
             white, _env("ICON_VOID_CARD", 0.9))
    # Reflectores de las barras interiores: la faceta (ancha y tendida) de
    # la barra superior refleja el rayo de cámara hacia abajo en el plano
    # de la C, y la de la inferior hacia arriba. Dos tiras blancas
    # intensas en ese plano (no delante: delante lavarían la cara frontal)
    # encienden las barras blancas del objetivo por puro reflejo.
    add_card(scene, "InnerTopReflector", (0.15, -0.25, -1.50), (1.30, 0.70),
             white, _env("ICON_INNER_REFL", 12.0) * w)
    add_card(scene, "InnerBottomReflector", (0.15, -0.25, 1.65), (2.20, 0.70),
             white, _env("ICON_INNER_REFL_BOT", 8.0) * w)
    # Reflectores diagonales: los chaflanes y diagonales del hueco
    # reflejan en diagonal en el mismo plano; sin tarjetas ahí salían
    # como triángulos negros en los extremos de las barras.
    add_card(scene, "InnerDiagTopLeft", (-1.2, -0.25, -1.0), (0.7, 0.7), white, 8.0 * w)
    add_card(scene, "InnerDiagTopRight", (1.3, -0.25, -0.9), (0.7, 0.7), white, 8.0 * w)
    add_card(scene, "InnerDiagBotLeft", (-1.2, -0.25, 1.1), (0.7, 0.7), white, 7.0 * w)
    add_card(scene, "InnerDiagBotRight", (1.3, -0.25, 1.0), (0.7, 0.7), white, 7.0 * w)
    # Puntos de destello: tarjetas minúsculas e intensas delante. Solo las
    # facetas frontales cuya inclinación acierte el ángulo las reflejan, y
    # dan los fogonazos blancos sueltos del objetivo (con un toque dorado
    # hacia los extremos de los brazos).
    add_card(scene, "GlintA", (-1.2, -2.6, 1.4), (0.28, 0.28), white, 26.0 * w)
    add_card(scene, "GlintB", (1.4, -2.6, -1.0), (0.22, 0.22),
             (1.0, 0.95, 0.85), 22.0 * w)
    add_card(scene, "GlintGold", (1.1, -2.4, 0.55), (0.18, 0.18), gold, 18.0 * g)
    # Luz puntual cálida en el hueco: baña los cantos interiores y, con el
    # bloom de los filos dorados, el halo cálido alrededor del hueco.
    data = bpy.data.lights.new("VoidGold", type='POINT')
    data.energy = 1.3 * g
    data.color = (1.0, 0.72, 0.38)
    data.shadow_soft_size = 0.25
    obj = bpy.data.objects.new("VoidGold", data)
    scene.collection.objects.link(obj)
    obj.location = (0.25, -0.55, 0.0)


def add_glow_ribbon(scene, name, points_px, width_px, y_center, color, strength,
                      inward_px=4.0):
    """Barra emisiva fina que sigue un borde de la C, semienterrada en el
    canto del cristal: produce la línea dorada luminosa de la referencia
    (con el bloom, el halo que se derrama sobre el fondo). El material de
    la C queda a la derecha del recorrido (en coordenadas de imagen)."""
    # Dirección de inglete por punto (en píxeles) y centro desplazado.
    centers = []
    n = len(points_px)
    for i in range(n):
        if i == 0:
            d = (points_px[1][0] - points_px[0][0], points_px[1][1] - points_px[0][1])
        elif i == n - 1:
            d = (points_px[-1][0] - points_px[-2][0], points_px[-1][1] - points_px[-2][1])
        else:
            d = (points_px[i + 1][0] - points_px[i - 1][0],
                 points_px[i + 1][1] - points_px[i - 1][1])
        ln = math.hypot(*d) or 1.0
        # Derecha del recorrido en imagen (y hacia abajo): (-dy, dx).
        rx, ry = -d[1] / ln, d[0] / ln
        cx = points_px[i][0] + rx * inward_px
        cy = points_px[i][1] + ry * inward_px
        centers.append((cx, cy, rx, ry))
    half = width_px / 2.0
    thick = 0.012
    verts, faces = [], []
    for cx, cy, rx, ry in centers:
        for sx, sy in ((cx - rx * half, cy - ry * half), (cx + rx * half, cy + ry * half)):
            x, z = px_to_world(sx, sy)
            verts.append((x, y_center - thick, z))
            verts.append((x, y_center + thick, z))
    # Por estación: 0=izq-delante, 1=izq-detrás, 2=der-delante, 3=der-detrás.
    for i in range(n - 1):
        a, b = i * 4, (i + 1) * 4
        faces += [
            (a + 0, b + 0, b + 2, a + 2),  # frente (hacia cámara)
            (a + 1, a + 3, b + 3, b + 1),  # detrás
            (a + 0, a + 1, b + 1, b + 0),  # canto izquierdo
            (a + 2, b + 2, b + 3, a + 3),  # canto derecho
            (a + 0, a + 2, a + 3, a + 1),  # tapa inicial (solo i=0 importa)
        ]
    faces.append(tuple(reversed(faces[-1])))  # tapa final aproximada
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    mesh.materials.append(make_emission_material(name + "Mat", color, strength))
    obj.visible_shadow = False
    return obj


def add_edge_glows(scene):
    """Filos luminosos finos semienterrados en los cantos (geometría +
    emisión localizada, lo único emisivo de la C). En el objetivo son
    líneas de 2-3 px, no bandas: dorada por todo el borde del hueco,
    blanca por la junta entre facetas de la pared interior izquierda,
    dorada fina por el perímetro exterior y dorada en los filos de los
    dos extremos (con el bloom dan el halo cálido, más fuerte en las
    barras interiores superior e inferior)."""
    gold = (1.0, 0.62, 0.18)
    white = (1.0, 1.0, 1.0)
    strength = _env("ICON_GLOW", 2.6)  # más alto quema el dorado a beige en AgX
    # Dorado por todo el borde del hueco (de punta a punta de los brazos).
    inner = [(660, 434), (604, 376), (472, 376), (442, 406), (442, 642),
             (470, 671), (600, 671), (672, 597)]
    add_glow_ribbon(scene, "GoldInnerEdge", inner, 2.4, -0.045, gold, strength,
                    inward_px=1.5)
    # Blanca por la junta entre el bisel y la cara frontal en la pared
    # interior izquierda (~38 px dentro del material desde el hueco,
    # medido en el perfil de brillo del objetivo a y=520).
    left_line = [(434, 398), (404, 420), (404, 628), (432, 657)]
    add_glow_ribbon(scene, "WhiteInnerLeft", left_line, 3.0, -0.15, white,
                    strength * 1.05, inward_px=0.0)
    # Dorado fino por el perímetro exterior: más fuerte arriba y abajo a
    # la derecha, tenue en el lado izquierdo, como en el objetivo.
    add_glow_ribbon(scene, "GoldOuterTop",
                    [(358, 170), (682, 170), (814, 302), (814, 388)],
                    2.0, -0.035, gold, strength * 0.55, inward_px=1.5)
    add_glow_ribbon(scene, "GoldOuterBottom",
                    [(814, 654), (814, 734), (678, 866), (358, 866), (209, 708)],
                    2.0, -0.035, gold, strength * 0.45, inward_px=1.5)
    add_glow_ribbon(scene, "GoldOuterLeft",
                    [(209, 708), (209, 329), (358, 170)],
                    2.0, -0.035, gold, strength * 0.20, inward_px=1.5)
    # Dorado en los filos inferiores/superiores de los dos extremos: las
    # chispas doradas de las puntas de los brazos en el objetivo.
    add_glow_ribbon(scene, "GoldTipTop", [(814, 388), (660, 434)],
                    2.4, -0.04, gold, strength * 0.75, inward_px=1.5)
    add_glow_ribbon(scene, "GoldTipBottom", [(672, 597), (814, 654)],
                    2.4, -0.04, gold, strength * 0.65, inward_px=1.5)


def add_sparkles(scene):
    """Partículas verdes/doradas: esferas emisivas minúsculas delante y
    detrás de la C (semilla fija, reproducible)."""
    rng = random.Random(P["seed"])
    hotspots = [  # (x_px, y_px, dispersión_px): zonas con más densidad
        (520, 230, 170), (700, 330, 120), (300, 470, 140),
        (620, 690, 150), (730, 640, 110), (430, 790, 160), (520, 520, 200),
    ]
    # Mezcla del objetivo: ~55 % verdes / 45 % doradas, casi todas
    # minúsculas y saturadas (no blanquecinas) y un ~18 % grandes y suaves
    # (radio x2,3 con poca fuerza: se leen como motas luminosas blandas).
    groups = {"green": [], "gold": [], "green_soft": [], "gold_soft": []}
    for _ in range(P["sparkles"]):
        if rng.random() < 0.85:
            hx, hy, spread = rng.choice(hotspots)
            x_px = rng.gauss(hx, spread)
            y_px = rng.gauss(hy, spread)
        else:
            x_px = rng.uniform(60, 980)
            y_px = rng.uniform(60, 960)
        x, z = px_to_world(x_px, y_px)
        front = rng.random() < 0.38
        y = rng.uniform(-1.5, -0.38) if front else rng.uniform(0.38, 2.3)
        soft = rng.random() < 0.18
        r = rng.uniform(0.0048, 0.0110) * (2.3 if soft else 1.0)
        key = "green" if rng.random() < 0.55 else "gold"
        if soft:
            key += "_soft"
        groups[key].append((x, y, z, r))
    specs = {
        "green": ((0.05, 1.0, 0.28), 2.6),
        "gold": ((1.0, 0.70, 0.22), 2.3),
        "green_soft": ((0.08, 1.0, 0.34), 0.85),
        "gold_soft": ((1.0, 0.74, 0.28), 0.80),
    }
    for key, items in groups.items():
        bm = bmesh.new()
        for x, y, z, r in items:
            bmesh.ops.create_icosphere(
                bm, subdivisions=1, radius=r,
                matrix=Matrix.Translation((x, y, z)))
        mesh = bpy.data.meshes.new("Sparkles_" + key)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new("Sparkles_" + key, mesh)
        scene.collection.objects.link(obj)
        color, strength = specs[key]
        mesh.materials.append(make_emission_material(
            "SparkleMat_" + key, color, strength * P["sparkle_strength"]))
        obj.visible_shadow = False


# ---------------------------------------------------------------------------
# Escena, cámara y render
# ---------------------------------------------------------------------------

def setup_glare(scene):
    """Bloom suave en compositor (halo de los bordes dorados y partículas).
    La API cambió entre versiones; si no está, se sigue sin él."""
    if P["glare"] <= 0:
        return
    try:
        tree = None
        if hasattr(scene, "compositing_node_group"):
            if scene.compositing_node_group is None:
                group = bpy.data.node_groups.new("Compositor", "CompositorNodeTree")
                scene.compositing_node_group = group
            tree = scene.compositing_node_group
            # En Blender 5.x la imagen renderizada entra por un nodo
            # "Render Layers" dentro del grupo (la entrada de grupo queda
            # vacía); la salida del grupo es la imagen final.
            outs = [s.name for s in tree.interface.items_tree
                    if getattr(s, "in_out", None) == 'OUTPUT']
            if "Image" not in outs:
                tree.interface.new_socket("Image", in_out='OUTPUT', socket_type='NodeSocketColor')
            rl = tree.nodes.new("CompositorNodeRLayers")
            out = tree.nodes.new("NodeGroupOutput")
            try:
                out.is_active_output = True
            except Exception:
                pass
            glare = tree.nodes.new("CompositorNodeGlare")
            if "Type" in glare.inputs:
                glare.inputs["Type"].default_value = 'Bloom'
            if "Strength" in glare.inputs:
                glare.inputs["Strength"].default_value = 0.20 * P["glare"]
            if "Threshold" in glare.inputs:
                glare.inputs["Threshold"].default_value = 0.9
            if "Size" in glare.inputs:
                glare.inputs["Size"].default_value = 0.50
            tree.links.new(rl.outputs["Image"], glare.inputs["Image"])
            tree.links.new(glare.outputs["Image"], out.inputs["Image"])
        elif getattr(scene, "node_tree", None) is not None or hasattr(scene, "use_nodes"):
            scene.use_nodes = True
            tree = scene.node_tree
            rl = tree.nodes.get("Render Layers") or tree.nodes.new("CompositorNodeRLayers")
            comp = tree.nodes.get("Composite") or tree.nodes.new("CompositorNodeComposite")
            glare = tree.nodes.new("CompositorNodeGlare")
            tree.links.new(rl.outputs["Image"], glare.inputs["Image"])
            tree.links.new(glare.outputs["Image"], comp.inputs["Image"])
        print("GLARE: activado")
    except Exception as exc:  # el bloom no debe tumbar el render
        print("GLARE: no disponible (", exc, ")")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"mode": "final", "res": None, "samples": None, "out": None, "blend": True}
    it = iter(range(len(argv)))
    for i in it:
        a = argv[i]
        if a == "--preview":
            opts["mode"] = "preview"
        elif a == "--final":
            opts["mode"] = "final"
        elif a == "--res":
            opts["res"] = int(argv[next(it)])
        elif a == "--samples":
            opts["samples"] = int(argv[next(it)])
        elif a == "--out":
            opts["out"] = argv[next(it)]
        elif a == "--no-blend":
            opts["blend"] = False
    if opts["mode"] == "preview":
        opts["res"] = opts["res"] or 512
        opts["samples"] = opts["samples"] or 48
    else:
        opts["res"] = opts["res"] or 1024
        opts["samples"] = opts["samples"] or 220
    return opts


def main():
    opts = parse_args()
    here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
    out_dir = os.path.join(here, "out")
    os.makedirs(out_dir, exist_ok=True)
    out_png = opts["out"] or os.path.join(
        out_dir, "icon_1024.png" if opts["mode"] == "final" else "preview.png")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    # Mundo casi negro verdoso: el fondo visible lo pone el plano degradado.
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg_node = world.node_tree.nodes["Background"]
    bg_node.inputs["Color"].default_value = (0.030, 0.045, 0.042, 1.0)
    bg_node.inputs["Strength"].default_value = 1.0

    make_background(scene)

    crystal = bpy.data.objects.new("CrystalC", build_crystal_mesh())
    scene.collection.objects.link(crystal)
    crystal.data.materials.append(make_bevel_material())   # índice 0: bisel ext.
    crystal.data.materials.append(make_crystal_material())  # índice 1: caras
    crystal.data.materials.append(make_inner_clear_material())  # índice 2: claro
    # índice 3: barra blanca superior del hueco; índice 4: barra inferior
    crystal.data.materials.append(make_inner_white_material(
        "CrystalInnerTopWhite", (1.0, 1.0, 1.0), 0.62, 0.10, "ICON_INNER_WHITE"))
    crystal.data.materials.append(make_inner_white_material(
        "CrystalInnerBottomWhite", (1.0, 0.985, 0.94), 0.48, 0.12,
        "ICON_INNER_WHITE_BOT"))
    crystal.visible_shadow = False  # el cristal no proyecta sombra opaca

    add_light_cards(scene)
    add_edge_glows(scene)
    add_sparkles(scene)

    # Cámara ortográfica frontal: sin perspectiva, la silueta coincide 1:1
    # con el trazado en píxeles.
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = P["ortho"]
    cam = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = (0, -8, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)

    # Render Cycles en GPU Metal, con rebotes de sobra para el cristal.
    scene.render.engine = 'CYCLES'
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for dev in prefs.devices:
            dev.use = dev.type == 'METAL'
        scene.cycles.device = 'GPU'
    except Exception as exc:
        print("GPU Metal no disponible, CPU:", exc)
    cyc = scene.cycles
    cyc.samples = opts["samples"]
    cyc.use_denoising = True
    try:
        cyc.denoiser = 'OPENIMAGEDENOISE'
    except Exception:
        pass
    cyc.max_bounces = 40
    cyc.transmission_bounces = 40
    cyc.glossy_bounces = 32
    cyc.transparent_max_bounces = 40
    cyc.caustics_reflective = False
    cyc.caustics_refractive = False
    cyc.blur_glossy = 0.0

    scene.view_settings.view_transform = 'AgX'
    for look in ('AgX - Medium High Contrast', 'Medium High Contrast'):
        try:
            scene.view_settings.look = look
            break
        except Exception:
            continue

    scene.render.resolution_x = opts["res"]
    scene.render.resolution_y = opts["res"]
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = out_png

    setup_glare(scene)

    if opts["blend"]:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "icon.blend"))

    bpy.ops.render.render(write_still=True)
    print("RENDERED", out_png, opts["res"], opts["samples"])


if __name__ == "__main__":
    main()

