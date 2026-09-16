// visionmask: CLI de macOS que produce, para una foto, el raster exacto que ve
// el motor en la app y las máscaras de SubjectKit por variante, con sus capas,
// para analizarlas con `ce batch` (capa 4) y reproducir cada paso con
// `ce regions` / `ce cut-head` / `ce skin`.
//
//   visionmask <imagen.png|jpg> --out-dir DIR [--variants LISTA] [--max-side 1024] [--layers]
//              [--min-coverage F] [--min-region-fraction F] [--bare-arms-fraction F] [--max-mahalanobis F]
//              [--skin-learning-iterations N] [--skin-learning-mahalanobis F] [--skin-halo N]
//              [--sleeve-fraction F] [--sleeve-mahalanobis F] [--skin-grow-mahalanobis F] [--skin-grow-radius N]
//              [--skin-grow-max-ratio F]
//              [--no-phantom-filter] [--accept-shape-only] [--no-human-rectangles]
//   visionmask report --masks-dir DIR --batch lote.jsonl --expected expected.json --out report.md
//                     [--repro repro.tsv]
//
// Variantes (separadas por comas; defecto none,allPeople,largest,largest-clothing,largest-clothing-skin):
//   none                      sin máscara (no escribe .pgm)
//   <base>[-clothing][-skin|-ownskin][-garments]  base = allPeople | largest | selected<N> (N = índice
//                             en people); -clothing = solo ropa (pose, silueta o corte de cabeza); -skin
//                             = piel adaptativa (compartida si la persona no tiene cara); -ownskin = solo
//                             la muestra de la propia cara; -garments = además el mapa de regiones de
//                             prenda de la pose (SubjectOptions.computeGarmentRegions, ADR-011) y la
//                             capa «Prendas» (`ce garments` con la máscara y el mapa).
//
// Salidas en DIR (base = nombre del fichero sin extensión):
//   <base>.ppm                  raster RGB (CGContext sRGB noneSkipLast, lado mayor <= max-side)
//   <base>.<variante>.pgm       máscara final de la variante (si no es nil)
//   <base>.batch.txt            una línea "imagen [mascara]" por variante (entrada de ce batch)
//   <base>.<variante>.garments.pgm  (variantes -garments con pose) mapa de regiones de prenda de la
//                               persona elegida en el raster: 0 fuera, 1 arriba, 2 abajo (==
//                               garment_regions.pgm de las capas); .ppm lo pinta con los colores de
//                               `ce`. La variante canónica largest-clothing-skin-garments deja además
//                               <base>.garments.pgm y <base>.garments.ppm (enlace duro)
//   <base>.garments.txt         (variantes -garments con pose) línea "imagen mascara regiones" por
//                               variante (entrada de `ce batch --garments --n-regions 2`); sin pose la
//                               variante va a <base>.batch.txt (camino clásico, como la app)
//   <base>.json                 personas (con su evidencia corporal), fantasmas descartados, pasos y tiempos por variante
//   <base>.<variante>.layers/   (--layers, variantes con personas) capas del raster:
//       person_vision.pgm máscara de instancia de Vision tal cual (blanda; unión en allPeople)
//       person.pgm        persona binaria (>= 128 -> 255): entrada de la cadena y de `ce regions`
//       region.pgm        región de ropa antes de la piel (regiones o silueta de la pose, o headCut)
//       silhouette.pgm    silueta de la pose (persona binaria ∩ esqueleto ancho, sin cabeza ni manos):
//                         referencia del 15 % y respaldo con pose en vez de la instancia de Vision
//       arms.pgm          brazos probados en la prueba de brazos desnudos o de mangas (regiones con brazos − sin brazos)
//       legs.pgm          piernas probadas en la prueba de piernas desnudas (regiones − sin piernas)
//       sleeve_torso.pgm  torso de la prueba de mangas (sin modelo de piel)
//       learned_sample_<i>.pgm  muestra de piel ampliada tras la pasada i de aprendizaje (1...)
//       skin_excluded.pgm máscara tras excludeSkin, antes del halo
//       face_sample.pgm   muestra de piel de la cara (solo con -skin y cara)
//       skin_removed.pgm  255 donde se quitó piel (sin salvaguarda)
//       person_final.pgm  salida de la cadena de la persona antes de la cobertura mínima
//       final.pgm         máscara que recibe el motor (== <base>.<variante>.pgm)
//       instances.pgm     id de instancia por píxel (0 = fondo); instances.ppm en color
//       pose.txt          pose que recibió el motor, en el formato de `ce regions` (con caderas
//                         estimadas en planos medios; pose_vision.txt = la de Vision si difiere;
//                         pose_<i>.txt por persona en allPeople)
//       garment_regions.pgm  (variantes -garments con pose) mapa de regiones de prenda en el raster
//                         (0 fuera, 1 arriba, 2 abajo) y garment_regions.ppm en color
//       garments.pgm      (idem) capa «Prendas»: swatch de prenda de cada píxel REDUCIDO
//                         (ce_debug_garment_map) y garments.ppm con el color de su swatch;
//                         garment_regions_reduced.pgm/.ppm = región de cada píxel reducido
//                         (ce_debug_region_map); garments.json = swatches con región, peso y clusters
//                         agrupados (group_head), hash de ce_garment_hash y top-3
//       repro.sh          (una persona) recalcula cada capa con `ce` y la compara con cmp
//   Los ficheros idénticos entre variantes se escriben una vez y se enlazan (enlace duro).
// Exit: 0 ok, 1 Vision o el motor fallaron, 2 uso o E/S.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ColorEngine
import SubjectKit

// MARK: - Utilidades

/// Escritor de capas que no duplica bytes: si ya escribió un fichero idéntico en
/// esta ejecución (p. ej. person.pgm de largest y largest-clothing, o
/// instances.pgm en todas las variantes) crea un enlace duro en vez de otra copia.
final class LayerStore {
    private var written: [Int: [(Data, URL)]] = [:]

    func write(_ data: Data, to url: URL) {
        let key = data.hashValue
        if let hit = written[key]?.first(where: { $0.0 == data }) {
            try? FileManager.default.removeItem(at: url)
            if (try? FileManager.default.linkItem(at: hit.1, to: url)) != nil { return }
        }
        writeData(data, to: url)
        written[key, default: []].append((data, url))
    }
}

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("visionmask: \(message)\n".utf8))
    exit(code)
}

func usageText() -> String {
    """
    uso:
      visionmask <imagen.png|jpg> --out-dir DIR [--variants none,allPeople,largest,largest-clothing,largest-clothing-skin,largest-clothing-skin-garments]
                 [--max-side 1024] [--layers] [--min-coverage 0.0005] [--min-region-fraction 0.15]
                 [--bare-arms-fraction 0.25] [--max-mahalanobis 2.75] [--skin-learning-iterations 2]
                 [--skin-learning-mahalanobis 3] [--skin-halo 2] [--sleeve-fraction 0.7] [--sleeve-mahalanobis 2]
                 [--skin-grow-mahalanobis 5] [--skin-grow-radius 12] [--skin-grow-max-ratio 0.5]
                 [--no-phantom-filter] [--accept-shape-only] [--no-human-rectangles]
                 [--no-split] [--no-face-seed-body] [--min-split-coverage 0.005] [--face-only-body]
      visionmask report --masks-dir DIR --batch lote.jsonl --expected expected.json --out report.md [--repro repro.tsv]
    """
}

func writeData(_ data: Data, to url: URL) {
    do {
        try data.write(to: url)
    } catch {
        fail("no se pudo escribir \(url.path): \(error.localizedDescription)")
    }
}

func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

func jsonData(_ object: Any) -> Data {
    do {
        var d = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        d.append(0x0a)
        return d
    } catch {
        fail("JSON inválido: \(error)")
    }
}

let jointLabels = ["nose", "neck", "left_shoulder", "right_shoulder", "left_elbow", "right_elbow", "left_wrist",
                   "right_wrist", "left_hip", "right_hip", "left_knee", "right_knee", "left_ankle", "right_ankle", "root"]

/// pose.txt en el formato de `ce regions`: 15 líneas "x y confidence" en el orden de ce_joint.
func poseText(_ pose: Pose, header: String) -> String {
    var s = "# \(header)\n# orden ce_joint: \(jointLabels.joined(separator: " "))\n# x y confidence (0 0 0 = ausente)\n"
    for k in pose.joints {
        s += "\(k.x) \(k.y) \(k.confidence)\n"
    }
    return s
}

func poseJSON(_ pose: Pose) -> [[String: Any]] {
    pose.joints.enumerated().map { i, k in
        ["joint": jointLabels[i], "x": k.x, "y": k.y, "confidence": k.confidence]
    }
}

func quoted(_ path: String) -> String { "\"\(path)\"" }

func evidenceJSON(_ e: PersonEvidence) -> [String: Any] {
    ["kind": e.kind.rawValue, "torso_joints_inside": e.torsoJointsInside, "has_face": e.hasFace,
     "coverage": round3(e.coverage * 1000) / 1000, "aspect": round3(e.aspect), "extent": round3(e.extent),
     "solidity": round3(e.solidity), "height_span": round3(e.heightSpan), "plausible_shape": e.plausibleShape,
     "human_box_xyxy": e.humanBox.map { [Double($0.minX), Double($0.minY), Double($0.maxX), Double($0.maxY)].map(round3) } as Any,
     "human_overlap": round3(e.humanOverlap), "human_fill": round3(e.humanFill)]
}

