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
// result.steps        => [.poseRegions, .skinExcluded], [.headCut], [.noPeople]...
// result.layers       => capas para pintar: personMask (binaria), pose, silhouetteMask, armsMask,
//                        regionMask, faceSampleMask, skinRemovedMask, finalMask (por persona),
//                        regionDecision (por qué se eligió cada región) y allPeopleOverlay
```

`SubjectExtractor.detectPeople` + `SubjectExtractor.mask(people:...)` separan la detección
(costosa: ~0,3–1 s por foto) de la cadena (barata): cambiar de persona o de modo no repite Vision.

## Cadena (`largestPerson` / `selectedPerson`)

1. **Persona binaria**: la instancia de Vision es blanda (halo 1…127 sobre vecinos y fondo);
   la cadena y el motor solo ven `>= 128 → 255`.
2. **Muestra de piel**: mejillas y frente de su cara; sin cara utilizable (de espaldas,
   gafas, < 50 muestras) y con `shareSkinModel`, la de la persona de la foto con más muestras.
3. **Región de ropa** (`region = .clothing`):
   - Sin modelo de piel pedido y disponible, sin brazos (con manga corta serían piel).
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
4. **Piel**: `fitSkinModel` + `excludeSkin` (salvaguarda del 35 %: `skinGuard`).
5. **Suelo** (`minCoverage` = 0,05 % del raster): si la máscara final no llega, la silueta
   (con pose) o la persona binaria (`wholePerson`, `PersonLayers.fallbackSource`); si
   tampoco, sin máscara (`none`). Con pose nunca se vuelve a la instancia cruda de Vision.

`allPeople` aplica la cadena a cada persona y une (máximo por píxel) las que llegan al suelo.
Instancias de menos del 0,05 % del raster se descartan en la detección (fragmentos).

## visionmask (macOS)

```sh
make visionmask            # build-subject/visionmask
build-subject/visionmask foto.png --out-dir DIR [--variants none,allPeople,largest,largest-clothing,largest-clothing-skin] \
                         [--max-side 1024] [--layers] [--min-coverage 0.0005] [--min-region-fraction 0.15] \
                         [--bare-arms-fraction 0.25] [--max-mahalanobis 2.5]
build-subject/visionmask report --masks-dir DIR --batch lote.jsonl --expected expected.json --out report.md \
                         [--repro repro.tsv] [--references Fixtures/people_references.json]
make visionmask-people     # harness/people -> harness/out/people-masks (+ ce batch, reproducción y report.md)
make subject-test          # swift test (cadena sintética + Vision real sobre harness/people)
```

Salidas por foto: `<base>.ppm` (raster exacto de la app), `<base>.<variante>.pgm` (máscara
final), `<base>.batch.txt` (entrada de `ce batch`), `<base>.json` (personas, poses, caras,
decisión de región, pasos y tiempos) y, con `--layers`, `<base>.<variante>.layers/` con
`person_vision.pgm`, `person.pgm`, `silhouette.pgm`, `arms.pgm`, `region.pgm`,
`face_sample.pgm`, `skin_removed.pgm`, `person_final.pgm`, `final.pgm`, `instances.pgm|ppm`,
`pose.txt` (la pose que recibió el motor, formato de `ce regions`) y `repro.sh`, que recalcula
cada capa y cada decisión con la CLI `ce` y la compara byte a byte.

`report --references` reparte el peso de cada paleta en prenda / piel / fondo / otro con
parches medidos a mano (`Fixtures/people_references.json`): el swatch dominante solo no ve un
30 % de piel en la paleta.
