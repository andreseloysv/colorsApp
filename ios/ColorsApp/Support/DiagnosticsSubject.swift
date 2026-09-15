// Ficheros del recorte y de las capas para "Exportar diagnóstico", junto a cada
// images/<scan_id>.png de 256 px (lo que lee oracle/tools/feedback_report.py y
// la capa 4 del harness):
//
//   <scan_id>.largest.pgm               persona más grande, completa
//   <scan_id>.largest-clothing.pgm      persona más grande, solo ropa
//   <scan_id>.largest-clothing-skin.pgm persona más grande, solo ropa y piel adaptativa
//   <scan_id>.json                      pasos, personas, variantes y tiempos
//   <scan_id>.labels.png                swatch por píxel del análisis (como labels.ppm de `ce --debug-dir`)
//   <scan_id>.debug.json                palette_debug y explicación del top-3 (nombres de `ce --debug-dir`)
//
// Las máscaras se calculan con SubjectKit sobre el raster del análisis (las
// mismas personas de Vision, sin volver a detectar) y se reescalan al tamaño
// exacto del PNG de 256 px (EngineBridge.targetSize), así `ce batch` sobre el
// PNG convertido a PPM y cada PGM evalúa las máscaras del dispositivo. Una
// variante sin máscara (sin personas, persona demasiado pequeña...) no escribe
// PGM: en el JSON su "file" es null y el motor analiza la foto completa.
import Foundation
import CoreGraphics
import ColorEngine
import SubjectKit

enum DiagnosticsSubject {
    /// Lado mayor del PNG exportado (formato del set dorado, PLAN §6 L4).
    static let exportSide = 256

    /// Variantes con los nombres de visionmask (`<largest>[-clothing][-skin]`).
    static let variants: [(name: String, options: SubjectOptions)] = [
        ("largest", SubjectOptions(mode: .largestPerson, region: .wholePerson, adaptiveSkin: false)),
        ("largest-clothing", SubjectOptions(mode: .largestPerson, region: .clothing, adaptiveSkin: false)),
        ("largest-clothing-skin", SubjectOptions(mode: .largestPerson, region: .clothing, adaptiveSkin: true)),
    ]

    /// Un fichero extra: images/<scan_id>.<suffix>.
    struct Extra: Equatable, Sendable {
        let suffix: String
        let data: Data
    }

    /// Lo que hace falta de un análisis para escribir los extras.
    struct Input: Sendable {
        let scanId: String
        let raster: EngineBridge.Raster
        let options: SubjectOptions
        let subject: SubjectMaskResult
        let debug: PaletteDebugLayers?
        let timings: AnalysisTimings
        /// "analysis" (capturado al votar, mismas personas que vio el usuario) o
        /// "export" (scan del carrete: Vision recalculado al exportar).
        let origin: String

        init(outcome: ScanOutcome, origin: String = "analysis") {
            scanId = outcome.scan.id
            raster = outcome.raster
            options = outcome.subjectOptions
            subject = outcome.subject
            debug = outcome.debug
            timings = outcome.timings
            self.origin = origin
        }

        init(scanId: String, analysis: ScanAnalyzer.Analysis, origin: String) {
            self.scanId = scanId
            raster = analysis.raster
            options = analysis.options
            subject = analysis.subject
            debug = analysis.debug
            timings = analysis.timings
            self.origin = origin
        }
    }

    /// Tamaño del PNG exportado para un raster.
    static func exportSize(width: Int, height: Int) -> (width: Int, height: Int) {
        EngineBridge.targetSize(width: width, height: height, maxSide: exportSide)
    }