/// repro.sh de una variante de una sola persona: recalcula cada capa con la CLI
/// `ce` y la compara byte a byte con la que escribió SubjectKit (o, para las
/// candidatas descartadas, el recuento de píxeles que imprime `ce`). Imprime una
/// línea TSV "foto variante paso ok|diff|skip" por paso; exit 1 si algo difiere.
func reproScript(base: String, variant: String, width: Int, height: Int, ppm: String, layer: PersonLayers,
                 steps: [MaskFallback], options: SubjectOptions, garments: Bool = false) -> String {
    let so = options.skinOptions
    func flag(_ b: Bool) -> String { b ? "1" : "0" }
    var s = """
    #!/bin/sh
    # Reproduce las capas de \(base) (\(variant)) con la CLI del motor.
    # uso: sh repro.sh /ruta/a/ce    (escribe repro_*.pgm junto a las capas)
    set -u
    CE=${1:-ce}
    D=$(cd "$(dirname "$0")" && pwd)
    status=0
    row() { printf '%s\\t%s\\t%s\\t%s\\n' "\(base)" "\(variant)" "$1" "$2"; }
    check() { if cmp -s "$1" "$2"; then row "$3" ok; else row "$3" diff; status=1; fi; }
    field() { sed -n "s/.*\\"$1\\": *\\([0-9]*\\).*/\\1/p"; }
    strfield() { sed -n "s/^ *\\"$1\\" *: *\\"\\([0-9a-f]*\\)\\".*/\\1/p" "$2" | head -1; }

    """
    let hasRegion = layer.regionMask != nil
    let decision = layer.regionDecision
    func regionsCall(_ o: RegionOptions, out: String) -> String {
        """
        "$CE" regions --size \(width)x\(height) --mask "$D/person.pgm" --pose "$D/pose.txt" --out "$D/\(out)" \\
            --min-confidence \(o.minConfidence) --torso-margin \(o.torsoMargin) --limb-width \(o.limbWidth) \\
            --upper-arms \(flag(o.includeUpperArms)) --forearms \(flag(o.includeForearms)) --legs \(flag(o.includeLegs)) \\
            --lower-legs \(flag(o.includeLowerLegs))
        """
    }
    /// Candidata descartada: solo se compara el recuento de píxeles que imprime `ce regions`.
    func candidate(_ o: RegionOptions, pixels: Int, step: String) -> String {
        """
        n=$(\(regionsCall(o, out: "repro_candidate.pgm")) | field pixels)
        if [ "$n" = "\(pixels)" ]; then row \(step) ok; else row \(step) diff; status=1; fi

        """
    }
    func exact(_ o: RegionOptions, out: String, against: String, step: String) -> String {
        """
        if \(regionsCall(o, out: out)) > /dev/null; then
          check "$D/\(out)" "$D/\(against)" \(step)
        else
          row \(step) diff; status=1
        fi

        """
    }
    // Muestra con la que se ajustó el modelo final: la última ampliada o la de la cara.
    let finalSample = layer.learnedSampleMasks.isEmpty ? "face_sample.pgm" : "learned_sample_\(layer.learnedSampleMasks.count).pgm"
    func skinCount(sample: String, mask: String, maha: Double, expect: Int, step: String, extraMaskPixels: Int? = nil,
                   threshold: Int? = nil, decided: Bool? = nil) -> String {
        var cond = "[ \"$c\" = \"\(expect)\" ]"
        if let extraMaskPixels { cond += " && [ \"$m\" = \"\(extraMaskPixels)\" ]" }
        if let threshold, let decided {
            cond += " && { [ \"$c\" -ge \(threshold) ] && echo 1 || echo 0; } | grep -qx \"\(decided ? 1 : 0)\""
        }
        return """
        out=$("$CE" skin --image "\(ppm)" --sample "$D/\(sample)" --mask "$D/\(mask)" --out "$D/repro_probe.pgm" \\
            --max-mahalanobis \(maha) --max-excluded 1)
        c=$(printf '%s' "$out" | field candidates); m=$(printf '%s' "$out" | field mask_pixels)
        if \(cond); then row \(step) ok; else row \(step) diff; status=1; fi

        """
    }
    if let d = decision, d.regionPose != nil, let ro = d.regionOptions, let regionPixels = d.poseRegionPixels {
        let silhouette = SubjectExtractor.silhouetteOptions(ro)
        if layer.silhouetteMask != nil {
            s += exact(silhouette, out: "repro_silhouette.pgm", against: "silhouette.pgm", step: "silhouette")
        }
        var withArms = ro, noArms = ro
        withArms.includeUpperArms = true
        noArms.includeUpperArms = false
        if let n = d.sleevePixels {
            // Prueba de mangas sin modelo de piel: recuentos con y sin brazos, torso exacto y
            // brazos parecidos al torso frente al umbral.
            s += candidate(withArms, pixels: d.sleevesKept ? regionPixels : regionPixels + n, step: "sleeves-with")
            s += candidate(noArms, pixels: d.sleevesKept ? regionPixels - n : regionPixels, step: "sleeves-without")
            if let match = d.sleeveMatchPixels, n > 0 {
                var torso = noArms
                torso.includeLegs = false
                torso.includeLowerLegs = false
                s += exact(torso, out: "repro_torso.pgm", against: "sleeve_torso.pgm", step: "sleeve-torso")
                s += skinCount(sample: "sleeve_torso.pgm", mask: "arms.pgm", maha: options.sleeveMatchMahalanobis,
                               expect: match, step: "sleeve-match", extraMaskPixels: n,
                               threshold: SubjectExtractor.sleeveThreshold(armPixels: n, options: options), decided: d.sleevesKept)
            }
        }
        // Zona de las pruebas de piel y del aprendizaje: la región antes de quitar brazos desnudos.
        var zone = ro
        if d.bareArmsDropped { zone.includeUpperArms = true }
        let zonePixels = d.bareArmsDropped ? regionPixels + (d.armPixels ?? 0) : regionPixels
        if let n = d.armPixels, let skin = d.armSkinPixels {
            // Prueba de brazos desnudos: recuentos con y sin brazos, y piel de los brazos con el
            // modelo final (candidatos de `ce skin` sin salvaguarda) frente al umbral.
            s += candidate(withArms, pixels: d.bareArmsDropped ? regionPixels + n : regionPixels, step: "arms-with")
            s += candidate(noArms, pixels: d.bareArmsDropped ? regionPixels : regionPixels - n, step: "arms-without")
            if n > 0 {
                s += skinCount(sample: finalSample, mask: "arms.pgm", maha: so.maxMahalanobis, expect: skin, step: "arms-skin",
                               extraMaskPixels: n, threshold: SubjectExtractor.bareArmsThreshold(armPixels: n, options: options),
                               decided: d.bareArmsDropped)
            }
        }
        if let n = d.legPixels, let skin = d.legSkinPixels {
            var noLegs = zone
            noLegs.includeLegs = false
            noLegs.includeLowerLegs = false
            s += candidate(noLegs, pixels: zonePixels - n, step: "legs-without")
            if n > 0 {
                s += skinCount(sample: "face_sample.pgm", mask: "legs.pgm", maha: so.maxMahalanobis, expect: skin,
                               step: "legs-skin", extraMaskPixels: n)
            }
        }
        if !layer.learnedSampleMasks.isEmpty {
            s += """
            if \(regionsCall(zone, out: "repro_zone.pgm")) > /dev/null; then :; else row learn-zone diff; status=1; fi

            """
            for (k, candidates) in layer.skinLearningPixels.enumerated() {
                let sample = k == 0 ? "face_sample.pgm" : "learned_sample_\(k).pgm"
                s += skinCount(sample: sample, mask: "repro_zone.pgm", maha: options.skinLearningMahalanobis,
                               expect: candidates, step: "learn-\(k + 1)", extraMaskPixels: zonePixels)
            }
        }
        if d.source == .poseRegions {
            s += exact(ro, out: "repro_region.pgm", against: "region.pgm", step: "regions")
        } else {
            s += candidate(ro, pixels: regionPixels, step: "regions-candidate")
        }
        if d.source == .poseSilhouette {
            s += "check \"$D/silhouette.pgm\" \"$D/region.pgm\" region-silhouette\n"
        }
    }
    if let d = decision, d.source == .headCut, let f = d.headCutFraction {
        s += """
        if "$CE" cut-head --mask "$D/person.pgm" --fraction \(f) --out "$D/repro_region.pgm" > /dev/null; then
          check "$D/repro_region.pgm" "$D/region.pgm" cut-head
        else
          row cut-head diff; status=1
        fi

        """
    }
    if layer.steps.contains(.skinExcluded) || layer.steps.contains(.skinGuard) {
        let input = hasRegion ? "region.pgm" : "person.pgm"
        let against = layer.steps.contains(.skinExcluded) ? "skin_excluded.pgm" : "person_final.pgm"
        s += """
        if "$CE" skin --image "\(ppm)" --sample "$D/\(finalSample)" --mask "$D/\(input)" --out "$D/repro_skin.pgm" \\
            --max-mahalanobis \(so.maxMahalanobis) --max-excluded \(so.maxExcludedFraction) > /dev/null; then
          check "$D/repro_skin.pgm" "$D/\(against)" skin
        else
          row skin diff; status=1
        fi

        """
        if let candidates = layer.skinGrowCandidatePixels, layer.steps.contains(.skinExcluded) {
            // Candidatos del crecimiento de la piel en sombra: `ce skin` sobre la máscara tras la
            // exclusión con el umbral de crecimiento, sin salvaguarda.
            s += skinCount(sample: finalSample, mask: "skin_excluded.pgm", maha: options.skinGrowMahalanobis,
                           expect: candidates, step: "skin-grow-candidates")
        }
        if layer.skinGrownPixels > 0 || layer.skinHaloPixels > 0 {
            // El crecimiento conectado y el halo (dilatación de la piel quitada) son geometría de
            // SubjectKit sin comando `ce`.
            if layer.skinGrownPixels > 0 { s += "row skin-grow skip\n" }
            if layer.skinHaloPixels > 0 { s += "row skin-halo skip\n" }
        } else if layer.steps.contains(.skinExcluded) {
            s += "check \"$D/skin_excluded.pgm\" \"$D/person_final.pgm\" skin-halo-none\n"
        }
    } else if layer.skinNote != nil {
        s += "row skin skip\n"
    }
    if steps.contains(.wholePerson) {
        let source = layer.fallbackSource == .poseSilhouette ? "silhouette.pgm" : "person.pgm"
        s += "check \"$D/\(source)\" \"$D/final.pgm\" wholePerson\n"
    } else if !steps.contains(.none) {
        s += "check \"$D/person_final.pgm\" \"$D/final.pgm\" final\n"
    }
    // Regiones de prenda y capa «Prendas» (ADR-011): el mapa sale de `ce garment-regions` con la
    // máscara final y la pose; las capas reducidas, de `ce garments` con ese mapa. Si la pose
    // llevaba caderas estimadas, SubjectKit une la parte de abajo a la de arriba (2 -> 1) antes de
    // comparar (regla de plataforma que la web debe repetir, ADR-010).
    if garments, let g = layer.garmentRegionStats {
        let o = g.options
        s += """
        "$CE" garment-regions --size \(width)x\(height) --mask "$D/final.pgm" --pose "$D/pose.txt" \\
            --out "$D/repro_garment_regions.pgm" --min-confidence \(o.minConfidence) \\
            --torso-margin \(o.torsoMargin) --limb-width \(o.limbWidth) --upper-arms \(flag(o.includeUpperArms)) \\
            --forearms \(flag(o.includeForearms)) --legs \(flag(o.includeLegs)) \\
            --lower-legs \(flag(o.includeLowerLegs)) > /dev/null

        """
        if g.lowerMergedIntoUpper {
            s += """
            LC_ALL=C tr '\\002' '\\001' < "$D/repro_garment_regions.pgm" > "$D/repro_garment_regions_merged.pgm"
            check "$D/repro_garment_regions_merged.pgm" "$D/garment_regions.pgm" garment-regions-estimated-hips

            """
        } else {
            s += "check \"$D/repro_garment_regions.pgm\" \"$D/garment_regions.pgm\" garment-regions\n"
        }
        s += """
        "$CE" garments "\(ppm)" --mask "$D/final.pgm" --regions "$D/garment_regions.pgm" \\
            --n-regions \(garmentMaxRegions) --match --top 3 --debug-dir "$D/repro_garments" --json \\
            > "$D/repro_garments.json"
        check "$D/repro_garments/garments.pgm" "$D/garments.pgm" garments
        check "$D/repro_garments/garments.ppm" "$D/garments.ppm" garments-color
        check "$D/repro_garments/regions.pgm" "$D/garment_regions_reduced.pgm" garment-regions-reduced
        check "$D/repro_garments/regions.ppm" "$D/garment_regions_reduced.ppm" garment-regions-reduced-color
        a=$(strfield hash "$D/repro_garments.json"); b=$(strfield hash "$D/garments.json")
        if [ -n "$a" ] && [ "$a" = "$b" ]; then row garment-hash ok; else row garment-hash diff; status=1; fi

        """
    }
    s += "exit $status\n"
    return s
}

