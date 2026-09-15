# Lista de tomas del set dorado (fase 8)

El set dorado son fotos reales de ropa etiquetadas a mano por tres personas. Sirve para medir
el motor en la capa 4 (`make l4`) y para validar a los validadores (PLAN §6). Lo hacen el usuario,
su esposa y un tercer juez; el agente solo aporta las herramientas.

**Objetivo: 100 fotos. Mínimo: 50** (`make golden-check` falla por debajo de 50).

## 1. Qué fotografiar

Una foto = una persona principal con un conjunto de ropa (en fotos de grupo, la persona más grande).
Cada foto lleva uno o varios **tags**; se cuentan por separado, así que una foto puede sumar en
varios (p. ej. un grupo en casa de noche con vaqueros cuenta para `grupo`, `interior` y `denim`).
Los tags son exactamente estos siete; `make golden-check` exige que cada uno aparezca al menos una
vez y compara con estos objetivos:

| Tag | Cuántas | Qué es | Casos difíciles a incluir a propósito |
|---|---|---|---|
| `negro` | 15 | La prenda principal es negra o casi negra | negro con poca luz; negro sobre fondo oscuro; negro con un color pequeño (bufanda, logo) |
| `denim` | 15 | Vaquero (pantalón, chaqueta, camisa) | denim claro y oscuro; denim contra una pared o cielo azul; total look vaquero |
| `gris` | 10 | La prenda principal es gris | gris claro frente a blanco; gris con luz cálida (parece beige) |
| `interior` | 20 | Luz interior o cálida (bombillas, restaurante, casa de noche) | luz de tungsteno muy amarilla; mezcla ventana + bombilla; poca luz |
| `fondo-sucio` | 15 | Fondo con muchos colores u objetos (calle, tienda, cocina, estantería) | fondo con colores saturados parecidos a la ropa; carteles; coches |
| `blanco` | 10 | La prenda principal es blanca o crema | blanco al sol (quemado); blanco en sombra (azulado); crema frente a blanco |
| `grupo` | **20 como mínimo** | Dos o más personas en la foto | la persona principal no está en el centro; dos personas de tamaño parecido; alguien cortado en el borde; personas con ropa muy distinta |
| (resto) | libre | Cualquier otra ropa: colores, estampados, prendas de Wada que os gusten | estampados; colores saturados; camel, beige y salmón (tonos cercanos a la piel) |

Las cifras suman más de 100 a propósito: varios tags por foto. Repartid personas, sitios y horas
del día; mejor 100 fotos distintas que 100 del mismo conjunto.

### Fotos de grupo (tag `grupo`)

- La app analiza por defecto a la **persona más grande** (la que ocupa más área en la foto), solo
  su ropa y sin su piel. Al etiquetar, **se etiqueta esa persona**, nunca una mezcla de varias ni el
  fondo; la página de etiquetado lo recuerda en cada foto con el tag `grupo`.
- Incluid al menos 20: con 2, 3 y 4 o más personas; con la persona más grande a un lado; con dos
  personas de tamaño parecido (caso difícil: ahí se ve si la app elige a quien esperáis).
- Pedid permiso a quien salga en la foto. No hace falta que se vean las caras para etiquetar, pero la
  app usa la cara para su modelo de piel: no cortéis cabezas a propósito; si alguien no quiere salir,
  no uséis esa foto.

## 2. Consejos para hacer las fotos

- **Distancia**: de 1,5 a 3 m; que se vea el torso entero y, si se puede, las piernas.
- **Encuadre**: la prenda que queréis juzgar, **en el centro** de la foto (el motor pondera el centro).
- **Evitad espejos** (selfies en el espejo duplican a la persona y el reflejo cambia el color),
  capturas de pantalla, fotos de fotos, filtros y el modo Retrato con fondo desenfocado artificial.
- **Luz**: no la arregléis; los casos difíciles (contraluz, bombillas, sombra) son justo los que hay
  que medir, pero que la foto no esté movida.
- **Un conjunto por foto**: si repetís conjunto, cambiad de sitio o de luz.
- **Incluid casos difíciles a propósito** (tabla de arriba). Si todas las fotos son fáciles, el set
  no sirve para decidir nada.

## 3. De la app a `$COLORSAPP_GOLDEN_DIR` (fuera del repo)

1. **Carpeta del set, fuera del repo** (una vez): por ejemplo
   `mkdir -p ~/ColorsAppGolden/{set,zips,entrada,labels}` y en `~/.zshrc`
   `export COLORSAPP_GOLDEN_DIR="$HOME/ColorsAppGolden/set"`. Nunca dentro de
   `~/DEVELOP/colorsApp`.
