# Fidelidad visual al ejemplo del usuario

> Estado: auditoría + especificación para implementar · 2026-09-15.
> Referencia visual **exacta**: `exampleDesign/stitch_solarpunk_palette_studio/` (cuatro pantallas con
> `screen.png` y `code.html`, más `solarpunk_meadow/DESIGN.md`). Se ha leído el HTML completo, no solo las capturas.
> Implementación auditada (sin commitear): `ios/ColorsApp/Design/**`, `ios/ColorsApp/Views/**`,
> `ios/ColorsApp/App/RootTabView.swift` y sus capturas `docs/design/screens/verify-*.png`.
> Motivo: el usuario, al verla en su iPhone: «la ui no es parecida al diseño que te di, faltan las animaciones
> las luces los detalles el logo etc».
> Este documento **manda sobre `DESIGN_SYSTEM.md` en movimiento, luces, marca e iconos** (§0.2). El resto de
> `DESIGN_SYSTEM.md` sigue vigente: tokens, tipografía, pocillo neutro, mapa de funciones y navegación.

Material de apoyo en `docs/design/fidelity/`:

| Fichero | Qué es |
|---|---|
| `compare-feed.jpg`, `compare-extraer.jpg`, `compare-rejilla.jpg`, `compare-jardin.jpg` | Ejemplo (izquierda, página completa) frente a la captura actual en claro (derecha) |
| `ambient-recipes.swift` | Recetas de §1 (reloj ambiental, curvas CSS exactas, motas, tarjeta con halo, barrido, poses). Typecheck Swift 6 con destino iOS 17: exit 0 (§8) |
| `original-characters.swift` + `original-characters.png` | Geometría ejecutada de los cuatro personajes, el logotipo y el sol de §2 (reposo, pico, parpadeo y tamaño real) |

## Índice

