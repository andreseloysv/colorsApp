// visionmask: CLI de macOS que produce, para una foto, el raster exacto que ve
// el motor en la app y las máscaras de SubjectKit por variante, con sus capas,
// para analizarlas con `ce batch` (capa 4) y reproducir cada paso con
// `ce regions` / `ce cut-head` / `ce skin`.
//
//   visionmask <imagen.png|jpg> --out-dir DIR [--variants LISTA] [--max-side 1024] [--layers]
//              [--min-coverage F] [--min-region-fraction F] [--bare-arms-fraction F] [--max-mahalanobis F]
//   visionmask report --masks-dir DIR --batch lote.jsonl --expected expected.json --out report.md
//                     [--repro repro.tsv]
//
// Variantes (separadas por comas; defecto none,allPeople,largest,largest-clothing,largest-clothing-skin):
//   none                      sin máscara (no escribe .pgm)
//   <base>[-clothing][-skin|-ownskin]  base = allPeople | largest | selected<N> (N = índice en people);
//                             -clothing = solo ropa (pose, silueta o corte de cabeza); -skin = piel
//                             adaptativa (compartida si la persona no tiene cara); -ownskin = solo la
//                             muestra de la propia cara.
//
// Salidas en DIR (base = nombre del fichero sin extensión):
//   <base>.ppm                  raster RGB (CGContext sRGB noneSkipLast, lado mayor <= max-side)
//   <base>.<variante>.pgm       máscara final de la variante (si no es nil)
//   <base>.batch.txt            una línea "imagen [mascara]" por variante (entrada de ce batch)
//   <base>.json                 personas, pasos y tiempos por variante
//   <base>.<variante>.layers/   (--layers, variantes con personas) capas del raster:
//       person_vision.pgm máscara de instancia de Vision tal cual (blanda; unión en allPeople)
//       person.pgm        persona binaria (>= 128 -> 255): entrada de la cadena y de `ce regions`
//       region.pgm        región de ropa antes de la piel (regiones o silueta de la pose, o headCut)
//       silhouette.pgm    silueta de la pose (persona binaria ∩ esqueleto ancho, sin cabeza ni manos):
//                         referencia del 15 % y respaldo con pose en vez de la instancia de Vision
//       arms.pgm          brazos probados en la prueba de brazos desnudos (regiones con brazos − sin brazos)
//       face_sample.pgm   muestra de piel de la cara (solo con -skin y cara)
//       skin_removed.pgm  255 donde se quitó piel (sin salvaguarda)
//       person_final.pgm  salida de la cadena de la persona antes de la cobertura mínima
//       final.pgm         máscara que recibe el motor (== <base>.<variante>.pgm)
//       instances.pgm     id de instancia por píxel (0 = fondo); instances.ppm en color
//       pose.txt          pose que recibió el motor, en el formato de `ce regions` (con caderas
//                         estimadas en planos medios; pose_vision.txt = la de Vision si difiere;
//                         pose_<i>.txt por persona en allPeople)
//       repro.sh          (una persona) recalcula cada capa con `ce` y la compara con cmp
//   Los ficheros idénticos entre variantes se escriben una vez y se enlazan (enlace duro).
// Exit: 0 ok, 1 Vision o el motor fallaron, 2 uso o E/S.
import CoreGraphics
import Foundation
import ImageIO
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
      visionmask <imagen.png|jpg> --out-dir DIR [--variants none,allPeople,largest,largest-clothing,largest-clothing-skin]
                 [--max-side 1024] [--layers] [--min-coverage 0.0005] [--min-region-fraction 0.15]
                 [--bare-arms-fraction 0.25] [--max-mahalanobis 2.5]
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