    /// PGM de las tres variantes, JSON del recorte, label map y debug.json. Síncrono: fuera del MainActor.
    static func extras(_ input: Input) throws -> [Extra] {
        let raster = input.raster
        let size = exportSize(width: raster.width, height: raster.height)
        var out: [Extra] = []
        var variantJSON: [String: Any] = [:]
        try raster.pixels.withUnsafeBufferPointer { px in
            for (name, options) in variants {
                let r = try SubjectExtractor.mask(people: input.subject.people, rgba: px, width: raster.width,
                                                  height: raster.height, stride: raster.stride, options: options)
                var file: Any = NSNull()
                if let mask = r.mask {
                    let small = try LayerBitmaps.resample(mask: mask, width: raster.width, height: raster.height,
                                                          toWidth: size.width, toHeight: size.height)
                    let suffix = "\(name).pgm"
                    out.append(Extra(suffix: suffix, data: PNM.pgm(width: size.width, height: size.height, gray: small)))
                    file = "\(input.scanId).\(suffix)"
                }
                variantJSON[name] = [
                    "steps": r.steps.map(\.rawValue),
                    "mask_coverage": r.maskCoverage,
                    "person_index": r.chosenIndex.map { $0 as Any } ?? NSNull(),
                    "file": file,
                ] as [String: Any]
            }
        }
        out.append(Extra(suffix: "json", data: try json(subjectJSON(input, size: size, variants: variantJSON))))
        if let debug = input.debug {
            let swatches = debug.analysis.swatches
            if let labels = LayerBitmaps.labelsOpaque(debug.labelMap, width: debug.debug.reducedWidth,
                                                      height: debug.debug.reducedHeight, swatches: swatches),
               let png = PNGCoding.png(from: labels) {
                out.append(Extra(suffix: "labels.png", data: png))
            }
            out.append(Extra(suffix: "debug.json", data: try json(debugJSON(debug))))
        }
        return out.sorted { $0.suffix < $1.suffix }
    }

    // MARK: JSON

