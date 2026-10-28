# Icono ChromaSol en Blender

Recreación 3D del icono elegido (`reference/target.png`) **sin la hoja** de
la esquina superior derecha: ahí la C sigue como cristal limpio, como en
`reference/leafless_variant_A.png`. Se mantienen las partículas, la luz
dorada interior y el fondo verde.

## Ficheros

| Fichero | Qué es |
|---|---|
| `build_icon.py` | Script de Blender (Python) que construye toda la escena y renderiza. Es la única fuente de verdad: reproducible de principio a fin. |
| `render.sh` | Lanzador: Blender headless con los argumentos correctos. |
| `compare.py` | Métricas render vs. referencia + imágenes de comparación. |
| `out/icon_1024.png` | El icono final, 1024×1024. |
| `out/icon.blend` | La escena guardada del último render. |
| `out/compare_side_by_side.png` | Referencia \| render \| diferencia ×4 (la caja de la hoja va en magenta). |
| `out/crops_side_by_side.png` | 5 recortes 1:1 ×2 sin suavizar (barra superior, pared interior izquierda, barra interior inferior, dos extremos), referencia \| render. |
| `out/preview_small.png` | Referencia y render a 180 px y a 48 px. |
| `out/metrics_round2.txt` | Salida completa de `compare.py` antes (ronda 1) y después (ronda 2). |
| `reference/` | Imágenes objetivo y el intento anterior (no se tocan). |

`out/` es scratch regenerable y está en el `.gitignore` local.

## Cómo se renderiza

Requisitos: Blender 5.2 en `/Applications/Blender.app` (o variable
`BLENDER=/ruta`), sin más dependencias para el render.

```sh
cd tools/icon
./render.sh --final     # out/icon_1024.png (1024 px, 220 muestras, ~10 s en Metal)
./render.sh --preview   # out/preview.png (512 px, 48 muestras, para iterar)
```

Opciones extra tras `--` dentro de `build_icon.py`: `--res N`,
`--samples N`, `--out ruta.png`, `--no-blend`.

Comparación con la referencia (solo necesita `uv`):

```sh
uv run --no-project --with pillow --with numpy --with scikit-image --with scipy \
    python -I compare.py
```

## Cómo está construida la escena

- **Silueta trazada en píxeles**: `OUTLINE_PX` en `build_icon.py` es el
  contorno de la C medido sobre la referencia (18 vértices). La cámara es
  ortográfica y el trazado se mapea 1:1 a píxeles, así el contorno del
  render coincide con el objetivo.
- **Cristal**: sólido cerrado por anillos (mesa frontal facetada con arista
  central, bisel frontal en dos filas de facetas triangulares, pared
  lateral, doble bisel trasero). Material Glass (IOR 1,52) con absorción
  volumétrica leve; las facetas de bisel mezclan una parte de glossy
  porque un Glass puro a 45° apenas refleja y se vería como una ventana.
  El bisel frontal tiene ancho por arista (`EDGE_RIDGE_SCALE` /
  `EDGE_TABLE_SCALE`): estrecho y empinado fuera (línea nítida) y con las
  dos filas interiores medidas en perfiles de brillo del objetivo — junto
  al hueco, cristal claro grisáceo (~22 px, se ve el verde a través) y
  encima el núcleo blanco quemado (~14 px). Los puntos medios de los
  anillos frontales se inclinan en profundidad con un patrón de 3 alturas
  para que cada triángulo tenga su propia normal (facetas grandes que
  recogen las tarjetas distinto), y la arista central frontal tiene pocos
  vértices con altura alterna, trazados leyendo las líneas de faceta del
  objetivo. Sin material crema ni emisión en el cristal (ronda 1): el
  blanco es reflejo especular, el dorado son filos finos y las líneas
  oscuras son las juntas entre facetas.
- **Luz**: las luces de área no se ven en refracción, así que el estudio
  son tarjetas emisivas invisibles a cámara en el plano de la C (los
  biseles reflejan lo que tienen justo enfrente). Las barras interiores
  las encienden dos reflectores blancos en ese plano (la superior refleja
  hacia abajo; la inferior, hacia arriba) más cuatro diagonales para los
  chaflanes; tres tarjetas puntuales delante dan los destellos sueltos de
  las facetas frontales. El resplandor dorado sale de filos emisivos
  finos (2-3 px) semienterrados en los cantos — dorado por el borde del
  hueco, el perímetro exterior y las puntas; blanco por la junta de la
  pared interior izquierda — con bloom en el compositor para el halo
  cálido, más fuerte en las barras superior e inferior del hueco.
- **Fondo**: plano emisivo tras la C con textura generada en el propio
  script (degradado vertical medido de la referencia + brillo radial bajo
  la C + viñeta). Está en escena, no compuesto después, para que se
  refracte a través del cristal.
- **Partículas**: ~320 esferas emisivas delante y detrás de la C, con
  semilla fija (reproducibles): ~55 % verdes / 45 % doradas saturadas y
  un ~18 % grandes y suaves (radio ×2,3 con poca fuerza).
