# SubjectKit

Paquete Swift (iOS 17 / macOS 14) que aísla a las personas de una foto con Apple Vision
y produce las máscaras que consume el motor C (`engine/`, producto `ColorEngine`).
Vision solo detecta (instancias de persona, pose, landmarks de cara); la región de ropa y
la exclusión de piel las calcula el motor. Decisión y medidas: `docs/DECISIONS.md`, ADR-010.

## Uso desde la app

```swift
import ColorEngine
import SubjectKit

// raster: los mismos píxeles RGBX sRGB que recibe ColorEngine.analyze (≤ 1024 px).
let result = try raster.pixels.withUnsafeBufferPointer { px in
    try SubjectExtractor.compute(image: cgImage, rgba: px, width: raster.width, height: raster.height,
                                 stride: raster.stride, options: .default)
}
// result.mask == nil  => analizar sin máscara (sin personas, Vision no disponible, modo off...)
// result.steps        => [.poseRegions, .skinExcluded], [.headCut], [.noPeople], [.rejectedPhantom, .noPeople]...
// result.rejectedPhantoms => instancias de Vision sin evidencia corporal descartadas (caso nuevo de MaskFallback:
//                        los `switch` exhaustivos sobre `MaskFallback` deben añadir `.rejectedPhantom`)
// result.layers       => capas para pintar: personMask (binaria), pose, silhouetteMask, armsMask,
//                        regionMask, faceSampleMask, skinRemovedMask, finalMask (por persona),
//                        regionDecision (por qué se eligió cada región) y allPeopleOverlay
```

Instancias fusionadas: Vision junta en una sola instancia a las personas que se tocan (07;
selfies apretadas). `detectPeopleDetailed` las separa con semillas de poses y caras
(`PersonSplitter`, geometría en `ce_mask_split_instance` del motor): cada persona separada lleva
`splitFrom` (id de la instancia de Vision), su pose y su cara, y su cadena empieza con
`.splitByPose` o `.splitByFace` (dos casos nuevos de `MaskFallback`: los `switch` exhaustivos
deben añadirlos, p. ej. «Persona separada por su pose»). Hasta 8 personas. Reglas y medidas:
cabecera de `PersonSplit.swift`, `docs/DECISIONS.md` (ADR-010) y la sección de abajo.

### Paleta por prenda (ADR-011)

```swift
var options = SubjectOptions.default
options.computeGarmentRegions = true   // aditivo; por defecto false
let result = try SubjectExtractor.compute(...)
if let mask = result.mask, let regions = result.garmentRegions {
    // Con pose: un color por prenda (arriba / abajo / prenda entera) con su tono iluminado.
    let g = try analyzeGarments(rgba: px, width: w, height: h, stride: s, mask: mb, regions: rb,
                                regionCount: garmentMaxRegions)
    // g.garments: [GarmentSwatch] con region (.upper/.lower/.whole), regionShare y mergedClusterCount
} else {
    // Sin pose (recorte de cabeza), wholePerson o sin máscara: camino clásico.
    let a = try analyze(rgba: px, width: w, height: h, stride: s, mask: mb)
}
```

`result.garmentRegions` (width * height bytes: 0 fuera, 1 arriba = torso y brazos, 2 abajo =
caderas a tobillos) sale de `ColorEngine.garmentRegions(pose:options:personMask:...)`
(`ce_mask_garment_regions`) con la pose del motor, las opciones de la silueta
(`SubjectExtractor.garmentRegionOptions`) y la máscara final de la persona: sus píxeles > 0 son
exactamente los de `result.mask`. Con caderas estimadas (plano medio) no hay parte de abajo: los
píxeles que el motor etiqueta 2 pasan a 1 (`PersonLayers.garmentRegionStats.lowerMergedIntoUpper`).
Con `allPeople` el mapa va por persona (`layers.persons[i].garmentRegions`) y el del resultado es
nil. Cuando se calcula, los pasos terminan en `.garmentRegions` (caso nuevo de `MaskFallback`:
los `switch` exhaustivos deben añadirlo, p. ej. «Regiones de prenda»). Etiquetas para las
tarjetas: 1 «Parte de arriba», 2 «Parte de abajo», 3 «Prenda entera».

`SubjectExtractor.detectPeopleDetailed` + `SubjectExtractor.mask(detection:...)` (o `mask(people:...)`, sin
el paso de fantasmas) separan la detección (costosa: ~0,3–1 s por foto) de la cadena (barata): cambiar de
persona o de modo no repite Vision.

## Personas fantasma (evidencia corporal)

