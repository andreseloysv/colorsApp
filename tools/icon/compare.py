"""Compara el render del icono con la referencia `reference/target.png`.

Uso:
    uv run --no-project --with pillow --with numpy --with scikit-image \
        --with scipy python -I compare.py [render.png] [referencia.png]

Por defecto compara `out/icon_1024.png` contra `reference/target.png`.
La caja de la hoja (esquina superior derecha, solo está en la referencia)
se excluye de todas las métricas.

Métricas:
- SSIM global y SSIM sobre la región de la C.
- IoU de silueta: el cristal se segmenta umbralizando el canal rojo (el
  fondo verde tiene R bajo; los brillos del cristal, alto), dilatando ese
  borde brillante como barrera y rellenando desde los bordes de la imagen.
- Diferencia media de color del fondo en tres bandas (arriba, centro-izquierda,
  abajo), en niveles sRGB 0-255.
- Contorno interior: SSIM y color medio en una banda de ±28 px alrededor
  del borde del hueco de la C, desglosada en barra superior, pared
  izquierda y barra inferior. Es la zona donde el render de la ronda 1
  fallaba a ojo (banda crema opaca en vez de cristal claro).

Escribe `out/compare_side_by_side.png` (referencia | render | diferencia x4),
`out/preview_small.png` (referencia y render a 180 px y 48 px) y
`out/crops_side_by_side.png` (5 recortes 1:1 ampliados x2: barra superior,
pared interior izquierda, barra interior inferior y los dos extremos).
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from skimage import filters, morphology
from skimage.metrics import structural_similarity

HERE = Path(__file__).resolve().parent
# Caja de la hoja en la referencia (x0, y0, x1, y1): se excluye siempre.
LEAF_BOX = (775, 190, 965, 390)

# Borde del hueco interior de la C en píxeles (misma silueta que
# OUTLINE_PX en build_icon.py): de la punta del terminal superior a la
# del inferior, pasando por la barra superior, la pared izquierda y la
# barra inferior del hueco.
INNER_CONTOUR_PX = [(660, 434), (604, 376), (472, 376), (442, 406),
                    (442, 642), (470, 671), (600, 671), (672, 597)]
INNER_BAND_PX = 28  # semiancho de la banda de medición del contorno

# Recortes de zoom 1:1 que pide la revisión (x0, y0, x1, y1).
CROPS = {
    "barra superior": (330, 140, 720, 430),
    "pared interior izquierda": (370, 330, 560, 700),
    "barra interior inferior": (370, 560, 720, 760),
    "extremo superior": (580, 260, 840, 460),
    "extremo inferior": (580, 550, 840, 760),
}


def load_rgb(path, size=(1024, 1024)):
    img = Image.open(path).convert("RGB")
    if img.size != size:
        img = img.resize(size, Image.LANCZOS)
    return np.asarray(img).astype(np.float64) / 255.0


def leaf_mask(shape):
    """True donde SÍ se evalúa (fuera de la caja de la hoja)."""
    m = np.ones(shape[:2], dtype=bool)
    x0, y0, x1, y1 = LEAF_BOX
    m[y0:y1, x0:x1] = False
    return m


def silhouette(rgb):
    """Máscara de la C: el borde brillante del cristal (canal R alto, el
    fondo verde lo tiene bajo) unido a los bordes de gradiente fuerte forma
    una barrera cerrada; el exterior es lo alcanzable desde el marco sin
    cruzarla, y la C es la componente mayor del resto."""
    bright = rgb[:, :, 0] > 0.42
    mx = rgb.max(axis=2)
    sat = np.where(mx > 0, (mx - rgb.min(axis=2)) / np.maximum(mx, 1e-6), 0)
    edge = (filters.sobel(rgb.mean(axis=2)) > 0.07) & (sat < 0.45)
    seed = morphology.remove_small_objects(bright | edge, max_size=8)
    barrier = morphology.dilation(
        morphology.closing(seed, morphology.disk(4)), morphology.disk(7))
    labels, _ = ndimage.label(~barrier)
    border = set(np.unique(np.concatenate(
        [labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1]])))
    border.discard(0)  # 0 = píxeles de la propia barrera, no una región
    exterior = np.isin(labels, list(border))
    mask = ndimage.binary_fill_holes(~exterior)
    labels2, n2 = ndimage.label(mask)
    if n2 == 0:
        return mask
    sizes = ndimage.sum(mask, labels2, range(1, n2 + 1))
    mask = labels2 == (1 + int(np.argmax(sizes)))
    return morphology.erosion(mask, morphology.disk(4))


def inner_band_masks(shape, valid):
    """Máscaras de la banda de ±INNER_BAND_PX alrededor del contorno
    interior: la completa y el desglose superior / izquierda / inferior
    (por posición vertical del píxel)."""
    from skimage.draw import line as sk_line
    contour = np.zeros(shape[:2], dtype=bool)
    for (xa, ya), (xb, yb) in zip(INNER_CONTOUR_PX, INNER_CONTOUR_PX[1:]):
        rr, cc = sk_line(ya, xa, yb, xb)
        contour[rr, cc] = True
    dist = ndimage.distance_transform_edt(~contour)
    band = (dist <= INNER_BAND_PX) & valid
    yy = np.arange(shape[0])[:, None]
    parts = {
        "barra superior": band & (yy <= 440),
        "pared izquierda": band & (yy > 440) & (yy < 600),
        "barra inferior": band & (yy >= 600),
    }
    return band, parts


def band_report(target, render, mask):
    """SSIM medio y color medio (ref/render) dentro de una máscara."""
    ssim = ssim_masked(target, render, mask)
    ct = target[mask].mean(axis=0) * 255
    cr = render[mask].mean(axis=0) * 255
    diff = np.abs(target[mask] - render[mask]).mean(axis=0) * 255
    hexof = lambda c: f"#{int(c[0]):02X}{int(c[1]):02X}{int(c[2]):02X}"
    return (f"SSIM {ssim:.4f}  ref {hexof(ct)} render {hexof(cr)} "
            f"|dif| media {diff.mean():.1f} (R {diff[0]:.1f} G {diff[1]:.1f} "
            f"B {diff[2]:.1f})  [{int(mask.sum())} px]")


def ssim_masked(a, b, valid):
    """SSIM medio solo en píxeles válidos (mapa SSIM recortado al válido)."""
    _, smap = structural_similarity(a, b, channel_axis=2, data_range=1.0,
                                    full=True)
    return float(smap[valid].mean())


def main():
    render_path = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "out" / "icon_1024.png"
    target_path = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE / "reference" / "target.png"
    out_dir = HERE / "out"
    out_dir.mkdir(exist_ok=True)

    target = load_rgb(target_path)
    render = load_rgb(render_path)
    valid = leaf_mask(target.shape)

    # --- Siluetas e IoU ---
    sil_t = silhouette(target)
    sil_r = silhouette(render)
    inter = (sil_t & sil_r & valid).sum()
    union = ((sil_t | sil_r) & valid).sum()
    iou = float(inter / union) if union else 0.0

    # --- SSIM global y en la región de la C ---
    ssim_global = ssim_masked(target, render, valid)
    ys, xs = np.where(sil_t & valid)
    pad = 30
    y0, y1 = max(0, ys.min() - pad), min(1024, ys.max() + pad)
    x0, x1 = max(0, xs.min() - pad), min(1024, xs.max() + pad)
    crop_valid = valid[y0:y1, x0:x1]
    ssim_c = ssim_masked(target[y0:y1, x0:x1], render[y0:y1, x0:x1], crop_valid)

    # --- Fondo por bandas (zonas sin C en ninguna de las dos) ---
    bg = valid & ~sil_t & ~sil_r
    bands = {
        "arriba (y 0-120)": (slice(0, 120), slice(0, 1024)),
        "centro-izq (x 0-150)": (slice(420, 620), slice(0, 150)),
        "abajo (y 920-1024)": (slice(920, 1024), slice(0, 1024)),
    }
    band_lines = []
    for name, (sy, sx) in bands.items():
        sel = bg[sy, sx]
        if sel.sum() < 100:
            band_lines.append(f"  {name}: sin píxeles de fondo suficientes")
            continue
        dt = target[sy, sx][sel].mean(axis=0) * 255
        dr = render[sy, sx][sel].mean(axis=0) * 255
        diff = np.abs(dt - dr)
        band_lines.append(
            f"  {name}: ref #{int(dt[0]):02X}{int(dt[1]):02X}{int(dt[2]):02X} "
            f"render #{int(dr[0]):02X}{int(dr[1]):02X}{int(dr[2]):02X} "
            f"|dif| media {diff.mean():.1f} (R {diff[0]:.1f} G {diff[1]:.1f} B {diff[2]:.1f})")

    # --- Contorno interior: banda alrededor del hueco ---
    inner_band, inner_parts = inner_band_masks(target.shape, valid)
    inner_lines = [f"  completa:        {band_report(target, render, inner_band)}"]
    for part_name, part_mask in inner_parts.items():
        inner_lines.append(
            f"  {part_name + ':':<19}{band_report(target, render, part_mask)}")

    # --- Imágenes de comparación ---
    t8 = Image.open(target_path).convert("RGB").resize((1024, 1024), Image.LANCZOS)
    r8 = Image.open(render_path).convert("RGB").resize((1024, 1024), Image.LANCZOS)
    diff = np.clip(np.abs(target - render) * 4.0, 0, 1)
    diff[~valid] = (0.5, 0.0, 0.5)  # caja de la hoja en magenta
    d8 = Image.fromarray((diff * 255).astype(np.uint8))
    sheet = Image.new("RGB", (1024 * 3, 1024))
    sheet.paste(t8, (0, 0))
    sheet.paste(r8, (1024, 0))
    sheet.paste(d8, (2048, 0))
    sheet_path = out_dir / "compare_side_by_side.png"
    sheet.save(sheet_path)

    small = Image.new("RGB", (180 * 2 + 48 * 2 + 30, 180), (24, 24, 24))
    x = 0
    for im, s in ((t8, 180), (r8, 180)):
        small.paste(im.resize((s, s), Image.LANCZOS), (x, 0))
        x += s + 10
    for im, s in ((t8, 48), (r8, 48)):
        small.paste(im.resize((s, s), Image.LANCZOS), (x, 180 - s))
        x += s + 10
    small_path = out_dir / "preview_small.png"
    small.save(small_path)

    # Recortes 1:1 (x2 con vecino más cercano, sin suavizar): cada zona
    # con referencia a la izquierda y render a la derecha, una por fila.
    from PIL import ImageDraw
    rows = []
    for crop_name, (cx0, cy0, cx1, cy1) in CROPS.items():
        cw, ch = (cx1 - cx0) * 2, (cy1 - cy0) * 2
        row = Image.new("RGB", (cw * 2 + 6, ch + 26), (24, 24, 24))
        row.paste(t8.crop((cx0, cy0, cx1, cy1)).resize((cw, ch), Image.NEAREST), (0, 26))
        row.paste(r8.crop((cx0, cy0, cx1, cy1)).resize((cw, ch), Image.NEAREST), (cw + 6, 26))
        draw = ImageDraw.Draw(row)
        draw.text((6, 7), f"{crop_name} - ref", fill=(230, 230, 230))
        draw.text((cw + 12, 7), f"{crop_name} - render", fill=(230, 230, 230))
        rows.append(row)
    crops_sheet = Image.new(
        "RGB", (max(r.width for r in rows), sum(r.height + 6 for r in rows)),
        (24, 24, 24))
    y_off = 0
    for row in rows:
        crops_sheet.paste(row, (0, y_off))
        y_off += row.height + 6
    crops_path = out_dir / "crops_side_by_side.png"
    crops_sheet.save(crops_path)

    print(f"Render:      {render_path}")
    print(f"Referencia:  {target_path} (caja de la hoja excluida: {LEAF_BOX})")
    print(f"IoU silueta: {iou:.4f}  (área ref {int((sil_t & valid).sum())} px, "
          f"render {int((sil_r & valid).sum())} px)")
    print(f"SSIM global: {ssim_global:.4f}")
    print(f"SSIM región C: {ssim_c:.4f}  (recorte x {x0}-{x1}, y {y0}-{y1})")
    print("Fondo por bandas:")
    for line in band_lines:
        print(line)
    print(f"Contorno interior (banda de ±{INNER_BAND_PX} px alrededor del hueco):")
    for line in inner_lines:
        print(line)
    print(f"Side-by-side: {sheet_path}")
    print(f"Previews:     {small_path} (180 px ref/render, 48 px ref/render)")
    print(f"Recortes 1:1: {crops_path} (5 zonas, ref | render, x2 sin suavizar)")


if __name__ == "__main__":
    main()