0. [Diagnóstico y reglas](#0-diagnóstico-y-reglas)
1. [Catálogo de movimiento (M) y luz (L)](#1-catálogo-de-movimiento-m-y-luz-l)
2. [Marca, personajes e iconos originales](#2-marca-personajes-e-iconos-originales)
3. [Feed](#3-feed)
4. [Extraer](#4-extraer)
5. [Rejilla](#5-rejilla)
6. [Jardín](#6-jardín)
7. [Lo que falta, priorizado por pantalla](#7-lo-que-falta-priorizado-por-pantalla)
8. [Verificaciones ejecutadas y criterios de aceptación](#8-verificaciones-ejecutadas-y-criterios-de-aceptación)

Leyenda de estado: **hecho** (igual o equivalente al ejemplo), **parcial** (existe pero le faltan valores del
ejemplo), **falta** (no existe), **omitido** (función inventada o propiedad intelectual: se sustituye por la función
real indicada y el sustituto está hecho).

---

## 0. Diagnóstico y reglas

### 0.1 Por qué no se parece (medido)

1. `DESIGN_SYSTEM.md` §3.5, §3.6 y §5.0 **eliminaron a propósito** partículas, anillos giratorios, sol con cara,
   barrido del botón, criaturas animadas, logotipo ilustrado, halos y avatar. La implementación lo cumplió al pie de
   la letra: en `ios/ColorsApp/{Design,Views,App}` hay **0** `TimelineView`, **0** `keyframeAnimator`, **0**
   `phaseAnimator`, **0** `symbolEffect`, **0** `repeatForever`, **0** `scenePhase` (§8.1). El ejemplo tiene 17
   `animate-ping`, 9 `animate-pulse`, 8 giros, 1 barrido, 9 `@keyframes` propios y 85 sombras de halo `shadow-[0_0_…]`.
2. Las luces de color del marco se cambiaron por sombras sepia o negras. Junto al borde de la tarjeta del día, el
   índice de calidez R−B vale **26** en el ejemplo (halo ámbar) y **11,4** en la app, igual que el fondo (11,6) (§8.1).
3. La marca es un SF Symbol (`sun.max.fill`) en un cuadrado melocotón; el botón de sol es un SF Symbol contextual
   (`camera`); las pestañas son SF Symbols estáticos sobre una cápsula verde.
4. Recuento (§8.2): de 158 elementos del ejemplo, 53 **hecho**, 58 **parcial**, 41 **falta** y 6 **omitido**. Lo que sí está bien (y no hay que rehacer): tokens de color, Literata + Plus Jakarta Sans, radios, pergamino
   esmerilado, filo de luz, pocillos neutros, mapa de funciones reales, estructura de las cuatro pantallas, modo oscuro.

### 0.2 Reglas que sustituyen a `DESIGN_SYSTEM.md`

| Tema | `DESIGN_SYSTEM.md` decía | Regla nueva |
|---|---|---|
| Movimiento (§3.5) | Se eliminan criaturas, partículas, anillos, sol con cara y barrido | Se recuperan todos con los valores de `code.html` (§1), respetando Reducir movimiento, pausa fuera de pantalla y en segundo plano, y ≤ 30 fps |
| Iconos de pestaña (§3.6) | SF Symbols `sun.max`, `drop.halffull`, `square.grid.2x2`, `leaf` | Personajes **originales** animados con los mismos tiempos del ejemplo (§2.3) |
| Marca (§3.6) | `sun.max.fill` en un cuadrado de 32 pt | Logotipo vectorial original (§2.1) |
| Botón de sol (§5.0) | Icono SF contextual | Sol-espíritu animado que **conserva** la acción contextual y su etiqueta (§2.2) |
| Avatar (§5.0) | ✕ | Avatar local (brote) con anillo, halo e insignia «✦» que solo aparece con un hecho real (§2.2) |
| E3 en un botón que comparte tarjeta con un pocillo (§4 n.º 6 y 7) | Prohibido | Permitido si hay ≥ 16 pt entre el borde del pocillo y el borde del botón |
| Alfileres (§1.4 regla 5) | Sin halos ni pulsos | Halo y ping permitidos en el alfiler (aro y cuenta sobre la foto). Se apagan con la máscara visible, mientras se aísla un color y en el alfiler seleccionado. Nunca en las tarjetas de prenda |
| Motas de luz | ✕ | Permitidas sobre la pantalla, pero nunca a menos de 8 pt de un pocillo (exclusión, §1.1) |
| Se mantiene | | Pocillo neutro §1.4 (swatches, tiras, gotas y franjas sin halo, tinte, sombra de color, degradado ni brillo), sin funciones inventadas §0.2 B, propiedad intelectual §0.2 C, contraste AA, textos ≥ 11 pt |

### 0.3 Lectura de `code.html`: hallazgos que condicionan la implementación

1. **Solo** `solar_feed…/code.html` define `@keyframes` (9: `botw-float`, `botw-pulse`, `soot-bounce`, `soot-blink`,
   `dragonfly-flutter`, `wing-vibrate`, `kodama-bob`, `sprout-sway`, `solar-sparkle`). Las otras tres pantallas usan
   clases **sin definir**: `anim-float-1…4`, `anim-spirit-bob`, `anim-dragonfly-wing`, `anim-soot`, `anim-sprout`,
   `spirit-anim`, `firefly`, `botw-glow`. En un navegador no se mueven. Aquí se implementa la intención con los tiempos
   definidos en Feed y se marca «propuesto» (M18–M20).
2. `@keyframes botw-pulse` y `.botw-sheikah-glow` están definidos pero **no se aplican** a ningún elemento. Se
   proponen para la tarjeta del día (M2) y la tarjeta «Se parece a» de Extraer (L2).
3. `animate-[shimmer_2.5s_infinite]` no tiene `@keyframes shimmer`: se implementa la intención (barrido de −100 % a
   +100 %, M13).
4. El CDN de Tailwind es v3: `blur-xs`, `backdrop-blur-xs` y `active:scale-98` no existen (no hacen nada). Se toman 4 pt
   y 0,98.
5. Valores por defecto de Tailwind v3 que usan las cuatro pantallas:
   `animate-ping` = 1 s `cubic-bezier(0,0,0.2,1)`, de 0 a 75 % escala 1→2 y opacidad 1→0, de 75 a 100 % quieto;
   `animate-pulse` = 2 s `cubic-bezier(0.4,0,0.6,1)`, 50 % opacidad 0,5; `animate-spin` = 1 s lineal (3, 6 y 8 s con
   `style="animation-duration"`); `transition` = 150 ms `cubic-bezier(0.4,0,0.2,1)`;
   `shadow-sm` = `0 1px 2px rgba(0,0,0,.05)`; `shadow-md` = `0 4px 6px -1px rgba(0,0,0,.1), 0 2px 4px -2px rgba(0,0,0,.1)`;
   `shadow-lg` = `0 10px 15px -3px rgba(0,0,0,.1), 0 4px 6px -4px rgba(0,0,0,.1)`;
   `shadow-xl` = `0 20px 25px -5px rgba(0,0,0,.1), 0 8px 10px -6px rgba(0,0,0,.1)`;
   `shadow-inner` = `inset 0 2px 4px rgba(0,0,0,.05)`; `blur-sm` 4, `blur-md` 12, `blur-lg` 16, `blur-xl` 24,
   `blur-2xl` 40; `backdrop-blur-md` 12, `-lg` 16, `-xl` 24; `ring-N` = anillo exterior de N px;
   `tracking-tight` −0,025 em, `-wide` 0,025, `-wider` 0,05, `-widest` 0,1.
6. Colores Tailwind usados en las luces: amber-200 `#FDE68A`, amber-300 `#FCD34D`, amber-400 `#FBBF24`, amber-500
   `#F59E0B`, amber-600 `#D97706`, yellow-200 `#FEF08A`, yellow-300 `#FDE047`, yellow-500 `#EAB308` (el
   `rgba(234,179,8,…)` de los halos), teal-300 `#5EEAD4`, teal-400 `#2DD4BF`, teal-500 `#14B8A6`, teal-600 `#0D9488`,
   teal-700 `#0F766E`, emerald-300 `#6EE7B7`, emerald-400 `#34D399`, emerald-600 `#059669`, emerald-700 `#047857`,
   red-400 `#F87171`.
7. En CSS la curva de `animation-timing-function` se aplica **por tramo** entre fotogramas clave (una propiedad que no
   aparece en un fotograma intermedio interpola entre los que sí la tienen). En SwiftUI se reproduce con
   `LinearKeyframe(valor, duration: tramo, timingCurve: .bezier(…))` por tramo.
8. Conversión: 1 px CSS = 1 pt. `box-shadow: 0 0 Bpx c` y `filter: drop-shadow(0 0 Bpx c)` → `.shadow(color: c, radius: B/2)`
   sobre la forma o el dibujo; `filter: blur(Bpx)` → `.blur(radius: B)` o `GraphicsContext.Filter.blur(radius: B)`;
   `bg-surface/85 backdrop-blur-xl` → `.ultraThinMaterial` + `Theme.surface.opacity(0.85)`;
   `ring-2 ring-X/60` → `.overlay(Circle().strokeBorder(X.opacity(0.6), lineWidth: 2).padding(-2))`. La equivalencia de
   radios de sombra es aproximada: se valida con captura A/B (§8.3).
9. Los nombres de estudios, películas, juegos y criaturas aparecen en este documento **solo** como cita literal de
   `code.html`. En `ios/` se usan los identificadores neutros de §1 y §2 (criterio §8.3-1).
10. La proporción de la foto: el ejemplo usa 4:3 apaisado (ilustraciones); la app usa 4:5…4:3 porque las fotos de
    personas son verticales y el usuario pidió «más como Instagram» (4:5). Con 4:5 la paleta de la primera publicación
    queda por debajo del pliegue (se ve en `compare-feed.jpg`); se acepta.

---

## 1. Catálogo de movimiento (M) y luz (L)

### 1.1 Infraestructura común (antes de cualquier animación)

Carpeta nueva `ios/ColorsApp/Design/Motion/` (dueño: sistema de diseño). Receta comprobada en
`docs/design/fidelity/ambient-recipes.swift`.

| Pieza | Qué hace | Detalle |
|---|---|---|
| `AmbientTimeline { t in … }` | Único reloj de todo lo ambiental | `TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused))`. `t == nil` = pose de reposo. `paused` = Reducir movimiento ∨ pestaña oculta ∨ `scenePhase != .active` ∨ fuera de pantalla (`onAppear`/`onDisappear`) ∨ Ahorro de energía ∨ reposo |
| `EnvironmentValues.isTabActive` (`@Entry`) | Pausa las pestañas ocultas | `RootTabContainer` mantiene vivas las pestañas abiertas con `opacity(0)` (`App/RootTabView.swift`): no reciben `onDisappear`. Hay que inyectar `.environment(\.isTabActive, selection == tab)` en `content(for:)` |
| `AmbientActivity` (`@Observable`, inyectado en `DesignSystemRootModifier`) | Ahorro de energía y reposo | `ProcessInfo.processInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange`; reposo tras 30 s sin toques, detectado con un `UILongPressGestureRecognizer(minimumPressDuration: 0)` con `cancelsTouchesInView = false` instalado en la ventana; cualquier toque o desplazamiento reanuda |
| `CSSCurve` | Curvas exactas | `UnitCurve.bezier`: `ease` (.25,.1,.25,1), `easeOut` (0,0,.58,1), `easeInOut` (.42,0,.58,1), `tailwindPing` (0,0,.2,1), `tailwindPulse` (.4,0,.6,1), `tailwindTransition` (.4,0,.2,1) |
| `KeyframeTimeline` (iOS 17) + `value(time:)` | Poses de personajes y tarjetas | Una `KeyframeTrack` por propiedad, muestreada con el `t` del reloj. No se usa `keyframeAnimator(repeating:)` para lo continuo porque no limita los fps. En Swift 6 el contenedor de las líneas de tiempo va `@MainActor` (`KeyframeTimeline` no es `Sendable`) |
| `keyframeAnimator(initialValue:trigger:)` y `phaseAnimator(_:trigger:)` (iOS 17) | Animaciones de un solo disparo | Sí para lo que responde a un toque y termina: destello del sol al tocarlo (escala 1 → 1,15 → 1 y sombra r 3 → 7 → 3 en 450 ms antes de navegar), barajar fichas (M16), aleteo de 12° de «Guardar», respiración de 2 ciclos tras «Otra». Con Reducir movimiento no se disparan |
| `AmbientExclusions` + `.ambientExclusion()` | Protege el pocillo | `SwatchWell`, las franjas de `ComboGridCard`, `GarmentCard` y los pocillos de `HarvestRow` publican su marco (`onGeometryChange` en el espacio de coordenadas `"ambient"`) en un almacén `@Observable` que lee el `Canvas` al dibujar (sin invalidar cuerpos). Mota u orbe cuyo rectángulo toque el pocillo ampliado 8 pt: no se dibuja |
| `AmbientPolicy` + DEBUG `-uiAmbient on/off/reduce` y `-uiAmbientTime <s>` | Capturas reproducibles | `accessibilityReduceMotion` es de solo lectura: la política combina el valor del sistema con el argumento. `-uiAmbientTime 1.25` congela el reloj en ese instante (mismo fotograma en cada captura) |

**Reducir movimiento**: todo lo decorativo queda en su pose de reposo (motas ocultas; ping = punto quieto al 100 %;
pulso = opacidad 1; giros a 0°; barrido oculto; personajes quietos con los ojos abiertos; halos estáticos al valor de
0 %). Los cambios de estado (toast, seleccionar, barajar) pasan a fundido de 150 ms. **Presupuesto**: ≤ 30 fps para
lo ambiental; 0 fotogramas con el reloj pausado.

**Estado (implementado en `ios/ColorsApp/Design/Motion/`)**: `AmbientTimeline` + `MotionPolicy` (`MotionGate.swift`),
`CSSCurve`/`CSSKeyframes`/`AnimationClock` (`MotionCurves.swift`), zonas neutras con `.neutralZone()` (`Lights.swift`)
y **`AmbientActivity.swift`**: Ahorro de energía (`isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange`) y
reposo tras 30 s sin tocar la pantalla, con el gesto de solo lectura en la ventana descrito arriba; el estado viaja por
`\.ambientActivity` y lo inyecta `ambientActivityRoot()` desde `DesignSystemRootModifier`. Medido en el simulador con
el Feed a la vista y sin tocar: 11–13 % de un núcleo los primeros 30 s y **0,0 % a partir del reposo** (vuelve solo al
primer toque o al volver a primer plano). Fotogramas: motas 20 fps, efectos lentos 15 fps, ping 20 fps, giros 10–30 fps.
Argumentos DEBUG: `-uiAmbientIdle 1`, `-uiAmbientLowPower 1`, `-uiAmbientIdleDelay <s>`.
Salvaguarda: si el gesto no llega a engancharse a ninguna ventana, **nunca** se declara el reposo (si no, el ambiente
quedaría congelado sin forma de despertarlo).

**Pestañas inactivas**: en `code.html` las cuatro criaturas llevan su animación en la clase del elemento, no en el
estado activo, así que las tres inactivas también se mueven (`AmbientTabIcon`, `Design/Motion/TabIconAmbient.swift`).
Desviaciones deliberadas: amplitud al 45 %, reloj a 15 fps, sin anillo de ping ni halo verde (siguen siendo de la
activa) y alas de la libélula quietas (su ciclo de 0,18 s a 15 fps se vería como parpadeo aleatorio, no como
vibración); el parpadeo sí se conserva entero y cada pestaña arranca con un desfase (0 / 0,35 / 0,7 / 1,05 s).

### 1.2 Movimiento

| Id | Fragmento de `code.html` | Valores exactos | SwiftUI | Dónde |
|---|---|---|---|---|
| M1 Mota flotante | `@keyframes botw-float` | 0 %: `translate(0,0)`, opacidad 0 · 20 %: opacidad 0,8 · 80 %: opacidad 0,6 · 100 %: `translate(15px,−120px)`, opacidad 0. `ease-out`, infinito. El desplazamiento usa la curva en todo el ciclo; la opacidad, por tramo. Sin `animation-fill-mode`: durante el retraso la mota se ve quieta → en la app, opacidad 0 durante el retraso | `AmbientMotes` (un `Canvas` en `AmbientTimeline`): posición = base + (15, −120)·easeOut(p); opacidad por tramos easeOut; `drawLayer` con `.shadow(color: glow, radius: glow/2)` y `.blur(radius:)` | Feed (5), visor de Extraer (5, M20) |
| M2 Respiración de tarjeta | `@keyframes botw-pulse` (definido, sin aplicar) | 0/100 %: `box-shadow: 0 0 16px rgba(245,158,11,.25), 0 0 30px rgba(45,90,60,.15)`, `border-color: rgba(234,179,8,.4)` · 50 %: `0 0 24px rgba(45,212,191,.35), 0 0 36px rgba(245,158,11,.3)`, `border-color: rgba(94,234,212,.5)`. Duración propuesta 4 s `ease-in-out` | Dos capas de sombra con opacidades interpoladas: ámbar `#F59E0B` α .25→0 y teal `#2DD4BF` α 0→.35 (radio 8→12); musgo `#2D5A3C` α .15→0 y ámbar α 0→.30 (radio 15→18); borde 1 pt `#EAB308` .4 ↔ `#5EEAD4` .5 | Tarjeta del día (Feed), «Se parece a» (Extraer); tarjeta al azar (Rejilla): 2 ciclos tras «Otra» |
| M3 Bote con estiramiento | `@keyframes soot-bounce`; `.soot-sprite-body { animation: soot-bounce 2.2s infinite ease-in-out }` | 0/100 %: `translateY(0) scale(1,1)` · 30 %: `−3px`, `scale(.95,1.08)` · 50 %: `−5px`, `scale(1.04,.96)` · 70 %: `−1px`, `scale(.98,1.02)`. Origen: centro | `KeyframeTimeline` con tramos 0,66 / 0,44 / 0,44 / 0,66 s y `easeInOut` por tramo; `translateBy` + `scaleBy` sobre el centro del cuerpo | Pestaña Feed; compañero del avatar del Jardín |
| M4 Parpadeo | `@keyframes soot-blink`; `.soot-eye-blink { 3.4s infinite ease-in-out; transform-origin: center }` | 0/92/100 %: `scaleY(1)` · 96 %: `scaleY(.1)` | Pista de ojos: 3,128 s a 1 → 0,136 s a 0,1 → 0,136 s a 1; escala Y de los ojos sobre su línea | Semilla solar; gota de rocío (desfase 1,1 s) |
| M5 Vuelo | `@keyframes dragonfly-flutter`; `.dragonfly-sprite { 2s infinite ease-in-out }` | 0/100 %: `rotate(0) scale(1)` · 25 %: `rotate(−5deg) scale(1.05)` · 75 %: `rotate(6deg) scale(.98)` | Tramos 0,5 / 1,0 / 0,5 s; rotación y escala sobre el centro | Pestaña Extraer |
| M6 Aleteo | `@keyframes wing-vibrate`; `.wing-flap { 0.18s infinite linear; transform-origin: center }` | 0/100 %: opacidad .7, `scaleY(1)` · 50 %: opacidad .3, `scaleY(.55)` | Onda triangular 0,09 + 0,09 s; a 30 fps son 5,4 fotogramas por ciclo (a 60 Hz en el navegador, 10,8): se ve como vibración, que es la intención; escala Y de cada ala sobre su centro | Libélula; yema del icono del CTA de Extraer (`anim-dragonfly-wing`) |
| M7 Cabeceo | `@keyframes kodama-bob`; `.kodama-head { 3.2s infinite ease-in-out; transform-origin: bottom center }` | 0/100 %: `rotate(0) translateY(0)` · 25 %: `−8deg`, `−1.5px` · 60 %: `7deg`, `.5px` · 80 %: `−3deg`, `−.5px` | Tramos 0,80 / 1,12 / 0,64 / 0,64 s; origen abajo al centro del cuerpo | Pestaña Rejilla (solo la gota) |
| M8 Vaivén de brote | `@keyframes sprout-sway`; `.sprout-sway-anim { 2.6s infinite ease-in-out; transform-origin: bottom center }` | 0/100 %: `rotate(0)` · 35 %: `rotate(6deg) translateY(−1px)` · 75 %: `rotate(−5deg) translateY(.5px)` | Tramos 0,91 / 1,04 / 0,65 s; solo tallo, hojas y yema (maceta fija), origen en el borde de la maceta | Pestaña Jardín; icono de «Guardar en el jardín» (`anim-sprout`) |
| M9 Destello solar | `@keyframes solar-sparkle`; `.solar-spirit { 12s infinite linear }` | 0/100 %: `rotate(0) scale(1)`, `drop-shadow(0 0 6px rgba(245,158,11,.6))` · 50 %: `rotate(180deg) scale(1.1)`, `drop-shadow(0 0 14px rgba(245,158,11,.9))`. De 50 a 100 % **vuelve** de 180° a 0° (vaivén, no vuelta completa) | Rotación triangular 0→180→0° y escala 1→1,1→1 lineales; `.shadow(#F59E0B, radius 3→7, α .6→.9)`. Adaptación: giran los rayos y la cara queda derecha (en `code.html` gira todo el SVG y la cara pasa boca abajo a los 6 s) | Sol-espíritu de la cabecera del Feed |
| M10 Giro | `animate-spin` + `style="animation-duration: Ns"`; `animate-[spin_Ns_linear_infinite]` | 0→360°, lineal, infinito. 1 s: estrella de «Surprise Me!» · 3 s: icono del toast del Feed · 6 s: icono del botón del día · 8 s: icono de la lente y estrella de «Solar Divination» · 10 s: aro discontinuo del reloj de sol · 25 s: anillos de la tarjeta del día | `.rotationEffect(.degrees(360 * (t / d).truncatingRemainder(dividingBy: 1)))` dentro de `AmbientTimeline` | Ver pantallas |
| M11 Pulso | `animate-pulse` | 2 s `cubic-bezier(.4,0,.6,1)`; 50 %: opacidad .5 | `opacity(Keyframes.pulse(t))` | Icono del chip activo, icono del día, insignia «✦» del avatar (Feed), mota de la semilla, halo de pestaña activa, orbe cálido de la tarjeta al azar, aro exterior del reloj de sol, punto verde de la tarjeta al azar |
| M12 Ping | `animate-ping` | 1 s `cubic-bezier(0,0,.2,1)`; 0→75 %: `scale(1→2)`, opacidad 1→0; 75–100 %: escala 2, opacidad 0; vuelve a 1. En `code.html` unas veces late el propio punto (aparece y se desvanece) y otras un aro detrás de un punto fijo | `Keyframes.ping(t)` → `scaleEffect` + `opacity`. Variante «aro»: punto fijo + círculo detrás con ping | Punto junto a «ChromaSol», punto teal del día, alfileres, puntos de estado, motas de las pestañas |
| M13 Barrido de luz | `<div class="absolute inset-0 bg-gradient-to-r from-transparent via-white/30 to-transparent -translate-x-full animate-[shimmer_2.5s_infinite]">` | Degradado transparente → blanco 30 % → transparente del ancho del botón, de x = −100 % a +100 %, 2,5 s, curva `ease` (por defecto), infinito | `Shimmer` en el **fondo** del botón, entre la cápsula y el texto (el texto no pierde contraste), recortado a `Capsule()` | «Otra combinación» (Feed). Variante de una pasada al pulsar (1 s `cubic-bezier(.4,0,.2,1)`): «Otra» de la Rejilla (`via-white/20`) y «Guardar en el jardín» de Extraer (`via-secondary-container/20`) |
| M14 Respuesta al pulsar | `hover:scale-105 active:scale-95`, `active:scale-[0.98]`, `active:scale-[0.99]`, `group-active:scale-90`, `group-hover:-translate-y-1`, `group-hover:rotate-12`, `group-hover:scale-110`, `group-hover:-translate-y-0.5`, `hover:shadow-[…]`, `transition-all` (150 ms) y `duration-300/500/700/1000` | Escala al pulsar por elemento (0,95 chips y botones pequeños; 0,98 botón del día; 0,99 CTA de Extraer; 0,90 gotas); hover de sombra = halo más intenso | `ButtonStyle` con escala por elemento y `.animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.15), value: isPressed)`; halo del hover → mientras está pulsado; `rotate-12`/`scale-110` → al tocar, `.symbolEffect(.bounce)` o rotación de 12° con muelle; zoom de foto al pasar → sin equivalente táctil. Reducir movimiento: opacidad .8 al pulsar (hoy `SolarPressStyle` ya lo hace) | Tablas de pantalla |
| M15 Toast | Feed: `opacity-0 → opacity-100`, `-translate-y-2 → translate-y-0`, `duration-300`, 2 200 ms, `top-20`. Extraer: `translate-y-[-8px]`, 2 400 ms, `bottom-20`. Jardín: solo opacidad, 2 200 ms, `bottom-20` | 300 ms `cubic-bezier(.4,0,.2,1)` | `.transition(.opacity.combined(with: .offset(y: -8)))` + `withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.3))` | `SolarToast` |
| M16 Barajar fichas | Rejilla, `generateRandomPalette()` | Cada ficha `scaleY(0.4)`; a los 120 + 60·i ms cambia el color y vuelve a `scaleY(1)`; transición `duration-500`. El icono del reloj de sol gira +360° + aleatorio [0,180)° en 500 ms (`transition-transform duration-500`) | `scaleEffect(x: 1, y: s)` por ficha con `.animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.5).delay(0.12 + 0.06 * i))`; `rotationEffect` acumulado en el sol | Tarjeta al azar |
| M17 Cambio de color de la cinta | Feed, `#hero-c1…c4` con `transition-all duration-500` | 500 ms `cubic-bezier(.4,0,.2,1)` sobre `background-color` | Cada segmento anima su `Color` con `.animation(…, value: comboId)`; la tarjeta **no** se sustituye entera (hoy `.id(id)` + `.transition(.scale(0.98))` en `FeedView.dayCard`) | Tarjeta del día |
| M18 Luciérnaga (propuesto) | Jardín: `firefly` (sin definir) con `animation-delay` 0 / 1,5 / 2,4 s | 4 s `ease-in-out`: desplazamiento (0,0)→(3,−6)→(0,0) pt, opacidad .4→1→.4 | `AmbientTimeline` + `offset` + `opacity` | Tarjeta de perfil del Jardín |
| M19 Flotación suave (propuesto) | Extraer: `anim-spirit-bob` (sin definir) | `translateY` 0 → −1,5 → 0 pt, 3,2 s `ease-in-out` (tiempos de M7 sin rotación) | `offset(y:)` | Sol del botón de cabecera de Extraer; glifos de los alfileres 1 y 4 |
| M20 Motas del visor (propuesto) | Extraer: `anim-float-1…4` (sin definir) | M1 con recorrido (8, −40) pt; duraciones 7 / 8,5 / 6,5 / 9 s; la 5.ª mota comparte `anim-float-2` (8,5 s, retraso 1 s) | `AmbientMotes(preset: .viewfinder)` recortado al visor | Visor de Extraer |

### 1.3 Luz

| Id | Fragmento de `code.html` | SwiftUI | Dónde |
|---|---|---|---|
| L1 Tarjeta con halo | `.botw-glow-card { box-shadow: 0 0 18px rgba(234,179,8,.22), 0 0 28px rgba(45,90,60,.12); border: 1px solid rgba(234,179,8,.25) }`; pulsada `hover:shadow-[0_0_22px_rgba(234,179,8,0.3)]` | Sobre la forma de fondo: `.shadow(color: #EAB308 .22, radius: 9)` + `.shadow(color: #2D5A3C .12, radius: 14)`; `strokeBorder(#EAB308 .25, lineWidth: 1)`. Pulsada: radio 11, α .30. En oscuro, mismos valores (farolillos sobre tierra oscura) | Tarjeta del día y publicaciones del Feed |
| L2 Halo teal y ámbar | `.botw-sheikah-glow { box-shadow: 0 0 14px rgba(45,212,191,.35), 0 0 22px rgba(245,158,11,.25) }` (definido, sin aplicar) | `.shadow(#2DD4BF .35, r 7)` + `.shadow(#F59E0B .25, r 11)` | Propuesto: tarjeta «Se parece a» de Extraer; píldora de la lente en publicaciones de cámara |
| L3 Cabecera | Feed: `bg-surface/85 backdrop-blur-xl shadow-[0_1px_14px_rgba(234,179,8,0.1)] border-b border-amber-500/10`. Resto: `bg-surface/85 backdrop-blur-xl shadow-[0_1px_8px_rgba(0,0,0,0.04)]` | `.ultraThinMaterial` + `surface` .85 + filo inferior 1 px `#F59E0B` .10 + `.shadow(#EAB308 .10, r 7, y 1)` (Feed); resto: sombra negra .04 r 4 y 1 | `AppHeader(style: .feed / .standard)` |
| L4 Barra de pestañas | Feed: `bg-surface/90 backdrop-blur-xl shadow-[0_-3px_16px_rgba(234,179,8,0.12)] border-t border-amber-500/15`. Resto: `shadow-[0_-2px_12px_rgba(68,48,28,0.05)]` | Material + `surface` .90 + filo superior 1 px `#F59E0B` .15 + `.shadow(#EAB308 .12, r 8, y −3)` (Feed); resto: sepia .05 r 6 y −2 | `SolarTabBar(style:)` según pestaña activa |
| L5 Halo de botón ámbar | `shadow-[0_0_18px_rgba(234,179,8,0.4)] border border-amber-300/40`; pulsado `0_0_24px … .6` | `.shadow(#EAB308 .4, r 9)` (pulsado r 12, α .6); `strokeBorder(#FCD34D .4, 1)` | «Otra combinación» |
| L6 Halo de CTA musgo | Extraer: `shadow-[0_4px_16px_rgba(20,66,38,0.35),0_0_20px_rgba(253,147,63,0.3)]`. Rejilla: `shadow-[0_0_14px_rgba(20,66,38,0.4),0_2px_4px_rgba(0,0,0,0.15)]` | Extraer: `.shadow(#144226 .35, r 8, y 4)` + `.shadow(#FD933F .3, r 10)`. Rejilla: `.shadow(#144226 .4, r 7)` + `.shadow(.black .15, r 2, y 2)` | «Guardar en el jardín», «Otra» |
| L7 Halo de chip activo | `shadow-[0_0_12px_rgba(45,90,60,0.3)] border border-emerald-400/30` | `.shadow(#2D5A3C .3, r 6)` + `strokeBorder(#34D399 .3, 1)` | Chip activo del Feed |
| L8 Resplandor de dibujo | `drop-shadow-[0_0_6px_rgba(245,158,11,0.3)]` (logo, Feed) · `…6px rgba(253,147,63,0.8)` (sol de Extraer, brote del CTA) · `…4px rgba(217,119,36,0.6)` (estrella) · `…6px rgba(217,119,36,0.7)` (sol del reloj) · `…8px rgba(253,147,63,0.8)` (sol de la barra del visor) · `…6px rgba(20,66,38,0.5)`, `…8px rgba(20,66,38,0.4)`, `…6px rgba(161,210,172,0.9)`, `…6px rgba(188,239,199,0.8)` (pestañas) · `…4px #fd933f` («✦» del CTA) | `.shadow(color:, radius: B/2)` sobre el `Canvas`/`Image` (sigue el alfa del dibujo) | §2 y pantallas |
| L9 Anillos | `ring-2 ring-amber-300/60` (avatar) · `ring-2 ring-amber-400/40` y `ring-2 ring-teal-400/40` (icono de publicación) · `ring-1 ring-primary/20` (miniatura de cosecha) · `ring-1 ring-white/50` y `ring-1 ring-black/10` (gotas) | `strokeBorder` exterior. En gotas y swatches ✕ (pocillo): se usa `swatchHairline` | Avatar, publicación, cosecha |
| L10 Orbes difusos | `bg-secondary-container/30 blur-2xl` 160 pt con `animate-pulse` · `bg-primary-fixed/40 blur-xl` 144 pt · `bg-secondary-fixed/40 blur-2xl` 144 pt · `bg-primary-fixed/40 blur-xl` 128 pt · `bg-secondary-fixed/30 blur-xl` 96 pt · esquinas de fichas `…/20 blur-md` 40 pt | `SolarWash` (existe) con el color, diámetro y desenfoque del ejemplo; M11 donde se indica; siempre detrás de los pocillos y a ≥ 16 pt de su borde (si no cabe, a la otra esquina) | Rejilla, Jardín |
| L11 Puntos de estado con halo | `w-2 h-2 rounded-full bg-[X] shadow-[0_0_6px_X]` (chips) · `shadow-[0_0_8px_#ffdcc6]` · `shadow-[0_0_6px_#bcefc7]` · `shadow-[0_0_6px_#144226]` | `Circle().fill(X).shadow(color: X, radius: 3…4)`; colores de marca, nunca de datos | Chips, tarjetas |
| L12 Pergamino esmerilado | `bg-surface/85…/95` + `backdrop-blur-md…xl` (cabecera, barra, HUD, etiquetas de alfiler, toast del Feed) | `ParchmentFrost` (hecho) con la opacidad de cada pieza | Todas |
| L13 Filo de luz | `shadow-[inset_0_1px_1px_rgba(255,255,255,0.7)]` | `SunGlint` (hecho) | Avatar (salvo Feed), píldora de armonía, reloj de sol |

---

## 2. Marca, personajes e iconos originales

Dibujo ejecutado: `docs/design/fidelity/original-characters.png` (generado con `original-characters.swift`, misma API
`GraphicsContext` que `Canvas` en iOS). Principio: el mismo encanto, tamaño, paleta y tiempos que el ejemplo, con formas
y rasgos propios. Prohibido: bola negra peluda con púas y ojos blancos enormes; cabeza blanca con ojos huecos negros
sobre un cuerpo de palo; cualquier nombre de criatura, película, estudio o juego en código o textos.

### 2.1 Logotipo «ChromaSol» (`BrandLogo`)

- **Ejemplo**: `<img alt="ChromaSol Logo" class="h-8 w-auto object-contain" src="…">` (imagen remota: ventana en arco
  crema con filo de latón, sol con rayos de hojas y centro dorado, haz de espectro hacia abajo a la derecha, gota
  abajo; dentro lleva un micro-rótulo «ChromaSol» y la propia imagen trae un fondo gris). En Feed añade
  `filter drop-shadow-[0_0_6px_rgba(245,158,11,0.3)]`.
- **Original** (viewbox 28×32, alto 32 pt): arco `M3 31 V14 A11 11 0 0 1 25 14 V29` con esquinas inferiores de radio 2,
  relleno `#FFF8EC`, filo `#C29B38` al 85 % de 1,2. Dentro, recortado al arco: 12 hojas alternas `#2D5A3C`/`#588157`
  (elipses 1×2,5 a 7 unidades del centro (14,15)), disco solar con degradado radial `#F2CC8F`→`#D4A347`→`#954A00` (r 4,3),
  haz de 4 franjas (`#E07A5F`, `#F2CC8F`, `#81B29A`, `#7CA99A` al 90 %) desde (15,5, 17) hacia la esquina inferior derecha
  y gota `#D97724` en (14, 25). Sin texto dentro (la palabra ya va al lado) y sin fondo gris.
- **SwiftUI**: `Canvas` estático de 28×32 dentro de `AppHeader` (sustituye a `BrandMark`, `Design/Components/Chrome.swift:89`);
  Feed: `.shadow(color: #F59E0B .3, radius: 3)`. `accessibilityHidden(true)`.
- **Icono de la app** (P2): el mismo dibujo a 1024 px con `ImageRenderer`. Exige `Assets.xcassets` y
  `ASSETCATALOG_COMPILER_APPICON_NAME` en `ios/project.yml` (hoy no hay catálogo ni icono).

### 2.2 Sol-espíritu de cabecera (`SunSpiritButton`) y avatar local

| Variante | Ejemplo | Original | Movimiento y luz |
|---|---|---|---|
| Feed | `button.w-11.h-11 … hover:scale-105 active:scale-95` + `div.absolute.inset-1.rounded-full.bg-amber-400/20.blur-sm` + `svg.w-7.h-7.solar-spirit` (4 rayos `#F59E0B`, 4 diagonales `#FBBF24`, núcleo r 7 `#F59E0B` y r 5,5 `#FDE047`, ojos r .9 `#713700`, sonrisa .8, mejillas r .8 `#F87171` .6) | Sol genérico dibujado de nuevo: 8 rayos triangulares (largos a 14 `#F59E0B`, cortos a 12,2 `#FBBF24`, base a 9), núcleo r 7 + r 5,5, ojos elipse .8×1, mejillas, sonrisa (viewbox 32) | Botón 44 pt, dibujo 28 pt, halo 36 pt `#FBBF24` .2 desenfoque 4; M9 en los rayos; pulsar 0,95 |
| Extraer | `span.absolute.inset-1.rounded-full.bg-secondary-container/20.animate-ping.opacity-40` + `span.absolute.inset-1.5.rounded-full.bg-secondary-fixed.shadow-[0_0_12px_rgba(253,147,63,0.5)]` + `svg.w-6.h-6.anim-spirit-bob.drop-shadow-[0_0_6px_rgba(253,147,63,0.8)]` (cuerpo r 4,5 `#954A00`, rayos trazo 1,8, ojos `#FFDCC6`) | Disco 32 pt `#FFDCC6` con sol de un tono `#954A00` 24 pt y ojos `#FFDCC6` | Aro 36 pt `#FD933F` .2 × .4 con M12; disco `.shadow(#FD933F .5, r 6)`; sol `.shadow(#FD933F .8, r 3)` y M19 |
| Rejilla, Jardín | `button.w-11.h-11` + `material-symbols sunny` 20 px `text-secondary` | `sun.max` 20 pt `secondary` | Sin movimiento |

**Función** (no se inventa nada): el sol conserva la acción contextual y la etiqueta de VoiceOver de hoy. Feed: «Analizar
una foto» (→ Extraer). Extraer: «Escanear carrete» en captura, «Nueva foto» en resultado. Jardín: «Escanear carrete».
Rejilla: se mantiene la cápsula «20/348» (función real) en lugar del sol. Un glifo SF de 11 pt en la esquina inferior
derecha del sol (`camera`, `photo.stack`, `arrow.counterclockwise`) indica la acción.

**Avatar local** (`LocalAvatar`, `Chrome.swift:106`). Ejemplo Feed: envoltorio
`relative p-0.5 rounded-full bg-secondary-fixed shadow-[0_0_12px_rgba(245,158,11,0.35)]`, imagen
`w-8 h-8 rounded-full ring-2 ring-amber-300/60`, insignia
`absolute -top-0.5 -right-0.5 w-3.5 h-3.5 rounded-full bg-secondary-container text-[8px] text-on-secondary shadow-md animate-pulse` «✦».
Extraer, Rejilla y Jardín: envoltorio con `shadow-[inset_0_1px_1px_rgba(255,255,255,0.7)]`, sin anillo, insignia `shadow-sm`
sin pulso. Original: el brote de hoy en círculo musgo + 2 pt `#FFDCC6` + anillo 2 pt `#FCD34D` .6 + halo `#F59E0B` .35 r 6
(Feed) o `SunGlint` (resto). Insignia 14 pt `#FD933F` con «✦» 8 pt blanco y `shadow-md`, **visible solo si hay
combinaciones desbloqueadas desde la última visita al Jardín** (recuento de `env.unlocks` frente a
`@AppStorage("jardin.lastSeenUnlockCount")`); con M11 en Feed. Tocar → Jardín. Etiqueta: «Tu jardín, 3 combinaciones
nuevas».

### 2.3 Personajes de la barra de pestañas (`SolarCreatureIcon`)

Viewbox 24×24 dibujado a 24 pt dentro de un contenedor de 28 pt (`w-7 h-7`); elemento de pestaña 64×48 pt
(`w-16 h-12 rounded-xl gap-0.5`); barra 64 pt (`h-16 px-gutter`, `justify-around`). Etiqueta `label-sm` (11 pt): activa
`primary` semibold con tracking 0,44; inactiva `onSurfaceVariant` medium.

| Pestaña | Ejemplo (NO copiar) | Personaje original | Geometría (viewbox 24) | Movimiento | Luz y estados |
|---|---|---|---|---|---|
| Feed | Bola negra de púas `#1C1C17`, ojos blancos r 3,2 que parpadean, mota dorada con pulso en (12,18) | **Semilla solar**: bola dorada con 7 pétalos redondeados, brote de una hoja arriba, ojos pequeños con brillo, mejillas y sonrisa | Cuerpo r 6,8 en (12, 12,5), degradado radial `#FEF08A`→`#FBBF24`→`#F59E0B`, filo `#B45309` .6; pétalos elipse 1,5×2,5 a 8,4 unidades (alternos `#F59E0B`/`#FBBF24`, sin el de arriba); tallo `#2D5A3C` .8 y hoja 2,1×1 `#81B29A`; ojos 0,95×1,25 `#3B2F2F` con brillo r .35 blanco; mejillas r .9 `#F87171` .55; sonrisa trazo .7 | M3 (2,2 s) en el cuerpo; M4 (3,4 s) en los ojos; destello de 4 puntas r 1,2 `#FDE68A` con M11 en (19,5, 18,5) | Activa: halo 28 pt `#FBBF24` .2 desenfoque 2 (`bg-amber-400/20 blur-[2px]`). Inactiva: mota 4 pt `secondary` .8 con M12 arriba a la derecha (`absolute -top-1 -right-0.5 w-1 h-1 bg-secondary/80 animate-ping`) |
| Extraer | Libélula de relojería: varilla `#954A00`, bola `#FD933F`, lente teal, alas teal y amarillas | **Libélula cuentagotas**: cabeza de lente, tórax de bulbo ámbar y abdomen de pipeta de cristal con una gota de color | Cabeza r 1,9 en (12, 5,3) `#5EEAD4` filo `#0D9488` .7 + brillo r .5; tórax elipse 2,1×2,6 en (12, 9,6) `#FD933F` filo `#954A00` .8 + reflejo `#FEF08A`; tubo de (11..13, 12) a la punta (12, 20,8) `#FFF7E6` filo `#954A00` .7 con líquido `#FD933F` .9 desde y 15,4; alas delanteras 4,9×1,9 a ±22° `#5EEAD4` .45 filo `#0D9488` .55; traseras 3,9×1,5 a ±8° `#FDE047` .4 filo `#D97706` .55 | M5 (2 s) en todo; M6 (0,18 s) en las alas | Activa (`absolute -top-1 w-8 h-8 rounded-full bg-primary-fixed/40 blur-xs -z-10 animate-pulse` + `drop-shadow-[0_0_6px_rgba(20,66,38,0.5)]`): halo 32 pt `#BCEFC7` .4 desenfoque 4 con M11 + `.shadow(#144226 .5, r 3)`. Tocar: rotación 12° (`group-hover:rotate-12`) |
| Rejilla | Espíritu blanco de cabeza redonda, ojos huecos negros, cuerpo de palo, cabeceo | **Gota de rocío** celadón con carita, posada en una piedra con dos hojas | Gota `M12 3.4 C12 3.4 6.8 9.6 6.8 13.2 C6.8 16.2 9.1 18.6 12 18.6 C14.9 18.6 17.2 16.2 17.2 13.2 C17.2 9.6 12 3.4 12 3.4 Z`, degradado vertical `#E3F6EE`→`#BDECDC`→`#7CA99A`, filo `#2D594C` .8; brillo elipse 0,8×1,8 blanco .8; ojos r .75 `#144136`; mejillas r .7 `#F4A261` .5; sonrisa .6; piedra 5,4×2,2 `#C1C9BF` filo `#717971` .5; hojas 2,3×1 a ±25° `#81B29A` | M7 (3,2 s) solo en la gota, origen (12, 18,6); M4 con desfase 1,1 s | Inactiva (Feed): aura 20 pt `#6EE7B7` .3 desenfoque 3 sobre la cabeza (`absolute -top-1 w-5 h-5 … bg-emerald-300/30 blur-[3px]`). Activa (`absolute inset-1 rounded-xl bg-primary-fixed/30 blur-md animate-pulse` + `drop-shadow-[0_0_6px_rgba(161,210,172,0.9)]`): rectángulo 56×40 radio 12 `#BCEFC7` .3 desenfoque 12 con M11 + `.shadow(#A1D2AC .9, r 3)`; chispa r 1 `#BCEFC7` con M12 en (18, 5) |
| Jardín | Maceta trapezoidal `#C8644A` con ojos de puntos y sonrisa, brote de dos hojas | **Brote en maceta** con ojos cerrados felices, dos hojas y una yema dorada | Maceta trapecio redondeado (7,4..16,6, 14,8 → 21,6) `#C8644A` filo `#713700` .6; borde 11×2,2 radio 1,1 `#E07A5F`; ojos arcos .6 `#FFF7E6`; sonrisa .55; tallo `#2D5A3C` 1,3; hojas `#81B29A` y `#A1D2AC` filo `#144226` .55; yema r 1,1 `#FBBF24` filo `#B45309` .4 | M8 (2,6 s) en tallo, hojas y yema; desplazamiento vertical ≤ 1 pt | Inactiva (Feed): halo 28 pt `#34D399` .2 desenfoque 2; espora 4 pt `#BCEFC7` con halo 2 (Rejilla). Activa (`absolute inset-1 rounded-xl bg-primary-fixed/40` + `drop-shadow-[0_0_8px_rgba(20,66,38,0.4)]`): rectángulo radio 12 `#BCEFC7` .4 + `.shadow(#144226 .4, r 4)`; gota `#FFDCC6` con M12 sobre núcleo `#FD933F` en la yema |

Implementación: un `Canvas` por icono dentro de `AmbientTimeline`; poses con `KeyframeTimeline`; `accessibilityHidden(true)`
(habla la etiqueta); Reducir movimiento: pose de reposo; tamaños de accesibilidad: el dibujo se queda en 24 pt (la
etiqueta ya se oculta hoy). Oscuro: colores de los personajes fijos; halos con `mossBadge`/`amberBadge` oscuros al mismo
alfa. Se sustituye `SolarTabs.standard` (SF Symbols) por `SolarTabItem.creature`.

### 2.4 Glifos pequeños y equivalencias de iconos

- «✦» (U+2726) y «✧» (U+2727) se mantienen como texto decorativo (`accessibilityHidden(true)`), en `secondary`,
  `secondaryFixed` o `primary` según el ejemplo. Dentro de un pocillo, en `wellTextSecondary`.
- Los emojis del ejemplo (U+2728 destellos, U+1F343 hoja al viento, U+1F408+U+200D+U+2B1B, U+1F3EE, U+1F331, U+1F4CC) no se
  usan: se sustituyen por `sparkle` (SF, iOS 14) o por el glifo de estado real.
- Material Symbols → SF Symbols (disponibilidad medida en el simulador iOS 27, §8.1; todos ≤ iOS 17):
  `flare`/`wb_sunny`/`sunny` → `sun.max`; `auto_awesome`/`redeem` → `sparkles`; `magic_button` → `wand.and.stars`;
  `filter_vintage` → `camera.macro` (iOS 15.4); `loupe` → `arrow.up.left.and.arrow.down.right`; `palette` →
  `paintpalette`; `potted_plant` → `leaf`; `content_copy` → `doc.on.doc`; `share` → `square.and.arrow.up`; `tune` →
  `slider.horizontal.3`; `check_circle` → `checkmark.circle`; `handyman` → `wrench.and.screwdriver`; `verified` →
  `checkmark.seal.fill`; `eco`/`local_florist` → `leaf.fill`; `filter_center_focus`/`crop_free` → `viewfinder` (esquinas
  dibujadas).

---

## 3. Feed

Ejemplo: `solar_feed_ghibli_botw_luminous_edition/`. Actual: `verify-feed-light.png`, `verify-feed-dark.png`,
`verify-feed-post-light.png`, `verify-feed-post-dark.png`; código `Views/Feed/FeedView.swift`,
`Views/Feed/FeedComponents.swift`, `Design/Components/{Chrome,Cards,Controls,SwatchWell}.swift`. Comparativa:
`docs/design/fidelity/compare-feed.jpg`. Funciones: `DESIGN_SYSTEM.md` §5.0 y §5.1.

| # | Elemento y fragmento de `code.html` | Valores exactos | SwiftUI | Función en la app | Estado actual |
|---|---|---|---|---|---|
| F1 | Capa de motas `#botw-particles-layer` `pointer-events-none fixed inset-0 z-20 overflow-hidden` | 5 motas sobre el contenido y bajo cabecera y barra (z-50). m1 `w-2 h-2 bg-amber-300/60 blur-[1px] shadow-[0_0_10px_#fde047]` left 12 % bottom 15 %, M1 7 s, sin retraso · m2 `w-2.5 h-2.5 bg-teal-300/50 blur-[1px] shadow-[0_0_12px_#5eead4]` 78 %/25 %, 8,5 s, retraso 1,5 s · m3 `w-1.5 h-1.5 bg-amber-200/70 blur-[0.5px] shadow-[0_0_8px_#fef08a]` 45 %/40 %, 6,5 s, 3 s · m4 `w-2 h-2 bg-emerald-300/40 blur-[1px] shadow-[0_0_10px_#6ee7b7]` 88 %/65 %, 9 s, 2 s · m5 `w-1.5 h-1.5 bg-amber-300/50 shadow-[0_0_6px_#fcd34d]` 28 %/8 %, 7,8 s, 4,2 s | `AmbientMotes(preset: .feed)` como `.overlay` del `ScrollView` aplicado antes de `.safeAreaInset(edge: .top)`; tamaños 8/10/6/8/6 pt; relleno con su alfa, `.shadow` radio 5/6/4/5/3, `.blur` 1/1/0,5/1/0; exclusión de pocillos (§1.1) | Ambiente de marca | **falta** (0 `TimelineView`/`Canvas` ambiental) |
| F2 | Cabecera `header.fixed.top-0 … bg-surface/85 backdrop-blur-xl shadow-[0_1px_14px_rgba(234,179,8,0.1)] border-b border-amber-500/10`; `div.h-16.px-margin` | Alto 64 + área segura; relleno lateral 16; halo ámbar hacia abajo; filo `#F59E0B` .10 | L3 variante `.feed` en `AppHeader` | `AppHeader(section: "Feed")` | **parcial**: material + tinte .78 + filo latón .25 + sombra negra .04 r 4; falta el tinte .85, el filo ámbar y el halo `#EAB308` .10 |
| F3 | Logotipo `img.h-8.w-auto.object-contain.filter.drop-shadow-[0_0_6px_rgba(245,158,11,0.3)]` + `gap-space-sm` | 32 pt de alto, 8 pt hasta la palabra, resplandor ámbar .3 | `BrandLogo` (§2.1) + `.shadow(#F59E0B .3, r 3)` | Marca | **falta**: hoy `BrandMark` = `sun.max.fill` en cuadrado `amberBadge` 32 pt (`Chrome.swift:89`) |
| F4 | «ChromaSol» `font-headline-sm text-headline-sm tracking-tight text-primary leading-none` | Literata 500 18/24, −0,45 pt, `#144226` | `textRole(.brand)` | `AppBrand.name` | **hecho** |
| F5 | Punto `span.w-1.5.h-1.5.rounded-full.bg-amber-400.animate-ping.inline-block` tras «ChromaSol» (`gap-1`) | 6 pt `#FBBF24`, M12 sobre el propio punto, 4 pt a la derecha de la palabra | `Circle` 6 pt con `Keyframes.ping` | Estado real: late mientras `env.scanProgress` analiza el carrete; en reposo, punto quieto | **falta** |
| F6 | Rótulo «Feed» `font-label-sm text-label-sm text-secondary tracking-widest uppercase opacity-80 pt-0.5` | 10 px → 11 pt bold, tracking 1,1, `#954A00`, 2 pt arriba | `textRole(.overline)` sin opacidad (AA) | Sección | **hecho** |
| F7 | Botón de sol `button.w-11.h-11 … hover:scale-105 active:scale-95` + halo `div.absolute.inset-1.rounded-full.bg-amber-400/20.blur-sm` + `svg.w-7.h-7.solar-spirit` | 44 pt; halo 36 pt `#FBBF24` .2 desenfoque 4; sol 28 pt con M9 (12 s) | `SunSpiritButton(.feed)` (§2.2); pulsar 0,95; al tocar, destello de un disparo (`keyframeAnimator(trigger:)`, §1.1) | «Analizar una foto» → Extraer (hoy igual) | **parcial**: acción hecha; dibujo, halo y M9 faltan (hoy `camera` SF en círculo `amberBadge` 34 pt) |
| F8 | Avatar `div.relative.p-0.5.rounded-full.bg-secondary-fixed.shadow-[0_0_12px_rgba(245,158,11,0.35)]` + `img.w-8.h-8.ring-2.ring-amber-300/60` | 32 pt + 2 pt `#FFDCC6`; anillo 2 pt `#FCD34D` .6; halo `#F59E0B` .35 r 6 | `LocalAvatar(style: .glow)` | Abre el Jardín | **parcial**: brote con aro 2 pt `amberBadge`; falta anillo claro y halo |
| F9 | Insignia `span.absolute.-top-0.5.-right-0.5.w-3.5.h-3.5.rounded-full.bg-secondary-container … text-[8px] text-on-secondary shadow-md animate-pulse` «✦» | 14 pt `#FD933F`, «✦» 8 pt blanco, `shadow-md`, M11 | Insignia en `LocalAvatar` | Desbloqueos nuevos desde la última visita al Jardín (§2.2); sin novedades, oculta | **falta** |
| F10 | Toast `#hex-toast` `fixed top-20 left-1/2 … px-space-md py-space-xs rounded-full bg-inverse-surface/95 text-inverse-on-surface shadow-[0_0_20px_rgba(245,158,11,0.4)] backdrop-blur-md border border-amber-400/30` + icono `auto_awesome` 18 px `text-secondary-fixed animate-spin` 3 s + `label-md` | Arriba (80 pt), relleno 12×4, halo `#F59E0B` .4 r 10, filo `#FBBF24` .3, icono girando 3 s; M15 (300 ms, 2 200 ms) | `SolarToast(style: .feedGlow)` en `.overlay(alignment: .top)` con `.padding(.top, 80)`; `sparkles` con M10 3 s | «Copiado #7A9A7B», «Guardado en el Jardín», «Gracias…» | **parcial**: toast abajo, `inverseSurface` con E3; falta posición arriba, halo, filo y giro del icono |
| F11 | Fila de chips `section.w-full.pt-space-xs.pb-space-sm.overflow-x-auto` + `div.flex.gap-space-sm.px-margin` | 4 pt arriba, 8 abajo, 8 entre chips, margen 16 | `FilterChipRow` | Filtros del Feed | **hecho** |
| F12 | Chip activo `button.filter-pill … px-space-md py-1.5 rounded-full bg-primary text-on-primary shadow-[0_0_12px_rgba(45,90,60,0.3)] active:scale-95 border border-emerald-400/30` + `wb_sunny` 16 px `text-amber-300 animate-pulse` + `label-md` | 12×6; halo musgo .3 r 6; filo `#34D399` .3; icono `#FCD34D` con M11; pulsar 0,95 | `FilterChip` seleccionado: L7 + icono `sun.max` con M11 | «Todo» | **parcial**: fondo, texto e icono ámbar hechos; faltan halo, filo, pulso y escala 0,95 (hoy 0,97) |
| F13 | Chip en reposo `bg-surface-container-high text-on-surface-variant hover:bg-surface-variant hover:shadow-[0_0_10px_rgba(129,178,154,0.3)]` + punto `span.w-2.h-2.rounded-full.bg-[#81B29A].shadow-[0_0_6px_#81B29A]` | Punto 8 pt con halo r 3 de su color; al pasar, halo del chip r 5 α .3 | Punto de tono de marca (`Tone.moss/amber/celadon`, no de datos) con L11; al pulsar, halo del tono r 5 α .3 | «2 colores» (musgo), «3 colores» (ámbar), «4 colores» (celadón), «Guardadas» (musgo), «Por votar» (ámbar) | **parcial**: chips hechos; faltan punto con halo y halo al pulsar |
| F14 | Tarjeta del día `section.px-margin.mb-space-lg` > `div.relative.overflow-hidden.rounded-xl.bg-surface-container.p-space-md.botw-glow-card.transition-all.duration-300` | Radio 12, relleno 12, `#F1EEE6`; L1; 20 pt debajo | `DailyPickCard(.day)` con L1 + M2 (4 s) | Combinación del día | **parcial**: tarjeta `container` con E1+ sepia y `SunGlint`; faltan filo ámbar .25, halos y respiración |
| F15 | Anillos `div.absolute.-right-6.-top-6.w-36.h-36.pointer-events-none.opacity-60` > `svg.text-secondary.animate-[spin_25s_linear_infinite]` (`viewBox 0 0 100 100`) | 144 pt, desplazado 24 pt fuera arriba y a la derecha, opacidad .6, giro 25 s. Círculos: r 42 `stroke-dasharray 4 6` trazo 1,5 `#954A00`; r 30 `8 4` trazo 1 `#5EEAD4` α .6; r 22 trazo 1 `#954A00`; marcas `M50 6 L50 18 M50 82 L50 94 M6 50 L18 50 M82 50 L94 50` trazo 2; centro r 3 `#F59E0B` | `SunDialRings` (`Shape`s con `StrokeStyle(dash:)`) en el fondo de la tarjeta con M10 25 s; el pocillo lleva un margen de 8 pt del color de la tarjeta por detrás para que los anillos no lo toquen (zona neutra) | Decoración de la tarjeta | **falta** |
| F16 | Icono `flare` 18 px `text-secondary animate-pulse` + `gap-1.5` | 18 pt `#954A00`, M11 | `sun.max` 16 pt con M11 | Icono del rótulo | **parcial**: `sun.max.fill` 14 pt estático |
| F17 | Rótulo «Solar Pick of the Day» `font-label-sm uppercase tracking-widest text-secondary font-semibold` | 11 pt, tracking 1,1, `#954A00` | `textRole(.overline)` | «COMBINACIÓN DEL DÍA» / «COMBINACIÓN AL AZAR» | **hecho** |
| F18 | Punto `span.w-1.5.h-1.5.rounded-full.bg-teal-400.animate-ping` tras el rótulo | 6 pt `#2DD4BF`, M12 | `Circle` 6 pt con ping | Es la de hoy (se oculta tras «Otra combinación») | **falta** |
| F19 | Insignia «Zenith #104» `px-2 py-0.5 rounded-full bg-surface-container-highest border border-amber-500/20 shadow-sm font-label-sm text-outline` | 8×2; `#E5E2DB`; filo `#F59E0B` .2; `shadow-sm`; texto `outline` (4,27:1 → `onSurfaceVariant`) | `SolarBadge` + filo + `shadow(.black .05, r 1, y 1)` | «Nº 098» | **parcial**: falta filo ámbar y sombra |
| F20 | Cinta `div.h-6.w-full.rounded-lg.overflow-hidden.flex.shadow-inner.ring-1.ring-amber-400/30` > segmentos `flex-1 transition-all duration-500 cursor-pointer hover:brightness-110 active:scale-95` con `onclick="copyHex(…)"` | 24 pt, radio 8; al tocar un segmento, copia su hex y toast | `PaletteRibbon(.strip, 24)` en pocillo (sin anillo ámbar ni sombra: regla); segmento tocable con M14 (0,95) y selección neutra; M17 al barajar | Colores de la combinación | **parcial**: pocillo hecho; falta copiar al tocar un segmento y el cambio de color de 500 ms (hoy la tarjeta entera hace `scale(0.98)` + fundido) |
| F21 | Pie de cinta `div.flex.justify-between.text-[11px].font-label-sm.text-on-surface-variant`: «✦ Harmonic Solar Quintet» · «4 NATURAL DYES» `tracking-wider opacity-75 font-mono` | 11 pt; «✦» delante; derecha con tracking 0,55 | Nombre (`headline-md`) + «✦» + estado «2 COLORES · EN TU REJILLA» `labelSM` tracking 0,55 sin opacidad | Nombre y estado reales | **parcial**: contenido hecho; faltan «✦» y el estilo de la derecha |
| F22 | Botón `button#draw-palette-btn.mt-1.w-full.relative.overflow-hidden.py-2.5.px-space-md.rounded-full.bg-secondary.text-on-secondary.shadow-[0_0_18px_rgba(234,179,8,0.4)] hover:shadow-[0_0_24px_rgba(234,179,8,0.6)] active:scale-[0.98] … gap-2 border border-amber-300/40` | 4 pt arriba, relleno 12×10, `#954A00`, L5, pulsar 0,98 | `SolarPrimaryButton(.amber, glow: .amber)` (se permite E3: hay ≥ 16 pt hasta el pocillo) | «Otra combinación» | **parcial**: cápsula ámbar hecha; faltan halo, filo y escala 0,98 (`elevated: false` en `Cards.swift:171`) |
| F23 | Barrido `div.absolute.inset-0.bg-gradient-to-r.from-transparent.via-white/30.to-transparent.-translate-x-full.animate-[shimmer_2.5s_infinite]` | M13 | `Shimmer` bajo el texto | — | **falta** |
| F24 | Icono `magic_button` 18 px `text-amber-200 animate-spin` `animation-duration: 6s` | 18 pt `#FDE68A`, M10 6 s | `wand.and.stars` 17 pt con M10 | Icono del botón | **parcial**: `dice` estático blanco |
| F25 | Publicación `article.mb-space-xl.flex.flex-col.bg-surface-container-lowest.shadow-sm.botw-glow-card.rounded-xl.overflow-hidden.mx-margin.transition-shadow.duration-300 hover:shadow-[0_0_22px_rgba(234,179,8,0.3)]` | Radio 12; `#FFFFFF`; `shadow-sm` + L1; 32 pt entre publicaciones; margen 16 | `FeedPostCard` con L1 (sin respiración) | Publicación de un análisis | **parcial**: tarjeta, radio, separación y borde sepia .08 hechos; faltan filo ámbar .25 y halos |
| F26 | Cabecera de publicación `div.p-space-md.flex.items-center.justify-between.border-b.border-surface-container/60` | Relleno 12; separador `#F1EEE6` .6 | `FeedPostCard.header` | Origen y fecha | **hecho** |
| F27 | Retrato `div.w-9.h-9.rounded-full.bg-secondary-fixed … shadow-inner overflow-hidden ring-2 ring-amber-400/40` (2.ª publicación: `bg-tertiary-fixed ring-teal-400/40`) | 36 pt; anillo 2 pt `#FBBF24` .4 o `#2DD4BF` .4; sombra interior | Icono de origen en círculo 36 pt con L9: ámbar (carrete, foto elegida) o teal (cámara) | Carrete / Cámara / Foto elegida | **parcial**: círculo `amberBadge` con icono; falta anillo |
| F28 | Título `font-label-lg text-label-lg font-semibold` + destello U+2728 `text-[11px] text-amber-500` (2.ª: U+1F343 `text-teal-500`) | 14 pt 600; glifo 11 pt `#F59E0B` / `#14B8A6` a 4 pt | `sparkle` 11 pt `#F59E0B` (`accessibilityHidden`) | «Foto elegida» | **parcial**: falta el destello |
| F29 | Metadatos `font-body-sm text-body-sm text-outline` «Colmar Outskirts • 10:45 AM Golden Hour» | 12 pt | `bodySM` `onSurfaceVariant` (AA) | «15 sept, 20:42 · Foto completa» (sin lugares ni «hora dorada») | **hecho** |
| F30 | Menú `button.w-8.h-8 … more_horiz` 20 px | 32 pt (44 táctil) | `Menu` `ellipsis` | Abrir en Extraer, Ver combinación, Borrar | **hecho** |
| F31 | Foto `div.relative.w-full.aspect-[4/3].bg-surface-container-low.overflow-hidden.group` + `img … transition-transform duration-700 group-hover:scale-105` | 4:3; zoom 1,05 en 700 ms al pasar | Foto 4:5…4:3 a sangre (§0.3-10); sin zoom (no hay hover) | Foto del análisis | **hecho** (adaptado) |
| F32 | Lente `div.absolute.bottom-3.left-3.flex.items-center.gap-1.5.px-2.5.py-1.rounded-full.bg-surface-container-lowest/90.backdrop-blur-md.shadow-[0_0_12px_rgba(245,158,11,0.3)] border border-amber-300/40` (2.ª: `shadow-[0_0_12px_rgba(45,212,191,0.3)] border-teal-300/40`) + `filter_vintage` 14 px `text-secondary animate-spin` 8 s + `label-sm font-semibold` | A 12 pt de la esquina; relleno 10×4; blanco .9 esmerilado; halo r 6 ámbar .3 (teal en cámara); filo `#FCD34D` .4 (`#5EEAD4` .4); icono M10 8 s | `HUDPill(style: .lens(tone:))` con `ParchmentFrost` blanco .9, halo, filo y `camera.macro` con M10 | Aviso del recorte («Solo ropa», «Foto completa») | **parcial**: píldora esmerilada con `person.crop.rectangle` estático; faltan halo, filo y giro |
| F33 | Lupa `div.absolute.top-3.right-3.w-8.h-8.rounded-full.bg-surface-container-lowest/85.backdrop-blur-md … shadow-md text-primary border border-emerald-400/30` + `loupe` 18 px | 32 pt; blanco .85; `shadow-md`; filo `#34D399` .3 (2.ª: `#2DD4BF` .3) | Botón con `shadow-md` y filo | «Abrir en Extraer» | **parcial**: esmerilado con E3 neutra; falta filo verde y `shadow-md` |
| F34 | Sección de paleta `div.p-space-md.bg-surface-container-low.flex.flex-col.gap-space-sm.border-t.border-surface-container-high/50` | Banda `#F6F3EB` con relleno 12 y filo superior `#EBE8E0` .5 | Banda `containerLow` (marco) con el pocillo blanco dentro (≥ 8 pt) | Paleta de la ropa | **parcial**: pocillo hecho; falta la banda de pergamino alrededor (hoy fondo blanco de la tarjeta) |
| F35 | Rótulo `palette` 16 px `text-emerald-600` + «Extracted Clothing Spectrum» `font-label-sm uppercase tracking-widest text-primary font-bold` | Icono `#059669`; rótulo 11 pt | `paintpalette` + `overline` `primary` | «PALETA DE LA ROPA» / «PALETA DE LA FOTO» | **hecho** |
| F36 | «Copy HEX Strip» `font-label-sm text-secondary hover:underline` + `content_copy` 13 px `group-hover:scale-110` | 11 pt `#954A00`; icono crece 1,1 | Botón `doc.on.doc` + `.symbolEffect(.bounce, value: copiado)` | «Copiar hex» (paleta de la foto) | **parcial**: falta la respuesta del icono |
| F37 | Gotas `div.grid.grid-cols-5.gap-1.5.pt-1` > `div.relative.w-11.h-11.rounded-full.shadow-sm … ring-1 ring-white/50` + punto `w-3.5 h-3.5 bg-white/25`; `group-hover:-translate-y-1 group-hover:shadow-[0_0_14px_<hex>] group-active:scale-90`; nombre `text-[10px] truncate`; hex `text-[9px] text-outline` | 44 pt; 6 pt entre gotas; al pulsar 0,90; al pasar sube 4 pt con halo del color | Pocillo: círculo plano + `swatchHairline` (sin anillo blanco, punto ni halo: regla); pulsar 0,90 con M14; tras copiar, `WellSelectionRing` + subida 2 pt 1 s; nombre 11 pt, hex 12 pt | Copiar el hex de ese color | **parcial**: pocillo hecho; falta pulsar 0,90 y marca de copiado (hoy 0,97) |
| F38 | Variante de 4 fichas `grid-cols-4 gap-2` > `button.p-1.5.rounded-lg.bg-surface-container-lowest.shadow-sm hover:shadow-[0_0_12px_rgba(…,0.4)] active:scale-95` + círculo `w-8 h-8 shadow-inner ring-1 ring-black/10` | 32 pt; ficha radio 8 | Solo con tamaños de accesibilidad (`FeedAccessiblePostCard`) | Paleta en AX | **hecho** |
| F39 | (No existe) Pie «Se parece a» | — | `ComboMatchFooter` | Combinación ganadora | **hecho** (nuevo) |
| F40 | Barra de acciones `div.px-space-md.py-space-sm.flex.justify-between.bg-surface-container-lowest` > `gap-space-md` | Relleno 12×8; 12 entre acciones | `FeedActionBar` | Acciones | **hecho** |
| F41 | Me gusta `favorite` 20 px + «482» `label-md`; `hover:text-error`; al tocar `FILL 1`, `text-error`, +1 y toast «Preserved to Inspiration» | Icono 20; contador | «Sí» `heart` → `heart.fill` `secondary` con `.symbolEffect(.bounce, value: verdict)`; sin contador | «Sí, es eso» (+ «No» `hand.thumbsdown`) | **omitido** (contador); voto **parcial**: falta el rebote del icono |
| F42 | «To Garden» `potted_plant` 20 px `group-hover:rotate-12` + `label-md`; al tocar `text-primary` + toast | Rotación 12° | `leaf`/`leaf.fill` con rotación 12° de muelle + `.symbolEffect(.bounce)` | Guardar en el Jardín | **parcial**: falta la animación del icono |
| F43 | «HEX Bar» `content_copy` 20 px + `label-md` | — | `doc.on.doc` → `checkmark` con `.contentTransition(.symbolEffect(.replace))` | Copiar hex de la combinación | **parcial**: cambia de icono sin transición |
| F44 | Compartir `button.w-8.h-8 … share` 20 px | 32 pt | `square.and.arrow.up` (tarjeta 4:5 o 9:16) | Compartir tarjeta | **hecho** |
| F45 | Barra de pestañas `nav.fixed.bottom-0 … bg-surface/90 backdrop-blur-xl shadow-[0_-3px_16px_rgba(234,179,8,0.12)] border-t border-amber-500/15` > `div.flex.justify-around.h-16.px-gutter` | 64 pt; relleno 12; L4 variante Feed | `SolarTabBar(style: .feed)` | Navegación | **parcial**: pergamino, filo latón .25 y sombra sepia .05; faltan tinte .90, filo y halo ámbar |
| F46 | Elemento de pestaña `a.flex.flex-col.items-center.justify-center.w-16.h-12.rounded-xl.transition-all.gap-0.5` | 64×48 pt, 2 pt icono-etiqueta | Botón de pestaña 64×48 | — | **parcial**: hoy ancho flexible y alto 52 con icono 52×28 |
| F47 | Pestaña Feed activa: `div.relative.w-7.h-7.soot-sprite-body` + halo `div.absolute.inset-0.rounded-full.bg-amber-400/20.blur-[2px]` + `svg.w-6.h-6` (cuerpo, `g.soot-eye-blink`, mota `circle.animate-pulse` r 1,2 `#FBBF24`) + `span.font-label-sm.font-semibold.tracking-wide` | M3 2,2 s, M4 3,4 s, M11; halo 28 pt | Semilla solar (§2.3) | Feed | **falta**: `sun.max.fill` sobre cápsula `mossBadge` .55 |
| F48 | Pestaña Extraer: `div.relative.w-7.h-7.dragonfly-sprite` + `g.wing-flap` (4 elipses) + cuerpo; `span.font-medium` | M5 2 s + M6 0,18 s | Libélula cuentagotas | Extraer | **falta**: `drop.halffull` estático |
| F49 | Pestaña Rejilla: aura `div.absolute.-top-1.w-5.h-5.rounded-full.bg-emerald-300/30.blur-[3px]` + `svg.kodama-head` + mota `circle.animate-ping` r .9 `#81B29A` en (17,5, 4,5) | M7 3,2 s; aura 20 pt; M12 | Gota de rocío | Rejilla | **falta**: `square.grid.2x2` estático |
| F50 | Pestaña Jardín: `div.relative.w-7.h-7.sprout-sway-anim` + halo `div.absolute.inset-0.rounded-full.bg-emerald-400/20.blur-[2px]` | M8 2,6 s; halo 28 pt `#34D399` .2 | Brote en maceta | Jardín | **falta**: `leaf` estático |

---

## 4. Extraer

Ejemplo: `clothing_extractor_ghibli_botw_edition/`. Actual: `verify-extraer-captura-light.png`,
`verify-extraer-resultado-light.png`, `verify-extraer-resultado-dark.png`, `verify-extraer-colores-{light,dark}.png`,
`verify-extraer-match-light.png`, `verify-extraer-acciones-dark.png`; código
`Views/Extract/{ExtractView,ExtractViewfinder,ExtractCaptureContent,ExtractResultContent}.swift`, `Design/Components/{PinOverlay,Cards,Controls}.swift`. Comparativa:
`docs/design/fidelity/compare-extraer.jpg`. Funciones: `DESIGN_SYSTEM.md` §5.2.

| # | Elemento y fragmento de `code.html` | Valores exactos | SwiftUI | Función en la app | Estado actual |
|---|---|---|---|---|---|
| E1 | Cabecera `header … bg-surface/85 backdrop-blur-xl shadow-[0_1px_8px_rgba(0,0,0,0.04)]` (sin filo) | 64 pt; sombra negra .04 r 4 y 1 | L3 `.standard` | `AppHeader(section: "EXTRAER")` | **hecho** (con filo latón .25 extra, de `DESIGN.md`) |
| E2 | Logotipo `img.h-8.w-auto` (sin resplandor) + «ChromaSol» + «Extract» `label-sm text-secondary tracking-widest uppercase opacity-80` | 32 pt | `BrandLogo` | Marca | **falta** el logotipo; palabra y rótulo **hechos** |
| E3 | Sol en disco `button.relative.w-11.h-11 … active:scale-95 group` + `span.absolute.inset-1.rounded-full.bg-secondary-container/20.animate-ping.opacity-40` + `span.absolute.inset-1.5.rounded-full.bg-secondary-fixed.shadow-[0_0_12px_rgba(253,147,63,0.5)]` + `svg.relative.w-6.h-6.anim-spirit-bob.drop-shadow-[0_0_6px_rgba(253,147,63,0.8)]` | Aro 36 pt `#FD933F` .2×.4 con M12; disco 32 pt `#FFDCC6` halo r 6 .5; sol 24 pt `#954A00` (cuerpo r 4,5, rayos 1,8, ojos r .8 `#FFDCC6`, sonrisa .8) con M19 y resplandor r 3 .8 | `SunSpiritButton(.disc)` (§2.2) + glifo de acción 11 pt | «Escanear carrete» (captura) / «Nueva foto» (resultado) | **parcial**: acción y disco `amberBadge` 34 pt hechos; faltan aro con ping, halo, sol dibujado y flotación |
| E4 | Avatar `div.relative.p-0.5.rounded-full.bg-secondary-fixed.shadow-[inset_0_1px_1px_rgba(255,255,255,0.7)]` + `img.w-8.h-8` + insignia `… shadow-sm` «✦» (sin pulso) | 32 + 2 pt; filo de luz; insignia 14 pt estática | `LocalAvatar(style: .glint)` | Abre el Jardín; insignia = desbloqueos nuevos | **parcial**: falta filo de luz e insignia |
| E5 | Visor `div.relative.w-full.px-margin.pt-space-sm.pb-space-xs` > `div#viewfinder.relative.w-full.h-[400px].rounded-xl.overflow-hidden.shadow-md.bg-surface-container-low` | 400 pt, radio 12, `shadow-md`, `#F6F3EB`; 8 pt arriba, 4 abajo | `ExtractViewfinder` con `shadow-md` (`0 4 6 −1` y `0 2 4 −2` negro .1) | Visor del resultado y de la captura | **hecho**; sombra E1 sepia en vez de `shadow-md` (menor) |
| E6 | Foto `img.w-full.h-full.object-cover.object-center` | Recorte a sangre | Foto ajustada sin recorte (los alfileres caen en su sitio) | Foto analizada | **hecho** (adaptado) |
| E7 | Viñeta `div.absolute.inset-0.bg-gradient-to-t.from-on-surface/40.via-transparent.to-on-surface/20` | Abajo `#1C1C17` .4, arriba .2 | Solo en las franjas del HUD (negro .22) | Legibilidad del HUD | **hecho** (adaptado) |
| E8 | Motas del visor `div.absolute.inset-0.pointer-events-none.overflow-hidden`: `top-[18%] left-[22%] w-3 h-3 bg-secondary-fixed shadow-[0_0_14px_rgba(255,220,198,0.95)] blur-[0.5px] anim-float-1` · `top-[35%] right-[16%] w-2.5 h-2.5 bg-tertiary-fixed shadow-[0_0_16px_rgba(189,236,220,0.9)] blur-[0.5px] anim-float-2` · `top-[62%] left-[18%] w-3.5 h-3.5 bg-primary-fixed shadow-[0_0_15px_rgba(188,239,199,0.85)] blur-[0.5px] anim-float-3` · `top-[78%] right-[25%] w-2 h-2 bg-secondary-container shadow-[0_0_12px_rgba(253,147,63,0.9)] blur-[0.5px] anim-float-4` · `top-[48%] left-[36%] w-1.5 h-1.5 bg-surface-container-lowest shadow-[0_0_10px_#ffffff] anim-float-2` | 12/10/14/8/6 pt; `#FFDCC6`/`#BDECDC`/`#BCEFC7`/`#FD933F`/`#FFFFFF`; halos r 7/8/7,5/6/5 | `AmbientMotes(preset: .viewfinder)` recortado al visor, M20 | Ambiente: en captura y mientras analiza, siempre; en resultado, se desvanecen (150 ms) con la máscara visible, al aislar un color o con un alfiler seleccionado | **falta** (hoy dos `SolarWash` estáticos en captura, nada en resultado) |
| E9 | Retículas `div.absolute.top-3.left-3.w-5.h-5.opacity-60` > `filter_center_focus` 18 px `text-surface` y `div.absolute.top-3.right-3` > `crop_free` | 18 pt `#FCF9F1` .6 a 12 pt de las esquinas | Esquinas dibujadas (`Path`, trazo 2, largo 8) en las 4 esquinas, solo en captura (en resultado las tapa el HUD) | Decoración de visor | **falta** (P2) |
| E10 | HUD `div.absolute.top-3.left-0.right-0.px-space-md.flex.justify-between` > píldora `gap-space-xs px-space-sm py-1 rounded-full bg-surface/85 backdrop-blur-md shadow-sm` + `flare` 15 px `text-secondary` + «Aura Reticle Active» `label-sm uppercase tracking-wider` | Relleno 8×4; pergamino .85; `shadow-sm`; 12 pt arriba | `HUDPill` (tocar despliega el texto) | Pasos del recorte («Persona principal de 2 · solo ropa · sin piel») | **hecho** (sin mayúsculas: el texto real es largo) |
| E11 | «Auto-Detect» `button#btn-autodetect … px-space-sm py-1 rounded-full bg-surface/85 hover:bg-surface backdrop-blur-md shadow-sm text-primary active:scale-95` + `auto_awesome` 15 px | 8×4; pulsar 0,95 | `HUDPill(.toggle)` | «Ver máscara» / «Ocultar máscara» | **hecho** |
| E12 | Alfiler, aro de ping: pin 1 `div.absolute.w-9.h-9.rounded-full.border.border-secondary-container/60.animate-ping.opacity-60`; pin 2 `w-8 h-8 bg-secondary-container/30 animate-ping opacity-60`; pin 4 `w-8 h-8 border border-primary-fixed/70 animate-ping opacity-60`; pin 3 (color claro) sin ping: `w-7 h-7 bg-surface-container/60 shadow-[0_0_10px_rgba(232,222,200,0.9)]` | 36/32 pt; trazo 1 `#FD933F` .6 o relleno .3 o trazo `#BCEFC7` .7; opacidad .6; M12 | `PinView`: aro detrás de la cuenta con M12; variante por luminancia del swatch (L\* del motor: `srgbToLab(r:g:b:).L`): claro (L\* > 80) sin ping y con halo estático; oscuro (L\* < 35) aro `#BCEFC7`; resto aro `#FD933F` | Alfiler de cada color | **falta** |
| E13 | Alfiler, halo: pin 1 `div.absolute.w-8.h-8.rounded-full.bg-secondary-fixed/40.backdrop-blur-xs.shadow-[0_0_14px_rgba(253,147,63,0.7)]` | 32 pt `#FFDCC6` .4 con halo r 7 `#FD933F` .7 | Círculo detrás de la cuenta (solo en el primer alfiler o en el de mayor peso) | Resalta el color dominante | **falta** |
| E14 | Alfiler, cuenta `div.relative.w-6.h-6.rounded-full.bg-surface.shadow-[0_0_10px_rgba(196,130,63,0.8)] … p-0.5 transition-transform group-hover:scale-125` > disco del color `w-full h-full rounded-full` | 24 pt; aro 2 pt `#FCF9F1`; halo del **color del swatch** r 5–6 α .8–.9 | `SwatchBead` 24 pt (aro `wellFill`) + `.shadow(color: swatch, radius: 5)` (permitido en alfileres, §0.2) + escala 1,25 al pulsar con M14 | Alfiler | **parcial**: cuenta con aro y sombra neutra hecha; faltan halo del color y escala al pulsar (hoy 1,08 al seleccionar sin animación) |
| E15 | Alfiler, glifo `svg.w-3.h-3.anim-spirit-bob` (círculo discontinuo `2 1` blanco .9 + punto r 1,8 blanco); pin 2 `anim-dragonfly-wing` (círculo continuo .8); pin 4 cara de hoja `#A1D2AC` | 12 pt blanco sobre el color | Glifo 10 pt dentro del disco: aro discontinuo blanco .9 + punto (M19; en color claro `#144226` .4); **no** en el disco si reduce la lectura del color: tamaño ≤ 40 % del disco | Marca de «punto de muestra» | **falta** |
| E16 | Etiqueta `div.absolute.bottom-full.mb-1.5 … whitespace-nowrap.bg-surface/95.backdrop-blur-md.px-2.5.py-0.5.rounded-full.shadow-[0_2px_10px_rgba(0,0,0,0.18)] border border-secondary-fixed/60 flex gap-1.5 group-hover:scale-105` + punto `w-2 h-2 rounded-full shadow-[0_0_6px_<hex>]` + nombre `label-sm font-semibold` + «✦» `text-[9px] text-secondary` | 6 pt sobre la cuenta (arriba si el alfiler está en la mitad superior; abajo si no: pins 3 y 4); relleno 10×2; pergamino .95; sombra negra .18 r 5 y 2; filo `#FFDCC6` .6 (claro: `surface-variant`; oscuro: `primary-fixed-dim`); punto 8 pt con halo del color; «✦»/«✧» | `PinView.label` + filo 1 pt por variante + «✦» 11 pt + halo r 3 en la cuenta de 12 pt | Nombre de Wada más cercano y peso («Green Blue 67 %») | **parcial**: etiqueta esmerilada con cuenta, nombre y peso hecha; faltan filo, «✦», halo del punto y escala al pulsar. La regla de lado es la contraria (hoy arriba si está en la mitad inferior; se mantiene por colisiones) |
| E17 | Barra inferior `div.absolute.bottom-3.inset-x-3.flex.items-center.justify-between.gap-space-sm.p-2.rounded-xl.bg-surface/90.backdrop-blur-lg.shadow-sm` | A 12 pt de los bordes; relleno 8; radio 12; pergamino .90; `shadow-sm` | Barra esmerilada | Personas («Todas») y «Ver capas» | **hecho** (adaptado) |
| E18 | Icono de la barra `div.relative.w-6.h-6` + `span.absolute.inset-0.rounded-full.bg-secondary-fixed-dim/50.animate-ping.opacity-50` + `svg.w-5.h-5.anim-dragonfly-wing.drop-shadow-[0_0_8px_rgba(253,147,63,0.8)]` (cuerpo r 5 `#954A00`, rayos `#FD933F` trazo 2, ojos blancos) | 24 pt; aro `#FFB785` .5×.5 con M12; sol 20 pt con resplandor r 4 | Sol-espíritu mini con M12 **solo mientras `model.reanalyzing`**; en reposo, quieto | Estado de reanálisis de persona | **parcial**: `person.3.fill` estático |
| E19 | «Sun Angle Chromatic Adjust 38° W» + `input#angle-slider` + `tune` | Ajuste de ángulo solar | — | No existe en la app | **omitido** → miniaturas de personas y «Ver capas» (**hecho**) |
| E20 | Título `span.font-headline-sm.text-headline-sm.text-primary` «Extracted Garment Harmony» + `palette` 20 px `text-secondary`; `mt-space-md`, `mb-space-md` | Literata 500 18 pt `#144226` | `textRole(.headlineSM)` + `paintpalette` | «Colores de la ropa» | **hecho** |
| E21 | Píldora de armonía `div.flex.gap-space-xs.px-space-md.py-1.5.rounded-full.bg-surface-container.w-fit.shadow-[inset_0_1px_1px_rgba(255,255,255,0.7)]` + punto `w-2 h-2 bg-secondary-container` + `label-md` + `body-sm text-on-surface-variant opacity-80` «• 98% Botanical Dye Match» | 12×6; filo de luz | `summaryPill` | «2 colores · 12,1 % de la foto» | **hecho** |
| E22 | Tarjetas de prenda `div.grid.grid-cols-2.gap-gutter.mb-space-lg` > `div.swatch-card.group.relative.flex.flex-col.p-space-sm.rounded-xl.bg-surface-container-lowest.shadow-sm hover:shadow-[0_6px_20px_rgba(<color>,0.22)] border border-transparent hover:border-secondary-fixed` | 12 pt entre tarjetas; relleno 8; radio 12; al pasar, sombra del color .22 y filo `#FFDCC6` | `GarmentCard` (la tarjeta es un pocillo: sin sombra ni filo de color); al pulsar, sombra neutra `0 6 20` negro .12 y escala 0,98; seleccionada desde el alfiler, `WellSelectionRing` | Color de la ropa (copiar hex) | **hecho** (pocillo); **parcial** la respuesta al pulsar (hoy 0,97 sin sombra) |
| E23 | Bloque de color `div.w-full.h-16.rounded-lg.mb-space-sm.shadow-[inset_0_1px_2px_rgba(255,255,255,0.6)] … relative overflow-hidden` + `div.absolute.inset-0.bg-gradient-to-tr.from-transparent.via-white/10.to-white/25` | 64 pt, radio 8, brillo interior y degradado blanco | Bloque plano + `swatchHairline` (regla del pocillo) | Color | **hecho** (sin brillo ni degradado: regla) |
| E24 | Insignias sobre el color: «01» `font-mono text-[10px] text-surface px-1.5 py-0.5 rounded-full bg-black/25 backdrop-blur-xs`; `div.bg-surface/90.px-1.5.py-0.5.rounded-full.shadow-sm` con `span.w-1.5.h-1.5.rounded-full.bg-secondary.animate-ping` + `check_circle` 13 px | Número y marca de listo con ping encima del color | Número en la zona de texto («01 · 67 %»); sin insignias ni ping sobre el color (regla) | Posición y peso | **hecho** (adaptado) |
| E25 | Textos: «Outer Vest» `label-sm text-secondary uppercase tracking-wider` + «✦» `text-[11px] text-secondary opacity-60`; nombre `headline-sm group-hover:text-primary`; hex `label-md font-mono text-on-surface-variant`; «Leather» `label-sm text-primary px-1.5 py-0.5 rounded bg-surface-container` | Rótulo 11 pt; «✦» a la derecha; nombre 18 pt; hex 12; etiqueta radio 4 | Rótulo «01 · 67 %» `wellTextSecondary` + «✦» 11 pt `wellTextSecondary` a la derecha (hoy ahí va `doc.on.doc`); nombre de Wada; hex; «ΔE 0,0» radio 4 `wellFillAlt` | Datos reales (la app no reconoce prendas ni tejidos) | **parcial**: falta «✦» (el icono de copiar puede ir junto al hex) |
| E26 | Cinta `div.w-full.flex.h-3.rounded-full.overflow-hidden.shadow-[inset_0_1px_1px_rgba(0,0,0,0.15)].mb-space-lg` | 12 pt, 20 abajo | `PaletteRibbon(.weights, 12)` en pocillo | Pesos | **hecho** |
| E27 | (No existe) «Se parece a», «También se parece a», votos, «Desbloquear» | — | `ExtractTopMatchCard` con L2 (propuesto) y M2 (4 s) en su marco | Top-3 del motor | **hecho** (nuevo); halo **falta** |
| E28 | CTA `button#btn-save-garden.relative.overflow-hidden.w-full.py-3.5.px-space-lg.rounded-full.bg-primary.text-on-primary.font-label-lg … gap-space-sm shadow-[0_4px_16px_rgba(20,66,38,0.35),0_0_20px_rgba(253,147,63,0.3)] hover:bg-primary-container active:scale-[0.99]` | Relleno 20×14; L6; pulsar 0,99 (fondo `#2D5A3C` mientras se pulsa) | `SolarPrimaryButton(.moss, glow: .solar)` | «Guardar en el jardín» / «Guardado en el jardín» | **parcial**: cápsula musgo con E3 (`mossGlow` .16 r 14 y 12 + ámbar .10 r 6 y 4) hecha; faltan halo ámbar r 10 α .3, sombra musgo α .35 y fondo pulsado |
| E29 | Barrido al pasar `div.absolute.inset-0.bg-gradient-to-r.from-transparent.via-secondary-container/20.to-transparent.translate-x-[-100%] group-hover:translate-x-[100%] transition-transform duration-1000` | Una pasada de 1 s | M13 variante al pulsar (`#FD933F` .2) | — | **falta** |
| E30 | Icono `svg.w-5.h-5.text-secondary-fixed.anim-sprout.drop-shadow-[0_0_6px_rgba(253,147,63,0.8)]` (tallo y dos hojas, trazo 2) + `circle.anim-dragonfly-wing` r 2 `#ffdcc6` en (12,6) | 20 pt `#FFDCC6`; M8; yema con M6; resplandor r 3 `#FD933F` .8 | Brote de la pestaña Jardín en línea (trazo `#FFDCC6`) con M8 y yema con M6 | Icono de guardar | **parcial**: `leaf` SF estático |
| E31 | Texto `span.tracking-wide.font-semibold` + «✦» `span.font-mono.text-secondary-fixed.text-xs.drop-shadow-[0_0_4px_#fd933f]` | Tracking 0,35; «✦» 12 pt `#FFDCC6` con resplandor r 2 `#FD933F` | Texto `labelLG` tracking 0,35 + «✦» con `.shadow` | — | **parcial**: falta «✦» y tracking |
| E32 | Secundarios `div.flex.items-center.gap-gutter` > `button.flex-1.py-2.5.px-space-md.rounded-full.bg-surface-container hover:bg-surface-container-high text-primary font-label-md … gap-1.5 shadow-sm active:scale-95` + iconos 17 px `text-secondary` | 12 pt entre ellos; 12×10; `shadow-sm`; pulsar 0,95 | `SolarSecondaryButton` | «Copiar hex» · «Ver capas» | **hecho** (pulsar 0,97 en vez de 0,95: menor) |
| E33 | (No existe) «Compartir tarjeta» y pie técnico | — | `GhostButton`-like + `technicalFooter` | Compartir; versión del motor | **hecho** (nuevo) |
| E34 | Toast `div#toast.fixed.bottom-20 … px-space-md py-2 rounded-full bg-inverse-surface text-inverse-on-surface font-label-sm shadow-lg … duration-300 gap-1.5` + `redeem` 16 px `text-secondary-container` | 80 pt del fondo; `shadow-lg`; M15 (2 400 ms, −8 pt) | `SolarToast` con `sparkles` `#FD933F` | «Guardado en el jardín», «Copiados 2 hex» | **parcial**: falta icono ámbar y desplazamiento de 8 pt |
| E35 | Barra `nav … bg-surface/90 backdrop-blur-xl shadow-[0_-2px_12px_rgba(68,48,28,0.05)]` | Sepia .05 r 6 y −2 | L4 `.standard` | Navegación | **hecho** (tinte .78 en vez de .90: menor) |
| E36 | Pestaña Extraer activa `a[aria-current=page] … text-primary font-label-md relative` + `div.absolute.-top-1.w-8.h-8.rounded-full.bg-primary-fixed/40.blur-xs.-z-10.animate-pulse` + `svg.drop-shadow-[0_0_6px_rgba(20,66,38,0.5)]` (cuerpo `#144226` rx 2,2 ry 6,5, cabeza `#954A00`, alas `#FD933F` .85 y `#A1D2AC` .8 con `anim-dragonfly-wing`, retraso 0,08 s) + `span.font-bold.text-primary` | Halo 32 pt `#BCEFC7` .4 desenfoque 4 con M11, 4 pt por encima del icono; resplandor musgo r 3 .5 | Libélula cuentagotas + halo activo | Extraer | **falta**: `drop.halffull` sobre cápsula |
| E37 | Pestañas inactivas: Feed `svg.anim-soot group-hover:scale-110`; Rejilla `svg.anim-spirit-bob group-hover:scale-110`; Jardín `g.anim-sprout` + `group-hover:scale-110` | Movimiento continuo; al tocar 1,1 | Personajes con su movimiento; al tocar, rebote 1,1 | Feed, Rejilla, Jardín | **falta** |
| E38 | (App) Estado de captura: intro con icono, «Elegir foto», «Cámara», «Escanear carrete», «Qué hace el análisis» | — | Sol-espíritu 64 pt (§2.2 disco) en lugar del círculo con gota; M20 y retículas E9 en el visor; «Elegir foto» con L6 y M13 al pulsar | Captura | **parcial**: estructura hecha (`verify-extraer-captura-light.png`); faltan sol, motas, retículas y luces del CTA |

---

## 5. Rejilla

Ejemplo: `la_rejilla_grid_ghibli_botw_edition/`. Actual: `verify-rejilla-light.png`, `verify-rejilla-dark.png`,
`verify-rejilla-tarjetas-light.png`, `verify-rejilla-detalle-light.png`; código
`Views/Rejilla/{GridView,ComboGridCard,RejillaFilterBar}.swift`, `Design/Components/{Cards,Controls}.swift`. Comparativa: `docs/design/fidelity/compare-rejilla.jpg`.
Funciones: `DESIGN_SYSTEM.md` §5.3.

| # | Elemento y fragmento de `code.html` | Valores exactos | SwiftUI | Función en la app | Estado actual |
|---|---|---|---|---|---|
| R1 | Cabecera `header … shadow-[0_1px_8px_rgba(0,0,0,0.04)]` | Como E1 | L3 `.standard` | `AppHeader(section: "Rejilla")` | **hecho** |
| R2 | Logotipo `img.h-8` + «ChromaSol» + «Rejilla» | 32 pt | `BrandLogo` | Marca | **falta** el logotipo; texto **hecho** |
| R3 | Sol `button.w-11.h-11 … text-primary` + `material-symbols sunny` 20 px `text-secondary` (estático) y avatar con filo de luz | 44 pt; icono 20 pt | Cápsula «20/348» (`Tone.moss`) | Contador de desbloqueadas; tocar filtra | **omitido** → cápsula (**hecho**) |
| R4 | Buscador fijo `div.sticky.top-16.z-30.-mx-margin.px-margin.py-space-sm.bg-surface/90.backdrop-blur-md` > `div.relative.flex.items-center.w-full.bg-surface-container-lowest.rounded-full.shadow-[0_4px_16px_-2px_rgba(68,48,28,0.06),0_1px_3px_rgba(68,48,28,0.04)] px-space-md py-2.5` + `search` 20 px `text-secondary mr-2` + `input … font-body-sm placeholder:text-outline` + `button.p-1 … tune` 18 px | Fijo bajo la cabecera con pergamino .90 esmerilado; campo blanco E1, relleno 12×10 | `SolarSearchField` fijo | «Busca por nombre, número o #hex»; `slider.horizontal.3` = buscar por color | **hecho** (placeholder `onSurfaceVariant` por AA) |
| R5 | Tarjeta al azar `div.relative.overflow-hidden.rounded-xl.bg-surface-container.p-space-md.shadow-[0_4px_16px_-2px_rgba(68,48,28,0.08),0_1px_3px_rgba(68,48,28,0.05)]` | Radio 12; relleno 12; E1+ | `DailyPickCard(.random)` | Combinación al azar | **hecho** (base) |
| R6 | Orbe cálido `div.absolute.-right-8.-top-8.w-40.h-40.rounded-full.bg-secondary-container/30.blur-2xl.pointer-events-none.animate-pulse` | 160 pt `#FD933F` .3, desenfoque 40, 32 pt fuera arriba a la derecha, M11 | `SolarWash` 160/40 `secondaryContainer` .3 con M11 | Decoración | **parcial**: lavado `washWarm` (`#FFDCC6` .4) 150/36 estático |
| R7 | Orbe verde `div.absolute.-left-6.-bottom-6.w-36.h-36.rounded-full.bg-primary-fixed/40.blur-xl` | 144 pt `#BCEFC7` .4, desenfoque 24, 24 pt fuera abajo a la izquierda | `SolarWash(.green)` 144/24 detrás del pie (a ≥ 16 pt del pocillo de fichas) | Decoración | **falta** |
| R8 | Punto `div.absolute.top-3.right-16.w-2.h-2.rounded-full.bg-secondary-fixed.shadow-[0_0_8px_#ffdcc6].animate-ping.opacity-70` | 8 pt `#FFDCC6` halo r 4, opacidad .7, M12; 12 pt arriba, 64 pt a la derecha | `Circle` con L11 + M12 | Decoración | **falta** |
| R9 | Punto `div.absolute.bottom-8.left-20.w-1.5.h-1.5.rounded-full.bg-primary-fixed.shadow-[0_0_6px_#bcefc7].animate-pulse.opacity-80` | 6 pt `#BCEFC7` halo r 3, .8, M11; 32 pt abajo, 80 pt a la izquierda | Idem con M11 | Decoración | **falta** |
| R10 | Estrella `svg.w-4.h-4.text-secondary.animate-[spin_8s_linear_infinite].filter.drop-shadow-[0_0_4px_rgba(217,119,36,0.6)]` (estrella de 8 puntas) + `gap-1.5` | 16 pt `#954A00`, M10 8 s, resplandor r 2 `#D97724` .6 | Estrella de 8 puntas propia (`Shape`) con M10 + L8 | Icono del rótulo | **falta**: `dice` estático |
| R11 | Rótulo «Solar Divination ✦» `font-label-sm uppercase tracking-widest font-bold text-secondary drop-shadow-sm` | 11 pt, tracking 1,1, sombra `drop-shadow-sm` (`0 1px 1px rgba(0,0,0,.05)`) | `overline` + «✦» | «AL AZAR ✦» | **parcial**: falta «✦» |
| R12 | Título `h2.font-headline-sm.text-headline-sm.text-primary.leading-snug.tracking-tight` + `p.font-body-sm.text-on-surface-variant`; bloque `max-w-[70%]` | 18 pt Literata `#144226`; texto 12 pt; 70 % del ancho (el reloj de sol ocupa la derecha) | Título y descripción al 70 % | «Una combinación al azar» + descripción real | **parcial**: textos hechos; ocupan todo el ancho porque no hay reloj de sol |
| R13 | Reloj de sol `div#solar-dial.relative.w-12.h-12.rounded-full.bg-secondary-container/20 … transition-transform duration-700 ease-out shadow-[0_0_16px_rgba(253,147,63,0.35),inset_0_1px_1px_rgba(255,255,255,0.8)] border border-secondary/30` | 48 pt; `#FD933F` .2; halo r 8 .35; filo de luz; filo `#954A00` .3 | `SunDial` (botón 48 pt = «Otra») con L8 y `SunGlint` | Barajar (misma acción que «Otra») | **falta** (hoy la insignia «Nº 255» ocupa esa esquina: pasa al pie) |
| R14 | Sol del reloj `svg#dial-icon.w-7.h-7.text-secondary … stroke-width="2" transition-transform duration-500 drop-shadow-[0_0_6px_rgba(217,119,36,0.7)]` (círculo r 4, 8 rayos, medio arco interior) | 28 pt trazo 2 `#954A00`; resplandor r 3 .7; al barajar gira +360° + [0,180)° en 500 ms | `sun.max` dibujado en trazo con medio arco, `rotationEffect` acumulado (M16) | — | **falta** |
| R15 | Aro discontinuo `div.absolute.inset-0.rounded-full.border-2.border-dashed.border-secondary/50.animate-[spin_10s_linear_infinite]` + aro exterior `div.absolute.-inset-1.rounded-full.border.border-secondary/20.animate-pulse` | Trazo 2 discontinuo `#954A00` .5 con M10 10 s; aro 56 pt trazo 1 .2 con M11 | `Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3]))` + `Circle().stroke` exterior | — | **falta** |
| R16 | Fichas `div#random-swatch-slot.mt-space-md.pt-space-xs.flex.gap-1.5.h-12` > `div.flex-1.h-full.rounded-lg.transition-all.duration-500.shadow-sm.hover:scale-105` | 48 pt; 6 pt entre fichas; radio 8; 16 pt arriba | `PaletteRibbon(.tiles, 48)` en pocillo (sin sombra ni escala: regla) | Colores de la combinación | **hecho** |
| R17 | Barajar `generateRandomPalette()` | M16 (0,4 → 1 escalonado 60 ms, 500 ms) | M16 en las fichas y el sol | «Otra» | **falta**: hoy fundido de la tarjeta entera (`.transition(.opacity)` en `GridView.randomCard`) |
| R18 | Pie `div.mt-space-md.flex.justify-between` > `span.w-2.h-2.rounded-full.bg-secondary.animate-ping` + `span#random-name.font-label-md.text-primary.font-semibold.truncate` (`max-w-[55%]`) | Punto 8 pt `#954A00` M12; nombre 12 pt 600 `#144226` | Punto de estado (M12; `secondary` si está bloqueada, `primary` si está en tu rejilla) + nombre `labelMD` + «Nº 255 · Bloqueada» debajo | Nombre y estado | **parcial**: nombre (`labelLG`) y estado hechos; falta el punto |
| R19 | «Surprise Me!» `button#surprise-btn.relative.inline-flex.items-center.gap-1.5.px-4.py-2.rounded-full.bg-primary.text-on-primary.font-label-md.shadow-[0_0_14px_rgba(20,66,38,0.4),0_2px_4px_rgba(0,0,0,0.15)] active:scale-95 overflow-hidden group` | Relleno 16×8; L6 variante Rejilla; pulsar 0,95 | `SolarPrimaryButton(.moss, .compact, glow: .grid)` | «Otra» | **parcial**: cápsula compacta; faltan halo (`elevated: false`) y escala 0,95 |
| R20 | Barrido `span.absolute.inset-0.bg-gradient-to-r.from-transparent.via-white/20.to-transparent.-translate-x-full.group-hover:translate-x-full.transition-transform.duration-1000` | Una pasada de 1 s | M13 al pulsar (blanco .2) | — | **falta** |
| R21 | Estrella `svg.w-3.5.h-3.5.text-secondary-fixed.animate-spin` (5 puntas) + «Surprise Me!» + «✦» `text-[11px] opacity-80` | 14 pt `#FFDCC6`, M10 **1 s**; «✦» 11 pt | `star.fill` 13 pt con M10 1 s + «✦» (sin opacidad) | Icono del botón | **falta**: `dice` estático, sin «✦» |
| R22 | Chips `div.-mx-margin.px-margin.overflow-x-auto.flex.gap-2.py-1` > activo `button.flex-shrink-0.px-3.5.py-1.5.rounded-full.bg-primary.text-on-primary.font-label-sm.shadow-sm`; reposo `bg-surface-container text-on-surface-variant hover:bg-surface-container-high font-label-sm` | 14×6; `label-sm` (11 pt bold); activo con `shadow-sm`; reposo `#F1EEE6` | `FilterChip(size: .compact)` con `labelSM`, 14×6, `container` en reposo, `shadow-sm` en activo | Todas, 2/3/4 colores, Desbloqueadas, Bloqueadas | **parcial**: chips hechos con `labelMD`, 12×7, `containerHigh` y sin sombra |
| R23 | (No existe) «20 de 348 desbloqueadas» con barra | — | `RejillaProgressRow` | Progreso real | **hecho** (nuevo) |
| R24 | Cuadrícula `div.grid.grid-cols-2.gap-gutter.w-full` | 2 columnas, 12 pt | `LazyVGrid` 2 columnas (1 en AX) | 348 combinaciones | **hecho** |
| R25 | Tarjeta `div.group.relative.flex.flex-col.bg-surface-container-lowest.rounded-xl.overflow-hidden.shadow-[0_4px_16px_-2px_rgba(68,48,28,0.06),0_1px_3px_rgba(68,48,28,0.04)] hover:shadow-[0_8px_24px_-4px_rgba(253,147,63,0.2)] transition-all duration-300` (el tono del halo cambia por tarjeta: `rgba(45,90,60,.2)`, `rgba(217,4,41,.18)`, `rgba(244,162,97,.2)`, `rgba(109,89,122,.2)`, `rgba(221,161,94,.2)`) | Radio 12, blanco, E1; al pasar, sombra `0 8 24 −4` de tono α .2 en 300 ms | `ComboGridCard` con `ButtonStyle`: al pulsar, `.shadow(#FD933F .2, r 10, y 8)` (tono de marca fijo: el del ejemplo sale del color de la paleta, que es dato) y escala 0,98 | Abrir el detalle | **parcial**: tarjeta hecha; sin respuesta al pulsar (`onTapGesture`) |
| R26 | Aura de esquina `div.absolute.-right-4.-top-4.w-16.h-16.rounded-full.bg-secondary-fixed/20.blur-xl.opacity-0.group-hover:opacity-100` (tarjeta 2: `-left-4 -top-4 bg-primary-fixed/25`) | 64 pt, desenfoque 24, aparece al pasar | Aura en la esquina inferior derecha (zona de texto, lejos de las franjas) visible solo al pulsar | Respuesta al pulsar | **falta** (adaptado: arriba tocaría el pocillo) |
| R27 | Franjas `div.flex.h-28.w-full` > `div.flex-1.h-full` | 112 pt a sangre | `PaletteRibbon(.stripes)` en pocillo con relleno 6 | Colores | **hecho** |
| R28 | Título `h3.font-headline-sm.text-[15px].leading-tight.text-on-surface.font-semibold.line-clamp-1` | Literata 600 15 pt, 1 línea | `textRole(.cardTitle)` | Nombre curado o propuesto | **hecho** |
| R29 | Insignia de autor `span.w-4.h-4.rounded-full.bg-secondary-fixed.text-[9px] … font-bold text-on-secondary-fixed shadow-[0_0_4px_rgba(255,183,133,0.6)]` («✦», «❖» o emoji) + autor `font-body-sm text-[11px] text-on-surface-variant` | 16 pt; halo r 2 del tono .6 | `ComboNameKindBadge` + `.shadow(tono, r 2, α .6)` + «Nombre propuesto» | Origen del nombre (curado, propuesto, número) | **parcial**: insignia hecha sin halo; autores **omitido** |
| R30 | Pie `div.flex.justify-between.pt-3.mt-1` > `favorite` 14 px `text-secondary` + «1.2k» `label-sm` · `bookmark_add` 18 px `text-outline hover:text-primary` | — | Estado (`checkmark.seal.fill` «14 sept» o `lock` «Bloqueada»), «Nº 012» y `leaf` guardar con `.symbolEffect(.bounce, value: isSaved)` | Desbloqueo real y guardar | **omitido** (me gusta y cifras) → estado **hecho**; guardar **parcial** (sin animación del icono) |
| R31 | Barra `nav … shadow-[0_-2px_12px_rgba(68,48,28,0.05)]` | Como E35 | L4 `.standard` | Navegación | **hecho** |
| R32 | Pestaña Rejilla activa `a[aria-current=page].relative … text-primary` + `div.absolute.inset-1.rounded-xl.bg-primary-fixed/30.blur-md.pointer-events-none.animate-pulse` + `svg.w-6.h-6.drop-shadow-[0_0_6px_rgba(161,210,172,0.9)]` (cabeza inclinada −8°) + `circle.animate-ping` r 1 `#bcefc7` en (22,5) + `span.font-bold.tracking-wide` | Halo 56×40 radio 12 `#BCEFC7` .3 desenfoque 12 con M11; resplandor r 3 `#A1D2AC` .9; chispa M12 | Gota de rocío + halo activo (§2.3) | Rejilla | **falta**: `square.grid.2x2.fill` sobre cápsula |
| R33 | Pestañas inactivas: Feed `div.group-hover:scale-110` + mota `span.absolute.-top-1.-right-0.5.w-1.h-1.rounded-full.bg-secondary/80.animate-ping`; Extraer `div.group-hover:rotate-12` + `svg.drop-shadow-[0_0_4px_rgba(217,119,36,0.4)]`; Jardín `div.group-hover:-translate-y-0.5` + espora `span.absolute.top-0.right-1.w-1.h-1.rounded-full.bg-primary-fixed.shadow-[0_0_4px_#bcefc7]` | Motas 4 pt; resplandor r 2; al tocar 1,1 / 12° / −2 pt | Personajes con sus motas y respuestas | Feed, Extraer, Jardín | **falta** |


### 5.1 Corrección de fidelidad de la Rejilla (2026-09-16)

Capturas: `docs/design/screens/fix-rejilla-{light,dark,real-sin-datos,detalle-light,reduce-motion,frame0..2}.png`
y la comparativa `fix-rejilla-compare.png` (ejemplo a la izquierda). Simulador «ColorsApp Grid»
(iPhone 18 Pro, 393 pt de ancho ≈ los 390 del ejemplo), `DERIVED=build-ios-grid`.

| Qué faltaba (veredicto) | Qué se ha hecho |
|---|---|
| La cuadrícula se veía gris y apagada con datos reales (0 de 348): la tarjeta bloqueada pintaba el texto sobre `containerLow` desaturado | R25: la bloqueada usa la MISMA tarjeta clara del ejemplo (`card` = `surface-container-lowest`); el bloqueo se marca solo con la píldora «Bloqueada» con candado (`containerHigh`) y el número. El gris vuelve solo con `colorSchemeContrast == .increased` (`ComboGridCard.dimsLocked`) |
| Faltaba el halo de tarjeta (solo aparecía al pulsar) | R25/L1: halo permanente `ComboGridCard.restGlow` = L1 a la mitad (ámbar `#EAB308` 12 % r 18, musgo 7 % r 28, filo ámbar 15 %), porque son 348 tarjetas a la vez. Las luces se dibujan **fuera** del `clipShape` (dentro las recortaba). Al pulsar sigue el `0 8px 24px -4px rgba(253,147,63,0.2)` y el aura melocotón |
| El pocillo blanco con relleno se veía como marco alrededor de las franjas | Con la tarjeta clara, en claro pocillo y tarjeta son el mismo `#FFFFFF`: las franjas leen a sangre como en el ejemplo. **Se mantienen los 6 pt** de relleno neutro (regla §1.4-1 y límite del usuario); medido: anillo blanco exacto alrededor de las franjas |
| Densidad (2,5 tarjetas por pantalla) | Tarjeta de 225 → **195 pt** (ejemplo ≈ 203 pt con sus 112 de franjas): pie de 28 → 24 pt, separaciones del bloque de texto y hueco del botón de guardar. Fila de progreso a `label-sm` y carril de 4 pt; `LazyVStack` de 12 → 8 pt; pie de la tarjeta al azar a `mt-space-md` (12 pt). El resto de la diferencia con el ejemplo es su `screen.png` de página completa (1 217 px) frente a una pantalla de 874 pt con barra de estado |
| El avatar de la cabecera era un glifo de hoja | `RejillaGardenAvatar` dibuja el MISMO personaje del brote en maceta que el Feed, Extraer y el Jardín (`BrandTabIconFrame(kind: .jardin)`), con su anillo ámbar, halo e insignia «✦». Test: `testRejillaHeaderAvatarDrawsTheBrandSprout` compara pixel a pixel |
| Hojas secundarias sin lenguaje solarpunk | La hoja de detalle (`Views/Explorar/ComboDetailView.swift`) estrena el rótulo con estrella de ocho puntas que gira (8 s) con resplandor ámbar, `.glowCard()` en la tarjeta de estado y el toast luminoso |

Zona neutra comprobada en las capturas: pocillo de fichas y franjas de la cuadrícula con **0 px** de
movimiento entre fotogramas y anillo neutro exacto alrededor (`testLockedGridCardStaysLightWithNeutralWell`).

---

## 6. Jardín

Ejemplo: `my_garden_vault_ghibli_botw_edition/`. Actual: `verify-jardin-light.png`, `verify-jardin-dark.png`,
`verify-jardin-cosechas-light.png`, `verify-jardin-estudio-dark.png`; código `Views/Garden/GardenView.swift`,
`Design/Components/Garden.swift`. Comparativa: `docs/design/fidelity/compare-jardin.jpg`. Funciones:
`DESIGN_SYSTEM.md` §5.4.

| # | Elemento y fragmento de `code.html` | Valores exactos | SwiftUI | Función en la app | Estado actual |
|---|---|---|---|---|---|
| G1 | Cabecera `header … shadow-[0_1px_8px_rgba(0,0,0,0.04)]` | Como E1 | L3 `.standard` | `AppHeader(section: "Jardín")` | **hecho** |
| G2 | Logotipo `img.h-8` + «ChromaSol» + «Garden» | 32 pt | `BrandLogo` | Marca | **falta** el logotipo; texto **hecho** |
| G3 | Sol `button.w-11.h-11` + `sunny` 20 px `text-secondary` (estático) + avatar con filo de luz e insignia `shadow-sm` | 44 pt; icono 20 | Sol plano (§2.2) con glifo `photo.stack`; sin avatar (el avatar lleva al propio Jardín) | «Escanear carrete» | **parcial**: acción hecha con `photo.stack` en disco `amberBadge`; falta el sol |
| G4 | Tarjeta de perfil `section.relative.w-full.rounded-xl.bg-surface-container-lowest.p-space-md.shadow-[0_4px_16px_-2px_rgba(68,48,28,0.06),0_1px_3px_rgba(68,48,28,0.04)] overflow-hidden`; `div.space-y-space-lg` entre secciones | Radio 12, relleno 12, E1; 20 pt entre secciones | `StatHeader` | Perfil local | **hecho** |
| G5 | Orbe `div.absolute.-right-8.-top-8.w-36.h-36.rounded-full.bg-secondary-fixed/40.blur-2xl` | 144 pt `#FFDCC6` .4 desenfoque 40, 32 pt fuera | `SolarWash(.warm, 144, 40)` | Decoración | **hecho** (150/40) |
| G6 | Orbe `div.absolute.left-1/3.-bottom-10.w-32.h-32.rounded-full.bg-primary-fixed/40.blur-xl` | 128 pt `#BCEFC7` .4 desenfoque 24; empieza en el tercio izquierdo, 40 pt por debajo | `SolarWash(.green, 128, 24)` en esa posición | Decoración | **parcial**: 130/34 desplazado (−170, 110): queda bajo los contadores de la izquierda |
| G7 | Luciérnagas `div.firefly.absolute.top-3.right-16.w-2.h-2.rounded-full.bg-secondary-container.shadow-[0_0_8px_#fd933f]` · `div.firefly.absolute.bottom-6.left-12.w-1.5.h-1.5.bg-primary-fixed.shadow-[0_0_6px_#bcefc7]` (retraso 1,5 s) · `div.firefly.absolute.top-10.left-2.w-2.h-2.bg-primary-fixed.shadow-[0_0_7px_#a1d2ac]` (retraso 2,4 s) | 8 pt `#FD933F` halo r 4 (12 pt arriba, 64 pt a la derecha) · 6 pt `#BCEFC7` r 3 (24 abajo, 48 izquierda) · 8 pt `#BCEFC7` r 3,5 (40 arriba, 8 izquierda) | Tres `Circle` con L11 y M18 (clase sin definir en `code.html`: propuesto) | Ambiente | **falta** |
| G8 | Anillo del retrato `div.relative.p-1.rounded-full.bg-gradient-to-tr.from-secondary-fixed.via-primary-fixed.to-secondary-container/40.shadow-md … botw-glow` + `img.w-14.h-14.rounded-full` | Retrato 56 pt; anillo 4 pt con degradado hacia arriba a la derecha `#FFDCC6` → `#BCEFC7` → `#FD933F` .4; `shadow-md` (`botw-glow` sin definir → propuesto L1 suave r 8 `#EAB308` .22) | `Circle().fill(LinearGradient(… startPoint: .bottomLeading, endPoint: .topTrailing))` detrás del círculo musgo 56 pt + `shadow-md` + halo | Insignia del jardín (sin retrato: no hay perfiles) | **parcial**: brote en círculo 56 pt con aro sólido `amberBadge` 3 pt; faltan degradado, `shadow-md` y halo |
| G9 | Compañero `span.absolute.-bottom-1.-right-1.w-5.h-5.rounded-full.bg-inverse-surface.border-2.border-surface … shadow-md spirit-anim` con carita de hollín | 20 pt `#31312B`, borde 2 pt `#FCF9F1`, `shadow-md`, 4 pt fuera abajo a la derecha | Semilla solar 14 pt (§2.3) en disco `inverseSurface` 20 pt con borde `surface` y M3 | Decoración (el personaje de la pestaña Feed «vive» en tu jardín) | **falta** |
| G10 | Nombre `h2.font-headline-sm.text-headline-sm.text-primary.tracking-tight.truncate` «Elian Finch» + insignia `span.px-1.5.py-0.5.rounded-full.bg-secondary-fixed/50.text-[10px].font-label-sm.text-secondary` con `eco` 13 px relleno (nombre de un videojuego) | 18 pt `#144226` tracking −0,45; insignia 11 pt | «Tu jardín» + insignia «Local» con `leaf.fill` (hecho cierto: sin cuenta) | Título del perfil | **parcial**: título hecho; nombre de persona e insignia del juego **omitido**; falta la insignia «Local» (P2) |
| G11 | Subtítulo `p.font-label-md.text-label-md.text-secondary.tracking-wide` «Solar Colorist • Botanical Vault» | 12 pt 600 `#954A00` tracking 0,3 | `labelMD` `secondary` | «Solo en este teléfono · sin cuenta» | **hecho** |
| G12 | Línea de índice `p.font-body-sm.text-on-surface-variant.flex.gap-1.mt-0.5` + `span.w-2.h-2.rounded-full.bg-primary.shadow-[0_0_6px_#144226].animate-ping` + `local_florist` 14 px `text-primary` + «Sol-Index:» + `span.font-semibold.text-primary` «94.8% Natural Dye» | Punto 8 pt `#144226` halo r 3 M12; icono 14 pt; valor 600 `#144226` | Punto con M12 **mientras** haya votos nuevos sin ver (si no, quieto) + `leaf.fill` 13 pt + «Acierto:» + valor semibold `primary` | «Acierto: 75 % (3 de 4 votos)» | **parcial**: texto hecho con `heart.fill`; faltan punto con ping y valor en semibold `primary` |
| G13 | Ajustes `button.w-9.h-9.rounded-full.bg-surface-container … text-primary … shadow-sm active:scale-95` + `filter_vintage` 18 px | 36 pt; `shadow-sm`; pulsar 0,95 | `SolarIconButton` `gearshape` + `shadow-sm` | Ajustes | **hecho** (sin `shadow-sm`: menor) |
| G14 | Contadores `div.grid.grid-cols-3.gap-space-xs.mt-space-md.pt-space-sm.bg-gradient-to-r.from-surface-container-low.via-surface-container.to-surface-container-low.rounded-lg.p-space-sm.border.border-outline-variant/30`; celda central `border-x border-outline-variant/40` | Carril con degradado horizontal, radio 8, relleno 8, filo `#C1C9BF` .3; divisores .4 | Carril de `StatHeader` | Tres contadores reales | **hecho** |
| G15 | Valor `span.font-headline-sm.text-headline-sm.leading-none.font-semibold` (colores `text-primary` / `text-secondary` / `text-primary-container`) + rótulo `span.font-label-sm.text-on-surface-variant.mt-1.flex.gap-0.5` con punto `w-1.5 h-1.5 rounded-full` (`bg-primary` / `bg-secondary-container` / `bg-primary-fixed-dim`) | 18 pt 600; punto 6 pt delante del rótulo | Valor `headlineSM` semibold (`primary`, `secondary`, `primaryContainer`) + punto 6 pt de tono delante del rótulo | «7 Fotos analizadas», «19/348 Desbloqueadas», «3 Sí, es eso» | **parcial**: valores hechos (el 3.º en `tertiary`, no `primaryContainer`); faltan los puntos |
| G16 | Segmentos `div.flex.items-center.p-1.bg-surface-container-high.rounded-full.shadow-inner` > activo `button.flex-1.py-1.5.px-space-xs.rounded-full.bg-primary.text-on-primary.font-label-md.shadow-sm` | Carril `#EBE8E0` relleno 4 con `shadow-inner`; activo 6 pt vertical con `shadow-sm` | `SegmentedPill` + sombra interior (`.overlay` con degradado negro .05 arriba) | Fotos · Guardadas · Colecciones | **hecho** (sin `shadow-inner`: menor) |
| G17 | Cabecera de carpetas `span.font-label-sm.text-on-surface-variant.tracking-widest.uppercase` «Moodboard Folios» + `span.font-label-sm.text-secondary` «3 active collections» | 11 pt tracking 1,1 | `overline` + `labelSM` `secondary` | «COLECCIONES» · «4 colecciones» | **hecho** |
| G18 | «+ New Folder» `button.flex.gap-1.5.px-3.py-2.rounded-full.bg-surface-container-high.text-primary.shadow-sm` + `create_new_folder` 16 px | 12×8 | — | Carpetas propias no existen | **omitido** |
| G19 | Carpeta `div.flex.items-center.gap-2.px-3.py-2.rounded-full.bg-surface-container-lowest.text-on-surface.shadow-[0_2px_8px_-1px_rgba(68,48,28,0.06)]` + punto `w-2.5 h-2.5` + `label-md` + contador `label-sm px-1.5 py-0.5 rounded-full bg-surface-container` | 12×8; E2; punto 10 pt | `CollectionPill` | «Guardadas 4», «2 colores 6/120»… | **hecho** |
| G20 | Cabecera de cosechas `palette` 18 px `text-primary` + `h3.font-headline-sm.text-primary.tracking-tight` «Extracted Harvests» + `span.font-label-sm.text-on-surface-variant` «Sorted by Recency» | Icono 18; título 18 pt | `SectionHeader` | «Cosechas · Más recientes» | **hecho** |
| G21 | Cosecha 1 `article.w-full.rounded-xl.bg-surface-container-lowest.p-space-md.shadow-[0_4px_18px_-2px_rgba(68,48,28,0.07)] flex flex-col space-y-space-sm relative overflow-hidden` | Radio 12, relleno 12, sombra `0 4 18 −2` sepia .07, 8 pt entre bloques | `HarvestRow(.droplets)` | Análisis más reciente | **hecho** |
| G22 | Rayo de sol `div.absolute.-right-6.-bottom-6.w-24.h-24.rounded-full.bg-secondary-fixed/30.blur-xl` | 96 pt `#FFDCC6` .3 desenfoque 24, 24 pt fuera abajo a la derecha | `SolarWash` 96/24 arriba a la derecha (detrás de la insignia de veredicto): abajo tocaría el pocillo de gotas | Decoración | **falta** (adaptado) |
| G23 | Miniatura `img.w-12.h-12.rounded-lg.object-cover.shadow-sm.ring-1.ring-primary/20` + insignia `span.absolute.-top-1.-left-1.w-3.5.h-3.5.rounded-full.bg-secondary-container … text-[7px] text-on-secondary shadow-sm` «✦» | 48 pt radio 8; anillo 1 pt `#144226` .2; insignia 14 pt `#FD933F` con «✦» 7 pt | Miniatura + L9 + insignia «✦» en la cosecha más reciente (es un hecho: «la última») | Foto del análisis | **parcial**: miniatura hecha; faltan anillo, `shadow-sm` e insignia |
| G24 | Título `h4.font-headline-sm.text-on-surface.leading-tight` + metadatos `span.font-body-sm.text-on-surface-variant` con tramo `span.text-secondary.font-medium` «Natural Daylight» | 18 pt; 12 pt; tramo en `#954A00` 500 | Nombre de la combinación + «hoy, 21:07 · **Carrete**» (el origen en `secondary` medium) | Nombre, fecha y origen | **parcial**: falta el tramo en `secondary` |
| G25 | «Synced» `span.inline-flex.gap-1.px-2.5.py-0.5.rounded-full.bg-primary-fixed.text-on-primary-fixed.font-label-sm.shadow-[0_0_8px_rgba(188,239,199,0.5)]` + `verified` 13 px | 10×2; `#BCEFC7`; halo r 4 `#BCEFC7` .5 | `VerdictBadge` con halo del tono (r 4, α .5) | Veredicto «Sí, es eso» / «No» / «Sin votar» | **omitido** («Synced»: no hay sincronización) → veredicto **parcial** (sin halo) |
| G26 | Gotas `div.pt-1.flex.justify-between.gap-1.5` > `div.w-full.aspect-square.rounded-full.shadow-sm.transition-all.duration-300.active:scale-95.group-hover:scale-105.group-hover:shadow-[0_0_10px_<hex>]`; dominante con `ring-2 ring-secondary/30`; hex `font-label-sm` (dominante `text-secondary font-semibold`) | Círculos que llenan el ancho; 6 pt entre ellos; pulsar 0,95 | Pocillo con círculos planos 48 pt; dominante con `WellSelectionRing` y hex en `wellText` semibold; pulsar 0,95 | Paleta de la cosecha | **parcial**: pocillo hecho; faltan marca del dominante y respuesta al pulsar |
| G27 | Hoja de especificación `div#hex-sheet-1.p-space-sm.bg-surface-container-low.rounded-lg.flex.justify-between.border.border-primary-fixed/20.shadow-sm` + `flare` 16 px `text-secondary` + `label-md` «Dominant: Flax Bark (#C39B6A)» + «Copy» `label-sm text-primary` con `content_copy` 13 px; al tocar una gota, fondo `bg-secondary-fixed/50` 400 ms | Relleno 8, radio 8, filo `#BCEFC7` .2 | Fila «Dominante» dentro del pocillo (texto `wellText`); destello neutro `wellFillAlt` 400 ms al tocar una gota; icono `doc.on.doc` con `.contentTransition(.symbolEffect(.replace))` | «Dominante: Black (#16171D) · 33 %» + «Copiar» | **parcial**: fila hecha; faltan destello y transición del icono (el `flare` ámbar no entra en el pocillo) |
| G28 | Cosecha 2: menú `button.w-8.h-8.rounded-full.bg-surface-container … more_vert` 16 px; tira `div.w-full.h-8.rounded-lg.overflow-hidden.flex.shadow-inner`; etiquetas `span.px-2.py-0.5.rounded-full.bg-surface-container.text-primary.font-label-sm` y `bg-secondary-fixed text-on-secondary-fixed-variant`; botón `bg-primary-container text-on-primary … data_object` «:root CSS» | Tira 32 pt radio 8; etiquetas 8×2 | `HarvestRow(.proportion)`: `leaf` guardar + menú contextual; barra de pesos 16 pt en pocillo; etiquetas «Nº 012» y «Ambigua» | Resto de cosechas | **hecho**; «:root CSS» **omitido** (no hay exportación CSS) |
| G29 | Cosecha 3: `star` 20 px relleno `text-secondary`; «Garment Distribution» + «48% Khaki • …» `text-[11px]`; barra `div.w-full.h-4.rounded-full.overflow-hidden.flex.shadow-inner` con anchos 48/26/14/12 %; micro-píldoras `div.flex.gap-1.px-2.py-1.rounded-full.bg-surface-container` + punto `w-2 h-2` + `label-sm` | Barra 16 pt; píldoras 8×4 | Guardada `leaf.fill` (+ `.symbolEffect(.bounce)`); «70 % · 30 %» + barra en pocillo; `MicroColorPill` | Proporción real | **hecho**; animación del icono **falta** |
| G30 | Estudio `section.w-full.rounded-xl.bg-surface-container.p-space-md.shadow-sm.space-y-space-sm` + `handyman` 18 px `text-secondary` + `h3.font-headline-sm.text-primary` + «Vault Tools» `label-sm text-secondary tracking-widest uppercase` | Radio 12, `#F1EEE6`, `shadow-sm` | Tarjeta del estudio | «Estudio de exportación · HERRAMIENTAS» | **hecho** |
| G31 | Ficha `button.relative.overflow-hidden.flex.flex-col.p-space-sm.rounded-lg.bg-surface-container-lowest.hover:bg-surface-bright … shadow-[0_2px_8px_rgba(68,48,28,0.06)] active:scale-98 group border border-outline-variant/30 hover:border-primary/40` (tono del filo al pasar por ficha: `primary`, `secondary`, `tertiary`, `secondary-container`) | Radio 8, relleno 8, E2, filo `#C1C9BF` .3; al pasar, filo del tono .4 | `ExportTile` + al pulsar filo del tono .4 y escala 0,98 | Compartir tarjeta, Copiar hex, Exportar diagnóstico, Escanear carrete | **parcial**: ficha y escala 0,97 al pulsar hechas; falta el filo del tono al pulsar |
| G32 | Orbe de esquina `div.absolute.-right-2.-top-2.w-10.h-10.rounded-full.bg-{primary,secondary,tertiary}-fixed/20` (4.ª `bg-secondary-container/20`) `blur-md … group-hover:…/40` | 40 pt, desenfoque 12, 8 pt fuera; al pasar .4 | `SolarWash` 40/12 del tono; al pulsar .4 | Decoración | **falta** |
| G33 | Disco de icono `div.w-8.h-8.rounded-full.bg-primary-fixed … mb-2 shadow-[0_0_10px_rgba(188,239,199,0.6)] group-hover:scale-105` (`rgba(255,220,198,.6)`, `rgba(189,236,220,.6)`, `bg-secondary-container/30 shadow-[0_0_10px_rgba(253,147,63,0.5)]`) + icono 18 px | 32 pt; halo r 5 del tono .6; al pasar 1,05; 8 pt debajo | Disco `tone.badgeFill` + `.shadow(tono fijo, r 5, α .6)`; al pulsar 1,05 | Icono de la herramienta | **parcial**: disco hecho sin halo |
| G34 | Toast `div#toast.fixed.bottom-20 … px-4 py-2 rounded-full bg-primary text-on-primary font-label-md shadow-xl … gap-2` + `auto_awesome` 16 px `text-primary-fixed` | 80 pt del fondo; `#144226`; `shadow-xl`; M15 (solo opacidad, 2 200 ms) | `SolarToast(style: .moss)` con `sparkles` `#BCEFC7` | «Copiados 5 hex», «Guardado» | **parcial**: toast `inverseSurface` |
| G35 | Barra `nav … shadow-[0_-2px_12px_rgba(68,48,28,0.05)]`; elementos `a … active:scale-95` | Pulsar 0,95 | L4 `.standard`; pulsar 0,95 | Navegación | **parcial**: sin escala al pulsar (`.buttonStyle(.plain)`) |
| G36 | Pestaña Jardín activa `a[aria-current=page].relative … text-primary font-label-md` + `div.absolute.inset-1.rounded-xl.bg-primary-fixed/40.botw-glow.-z-10` + `svg.w-5.h-5.drop-shadow-[0_0_8px_rgba(20,66,38,0.4)]` (maceta `#FD933F`, borde `#954A00`, cara blanca, hojas `#144226`/`#2D5A3C`, gota `circle.animate-ping` r 1,2 `#FFDCC6` sobre `#FD933F`) + `span.font-semibold.text-primary` | Rectángulo 56×40 radio 12 `#BCEFC7` .4; resplandor r 4; gota M12 | Brote en maceta + halo activo (§2.3) | Jardín | **falta**: `leaf.fill` sobre cápsula |
| G37 | Pestañas inactivas: Feed `div.spirit-anim.group-hover:scale-110` (bola con 8 bolitas y ojos) + `svg.drop-shadow-sm`; Extraer `div.group-hover:rotate-12` (libélula `#954A00`, alas `#FFDCC6` .85 y `#BCEFC7` .75); Rejilla `div.spirit-anim` con `animation-delay: 0.8s` + `drop-shadow-[0_0_6px_rgba(188,239,199,0.8)]` | Movimiento continuo desfasado 0,8 s | Personajes con desfase de fase por pestaña (Feed 0, Extraer 0,4 s, Rejilla 0,8 s, Jardín 1,2 s) para que no se muevan al unísono | Feed, Extraer, Rejilla | **falta** |

---

## 7. Lo que falta, priorizado por pantalla

P0 = sin esto el usuario seguirá diciendo que «no se parece» (animaciones, luces, logotipo, personajes). P1 = detalles
visibles del ejemplo. P2 = pulido. Entre paréntesis, las filas de §3–§6. Dueños: **DS** = sistema de diseño
(`Design/**`), **Feed** = `Views/Feed/**` y `App/RootTabView.swift`, **Extraer** = `Views/Extract/**`, **Rejilla** =
`Views/Rejilla/**`, **Jardín** = `Views/Garden/**`.

### 7.0 Transversal (bloquea al resto)

| Prioridad | Qué | Filas | Dueño | Hecho cuando |
|---|---|---|---|---|
| P0-1 | Infraestructura de §1.1: `AmbientTimeline`, `isTabActive` inyectado en `RootTabContainer.content(for:)`, `AmbientActivity` (Ahorro de energía y reposo 30 s), `CSSCurve`, `Keyframes` (M3–M12 con `KeyframeTimeline`), `AmbientExclusions` en los pocillos y argumentos DEBUG `-uiAmbient`/`-uiAmbientTime` | §1.1 | DS + Feed (raíz) | Criterios §8.3-2 a §8.3-5 |
| P0-2 | Barra de pestañas con los cuatro personajes originales animados, halo activo con pulso, motas de pestaña, variante Feed (L4) y elemento 64×48 | F45–F50, E35–E37, R31–R33, G35–G37 | DS (`SolarTabBar`, `SolarCreatureIcon`) | Capturas en t = 0 y t = 1,25 s distintas en la barra; iguales con `reduce` |
| P0-3 | Logotipo `BrandLogo` en `AppHeader` (resplandor en Feed) | F3, E2, R2, G2 | DS | «ChromaSol» con el arco a su izquierda en las 4 cabeceras |
| P0-4 | `SunSpiritButton` (Feed con M9, disco de Extraer con ping, plano en Jardín) y `LocalAvatar` con anillo, halo e insignia real | F7–F9, E3–E4, G3 | DS + pantallas (acción) | Acciones y etiquetas de VoiceOver sin cambios |
| P0-5 | Luces de componente: L1 (+ M2) en `DailyPickCard` y `FeedPostCard`; `SolarPrimaryButton(glow:)` con L5/L6 y `Shimmer`; L7 en `FilterChip`; variantes de cabecera L3 | F2, F12, F14, F22–F23, F25, E28–E29, R19–R20 | DS | Índice R−B junto a la tarjeta del día ≥ 20 (§8.3-6) |
| P1-6 | `SolarToast(style:)`: Feed arriba con halo, filo y icono girando; Jardín musgo; Extraer icono ámbar; M15 | F10, E34, G34 | DS + pantallas | — |
| P1-7 | Respuestas al pulsar (M14) por elemento y microanimaciones de iconos (`symbolEffect(.bounce)`, `.contentTransition(.symbolEffect(.replace))`, rotación 12°) | F36–F37, F41–F43, E22, E32, R25, R30, G26, G29, G31, G33 | DS | — |
| P2-8 | Icono de la app a partir del logotipo | §2.1 | DS + `ios/project.yml` | — |

### 7.1 Feed

| Prioridad | Qué falta | Filas |
|---|---|---|
| P0 | Motas de luz de pantalla (5, M1) con exclusión de pocillos | F1 |
| P0 | Tarjeta del día: filo y halos L1 + respiración M2, anillos giratorios de 25 s, icono con pulso, punto teal con ping | F14, F15, F16, F18 |
| P0 | Botón «Otra combinación»: halo ámbar L5, filo, barrido M13 de 2,5 s, icono `wand.and.stars` girando 6 s, pulsar 0,98 | F22, F23, F24 |
| P0 | Publicación con halo L1 (filo ámbar .25) | F25 |
| P0 | Cabecera ámbar (tinte .85, filo y halo) y punto con ping junto a la marca (ligado al escaneo) | F2, F5 |
| P1 | Píldora de la lente con halo, filo y `camera.macro` girando 8 s; lupa con filo verde y `shadow-md` | F32, F33 |
| P1 | Anillo del icono de origen y destello tras el título | F27, F28 |
| P1 | Chips: halo y filo del activo, icono con pulso, puntos de tono con halo, pulsar 0,95 | F12, F13 |
| P1 | Cinta del día: tocar un segmento copia; cambio de color de 500 ms en lugar de sustituir la tarjeta; «✦» y estilo del pie; insignia «Nº» con filo | F19, F20, F21 |
| P1 | Banda de pergamino alrededor del pocillo de gotas; gotas con pulsar 0,90 y marca de copiado | F34, F37 |
| P1 | Microanimaciones de «Sí», «Guardar», «Copiar» y «Copiar hex» | F36, F41, F42, F43 |
| P1 | Toast arriba con halo, filo e icono girando | F10 |
| P2 | Geometría 64×48 del elemento de pestaña | F46 |

### 7.2 Extraer

| Prioridad | Qué falta | Filas |
|---|---|---|
| P0 | Alfileres vivos: aro con ping (variantes por luminancia), halo del dominante, halo del color en la cuenta, glifo de muestra con flotación, etiqueta con filo y «✦», escala al pulsar; todo se apaga con máscara, aislamiento o alfiler seleccionado | E12, E13, E14, E15, E16 |
| P0 | Sol en disco con aro de ping, halo y flotación en la cabecera | E3 |
| P0 | Motas del visor (M20) con sus reglas de desvanecimiento | E8 |
| P0 | «Guardar en el jardín»: halo L6 completo, barrido al pulsar, brote animado (M8 + M6) y «✦» | E28, E29, E30, E31 |
| P1 | «Se parece a» con halo L2 y respiración M2 | E27 |
| P1 | Estado de captura con sol-espíritu, motas, retículas y luces del CTA | E38 |
| P1 | Sol mini con ping en la barra de personas mientras reanaliza | E18 |
| P1 | Tarjetas de prenda: respuesta al pulsar (sombra neutra, 0,98) y «✦» | E22, E25 |
| P1 | Avatar con filo de luz e insignia; toast con icono ámbar y desplazamiento | E4, E34 |
| P2 | Retículas de esquina; `shadow-md` del visor; pulsar 0,95 en secundarios; tinte .90 de la barra | E5, E9, E32, E35 |

### 7.3 Rejilla

| Prioridad | Qué falta | Filas |
|---|---|---|
| P0 | Reloj de sol de la tarjeta al azar: disco con halo y filo, sol en trazo con resplandor, aro discontinuo girando 10 s, aro exterior con pulso, giro acumulado al barajar; título al 70 % | R12, R13, R14, R15 |
| P0 | Barajar con fichas que se aplastan y vuelven escalonadas (M16) | R17 |
| P0 | Luces de la tarjeta: orbe cálido con pulso, orbe verde, punto con ping, punto con pulso, estrella girando 8 s con resplandor | R6, R7, R8, R9, R10 |
| P0 | «Otra»: halo L6, barrido al pulsar, estrella girando 1 s y «✦», pulsar 0,95 | R19, R20, R21 |
| P1 | Tarjetas de la cuadrícula con halo y aura al pulsar | R25, R26 |
| P1 | Chips compactos (`label-sm`, 14×6, `container`, sombra del activo) | R22 |
| P1 | Punto de estado junto al nombre, «✦» en el rótulo, halo en la insignia del nombre, rebote de «Guardar» | R11, R18, R29, R30 |

### 7.4 Jardín

| Prioridad | Qué falta | Filas |
|---|---|---|
| P0 | Luciérnagas en la tarjeta de perfil (M18) | G7 |
| P0 | Anillo con degradado, `shadow-md` y halo en la insignia del perfil; compañero (semilla solar) con bote | G8, G9 |
| P0 | Punto con ping en la línea de acierto y valor en semibold `primary` | G12 |
| P1 | Puntos de tono delante de los rótulos de los contadores | G15 |
| P1 | Cosechas: anillo e insignia «✦» en la miniatura, origen en `secondary`, halo del veredicto, rayo de sol, dominante marcado, destello de la fila «Dominante» | G22, G23, G24, G25, G26, G27 |
| P1 | Estudio: orbe de esquina, halo del disco del icono y respuesta al pulsar en las fichas | G31, G32, G33 |
| P1 | Toast musgo; sol plano en la cabecera; posición del lavado verde | G3, G6, G34 |
| P2 | Insignia «Local»; `shadow-sm` en Ajustes; `shadow-inner` en segmentos; rebote de la estrella/hoja | G10, G13, G16, G29 |

### 7.5 Pantallas secundarias (Ajustes, «Acerca de», licencias, escaneo y capas)

El ejemplo del usuario no dibuja ninguna de estas pantallas: su lenguaje se extrapola del marco de las cuatro
que sí dibuja (cabecera esmerilada con logotipo y rótulo de sección, motas de luz, tarjetas con halo, orbe
difuso de esquina, insignia circular de tono con resplandor y rótulo en versales). Dueño: **otro**
(`Views/Ajustes/**`, `Views/Common/**`, `Views/Wrapped/**`, `Views/Capas/**`).

| Estado | Pantalla | Qué lleva | Dónde |
|---|---|---|---|
| **hecho** | Ajustes | `SecondaryHeader` («AJUSTES») con `ChromaSolLogo` + wordmark y punto con ping, motas de luz, seis tarjetas con `glowCard`, orbe de esquina, `SectionBadge` con halo y rótulo en versales; sin barra de navegación del sistema | `Views/Ajustes/AjustesView.swift`, `Views/Common/SecondaryChrome.swift` |
| **hecho** | Acerca de | Portada con el emblema a 72 pt y destello solar de 12 s (`ChromaSolLockup(size: .display)`) en vez del antiguo `BrandMark` (SF Symbol `sun.max`), halo de tarjeta, lavados cálido y verde, filo de luz | `Views/Ajustes/AboutView.swift` |
| **hecho** | Licencias de fuentes | Ya no es una `List` blanca del sistema: cabecera de marca, tarjeta de sección y el texto OFL en un pocillo de lectura `container` | `Views/Ajustes/FontLicensesView.swift` |
| **hecho** | Escaneo del carrete (hoja) | Cabecera de marca con el aspa de cerrar (cancela el escaneo), emblema en la portada, halo en las tarjetas de estado, `glowPulse` en la tarjeta de progreso y motas en todas las etapas | `Views/Wrapped/ScanOnboardingView.swift` |
| **hecho** | «Tu carrete en color» | Emblema en el rótulo y halo de tarjeta en la portada; los pocillos de color siguen neutros | `Views/Wrapped/WrappedSummaryView.swift` |
| **hecho** | Resultado (Feed › «Abrir en Extraer») | Misma cabecera de marca en vez del título de la barra del sistema; el contenido (`ExtractResultContent`) ya es el de Extraer | `Views/Resultado/ResultView.swift` |
| **omitido (deliberado)** | Visor de capas | Se queda **neutro a propósito**: fondo `#121212`, pocillos `#303030` y ninguna luz de color. Es la pantalla de juicio de color por excelencia (§0.2 A de `DESIGN_SYSTEM.md`); meter halos ámbar aquí falsearía la lectura de las máscaras y de la paleta | `Views/Capas/**` |

Reglas que se mantienen en todas ellas: nada de luz de color a menos de 8 pt de un pocillo (las motas se
recortan solas con `.neutralZone()`), Reducir movimiento deja todo quieto, el ambiente se para fuera de
pantalla, en segundo plano y en reposo (§1.1), y el contraste sigue AA.

---

## 8. Verificaciones ejecutadas y criterios de aceptación

### 8.1 Comandos ejecutados (2026-09-15, Xcode 27.0 build 27A266a)

| Qué | Comando | Salida real |
|---|---|---|
| APIs de animación en la app | `for p in TimelineView Canvas keyframeAnimator phaseAnimator symbolEffect repeatForever "\.blur\(" "\.shadow\(" accessibilityReduceMotion scenePhase isLowPowerModeEnabled; do grep -rE "$p" ios/ColorsApp/Design ios/ColorsApp/Views ios/ColorsApp/App \| wc -l; done` | `TimelineView: 0`, `Canvas: 5` (rayado de bloqueadas y visor de capas, ninguno ambiental), `keyframeAnimator: 0`, `phaseAnimator: 0`, `symbolEffect: 0`, `repeatForever: 0`, `.blur(: 1` (`SolarWash`), `.shadow(: 11`, `accessibilityReduceMotion: 3`, `scenePhase: 0`, `isLowPowerModeEnabled: 0` |
| Clases de animación y luz del ejemplo | `grep -o "<clase>" <pantalla>/code.html \| wc -l` | Feed: `animate-ping` 3, `animate-pulse` 4, `animate-spin` 4, `animate-[spin` 1, `animate-[shimmer` 1, `backdrop-blur` 7, `shadow-[0_0_` 34, `ring-` 26, `blur-` 15 · Extraer: 8, 1, 0, 0, 0, 18, 20, 0, 23 · Rejilla: 4, 4, 1, 2, 0, 3, 15, 0, 8 · Jardín: 2, 0, 0, 0, 0, 2, 16, 4, 9 |
| `@keyframes` definidos | `grep -o "@keyframes [a-z-]*" */code.html` | Solo `solar_feed…`: `botw-float`, `botw-pulse`, `soot-bounce`, `soot-blink`, `dragonfly-flutter`, `wing-vibrate`, `kodama-bob`, `sprout-sway`, `solar-sparkle` |
| Clases de animación usadas | `grep -o "anim-[a-z0-9-]*\|…" *.txt \| sort \| uniq -c` | Extraer: `anim-dragonfly-wing` 5, `anim-float-1` 1, `anim-float-2` 2, `anim-float-3` 1, `anim-float-4` 1, `anim-soot` 1, `anim-spirit-bob` 4, `anim-sprout` 2 (ninguna definida) · Jardín: `botw-glow` 2 (sin definir) · `shimmer` sin `@keyframes` |
| Propiedad intelectual en `ios/` | `grep -rniE "ghibli\|totoro\|howl\|kiki\|laputa\|chihiro\|arrietty\|zelda\|botw\|sheikah\|zonai\|kodama\|susuwatari\|nausica\|mononoke\|ponyo\|porco\|cagliostro\|soot" ios/ \| wc -l` | `0` |
| Halo junto a la tarjeta del día (índice R−B, media de píxeles) | Python/Pillow sobre `screen.png` (x 11–16, y 150–230) y `verify-feed-light.png` (x 9–39 px, y 700–1000) | Ejemplo `(240.0, 235.2, 214.0)` → R−B 26,0; ejemplo lejos de tarjetas `(252.0, 249.0, 241.0)` → 11; app `(249.7, 246.5, 238.3)` → 11,4; app fondo `(248.5, 245.1, 236.9)` → 11,6 |
| Recetas de §1 compilan | `xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 6 -target arm64-apple-ios17.0-simulator -sdk $(xcrun --sdk iphonesimulator --show-sdk-path) docs/design/fidelity/ambient-recipes.swift; echo $?` | `0` (con `-swift-version 6` y sin `@MainActor` en `Keyframes` daba el error «static property 'bounce' is not concurrency-safe because non-'Sendable' type 'KeyframeTimeline<BouncePose>'»: corregido; comprobación negativa con un nombre inexistente: «cannot find 'KeyframeTimelineX' in scope») |
| Personajes originales dibujados | `swiftc -O -parse-as-library -o oc original-characters.swift && ./oc` | `ok 1372x1136` → `original-characters.png` |
| SF Symbols propuestos | `plistlib` sobre `CoreGlyphs.bundle/name_availability.plist` del runtime iOS 27 | `camera.macro` iOS 15.4, `sparkle` 14.0, `sparkles` 13.0, `wand.and.stars` 13.0, `sun.max` 13.0, `viewfinder` 13.0, `leaf.fill` 14.0, `paintpalette` 14.0, `square.3.layers.3d` 16.0, `theatermask.and.paintbrush` 16.0, `dice` 15.0, `wrench.and.screwdriver` 14.0, `checkmark.circle` 13.0, `slider.horizontal.3` 13.0, `photo.stack` 16.0, `star.fill` 13.0, `drop.halffull` 17.0 |
| Tamaño de las capturas | `sips -g pixelWidth -g pixelHeight` | Ejemplo: Feed 425×1600, Extraer 545×1600, Rejilla 513×1600, Jardín 456×1600 (página completa). App: 19 `verify-*.png` de 1320×2868 (440×956 pt @3x) |
| Rutas protegidas | `grep -n docs harness/PROTECTED.txt` | Sin coincidencias: `docs/design/**` no está protegido |

### 8.2 Recuento de estados de la auditoría

Regla: cuenta el primer estado de la celda «Estado actual» (una celda como «**falta** el logotipo; texto **hecho**»
cuenta como **falta**). Si se editan las tablas, recalcular con el mismo método.

| Pantalla | Elementos | hecho | parcial | falta | omitido |
|---|---|---|---|---|---|
| Feed (§3) | 50 | 13 | 25 | 11 | 1 |
| Extraer (§4) | 38 | 17 | 11 | 9 | 1 |
| Rejilla (§5) | 33 | 9 | 8 | 14 | 2 |
| Jardín (§6) | 37 | 14 | 14 | 7 | 2 |
| **Total** | **158** | **53** | **58** | **41** | **6** |

Cómo se contó: `uv run --project oracle python` con una expresión regular sobre las filas `| F…`, `| E…`, `| R…`, `| G…`
de este fichero (primer `**estado**` de la última celda; se comprobó además que todas las filas tienen 6 celdas).
Casi todo lo que está **hecho** es estructura, tipografía, color y funciones; casi todo lo que está en **falta** o
**parcial** es movimiento, luz, marca y personajes.

### 8.3 Criterios de aceptación para quien implemente

Con su propio `DERIVED` y su propio simulador clonado (`xcrun simctl clone`), en claro y oscuro:

1. **Propiedad intelectual**: el `grep` de §8.1 sobre `ios/` sigue en `0`, y no hay rasgos prohibidos de §2 (revisión
   visual de `original-characters.png` frente a lo implementado).
2. **Un solo reloj**: `grep -rn "TimelineView" ios/ColorsApp` solo aparece en `Design/Motion/`; ninguna animación continua
   con `repeatForever` o `keyframeAnimator(repeating:)`.
3. **Se mueve**: dos capturas de cada pantalla con `-uiAmbientTime 0` y `-uiAmbientTime 1.25` difieren en la barra de
   pestañas, las motas y los elementos M de la pantalla; son idénticas (diferencia 0) dentro de cada pocillo.
4. **Reducir movimiento**: con `-uiAmbient reduce`, dos capturas separadas 2 s son idénticas píxel a píxel y no hay
   motas ni barrido; los personajes están en su pose de reposo.
5. **Pocillo neutro con luces**: el criterio 4 de `DESIGN_SYSTEM.md` §7 (ningún píxel no neutro en un anillo de 8 pt
   alrededor de cada swatch) se cumple en 25 capturas con `-uiAmbientTime` de 0 a 12 s cada 0,5 s.
6. **Luces**: índice R−B junto al borde izquierdo de la tarjeta del día ≥ 20 en claro (ejemplo 26, hoy 11,4); halo del
   botón ámbar y de la publicación visibles en `compare-feed.jpg` regenerado.
7. **Fidelidad A/B**: regenerar `docs/design/fidelity/compare-*.jpg` con las capturas nuevas y revisar fila a fila §3–§6;
   ninguna fila P0 en **falta**.
8. **Pausa**: al cambiar de pestaña, el reloj de la anterior queda pausado (registro DEBUG
   `ambient paused tab=<tab>`); en segundo plano y con Ahorro de energía, 0 fotogramas.
9. **Rendimiento** (en el iPhone 13 mini del usuario, no medible aquí): 
   `xcrun xctrace record --template "Time Profiler" --device <udid> --attach ColorsApp --time-limit 20s`
   en el Feed quieto: CPU media ≤ 8 % con el ambiente activo, ≤ 30
   fps en el instrumento Animation Hitches/Core Animation, y ≈ 0 % tras 30 s sin tocar.
10. **Contraste**: `DesignSystemTests` en verde (los tokens no cambian); el barrido va bajo el texto; ningún texto nuevo
    con opacidad < 1 ni en `outline`.