Vision devuelve instancias de persona en imágenes sin nadie (PNG liso, bandas de color, texturas) y en
prendas sin persona (vestidos y monos en percha, perchero, prenda plana, abrigo en la puerta). Tras
asociar poses y caras, una instancia solo es persona si tiene (`PersonEvidence`, `PhantomOptions`):
1. **pose**: >= 2 puntos del torso (cuello, hombros, caderas, raíz) con confianza >= 0,3 dentro de su
   máscara (tolerancia 2 px);
2. **cara** asociada;
3. **rectángulo de persona** (sin pose ni cara): un rectángulo de cuerpo entero de
   `VNDetectHumanRectanglesRequest` (confianza >= 0,3; se pide solo si alguna instancia no tiene pose ni
   cara) asociado a la instancia (`associateHumanRectangles`: va a la instancia con más píxeles dentro) con
   >= 50 % de sus píxeles dentro y cubriendo >= 10 % del rectángulo (`PersonEvidence.Kind.humanRectangle`,
   caso nuevo);
4. **forma** solo con `acceptShapeOnly` (desactivada por defecto): cobertura 1–60 % del raster, alto/ancho
   del bbox 1,2–6, relleno del bbox <= 0,8, solidez <= 0,88 y alto del bbox < 95 % del raster. Un vestido
   colgado cumple todo eso; `PersonEvidence.plausibleShape` la sigue informando.

El resto se descarta (`rejectedPhantoms`, paso `.rejectedPhantom` al principio); si no queda nadie, la foto
se analiza completa (`[.rejectedPhantom, .noPeople]`). Medido con visionmask (macOS): ninguna de las 148
sintéticas sin personas de `harness/people/nopeople` (48 son prendas), de los 20 PNG de `sim_media`, de 100
sintéticos de la capa 3 ni de 32 imágenes de prendas del verificador tiene rectángulo de persona ni persona
aceptada; las 18 personas de `harness/people` se conservan (16 por pose, 2 por cara).

## Separación de instancias fusionadas

`VNGeneratePersonInstanceMaskRequest` devuelve como mucho 4 instancias y junta en una sola a las
personas que se tocan o se solapan (el fallo real del usuario: una selfie con los dos adultos
hombro con hombro). Las caras y las poses sí salen por persona: `PersonSplitter` construye una
**semilla** (eje del cuerpo + semiancho) por persona y el motor decide qué píxel es de quién
(`ce_mask_split_instance`: argmin de distancia al eje / semiancho), para que la web futura use la
misma geometría.

- **Semilla de pose** (cuello o dos hombros): eje cuello → raíz/caderas, o extrapolado
  1,6 · anchura de hombros; semiancho 0,55 · anchura de hombros, mínimo 0,6 · ancho de su cara.
- **Semilla de cara** (cara sin pose): base del rectángulo → 3,0 · alto, semiancho 1,1 · ancho.
  Cara y pose se fusionan si el centro de la cara está a < 0,8 · ancho de cara del cuello o la nariz.
- **Cuenta para una instancia** si su cara cae dentro (>= 128) o su punto superior está en la
  máscara dilatada 0,25 · ancho de cara **y** al menos la mitad de las 17 muestras de su eje está
  dentro. Una instancia con 2 o más semillas se separa; cada semilla con cara aporta además un
  **segmento de cabeza** (centro de la cara → punto superior del eje, semiancho 0,5 · ancho de
  cara). Las partes de una misma semilla en varias instancias se unen; las etiquetas con menos de
  `minSplitCoverage` (0,5 % del raster) van a la vecina conservada con más píxeles; si quedan
  menos de 2, la instancia no se toca.
- **Caras que no son personas**: una semilla de CARA sin pose solo cuenta si tiene cuerpo
  (`SplitOptions.requireBodyForFaceSeeds`, activo): un rectángulo de persona de Vision que sea el
  SUYO (contiene el centro de la cara, empieza a su altura y baja al menos un alto de cara por
  debajo) o >= 2 puntos de una pose que no es semilla, bajo la cara y dentro de su eje. Sin esta
  regla, una cara estampada en una camiseta o la de una pantalla creaba una persona fantasma con
  la mitad de la ropa de la persona real (`harness/out/faces`, `make visionmask-faces`).

Medido (macOS 26, instancias de Vision → personas): 01 1→1, 02 1→1, 03 2→2, 04 2→2, 05 3→3,
06 4→4, **07 4→7**, 08 1→1 y `synthetic_tight_selfie` **2→3**. `SplitOptions(enabled: false)`
devuelve el comportamiento anterior (una persona por instancia).

## Cadena (`largestPerson` / `selectedPerson`)

1. **Persona binaria**: la instancia de Vision es blanda (halo 1…127 sobre vecinos y fondo);
   la cadena y el motor solo ven `>= 128 → 255`.
