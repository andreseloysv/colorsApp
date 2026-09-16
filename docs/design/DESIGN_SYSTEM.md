# Sistema de diseño de la app (marca provisional «ChromaSol»)

> Estado: propuesta para implementar · 2026-09-15.
> Fuente visual que manda: `exampleDesign/stitch_solarpunk_palette_studio/` (el ejemplo del usuario:
> `solarpunk_meadow/DESIGN.md` y las cuatro pantallas con `screen.png` y `code.html`).
> Este documento traduce ese ejemplo a la app real: iOS 17+, SwiftUI, sin red, sin cuentas, motor C
> y SubjectKit en el dispositivo, 348 combinaciones de Sanzo Wada. Donde el ejemplo y la app chocan,
> mandan las adaptaciones obligatorias del §0.2. Sustituye la lista de pestañas de `PLAN.md` §7
> (Hoy, Rejilla, Explorar, Ajustes); ver §6.3.

> **AVISO (2026-09-16): `docs/design/FIDELITY.md` manda sobre este documento en movimiento, luces,
> marca, logotipo e iconos de pestaña.** Las secciones §0.2 C, §3.5, §3.6 y §5.0 de aquí eliminaban a
> propósito animaciones, partículas, criaturas, halos y logotipo ilustrado, y la primera implementación
> lo cumplió al pie de la letra; el usuario, al verla en su iPhone, dijo: «la ui no es parecida al diseño
> que te di, faltan las animaciones las luces los detalles el logo etc». Desde entonces: movimiento y luz
> según `FIDELITY.md` §1 (con Reducir movimiento, pausa fuera de pantalla, en segundo plano y en reposo,
> ≤ 30 fps), marca y personajes **originales** según `FIDELITY.md` §2 (nunca los del ejemplo: la regla de
> propiedad intelectual §0.2 C sigue intacta) y pantallas según `FIDELITY.md` §3–§7.
> Lo demás de este documento sigue vigente y no se toca: tokens de color, Solarpunk Night, tipografía,
> radios, pergamino, **pocillo neutro §1.4**, mapa de funciones §5 y navegación §6.

## Índice

