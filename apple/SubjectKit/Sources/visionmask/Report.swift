// visionmask report: tabla por foto y variante (pasos, cobertura, top-3 de
// `ce batch` y color dominante frente a la prenda anotada en expected.json con
// ΔE00 calculado por el motor) y resumen por variante. Lee lo que escribió
// `visionmask <imagen>` en --masks-dir y el JSONL de `ce batch --json`.
//
// Con --references (apple/SubjectKit/Fixtures/people_references.json) reparte
// además el peso de la paleta en clases: cada swatch va a la referencia más
// cercana en ΔE00 (motor) entre las prendas anotadas de la persona más grande,
// los parches de piel y los de fondo u objetos, si está a <= 10; si no, «otro».
// El swatch dominante solo cuenta una parte de la historia: una paleta con el
// dominante bien y un 40 % de piel sigue eligiendo mal la combinación.
//
// Paleta por prenda (ADR-011): con --garments-batch (JSONL de `ce batch --garments`) las variantes
// -garments salen con un color por prenda (arriba / abajo / prenda entera, tono iluminado) y el
// informe añade la tabla «Colores por prenda» por foto y el resumen ANTES (camino clásico, misma
// máscara) / DESPUÉS (por prenda): swatches, ΔE00 a la prenda anotada de su parte y top-3.
//
// Piel en sombra (verificación de ADR-010): los swatches se clasifican también contra los
// parches de piel oscurecidos en luz lineal («skin_shaded») y, con SubjectMetrics, se mide
// qué fracción de la PALETA viene de píxeles reducidos de piel (el color de cada píxel que
// alimenta un swatch conservado, no el del swatch) y qué fracción de la MÁSCARA es piel, sin
// contar las zonas de pelo («hair_zones»). Gate (exit 1): con la variante por defecto
// largest-clothing-skin, ninguna foto cuya persona elegida tiene modelo de piel («cara
// visible») pasa del 5 % de piel en la paleta ni del 5 % en la máscara.
import CryptoKit
import Foundation
import ColorEngine
import SubjectKit
import SubjectMetrics

/// Umbral de ΔE00 para asignar un swatch a una referencia.
let referenceDeltaE = 10.0
/// Gate de piel de la variante por defecto (fracción de la paleta y de la máscara).
let skinGate = 0.05
/// Límites conocidos del MODELO DE PIEL por foto (no de la separación de personas): el gate
/// se mide e imprime igual, pero no hace fallar el informe. Lo mismo que
/// `PeoplePhotosTests.knownSkinLimits`; ver `docs/DECISIONS.md` (ADR-010).
let knownSkinLimits: [String: String] = [
    "07_group_mural_white_outfits": "tras separar las instancias que Vision fusiona, la persona más grande es la mujer de la izquierda (la anotada) y no la instancia fusionada de tres: el modelo ajustado a su cara al sol (muestra 106 px) no alcanza sus piernas desnudas en sombra (3,0 % -> 24,2 % de la máscara)",
]
let defaultVariantName = "largest-clothing-skin"

/// Clase de un swatch frente a las referencias de una foto.
enum SwatchClass: String, CaseIterable {
    case garment = "prenda", skin = "piel", background = "fondo", other = "otro"
}

/// Referencias de color de una foto: (clase, Lab, nombre).
struct PhotoReferences {
    var refs: [(cls: SwatchClass, lab: Lab, name: String)] = []

    /// Clase de un color: la referencia más cercana si ΔE00 <= `referenceDeltaE`
    /// (empate: el orden prenda, piel, fondo); si no, `.other`.
    func classify(_ lab: Lab) -> SwatchClass {
        var best: (SwatchClass, Double)? = nil
        for r in refs {
            let d = deltaE2000(lab, r.lab)
            if d <= referenceDeltaE, best == nil || d < best!.1 { best = (r.cls, d) }
        }
        return best?.0 ?? .other
    }

    /// Peso por clase de una lista de swatches (lab, peso).
    func weights(_ swatches: [(lab: Lab, weight: Double)]) -> [SwatchClass: Double] {
        var out: [SwatchClass: Double] = [:]
        for c in SwatchClass.allCases { out[c] = 0 }
        for s in swatches { out[classify(s.lab), default: 0] += s.weight }
        return out
    }
}

private func readJSON(_ path: String) -> Any? {
    guard let d = FileManager.default.contents(atPath: path) else { return nil }
    return try? JSONSerialization.jsonObject(with: d)
}

private func hexToLab(_ hex: String) -> Lab? {
    var s = hex.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    return srgbToLab(r: UInt8((v >> 16) & 0xff), g: UInt8((v >> 8) & 0xff), b: UInt8(v & 0xff))
}

private func fmt(_ v: Double?, _ digits: Int = 1) -> String {
    guard let v, v.isFinite else { return "–" }
    return String(format: "%.\(digits)f", v)
}

private func sha256Hex(_ path: String) -> String? {
    guard let d = FileManager.default.contents(atPath: path) else { return nil }
    return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
}

private func mean(_ xs: [Double]) -> Double? {
    xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
}