2. **Muestra de piel**: mejillas y frente de su cara; sin cara utilizable (de espaldas,
   gafas, < 50 muestras) y con `shareSkinModel`, la de la persona de la foto con más muestras.
3. **Región de ropa** (`region = .clothing`):
   - Sin modelo de piel pedido y disponible, **prueba de mangas**: los brazos se quedan si >= 70 %
     (`sleeveMatchFraction`) de sus píxeles está a Mahalanobis <= 2 del modelo gaussiano del torso
     (`fitSkinModel` con el torso como muestra: camisa de espaldas, 03); si no, fuera (manga corta = piel).
   - Con pose: caderas estimadas si solo hay hombros (plano medio, `regionPose`);
     `clothingRegions`; **brazos desnudos**: si el modelo marca como piel >= 25 %
     (`bareArmsSkinFraction`) de los brazos, se quitan; **silueta de la pose**
     (`silhouetteOptions`: cápsulas y torso anchos, sin cabeza ni manos).
     Si la silueta llega al suelo absoluto: regiones si son >= 15 % de la silueta
     (`minRegionFraction`), si no la silueta. La referencia es la silueta (la persona que
     describe la pose), no la instancia de Vision: un bebé en un cochecito conserva su ropa
     y el cochecito no entra.
   - Sin pose, `CE_ERR_POSE` o silueta por debajo del suelo: `cutHead` con la altura de la
     cara si la hay (mínimo 18 %).
   - Con modelo, **piel del cuerpo aprendida**: si los brazos o las piernas son desnudos (>= 25 % piel con
     el modelo de la cara), hasta 2 pasadas (`skinLearningIterations`) amplían la muestra con los píxeles de
     la región que el modelo vigente marca como piel a Mahalanobis <= 3 y reajustan el modelo con el motor;
     una pasada no se acepta si el modelo ampliado dispararía la salvaguarda. Hombros al sol y escote o
     piernas en sombra (07, 02) entran en el modelo aunque la cara tenga otra luz.
4. **Piel**: `fitSkinModel` + `excludeSkin` con el preajuste de SubjectKit (Mahalanobis 2,75, salvaguarda
   del 35 %: `skinGuard`); **crecimiento de la piel en sombra** (histéresis): los píxeles que quedan a
   Mahalanobis <= 5 (`skinGrowMahalanobis`) del mismo modelo y conectados (vecindad de 8, <= 12 pasos,
   `skinGrowRadius`) con la piel quitada también se quitan, salvo que piel + crecimiento superen la
   salvaguarda o el crecimiento supere 0,5 veces la piel quitada (`skinGrowMaxRatio`: una prenda de color
   piel con unos pocos píxeles dentro del umbral estricto no crece entera) (cuello, axila, canto de la mano
   y dedos en sombra: 05 y 07); y **halo** de 2 px
   (`skinHaloRadius`): fuera los píxeles pegados a la piel quitada (bordes piel/prenda mezclados; el motor
   además promedia bloques de 4 px con los píxeles fuera de la máscara). Capas: `learnedSampleMasks`,
   `skinExcludedMask` (antes del crecimiento y del halo), `skinGrownMask`, `skinGrownPixels`,
   `skinGrowCandidatePixels`, `skinHaloPixels`, `legsMask`, `sleeveTorsoMask`.
5. **Suelo** (`minCoverage` = 0,05 % del raster): si la máscara final no llega, la silueta
   (con pose) o la persona binaria (`wholePerson`, `PersonLayers.fallbackSource`); si
   tampoco, sin máscara (`none`). Con pose nunca se vuelve a la instancia cruda de Vision.

`allPeople` aplica la cadena a cada persona y une (máximo por píxel) las que llegan al suelo.
Instancias de menos del 0,05 % del raster se descartan en la detección (fragmentos).

## visionmask (macOS)

```sh
make visionmask            # build-subject/visionmask
make subject-nopeople      # harness/out/nopeople: 148 PNG sin personas, 48 de prendas (build_nopeople.py, sha256 de píxeles)
make subject-faces         # harness/out/faces: 8 PNG con caras que NO son personas (retrato y pantalla, solos, pegados, detrás y sobre el torso)
make visionmask-faces      # personas por fixture con la regla de evidencia corporal, sin ella (--no-face-seed-body) y sin separar (--no-split)
make visionmask-nopeople   # fantasmas antes/después en nopeople + sim_media (gate: 0 en sim_media, >= 98 % en total y en prendas)
build-subject/visionmask foto.png --out-dir DIR [--variants none,allPeople,largest,largest-clothing,largest-clothing-skin,largest-clothing-skin-garments] \
                         [--max-side 1024] [--layers] [--min-coverage 0.0005] [--min-region-fraction 0.15] \
                         [--bare-arms-fraction 0.25] [--max-mahalanobis 2.75] [--skin-learning-iterations 2] \
                         [--skin-learning-mahalanobis 3] [--skin-halo 2] [--sleeve-fraction 0.7] \
                         [--sleeve-mahalanobis 2] [--skin-grow-mahalanobis 5] [--skin-grow-radius 12] [--skin-grow-max-ratio 0.5] \
                         [--no-phantom-filter] [--accept-shape-only] [--no-human-rectangles]
build-subject/visionmask report --masks-dir DIR --batch lote.jsonl --expected expected.json --out report.md \
                         [--repro repro.tsv] [--references Fixtures/people_references.json]
make visionmask-people     # harness/people -> harness/out/people-masks (+ ce batch, reproducción y report.md)
make subject-test          # swift test (cadena sintética + Vision real sobre harness/people, sim_media y nopeople)
```