2. **Analizar y valorar cada foto en la app**: pestaña **Hoy** → **Cámara** o **Elegir foto** →
   en **Resultado** pulsad **Sí, es eso** o **No**. Solo las fotos con valoración salen en el zip,
   ya convertidas a **PNG sRGB de 256 px** (los mismos píxeles que vio el motor; nunca HEIC). No
   mandéis los HEIC originales del carrete: `make golden-check` y `make label-html` los rechazan.
3. **Exportar**: **Ajustes → Exportar diagnóstico** → AirDrop al Mac. Renombrad cada zip con el
   teléfono (`andres.zip`, `esposa.zip`) o guardadlo en una subcarpeta por teléfono
   (`~/ColorsAppGolden/zips/andres/`), y dejadlo en `~/ColorsAppGolden/zips/`.
4. **Informe y extracción** (desde la raíz del repo):

   ```sh
   make feedback-report ZIPS="$HOME/ColorsAppGolden/zips" FEEDBACK_EXTRACT="$HOME/ColorsAppGolden/entrada"
   ```

   Imprime scans, valoraciones, % de "sí", cuota del top-1, fuentes, tiempos y las fotos con "no"
   (y, si la build las exporta, las cifras por modo de recorte y número de personas), escribe
   `harness/out/feedback-report.{json,md}` y copia a `entrada/` cada PNG valorado como
   `<teléfono>_<scan_id>.png`, con sus máscaras `<teléfono>_<scan_id>.<variante>.pgm` al lado (las
   capas de persona/ropa/piel que exporte la app) y un `feedback-index.csv`. `FEEDBACK_EXTRACT`
   dentro del repo se rechaza.
5. **Elegir**: moved de `entrada/` a `$COLORSAPP_GOLDEN_DIR` las fotos de la lista de tomas **junto con
   sus `.pgm`**. No abráis y volváis a guardar los PNG (cambia el sha256 y la etiqueta se descarta).

## 4. Etiquetar (tres jueces, independientes)

1. Generad la página **dentro del directorio del set** (incrusta las fotos):

   ```sh
   make label-html GOLDEN_DIR="$COLORSAPP_GOLDEN_DIR" LABEL_HTML="$COLORSAPP_GOLDEN_DIR/index.html"
   ```

   Por defecto escribe `harness/label/index.html` (ruta protegida del repo, solo para la demo
   sintética): con fotos personales pasad siempre `LABEL_HTML`.
2. Cada juez abre `index.html` en su navegador, escribe su **nombre de juez**, y para cada foto elige
   entre las 10 candidatas del motor, escribe otra combinación por número si la reconoce y no está, o
   pulsa **Ninguna de estas**; marca los tags y deja una nota si duda. Si la foto trae máscaras de la
   app, los botones de vista enseñan qué persona y qué región tomó la app.
3. **Sin mirar ni comentar las etiquetas de los otros** hasta que los tres hayan descargado su
   `labels-<juez>.json`. Guardad los tres en `~/ColorsAppGolden/labels/`.
4. Fusionar y validar:

   ```sh
   make labels-merge GOLDEN_DIR="$COLORSAPP_GOLDEN_DIR" LABELS="$HOME/ColorsAppGolden/labels"
   make golden-check GOLDEN_DIR="$COLORSAPP_GOLDEN_DIR"
   make l4
   ```

   `labels-merge` escribe `$COLORSAPP_GOLDEN_DIR/manifest.json` (sha256, tags, etiqueta de cada juez,
   consenso por mayoría —2 de 3—, "ninguna" por mayoría, fotos sin consenso y Fleiss κ).
   `golden-check` exige ≥ 50 fotos, los siete tags, sha256 correctos, 3 etiquetas por foto, solo
   PNG/JPEG sRGB de ≤ 256 px, sin HEIC y máscaras con las dimensiones de la foto; muestra κ y los
   objetivos por tag de esta lista.

## 5. Privacidad

- Las fotos, los zips, `index.html` (lleva las fotos dentro), los `labels-*.json` y `manifest.json`
  viven **solo** en `~/ColorsAppGolden/` (o donde apunte `$COLORSAPP_GOLDEN_DIR`): **nunca en el repo**
  ni en un commit. En el repo solo quedan `harness/out/feedback-report.{json,md}` (sin fotos,
  no versionado).
- Las caras no son necesarias para etiquetar; si una foto no se quiere compartir con los otros
  jueces, no la incluyáis.
- La app no usa red: el zip solo sale del teléfono cuando pulsáis **Exportar diagnóstico** y lo
  mandáis vosotros por AirDrop.