private func median(_ xs: [Double]) -> Double? {
    guard !xs.isEmpty else { return nil }
    let s = xs.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

/// Nombre de cada región de prenda en las tarjetas (CONTEXT §13).
func regionLabel(_ region: Int) -> String {
    switch region {
    case 1: "Parte de arriba"
    case 2: "Parte de abajo"
    case 3: "Prenda entera"
    default: "Sin región"
    }
}

/// Regiones de la paleta por prenda que corresponden a una parte anotada en expected.json
/// («torso» -> arriba o prenda entera; «legs» -> abajo o prenda entera; «full» -> cualquiera).
func regionsFor(part: String) -> Set<Int> {
    switch part {
    case "torso": [1, 3]
    case "legs": [2, 3]
    default: [0, 1, 2, 3]
    }
}

func runReport(_ args: [String]) -> Int32 {
    var masksDir: String?, batchPath: String?, expectedPath: String?, outPath: String?, reproPath: String?
    var referencesPath: String?, garmentsBatchPath: String?
    var i = 0
    while i < args.count {
        let a = args[i]
        guard i + 1 < args.count else { fail("falta el valor de \(a)\n\(usageText())") }
        let v = args[i + 1]
        switch a {
        case "--masks-dir": masksDir = v
        case "--batch": batchPath = v
        case "--expected": expectedPath = v
        case "--out": outPath = v
        case "--repro": reproPath = v
        case "--references": referencesPath = v
        case "--garments-batch": garmentsBatchPath = v
        default: fail("argumento no reconocido: \(a)\n\(usageText())")
        }
        i += 2
    }
    guard let masksDir, let batchPath, let expectedPath, let outPath else { fail(usageText()) }

    // expected.json
    guard let expectedArray = readJSON(expectedPath) as? [[String: Any]] else { fail("no se pudo leer \(expectedPath)") }
    var expected: [String: [String: Any]] = [:]
    for e in expectedArray {
        if let f = e["file"] as? String {
            expected[(f as NSString).deletingPathExtension] = e
        }
    }

    // Referencias de piel y fondo (opcional): {"photos": {"<fichero>": {"sha256", "skin": [{hex, name}], "background": [...]}}}
    var referenceDoc: [String: [String: Any]] = [:]
    if let referencesPath {
        guard let obj = readJSON(referencesPath) as? [String: Any], let photos = obj["photos"] as? [String: [String: Any]] else {
            fail("no se pudo leer \(referencesPath)")
        }
        for (f, entry) in photos { referenceDoc[(f as NSString).deletingPathExtension] = entry }
    }

    // ce batch JSONL
    guard let batchText = try? String(contentsOfFile: batchPath, encoding: .utf8) else { fail("no se pudo leer \(batchPath)") }
    var batch: [String: [String: Any]] = [:]
    var batchErrors = 0
    for line in batchText.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              let file = obj["file"] as? String else { fail("línea JSONL inválida en \(batchPath)") }
        let mask = obj["mask"] as? String ?? ""
        if obj["error"] != nil { batchErrors += 1 }
        batch["\(file)|\(mask)"] = obj
    }

    // JSONL de `ce batch --garments` (paleta por prenda), con la misma clave imagen|máscara.
    var garmentsBatch: [String: [String: Any]] = [:]
    if let garmentsBatchPath {
        guard let text = try? String(contentsOfFile: garmentsBatchPath, encoding: .utf8) else {
            fail("no se pudo leer \(garmentsBatchPath)")
        }
        for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let file = obj["file"] as? String else { fail("línea JSONL inválida en \(garmentsBatchPath)") }
            if obj["error"] != nil { batchErrors += 1 }
            garmentsBatch["\(file)|\(obj["mask"] as? String ?? "")"] = obj
        }
    }

    // Resultados de visionmask
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: masksDir)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
    var images: [[String: Any]] = []
    for f in files {
        if let obj = readJSON((masksDir as NSString).appendingPathComponent(f)) as? [String: Any],
           obj["tool"] as? String == "visionmask" {
            images.append(obj)
        }
    }
    guard !images.isEmpty else { fail("no hay resultados de visionmask en \(masksDir)") }

    var intro = "# visionmask sobre harness/people\n\n"
    intro += "Generado por `make visionmask-people`. Motor \(images.first?["engine"] ?? "?"), diccionario \(images.first?["dict_version"] ?? "?"). "
    intro += "Cada variante se analiza con `ce batch` sobre el raster exacto de la app (`<foto>.ppm`) y su máscara (`<foto>.<variante>.pgm`). "
    intro += "ΔE00 (motor) entre el swatch dominante y el color anotado a mano en `harness/people/expected.json` (mediana de un parche: guía aproximada, no verdad de color). "
    intro += "«prenda 1» = primera prenda anotada; «mín.» = la prenda anotada más cercana.\n\n"
    intro += "Cadena (ADR-010): instancias sin evidencia corporal fuera (fantasmas) → persona binaria (>= 128) → con pose: regiones de la pose (caderas estimadas si solo hay hombros; sin modelo de piel, brazos fuera salvo mangas del color del torso; con modelo, brazos fuera si >= 25 % es piel y piel del cuerpo aprendida si brazos o piernas son desnudos) si son >= 15 % de la silueta de la pose, si no la silueta; sin pose (o con silueta por debajo del suelo) el recorte de cabeza (altura por la cara si la hay) → piel adaptativa (Mahalanobis 2,75, halo de 1 px) → solo si la máscara no llega al suelo de 0,05 % del raster, la silueta (con pose) o la persona completa. Con pose nunca se usa la instancia cruda de Vision.\n\n"
    var md = ""

    var perVariantMain: [String: [Double]] = [:]
    var perVariantMin: [String: [Double]] = [:]
    var perVariantBetter: [String: Int] = [:]
    var perVariantWorse: [String: Int] = [:]
    var perVariantSteps: [String: [String: Int]] = [:]
    var perVariantClass: [String: [SwatchClass: [Double]]] = [:]
    var referenceNotes: [String] = []
    var variantOrder: [String] = []
    var missing = 0
    var stdout = ""
    var metricsRows = ""
    var perVariantMetric: [String: [String: [Double]]] = [:]
    var gateFailures: [String] = []
    var gateKnown: [String] = []
    var garmentSummaryRows = ""
    var garmentNotes: [String] = []
    var garmentDeltas: [Double] = [], classicDeltas: [Double] = []
    var garmentCounts: [Int] = [], classicCounts: [Int] = []
    var peopleRows = "| foto | instancias Vision | personas tras separar | fantasmas descartados | anotadas | separadas (instancia -> personas) | caras sin cuerpo | evidencia (pose / cara / forma) | poses sin persona | caras sin persona | bbox de la mayor | centro de bbox_hint dentro | detección (ms) |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"

    for img in images {
        guard let base = img["base"] as? String, let raster = img["raster"] as? String,
              let variants = img["variants"] as? [[String: Any]] else { continue }
        let exp = expected[base]
        let garments = ((exp?["largest_person"] as? [String: Any])?["garments"] as? [[String: Any]]) ?? []
        let garmentLabs = garments.compactMap { ($0["color_hex"] as? String).flatMap(hexToLab) }
        var references: PhotoReferences? = nil
        if let entry = referenceDoc[base] {
            let imagePath = img["image"] as? String ?? ""
            if let want = entry["sha256"] as? String, let got = sha256Hex(imagePath), want != got {
                referenceNotes.append("\(base): sha256 de la foto distinto del de las referencias; sin clases")
            } else {
                var r = PhotoReferences()
                for (g, lab) in zip(garments, garments.map { ($0["color_hex"] as? String).flatMap(hexToLab) }) {
                    if let lab { r.refs.append((.garment, lab, g["name"] as? String ?? "prenda")) }
                }
                for (key, cls) in [("skin", SwatchClass.skin), ("skin_shaded", SwatchClass.skin), ("background", SwatchClass.background)] {
                    for p in (entry[key] as? [[String: Any]]) ?? [] {
                        if let lab = (p["hex"] as? String).flatMap(hexToLab) { r.refs.append((cls, lab, p["name"] as? String ?? key)) }
                    }
                }
                references = r
            }
        }
        var metricRefs: ColorReferences? = nil
        if references != nil, let entry = referenceDoc[base] {
            let hexes = { (key: String) -> [String] in ((entry[key] as? [[String: Any]]) ?? []).compactMap { $0["hex"] as? String } }
            metricRefs = ColorReferences(garments: garments.compactMap { $0["color_hex"] as? String },
                                         skin: hexes("skin") + hexes("skin_shaded"), background: hexes("background"),
                                         hairZones: (entry["hair_zones"] as? [[Int]]) ?? [], threshold: referenceDeltaE)
        }
        var rasterRGBA: (w: Int, h: Int, px: [UInt8])? = nil
        if metricRefs != nil, let data = FileManager.default.contents(atPath: raster), let pnm = PNM.read(data), pnm.channels == 3 {
            var px = [UInt8](repeating: 255, count: pnm.width * pnm.height * 4)
            for i in 0..<(pnm.width * pnm.height) {
                px[4 * i] = pnm.bytes[3 * i]
                px[4 * i + 1] = pnm.bytes[3 * i + 1]
                px[4 * i + 2] = pnm.bytes[3 * i + 2]
            }
            rasterRGBA = (pnm.width, pnm.height, px)
        }
        let people = img["people"] as? [[String: Any]] ?? []
        let vision = img["vision"] as? [String: Any] ?? [:]
        var inside = "–"
        var bboxText = "–"
        if let bb = people.first?["bbox_xyxy"] as? [Int], bb.count == 4 {
            bboxText = "[\(bb[0]), \(bb[1]), \(bb[2]), \(bb[3])]"
            if let hint = (exp?["largest_person"] as? [String: Any])?["bbox_hint"] as? [Int], hint.count == 4 {
                let cx = Double(hint[0] + hint[2]) / 2, cy = Double(hint[1] + hint[3]) / 2
                inside = (Double(bb[0]) <= cx && cx < Double(bb[2]) && Double(bb[1]) <= cy && cy < Double(bb[3])) ? "sí" : "no"
            }
        }
        let detectMs = (img["timings_detect_ms"] as? [String: Double])?["detect"]
        let phantoms = (img["rejected_phantoms"] as? [Any])?.count ?? 0
        let kinds = people.compactMap { ($0["evidence"] as? [String: Any])?["kind"] as? String }
        let evidenceText = ["pose", "face", "shape"].map { k in "\(kinds.filter { $0 == k }.count)" }.joined(separator: " / ")
        let splitText = ((img["splits"] as? [[String: Any]]) ?? []).map { sp -> String in
            "\(sp["instance"] ?? "?") -> \((sp["person_ids"] as? [Int])?.count ?? 0) (\(sp["step"] ?? "?"))"
        }.joined(separator: ", ")
        let facelessBodies = (img["face_seeds_without_body"] as? [Any])?.count ?? 0
        peopleRows += "| \(base) | \(img["vision_instance_count"] ?? "–") | \(people.count) | \(phantoms) | \(exp?["people"] ?? "–") | \(splitText.isEmpty ? "–" : splitText) | \(facelessBodies) | \(evidenceText) | \(vision["unassigned_poses"] ?? 0) | \(vision["unassigned_faces"] ?? 0) | \(bboxText) | \(inside) | \(fmt(detectMs, 0)) |\n"

        md += "## \(base)\n\n"
        let gText = garments.map { "\($0["part"] ?? "?") \($0["color_hex"] ?? "?") (\($0["name"] ?? ""))" }.joined(separator: "; ")
        md += "Prendas anotadas: \(gText.isEmpty ? "–" : gText)\n\n"
        md += "| variante | pasos | cobertura | top-3 (score) | dominante (peso) | ΔE00 prenda 1 | ΔE00 mín. | prenda / piel / fondo / otro (peso) |\n|---|---|---|---|---|---|---|---|\n"
        stdout += "\n\(base)  (instancias Vision \(img["vision_instance_count"] ?? "–") -> personas \(people.count), anotadas \(exp?["people"] ?? "–")\(splitText.isEmpty ? "" : "; separadas " + splitText)\(facelessBodies > 0 ? "; caras sin cuerpo \(facelessBodies)" : ""))\n"
        var noneMin: Double? = nil
        for v in variants {
            guard let name = v["name"] as? String else { continue }
            if !variantOrder.contains(name) { variantOrder.append(name) }
            let steps = (v["steps"] as? [String]) ?? []
            for s in steps { perVariantSteps[name, default: [:]][s, default: 0] += 1 }
            let mask = v["mask"] as? String ?? ""
            let isGarments = (v["garments_variant"] as? Bool) ?? false
            let garmentEntry = isGarments ? garmentsBatch["\(raster)|\(mask)"] : nil
            guard let entry = garmentEntry ?? batch["\(raster)|\(mask)"] else {
                missing += 1
                md += "| \(name) | \(steps.joined(separator: " → ")) | – | sin resultado de ce batch | – | – | – | – |\n"
                continue
            }
            if let err = entry["error"] {
                md += "| \(name) | \(steps.joined(separator: " → ")) | – | error: \(err) | – | – | – | – |\n"
                continue
            }
            let hits = (entry["hits"] as? [[String: Any]]) ?? []
            let top3 = hits.prefix(3).map { h -> String in
                "\(h["id"] ?? "?") (\(fmt(h["score"] as? Double)))"
            }.joined(separator: ", ")
            let swatches = (entry["swatches"] as? [[String: Any]]) ?? []
            var dominant = "–"
            var deMain: Double? = nil, deMin: Double? = nil
            if let s0 = swatches.first, let lab = s0["lab"] as? [Double], lab.count == 3 {
                let l = Lab(L: lab[0], a: lab[1], b: lab[2])
                dominant = "\(s0["hex"] ?? "?") (\(fmt((s0["weight"] as? Double).map { $0 * 100 }, 0)) %)"
                if let g = garmentLabs.first { deMain = deltaE2000(l, g) }
                deMin = garmentLabs.map { deltaE2000(l, $0) }.min()
            }
            var classText = "–"
            if let references {
                let list = swatches.compactMap { sw -> (lab: Lab, weight: Double)? in
                    guard let lab = sw["lab"] as? [Double], lab.count == 3, let w = sw["weight"] as? Double else { return nil }
                    return (Lab(L: lab[0], a: lab[1], b: lab[2]), w)
                }
                let w = references.weights(list)
                for c in SwatchClass.allCases { perVariantClass[name, default: [:]][c, default: []].append(w[c] ?? 0) }
                classText = SwatchClass.allCases.map { fmt((w[$0] ?? 0) * 100, 0) }.joined(separator: " / ") + " %"
            }
            if let deMain { perVariantMain[name, default: []].append(deMain) }
            if let deMin {
                perVariantMin[name, default: []].append(deMin)
                if name == "none" {
                    noneMin = deMin
                } else if let n = noneMin {
                    if deMin < n - 1 { perVariantBetter[name, default: 0] += 1 }
                    if deMin > n + 1 { perVariantWorse[name, default: 0] += 1 }
                }
            }
            if let refs = metricRefs, let r = rasterRGBA {
                var maskBytes: [UInt8]? = nil
                if let mp = v["mask"] as? String, let data = FileManager.default.contents(atPath: mp), let pnm = PNM.read(data),
                   pnm.channels == 1, pnm.width == r.w, pnm.height == r.h {
                    maskBytes = pnm.bytes
                }
                let hasMask = v["mask"] is String
                if !hasMask || maskBytes != nil, let share = try? r.px.withUnsafeBufferPointer({ px in
                    try SkinMetrics.measure(rgba: px, width: r.w, height: r.h, stride: r.w * 4, mask: maskBytes, references: refs)
                }) {
                    let face = ((v["persons"] as? [[String: Any]])?.first?["skin_model"]) != nil
                    let pSkin = share.paletteWeight[.skin] ?? 0, mSkin = share.maskSkinFraction
                    let swSkin = share.swatchWeight[.skin] ?? 0
                    perVariantMetric[name, default: [:]]["palette_skin", default: []].append(pSkin)
                    perVariantMetric[name, default: [:]]["mask_skin", default: []].append(mSkin)
                    perVariantMetric[name, default: [:]]["palette_garment", default: []].append(share.paletteWeight[.garment] ?? 0)
                    perVariantMetric[name, default: [:]]["palette_background", default: []].append(share.paletteWeight[.background] ?? 0)
                    perVariantMetric[name, default: [:]]["swatch_skin", default: []].append(swSkin)
                    metricsRows += "| \(base) | \(name) | \(face ? "sí" : "no") | \(fmt(pSkin * 100)) % | \(hasMask ? fmt(mSkin * 100) + " %" : "–") | \(fmt(swSkin * 100)) % | \(fmt((share.paletteWeight[.garment] ?? 0) * 100)) % | \(fmt((share.paletteWeight[.background] ?? 0) * 100)) % |\n"
                    if name == defaultVariantName, face, pSkin > skinGate || mSkin > skinGate {
                        let text = "\(base): piel en la paleta \(fmt(pSkin * 100)) %, en la máscara \(fmt(mSkin * 100)) % (> \(fmt(skinGate * 100, 0)) %)"
                        if let limit = knownSkinLimits[base] {
                            gateKnown.append("\(text) — límite conocido del modelo de piel: \(limit)")
                        } else {
                            gateFailures.append(text)
                        }
                    }
                    stdout += "  \(name.padding(toLength: 24, withPad: " ", startingAt: 0)) piel en la paleta (px reducidos)=\(fmt(pSkin * 100)) % en la máscara=\(hasMask ? fmt(mSkin * 100) + " %" : "–") swatches (sombra)=\(fmt(swSkin * 100)) % prenda paleta=\(fmt((share.paletteWeight[.garment] ?? 0) * 100)) %\(face ? " [cara]" : "")\n"
                }
            }
            let cov = (v["mask"] is NSNull || v["mask"] == nil) ? "sin máscara" : fmt((v["mask_coverage"] as? Double).map { $0 * 100 }) + " %"
            md += "| \(name) | \(steps.isEmpty ? "–" : steps.joined(separator: " → ")) | \(cov) | \(top3) | \(dominant) | \(fmt(deMain)) | \(fmt(deMin)) | \(classText) |\n"
            stdout += "  \(name.padding(toLength: 24, withPad: " ", startingAt: 0)) \(steps.joined(separator: "+").padding(toLength: 36, withPad: " ", startingAt: 0)) top3=[\(top3)] dominante=\(dominant) ΔE00 prenda1=\(fmt(deMain)) mín=\(fmt(deMin)) prenda/piel/fondo/otro=\(classText)\n"
        }
        md += "\n"

        // Colores por prenda (ADR-011) y comparación con el camino clásico de la misma máscara.
        for v in variants {
            guard let name = v["name"] as? String, (v["garments_variant"] as? Bool) == true else { continue }
            let mask = v["mask"] as? String ?? ""
            let classicName = name.hasSuffix("-garments") ? String(name.dropLast("-garments".count)) : name
            let classicMask = variants.first { $0["name"] as? String == classicName }?["mask"] as? String ?? mask
            let classic = batch["\(raster)|\(classicMask)"]
            guard let entry = garmentsBatch["\(raster)|\(mask)"], entry["error"] == nil else {
                if v["garment_regions"] == nil || v["garment_regions"] is NSNull {
                    garmentNotes.append("\(base) (\(name)): sin pose utilizable, el mapa de prendas es nil y la app sigue con el camino clásico")
                } else {
                    garmentNotes.append("\(base) (\(name)): sin resultado de `ce batch --garments`")
                }
                continue
            }
            let list = (entry["garments"] as? [[String: Any]]) ?? []
            let classicSwatches = (classic?["swatches"] as? [[String: Any]]) ?? []
            func lab(_ o: [String: Any]) -> Lab? {
                guard let l = o["lab"] as? [Double], l.count == 3 else { return nil }
                return Lab(L: l[0], a: l[1], b: l[2])
            }
            md += "### Colores por prenda (\(name))\n\n"
            md += "| prenda | color | peso | clusters agrupados | cuota de la región | prenda anotada más cercana | ΔE00 |\n|---|---|---|---|---|---|---|\n"
            for g in list {
                let region = g["region"] as? Int ?? 0
                var nearest = "–", de = "–"
                if let l = lab(g) {
                    let pool = garments.filter { regionsFor(part: $0["part"] as? String ?? "").contains(region) }
                    let candidates = (pool.isEmpty ? garments : pool).compactMap { a -> (String, Double)? in
                        guard let hex = a["color_hex"] as? String, let al = hexToLab(hex) else { return nil }
                        return ("\(a["part"] ?? "?") \(hex)", deltaE2000(l, al))
                    }
                    if let best = candidates.min(by: { $0.1 < $1.1 }) {
                        nearest = best.0
                        de = fmt(best.1)
                    }
                }
                md += "| \(regionLabel(region)) | \(g["hex"] ?? "?") | \(fmt((g["weight"] as? Double).map { $0 * 100 }, 0)) % | \(g["n_merged_clusters"] ?? 0) | \(fmt((g["region_share"] as? Double).map { $0 * 100 }, 0)) % | \(nearest) | \(de) |\n"
            }
            md += "\n"
            // Resumen ANTES (clásico con la misma máscara) / DESPUÉS (por prenda).
            var deC: [String] = [], deG: [String] = []
            for a in garments {
                guard let hex = a["color_hex"] as? String, let al = hexToLab(hex) else { continue }
                let part = a["part"] as? String ?? ""
                let c = classicSwatches.compactMap { lab($0).map { deltaE2000($0, al) } }.min()
                let pool = list.filter { regionsFor(part: part).contains($0["region"] as? Int ?? 0) }
                let g = (pool.isEmpty ? list : pool).compactMap { lab($0).map { deltaE2000($0, al) } }.min()
                if let c { classicDeltas.append(c) }
                if let g { garmentDeltas.append(g) }
                deC.append(fmt(c))
                deG.append(fmt(g))
            }
            classicCounts.append(classicSwatches.count)
            garmentCounts.append(list.count)
            func count(_ region: Int) -> Int { list.filter { ($0["region"] as? Int ?? 0) == region }.count }
            let lowerColors = count(2) + count(3)
            let hasTrousers = garments.contains { ($0["part"] as? String) == "legs" }
            let patterned = garments.filter { ($0["part"] as? String) == "legs" }
            let printed = patterned.count > 1 || patterned.contains {
                ($0["name"] as? String)?.range(of: "estampad|rayas|cuadros", options: .regularExpression) != nil
            }
            var gate = "–"
            if hasTrousers && !printed {
                gate = lowerColors <= 1 ? "OK (\(lowerColors))" : "> 1 (\(lowerColors))"
                if lowerColors > 1 {
                    garmentNotes.append("\(base): pantalón liso con \(lowerColors) colores abajo (\(list.filter { ($0["region"] as? Int ?? 0) != 1 }.map { "\($0["hex"] ?? "?")" }.joined(separator: " + ")))")
                }
            }
            let hitsC = ((classic?["hits"] as? [[String: Any]]) ?? []).prefix(3).map { "\($0["id"] ?? "?")" }.joined(separator: ", ")
            let hitsG = ((entry["hits"] as? [[String: Any]]) ?? []).prefix(3).map { "\($0["id"] ?? "?")" }.joined(separator: ", ")
            garmentSummaryRows += "| \(base) | \(name) | \(classicSwatches.count) | \(count(1)) / \(count(2)) / \(count(3)) | \(deC.joined(separator: "; ")) | \(deG.joined(separator: "; ")) | \(hitsC) | \(hitsG) | \(gate) |\n"
            stdout += "  \(name.padding(toLength: 24, withPad: " ", startingAt: 0)) prendas=\(list.map { "\(regionLabel($0["region"] as? Int ?? 0)) \($0["hex"] ?? "?")" }.joined(separator: ", ")) clásico=\(classicSwatches.count) swatches ΔE00 \(deC.joined(separator: "; ")) -> \(deG.joined(separator: "; ")) gate pantalón=\(gate)\n"
        }
    }

    var summary = "## Resumen por variante\n\n"
    summary += "| variante | fotos | ΔE00 prenda 1 media | mediana | ΔE00 mín. media | mediana | mejor que none (> 1 ΔE) | peor que none | pasos (recuento) |\n|---|---|---|---|---|---|---|---|---|\n"
    stdout += "\nResumen por variante (ΔE00 del dominante frente a la prenda anotada):\n"
    for name in variantOrder {
        let m = perVariantMain[name] ?? [], n = perVariantMin[name] ?? []
        let steps = (perVariantSteps[name] ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        let better = name == "none" ? "–" : "\(perVariantBetter[name] ?? 0)"
        let worse = name == "none" ? "–" : "\(perVariantWorse[name] ?? 0)"
        summary += "| \(name) | \(n.count) | \(fmt(mean(m))) | \(fmt(median(m))) | \(fmt(mean(n))) | \(fmt(median(n))) | \(better) | \(worse) | \(steps) |\n"
        stdout += "  \(name.padding(toLength: 24, withPad: " ", startingAt: 0)) prenda1 media=\(fmt(mean(m))) mediana=\(fmt(median(m)))  mín media=\(fmt(mean(n))) mediana=\(fmt(median(n)))  mejor=\(better) peor=\(worse)\n"
    }
    summary += "\n"
    if !perVariantClass.isEmpty {
        summary += "### Reparto del peso de la paleta (referencias)\n\n"
        summary += "Cada swatch va a la referencia más cercana en ΔE00 (motor) si está a <= \(fmt(referenceDeltaE, 0)): prendas anotadas de la persona más grande (`expected.json`), parches de piel y de fondo u objetos (`--references`); si no, «otro» (otras personas, pelo, sombras). Media y máximo por foto.\n\n"
        summary += "| variante | fotos | prenda media | piel media | piel máx. | fondo media | fondo máx. | otro media |\n|---|---|---|---|---|---|---|---|\n"
        stdout += "\nReparto del peso de la paleta (media por foto; piel y fondo con máximo):\n"
        for name in variantOrder {
            guard let c = perVariantClass[name] else { continue }
            let pct = { (xs: [Double]?) -> String in fmt(mean(xs ?? []).map { $0 * 100 }, 1) + " %" }
            let mx = { (xs: [Double]?) -> String in fmt((xs ?? []).max().map { $0 * 100 }, 1) + " %" }
            summary += "| \(name) | \(c[.garment]?.count ?? 0) | \(pct(c[.garment])) | \(pct(c[.skin])) | \(mx(c[.skin])) | \(pct(c[.background])) | \(mx(c[.background])) | \(pct(c[.other])) |\n"
            stdout += "  \(name.padding(toLength: 24, withPad: " ", startingAt: 0)) prenda=\(pct(c[.garment])) piel=\(pct(c[.skin])) (máx \(mx(c[.skin]))) fondo=\(pct(c[.background])) (máx \(mx(c[.background]))) otro=\(pct(c[.other]))\n"
        }
        summary += "\n"
        if !perVariantMetric.isEmpty {
            summary += "### Piel en sombra: paleta por píxel reducido y máscara por píxel\n\n"
            summary += "SubjectMetrics: cada píxel reducido que alimenta un swatch conservado se clasifica por SU color (prendas anotadas, piel iluminada y en sombra `skin_shaded`, fondo; ΔE00 <= \(fmt(referenceDeltaE, 0))) y se suma su peso; «máscara» = fracción de los píxeles de la máscara de clase piel. El pelo dentro de `hair_zones` no cuenta como piel. Gate: variante \(defaultVariantName), fotos con cara visible (modelo de piel), piel <= \(fmt(skinGate * 100, 0)) % en ambas.\n\n"
            summary += "| variante | piel en la paleta media | máx. | piel en la máscara media | máx. | piel en swatches (sombra) media | prenda en la paleta media | fondo en la paleta media |\n|---|---|---|---|---|---|---|---|\n"
            stdout += "\nPiel en sombra (media por foto; máximo):\n"
            for name in variantOrder {
                guard let m = perVariantMetric[name] else { continue }
                let pct = { (k: String) -> String in fmt(mean(m[k] ?? []).map { $0 * 100 }) + " %" }
                let mx = { (k: String) -> String in fmt((m[k] ?? []).max().map { $0 * 100 }) + " %" }
                summary += "| \(name) | \(pct("palette_skin")) | \(mx("palette_skin")) | \(pct("mask_skin")) | \(mx("mask_skin")) | \(pct("swatch_skin")) | \(pct("palette_garment")) | \(pct("palette_background")) |\n"
                stdout += "  \(name.padding(toLength: 24, withPad: " ", startingAt: 0)) piel paleta=\(pct("palette_skin")) (máx \(mx("palette_skin"))) piel máscara=\(pct("mask_skin")) (máx \(mx("mask_skin"))) prenda paleta=\(pct("palette_garment"))\n"
            }
            summary += "\n| foto | variante | cara visible | piel en la paleta | piel en la máscara | piel en swatches (sombra) | prenda en la paleta | fondo en la paleta |\n|---|---|---|---|---|---|---|---|\n" + metricsRows + "\n"
            summary += gateFailures.isEmpty ? "Gate de piel: OK.\n\n" : "Gate de piel FALLIDO:\n" + gateFailures.map { "- \($0)\n" }.joined() + "\n"
            if !gateKnown.isEmpty {
                summary += "Límites conocidos del modelo de piel (no fallan el informe):\n" + gateKnown.map { "- \($0)\n" }.joined() + "\n"
            }
            stdout += gateFailures.isEmpty ? "Gate de piel (\(defaultVariantName), cara visible, <= \(fmt(skinGate * 100, 0)) %): OK\(gateKnown.isEmpty ? "" : " (\(gateKnown.count) límite(s) conocido(s) del modelo de piel)")\n" : "Gate de piel FALLIDO: \(gateFailures.joined(separator: "; "))\n"
        }
        for n in referenceNotes { summary += "- \(n)\n" }
        if !referenceNotes.isEmpty { summary += "\n" }
    }

    // Paleta por prenda: ANTES (camino clásico con la misma máscara) / DESPUÉS (un color por prenda).
    if !garmentSummaryRows.isEmpty {
        summary += "### Paleta por prenda (ADR-011): antes y después\n\n"
        summary += "Variantes `-garments`: el mapa de regiones de la pose (`SubjectMaskResult.garmentRegions`, 1 arriba / 2 abajo) va con la máscara a `ce batch --garments`, que agrupa los tonos del mismo color con distinta luz y devuelve el TONO ILUMINADO de cada prenda. «antes» = `ce batch` clásico con la MISMA máscara. ΔE00 de cada prenda anotada al swatch más cercano (clásico) o al swatch de su región (por prenda; las anotaciones son parches en tonos medios, no el tono iluminado: el ΔE00 puede subir aunque el color sea el que se ve). «gate pantalón liso» = colores en la parte de abajo (o en la prenda entera) de una persona con pantalón anotado sin estampado: debe ser <= 1.\n\n"
        summary += "| foto | variante | swatches clásico | por prenda: arriba / abajo / entera | ΔE00 clásico | ΔE00 por prenda | top-3 clásico | top-3 por prenda | gate pantalón liso |\n|---|---|---|---|---|---|---|---|---|\n"
        summary += garmentSummaryRows
        let meanInt = { (xs: [Int]) -> String in xs.isEmpty ? "–" : fmt(Double(xs.reduce(0, +)) / Double(xs.count), 2) }
        summary += "\nMedias: swatches \(meanInt(classicCounts)) -> \(meanInt(garmentCounts)); ΔE00 a la prenda anotada media \(fmt(mean(classicDeltas))) -> \(fmt(mean(garmentDeltas))), mediana \(fmt(median(classicDeltas))) -> \(fmt(median(garmentDeltas))).\n\n"
        for n in garmentNotes { summary += "- \(n)\n" }
        if !garmentNotes.isEmpty { summary += "\n" }
        stdout += "\nPaleta por prenda: swatches \(meanInt(classicCounts)) -> \(meanInt(garmentCounts)); ΔE00 mediana \(fmt(median(classicDeltas))) -> \(fmt(median(garmentDeltas)))\n"
        for n in garmentNotes { stdout += "  aviso: \(n)\n" }
    }

    var repro = ""
    var reproDiffs = 0
    if let reproPath, let text = try? String(contentsOfFile: reproPath, encoding: .utf8) {
        var counts: [String: Int] = [:]
        var rows = ""
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: "\t").map(String.init)
            guard cols.count >= 4 else { continue }
            counts[cols[3], default: 0] += 1
            if cols[3] == "diff" { reproDiffs += 1 }
            rows += "| \(cols[0]) | \(cols[1]) | \(cols[2]) | \(cols[3]) |\n"
        }
        repro = "## Reproducción con la CLI `ce`\n\n"
        repro += "Cada capa de `<foto>.<variante>.layers/` se recalcula con `ce regions` (person.pgm + pose.txt: silueta, regiones y recuentos con y sin brazos), `ce skin` (piel de arms.pgm frente al umbral de brazos desnudos; face_sample.pgm sobre region.pgm), `ce cut-head` (fracción del JSON) y cada instancia separada con `ce split` (`<foto>.split<id>.mask.pgm` + `.seeds.txt`, `<foto>.split_repro.sh`), y se compara byte a byte (`cmp`) con la capa que escribió SubjectKit; las candidatas descartadas se comparan por recuento de píxeles. "
        repro += "Recuento: " + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + ".\n\n"
        repro += "| foto | variante | paso | resultado |\n|---|---|---|---|\n" + rows + "\n"
        stdout += "\nReproducción con ce: " + counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ") + "\n"
    }

    let header = "## Personas detectadas\n\nVision devuelve como mucho 4 instancias de persona (VNGeneratePersonInstanceMaskRequest) y junta en una sola a las que se tocan o se solapan. SubjectKit separa esas instancias con semillas de caras y poses (PersonSplitter + `ce split`, hasta 8 personas): «separadas» lista cada instancia separada y en cuántas personas; «caras sin cuerpo» son semillas de cara descartadas por no tener rectángulo de persona ni puntos de pose (póster, pantalla, retrato). «fantasmas descartados»: instancias sin evidencia corporal (sin pose con torso dentro, sin cara y sin silueta plausible; ADR-010), que no cuentan como personas. «evidencia»: la regla que acepta a cada persona. «poses/caras sin persona»: observaciones de Vision que no caen en ninguna máscara o que perdieron frente a otra en la misma instancia.\n\n" + peopleRows + "\n"
    let text = intro + summary + repro + header + md
    do {
        try text.write(toFile: outPath, atomically: true, encoding: .utf8)
    } catch {
        fail("no se pudo escribir \(outPath): \(error.localizedDescription)")
    }
    print(stdout)
    print("informe: \(outPath)")
    if missing > 0 { FileHandle.standardError.write(Data("visionmask report: \(missing) variantes sin resultado de ce batch\n".utf8)) }
    if batchErrors > 0 { FileHandle.standardError.write(Data("visionmask report: \(batchErrors) líneas de error en ce batch\n".utf8)) }
    if reproDiffs > 0 { FileHandle.standardError.write(Data("visionmask report: \(reproDiffs) capas no se reproducen con ce\n".utf8)) }
    if !gateFailures.isEmpty { FileHandle.standardError.write(Data("visionmask report: gate de piel fallido: \(gateFailures.joined(separator: "; "))\n".utf8)) }
    return (missing > 0 || batchErrors > 0 || reproDiffs > 0 || !gateFailures.isEmpty) ? 1 : 0
}
