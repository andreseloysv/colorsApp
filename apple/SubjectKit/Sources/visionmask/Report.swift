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
import CryptoKit
import Foundation
import ColorEngine

/// Umbral de ΔE00 para asignar un swatch a una referencia.
let referenceDeltaE = 10.0

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

func runReport(_ args: [String]) -> Int32 {
    var masksDir: String?, batchPath: String?, expectedPath: String?, outPath: String?, reproPath: String?
    var referencesPath: String?
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
    intro += "Cadena (ADR-010): persona binaria (>= 128) → con pose: regiones de la pose (caderas estimadas si solo hay hombros; sin brazos si no hay modelo de piel o si >= 25 % de los brazos es piel) si son >= 15 % de la silueta de la pose, si no la silueta; sin pose (o con silueta por debajo del suelo) el recorte de cabeza (altura por la cara si la hay) → piel adaptativa → solo si la máscara no llega al suelo de 0,05 % del raster, la silueta (con pose) o la persona completa. Con pose nunca se usa la instancia cruda de Vision.\n\n"
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
    var peopleRows = "| foto | personas Vision | anotadas | poses sin persona | caras sin persona | bbox de la mayor | centro de bbox_hint dentro | detección (ms) |\n|---|---|---|---|---|---|---|---|\n"

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
                for (key, cls) in [("skin", SwatchClass.skin), ("background", SwatchClass.background)] {
                    for p in (entry[key] as? [[String: Any]]) ?? [] {
                        if let lab = (p["hex"] as? String).flatMap(hexToLab) { r.refs.append((cls, lab, p["name"] as? String ?? key)) }
                    }
                }
                references = r
            }
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
        peopleRows += "| \(base) | \(people.count) | \(exp?["people"] ?? "–") | \(vision["unassigned_poses"] ?? 0) | \(vision["unassigned_faces"] ?? 0) | \(bboxText) | \(inside) | \(fmt(detectMs, 0)) |\n"

        md += "## \(base)\n\n"
        let gText = garments.map { "\($0["part"] ?? "?") \($0["color_hex"] ?? "?") (\($0["name"] ?? ""))" }.joined(separator: "; ")
        md += "Prendas anotadas: \(gText.isEmpty ? "–" : gText)\n\n"
        md += "| variante | pasos | cobertura | top-3 (score) | dominante (peso) | ΔE00 prenda 1 | ΔE00 mín. | prenda / piel / fondo / otro (peso) |\n|---|---|---|---|---|---|---|---|\n"
        stdout += "\n\(base)  (personas \(people.count), anotadas \(exp?["people"] ?? "–"))\n"
        var noneMin: Double? = nil
        for v in variants {
            guard let name = v["name"] as? String else { continue }
            if !variantOrder.contains(name) { variantOrder.append(name) }
            let steps = (v["steps"] as? [String]) ?? []
            for s in steps { perVariantSteps[name, default: [:]][s, default: 0] += 1 }
            let mask = v["mask"] as? String ?? ""
            guard let entry = batch["\(raster)|\(mask)"] else {
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
            let cov = (v["mask"] is NSNull || v["mask"] == nil) ? "sin máscara" : fmt((v["mask_coverage"] as? Double).map { $0 * 100 }) + " %"
            md += "| \(name) | \(steps.isEmpty ? "–" : steps.joined(separator: " → ")) | \(cov) | \(top3) | \(dominant) | \(fmt(deMain)) | \(fmt(deMin)) | \(classText) |\n"
            stdout += "  \(name.padding(toLength: 24, withPad: " ", startingAt: 0)) \(steps.joined(separator: "+").padding(toLength: 36, withPad: " ", startingAt: 0)) top3=[\(top3)] dominante=\(dominant) ΔE00 prenda1=\(fmt(deMain)) mín=\(fmt(deMin)) prenda/piel/fondo/otro=\(classText)\n"
        }
        md += "\n"
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
        for n in referenceNotes { summary += "- \(n)\n" }
        if !referenceNotes.isEmpty { summary += "\n" }
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
        repro += "Cada capa de `<foto>.<variante>.layers/` se recalcula con `ce regions` (person.pgm + pose.txt: silueta, regiones y recuentos con y sin brazos), `ce skin` (piel de arms.pgm frente al umbral de brazos desnudos; face_sample.pgm sobre region.pgm), `ce cut-head` (fracción del JSON) y se compara byte a byte (`cmp`) con la capa que escribió SubjectKit; las candidatas descartadas se comparan por recuento de píxeles. "
        repro += "Recuento: " + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + ".\n\n"
        repro += "| foto | variante | paso | resultado |\n|---|---|---|---|\n" + rows + "\n"
        stdout += "\nReproducción con ce: " + counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ") + "\n"
    }

    let header = "## Personas detectadas\n\nVision devuelve como mucho 4 instancias de persona (VNGeneratePersonInstanceMaskRequest): con más gente fusiona o descarta personas. «poses/caras sin persona»: observaciones de Vision que no caen en ninguna máscara o que perdieron frente a otra en la misma instancia.\n\n" + peopleRows + "\n"
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
    return (missing > 0 || batchErrors > 0 || reproDiffs > 0) ? 1 : 0
}