// MARK: - Separación de instancias fusionadas

let personPalette: [[UInt8]] = [[230, 25, 75], [60, 180, 75], [0, 130, 200], [245, 130, 48], [145, 30, 180],
                                [70, 240, 240], [240, 50, 230], [210, 245, 60], [250, 190, 212], [0, 128, 128]]

/// Mapa de ids -> PPM con un color por id (`colorOf`), negro el fondo.
func labelsPPM(_ labels: [UInt8], width: Int, height: Int, colorOf: (Int) -> [UInt8]) -> Data {
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    for (k, l) in labels.enumerated() where l != 0 {
        let c = colorOf(Int(l))
        rgb[3 * k] = c[0]
        rgb[3 * k + 1] = c[1]
        rgb[3 * k + 2] = c[2]
    }
    return PNM.ppm(width: width, height: height, rgb: rgb)
}

func seedLine(_ s: PersonSeed) -> String { "\(s.x0) \(s.y0) \(s.x1) \(s.y1) \(s.halfWidth)" }

func seedComment(_ s: SubjectSeed) -> String {
    var c = "\(s.kind.rawValue)"
    if let p = s.poseIndex { c += " pose \(p)" }
    if let f = s.faceIndex { c += " cara \(f)" }
    c += " ancho de cara \(round3(s.faceWidth)); cuerpo \(s.bodyEvidence.rawValue)"
    return c
}

/// Foto con las personas separadas superpuestas, ejes de semillas y caras (PNG).
func splitOverlayPNG(raster: SubjectRaster, people: [PersonInstance], detection: PeopleDetection, url: URL) {
    let W = raster.width, H = raster.height
    var px = [UInt8](repeating: 0, count: W * H * 4)
    let overlay = MaskOps.instanceOverlay(people, width: W, height: H)
    var colorById: [Int: [UInt8]] = [:]
    for (i, p) in people.enumerated() { colorById[p.id] = personPalette[i % personPalette.count] }
    for y in 0..<H {
        for x in 0..<W {
            let i = y * W + x, src = y * raster.stride + x * 4
            var r = Double(raster.pixels[src]), g = Double(raster.pixels[src + 1]), b = Double(raster.pixels[src + 2])
            if overlay[i] != 0, let c = colorById[Int(overlay[i])] {
                r = 0.45 * r + 0.55 * Double(c[0])
                g = 0.45 * g + 0.55 * Double(c[1])
                b = 0.45 * b + 0.55 * Double(c[2])
            }
            px[4 * i] = UInt8(max(0, min(255, r.rounded())))
            px[4 * i + 1] = UInt8(max(0, min(255, g.rounded())))
            px[4 * i + 2] = UInt8(max(0, min(255, b.rounded())))
            px[4 * i + 3] = 255
        }
    }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    // CoreGraphics tiene el origen abajo: se voltea para dibujar en píxeles del raster.
    ctx.translateBy(x: 0, y: CGFloat(H))
    ctx.scaleBy(x: 1, y: -1)
    let lw = CGFloat(max(2, max(W, H) / 300))
    for f in detection.detectedFaces where !f.boundingBox.isNull && !f.boundingBox.isEmpty {
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.setLineWidth(lw)
        ctx.stroke(f.boundingBox)
    }
    func drawSeed(_ s: SubjectSeed, color: [UInt8], rejected: Bool) {
        let cg = CGColor(red: CGFloat(color[0]) / 255, green: CGFloat(color[1]) / 255, blue: CGFloat(color[2]) / 255,
                         alpha: 1)
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.setLineWidth(lw * 2.5)
        ctx.move(to: CGPoint(x: s.seed.x0, y: s.seed.y0))
        ctx.addLine(to: CGPoint(x: s.seed.x1, y: s.seed.y1))
        ctx.strokePath()
        ctx.setStrokeColor(cg)
        ctx.setLineWidth(lw * 1.5)
        ctx.setLineDash(phase: 0, lengths: rejected ? [lw, lw * 2] : (s.kind == .face ? [lw * 4, lw * 3] : []))
        ctx.move(to: CGPoint(x: s.seed.x0, y: s.seed.y0))
        ctx.addLine(to: CGPoint(x: s.seed.x1, y: s.seed.y1))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setFillColor(cg)
        let r = lw * 3
        ctx.fillEllipse(in: CGRect(x: s.seed.x0 - r, y: s.seed.y0 - r, width: 2 * r, height: 2 * r))
        // Semiancho: segmento horizontal en el punto superior.
        ctx.setLineWidth(lw)
        ctx.move(to: CGPoint(x: s.seed.x0 - s.seed.halfWidth, y: s.seed.y0))
        ctx.addLine(to: CGPoint(x: s.seed.x0 + s.seed.halfWidth, y: s.seed.y0))
        ctx.strokePath()
    }
    for (k, s) in detection.seeds.enumerated() {
        var color: [UInt8] = [255, 255, 255]
        if let split = detection.splits.first(where: { $0.seeds.contains(s) }),
           let j = split.seeds.firstIndex(of: s), let id = split.personIdBySeed[j], let c = colorById[id] {
            color = c
        } else if let iid = detection.seedInstanceIds[k], let c = colorById[iid] {
            color = c
        }
        drawSeed(s, color: color, rejected: false)
    }
    // Semillas de cara sin cuerpo (póster, pantalla): en gris y con guiones cortos.
    for s in detection.faceSeedsWithoutBody {
        drawSeed(s, color: [150, 150, 150], rejected: true)
    }
    // Segmentos de cabeza de las instancias separadas (línea fina).
    for split in detection.splits {
        for (k, seg) in split.segments.enumerated() where k >= split.seeds.count {
            let j = split.segmentOwner[k]
            let c = split.personIdBySeed[j].flatMap { colorById[$0] } ?? [255, 255, 255]
            ctx.setStrokeColor(CGColor(red: CGFloat(c[0]) / 255, green: CGFloat(c[1]) / 255, blue: CGFloat(c[2]) / 255,
                                       alpha: 1))
            ctx.setLineWidth(lw)
            ctx.move(to: CGPoint(x: seg.x0, y: seg.y0))
            ctx.addLine(to: CGPoint(x: seg.x1, y: seg.y1))
            ctx.strokePath()
        }
    }
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        fail("no se pudo escribir \(url.path)")
    }
}