    static func json(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    static func subjectJSON(_ input: Input, size: (width: Int, height: Int), variants: [String: Any]) -> [String: Any] {
        let s = input.subject
        let people: [[String: Any]] = s.people.enumerated().map { i, p in
            let layer = s.layers.persons.first { $0.personIndex == i }
            return [
                "index": i,
                "id": p.id,
                "coverage": p.coverage,
                "bbox": [p.bbox.minX, p.bbox.minY, p.bbox.width, p.bbox.height].map { Double($0) },
                "pose": p.pose != nil,
                "face_sample": p.faceSampleMask != nil,
                "chosen": s.chosenIndex == i || input.options.mode == .allPeople,
                "steps": layer.map { $0.steps.map(\.rawValue) as Any } ?? NSNull(),
                "skin_excluded_pixels": layer?.skinExcludedPixels ?? 0,
                "skin_note": layer?.skinNote.map { $0 as Any } ?? NSNull(),
            ]
        }
        return [
            "scan_id": input.scanId,
            "engine": colorEngineVersion,
            "dict_version": dictionaryVersion,
            "origin": input.origin,
            // Vision: "run" (detectó), "off" (modo desactivado: no se buscaron personas y las
            // variantes quedan sin máscara) o "unavailable" (Vision lanzó, p. ej. en el simulador).
            "vision": s.steps.contains(.visionUnavailable) ? "unavailable" : (input.options.mode == .off ? "off" : "run"),
            "raster": ["width": input.raster.width, "height": input.raster.height],
            "export": ["width": size.width, "height": size.height],
            "subject": [
                "mode": input.options.mode.rawValue,
                "region": input.options.region.rawValue,
                "adaptive_skin": input.options.adaptiveSkin,
                "person_index": s.chosenIndex.map { $0 as Any } ?? NSNull(),
                "people_count": s.people.count,
                "steps": s.steps.map(\.rawValue),
                "mask_coverage": s.maskCoverage,
                "min_coverage": input.options.minCoverage,
            ] as [String: Any],
            "people": people,
            "variants": variants,
            "timings_ms": [
                "raster": input.timings.rasterMs,
                "vision": input.timings.visionMs,
                "mask": input.timings.maskMs,
                "engine": input.timings.engineMs,
                "total": input.timings.totalMs,
                "subjectkit": s.timings,
            ] as [String: Any],
        ]
    }

    static func fateName(_ fate: ClusterFate) -> String {
        switch fate {
        case .kept: "kept"
        case .merged: "merged"
        case .discarded: "discarded"
        case .truncated: "truncated"
        }
    }

    static func illuminantName(_ illuminant: Int) -> String {
        switch illuminant {
        case -1: "none"
        case 0: "A"
        case 1: "D50"
        case 2: "D65"
        case 3: "D75"
        case 4: "F2"
        default: "unknown"
        }
    }

    /// debug.json con los nombres de campo de `ce match --debug-dir` (sin rutas de capas).
    static func debugJSON(_ d: PaletteDebugLayers) -> [String: Any] {
        let clusterPixels = counts(d.clusterMap)
        let labelPixels = counts(d.labelMap)
        let clusters: [[String: Any]] = d.debug.clusters.enumerated().map { i, c in
            [
                "index": i,
                "rgb": [Int(c.r), Int(c.g), Int(c.b)],
                "hex": c.hex,
                "lab": [c.lab.L, c.lab.a, c.lab.b],
                "weight": c.weight,
                "fate": c.fate.rawValue,
                "fate_name": fateName(c.fate),
                "final_index": c.finalIndex.map { $0 as Any } ?? NSNull(),
                "group_head": c.groupHead,
                "pixels": clusterPixels[i] ?? 0,
            ]
        }
        let swatches: [[String: Any]] = d.analysis.swatches.enumerated().map { i, s in
            [
                "index": i,
                "rgb": [Int(s.r), Int(s.g), Int(s.b)],
                "hex": s.hex,
                "lab": [s.lab.L, s.lab.a, s.lab.b],
                "weight": s.weight,
                "pixels": labelPixels[i] ?? 0,
            ]
        }
        let explain: [[String: Any]] = d.explanations.enumerated().map { rank, e in
            [
                "rank": rank + 1,
                "id": e.comboId,
                "score": e.score,
                "score_equals_match": rank < d.analysis.hits.count && d.analysis.hits[rank].score == e.score,
                "fit_term": e.fitTerm,
                "coverage_term": e.coverageTerm,
                "hypothesis_penalty": e.hypothesisPenalty,
                "exposure_ev": e.exposureEV,
                "illuminant": e.illuminant,
                "illuminant_name": illuminantName(e.illuminant),
                "per_swatch": e.perSwatch.enumerated().map { i, p in
                    ["swatch": i, "nearest_color": p.nearestColorIndex, "de": p.deltaE] as [String: Any]
                },
                "per_color": e.perColor.map { c in
                    ["color": c.colorIndex, "nearest_swatch": c.nearestSwatch, "de": c.deltaE] as [String: Any]
                },
            ]
        }
        return [
            "engine": colorEngineVersion,
            "dict_version": dictionaryVersion,
            "reduced_width": d.debug.reducedWidth,
            "reduced_height": d.debug.reducedHeight,
            "label_values": ["none": Int(paletteLabelNone), "discarded": Int(paletteLabelDiscarded)],
            "palette_debug": [
                "lloyd_iterations": d.debug.lloydIterations,
                "total_weight": d.debug.totalWeight,
                "zero_weight_fraction": d.debug.zeroWeightFraction,
                "center_sigma_px": d.debug.centerSigmaPx,
                "n_swatches": d.debug.swatchCount,
                "n_clusters": d.debug.clusters.count,
                "clusters": clusters,
            ] as [String: Any],
            "swatches": swatches,
            "label_counts": ["none": labelPixels[Int(paletteLabelNone)] ?? 0,
                             "discarded": labelPixels[Int(paletteLabelDiscarded)] ?? 0],
            "hits": d.analysis.hits.map { ["id": $0.comboId, "score": $0.score] as [String: Any] },
            "ambiguous": d.analysis.ambiguous ? 1 : 0,
            "explain": explain,
        ]
    }

    /// Recuento de cada valor de un mapa de etiquetas.
    static func counts(_ map: [UInt8]) -> [Int: Int] {
        var c = [Int](repeating: 0, count: 256)
        for v in map { c[Int(v)] += 1 }
        var out: [Int: Int] = [:]
        for (i, n) in c.enumerated() where n > 0 { out[i] = n }
        return out
    }
}