0. [Cómo leer este documento](#0-cómo-leer-este-documento)
1. [Color: tokens, Solarpunk Night y zona neutra](#1-color)
2. [Tipografía](#2-tipografía)
3. [Forma, espacio, elevación, movimiento e iconos](#3-forma-espacio-elevación-movimiento-e-iconos)
4. [Inventario de componentes](#4-inventario-de-componentes)
5. [Mapa de funciones por pantalla](#5-mapa-de-funciones-por-pantalla)
6. [Pantallas actuales y navegación final](#6-pantallas-actuales-y-navegación-final)
7. [Criterios de aceptación visual](#7-criterios-de-aceptación-visual)
8. [Apéndice: verificaciones ejecutadas](#8-apéndice-verificaciones-ejecutadas)

---

## 0. Cómo leer este documento

### 0.1 Fuentes

| Fuente | Qué se ha tomado |
|---|---|
| `solarpunk_meadow/DESIGN.md` | Tokens de color (frontmatter), escala tipográfica, espaciados, filosofía de elevación y componentes |
| `solar_feed_ghibli_botw_luminous_edition/` (en adelante **Feed**) | Cabecera, chips de filtro, tarjeta del día, publicación con foto, tira de gotas, barra de acciones, barra de pestañas |
| `clothing_extractor_ghibli_botw_edition/` (**Extract**) | Visor con HUD, alfileres sobre prendas, tarjetas de prenda 2×2, cinta de paleta, CTA y botones secundarios |
| `la_rejilla_grid_ghibli_botw_edition/` (**Rejilla**) | Buscador fijo, tarjeta aleatoria, chips, cuadrícula de 2 columnas con franjas verticales |
| `my_garden_vault_ghibli_botw_edition/` (**Garden**) | Tarjeta de perfil con contadores, segmentos, carpetas, «cosechas», estudio de exportación |
| `ios/ColorsApp/App`, `ios/ColorsApp/Views/**` | Funciones reales y API existentes (citadas en §5) |
| `harness/out/screens-verify/*.png`, `screens-subject/*.png`, `screens/*.png` | Aspecto actual (listas del sistema, Liquid Glass en la barra de pestañas del SDK iOS 27) |

Los valores exactos (clases Tailwind, sombras, alfas) salen de `code.html`; la configuración de Tailwind es
idéntica en las cuatro pantallas (comprobado, §8).

### 0.2 Adaptaciones obligatorias (resumen normativo)

| Id | Regla | Dónde se concreta |
|---|---|---|
| A | **Zona neutra de juicio de color**: todo swatch, tira o franja de paleta vive dentro de un pocillo neutro (claro `#FFFFFF`; oscuro `#303030`, L\* 19,9) con filo neutro fino. Sin brillos ámbar, sombras tintadas, veladuras ni pergamino pegados a un swatch. Pergamino y tintes cálidos solo en el marco. | §1.4 |
| B | **Sin funciones que no existen**: nada de likes, contadores de comunidad, seguidores, perfiles ajenos, exportaciones que la app no hace. Corazón = «Sí, es eso»; «To Garden» = guardar en colección local; «HEX Bar»/«Copy HEX Strip» = copiar hex. | §5 |
| C | **Propiedad intelectual**: ningún nombre de estudio, película, videojuego, personaje o criatura del ejemplo en código ni en textos. ~~Los iconos-criatura de las pestañas se sustituyen por SF Symbols (sol, gota, rejilla, brote).~~ **Actualizado (FIDELITY.md §2.3)**: se sustituyen por personajes **originales** dibujados a mano (semilla solar, libélula, gotita de rocío, brote en maceta) con los tiempos de animación del ejemplo pero sin parecido con ningún personaje existente; el `grep` de propiedad intelectual sobre `ios/` sigue dando 0. Nombres de paleta: los de Wada (`dictionary.json`) o los propuestos (`names.suggested.json`). | §3.6, §7, FIDELITY.md §2 |
| D | Interfaz en **español**. Pestañas: **Feed**, **Extraer**, **Rejilla**, **Jardín**. | §6 |
| E | **Marca** «ChromaSol» desde una sola constante `AppBrand.name`; el bundle (`PRODUCT_NAME`, `CFBundleDisplayName` = ColorsApp, `com.andreseloy.colorsapp`) no cambia. | §3.6 |
| F | **Modo oscuro «Solarpunk Night»** derivado, AA verificado. | §1.2 |
| G | **Literata** y **Plus Jakarta Sans** (OFL) empaquetadas, Dynamic Type con `relativeTo:`, licencias OFL en el bundle y en «Acerca de»; iconos SF Symbols. | §2 |

### 0.3 Discrepancias dentro del ejemplo y cómo se resuelven

1. **Colores de marca**: la prosa de `DESIGN.md` nombra `#2D5A3C` (musgo), `#D97724` (ámbar), `#7CA99A`
   (celadón), `#F9F6EE` (pergamino), `#C29B38` (latón) y `#3B2F2F` (sepia), pero el frontmatter y
   `code.html` pintan `primary #144226`, `secondary #954A00`, `surface #FCF9F1`. **Se adoptan los tokens del
   frontmatter** (lo que se ve en `screen.png`); los colores de la prosa quedan como semillas y acentos (§1.3).
2. **Radios**: el frontmatter dice `lg 16 / xl 24`, pero la configuración Tailwind de las cuatro `code.html`
   redefine `DEFAULT 4 / lg 8 / xl 12`, y las capturas usan esta última. **Se adoptan los radios renderizados**
   (tarjetas 12, bloques de color 8, etiquetas 4, píldoras capsule) y el 24 de la prosa solo para hojas (§3.1).
3. **Tamaños mínimos**: `label-sm` es 10 px y hay textos sueltos de 7 a 9 px (`text-[9px]` en los hex). En iOS el
   mínimo es **11 pt**: `label-sm` pasa a 11 pt y los hex a 12 pt (§2.2).
4. **Hex**: el ejemplo usa `font-mono` sin fuente mono cargada. En la app, **SF Mono** del sistema (§2.2).
5. **Proporción de la foto**: el ejemplo usa 4:3 apaisado (ilustraciones). La mayoría de las fotos de personas
   son verticales; la publicación usa la proporción de la foto limitada a **4:5 … 4:3** (como una red de fotos)
   para no cortar a la persona (§5.1).

---

## 1. Color

### 1.1 Tokens semánticos

Claro = valor del ejemplo, sin cambios. Oscuro = «Solarpunk Night» (§1.2). Nombre Swift propuesto entre
paréntesis; se leen como `Solar.surface`, etc. (§1.5). `background`/`on-background` son alias de
`surface`/`on-surface`.

**Superficies (marco cálido)**

| Token | Uso en la app | Claro | Oscuro |
|---|---|---|---|
| `surface` (`surface`) | Fondo de pantalla, cabecera esmerilada | `#FCF9F1` | `#15130E` |
| `surface-dim` (`surfaceDim`) | Fondo detrás de hojas | `#DCDAD2` | `#15130E` |
| `surface-bright` (`surfaceBright`) | Estado pulsado de filas sobre `surface` | `#FCF9F1` | `#3C372E` |
| `surface-container-lowest` (`containerLowest`) | Base de `card` en claro; en oscuro, fondo del visor de capas y zonas hundidas | `#FFFFFF` | `#0F0D09` |
| `surface-container-low` (`containerLow`) | Hojas de detalle, fondo de visor sin foto | `#F6F3EB` | `#1C1913` |
| `surface-container` (`container`) | Tarjeta del día, tarjeta aleatoria, estudio de exportación, píldoras secundarias | `#F1EEE6` | `#221F18` |
| `surface-container-high` (`containerHigh`) | Chips en reposo, carril de segmentos | `#EBE8E0` | `#2C2820` |
| `surface-container-highest` (`containerHighest`) | Insignia «Nº 104», pistas de progreso | `#E5E2DB` | `#37322A` |
| `surface-variant` (`surfaceVariant`) | Pista de sliders | `#E5E2DB` | `#37322A` |
| `surface-tint` (`surfaceTint`) | Tinte de elevación (no usar sobre pocillos) | `#3B6849` | `#A1D2AC` |
| **`card`** (alias de uso) | Fondo de toda tarjeta: publicación, rejilla, perfil, cosecha, top-1. En claro es `containerLowest`; en oscuro `containerLow`, porque una tarjeta más oscura que el fondo parece hundida y la sombra no se ve (texto sobre ella: `onSurface` 14,10, `onSurfaceVariant` 10,21, `primary` 10,29, `secondary` 10,32) | `#FFFFFF` | `#1C1913` |

**Texto y contornos**

| Token | Uso | Claro | Oscuro |
|---|---|---|---|
| `on-surface` (`onSurface`) | Texto principal, títulos de tarjeta | `#1C1C17` | `#EDE6D6` |
| `on-surface-variant` (`onSurfaceVariant`) | Texto secundario, metadatos, iconos en reposo, pestañas no seleccionadas | `#414942` | `#CDC5B3` |
| `outline` (`outline`) | **Solo** contornos e iconos no textuales (4,27:1 en claro: no apto para texto de cuerpo) | `#717971` | `#979080` |
| `outline-variant` (`outlineVariant`) | Separadores y bordes de tarjetas de herramienta | `#C1C9BF` | `#4B463B` |

**Primario, musgo antiguo** (anclas de navegación, CTA principal, estado activo)

| Token | Claro | Oscuro |
|---|---|---|
| `primary` (`primary`) | `#144226` | `#A1D2AC` |
| `on-primary` (`onPrimary`) | `#FFFFFF` | `#0B3A1D` |
| `primary-container` (`primaryContainer`) | `#2D5A3C` | `#224F32` |
| `on-primary-container` (`onPrimaryContainer`) | `#9ED0AA` | `#BCEFC7` |
| `inverse-primary` (`inversePrimary`) | `#A1D2AC` | `#2D5A3C` |

**Secundario, ámbar solar / terracota** (disparadores de extracción, insignias, celebraciones)

| Token | Claro | Oscuro |
|---|---|---|
| `secondary` (`secondary`) | `#954A00` | `#FFB785` |
| `on-secondary` (`onSecondary`) | `#FFFFFF` | `#4F2500` |
| `secondary-container` (`secondaryContainer`) | `#FD933F` | `#713700` |
| `on-secondary-container` (`onSecondaryContainer`) | `#693300` | `#FFDCC6` |

**Terciario, brisa celadón** (etiquetas secundarias, pistas de progreso, chips pasivos)

| Token | Claro | Oscuro |
|---|---|---|
| `tertiary` (`tertiary`) | `#144136` | `#A2D0C0` |
| `on-tertiary` (`onTertiary`) | `#FFFFFF` | `#07372B` |
| `tertiary-container` (`tertiaryContainer`) | `#2D594C` | `#224E42` |
| `on-tertiary-container` (`onTertiaryContainer`) | `#A0CEBE` | `#BDECDC` |

**Error**

| Token | Claro | Oscuro |
|---|---|---|
| `error` / `on-error` | `#BA1A1A` / `#FFFFFF` | `#FFB4AB` / `#690005` |
| `error-container` / `on-error-container` | `#FFDAD6` / `#93000A` | `#93000A` / `#FFDAD6` |

**Fijos** (iguales en ambos temas; insignias que no deben invertirse)

| Token | Valor |
|---|---|
| `primary-fixed` / `primary-fixed-dim` | `#BCEFC7` / `#A1D2AC` |
| `on-primary-fixed` / `on-primary-fixed-variant` | `#00210E` / `#224F32` |
| `secondary-fixed` / `secondary-fixed-dim` | `#FFDCC6` / `#FFB785` |
| `on-secondary-fixed` / `on-secondary-fixed-variant` | `#301400` / `#713700` |
| `tertiary-fixed` / `tertiary-fixed-dim` | `#BDECDC` / `#A2D0C0` |
| `on-tertiary-fixed` / `on-tertiary-fixed-variant` | `#002019` / `#224E42` |

**Inversos** (toasts)

| Token | Claro | Oscuro |
|---|---|---|
| `inverse-surface` (`inverseSurface`) | `#31312B` | `#EDE6D6` |
| `inverse-on-surface` (`inverseOnSurface`) | `#F3F1E9` | `#2C2820` |

### 1.2 «Solarpunk Night»: cómo se derivó

Idea: un jardín de noche con farolillos. Musgo que brilla, ámbar de farol y bruma celadón sobre tierra
oscura cálida; nunca negro puro ni gris azulado.

1. **Acentos**: el propio ejemplo ya trae los tonos claros de sus paletas. En oscuro, `primary` = su
   `inverse-primary`/`primary-fixed-dim` `#A1D2AC`, `secondary` = `secondary-fixed-dim` `#FFB785`,
   `tertiary` = `tertiary-fixed-dim` `#A2D0C0`. Los contenedores oscuros son sus tonos 30
   (`on-*-fixed-variant`: `#224F32`, `#713700`, `#224E42`) y los textos sobre contenedor, sus tonos 90
   (`#BCEFC7`, `#FFDCC6`, `#BDECDC`). Los `on-*` sobre acento son tonos 20 interpolados entre los tonos 10 y
   30 del ejemplo (`#0B3A1D`, `#4F2500`, `#07372B`).
2. **Superficies**: escalera cálida de L\* 3,7 a 21,1 con b\* positivo (amarillo-marrón) y croma ≤ 6, medida en
   CIELAB D65 con `oracle.reference.srgb8_to_lab_strict` (§8):

   | Token oscuro | Hex | L\* | a\* | b\* | C\* |
   |---|---|---|---|---|---|
   | `containerLowest` | `#0F0D09` | 3,70 | 0,06 | 1,84 | 1,84 |
   | `surface` | `#15130E` | 5,93 | −0,12 | 2,94 | 2,95 |
   | `containerLow` | `#1C1913` | 8,90 | 0,15 | 4,52 | 4,52 |
   | `container` | `#221F18` | 11,86 | −0,09 | 5,31 | 5,31 |
   | `containerHigh` | `#2C2820` | 16,29 | 0,17 | 5,94 | 5,95 |
   | `containerHighest` | `#37322A` | 21,06 | 0,60 | 5,90 | 5,93 |
   | `onSurface` | `#EDE6D6` | 91,44 | −0,33 | 8,63 | 8,64 |
   | `onSurfaceVariant` | `#CDC5B3` | 79,71 | −0,27 | 10,02 | 10,03 |
   | `outline` | `#979080` | 59,97 | −0,25 | 9,43 | 9,44 |
   | `outlineVariant` | `#4B463B` | 29,89 | −0,05 | 7,40 | 7,40 |

   Referencia en claro: `surface #FCF9F1` L\* 97,95, C\* 4,20 (el pergamino del ejemplo es igual de cálido).
3. **Sombras** en oscuro: la sombra sepia no se ve sobre fondo oscuro; se usa negro con más opacidad y se
   refuerza el filo de luz superior (§3.3).
4. **Contraste WCAG 2.x** (luminancia relativa sRGB), 26 pares por tema, **0 fallos** (§8). Selección:

   | Par | Claro | Oscuro | Mínimo |
   |---|---|---|---|
   | `onSurface` / `surface` | 16,26 | 14,93 | 4,5 |
   | `onSurface` / `containerHighest` | 13,22 | 10,22 | 4,5 |
   | `onSurfaceVariant` / `surface` | 8,85 | 10,81 | 4,5 |
   | `onSurfaceVariant` / `containerHighest` | 7,19 | 7,40 | 4,5 |
   | `primary` / `surface` (texto) | 10,87 | 10,90 | 4,5 |
   | `onPrimary` / `primary` (botón) | 11,43 | 7,53 | 4,5 |
   | `onPrimaryContainer` / `primaryContainer` | 4,57 | 7,31 | 4,5 |
   | `secondary` / `surface` (texto) | 6,13 | 10,93 | 4,5 |
   | `secondary` / `container` | 5,56 | 9,68 | 4,5 |
   | `onSecondary` / `secondary` | 6,45 | 7,74 | 4,5 |
   | `onSecondaryContainer` / `secondaryContainer` | 4,54 | 7,25 | 4,5 |
   | `onTertiaryContainer` / `tertiaryContainer` | 4,56 | 7,24 | 4,5 |
   | `error` / `surface` | 6,14 | 10,93 | 4,5 |
   | `outline` / `surface` (no texto) | 4,27 | 5,85 | 3,0 |
   | `inverseOnSurface` / `inverseSurface` (toast) | 11,57 | 11,80 | 4,5 |

   Casos del ejemplo que **no** pasan y se corrigen: `text-outline` como texto de metadatos (4,27 sobre
   `surface`, 4,05 sobre `containerLow`) → usar `onSurfaceVariant`; `text-secondary opacity-80` (4,04) → sin
   opacidad; `secondary-container #FD933F` y ámbar `#F59E0B` como texto o icono con significado (2,12 y 2,04)
   → solo decorativos.

### 1.3 Acentos decorativos (marco, nunca junto a un swatch)

| Acento | Claro | Oscuro | Uso permitido |
|---|---|---|---|
| Filo de latón (`brassHairline`) | `#C29B38` al 25 % | `#C29B38` al 30 % | Borde de 1 px de cabecera, barra de pestañas (iOS 17–25) y HUD esmerilados |
| Sombra sepia (`sepiaShadow`) | `rgb(68,48,28)` al 4–8 % | negro al 35–50 % | Sombras de reposo (§3.3) |
| Sol (`sunAmber`, `sunAmberSoft`) | `#F59E0B`, `#FBBF24` | `#FBBF24` | Icono de sol de la marca y lavados difusos de fondo; nunca texto ni icono con significado |
| Brillo musgo (`mossGlow`) | `rgb(45,90,60)` al 16 % | `#A1D2AC` al 12 % | Sombra de elementos flotantes sin swatch |
| Lavado cálido | `secondaryFixed` al 40 %, desenfoque 40 | `secondaryContainer` al 25 % | Esquinas de tarjetas de perfil y aleatoria (a ≥ 16 pt de un pocillo) |
| Lavado verde | `primaryFixed` al 40 %, desenfoque 32 | `primaryContainer` al 35 % | Ídem |
| Chip pasivo celadón | `#7CA99A` al 15 % sobre `surface` = `#E9EDE4` | al 15 % sobre `surface` = `#242A23` | Fondo de chips en reposo (texto `onSurfaceVariant`: 7,84 / 8,55) |
| Pergamino esmerilado (`frostTint`) | `rgba(249,246,238,0.78)` | `rgba(21,19,14,0.72)` | Cabecera, HUD sobre foto, barra de pestañas en iOS 17–25 (§3.4) |

### 1.4 Zona neutra de juicio de color («pocillo»)

El usuario juzga colores de ropa. Un pergamino amarillento o un halo ámbar al lado de un swatch desplaza
lo que ve (contraste simultáneo). Por eso todo color de datos (paleta del motor, colores de Wada,
combinaciones) se muestra dentro de un **pocillo** neutro.

**Tokens del pocillo** (acromáticos: a\* = b\* = 0,00 medidos):

| Token (`Solar.well…`) | Claro | L\* | Oscuro | L\* | Uso |
|---|---|---|---|---|---|
| `wellFill` | `#FFFFFF` | 100,00 | `#303030` | 19,87 | Fondo del pocillo (oscuro dentro del rango exigido L\* 18–22) |
| `wellFillAlt` | `#F2F2F2` | 95,49 | `#333333` | 21,25 | Pocillo anidado (fila seleccionada dentro de un pocillo) |
| `wellEdge` | `#D6D6D6` | 85,63 | `#4A4A4A` | 31,46 | Filo de 1 px físico (`1 / displayScale`) alrededor del pocillo |
| `swatchHairline` | negro al 12 % (sobre blanco = `#E0E0E0`, L\* 89,18) | | blanco al 14 % (sobre `#303030` = `#4D4D4D`, L\* 32,75) | | Borde de cada swatch (distingue un blanco roto del pocillo) |
| `swatchDivider` | = `wellFill` | | = `wellFill` | | Separación de 2 pt entre segmentos de una tira |
| `wellText` | `#1F1F1F` (16,48:1) | 11,76 | `#EDEDED` (11,27:1) | 93,75 | Hex, pesos y nombres de color dentro del pocillo |
| `wellTextSecondary` | `#5C5C5C` (6,69:1; 5,97:1 sobre `wellFillAlt`) | 39,07 | `#B0B0B0` (6,09:1) | 71,84 | Etiquetas secundarias dentro del pocillo |
| `wellPlaceholder` | `#E6E6E6` / franja `#DEDEDE` | 91,29 / 88,47 | `#3D3D3D` / franja `#454545` | 25,76 / 29,29 | Combinación bloqueada (candado `wellTextSecondary`: 5,36 / 5,01) |
| `wellSelection` | anillo de 2 pt `wellText` con 2 pt de separación | | ídem | | Swatch seleccionado |

**Reglas normativas**

1. Todo swatch, tira de paleta, cinta de pesos, franja de combinación o gota vive dentro de un `wellFill` con
   **al menos 8 pt de relleno** (6 pt en la cuadrícula de la Rejilla) y filo `wellEdge`. El pergamino, los lavados
   y los filos de latón quedan fuera de ese rectángulo.
2. Dentro del pocillo solo hay colores de datos y texto `wellText`/`wellTextSecondary`. Nada de tokens cálidos
   (`onSurface` claro tiene C\* 3,67: no se usa dentro del pocillo).
3. Prohibido sobre o junto a un swatch: sombras de color (`shadow-[0_0_14px_#7A9A7B]`), anillos ámbar
   (`ring-amber-400/30`), veladuras y degradados (`bg-gradient-to-tr … via-white/10 to-white/25`), brillos
   interiores (`shadow-[inset_0_1px_2px_rgba(255,255,255,0.6)]`, punto `bg-white/25`), `blur`, `opacity` y
   `brightness`. Un swatch es un rectángulo o círculo plano del color exacto.
4. El estado seleccionado no brilla: `wellSelection` + elevación de 2 pt en y + escala 1,04 (sin color).
5. **Cuentas sobre la foto** (alfileres, etiquetas del visor, micro-píldoras): la cuenta de color lleva un anillo
   de 2 pt `wellFill` y un filo exterior de 1 px `wellEdge`; ese anillo es el pocillo mínimo que la separa del
   pergamino esmerilado o de la foto.
6. En oscuro la tarjeta alrededor es cálida (`card` `#1C1913`), pero el pocillo es `#303030` (ΔE00 8,26 con
   la tarjeta) y ocupa todo el ancho útil del bloque de color.
7. La tarjeta compartible (§4 n.º 31, 1080 × 1350) usa siempre la paleta clara y pocillos blancos,
   sea cual sea el tema del dispositivo.
8. Contraste del pocillo con el marco: en claro `#FFFFFF` vs `#FCF9F1` es ΔE00 4,03 (1,05:1); por eso el
   `wellEdge` es obligatorio. En oscuro `#303030` vs `container #221F18` es ΔE00 7,12.

**Traducción de clases del ejemplo que tocan swatches**

| Pantalla | Clase del ejemplo | Sustituto |
|---|---|---|
| Feed, tarjeta del día | `ring-1 ring-amber-400/30 shadow-inner` en la cinta | Cinta dentro de `wellFill` + `wellEdge`, sin sombra |
| Feed, gotas | `group-hover:shadow-[0_0_14px_<hex>] ring-white/50` + punto `bg-white/25` | Círculo plano + `swatchHairline`; seleccionado = `wellSelection` |
| Feed, sección de paleta | `bg-surface-container-low` (pergamino) | `wellFill` |
| Extract, tarjeta de prenda | `shadow-[inset_0_1px_2px_rgba(255,255,255,0.6)]` + degradado blanco + insignias sobre el color | Bloque plano; número e insignias en la zona de texto, no sobre el color; tarjeta = `wellFill` |
| Extract, alfileres | `shadow-[0_0_14px_rgba(253,147,63,0.7)]`, `animate-ping` de color | Sombra neutra `negro 18 %, radio 5, y 2`; anillo `wellFill` (regla 5); sin pulsos de color |
| Rejilla, tarjeta aleatoria | `shadow-sm hover:scale-105` en las fichas | Fichas planas en `wellFill`, separación 6 pt |
| Rejilla, tarjeta | Franjas a sangre sobre `bg-surface-container-lowest` | Franjas dentro de pocillo con 6 pt de relleno (en claro la tarjeta ya es blanca) |
| Garden, cosecha | `group-hover:shadow-[0_0_10px_<hex>] ring-2 ring-secondary/30` | Círculo plano + `swatchHairline`; dominante marcado con `wellSelection` |
| Garden, micro-píldoras | Punto de color sobre `bg-surface-container` | Píldora `wellFillAlt` + cuenta con anillo (regla 5) |

### 1.5 Implementación en SwiftUI

Tokens en código (el proyecto no tiene `Assets.xcassets`), con `UIColor` dinámico para que sigan el tema del
sistema y los `ImageRenderer` puedan forzar claro:

```swift
// ios/ColorsApp/Theme/SolarColor.swift (propuesto)
import SwiftUI
import UIKit

extension Color {
    /// Color que cambia con el tema. `light`/`dark` en hex "#RRGGBB".
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let v = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }
}

enum Solar {
    static let surface = Color(light: 0xFCF9F1, dark: 0x15130E)
    static let containerLowest = Color(light: 0xFFFFFF, dark: 0x0F0D09)
    static let card = Color(light: 0xFFFFFF, dark: 0x1C1913)
    static let onSurface = Color(light: 0x1C1C17, dark: 0xEDE6D6)
    static let primary = Color(light: 0x144226, dark: 0xA1D2AC)
    static let secondary = Color(light: 0x954A00, dark: 0xFFB785)
    // … resto de §1.1
    static let wellFill = Color(light: 0xFFFFFF, dark: 0x303030)
    static let wellEdge = Color(light: 0xD6D6D6, dark: 0x4A4A4A)
    static let wellText = Color(light: 0x1F1F1F, dark: 0xEDEDED)
    static let wellTextSecondary = Color(light: 0x5C5C5C, dark: 0xB0B0B0)
}
```

- `ColorsAppApp` aplica `.tint(Solar.primary)` en la raíz; las pantallas pintan `Solar.surface` a sangre
  (`.background(Solar.surface.ignoresSafeArea())`) y las listas usan `.scrollContentBackground(.hidden)`.
- Los colores de datos **no** se crean con estos tokens: siguen `Color(wada:)`, `Color(rgb8:)` y
  `Color(hex:)` de `Model/Color+Wada.swift`, en espacio sRGB. Ninguna lógica de color nueva en Swift: nombres
  de color más cercanos y ΔE vienen del motor (`ColorSearch.nearest(hex:)` → `nearestDictionaryColor`) y el
  texto legible sobre un swatch de `legibleTextColor(r:g:b:)` (L\* del motor).

---

## 2. Tipografía

### 2.1 Familias, ficheros y licencias

| Familia | Rol | Fichero oficial (repositorio `google/fonts`) | Licencia |
|---|---|---|---|
| **Literata** (variable, ejes `opsz` 7–72 y `wght` 200–900; v3.103) | Titulares, nombres de combinación, marca | Carpeta: <https://github.com/google/fonts/tree/main/ofl/literata> · Fichero: <https://raw.githubusercontent.com/google/fonts/main/ofl/literata/Literata%5Bopsz%2Cwght%5D.ttf> (955 132 bytes, sha256 `b41138c9373112f32abb589cc22e8674b06ed4048b0c513be922bdd26f274440`) | SIL OFL 1.1: <https://raw.githubusercontent.com/google/fonts/main/ofl/literata/OFL.txt> |
| **Plus Jakarta Sans** (variable, eje `wght` 200–800; v2.071) | Cuerpo, etiquetas, botones, contadores | Carpeta: <https://github.com/google/fonts/tree/main/ofl/plusjakartasans> · Fichero: <https://raw.githubusercontent.com/google/fonts/main/ofl/plusjakartasans/PlusJakartaSans%5Bwght%5D.ttf> (176 288 bytes, sha256 `89b3fb38aa0d275d7a731d0d817a4f1622b316b4d7fbdedcf02ee9099ff68bc8`) | SIL OFL 1.1: <https://raw.githubusercontent.com/google/fonts/main/ofl/plusjakartasans/OFL.txt> |
| **SF Mono** (sistema) | Hex y valores Lab | — | Fuente del sistema |

Las cursivas (`Literata-Italic[opsz,wght].ttf`, `PlusJakartaSans-Italic[wght].ttf`) no se empaquetan: el
ejemplo no usa cursiva (0 apariciones de `italic` en las cuatro `code.html`). Ninguna de las dos licencias
declara «Reserved Font Name»; aun así los ficheros se empaquetan sin modificar (solo se renombran en disco).

**Empaquetado**

1. Copiar a `ios/ColorsApp/Resources/Fonts/` como `Literata-VF.ttf`, `PlusJakartaSans-VF.ttf`,
   `Literata-OFL.txt` y `PlusJakartaSans-OFL.txt` (xcodegen los mete en *Copy Bundle Resources* porque
   `project.yml` ya incluye todo `ColorsApp/`; en el bundle quedan en la raíz).
2. `Info.plist`: clave `UIAppFonts` con `Literata-VF.ttf` y `PlusJakartaSans-VF.ttf`.
3. «Acerca de» (`Views/Ajustes/AboutView.swift`): dos créditos nuevos («Literata, The Literata Project
   Authors, SIL Open Font License 1.1», «Plus Jakarta Sans, The Plus Jakarta Sans Project Authors, SIL OFL
   1.1») y un enlace a una vista que muestra el texto de cada `*-OFL.txt` desde el bundle (la app no abre
   URLs: sin red).
4. Test: `UIFont.familyNames` contiene «Literata» y «Plus Jakarta Sans», y los dos OFL están en el bundle.

### 2.2 Escala por rol

Tamaños en pt (1 px del ejemplo = 1 pt). «Natural» = ascendente + descendente + interlínea de la fuente a ese
tamaño, medido con CoreText (§8). SwiftUI no puede reducir la altura de línea: `lineSpacing` = objetivo −
natural si es positivo; con Literata la altura natural (1,485 em) ya supera la del ejemplo y se acepta
(titulares de 1–2 líneas). Tracking en pt = em × tamaño.

| Rol | Familia · peso | Tamaño / objetivo | Natural | `lineSpacing` | Tracking | Dynamic Type (`relativeTo:`) | Uso en la app |
|---|---|---|---|---|---|---|---|
| `headline-xl` | Literata 600 | 36 / 44 | 53,46 | 0 | −0,72 | `.largeTitle` (34) | Cifra de portada del resumen del carrete («26 fotos») |
| `headline-xl-mobile` | Literata 600 | 28 / 36 | 41,58 | 0 | −0,28 | `.title` (28) | Título del resumen del carrete («Tu carrete en color») |
| `headline-lg` | Literata 600 | 30 / 38 | 44,55 | 0 | 0 | `.title` (28) | Nombre de la combinación en el detalle |
| `headline-lg-mobile` | Literata 600 | 24 / 32 | 35,64 | 0 | 0 | `.title2` (22) | Nombre del top-1 en Extraer |
| `headline-md` | Literata 500 | 20 / 28 | 29,70 | 0 | 0 | `.title3` (20) | Títulos de la visita por capas, nombre en la tarjeta del día |
| `headline-sm` | Literata 500 | 18 / 24 | 26,73 | 0 | −0,45 (`tracking-tight`) en la marca | `.headline` (17) | Marca «ChromaSol», títulos de sección («Colores de la ropa», «Cosechas»), nombre de color en tarjetas de prenda, contadores del Jardín (600) |
| `card-title` | Literata 600 | 15 / 19 | 22,28 | 0 | 0 | `.subheadline` (15) | Nombre en tarjetas de la Rejilla (`text-[15px]`, 1 línea) |
| `body-lg` | Plus Jakarta Sans 400 | 16 / 24 | 20,16 | 3,84 | 0 | `.callout` (16) | Textos de onboarding y estados vacíos |
| `body-md` | Plus Jakarta Sans 400 | 14 / 20 | 17,64 | 2,36 | 0 | `.subheadline` (15) | Cuerpo por defecto, significado de cada capa |
| `body-sm` | Plus Jakarta Sans 400 | 12 / 16 | 15,12 | 0,88 | 0 | `.caption` (12) | Metadatos («Carrete · 14 sept, 10:45»), notas al pie |
| `label-lg` | Plus Jakarta Sans 600 | 14 / 18 | 17,64 | 0,36 | 0,14 | `.subheadline` (15) | Botones, título de la publicación, contador «20/348» |
| `label-md` | Plus Jakarta Sans 600 | 12 / 16 | 15,12 | 0,88 | 0,24 | `.caption` (12) | Chips, acciones de la barra, píldoras secundarias |
| `label-sm` | Plus Jakarta Sans 700 | **11** / 13 (ejemplo 10 / 12) | 13,86 | 0 | 0,44 | `.caption2` (11) | Etiqueta de sección de la cabecera («FEED»), rótulos en mayúsculas, nombres bajo gotas |
| `overline` | `label-sm` + mayúsculas + `tracking-widest` | 11 | 13,86 | 0 | 1,10 (0,1 em) | `.caption2` | «PALETA DE LA ROPA», «COMBINACIÓN DEL DÍA», «AL AZAR» |
| `hex` | SF Mono 500 | 12 (ejemplo 9–12) | — | 0 | 0 | `.caption` | Hex (`#7A9A7B`, siempre mayúsculas en pantalla y al copiar), valores Lab |
| `number` | Plus Jakarta Sans 600 + `.monospacedDigit()` | según rol | — | — | — | según rol | Contadores, pesos «39 %», scores (`tnum` presente en la fuente, §8) |

Tamaños de Dynamic Type por defecto (Large) y en AX5 medidos en el simulador iOS 27 (§8):
`largeTitle` 34→60, `title1` 28→58, `title2` 22→56, `title3` 20→55, `headline` 17→53, `body` 17→53,
`callout` 16→51, `subheadline` 15→49, `footnote` 13→44, `caption1` 12→43, `caption2` 11→40.

### 2.3 Uso en SwiftUI (verificado)

```swift
// ios/ColorsApp/Theme/SolarFont.swift (propuesto)
enum SolarFont {
    static func headlineSm() -> Font { .custom("Literata", size: 18, relativeTo: .headline).weight(.medium) }
    static func cardTitle() -> Font { .custom("Literata", size: 15, relativeTo: .subheadline).weight(.semibold) }
    static func bodyMd() -> Font { .custom("Plus Jakarta Sans", size: 14, relativeTo: .subheadline) }
    static func labelLg() -> Font { .custom("Plus Jakarta Sans", size: 14, relativeTo: .subheadline).weight(.semibold) }
    static func labelSm() -> Font { .custom("Plus Jakarta Sans", size: 11, relativeTo: .caption2).weight(.bold) }
    static func hex() -> Font { .system(.caption, design: .monospaced).weight(.medium) }
}
// Uso: Text("ChromaSol").font(SolarFont.headlineSm()).tracking(-0.45)
//      Text("PALETA DE LA ROPA").font(SolarFont.labelSm()).tracking(1.1).textCase(.uppercase)
```

- Se usa el **nombre de familia** («Literata», «Plus Jakarta Sans») más `.weight(_:)`: CoreText resuelve el eje
  `wght` de la fuente variable (instancias `Literata-Regular_SemiBold`, etc.) y aplica `opsz` automático según
  el tamaño (36 pt → `opsz` 36). Verificado en el simulador iOS 27 con un binario de destino iOS 17: la tinta
  de «Combinación Nº 067 · Laelia Pink» crece con el peso (Literata 20: regular 4927, medium 5805, semibold
  6564, bold 7623; Plus Jakarta Sans 14: 2164, 3026, 3441), así que el peso se aplica (§8).
- Si el nombre falla, SwiftUI cae en silencio a SF: el test de §2.1 punto 4 lo detecta.
- `.monospacedDigit()` en contadores y pesos; `.textCase(.uppercase)` solo en `overline`/`label-sm`.
- Títulos de navegación de pantallas empujadas: `UINavigationBarAppearance` con
  `UIFontMetrics(forTextStyle: .headline).scaledFont(for: UIFont(name: "Literata-Regular_Medium", size: 18)!)`.

### 2.4 Reglas

1. Mínimo 11 pt en cualquier texto; 12 pt para hex.
2. Literata solo en titulares y nombres (combinación, color de Wada, marca); nunca en botones, chips, hex ni
   números de tabla.
3. Con tamaños de accesibilidad (≥ AX1): cuadrícula de la Rejilla a 1 columna, gotas del Feed a 3 por fila con
   salto, tarjetas de prenda a 1 columna, barra de acciones solo con iconos (con `accessibilityLabel`), cabecera
   sin rótulo de sección.
4. Nombres de combinación: `names.es.json` aceptado → `names.suggested.json` (`name_es`, máximo 25 caracteres,
   mediana 16) → «Nº 067». Nombres de color: los de `dictionary.json` tal cual (nomenclatura de Ridgway en
   inglés, máximo 23 caracteres: «Deep Violet / Plumbeous»). Líneas: `card-title` 1 línea, `headline-sm` 2.

---

## 3. Forma, espacio, elevación, movimiento e iconos

### 3.1 Radios (valores renderizados del ejemplo)

| Token | Valor | Clase del ejemplo | Uso | SwiftUI |
|---|---|---|---|---|
| `radiusTag` | 4 | `rounded` | Etiqueta pequeña («ΔE 2,3» en tarjeta de prenda) | `RoundedRectangle(cornerRadius: 4, style: .continuous)` |
| `radiusBlock` | 8 | `rounded-lg` | Bloque de color de prenda, miniaturas, fichas de la tarjeta aleatoria, tiras de cosecha, carril interior de tarjetas | `…cornerRadius: 8…` |
| `radiusCard` | 12 | `rounded-xl` | Tarjetas (publicación, rejilla, prenda, perfil, estudio), visor, tarjeta del día, pocillos de sección | `…cornerRadius: 12…` |
| `radiusSheet` | 24 (solo esquinas superiores) | prosa de DESIGN.md | Hojas (`presentationCornerRadius(24)`), panel inferior del visor de capas | `UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)` |
| `radiusPill` | capsule | `rounded-full` | Chips, botones, píldoras HUD, gotas, cuentas, buscador | `Capsule()` / `Circle()` |

Regla de anidado: radio interior = radio exterior − relleno (tarjeta 12 con relleno 8 → bloque 4…8; se
redondea a los tokens `radiusBlock` 8 o `radiusTag` 4).

### 3.2 Espaciado y medidas

| Token | pt | Ejemplo | Uso |
|---|---|---|---|
| `spaceXS` | 4 | `space-xs` | Entre icono y texto en píldoras |
| `spaceSM` | 8 | `space-sm` | Entre chips; relleno de tarjeta de prenda; relleno mínimo del pocillo |
| `spaceMD` | 12 | `space-md` | Relleno de tarjetas y cabeceras de publicación |
| `spaceLG` | 20 | `space-lg` | Entre secciones de una pantalla |
| `spaceXL` | 32 | `space-xl` | Entre publicaciones del Feed |
| `margin` | 16 | `margin` | Margen lateral de pantalla |
| `gutter` | 12 | `gutter` | Hueco de cuadrícula (Rejilla, prendas, estudio) |
| Extras de Tailwind usados | 6 (`1.5`), 10 (`2.5`), 14 (`3.5`) | | Relleno vertical de chips (6), botones secundarios (10), CTA (14) |

| Medida recurrente | pt | Origen |
|---|---|---|
| Cabecera | 64 de alto + área segura | `h-16` |
| Botón de icono de cabecera | 44 × 44 | `w-11 h-11` |
| Marca (logotipo) | 32 × 32 | `h-8` |
| Avatar de publicación → icono de origen | 36 | `w-9` |
| Foto de publicación | ancho de tarjeta; proporción de la foto limitada a 4:5 … 4:3 | `aspect-[4/3]` (§0.3) |
| Visor de Extraer | alto 400 (máx.), ancho útil | `h-[400px]` |
| Gota del Feed | 44 | `w-11 h-11` |
| Bloque de color de prenda | 64 de alto | `h-16` |
| Cinta de la tarjeta del día / de Extraer / tira de cosecha / barra de pesos | 24 / 12 / 32 / 16 | `h-6` / `h-3` / `h-8` / `h-4` |
| Fichas de la tarjeta aleatoria | 48 de alto | `h-12` |
| Franjas de tarjeta de Rejilla | 112 de alto | `h-28` |
| Cuenta de alfiler | 24 (anillo incluido) | `w-6 h-6` |
| Miniatura de cosecha | 48 | `w-12 h-12` |
| Objetivo táctil mínimo | 44 × 44 (`contentShape` si el dibujo es menor) | HIG |

### 3.3 Elevación: luz de día difusa

Conversión CSS → SwiftUI: `radius` ≈ desenfoque / 2 − |spread| / 2; `x`, `y` iguales. Las sombras se ponen en
la forma de fondo (`.background(shape.fill(…).shadow(…))`), no en el contenido, para no sombrear textos
y abaratar el render en listas largas.

| Nivel | CSS del ejemplo | SwiftUI claro | SwiftUI oscuro | Uso |
|---|---|---|---|---|
| E0 plano | — | sin sombra | sin sombra | Pocillos, chips, filas |
| E1 reposo | `0 4px 16px -2px rgba(68,48,28,0.06), 0 1px 3px rgba(68,48,28,0.04)` | `.shadow(color: sepia.opacity(0.06), radius: 7, y: 4)` + `.shadow(color: sepia.opacity(0.04), radius: 1.5, y: 1)` | `.shadow(color: .black.opacity(0.45), radius: 7, y: 4)` + filo de luz | Tarjetas de publicación, rejilla, perfil, buscador |
| E1+ reposo marcado | `0 4px 16px -2px rgba(68,48,28,0.08), 0 1px 3px rgba(68,48,28,0.05)` y `0 4px 18px -2px rgba(68,48,28,0.07)` | ídem con 0,08 / 0,05 | ídem con 0,5 | Tarjeta del día, aleatoria, cosechas |
| E2 pequeña | `0 2px 8px rgba(68,48,28,0.06)` | `.shadow(color: sepia.opacity(0.06), radius: 4, y: 2)` | `.black.opacity(0.35)` | Carpetas/colecciones, fichas del estudio |
| E3 flotante | `0 12px 32px -4px rgba(45,90,60,0.16), 0 4px 12px rgba(217,119,36,0.10)` | `.shadow(color: mossGlow, radius: 14, y: 12)` + `.shadow(color: Color(red: 217/255, green: 119/255, blue: 36/255).opacity(0.10), radius: 6, y: 4)` | `.black.opacity(0.5), radius: 14, y: 12` | CTA principal, toasts, botón «Otra». **Nunca** en elementos que contienen un swatch |
| E3 neutra | `0 2px 10px rgba(0,0,0,0.18)` | `.shadow(color: .black.opacity(0.18), radius: 5, y: 2)` | ídem 0,4 | Alfileres y etiquetas sobre la foto |

**Filo de luz superior** (`inset 0 1px 1px rgba(255,255,255,0.7)`): trazo interior de 1 pt con degradado que se
apaga en el primer 12 % de la altura.

```swift
struct SunGlint: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.10 : 0.7), .white.opacity(0)],
                                             startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.12)), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}
```

Borde pictórico de tarjeta de publicación (`rgba(68,48,28,0.08)`): `strokeBorder(sepia.opacity(0.08), lineWidth: 1)`
en claro, `outlineVariant.opacity(0.6)` en oscuro.

### 3.4 Pergamino esmerilado

Cabecera, HUD sobre la foto, etiquetas de alfiler y barra de pestañas en iOS 17–25:

```swift
struct FrostedParchment: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var shape: AnyShape = AnyShape(Rectangle())
    func body(content: Content) -> some View {
        content.background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(scheme == .dark ? Color(red: 21/255, green: 19/255, blue: 14/255).opacity(0.72)
                                           : Color(red: 249/255, green: 246/255, blue: 238/255).opacity(0.78))
                shape.stroke(Color(red: 194/255, green: 155/255, blue: 56/255).opacity(scheme == .dark ? 0.30 : 0.25), lineWidth: 1)
            }
        }
    }
}
```

- Peor caso medido: tinte claro sobre negro puro = `#C2C0BA` (`onSurface` 9,40:1, `primary` 6,28:1); tinte oscuro
  sobre blanco puro = `#575551` (`onSurface` 5,98:1). El material añade desenfoque y contraste.
- **iOS 26 o superior**: la barra de pestañas y las barras de navegación del sistema ya son Liquid Glass (así se ve
  en las capturas actuales). No se sustituyen: solo `.tint(Solar.primary)`. En iOS 17–25, `UITabBarAppearance`
  con `backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)`, `backgroundColor` = tinte y
  `shadowColor` = latón al 15 %.
- Sin materiales dentro de celdas de `LazyVGrid`/`LazyVStack` (coste de desenfoque por celda): solo cabecera, HUD y
  toasts.

### 3.5 Movimiento

> **Superado por `FIDELITY.md` §1** (2026-09-16). La tabla de abajo es el estado anterior: eliminaba las
> criaturas animadas, las partículas, los anillos giratorios, el sol con cara y el barrido del botón, y es
> la causa directa del «faltan las animaciones» del usuario. Hoy mandan las recetas de `FIDELITY.md` §1.2
> (M1–M20) y §1.3 (L1–L7) con los valores exactos de `code.html`, implementadas en
> `ios/ColorsApp/Design/Motion/**` y `Design/Brand/**`. Lo único que se conserva de aquí: nada de movimiento
> ni luz de color dentro de un pocillo (§1.4) y el comportamiento con `accessibilityReduceMotion`.

| Del ejemplo | En la app (OBSOLETO, ver FIDELITY.md §1) |
|---|---|
| Criaturas animadas en pestañas, partículas flotantes, anillos giratorios, sol con cara | **Se eliminan** (propiedad intelectual y distracción junto a swatches) |
| `active:scale-95/0.98` | Pulsación: `scaleEffect(0.97)` con `.spring(response: 0.25, dampingFraction: 0.8)` |
| `animate-ping` en puntos | Solo en el indicador de escaneo en curso (punto `secondaryContainer`, fuera de pocillos); nunca en swatches |
| Barajado de fichas (`scaleY(0.4)→1`, escalonado 60 ms, Rejilla) | «Otra»: fichas `scaleEffect(y: 0.4 → 1)` escalonadas 60 ms, 250 ms cada una |
| Brillo que recorre el botón (`shimmer`) | Se elimina |
| Toast 2,2–2,4 s | Toast `inverseSurface` 2,2 s, desde abajo, con `.sensoryFeedback(.success, trigger:)` al copiar |

Con `accessibilityReduceMotion`: sin escalas ni escalonados, solo fundidos de 150 ms.

### 3.6 Iconos (SF Symbols) y marca

> **Superado en parte por `FIDELITY.md` §2** (2026-09-16). Siguen vigentes todos los SF Symbols de acciones
> y estados de la tabla (corazón, guardar, copiar, compartir, capas, candado…). **Ya no** valen las cuatro
> primeras filas ni la fila «Marca en cabecera»: las pestañas llevan los personajes **originales**
> (`BrandTabIcon`, FIDELITY.md §2.3) y la cabecera el logotipo vectorial `ChromaSolLogo`/`ChromaSolLockup`
> (FIDELITY.md §2.1), del que sale también el icono de la app. `AppBrand.name` no cambia; `AppBrand.symbol`
> (`sun.max.fill`) queda obsoleto y `BrandMark` ya no aparece en ninguna pantalla de la app (solo en
> las galerías de depuración `-uiScreen design-gallery` / `motion-gallery`).

Todos disponibles en iOS 17 o antes (comprobado en `name_availability.plist` del sistema, §8).

| Uso | Símbolo | Sustituye a (ejemplo) |
|---|---|---|
| Pestaña **Feed** | `sun.max` (seleccionada `sun.max.fill`) | Criatura de hollín animada |
| Pestaña **Extraer** | `drop.halffull` (iOS 17) | Libélula mecánica |
| Pestaña **Rejilla** | `square.grid.2x2` (`square.grid.2x2.fill`) | Espíritu del bosque |
| Pestaña **Jardín** | `leaf` (`leaf.fill`) | Brote con cara |
| Marca en cabecera | `sun.max.fill` en `secondary`, dentro de un cuadrado `radiusBlock` 32 pt `secondaryFixed` | Logotipo ilustrado |
| «Sí, es eso» | `heart` / `heart.fill` (color `secondary`, no `error`: no es un aviso) | `favorite` con contador |
| «No» | `hand.thumbsdown` / `hand.thumbsdown.fill` | — |
| Guardar en el Jardín | `leaf` + «Guardar» / `leaf.fill` + «Guardado» | `potted_plant` «To Garden» |
| Copiar hex | `doc.on.doc` | `content_copy` |
| Compartir tarjeta | `square.and.arrow.up` | `share` |
| Menú de publicación | `ellipsis` | `more_horiz` |
| Ver en Extraer (reanalizar) | `arrow.up.left.and.arrow.down.right` | `loupe` |
| Elegir foto / Cámara / Escanear carrete | `photo.on.rectangle` / `camera` / `photo.stack` | — |
| Ver máscara / Ocultar máscara | `theatermask.and.paintbrush` / `eye.slash` | `auto_awesome` «Auto-Detect» |
| Ver capas | `square.3.layers.3d` | `tune` |
| Todas las personas | `person.3.fill` | — |
| Buscar / Buscar por color | `magnifyingglass` / `slider.horizontal.3` | `search` / `tune` |
| Otra (al azar) | `dice` | Reloj de sol, `magic_button` |
| Bloqueada / Desbloquear / En tu rejilla | `lock` / `lock.open` / `checkmark.seal.fill` | `bookmark_add`, corazón con cifra |
| Ajustes | `gearshape` | `filter_vintage` |
| Exportar diagnóstico | `doc.zipper` | `photo_library` «Postcard» |
| Colecciones | `folder` | `create_new_folder` |
| Aviso de recorte / fallo | `person.crop.rectangle` / `exclamationmark.triangle` | `flare` «Aura Reticle» |
| Nueva foto (en resultado) | `arrow.counterclockwise` | — |
| Cerrar visor de capas | `xmark` | — |

**Marca**: `ios/ColorsApp/App/AppBrand.swift` → `enum AppBrand { static let name = "ChromaSol" }`. La usan la
cabecera, la marca de agua de la tarjeta («ChromaSol · Wada Nº 067»), «Acerca de», el PNG de capas y el título
de `BootErrorView`. No cambian `PRODUCT_NAME`, `CFBundleDisplayName` (ColorsApp), el identificador del bundle
ni los textos de permisos de `Info.plist` (siguen diciendo «ColorsApp»; cambiarlos es decisión del usuario).

---

## 4. Inventario de componentes

Nombres Swift propuestos en `ios/ColorsApp/Theme/Components/`. «Pantalla» = dónde aparece en el ejemplo.
Todos respetan §1.4 si contienen color de datos.

| # | Componente | Pantalla del ejemplo | Anatomía y tokens | Estados |
|---|---|---|---|---|
| 1 | `BrandHeader` | Las cuatro | 64 pt + área segura; pergamino esmerilado; marca 32 pt; «ChromaSol» `headline-sm` `primary` tracking −0,45; rótulo de sección `label-sm` `secondary` mayúsculas tracking 1,1; a la derecha un solo botón de icono 44 pt (`secondary`) | Normal · con acción contextual · sin rótulo en AX · sombra `sepia 4 %` al desplazar |
| 2 | `SolarTabBar` (TabView del sistema) | Las cuatro | Cuatro pestañas §3.6, `label-sm`; seleccionada `primary`, resto `onSurfaceVariant` | Seleccionada · no seleccionada · insignia del sistema (`.badge`) con el número de fotos analizadas sobre Extraer mientras escanea el carrete |
| 3 | `FilterChip` | Feed (fila superior), Rejilla (chips) | Capsule, relleno 12 × 6, `label-md`; activa `primary`/`onPrimary` con icono; reposo `containerHigh`/`onSurfaceVariant`; icono opcional (no puntos de color de datos) | Reposo · activa · deshabilitada (50 %) · con contador («2 colores · 12») |
| 4 | `SegmentedPill` | Garden | Carril `containerHigh` capsule con relleno 4; segmento activo `primary`/`onPrimary` `label-md` | Seleccionado · no seleccionado |
| 5 | `SearchField` | Rejilla | Capsule `card`, E1, relleno 12 × 10; lupa `secondary` 20; texto `body-md`; placeholder `onSurfaceVariant`; botón `slider.horizontal.3` | Vacío · enfocado · con texto y borrar (`xmark.circle.fill`) · interpretado (chip bajo el campo: «Nº 67», «Color más cercano: Laelia Pink · ΔE 2,3») · sin resultados |
| 6 | `DayComboCard` | Feed («Solar Pick of the Day») | Tarjeta `container` radio 12 relleno 12 E1+; `overline` «COMBINACIÓN DEL DÍA»; insignia «Nº 104» `containerHighest`; `PaletteWell` tira 24 pt; nombre `headline-md`; «4 colores · Bloqueada»; `PrimaryButton` variante ámbar (`secondary`/`onSecondary`, 6,45:1) a todo el ancho «Otra combinación» (`dice`), **sin sombra E3** porque comparte tarjeta con un pocillo | Cargando · desbloqueada · bloqueada · barajando |
| 7 | `RandomComboCard` | Rejilla («Draw a Random Solar Palette») | Tarjeta `container` radio 12 relleno 12 E1+ con lavados cálido y verde lejos del pocillo; `overline` «AL AZAR»; título `headline-sm` `primary`; descripción `body-sm`; fichas 48 pt separadas 6 pt en `PaletteWell`; nombre `label-md` `primary`; botón `PrimaryButton` compacto «Otra» (`dice`), sin sombra E3 | Igual que 6 |
| 8 | `PaletteWell` | Todas | Contenedor `wellFill` + `wellEdge`, radio 12 (8 en tarjetas), relleno ≥ 8; variantes: `.strip` (partes iguales), `.weights` (proporcional al peso), `.tiles` (fichas separadas), `.stripes` (verticales), `.droplets` (círculos con rótulos) | Normal · segmento seleccionado (`wellSelection`) · copiado (check 1 s) · bloqueada (`wellPlaceholder` rayado + `lock`) |
| 9 | `SwatchDroplet` | Feed (gotas), Garden (cosecha) | Círculo 44 plano + `swatchHairline`; bajo él nombre de Wada más cercano `label-sm` `wellText` (1 línea) y hex `hex` `wellTextSecondary`; opcional peso «39 %» | Normal · pulsado (copia hex + toast) · seleccionado · foco VoiceOver («Color 1 de 5, Black, #222524, 39 por ciento») |
| 10 | `SwatchBead` y `MicroColorPill` | Extract (etiquetas), Garden (micro-píldoras) | Cuenta 8–20 pt con anillo `wellFill` 2 pt + filo `wellEdge`; píldora `wellFillAlt` o esmerilada con nombre `label-sm` y hex `hex` al 60 % → `wellTextSecondary` | Normal · copiado |
| 11 | `FeedPostCard` | Feed | Tarjeta `card` radio 12 E1, borde pictórico; cabecera (icono de origen 36, título `label-lg`, metadatos `body-sm`, `ellipsis`); foto a sangre dentro de la tarjeta; `PaletteWell.droplets`; pie con combinación ganadora; `FeedActionBar` | Con foto · sin foto (placeholder `containerLow` + `photo`) · ambiguo · sin resultado · votado sí / no · guardado · borrándose |
| 12 | `FeedActionBar` | Feed | Relleno 12 × 8; acciones `label-md` con iconos 20: Sí (`heart`), No (`hand.thumbsdown`), Guardar (`leaf`), Copiar (`doc.on.doc`); a la derecha Compartir 32 | Sí marcado (`heart.fill` `secondary`) · No marcado · votos bloqueados tras votar · guardado · preparando tarjeta (`ProgressView`) |
| 13 | `Viewfinder` | Extract | Radio 12, alto ≤ 400, foto ajustada sin recorte sobre `containerLow`; viñeta `onSurface` 40 % abajo / 20 % arriba solo en las franjas del HUD; HUD superior e inferior | Vacío (captura) · cargando · analizando · resultado · máscara visible · reanalizando persona · error |
| 14 | `GarmentPin` | Extract | `SwatchBead` 24 pt en el centroide del swatch (§5.2) + etiqueta esmerilada capsule con nombre de Wada y peso; etiqueta arriba si la cuenta está en la mitad inferior, abajo si no; sombra E3 neutra | Normal · seleccionado (anillo `wellSelection`, tarjeta enlazada resaltada) · aislado (pulsación larga: capa 10 aislando ese swatch) · colisión (etiqueta desplazada, cuenta desplazada ≤ 12 pt con guía de 1 px `wellEdge`) |
| 15 | `HUDPill` | Extract | Capsule esmerilada, relleno 8 × 4, icono 15, `label-sm` | Aviso normal (`onSurface`) · aviso de fallback (`secondary` + `exclamationmark.triangle`) · conmutador activo (`primary` relleno) |
| 16 | `PeopleStrip` | Extract (barra inferior del visor) | Barra esmerilada radio 12 relleno 8 a 12 pt de los bordes; miniaturas 32 × 40 radio 8; «Todas» `person.3.fill`; botón «Ver capas» 32 a la derecha | Persona elegida (anillo `primary` 2 pt) · otra · deshabilitada tras votar (texto «Ya has votado…») · reanalizando (`ProgressView`) · oculta con < 2 personas (queda solo «Ver capas») |
| 17 | `GarmentSwatchCard` | Extract (2 × 2) | Tarjeta `wellFill` radio 12 relleno 8 E1; bloque de color 64 pt radio 8 plano; debajo: «01 · 39 %» `overline` `wellTextSecondary`; nombre de Wada `headline-sm` `wellText`; hex `hex`; etiqueta «ΔE 2,3» radio 4 `wellFillAlt`; `doc.on.doc` | Normal · seleccionada (desde el alfiler) · copiada · 5.º swatch a ancho completo |
| 18 | `WeightRibbon` | Extract (cinta), Garden (barra de proporción) | `PaletteWell.weights` alto 12 (Extraer) o 16 (Jardín), capsule, sin sombra interior; texto opcional «39 % · 23 % · 16 %» `body-sm` | Normal |
| 19 | `MatchCard` y `MatchRow` | Nuevo (Extract no tiene top-3) | Top-1: tarjeta `card` radio 12 E1; `PaletteWell.strip` 64 pt; nombre `headline-lg-mobile`; «Nº 337 · 4 colores» `body-sm`; «Score 19,56 (menor es mejor)» `label-md`; `AmbiguityPill` (`secondaryFixed` / `onSecondaryFixedVariant`); `UnlockButton`; «Ver en el diccionario». Top-2/3: fila con tira 104 × 34 en pocillo, nombre `label-lg`, score a la derecha | Normal · ambiguo · sin resultado · desbloquear: bloqueada / recién desbloqueada / ya en tu rejilla |
| 20 | `PrimaryButton` | Extract («Save Palette…»), Feed («Draw…»), Rejilla («Surprise Me!») | Capsule `primary` (o `secondary` en la variante ámbar), texto `label-lg` `onPrimary`, relleno 20 × 14, filo de luz, E3 | Normal · pulsado (0,97) · deshabilitado (`onSurface` 12 % / texto 38 %) · cargando (`ProgressView` + texto) |
| 21 | `SecondaryPillButton` | Extract («Copy HEX Codes», «Variations») | Capsule `container`, texto `label-md` `primary`, icono `secondary` 17, relleno 12 × 10, E2 | Normal · pulsado · deshabilitado · hecho (check 1 s) |
| 22 | `GhostButton` | DESIGN.md (filigrana) | Capsule `surface`, borde latón 35 %, texto `primary` | Normal · pulsado · deshabilitado |
| 23 | `ComboGridCard` | Rejilla | Tarjeta `card` radio 12 E1; `PaletteWell.stripes` 112 pt con relleno 6; cuerpo relleno 8: nombre `card-title`; «Nº 012 · 3 colores» `body-sm`; pie: estado (`checkmark.seal.fill` «14 sept» `primary` o `lock` «Bloqueada» `onSurfaceVariant`) y `leaf` guardar | Desbloqueada · bloqueada (`wellPlaceholder`) · bloqueada en resultados de búsqueda (colores reales + candado) · guardada |
| 24 | `ProfileHeaderCard` + `StatTriplet` | Garden | Tarjeta `card` radio 12 E1 con lavados; icono `leaf.fill` en círculo `primaryFixed` 56; «Tu jardín» `headline-sm`; subtítulo `label-md` `secondary`; línea de acierto `body-sm`; `gearshape` 36; contadores en carril `containerLow`→`container` radio 8 con divisores `outlineVariant` 40 %: valor `headline-sm` 600 + `label-sm` | Cargando (—) · valores · sin datos |
| 25 | `CollectionChip` | Garden («Moodboard Folios») | Capsule `card` E2, punto `tertiary`/`secondaryContainer`/`primary` (tokens, no datos), `label-md`, contador `label-sm` en `container` | Normal · pulsado |
| 26 | `HarvestCard` | Garden («Extracted Harvests») | Tarjeta `card` radio 12 relleno 12 E1+; miniatura 48 radio 8; título `headline-sm`; metadatos `body-sm`; insignia de veredicto; variante gotas (`PaletteWell.droplets` + fila «Dominante») o variante proporción (`WeightRibbon` + `MicroColorPill`) | Sí · No · sin votar · guardada · sin foto · copiado |
| 27 | `ExportToolTile` | Garden («Artisanal Export Studio») | Ficha `card` radio 8 relleno 8 E2 borde `outlineVariant` 30 %; icono 32 en círculo `primaryFixed`/`secondaryFixed`/`tertiaryFixed`; título `label-md` 600; descripción `body-sm` | Normal · en curso (`ProgressView`) · listo (se convierte en `ShareLink`) · error (`error`) · deshabilitado (sin scans) |
| 28 | `Toast` | Las cuatro | Capsule `inverseSurface`, `label-md` `inverseOnSurface`, icono `secondaryFixedDim`, E3, 2,2 s | Copiado · guardado · error |
| 29 | `ProgressBanner` | Nuevo (escaneo del carrete) | Tarjeta `container` radio 12; `photo.stack`; texto `label-lg`; `ProgressView` lineal `primary` sobre `surfaceVariant`; «Cancelar» | Pidiendo acceso · buscando · analizando n/N · terminado (enlace al resumen) · fallo (reintentar) |
| 30 | `LayerStoriesViewer` | Nuevo (inspector de 12 capas; la 8 es «Prendas», ADR-011) | Pantalla completa sobre neutro `#121212`; 12 segmentos arriba; capa sobre la foto; panel inferior radio 24 esmerilado oscuro neutro con título `headline-md`, significado `body-md`, datos `body-sm` con dígitos tabulares, slider de opacidad, pocillo por prenda con sus tonos agrupados en la capa 8 y chips de swatch en la capa 10 | Cargando capas · capa n · panel expandido (capas 8, 11 y 12) · interfaz oculta (pulsación larga) · compartiendo |
| 31 | `ShareCardView` 1080 × 1350 | Garden («Postcard PNG» → tarjeta real) | Siempre claro; marco `surface`; foto radio 12 con margen 16; `WeightRibbon` y tira de la combinación en pocillos blancos; nombre Literata 600; «Nº 067 · 2 colores»; marca `AppBrand.name` | Con foto · sin foto |
| 32 | `EmptyState` | Nuevo | Icono 44 `secondary`, título `headline-sm`, texto `body-lg`, `PrimaryButton` | Feed vacío · Jardín vacío · búsqueda sin resultados |
| 33 | `ComboDetailSheet` | Rejilla (tap en tarjeta) | Hoja radio 24 `containerLow`; tira 180 pt en pocillo; nombre `headline-lg`; estado en la rejilla; `WadaColorCard` por color (swatch 64 en pocillo, nombre, hex, RGB, Lab del motor) | Desbloqueada · bloqueada · nombre propuesto (etiqueta «Nombre propuesto») |

---

## 5. Mapa de funciones por pantalla

Convención de las tablas: **Bloque** = lo que hay en el ejemplo (texto o clase literal) · **En la app** = la
función real que ocupa ese sitio · **Datos / API** = lo que ya existe en `ios/ColorsApp` (o el hueco de §5.5) ·
**Destino** = se mantiene, se sustituye (→) o se elimina (✕).

### 5.0 Común a las cuatro pantallas

> **Superado por `FIDELITY.md` §2 y §3–§6** (2026-09-16) en las filas del logotipo, el botón de sol, el
> avatar, las partículas y la barra de pestañas: la marca es un logotipo ilustrado propio, el botón de sol
> conserva su acción contextual pero se dibuja como sol animado, hay avatar local (brote en maceta, sin
> cuentas ni fotos de persona), sí hay motas de luz y anillos, y la barra de pestañas es propia
> (`RootTabBar`) con los cuatro personajes originales. Las **funciones** de la columna «En la app» no
> cambian: son las mismas acciones y los mismos datos.
> Pantallas secundarias (Ajustes, «Acerca de», licencias y el flujo de escaneo): `FIDELITY.md` §7.5.

| Bloque | En la app | Datos / API | Destino |
|---|---|---|---|
| Logotipo ilustrado + «ChromaSol» + rótulo («FEED», «EXTRACT», «REJILLA», «GARDEN») | `BrandHeader` con `AppBrand.name` y rótulo «FEED», «EXTRAER», «REJILLA», «JARDÍN» | `AppBrand` | → marca sencilla (§3.6) |
| Botón «Solar Flare Aura» (sol con cara, solo muestra un toast) | Un botón de icono contextual: Feed `camera` «Analizar una foto» (`selectTab(.extraer)`); Extraer `photo.stack` «Escanear carrete» en captura y `arrow.counterclockwise` «Nueva foto» en resultado; Rejilla cápsula «20/348»; Jardín `gearshape` «Ajustes» | `SelectTabAction`, `ScanOnboardingView`, `RejillaModel.counterText`, `AjustesForm` | → |
| Avatar de perfil con insignia «✦» | — | — | ✕ (sin cuentas ni perfiles) |
| Partículas, motas, anillos giratorios, `animate-ping` decorativos | — | — | ✕ |
| Barra inferior con criaturas animadas | `TabView` del sistema: Feed · Extraer · Rejilla · Jardín con SF Symbols | `AppTab` (§6.2) | → |
| Toasts («Harvested Swatch to Clipboard», «Planted into Your Solarpunk Garden 🌱») | `Toast`: «Copiado #222524», «Copiados 5 hex», «Guardado en el Jardín», «Quitado del Jardín» | `UIPasteboard.general.string` | → |

### 5.1 Feed: los análisis guardados como publicaciones

Fuente de las publicaciones: `env.scans.observeRecent(limit: 50)` (se amplía de 50 en 50 al llegar al final).
Cada `ScanRecord` aporta `palette` (hex + peso, ≤ 5), `topIds`, `scoreValues`, `ambiguous`, `source`,
`scannedAt`, `subjectMode`, `regionMode`, `peopleCount`, `personIndex` y `maskStepValues`. Veredicto:
`env.feedback.latest(forScan:)` (o `all()` agrupado, como hace hoy `HoyView.latestVerdicts`). Desbloqueos:
`env.unlocks.observeUnlockedIds()`.

| Bloque | En la app | Datos / API | Destino |
|---|---|---|---|
| Chips «All Clothing», «Linen Coats», un chip con el nombre de un estudio de animación, «Botanist Aprons», «Summer Dusters» (con puntos de color brillantes) | `FilterChip`: «Todo» (`sun.max`), «2 colores», «3 colores», «4 colores» (tamaño de la combinación top-1), «Guardadas» (colección propia), «Por votar» (sin veredicto). Sin puntos de color de datos | `dictionary.combo(id:).size`, `GardenStore` (§5.5-2), veredictos | → colecciones por tamaño / propias |
| Tarjeta «Solar Pick of the Day» + insignia «Zenith #104» | `DayComboCard` «COMBINACIÓN DEL DÍA» + insignia «Nº 104». Elección determinista por fecha local: `id = (díasDesde1970 × 7919) mod 348 + 1` | `dictionary.combinations` | → |
| Cinta de 4 colores con anillo ámbar | `PaletteWell.strip` (24 pt) con los colores de la combinación en pocillo | `dictionary.colors(of:)` | → (§1.4) |
| «✦ Harmonic Solar Quintet» · «4 NATURAL DYES» | Nombre (aceptado → propuesto → «Nº 104») · «4 COLORES · BLOQUEADA / EN TU REJILLA» | `displayName`, §5.5-3, `observeUnlockedIds` | → |
| Botón ámbar «Draw Random Sun Palette» | `PrimaryButton` ámbar a todo el ancho «Otra combinación» (`dice`): otra combinación al azar distinta de la actual; en memoria, vuelve a la del día al cambiar la fecha. Tocar la tarjeta abre `ComboDetailSheet` | `SystemRandomNumberGenerator` (UI; el motor no tiene RNG y no se toca) | → |
| Cabecera de publicación: retrato, «Clara & The Windmill ✨», «Colmar Outskirts • 10:45 AM Golden Hour» | Icono de origen en círculo `secondaryFixed` (`photo.stack` carrete, `camera` cámara, `photo.on.rectangle` foto elegida); título `label-lg` «Carrete» / «Cámara» / «Foto elegida»; metadatos «14 sept 2026, 10:45 · Persona principal · solo ropa» | `ScanSource.label`, `scannedAt.formatted(date: .abbreviated, time: .shortened)`, `MaskStepsText.short(scan:)` (§5.5-7) | → (sin nombres de personas, lugares ni «hora dorada») |
| `more_horiz` | Menú `ellipsis`: «Abrir en Extraer», «Ver combinación», «Borrar del Feed» (confirmación) | §5.5-4, `ComboDetailSheet`, `env.scans.softDelete(id:)` | → |
| Foto 4:3 a sangre | Foto del análisis a sangre dentro de la tarjeta, proporción de la foto limitada a 4:5 … 4:3, recorte centrado; sin foto disponible: placeholder `containerLow` con `photo` y «Foto no disponible» | `ScanPhotoStore` o `PHImageManager` por `assetLocalId` (§5.5-1) | → |
| Insignia «ChromaSol Sunbeam Lens» | Píldora esmerilada con el recorte usado: «Solo ropa», «Todas las personas (3)», «Foto completa» (fallback en `secondary`) | `MaskStepsText.short(scan:)` | → |
| Botón lupa `loupe` | `arrow.up.left.and.arrow.down.right` «Abrir en Extraer»: reanaliza la foto y empuja `ResultView` con alfileres, personas y capas | §5.5-4, `ScanAnalyzer.analyze`, `ResultViewModel` | → |
| «EXTRACTED CLOTHING SPECTRUM» + «Copy HEX Strip» | `overline` «PALETA DE LA ROPA» («PALETA DE LA FOTO» si no hubo máscara) + enlace «Copiar hex»: copia los hex de la paleta de la foto separados por espacios | `scan.palette`, `scan.maskCoverage` | → copiar hex |
| 5 gotas (círculo 44 con brillo, «Sage Wool», «#7A9A7B») sobre pergamino `surface-container-low` | `PaletteWell.droplets` sobre `wellFill`: círculo plano, nombre del color de Wada más cercano, hex, peso «39 %». Tocar = copiar ese hex | `ColorSearch.nearest(hex:)` → `dictionary.color(index:).name` | → (§1.4) |
| Variante de 4 chips en tarjetas (segunda publicación) | Solo con tamaños de accesibilidad: filas de 1 swatch + nombre + hex | ídem | → |
| (No existe) | **Pie**: «Se parece a» `label-sm` + tira de la combinación top-1 en pocillo + nombre `headline-sm` + «Nº 337 · 4 colores»; si `ambiguous`, píldora «Entre Nº 337 y Nº 027»; sin resultado: «El motor no ha encontrado combinación». Tocar = `ComboDetailSheet` | `topIds`, `ambiguous`, `displayName` | nuevo |
| ♥ «482» (me gusta con contador) | «Sí» `heart` → `heart.fill` «Es eso»; al lado «No» `hand.thumbsdown`. Un solo voto por publicación (igual que Resultado); sin contadores | `env.feedback.record(scanId:verdict:)` + copia de diagnóstico (§5.5-5) | → «Sí, es eso» / «No» |
| `potted_plant` «To Garden» | `leaf` «Guardar» ⇄ `leaf.fill` «Guardado» | `GardenStore` (§5.5-2) | → guardar en colección local |
| `content_copy` «HEX Bar» | `doc.on.doc` «Copiar»: copia los hex **de la combinación ganadora** de Wada (el enlace de la paleta copia los de la foto) | `dictionary.colors(of:).map(\.hex)` | → copiar hex |
| `share` | `ShareLink` con la tarjeta 1080 × 1350 (se renderiza al aparecer la publicación y se cachea por `scan.id`/`rev`) | `ShareCardRenderer.card(for scan:photo:dictionary:)` (§5.5-6) | → compartir |
| Contadores «482», «319» | — | — | ✕ |
| (No existe) | `ProgressBanner` del escaneo del carrete bajo los chips mientras `env.scanProgress.phase` ≠ `.idle`/`.finished` | `AppEnvironment.scanProgress` | nuevo |
| (No existe) | `EmptyState`: «Tus fotos analizadas aparecen aquí» + «Analizar una foto» (→ Extraer) + «Escanear carrete». En el primer arranque se presenta `ScanOnboardingView` con la regla actual | `HoyView.shouldPresentOnboarding` → `FeedOnboarding` (§6.3) | nuevo |

### 5.2 Extraer: captura y resultado con alfileres

**Estado de captura** (sin foto) dentro del visor:

| Elemento | En la app | Datos / API |
|---|---|---|
| Título | «Analiza la ropa de una foto» `headline-sm` + «Se procesa en el teléfono; nada sale del dispositivo.» `body-sm` | — |
| `PrimaryButton` «Elegir foto» | `PhotosPicker(selection:matching: .images, photoLibrary: .shared())` | `ImageLoading.cgImage(from:)` |
| `SecondaryPillButton` «Cámara» | `CameraPicker` a pantalla completa; sin cámara: deshabilitado con «No hay cámara en este dispositivo (simulador).» | `CameraPicker.isAvailable`, `ImageLoading.upright` |
| `GhostButton` «Escanear carrete (200 fotos)» | Hoja `ScanOnboardingView` → `WrappedSummaryView` | `env.runInitialScan(limit: 200)` |
| Progreso / error | Capa sobre el visor: «Cargando la foto…», «Analizando…» con `ProgressView`; error en `HUDPill` de fallback + texto `error` | `ScanAnalyzer.run(image:source:assetLocalId:env:)`, `ErrorText.describe` |

**Estado de resultado** (`ResultViewModel(outcome:env:)`):

| Bloque | En la app | Datos / API | Destino |
|---|---|---|---|
| Visor 400 pt con foto a sangre recortada | `Viewfinder` con `outcome.image` ajustada **sin recorte** (los alfileres caen donde toca) | `ScanOutcome.image` | → |
| Viñeta `from-on-surface/40` | Solo detrás del HUD superior e inferior, no sobre toda la foto | — | → |
| Motas de luz, retículas de esquina `filter_center_focus`/`crop_free` | — | — | ✕ |
| Píldora «AURA RETICLE ACTIVE» | `HUDPill` con el aviso del recorte («Persona principal de 2 · solo ropa · piel excluida»; fallback «Vision no disponible: foto completa» en `secondary`). Tocar muestra el texto completo | `model.maskNotice` | → |
| Botón «Auto-Detect» | Conmutador «Ver máscara» / «Ocultar máscara» (`theatermask.and.paintbrush` / `eye.slash`), deshabilitado sin máscara | `model.showMask`, `model.maskOverlay` (`LayerBitmaps.dimOutside`) | → |
| Alfileres «Copper Marigold ✦», «Sunlit Brass», «Windmill Linen», «Ancient Fern» con halo del color | `GarmentPin` por swatch: cuenta en el **centroide de los píxeles del swatch en el label map** ajustado al píxel más cercano con esa etiqueta (cae sobre la prenda aunque la región no sea convexa); etiqueta con el nombre de Wada más cercano y el peso («Black · 39 %») | `outcome.debug.labelMap` (`reducedWidth × reducedHeight`, etiqueta = índice del swatch; se ignoran `paletteLabelNone` y `paletteLabelDiscarded`); coordenada normalizada `((x + 0,5) / rw, (y + 0,5) / rh)` × rectángulo mostrado; cálculo en `Task.detached`; sin `debug` no hay alfileres | → |
| Tocar alfiler (toast «Target reticle calibrated») | Selecciona y desplaza a su `GarmentSwatchCard`; pulsación larga = aislar sus píxeles sobre la foto mientras se mantiene | `LayerBitmaps.labels(_:width:height:swatches:isolate:)` | → |
| Barra «Sun Angle Chromatic Adjust 38° W» con slider y `tune` | `PeopleStrip` (miniaturas + «Todas», solo con ≥ 2 personas) + botón «Ver capas» a la derecha | `model.personThumbnails`, `model.choose(_:)`, `model.canChangePerson`, `LayersRoute(outcome:)` | → (el ajuste de ángulo solar no existe) |
| «Extracted Garment Harmony» + `palette` | «Colores de la ropa» («Colores de la foto» sin máscara) | `outcome.maskApplied` | → |
| Píldora «Warm Earth Analogous • 98% Botanical Dye Match» | Píldora informativa «5 colores · 12 % de la foto» (o «foto completa») | `result.swatches.count`, `subject.maskCoverage` | → (sin armonías ni porcentajes inventados) |
| Tarjetas 2 × 2 «01 OUTER VEST / Sunlit Brass / #C4823F / Leather» | `GarmentSwatchCard`: «01 · 39 %», nombre de Wada más cercano, hex, etiqueta «ΔE 2,3» (distancia a ese color de Wada). Tocar copia el hex | `result.swatches` (hex, peso), `ColorSearch.nearest(hex:)` (`index`, `deltaE`) | → (la app no reconoce tipos de prenda ni materiales: ✕ «Outer vest», «Leather») |
| Cinta de 4 partes iguales | `WeightRibbon` proporcional al peso | `swatch.weight` | → |
| (No existe) | **Top-3**: `MatchCard` top-1 (tira, nombre, «Nº 337 · 4 colores», «Score 19,56 (menor es mejor)», «Entre A y B» si ambiguo, `UnlockButton`, «Ver en el diccionario») + `MatchRow` top-2 y top-3 | `model.top1Combo`, `model.topHit`, `model.otherHits`, `model.ambiguityText`, `model.comboHeadline`, `model.unlockState`, `model.unlock()` | nuevo |
| CTA «Save Palette to Garden» | `PrimaryButton` «Sí, es eso» (`heart`); tras votar, «Gracias. Marcado como acierto.» | `model.vote(.yes)`, `model.verdict` | → |
| (No existe) | Fila secundaria 1: «No, no es eso» (`hand.thumbsdown`) · «Guardar» (`leaf`) | `model.vote(.no)`, `GardenStore` | nuevo |
| «Copy HEX Codes» · «Variations» | Fila secundaria 2: «Copiar hex» (paleta de la foto) · «Compartir» (tarjeta 1080 × 1350) | `result.swatches`, `model.makeShareImage()` | → («Variations» ✕: no existe) |
| (Pie técnico actual) | «Motor 0.x · diccionario fd95ac692777 · 812 ms (Vision · máscara · motor)» `body-sm` `onSurfaceVariant` | `outcome.scan.engineVersion`, `timings` | se mantiene |

**«Ver capas» como visor tipo historias** (`LayerStoriesViewer`, `fullScreenCover`):

- Once segmentos arriba (uno por `InspectorLayer`, en el orden del pipeline); cabecera «9 · Asignación a colores»,
  `xmark` y `square.and.arrow.up` (`model.shareURL`, id `layers.share`).
- Foto con la capa superpuesta a pantalla completa sobre neutro `#121212`; tercio izquierdo = anterior, resto =
  siguiente; deslizar hacia abajo = cerrar; pulsación larga = ocultar la interfaz para ver la capa limpia.
- **Sin avance automático**: cada capa se lee a su ritmo.
- Panel inferior (radio 24): título, significado, datos, slider de opacidad (`model.opacityBinding`), chips de
  swatch para aislar en la capa 10 (`model.toggleIsolation`); las capas 8, 11 y 12 (prendas, paleta y explicación del
  top-3) abren el panel expandido con desplazamiento.
- `initialLayer` (atajo `-uiLayer`) abre directamente esa capa. Modelo y datos sin cambios:
  `LayersInspectorModel`, `LayerStack.build`, `LayersShareRenderer`.

### 5.3 Rejilla: las 348 combinaciones

Estado: `RejillaModel` (desbloqueos observados, `sizeFilter`, `counterText`, `unlockedCount(in:)`) +
`env.dictionary`.

| Bloque | En la app | Datos / API | Destino |
|---|---|---|---|
| Sol + avatar | Cápsula «20/348» (`label-lg` `primary` sobre `primaryFixed`), id `rejilla.counter` | `model.counterText(total:)` | → |
| Buscador fijo «Search 12,400+ community garment palettes…» | `SearchField` fijo bajo la cabecera: «Busca por nombre, número o #hex». Interpretación: número `^\s*(n[º°o.]?\s*)?\d{1,3}\s*$` en 1…348 → esa combinación primero (Intro abre su detalle); hex `^#?[0-9a-fA-F]{6}$` → color de Wada más cercano y combinaciones que lo contienen (chip «Color más cercano: Laelia Pink · ΔE 2,3»); resto → texto sin mayúsculas ni tildes sobre el nombre de la combinación (aceptado o propuesto) y los nombres de sus colores | `ExplorarView.parseNumber` → `RejillaSearch.parseNumber`, `ColorSearch.nearest(hex:)`, `dictionary.combos(containingColor:)`, `localizedStandardContains` | → (sin «comunidad») |
| Botón `tune` del buscador | Hoja «Buscar por color»: `ColorPicker` + hex → color de Wada más cercano (ΔE00, Lab del motor) → combinaciones | `ColorSearchView` (reestilizada) | → |
| Tarjeta «SOLAR DIVINATION ✦ · Draw a Random Solar Palette · Let the morning prism…» con reloj de sol | `RandomComboCard` «AL AZAR · Una combinación al azar · Una de las 348 de Sanzo Wada. Tócala para ver sus colores y cómo desbloquearla.»; icono `dice` en círculo | `dictionary.combinations` | → |
| Cinco fichas de color con sombra | Fichas de la combinación en `PaletteWell.tiles` (siempre con sus colores: es la puerta de exploración) + estado «Bloqueada» / «En tu rejilla» | `dictionary.colors(of:)`, `model.isUnlocked` | → |
| «Ancient Garden Canopy» + «Surprise Me!» | Nombre + `PrimaryButton` compacto «Otra» (`dice`) | `displayName` | → |
| Chips «All Palettes», «Botanical Coats», un chip con el nombre de un estudio de animación, «Earth & Linen», «Brass & Clockwork», «Pastel Florals» | Grupo tamaño: «Todas», «2 colores», «3 colores», «4 colores» (id `rejilla.filter`) · separador · grupo estado: «Desbloqueadas», «Bloqueadas» · «Guardadas». Debajo: «12 de 120 desbloqueadas» + barra de progreso `primary` (id `rejilla.filter.counter`) | `model.sizeFilter`, `statusFilter` nuevo en `RejillaModel`, `GardenStore` | → |
| Cuadrícula de 6 tarjetas: franjas, títulos con nombres de películas, autoras ficticias, ♥ «1.2k», `bookmark_add` | `LazyVGrid` de 2 columnas (1 en AX) con las 348 `ComboGridCard` en orden de número: franjas verticales en pocillo; título = nombre aceptado o propuesto (o «Nº 012»); «Nº 012 · 3 colores»; pie con estado (`checkmark.seal.fill` + fecha de desbloqueo, o `lock` «Bloqueada»); `leaf` guardar. Tocar = `ComboDetailSheet` (`.medium`, `.large`), ids `rejilla.tile.<id>` y `rejilla.detail.<id>` | `model.unlock(for:)`, `dictionary.colors(of:)`, `RejillaComboDetailView` | → (sin autores, likes ni nombres del ejemplo) |
| Botón actual «Escanear carrete» de la barra | Pasa a Extraer y al Jardín | — | → |

**Decisión sobre las bloqueadas** (a confirmar por el usuario): la cuadrícula conserva la mecánica de `PLAN.md`
§7.5, «desbloqueadas vs. grises»: una combinación bloqueada muestra `wellPlaceholder` rayado y candado. Con una
búsqueda activa (sustituye a Explorar) los resultados muestran sus colores reales con el candado; la tarjeta
«Al azar» y el detalle siempre los muestran. Si el usuario prefiere ver siempre los colores, basta con quitar el
placeholder: el resto del diseño no cambia.

### 5.4 Jardín: perfil local

| Bloque | En la app | Datos / API | Destino |
|---|---|---|---|
| Sol + avatar | `gearshape` → empuja `AjustesForm` («Ajustes»: Recorte, Desbloqueo, Carrete, Diagnóstico, Versiones, Acerca de) | `AjustesForm` | → acceso a Ajustes |
| Retrato ilustrado con compañero, «Elian Finch», insignia con el nombre de un videojuego | `ProfileHeaderCard`: `leaf.fill` en círculo `primaryFixed` + «Tu jardín» | — | → (✕ retrato, nombre de persona e insignia) |
| «Solar Colorist • Botanical Vault» | «Solo en este teléfono · sin cuenta» | — | → |
| «Sol-Index: 94.8% Natural Dye» | «Acierto: 82 % (41 de 50 votos)» = sí / (sí + no); sin votos: «Vota tus resultados para medir el acierto» | `env.feedback.counts()` | → métrica real |
| Botón `filter_vintage` de la tarjeta | — (Ajustes ya está en la cabecera) | — | ✕ |
| Contadores «42 Extracted · 128 Community · 1.4k Sol Likes» | `StatTriplet`: «Fotos analizadas» · «Desbloqueadas 20/348» · «Sí, es eso». Tocar: Feed · Rejilla · Feed | `env.scans.count()`, `env.unlocks.observeCount()` + `env.comboCount`, `env.feedback.counts().yes` | → contadores reales |
| Segmentos «Extracted Photos · Saved Feed · Custom Blends» | `SegmentedPill` «Cosechas» (todos los análisis) · «Guardadas» | `scans.observeRecent`, `GardenStore` | → («Custom Blends» ✕: la app no crea paletas propias) |
| «MOODBOARD FOLIOS · 3 active collections», «+ New Folder», carpetas «Autumn Linen Wardrobe 8»… | «COLECCIONES · 3»: hoy no hay carpetas locales, así que `CollectionChip` por tamaño: «2 colores · 12/120», «3 colores · 5/120», «4 colores · 3/108»; tocar abre la Rejilla con ese filtro. Cuando `GardenStore` tenga carpetas, sus chips van primero y aparece «Nueva carpeta» (`folder.badge.plus`) | `dictionary.collectionsBySize`, `RejillaModel.unlockedCount(in:)` | → |
| «Extracted Harvests · Sorted by Recency» | «Cosechas · Más recientes» + enlace «Ver todas en el Feed» | `scans.observeRecent(limit: 20)` | → |
| Cosecha 1: miniatura, «My Studio Linen Apron», «Harvested yesterday • Natural Daylight», «Synced», 5 círculos, «Dominant: Flax Bark (#C39B6A) · Copy» | `HarvestCard` (variante gotas, para la más reciente): miniatura; nombre de la combinación top-1; «ayer · Carrete»; insignia de veredicto («Sí, es eso» `primaryFixed`, «No» `secondaryFixed`, «Sin votar» `containerHigh`); gotas con hex en pocillo; fila «Dominante: Black (#222524) · 39 %» + «Copiar» | `ScanPhotoStore`, `displayName(id: top1)`, `scannedAt` relativo, `source.label`, veredicto, `palette[0]`, `ColorSearch.nearest` | → («Synced» ✕: no hay sincronización; «Natural Daylight» ✕: la app no mide la luz) |
| Cosecha 2: tira, etiquetas «Analogous Green», «High Contrast», botón «:root CSS» | Variante proporción (resto de cosechas): `WeightRibbon` 16 pt con «39 % · 23 % · 16 % · 13 % · 8 %» y `MicroColorPill` con nombres de Wada; etiquetas reales «Nº 337» y «Ambigua» (si `ambiguous`) | `palette`, `topIds`, `ambiguous` | → (armonías y CSS ✕) |
| Estrella de la cosecha 3 | `leaf.fill` «Guardada» (tocar quita) | `GardenStore` | → |
| «Artisanal Export Studio · VAULT TOOLS» | «Estudio de exportación · HERRAMIENTAS», cuatro `ExportToolTile`: | | → |
| · «Procreate (.swatches) · Direct iPad AirDrop pack» | «Compartir tarjeta · Imagen 1080 × 1350 de la última cosecha» | `ShareCardRenderer` + `ShareLink` | → |
| · «Tailwind & CSS Tokens · JSON format & variables» | «Copiar hex · Los colores de la última cosecha» | `palette`, `UIPasteboard` | → |
| · «(estudio) Postcard PNG · Parchment framed print» | «Exportar diagnóstico · Zip con veredictos, tiempos y fotos votadas» (mismo flujo que `AjustesForm.exportDiagnostics`; `ShareLink(item: export.url)`) | `Diagnostics.export(scans:feedback:timings:photoProvider:)` | → |
| · «Solar Harmony Check · Analyze natural balance» | «Escanear carrete · Últimas 200 fotos, en el teléfono» → `ScanOnboardingView` / `WrappedSummaryView` | `env.runInitialScan` | → |
| Luciérnagas, lavados con halo | Lavados estáticos lejos de pocillos (§1.3) | — | → |

### 5.5 Datos que el diseño necesita y hoy no existen

| # | Necesidad | Hoy | Propuesta | Dónde (propiedad) |
|---|---|---|---|---|
| 1 | Foto de publicaciones y cosechas | `scans` no guarda la foto. `assetLocalId` solo en carrete y en `PhotosPicker` con acceso a Fotos; la cámara no deja nada | `ScanPhotoStore`: `Application Support/ScanPhotos/<scanId>.jpg`, lado máx. 1080 px, sin metadatos, escrito tras `ScanAnalyzer.run` para cámara y foto elegida; carrete: `PHImageManager` por `assetLocalId` (reutilizar `PhotoLibraryImages.uprightImage`). Se borra con «Borrar del Feed». Nunca entra en el zip salvo lo que ya entra hoy (fotos votadas, 256 px) | `ios/ColorsApp/Support/` (interfaz) |
| 2 | «Guardar» y colecciones propias | No hay tabla | v1: `GardenStore` en JSON local (`[{kind: scan o combo, id, folder?, savedAt}]`), observable. v2: migración `v3` `garden_items` con columnas sync-ready | v1 en `Support/`; v2 se pide al equipo dueño de `ios/ColorsApp/DB/**` (no se edita desde la interfaz) |
| 3 | Nombres de combinación | `names.es.json`: 348 entradas `pending` → todo se ve «Nº 067» | Añadir `../data/wada/names.suggested.json` a recursos en `ios/project.yml` (solo lectura) y `WadaDictionary.proposedName(id:)`; `displayName` = aceptado → propuesto → «Nº 067»; en el detalle, etiqueta «Nombre propuesto» | `ios/project.yml`, `ios/ColorsApp/Model/`; `data/**` no se toca |
| 4 | Alfileres y capas de un análisis antiguo | `labelMap` y capas solo existen en `ScanOutcome` recién calculado | «Abrir en Extraer» reanaliza la foto (1) con las opciones guardadas del scan (como `PhotoLibraryImages.attachment`) usando `ScanAnalyzer.analyze(image:subject:)`, que no toca la base de datos, y construye `ScanOutcome` con el `ScanRecord` existente; **nunca** `ScanAnalyzer.run`, que insertaría un scan duplicado. El scan solo se reescribe si el usuario cambia de persona (`ResultViewModel.choose`). Si `engineVersion` difiere o el top-1 recalculado no coincide con el guardado, aviso «Recalculado con el motor actual» | Interfaz |
| 5 | Votar desde el Feed | `ResultViewModel.vote` además guarda el PNG de 256 px del raster para el diagnóstico | Desde el Feed: `feedback.record` y la copia en segundo plano desde (1) con el mismo código de `PhotoLibraryImages.attachment` | Interfaz |
| 6 | Tarjeta desde un scan | `ShareCardRenderer.card(for: ScanOutcome, …)` | Sobrecarga `card(for scan: ScanRecord, photo: CGImage?, dictionary:)` con `PaletteBars.entries(from: scan.palette)` | Interfaz |
| 7 | Aviso corto del recorte desde un scan | `MaskStepsText.notice` necesita `SubjectMaskResult` | `MaskStepsText.short(scan:)` con `subjectMode`, `regionMode`, `peopleCount`, `personIndex`, `maskStepValues` | `ios/ColorsApp/Subject/` (interfaz) |

---

## 6. Pantallas actuales y navegación final

### 6.1 Qué desaparece, qué se fusiona

| Pantalla actual (fichero) | Destino | Detalle |
|---|---|---|
| **Hoy** (`Views/Hoy/HoyView.swift`) | Se reparte en **Feed + Extraer** | «Analizar una foto» (PhotosPicker, Cámara, estados, errores) → estado de captura de Extraer. «Carrete» (escanear, progreso) → Extraer (`GhostButton` + `ProgressBanner`) y banner del Feed. «Combinaciones en tu rejilla» → cápsula de la Rejilla y contador del Jardín. «Últimos análisis» (`ScanHistoryRow`) → publicaciones del Feed y cosechas del Jardín. Presentación automática de `ScanOnboardingView` → Feed. Se conservan `ScanAnalyzer`, `ImageLoading`, `CameraPicker`, `ErrorText`, `DebugLaunch` |
| **Resultado** (`Views/Resultado/ResultView.swift`) | **Extraer**, estado de resultado; también empujado desde el Feed («Abrir en Extraer») | `ResultViewModel` se reutiliza sin cambiar su API |
| **Capas** (`Views/Capas/LayersInspectorView.swift`) | `LayerStoriesViewer` a pantalla completa | `LayersInspectorModel`, `LayerStack`, `LayersShareSheet` sin cambios |
| **Explorar** (`Views/Explorar/ExplorarView.swift`) | Desaparece → **Rejilla** | «Buscar por número» → buscador. «Buscar por color» (`ColorSearchView`) → hoja desde el buscador. «Extraer de una foto» (`PaletteExtractView`, paleta sin match y sin guardar) → se elimina: Extraer ya muestra la paleta con su match. «Colecciones» (`CollectionView`) → chips de tamaño de la Rejilla y colecciones del Jardín. `ComboDetailView` → `ComboDetailSheet` |
| **Rejilla** (`Views/Rejilla/RejillaView.swift`) | **Rejilla** rediseñada | Casillas de 58–90 pt → tarjetas de 2 columnas; contador, filtro por tamaño y detalle en hoja se mantienen; su botón «Escanear carrete» pasa a Extraer y Jardín |
| **Ajustes** (pestaña, `Views/Ajustes/AjustesView.swift`) | Deja de ser pestaña → **Jardín** › `gearshape` | `AjustesForm` conserva sus secciones y su lógica; `AboutView` suma las licencias OFL |
| Tarjeta (`Views/Tarjeta/ShareCardView.swift`) | Rediseño (§4 n.º 31) | Siempre en claro, pocillos blancos, marca `AppBrand.name` |
| Escaneo día 0 (`Views/Wrapped/*`) | Hoja desde Feed, Extraer y Jardín | Reestilo; «Ver rejilla» → `selectTab(.rejilla)` |
| `PlaceholderTabView` (`App/RootTabView.swift`) | Se elimina | Sin uso |

### 6.2 Navegación final

```text
TabView  (.tint(Solar.primary); Liquid Glass del sistema en iOS 26+, pergamino esmerilado en 17–25)
├─ Feed      sun.max            NavigationStack
│   ├─ push   ResultView(ScanOutcome)            «Abrir en Extraer» (reanaliza la foto guardada)
│   ├─ sheet  ComboDetailSheet(id)               pie de publicación, combinación del día
│   ├─ sheet  ScanOnboardingView → WrappedSummaryView
│   └─ cover  LayerStoriesViewer(LayersRoute)    desde ResultView empujado
├─ Extraer   drop.halffull      NavigationStack  (captura ⇄ resultado en la misma pantalla)
│   ├─ cover  CameraPicker
│   ├─ cover  LayerStoriesViewer(LayersRoute)
│   ├─ sheet  ComboDetailSheet(id)
│   └─ sheet  ScanOnboardingView
├─ Rejilla   square.grid.2x2    NavigationStack
│   ├─ sheet  ComboDetailSheet(id)               [.medium, .large]
│   └─ sheet  ColorSearchView                    «Buscar por color»
└─ Jardín    leaf               NavigationStack
    ├─ push   AjustesForm → AboutView → licencias OFL
    ├─ sheet  ScanOnboardingView
    └─ sheet  ComboDetailSheet(id)
```

- `AppTab`: `feed`, `extraer`, `rejilla`, `jardin`; títulos «Feed», «Extraer», «Rejilla», «Jardín»; símbolos de §3.6.
  Pestaña inicial: Feed. `SelectTabAction` se mantiene y se añade una intención para abrir la Rejilla con un
  filtro de tamaño desde el Jardín.
- Cabeceras: las cuatro raíces ocultan la barra de navegación (`.toolbar(.hidden, for: .navigationBar)`) y usan
  `BrandHeader` en `.safeAreaInset(edge: .top)`; las pantallas empujadas usan la barra del sistema con título
  Literata (§2.3).

### 6.3 Compatibilidad con tests, capturas y el plan

**Símbolos que usan los tests** (mantener o actualizar el test en el mismo cambio):

| Test | Símbolo | Qué hacer |
|---|---|---|
| `OnboardingTests` | `HoyView.shouldPresentOnboarding`, `HoyOnboarding.markDismissed` | Mover a `FeedOnboarding` y actualizar el test |
| `ExplorarTests` | `ExplorarView.parseNumber`, `ColorSearch.nearest/srgb8`, `PaletteBars.entries` | `RejillaSearch.parseNumber` (misma semántica); el resto no cambia |
| `RejillaTests`, `DayZeroScanTests` | `RejillaModel.counterText`, `RejillaContentView(model:dictionary:)`, `ComboTile(combo:colors:unlocked:)`, `RejillaComboDetailView.sourceLabel`, `WrappedSummaryView(summary:dictionary:totalCombos:onShowGrid:)`, `WrappedSummaryView.durationText` | Conservar los inicializadores (la tarjeta nueva puede llamarse `ComboTile`) o actualizar tests |
| `SubjectDatabaseTests` | `AjustesForm.persist` | Sin cambios |
| `ResultViewModelTests` | `ShareCardRenderer.card(for:dictionary:)`, `.render` | Sin cambios de firma (la sobrecarga de §5.5-6 es aditiva) |
| `LayersInspectorTests` | `LayerStack.build` | Sin cambios |

**Identificadores de accesibilidad**: se conservan `result.*`, `rejilla.*`, `ajustes.*`, `layers.share`,
`wrapped.*`, `root.tabs`, `boot.error`; los `hoy.pick`, `hoy.camera`, `hoy.scanLibrary`, `hoy.progress` y
`hoy.error` pasan a `extraer.*` (ningún test los usa: 0 coincidencias en `ios/ColorsAppTests`). Nuevos:
`feed.post.<scanId>`, `feed.yes`, `feed.no`, `feed.save`, `feed.copy`, `feed.share`, `feed.day`, `extraer.pin.<n>`,
`jardin.settings`, `jardin.export`.

**Atajos `-uiScreen`** (los usa `make ios-screens-subject` en `mk/ios.mk`): `result-demo`, `result-demo-person`,
`result-demo-people`, `result-demo-people-mask`, `result-people`, `result-people-mask`, `layers-demo` y
`layers-people` (con `-uiLayer`) abren Extraer; `explorar-<id>` abre la Rejilla con el detalle (se conserva el
nombre como alias); `ajustes` abre Jardín › Ajustes. Se añaden `feed`, `extraer`, `rejilla` y `jardin` para
capturas en claro y oscuro.

**Plan**: `PLAN.md` §7 sigue diciendo «Pestañas Hoy, Rejilla, Explorar, Ajustes»; cuando se implemente este
documento hay que actualizar esa línea (este documento no la edita).

---

## 7. Criterios de aceptación visual

Para quien implemente (con su propio `DERIVED` y su propio simulador):

1. **Propiedad intelectual**: `grep -rniE "ghibli|totoro|howl|kiki|laputa|chihiro|arrietty|zelda|botw|sheikah|zonai|kodama|susuwatari|nausica|mononoke|ponyo|porco|cagliostro" ios/` → 0 líneas.
2. **Sin funciones falsas**: `grep -rniE "12[.,]?400|community|comunidad|seguidores|followers|likes|synced|sincronizad" ios/ColorsApp` → 0 líneas.
3. **Sin red**: `make ios-lint` en verde.
4. **Pocillos**: en capturas del simulador, los píxeles del pocillo valen exactamente `(255,255,255)` en claro y `(48,48,48)` en oscuro; ningún píxel no neutro (|R−G|, |G−B| > 2) en un anillo de 8 pt alrededor de cada swatch.
5. **Fuentes**: test de §2.1 punto 4 en verde; en una captura, «ChromaSol» se ve en Literata (no en SF).
6. **Temas y tamaños**: capturas de Feed, Extraer (captura y resultado), Rejilla, Jardín, detalle y visor de capas en
   claro y oscuro (`xcrun simctl ui <udid> appearance light|dark`) y con
   `xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`, sin textos cortados ni solapes.
7. **Tokens**: un test compara los hex de `Solar` con las tablas de §1.1 y §1.4 y comprueba R = G = B en los tokens del
   pocillo.
8. **Rendimiento**: desplazamiento de las 348 tarjetas y del Feed con 200 publicaciones sin materiales dentro de
   celdas; medir en el iPhone 13 mini del usuario cuando haya build.
9. **Idioma**: toda cadena visible en español salvo los nombres de color de Ridgway del diccionario y la marca.

---

## 8. Apéndice: verificaciones ejecutadas

Todo lo siguiente se ejecutó el 2026-09-15 en la máquina del proyecto; los ficheros temporales viven en el
scratchpad de la sesión (fuera del repo).

| Qué | Cómo | Resultado |
|---|---|---|
| Configuración Tailwind de las 4 `code.html` | Comparación del bloque `tailwind-config` en Python | Idéntica en las cuatro («same config») |
| Radios usados | Recuento de clases `rounded*` | `rounded-full` 31–60, `rounded-xl` 7–12, `rounded-lg` 5–10, `rounded` 0–4 por pantalla |
| Sombras usadas | Recuento de `shadow-[…]` | La más frecuente, `0_4px_16px_-2px_rgba(68,48,28,0.06),0_1px_3px_rgba(68,48,28,0.04)` (8 usos) |
| Cursivas | `grep -c -i italic` | 0 en las cuatro |
| Ficheros de fuente oficiales | API de GitHub `repos/google/fonts/contents/ofl/{literata,plusjakartasans}` + `curl` | Nombres, tamaños y sha256 de §2.1; `OFL.txt` descargados (SIL OFL 1.1) |
| Ejes, instancias y métricas | `uvx --from fonttools` sobre los TTF | Literata: `opsz` 7–12–72, `wght` 200–400–900, 8 instancias, UPM 1000, hhea 1177/−308/0, `tnum`, glifos ñáéíóúü¿¡ºÑ·; Plus Jakarta Sans: `wght` 200–400–800, 7 instancias, hhea 1038/−222/0, `tnum`, mismos glifos |
| Resolución de peso y `opsz` | Programa CoreText en macOS | Familia + rasgo de peso → eje `wght` 500/600/700; `opsz` 36 a 36 pt |
| Altura natural por rol | Programa CoreText (ascent + descent + leading) | Tabla de §2.2 |
| Fuentes en iOS | Simulador propio «DS-Design-Fonts» (iPhone 17, iOS 27.0), binario con destino iOS 17 ejecutado con `xcrun simctl spawn` | Registro OK; `UIFont.fontNames(forFamilyName: "Literata")` = 8 instancias; tamaños Dynamic Type Large/AX5 de §2.2; tinta de `Font.custom(…).weight(…)` creciente con el peso (§2.3) |
| Contraste WCAG y CIELAB | `uv run --project oracle python` con `oracle.reference.srgb8_to_lab_strict` y `de2000` | 26 pares por tema, 0 fallos; valores L\*/a\*/b\*/C\* de §1.2 y §1.4 |
| SF Symbols | `CoreGlyphs.bundle/…/name_availability.plist` | Todos los de §3.6 disponibles en iOS ≤ 17 (`drop.halffull` y `photo.badge.plus`: iOS 17) |
| Toolchain | `xcodebuild -version`, `xcrun --sdk iphonesimulator --show-sdk-version`, `ios/project.yml` | Xcode 27.0 (27A266a), SDK 27.0, destino iOS 17.0 |
| Código actual citado | Lectura de `ios/ColorsApp/App/*`, `Views/**`, `DB/Records.swift`, `DB/Repositories.swift`, `Subject/SubjectSettings.swift`, `Model/WadaDictionary.swift` | API y nombres de §5 y §6 |
| Datos de nombres | Python sobre `data/wada/*.json` | `names.es.json` 348 `pending`; `names.suggested.json` 348 propuestas (`name_es` 6–25 caracteres, mediana 16); `dictionary.json` 159 colores (nombre máx. 23 caracteres), 348 combinaciones (120/120/108 por tamaño, `collection` nula en todas) |