- **Render**: Cycles en GPU Metal, AgX, 40 rebotes de transmisión,
  denoising OIDN, bloom (nodo Glare tipo Bloom; en Blender 5.x la imagen
  entra al grupo de composición por un nodo «Render Layers», no por la
  entrada del grupo).

## Parámetros

Los principales están en el dict `P` al principio de `build_icon.py`
(geometría de anillos en píxeles, colores del fondo, IOR…). Ajustes finos
sin editar el fichero, por entorno:

| Variable | Efecto (defecto) |
|---|---|
| `ICON_CARD_WHITE` / `ICON_CARD_GOLD` | Multiplicador de tarjetas blancas / doradas (1) |
| `ICON_BEVEL_GLOSS` | Parte glossy del bisel exterior (0,12) |
| `ICON_INNER_WHITE` / `ICON_INNER_WHITE_BOT` | Parte glossy de las barras blancas superior / inferior (0,62 / 0,48) |
| `ICON_INNER_REFL` / `ICON_INNER_REFL_BOT` | Reflectores que encienden las barras (12 / 8) |
| `ICON_GLOW` | Fuerza de los filos dorados/blancos del canto (2,6) |
| `ICON_VOID_CARD` | Tarjeta neutra delante del hueco (0,9) |
| `ICON_ABSORB` | Densidad de absorción del cristal (0,22) |
| `ICON_IOR`, `ICON_ROUGHNESS` | Cristal de las caras (1,52 / 0,02) |
| `ICON_BG_STRENGTH` | Brillo del fondo (1,35) |
| `ICON_SPARKLES`, `ICON_SPARKLE_STRENGTH`, `ICON_SEED` | Partículas (320 / 1 / 7) |
| `ICON_GLARE` | Bloom (1; 0 lo apaga) |

## Métricas

`compare.py` excluye la caja de la hoja `(775,190)-(965,390)` de todo.
La silueta se segmenta con el borde brillante del cristal (canal R alto)
más los bordes de gradiente como barrera cerrada y relleno desde el marco;
como control, el mismo método entre `leafless_variant_A.png` y
`target.png` da IoU 0,9967 (son la misma C).

Resultado del render final contra `target.png` (ronda 2; salida completa
en `out/metrics_round2.txt`):

```
IoU silueta: 0.9271  (área ref 287613 px, render 306455 px)
SSIM global: 0.7953
SSIM región C: 0.6316
Fondo: |dif| media por banda 2.4 / 3.0 / 1.4 niveles sRGB (arriba/centro/abajo)
```

### Contorno interior (nueva en la ronda 2)

`compare.py` mide SSIM y color medio en una banda de ±28 px alrededor del
borde del hueco, con desglose por barra superior, pared izquierda y barra
inferior. Antes (`reference/round1_render.png`) y después
(`out/icon_1024.png`):

```
                         ANTES (ronda 1)              DESPUÉS (ronda 2)
completa:       SSIM 0.4103  render #72896F  |dif| 39.7   SSIM 0.3740  render #7C947F  |dif| 41.0
barra superior: SSIM 0.3774  render #6F836F  |dif| 42.6   SSIM 0.3478  render #809586  |dif| 41.9
pared izquierda:SSIM 0.5180  render #658468  |dif| 29.7   SSIM 0.4935  render #5B7B63  |dif| 33.2
barra inferior: SSIM 0.3714  render #7C9174  |dif| 43.4   SSIM 0.3208  render #8DA28B  |dif| 45.4
(referencia: #708C73 completa, #758975 superior, #5D7F63 izquierda, #77977A inferior)
```

Lectura honesta: a ojo el contorno interior es ahora cristal claro con
barra blanca, filo dorado y líneas oscuras (ver `out/crops_side_by_side.png`
y los perfiles de brillo: en x=540 el render reproduce la secuencia del
objetivo blanco quemado → gris → dorado → hueco), pero el SSIM de la banda
NO mejora (0,4103 → 0,3740). La banda crema y lisa de la ronda 1 puntuaba
parecido porque el SSIM premia los degradados suaves de la imagen pintada
de Gemini frente a las aristas duras de un cristal facetado real, y porque
la barra blanca cae ~8 px desplazada respecto a la del objetivo (el borde
del hueco trazado de la silueta va unos píxeles por dentro del suyo). El
color medio de la pared izquierda sí clava el objetivo
(#5B7B63 frente a #5D7F63); las barras quedan algo más luminosas que la
media de referencia. La IoU baja de 0,9519 a 0,9271 sin tocar la silueta:
el segmentador incluye el halo del bloom en la máscara del render.

Diferencias que quedan, a propósito o por límite del modelo: las facetas
frontales y de los extremos son triángulos reales con refracciones a veces
muy oscuras (una faceta negra en el brazo inferior), mientras que las del
objetivo son reflejos internos pintados y más suaves; la pared interior
izquierda tiene una banda oscura de refracción que en el objetivo es gris
clara; y el filo dorado se lee algo pálido a través del cristal. La
silueta, el fondo, el encuadre y la lectura a 48 px coinciden.