/// Capas de la separación (una vez por foto) y su repro.sh.
func writeSplitLayers(base: String, outURL: URL, raster: SubjectRaster, detection: PeopleDetection) {
    let W = raster.width, H = raster.height
    let people = detection.people
    let visionMap = MaskOps.instanceOverlay(detection.visionInstances, width: W, height: H)
    var visionIndex: [Int: Int] = [:]
    for (i, p) in detection.visionInstances.enumerated() { visionIndex[p.id] = i }
    writeData(PNM.pgm(width: W, height: H, gray: visionMap), to: outURL.appendingPathComponent("\(base).instances_vision.pgm"))
    writeData(labelsPPM(visionMap, width: W, height: H) { personPalette[(visionIndex[$0] ?? 0) % personPalette.count] },
              to: outURL.appendingPathComponent("\(base).instances_vision.ppm"))
    let splitMap = MaskOps.instanceOverlay(people, width: W, height: H)
    var indexById: [Int: Int] = [:]
    for (i, p) in people.enumerated() { indexById[p.id] = i }
    writeData(PNM.pgm(width: W, height: H, gray: splitMap), to: outURL.appendingPathComponent("\(base).instances_split.pgm"))
    writeData(labelsPPM(splitMap, width: W, height: H) { personPalette[(indexById[$0] ?? 0) % personPalette.count] },
              to: outURL.appendingPathComponent("\(base).instances_split.ppm"))
    splitOverlayPNG(raster: raster, people: people, detection: detection,
                    url: outURL.appendingPathComponent("\(base).instances_split.png"))
    var seedsText = "# visionmask \(base): semillas de persona (x0 y0 x1 y1 half_width, formato de `ce split`), raster \(W)x\(H)\n"
    for (k, s) in detection.seeds.enumerated() {
        let inst = detection.seedInstanceIds[k].map { "instancia \($0)" } ?? "sin instancia"
        seedsText += "# \(k): \(seedComment(s)); \(inst)\n\(seedLine(s.seed))\n"
    }
    for (k, s) in detection.faceSeedsWithoutBody.enumerated() {
        seedsText += "# descartada \(k): \(seedComment(s)); sin evidencia corporal\n# \(seedLine(s.seed))\n"
    }
    writeData(Data(seedsText.utf8), to: outURL.appendingPathComponent("\(base).seeds.txt"))
    var repro = """
    #!/bin/sh
    # Reproduce la separación de instancias de \(base) con `ce split` (uso: sh \(base).split_repro.sh /ruta/a/ce).
    set -u
    CE=${1:-ce}
    D=$(cd "$(dirname "$0")" && pwd)
    status=0
    row() { printf '%s\t%s\t%s\t%s\n' "\(base)" "$1" split "$2"; }

    """
    for split in detection.splits {
        let stem = "\(base).split\(split.instanceId)"
        writeData(PNM.pgm(width: W, height: H, gray: split.mask), to: outURL.appendingPathComponent("\(stem).mask.pgm"))
        writeData(PNM.pgm(width: W, height: H, gray: split.labels), to: outURL.appendingPathComponent("\(stem).labels.pgm"))
        var t = "# instancia \(split.instanceId) de Vision: \(split.seeds.count) semillas, \(split.segments.count) segmentos (etiqueta k = línea de datos k)\n"
        for (k, seg) in split.segments.enumerated() {
            let j = split.segmentOwner[k]
            let s = split.seeds[j]
            let part = k < split.seeds.count ? "eje" : "cabeza"
            t += "# etiqueta \(k + 1): \(part) de la semilla \(j) (\(seedComment(s))); píxeles de la semilla \(split.labelPixels[j]); persona \(split.personIdBySeed[j].map(String.init) ?? "-")\n\(seedLine(seg))\n"
        }
        writeData(Data(t.utf8), to: outURL.appendingPathComponent("\(stem).seeds.txt"))
        repro += """
        if "$CE" split --mask "$D/\(stem).mask.pgm" --seeds "$D/\(stem).seeds.txt" --out "$D/\(stem).repro.pgm" > /dev/null \\
            && cmp -s "$D/\(stem).repro.pgm" "$D/\(stem).labels.pgm"; then
          row split\(split.instanceId) ok
        else
          row split\(split.instanceId) diff; status=1
        fi
        rm -f "$D/\(stem).repro.pgm"

        """
    }
    repro += "exit $status\n"
    writeData(Data(repro.utf8), to: outURL.appendingPathComponent("\(base).split_repro.sh"))
}

// MARK: - Variantes

struct Variant {
    let name: String
    let options: SubjectOptions
    /// Sufijo `-garments`: mapa de regiones de prenda y capa «Prendas».
    var garments: Bool { options.computeGarmentRegions }
}

func parseVariant(_ name: String) -> Variant? {
    if name == "none" {
        return Variant(name: name, options: SubjectOptions(mode: .off, region: .wholePerson, adaptiveSkin: false))
    }
    let parts = name.split(separator: "-").map(String.init)
    guard let base = parts.first else { return nil }
    var options = SubjectOptions(mode: .largestPerson, region: .wholePerson, adaptiveSkin: false)
    if base == "allPeople" {
        options.mode = .allPeople
    } else if base == "largest" {
        options.mode = .largestPerson
    } else if base.hasPrefix("selected"), let n = Int(base.dropFirst("selected".count)), n >= 0 {
        options.mode = .selectedPerson
        options.selectedIndex = n
    } else {
        return nil
    }
    var seen = Set<String>()
    for p in parts.dropFirst() {
        guard !seen.contains(p) else { return nil }
        seen.insert(p)
        switch p {
        case "clothing": options.region = .clothing
        case "skin": options.adaptiveSkin = true
        case "ownskin":
            options.adaptiveSkin = true
            options.shareSkinModel = false
        case "garments": options.computeGarmentRegions = true
        default: return nil
        }
    }
    return Variant(name: name, options: options)
}

// MARK: - Capa «Prendas»

/// Variante canónica de prendas (la política de la app): además de
/// `<base>.<variante>.garments.pgm` deja `<base>.garments.pgm`.
let defaultGarmentVariant = "largest-clothing-skin-garments"

/// Color de una etiqueta de región, igual que `region_rgb` de `ce` (ce_cli.c): 0 gris, 1 naranja
/// (arriba), 2 azul (abajo), 3 verde (prenda entera), resto negro.
func regionRGB(_ v: UInt8) -> [UInt8] {
    switch v {
    case 0: [128, 128, 128]
    case 1: [230, 159, 0]
    case 2: [0, 114, 178]
    case 3: [0, 158, 115]
    default: [0, 0, 0]
    }
}

func regionPPM(_ map: [UInt8], width: Int, height: Int) -> Data {
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    for (i, v) in map.enumerated() {
        let c = regionRGB(v)
        rgb[3 * i] = c[0]
        rgb[3 * i + 1] = c[1]
        rgb[3 * i + 2] = c[2]
    }
    return PNM.ppm(width: width, height: height, rgb: rgb)
}