Salidas por foto: `<base>.ppm` (raster exacto de la app), `<base>.<variante>.pgm` (máscara
final), `<base>.batch.txt` (entrada de `ce batch`), `<base>.json` (personas, poses, caras,
decisión de región, pasos y tiempos) y, con `--layers`, `<base>.<variante>.layers/` con
`person_vision.pgm`, `person.pgm`, `silhouette.pgm`, `arms.pgm`, `legs.pgm`, `sleeve_torso.pgm`,
`region.pgm`, `face_sample.pgm`, `learned_sample_<i>.pgm`, `skin_excluded.pgm`, `skin_grown.pgm`, `skin_removed.pgm`,
`person_final.pgm`, `final.pgm`, `instances.pgm|ppm`,
`pose.txt` (la pose que recibió el motor, formato de `ce regions`) y `repro.sh`, que recalcula
cada capa y cada decisión con la CLI `ce` y la compara byte a byte.

Variantes con el sufijo `-garments` (por defecto `largest-clothing-skin-garments`): además del
mapa de regiones de prenda (`<base>.<variante>.garments.pgm|.ppm`, y `<base>.garments.pgm|.ppm`
en la variante canónica) escriben la capa «Prendas» en `<variante>.layers/`
(`garment_regions.pgm|.ppm` en el raster, `garments.pgm|.ppm` con el swatch de prenda de cada
píxel reducido, `garment_regions_reduced.pgm|.ppm` y `garments.json` con los swatches, sus
clusters agrupados y el hash de `ce_garment_hash`) y dejan su línea en `<base>.garments.txt`
("imagen máscara regiones"), que `make visionmask-people` analiza con `ce batch --garments
--n-regions 2`. Sin pose, la variante vuelve a `<base>.batch.txt` (camino clásico, como la app).
`repro.sh` añade los pasos `garment-regions`, `garments`, `garments-color`,
`garment-regions-reduced[-color]` y `garment-hash`: la capa del wrapper Swift
(`garmentDebugLayers`) debe salir byte a byte igual que `ce garments --debug-dir`.

`report --references` reparte el peso de cada paleta en prenda / piel / fondo / otro con
parches medidos a mano (`Fixtures/people_references.json`): el swatch dominante solo no ve un
30 % de piel en la paleta. La piel incluye los parches oscurecidos en luz lineal (`skin_shaded`,
`Scripts/people_references_shaded.py write|check`) y, con el módulo interno `SubjectMetrics` (sin
producto; la app no lo enlaza), se mide también qué fracción de la PALETA viene de píxeles reducidos de
piel (color de cada píxel que alimenta un swatch conservado) y qué fracción de la MÁSCARA es piel, sin
contar las zonas de pelo (`hair_zones`). Gate de `make visionmask-people` y `make subject-test`: con la
variante por defecto y cara visible, <= 5 % en ambas.

El informe añade, con las variantes `-garments`, la tabla «Colores por prenda» por foto (prenda,
color, peso, clusters agrupados y ΔE00 a la prenda anotada de su parte) y el resumen antes
(camino clásico con la misma máscara) / después, con el gate informativo del pantalón liso
(<= 1 color abajo salvo estampado anotado; `make subject-test` lo comprueba de verdad).

Con `--layers`, además, una vez por foto: `<base>.instances_vision.pgm|ppm` (instancias de
Vision), `<base>.instances_split.pgm|ppm|png` (personas tras separar; el PNG superpone colores,
ejes de semillas —a rayas las de cara, en gris las descartadas por no tener cuerpo— y rectángulos
de cara sobre la foto), `<base>.seeds.txt` (todas las semillas en el formato de `ce split`, con su
origen y su evidencia corporal) y, por instancia separada, `<base>.split<id>.mask.pgm|seeds.txt|labels.pgm`
con un `<base>.split_repro.sh` que las recalcula con `ce split` y las compara byte a byte
(`make visionmask-people` lo ejecuta).