/// repro.sh de una variante de una sola persona: recalcula cada capa con la CLI
/// `ce` y la compara byte a byte con la que escribió SubjectKit (o, para las
/// candidatas descartadas, el recuento de píxeles que imprime `ce`). Imprime una
/// línea TSV "foto variante paso ok|diff|skip" por paso; exit 1 si algo difiere.
func reproScript(base: String, variant: String, width: Int, height: Int, ppm: String, layer: PersonLayers,
                 steps: [MaskFallback], options: SubjectOptions) -> String {
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
    if let d = decision, d.regionPose != nil, let ro = d.regionOptions, let regionPixels = d.poseRegionPixels {
        let silhouette = SubjectExtractor.silhouetteOptions(ro)
        if layer.silhouetteMask != nil {
            s += exact(silhouette, out: "repro_silhouette.pgm", against: "silhouette.pgm", step: "silhouette")
        }
        if let n = d.armPixels, let skin = d.armSkinPixels {
            // Prueba de brazos desnudos: recuentos con y sin brazos, y piel de los brazos
            // (candidatos de `ce skin` sin salvaguarda) frente al umbral.
            var withArms = ro, noArms = ro
            withArms.includeUpperArms = true
            noArms.includeUpperArms = false
            s += candidate(withArms, pixels: d.bareArmsDropped ? regionPixels + n : regionPixels, step: "arms-with")
            s += candidate(noArms, pixels: d.bareArmsDropped ? regionPixels : regionPixels - n, step: "arms-without")
            if n > 0 {
                let threshold = SubjectExtractor.bareArmsThreshold(armPixels: n, options: options)
                s += """
                out=$("$CE" skin --image "\(ppm)" --sample "$D/face_sample.pgm" --mask "$D/arms.pgm" --out "$D/repro_arms_skin.pgm" \\
                    --max-mahalanobis \(so.maxMahalanobis) --max-excluded 1)
                c=$(printf '%s' "$out" | field candidates); m=$(printf '%s' "$out" | field mask_pixels)
                if [ "$c" = "\(skin)" ] && [ "$m" = "\(n)" ] && { [ "$c" -ge \(threshold) ] && echo 1 || echo 0; } | grep -qx "\(d.bareArmsDropped ? 1 : 0)"; then
                  row arms-skin ok
                else
                  row arms-skin diff; status=1
                fi

                """
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
        s += """
        if "$CE" skin --image "\(ppm)" --sample "$D/face_sample.pgm" --mask "$D/\(input)" --out "$D/repro_skin.pgm" \\
            --max-mahalanobis \(so.maxMahalanobis) --max-excluded \(so.maxExcludedFraction) > /dev/null; then
          check "$D/repro_skin.pgm" "$D/person_final.pgm" skin
        else
          row skin diff; status=1
        fi

        """
    } else if layer.skinNote != nil {
        s += "row skin skip\n"
    }
    if steps.contains(.wholePerson) {
        let source = layer.fallbackSource == .poseSilhouette ? "silhouette.pgm" : "person.pgm"
        s += "check \"$D/\(source)\" \"$D/final.pgm\" wholePerson\n"
    } else if !steps.contains(.none) {
        s += "check \"$D/person_final.pgm\" \"$D/final.pgm\" final\n"
    }
    s += "exit $status\n"
    return s
}

// MARK: - Variantes

struct Variant {
    let name: String
    let options: SubjectOptions
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
        default: return nil
        }
    }
    return Variant(name: name, options: options)
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
        if minCoverage != nil || minRegionFraction != nil || bareArmsFraction != nil || maxMahalanobis != nil {
            var o = v.options
            if let minCoverage { o.minCoverage = minCoverage }
            if let minRegionFraction { o.minRegionFraction = minRegionFraction }
            if let bareArmsFraction { o.bareArmsSkinFraction = bareArmsFraction }
            if let maxMahalanobis { o.skinOptions.maxMahalanobis = maxMahalanobis }
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
            detection = try SubjectExtractor.detectPeopleDetailed(in: image, rasterWidth: W, rasterHeight: H)
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
            "pose": p.pose != nil, "face": face != nil,
            "face_sample_pixels": p.faceSampleMask.map { MaskOps.nonZero($0) } ?? 0,
        ]
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

    var batchLines: [String] = []
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
                    try SubjectExtractor.mask(people: people, rgba: px, width: W, height: H, stride: raster.stride,
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
        if let m = result.mask {
            let url = outURL.appendingPathComponent("\(base).\(v.name).pgm")
            writeData(PNM.pgm(width: W, height: H, gray: m), to: url)
            maskPath = url.path
            batchLines.append("\(quoted(ppmURL.path)) \(quoted(url.path))")
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
            ]
            if let d = pl.regionDecision {
                var dj: [String: Any] = [
                    "source": d.source.rawValue, "body_pixels": d.bodyPixels, "required_pixels": d.requiredPixels,
                    "pose_region_pixels": d.poseRegionPixels as Any, "silhouette_pixels": d.silhouettePixels as Any,
                    "region_pixels": d.regionPixels, "hips_estimated": d.hipsEstimated,
                    "head_cut_fraction": d.headCutFraction as Any, "upper_arms_dropped": d.upperArmsDropped,
                    "arm_pixels": d.armPixels as Any, "arm_skin_pixels": d.armSkinPixels as Any,
                    "bare_arms_dropped": d.bareArmsDropped,
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
            put("face_sample.pgm", ps.compactMap(\.faceSampleMask))
            put("skin_removed.pgm", ps.compactMap(\.skinRemovedMask))
            put("person_final.pgm", ps.map(\.finalMask))
            if let m = result.mask { put("final.pgm", [m]) }
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
                                         layer: pl, steps: result.steps, options: v.options)
                writeData(Data(script.utf8), to: dir.appendingPathComponent("repro.sh"))
            }
        }
        variantsJSON.append([
            "name": v.name, "mode": v.options.mode.rawValue, "region": v.options.region.rawValue,
            "adaptive_skin": v.options.adaptiveSkin, "selected_index": v.options.selectedIndex as Any,
            "min_coverage": v.options.minCoverage, "min_region_fraction": v.options.minRegionFraction,
            "bare_arms_skin_fraction": v.options.bareArmsSkinFraction,
            "max_mahalanobis": v.options.skinOptions.maxMahalanobis,
            "mask": maskPath as Any, "mask_coverage": result.maskCoverage,
            "mask_pixels": result.mask.map { MaskOps.nonZero($0) } as Any,
            "chosen_index": result.chosenIndex as Any, "steps": result.steps.map(\.rawValue),
            "timings_ms": result.timings.mapValues(round3), "persons": personsJSON, "layers": layersPath as Any,
        ])
    }
    let batchURL = outURL.appendingPathComponent("\(base).batch.txt")
    writeData(Data((batchLines.joined(separator: "\n") + "\n").utf8), to: batchURL)

    let summary: [String: Any] = [
        "tool": "visionmask", "engine": colorEngineVersion, "dict_version": dictionaryVersion,
        "image": imageURL.path, "base": base, "orientation": orientation,
        "source_width": image.width, "source_height": image.height, "max_side": maxSide,
        "width": W, "height": H, "stride": raster.stride, "raster": ppmURL.path, "batch": batchURL.path,
        "vision": ["available": visionError == nil, "error": visionError as Any,
                   "warnings": detection?.warnings ?? [],
                   "unassigned_poses": detection?.unassignedPoses ?? 0,
                   "unassigned_faces": detection?.unassignedFaces ?? 0] as [String: Any],
        "timings_detect_ms": (detection?.timings ?? [:]).mapValues(round3),
        "people_count": people.count, "people": peopleJSON, "variants": variantsJSON,
        "discarded_people": detection?.discardedPeople ?? 0,
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
    print("\(base): \(W)x\(H) personas=\(people.count) \(stepsSummary)")
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