/// Capa «Prendas» de una variante `-garments` con mapa: paleta por prenda con el match de la app
/// (`garmentDebugLayers`, lo mismo que `ce garments --match --top 3 --debug-dir`). Escribe
/// garment_regions.pgm/.ppm (raster), garments.pgm/.ppm y garment_regions_reduced.pgm/.ppm
/// (reducidos, byte a byte como `ce --debug-dir`) y garments.json, y devuelve el bloque JSON
/// del resumen de la variante.
func writeGarmentLayers(dir: URL, store: LayerStore, raster: SubjectRaster, mask: [UInt8], regions: [UInt8],
                        stats: GarmentRegionStats?) -> [String: Any] {
    let W = raster.width, H = raster.height
    store.write(PNM.pgm(width: W, height: H, gray: regions), to: dir.appendingPathComponent("garment_regions.pgm"))
    store.write(regionPPM(regions, width: W, height: H), to: dir.appendingPathComponent("garment_regions.ppm"))
    let layers: GarmentDebugLayers
    do {
        layers = try raster.pixels.withUnsafeBufferPointer { px in
            try mask.withUnsafeBufferPointer { mb in
                try regions.withUnsafeBufferPointer { rb in
                    try garmentDebugLayers(rgba: px, width: W, height: H, stride: raster.stride, mask: mb, regions: rb,
                                           regionCount: garmentMaxRegions)
                }
            }
        }
    } catch {
        return ["error": "\(error)"]
    }
    let rw = layers.layers.debug.reducedWidth, rh = layers.layers.debug.reducedHeight
    store.write(PNM.pgm(width: rw, height: rh, gray: layers.garmentMap), to: dir.appendingPathComponent("garments.pgm"))
    var color = [UInt8](repeating: 0, count: rw * rh * 3)
    for (i, v) in layers.garmentMap.enumerated() where Int(v) < layers.result.garments.count {
        let sw = layers.result.garments[Int(v)].swatch
        color[3 * i] = sw.r
        color[3 * i + 1] = sw.g
        color[3 * i + 2] = sw.b
    }
    store.write(PNM.ppm(width: rw, height: rh, rgb: color), to: dir.appendingPathComponent("garments.ppm"))
    store.write(PNM.pgm(width: rw, height: rh, gray: layers.regionMap),
                to: dir.appendingPathComponent("garment_regions_reduced.pgm"))
    store.write(regionPPM(layers.regionMap, width: rw, height: rh),
                to: dir.appendingPathComponent("garment_regions_reduced.ppm"))
    var pixels = [Int](repeating: 0, count: layers.result.garments.count)
    for v in layers.garmentMap where Int(v) < pixels.count { pixels[Int(v)] += 1 }
    let names = ["none", "upper", "lower", "whole"]
    let garmentsJSON: [[String: Any]] = layers.result.garments.enumerated().map { i, g in
        ["index": i, "region": g.region.rawValue, "region_name": names[g.region.rawValue],
         "region_share": g.regionShare, "n_merged_clusters": g.mergedClusterCount, "hex": g.swatch.hex,
         "rgb": [Int(g.swatch.r), Int(g.swatch.g), Int(g.swatch.b)],
         "lab": [g.swatch.lab.L, g.swatch.lab.a, g.swatch.lab.b], "weight": g.swatch.weight, "pixels": pixels[i]]
    }
    let clusters: [[String: Any]] = layers.layers.debug.clusters.enumerated().map { i, c in
        ["index": i, "hex": c.hex, "lab": [c.lab.L, c.lab.a, c.lab.b], "weight": c.weight, "fate": c.fate.rawValue,
         "final_index": c.finalIndex as Any, "group_head": c.groupHead]
    }
    var regionPixels: [String: Int] = ["none": 0, "upper": 0, "lower": 0, "whole": 0, "outside": 0]
    for v in layers.regionMap {
        let key = Int(v) < names.count ? names[Int(v)] : "outside"
        regionPixels[key, default: 0] += 1
    }
    let summary: [String: Any] = [
        "garments": garmentsJSON,
        "hash": String(format: "%016llx", garmentHash(layers.result.garments)),
        "region_pixels_reduced": regionPixels,
        "region_pixels": ["upper": stats?.upperPixels as Any, "lower": stats?.lowerPixels as Any,
                          "mask": stats?.maskPixels as Any,
                          "lower_merged_into_upper": stats?.lowerMergedIntoUpper as Any,
                          "merged_lower": stats?.mergedLowerPixels as Any] as [String: Any],
        "n_regions": garmentMaxRegions,
        "hits": layers.result.analysis.hits.map { ["id": $0.comboId, "score": $0.score] },
        "ambiguous": layers.result.analysis.ambiguous,
        "reduced_width": rw, "reduced_height": rh,
    ]
    var doc = summary
    doc["clusters"] = clusters
    doc["opts"] = ["garment": ["shade_kL": GarmentOptions.default.shadeKL,
                               "shade_merge_de": GarmentOptions.default.shadeMergeDeltaE,
                               "lit_low_pct": GarmentOptions.default.litLowPercentile,
                               "lit_high_pct": GarmentOptions.default.litHighPercentile,
                               "secondary_min_share": GarmentOptions.default.secondaryMinShare,
                               "max_colors_per_region": Int(GarmentOptions.default.maxColorsPerRegion)],
                   "region": ["min_confidence": stats?.options.minConfidence as Any,
                              "torso_margin": stats?.options.torsoMargin as Any,
                              "limb_width": stats?.options.limbWidth as Any,
                              "upper_arms": stats?.options.includeUpperArms as Any,
                              "forearms": stats?.options.includeForearms as Any,
                              "legs": stats?.options.includeLegs as Any,
                              "lower_legs": stats?.options.includeLowerLegs as Any]]
    writeData(jsonData(doc), to: dir.appendingPathComponent("garments.json"))
    return summary
}

// MARK: - Comando principal

func loadImage(_ path: String) -> (CGImage, Int) {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fail("no se pudo decodificar \(path)")
    }
    var orientation = 1
    if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
       let o = props[kCGImagePropertyOrientation] as? Int {
        orientation = o
    }
    return (image, orientation)
}

func runMask(_ args: [String]) -> Int32 {
    var imagePath: String?
    var outDir: String?
    var variantNames = ["none", "allPeople", "largest", "largest-clothing", "largest-clothing-skin"]
    var maxSide = SubjectRaster.defaultMaxSide
    var layers = false
    var minCoverage: Double? = nil
    var minRegionFraction: Double? = nil
    var bareArmsFraction: Double? = nil
    var maxMahalanobis: Double? = nil
    var learningIterations: Int? = nil
    var learningMahalanobis: Double? = nil
    var haloRadius: Int? = nil
    var sleeveFraction: Double? = nil
    var sleeveMahalanobis: Double? = nil
    var phantomFilter = true
    var acceptShapeOnly = false
    var humanRectangles = true
    var splitInstances = true
    var faceSeedBody = true
    var faceOnlyBody = false
    var minSplitCoverage: Double? = nil
    var growMahalanobis: Double? = nil
    var growRadius: Int? = nil
    var growRatio: Double? = nil
    var i = 0
    while i < args.count {
        let a = args[i]
        func value() -> String {
            guard i + 1 < args.count else { fail("falta el valor de \(a)\n\(usageText())") }
            i += 1
            return args[i]
        }
        switch a {
        case "--out-dir": outDir = value()
        case "--variants": variantNames = value().split(separator: ",").map(String.init)
        case "--max-side":
            guard let v = Int(value()), v >= 1 else { fail("--max-side debe ser un entero >= 1") }
            maxSide = v
        case "--layers": layers = true
        case "--min-coverage":
            guard let v = Double(value()), v.isFinite, v >= 0, v <= 1 else { fail("--min-coverage debe estar en 0...1") }
            minCoverage = v
        case "--min-region-fraction":
            guard let v = Double(value()), v.isFinite, v >= 0, v <= 1 else { fail("--min-region-fraction debe estar en 0...1") }
            minRegionFraction = v
        case "--bare-arms-fraction":
            guard let v = Double(value()), v.isFinite, v >= 0, v <= 1 else { fail("--bare-arms-fraction debe estar en 0...1") }
            bareArmsFraction = v
        case "--max-mahalanobis":
            guard let v = Double(value()), v.isFinite, v >= 0 else { fail("--max-mahalanobis debe ser >= 0") }
            maxMahalanobis = v
        case "--skin-learning-iterations":
            guard let v = Int(value()), (0...SubjectExtractor.maxLearningIterations).contains(v) else {
                fail("--skin-learning-iterations debe estar en 0...\(SubjectExtractor.maxLearningIterations)")
            }
            learningIterations = v
        case "--skin-learning-mahalanobis":
            guard let v = Double(value()), v.isFinite, v >= 0 else { fail("--skin-learning-mahalanobis debe ser >= 0") }
            learningMahalanobis = v
        case "--skin-halo":
            guard let v = Int(value()), (0...SubjectExtractor.maxHaloRadius).contains(v) else {
                fail("--skin-halo debe estar en 0...\(SubjectExtractor.maxHaloRadius)")
            }
            haloRadius = v
        case "--sleeve-fraction":
            guard let v = Double(value()), v.isFinite, v >= 0, v <= 1 else { fail("--sleeve-fraction debe estar en 0...1") }
            sleeveFraction = v
        case "--sleeve-mahalanobis":
            guard let v = Double(value()), v.isFinite, v >= 0 else { fail("--sleeve-mahalanobis debe ser >= 0") }
            sleeveMahalanobis = v
        case "--no-phantom-filter":
            phantomFilter = false
        case "--accept-shape-only":
            acceptShapeOnly = true
        case "--no-human-rectangles":
            humanRectangles = false
        case "--no-split":
            splitInstances = false
        case "--no-face-seed-body":
            faceSeedBody = false
        case "--face-only-body":
            faceOnlyBody = true
        case "--min-split-coverage":
            guard let v = Double(value()), v.isFinite, v >= 0, v <= 1 else { fail("--min-split-coverage debe estar en 0...1") }
            minSplitCoverage = v
        case "--skin-grow-mahalanobis":
            guard let v = Double(value()), v.isFinite, v >= 0 else { fail("--skin-grow-mahalanobis debe ser >= 0") }
            growMahalanobis = v
        case "--skin-grow-radius":
            guard let v = Int(value()), (0...SubjectExtractor.maxGrowRadius).contains(v) else {
                fail("--skin-grow-radius debe estar en 0...\(SubjectExtractor.maxGrowRadius)")
            }
            growRadius = v
        case "--skin-grow-max-ratio":
            guard let v = Double(value()), v.isFinite, v >= 0, v <= 1 else { fail("--skin-grow-max-ratio debe estar en 0...1") }
            growRatio = v
        case "-h", "--help":
            print(usageText())
            return 0
        default:
            if a.hasPrefix("--") || imagePath != nil { fail("argumento no reconocido: \(a)\n\(usageText())") }
            imagePath = a
        }
        i += 1
    }
    guard let imagePath, let outDir else { fail(usageText()) }
    var variants: [Variant] = []
    for n in variantNames {
        guard var v = parseVariant(n) else { fail("variante desconocida: \(n)") }
        do {
            var o = v.options
            if let minCoverage { o.minCoverage = minCoverage }
            if let minRegionFraction { o.minRegionFraction = minRegionFraction }
            if let bareArmsFraction { o.bareArmsSkinFraction = bareArmsFraction }
            if let maxMahalanobis { o.skinOptions.maxMahalanobis = maxMahalanobis }
            if let learningIterations { o.skinLearningIterations = learningIterations }
            if let learningMahalanobis { o.skinLearningMahalanobis = learningMahalanobis }
            if let haloRadius { o.skinHaloRadius = haloRadius }
            if let sleeveFraction { o.sleeveMatchFraction = sleeveFraction }
            if let sleeveMahalanobis { o.sleeveMatchMahalanobis = sleeveMahalanobis }
            if let growMahalanobis { o.skinGrowMahalanobis = growMahalanobis }
            if let growRadius { o.skinGrowRadius = growRadius }
            if let growRatio { o.skinGrowMaxRatio = growRatio }
            o.phantomOptions.enabled = phantomFilter
            o.phantomOptions.acceptShapeOnly = acceptShapeOnly
            o.phantomOptions.humanRectangles = humanRectangles
            o.phantomOptions.requireBodyForFaceOnly = faceOnlyBody
            o.splitOptions.enabled = splitInstances
            o.splitOptions.requireBodyForFaceSeeds = faceSeedBody
            if let minSplitCoverage { o.splitOptions.minSplitCoverage = minSplitCoverage }
            v = Variant(name: v.name, options: o)
        }
        guard !variants.contains(where: { $0.name == n }) else { fail("variante repetida: \(n)") }
        variants.append(v)
    }
    let outURL = URL(fileURLWithPath: outDir, isDirectory: true).standardizedFileURL
    do {
        try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
    } catch {
        fail("no se pudo crear \(outDir): \(error.localizedDescription)")
    }
    let imageURL = URL(fileURLWithPath: imagePath).standardizedFileURL
    let base = imageURL.deletingPathExtension().lastPathComponent
    let (image, orientation) = loadImage(imagePath)
    if orientation != 1 {
        FileHandle.standardError.write(Data("visionmask: aviso: \(imagePath) tiene orientación EXIF \(orientation); se usa la imagen sin rotar (como CGImageSourceCreateImageAtIndex)\n".utf8))
    }
    let raster: SubjectRaster
    do {
        raster = try SubjectRaster.rasterize(image, maxSide: maxSide)
    } catch {
        fail("no se pudo rasterizar: \(error)")
    }
    let W = raster.width, H = raster.height
    let ppmURL = outURL.appendingPathComponent("\(base).ppm")
    writeData(PNM.ppm(width: W, height: H, rgb: raster.rgb), to: ppmURL)

    var exitCode: Int32 = 0
    var visionError: String? = nil
    var detection: PeopleDetection? = nil
    let needsVision = variants.contains { $0.options.mode != .off }
    if needsVision {
        do {
            var phantom = PhantomOptions.default
            phantom.enabled = phantomFilter
            phantom.acceptShapeOnly = acceptShapeOnly
            phantom.humanRectangles = humanRectangles
            phantom.requireBodyForFaceOnly = faceOnlyBody
            var split = SplitOptions.default
            split.enabled = splitInstances
            split.requireBodyForFaceSeeds = faceSeedBody
            if let minSplitCoverage { split.minSplitCoverage = minSplitCoverage }
            detection = try SubjectExtractor.detectPeopleDetailed(in: image, rasterWidth: W, rasterHeight: H,
                                                                  phantomOptions: phantom, splitOptions: split)
        } catch {
            visionError = "\(error)"
            exitCode = 1
        }
    }
    let people = detection?.people ?? []

    var peopleJSON: [[String: Any]] = []
    for (idx, p) in people.enumerated() {
        let face = detection?.faces[idx]
        var entry: [String: Any] = [
            "index": idx, "id": p.id, "coverage": p.coverage,
            "bbox_xyxy": [Int(p.bbox.minX), Int(p.bbox.minY), Int(p.bbox.maxX), Int(p.bbox.maxY)],
            "mask_pixels": MaskOps.stats(p.mask, width: W, height: H).count,
            "pose": p.pose != nil, "face": face != nil, "split_from": p.splitFrom as Any,
            "face_bbox_xyxy": p.faceBox.map { [Double($0.minX), Double($0.minY), Double($0.maxX), Double($0.maxY)].map(round3) } as Any,
            "face_sample_pixels": p.faceSampleMask.map { MaskOps.nonZero($0) } ?? 0,
        ]
        if let e = detection?.evidence[idx] { entry["evidence"] = evidenceJSON(e) }
        // Referencia de piel de la persona (independiente de la variante): el modelo
        // del motor ajustado a su muestra de cara. La usa `visionmask report` para
        // medir cuánto peso de la paleta cae cerca de la piel.
        if let sample = p.faceSampleMask {
            do {
                let m = try raster.pixels.withUnsafeBufferPointer { px in
                    try fitSkinModel(rgba: px, width: W, height: H, stride: raster.stride, sampleMask: sample)
                }
                entry["skin_reference"] = ["n": m.sampleCount, "lab": [m.mean.L, m.mean.a, m.mean.b]]
            } catch {
                entry["skin_reference"] = ["error": "\(error)"]
            }
        }
        if let pose = p.pose {
            entry["pose_points"] = poseJSON(pose)
        }
        if let face {
            if let polys = FaceSample.polygons(face) {
                entry["face_sample_polygons"] = polys.map { $0.map { [round3(Double($0.x)), round3(Double($0.y))] } }
            }
            entry["face_landmarks"] = [
                "left_eye": face.leftEye, "right_eye": face.rightEye, "left_eyebrow": face.leftEyebrow,
                "right_eyebrow": face.rightEyebrow, "outer_lips": face.outerLips, "face_contour": face.faceContour,
            ].mapValues { $0.map { [round3(Double($0.x)), round3(Double($0.y))] } }
            entry["face_bbox_xyxy"] = [Double(face.boundingBox.minX), Double(face.boundingBox.minY),
                                       Double(face.boundingBox.maxX), Double(face.boundingBox.maxY)].map(round3)
        }
        peopleJSON.append(entry)
    }

    if layers, let detection {
        writeSplitLayers(base: base, outURL: outURL, raster: raster, detection: detection)
    }
    var seedsJSON: [[String: Any]] = []
    var splitsJSON: [[String: Any]] = []
    var facelessJSON: [[String: Any]] = []
    if let detection {
        for (k, sd) in detection.seeds.enumerated() {
            seedsJSON.append(["kind": sd.kind.rawValue, "x0": sd.seed.x0, "y0": sd.seed.y0, "x1": sd.seed.x1,
                              "y1": sd.seed.y1, "half_width": sd.seed.halfWidth, "face_width": sd.faceWidth,
                              "body_evidence": sd.bodyEvidence.rawValue,
                              "pose_index": sd.poseIndex as Any, "face_index": sd.faceIndex as Any,
                              "instance": detection.seedInstanceIds[k] as Any,
                              "membership": detection.visionInstances.compactMap { inst -> [String: Any]? in
                                  let m = PersonSplitter.membership(sd, mask: inst.mask, width: W, height: H)
                                  guard m.touches || m.axisInside > 0 else { return nil }
                                  return ["instance": inst.id, "counts": m.counts, "touches": m.touches,
                                          "face_inside": m.faceInside, "top_inside": m.topInside,
                                          "top_distance": m.topDistance.isFinite ? round3(m.topDistance) : NSNull(),
                                          "axis_inside": round3(m.axisInside)]
                              }])
        }
        for split in detection.splits {
            splitsJSON.append(["instance": split.instanceId, "step": split.step.rawValue,
                               "segments": split.segments.map { [$0.x0, $0.y0, $0.x1, $0.y1, $0.halfWidth] },
                               "segment_owner": split.segmentOwner,
                               "seeds": split.seeds.map { ["kind": $0.kind.rawValue, "x0": $0.seed.x0, "y0": $0.seed.y0,
                                                           "x1": $0.seed.x1, "y1": $0.seed.y1,
                                                           "half_width": $0.seed.halfWidth] },
                               "label_pixels": split.labelPixels, "person_ids": split.personIds,
                               "person_id_by_seed": split.personIdBySeed.map { $0 as Any }])
        }
        for sd in detection.faceSeedsWithoutBody {
            facelessJSON.append(["x0": sd.seed.x0, "y0": sd.seed.y0, "x1": sd.seed.x1, "y1": sd.seed.y1,
                                 "half_width": sd.seed.halfWidth, "face_width": sd.faceWidth,
                                 "face_index": sd.faceIndex as Any,
                                 "face_bbox_xyxy": sd.face.map { f in
                                     [Double(f.boundingBox.minX), Double(f.boundingBox.minY),
                                      Double(f.boundingBox.maxX), Double(f.boundingBox.maxY)].map(round3)
                                 } as Any])
        }
    }

    var batchLines: [String] = []
    var garmentLines: [String] = []
    let layerStore = LayerStore()
    var variantsJSON: [[String: Any]] = []
    let instancesColors: [[UInt8]] = [[0, 0, 0], [230, 25, 75], [60, 180, 75], [0, 130, 200], [245, 130, 48],
                                      [145, 30, 180], [70, 240, 240], [240, 50, 230], [210, 245, 60]]
    for v in variants {
        let result: SubjectMaskResult
        do {
            if visionError != nil && v.options.mode != .off {
                let empty = [UInt8](repeating: 0, count: W * H)
                result = SubjectMaskResult(width: W, height: H, people: [], chosenIndex: nil, mask: nil,
                                           steps: [.visionUnavailable], timings: [:], maskCoverage: 0,
                                           layers: SubjectLayers(width: W, height: H, persons: [],
                                                                 allPeopleOverlay: empty, finalMask: nil))
            } else {
                result = try raster.pixels.withUnsafeBufferPointer { px in
                    if let detection, v.options.mode != .off {
                        return try SubjectExtractor.mask(detection: detection, rgba: px, width: W, height: H,
                                                         stride: raster.stride, options: v.options)
                    }
                    return try SubjectExtractor.mask(people: people, rgba: px, width: W, height: H, stride: raster.stride,
                                                     options: v.options)
                }
            }
        } catch {
            FileHandle.standardError.write(Data("visionmask: \(base) \(v.name): error del motor: \(error)\n".utf8))
            exitCode = 1
            variantsJSON.append(["name": v.name, "error": "\(error)"])
            continue
        }
        var maskPath: String? = nil
        var regionsPath: String? = nil
        if let m = result.mask {
            let url = outURL.appendingPathComponent("\(base).\(v.name).pgm")
            writeData(PNM.pgm(width: W, height: H, gray: m), to: url)
            maskPath = url.path
            // Con mapa de regiones la variante va al lote de prendas ("imagen mascara regiones",
            // `ce batch --garments`); sin pose (mapa nil) sigue el camino clásico, como la app.
            if v.garments, let map = result.garmentRegions {
                let regionsURL = outURL.appendingPathComponent("\(base).\(v.name).garments.pgm")
                layerStore.write(PNM.pgm(width: W, height: H, gray: map), to: regionsURL)
                layerStore.write(regionPPM(map, width: W, height: H),
                                 to: outURL.appendingPathComponent("\(base).\(v.name).garments.ppm"))
                // La variante canónica deja además <base>.garments.pgm/.ppm (enlace duro, sin copiar).
                if v.name == defaultGarmentVariant {
                    layerStore.write(PNM.pgm(width: W, height: H, gray: map),
                                     to: outURL.appendingPathComponent("\(base).garments.pgm"))
                    layerStore.write(regionPPM(map, width: W, height: H),
                                     to: outURL.appendingPathComponent("\(base).garments.ppm"))
                }
                regionsPath = regionsURL.path
                garmentLines.append("\(quoted(ppmURL.path)) \(quoted(url.path)) \(quoted(regionsURL.path))")
            } else {
                batchLines.append("\(quoted(ppmURL.path)) \(quoted(url.path))")
            }
        } else {
            batchLines.append(quoted(ppmURL.path))
        }
        var personsJSON: [[String: Any]] = []
        for pl in result.layers.persons {
            var pj: [String: Any] = [
                "index": pl.personIndex, "id": pl.instanceId, "steps": pl.steps.map(\.rawValue),
                "person_pixels": MaskOps.nonZero(pl.personMask),
                "region_pixels": pl.regionMask.map { MaskOps.nonZero($0) } as Any,
                "face_sample_pixels": pl.faceSampleMask.map { MaskOps.nonZero($0) } as Any,
                "skin_removed_pixels": pl.skinExcludedPixels,
                "final_pixels": MaskOps.nonZero(pl.finalMask),
                "skin_note": pl.skinNote as Any,
                "used_in_mask": pl.usedInMask, "skin_sample_source": pl.skinSampleSource as Any,
                "silhouette_pixels": pl.silhouetteMask.map { MaskOps.nonZero($0) } as Any,
                "fallback_source": pl.fallbackSource?.rawValue as Any,
                "skin_learning_candidates": pl.skinLearningPixels,
                "learned_sample_pixels": pl.learnedSampleMasks.map { MaskOps.nonZero($0) },
                "skin_halo_pixels": pl.skinHaloPixels,
                "skin_grow_candidates": pl.skinGrowCandidatePixels as Any,
                "skin_grown_pixels": pl.skinGrownPixels,
                "garment_region_pixels": pl.garmentRegionStats.map {
                    ["upper": $0.upperPixels, "lower": $0.lowerPixels, "mask": $0.maskPixels,
                     "lower_merged_into_upper": $0.lowerMergedIntoUpper, "merged_lower": $0.mergedLowerPixels]
                } as Any,
            ]
            if let d = pl.regionDecision {
                var dj: [String: Any] = [
                    "source": d.source.rawValue, "body_pixels": d.bodyPixels, "required_pixels": d.requiredPixels,
                    "pose_region_pixels": d.poseRegionPixels as Any, "silhouette_pixels": d.silhouettePixels as Any,
                    "region_pixels": d.regionPixels, "hips_estimated": d.hipsEstimated,
                    "head_cut_fraction": d.headCutFraction as Any, "upper_arms_dropped": d.upperArmsDropped,
                    "arm_pixels": d.armPixels as Any, "arm_skin_pixels": d.armSkinPixels as Any,
                    "bare_arms_dropped": d.bareArmsDropped,
                    "leg_pixels": d.legPixels as Any, "leg_skin_pixels": d.legSkinPixels as Any,
                    "sleeve_pixels": d.sleevePixels as Any, "sleeve_match_pixels": d.sleeveMatchPixels as Any,
                    "sleeves_kept": d.sleevesKept,
                    "include_upper_arms": d.regionOptions.map { $0.includeUpperArms } as Any,
                ]
                if d.hipsEstimated, let rp = d.regionPose { dj["region_pose_points"] = poseJSON(rp) }
                pj["region_decision"] = dj
            }
            if let m = pl.skinModel {
                pj["skin_model"] = ["n": m.sampleCount, "mean": [m.mean.L, m.mean.a, m.mean.b],
                                    "cov": m.covariance, "inv_cov": m.inverseCovariance]
            }
            personsJSON.append(pj)
        }
        var layersPath: String? = nil
        var garmentSummary: [String: Any]? = nil
        if layers && v.options.mode != .off {
            let dir = outURL.appendingPathComponent("\(base).\(v.name).layers", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                fail("no se pudo crear \(dir.path): \(error.localizedDescription)")
            }
            layersPath = dir.path
            let ps = result.layers.persons
            func put(_ name: String, _ masks: [[UInt8]]) {
                if let u = MaskOps.union(masks) {
                    layerStore.write(PNM.pgm(width: W, height: H, gray: u), to: dir.appendingPathComponent(name))
                }
            }
            put("person_vision.pgm", ps.map { result.people[$0.personIndex].mask })
            put("person.pgm", ps.map(\.personMask))
            put("region.pgm", ps.compactMap(\.regionMask))
            put("silhouette.pgm", ps.compactMap(\.silhouetteMask))
            put("arms.pgm", ps.compactMap(\.armsMask))
            put("legs.pgm", ps.compactMap(\.legsMask))
            put("sleeve_torso.pgm", ps.compactMap(\.sleeveTorsoMask))
            put("skin_excluded.pgm", ps.compactMap(\.skinExcludedMask))
            put("skin_grown.pgm", ps.compactMap(\.skinGrownMask))
            let learnedCount = ps.map(\.learnedSampleMasks.count).max() ?? 0
            for k in 0..<learnedCount {
                put("learned_sample_\(k + 1).pgm", ps.compactMap { k < $0.learnedSampleMasks.count ? $0.learnedSampleMasks[k] : nil })
            }
            put("face_sample.pgm", ps.compactMap(\.faceSampleMask))
            put("skin_removed.pgm", ps.compactMap(\.skinRemovedMask))
            put("person_final.pgm", ps.map(\.finalMask))
            if let m = result.mask { put("final.pgm", [m]) }
            if v.garments {
                if let map = result.garmentRegions, let m = result.mask {
                    garmentSummary = writeGarmentLayers(dir: dir, store: layerStore, raster: raster, mask: m,
                                                        regions: map, stats: ps.first?.garmentRegionStats)
                } else {
                    // allPeople (un mapa por persona) o sin pose: solo los mapas que haya.
                    for pl in ps {
                        guard let map = pl.garmentRegions else { continue }
                        let suffix = ps.count > 1 ? "_\(pl.personIndex)" : ""
                        layerStore.write(PNM.pgm(width: W, height: H, gray: map),
                                         to: dir.appendingPathComponent("garment_regions\(suffix).pgm"))
                        layerStore.write(regionPPM(map, width: W, height: H),
                                         to: dir.appendingPathComponent("garment_regions\(suffix).ppm"))
                    }
                }
            }
            let overlay = result.layers.allPeopleOverlay
            layerStore.write(PNM.pgm(width: W, height: H, gray: overlay), to: dir.appendingPathComponent("instances.pgm"))
            var rgb = [UInt8](repeating: 0, count: W * H * 3)
            for (k, label) in overlay.enumerated() {
                let c = instancesColors[Int(label) % instancesColors.count]
                rgb[3 * k] = c[0]
                rgb[3 * k + 1] = c[1]
                rgb[3 * k + 2] = c[2]
            }
            layerStore.write(PNM.ppm(width: W, height: H, rgb: rgb), to: dir.appendingPathComponent("instances.ppm"))
            var wrotePose = false
            for pl in ps {
                guard let visionPose = pl.pose else { continue }
                let pose = pl.regionDecision?.regionPose ?? visionPose
                let estimated = pl.regionDecision?.hipsEstimated == true
                let header = "visionmask \(base) \(v.name): persona \(pl.personIndex) (instancia \(pl.instanceId)), raster \(W)x\(H)"
                    + (estimated ? "; caderas y raíz ESTIMADAS (plano medio), rodillas y tobillos borrados" : "")
                let text = Data(poseText(pose, header: header).utf8)
                let visionText = Data(poseText(visionPose, header: header.components(separatedBy: ";")[0] + "; pose de Vision").utf8)
                if !wrotePose {
                    writeData(text, to: dir.appendingPathComponent("pose.txt"))
                    if estimated { writeData(visionText, to: dir.appendingPathComponent("pose_vision.txt")) }
                    wrotePose = true
                }
                if v.options.mode == .allPeople {
                    writeData(text, to: dir.appendingPathComponent("pose_\(pl.personIndex).txt"))
                    if estimated { writeData(visionText, to: dir.appendingPathComponent("pose_vision_\(pl.personIndex).txt")) }
                }
            }
            if let pl = ps.first, v.options.mode != .allPeople {
                let script = reproScript(base: base, variant: v.name, width: W, height: H, ppm: ppmURL.path,
                                         layer: pl, steps: result.steps, options: v.options,
                                         garments: v.garments && result.garmentRegions != nil)
                writeData(Data(script.utf8), to: dir.appendingPathComponent("repro.sh"))
            }
        }
        variantsJSON.append([
            "name": v.name, "mode": v.options.mode.rawValue, "region": v.options.region.rawValue,
            "adaptive_skin": v.options.adaptiveSkin, "selected_index": v.options.selectedIndex as Any,
            "min_coverage": v.options.minCoverage, "min_region_fraction": v.options.minRegionFraction,
            "bare_arms_skin_fraction": v.options.bareArmsSkinFraction,
            "max_mahalanobis": v.options.skinOptions.maxMahalanobis,
            "skin_halo_radius": v.options.skinHaloRadius, "skin_grow_mahalanobis": v.options.skinGrowMahalanobis,
            "skin_grow_radius": v.options.skinGrowRadius, "skin_grow_max_ratio": v.options.skinGrowMaxRatio,
            "garments_variant": v.garments,
            "garment_regions": regionsPath as Any,
            "garment_layers": garmentSummary as Any,
            "mask": maskPath as Any, "mask_coverage": result.maskCoverage,
            "mask_pixels": result.mask.map { MaskOps.nonZero($0) } as Any,
            "chosen_index": result.chosenIndex as Any, "steps": result.steps.map(\.rawValue),
            "timings_ms": result.timings.mapValues(round3), "persons": personsJSON, "layers": layersPath as Any,
        ])
    }
    let batchURL = outURL.appendingPathComponent("\(base).batch.txt")
    writeData(Data((batchLines.joined(separator: "\n") + "\n").utf8), to: batchURL)
    var garmentBatchURL: URL? = nil
    if !garmentLines.isEmpty {
        let url = outURL.appendingPathComponent("\(base).garments.txt")
        writeData(Data((garmentLines.joined(separator: "\n") + "\n").utf8), to: url)
        garmentBatchURL = url
    }

    let summary: [String: Any] = [
        "tool": "visionmask", "engine": colorEngineVersion, "dict_version": dictionaryVersion,
        "image": imageURL.path, "base": base, "orientation": orientation,
        "source_width": image.width, "source_height": image.height, "max_side": maxSide,
        "width": W, "height": H, "stride": raster.stride, "raster": ppmURL.path, "batch": batchURL.path,
        "garments_batch": garmentBatchURL?.path as Any,
        "vision": ["available": visionError == nil, "error": visionError as Any,
                   "warnings": detection?.warnings ?? [],
                   "unassigned_poses": detection?.unassignedPoses ?? 0,
                   "unassigned_faces": detection?.unassignedFaces ?? 0] as [String: Any],
        "timings_detect_ms": (detection?.timings ?? [:]).mapValues(round3),
        "people_count": people.count, "people": peopleJSON, "variants": variantsJSON,
        "discarded_people": detection?.discardedPeople ?? 0,
        "phantom_filter": phantomFilter,
        "phantom_options": ["accept_shape_only": acceptShapeOnly, "human_rectangles": humanRectangles,
                            "require_body_for_face_only": faceOnlyBody] as [String: Any],
        "human_rectangles_requested": detection?.humanRectanglesRequested ?? false,
        "human_rectangles_xyxy": (detection?.humanRectangles ?? []).map {
            [Double($0.minX), Double($0.minY), Double($0.maxX), Double($0.maxY)].map(round3)
        },
        "rejected_phantoms": (detection?.rejectedPhantoms ?? []).map { r -> [String: Any] in
            ["id": r.instance.id, "coverage": r.instance.coverage,
             "bbox_xyxy": [Int(r.instance.bbox.minX), Int(r.instance.bbox.minY), Int(r.instance.bbox.maxX), Int(r.instance.bbox.maxY)],
             "pose": r.instance.pose != nil, "evidence": evidenceJSON(r.evidence)]
        },
        "vision_instances": (detection?.visionInstances ?? []).map { ["id": $0.id, "coverage": $0.coverage,
                                                                      "bbox_xyxy": [Int($0.bbox.minX), Int($0.bbox.minY), Int($0.bbox.maxX), Int($0.bbox.maxY)]] as [String: Any] },
        "vision_instance_count": detection?.visionInstances.count ?? 0,
        "absorbed_instances": detection?.absorbedInstances ?? [],
        "poses_count": detection?.poses.count ?? 0,
        "split_options": ["enabled": splitInstances, "require_body_for_face_seeds": faceSeedBody,
                          "min_split_coverage": minSplitCoverage ?? SplitOptions.default.minSplitCoverage] as [String: Any],
        "faces_detected": (detection?.detectedFaces ?? []).map { f -> [String: Any] in
            ["bbox_xyxy": [Double(f.boundingBox.minX), Double(f.boundingBox.minY), Double(f.boundingBox.maxX),
                           Double(f.boundingBox.maxY)].map(round3),
             "landmarks": FaceSample.polygons(f) != nil]
        },
        "all_poses": (detection?.poses ?? []).map(poseJSON),
        "seeds": seedsJSON, "splits": splitsJSON, "face_seeds_without_body": facelessJSON,
        "orphan_poses": (detection?.orphanPoses ?? []).map(poseJSON),
        "orphan_faces": (detection?.orphanFaces ?? []).map { f -> [String: Any] in
            ["face_bbox_xyxy": [Double(f.boundingBox.minX), Double(f.boundingBox.minY), Double(f.boundingBox.maxX),
                                Double(f.boundingBox.maxY)].map(round3),
             "landmarks": FaceSample.polygons(f) != nil]
        },
    ]
    writeData(jsonData(summary), to: outURL.appendingPathComponent("\(base).json"))
    let stepsSummary = variantsJSON.map { v -> String in
        let steps = (v["steps"] as? [String])?.joined(separator: "+") ?? "error"
        let cov = (v["mask_coverage"] as? Double).map { String(format: "%.3f", $0) } ?? "-"
        return "\(v["name"] ?? "?")=\(steps)(\(cov))"
    }.joined(separator: " ")
    let visionCount = detection?.visionInstances.count ?? 0
    let splitSummary = (detection?.splits ?? []).map { "\($0.instanceId)->\($0.personIds.count)(\($0.step.rawValue))" }
        .joined(separator: ",")
    let faceless = detection?.faceSeedsWithoutBody.count ?? 0
    print("\(base): \(W)x\(H) vision=\(visionCount) personas=\(people.count) semillas=\(detection?.seeds.count ?? 0)" +
          "\(splitSummary.isEmpty ? "" : " separadas=" + splitSummary)" +
          "\(faceless > 0 ? " caras-sin-cuerpo=\(faceless)" : "") fantasmas=\(detection?.rejectedPhantoms.count ?? 0) \(stepsSummary)")
    if let visionError {
        FileHandle.standardError.write(Data("visionmask: Vision no disponible: \(visionError)\n".utf8))
    }
    return exitCode
}

// MARK: - Entrada

let argv = Array(CommandLine.arguments.dropFirst())
if argv.isEmpty {
    fail(usageText())
}
if argv[0] == "report" {
    exit(runReport(Array(argv.dropFirst())))
}
exit(runMask(argv))
