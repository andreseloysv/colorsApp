// Capas de un análisis (requisito del usuario: «The colors are not right. It
// will be helpful for me to see the layers from which the color is being
// extracted»). Once capas en el orden del pipeline, todas del MISMO análisis
// guardado en memoria (ScanOutcome: raster, SubjectMaskResult de SubjectKit y
// PaletteDebugLayers del motor); construirlas no vuelve a ejecutar Vision ni el
// motor, solo pinta mapas de bits. Cada capa lleva título, una frase de qué
// significa, sus números y avisos. Reproducible desde la línea de comandos:
// `visionmask --layers` (capas 4–7) y `ce match --mask --debug-dir` / `ce garments`
// (capas 3, 8–12). La capa 8, «Prendas» (ADR-011), va entre la máscara final y la
// asignación a colores: es donde se ve por qué un pantalón con sombras es UN color.
import Foundation
import CoreGraphics
import ColorEngine
import SubjectKit

struct InspectorLayer: Identifiable, Sendable {
    enum Kind: Int, CaseIterable, Sendable {
        /// «Prendas» (`garments`) se intercaló en el 8 (ADR-011): entre la máscara final y el
        /// peso por píxel, que es donde ocurre en el motor (`ce_palette_extract_garments`).
        case photo = 1, raster, reduced, people, pose, skin, finalMask, garments, weights, labels, palette, explanation
    }

    let kind: Kind
    let title: String
    /// Una frase: qué significa la capa.
    let meaning: String
    /// Números de la capa, una línea cada uno.
    var facts: [String] = []
    /// Aviso (retorno, salvaguarda, capa vacía...).
    var warning: String? = nil
    /// Mapa de bits superpuesto a la foto (nil en foto, paleta y explicación).
    var overlay: CGImage? = nil
    /// Escalado sin interpolación (capas de la imagen reducida).
    var pixelated = false
    /// Opacidad inicial del control.
    var defaultOpacity = 1.0

    var id: Int { kind.rawValue }
    var number: Int { kind.rawValue }
}

/// Un swatch de la paleta final con su recuento de píxeles y el color más cercano del diccionario.
struct SwatchRow: Identifiable, Sendable {
    let index: Int
    let swatch: Swatch
    let pixels: Int
    let nearestColorName: String
    let nearestColorHex: String
    let nearestDeltaE: Double
    var id: Int { index }
}

/// Un tono (cluster de Lloyd) agrupado dentro de un color de prenda: la luz, la sombra o el
/// pliegue de la MISMA tela.
struct GarmentToneRow: Identifiable, Sendable {
    let index: Int
    let hex: String
    let rgb: (UInt8, UInt8, UInt8)
    /// Peso del cluster sobre el total de la imagen (antes de agrupar).
    let weight: Double
    let pixels: Int
    var id: Int { index }
}

/// Un color de la paleta POR PRENDA con su región, su cuota y los tonos que se agruparon en él.
struct GarmentRow: Identifiable, Sendable {
    /// Índice del swatch en la paleta final (0-based).
    let index: Int
    let swatch: Swatch
    /// `CE_GARMENT_REGION_*`: 1 arriba, 2 abajo, 3 prenda entera, 0 sin mapa.
    let region: Int
    let regionLabel: String
    /// Cuota de la región sobre el área que cubre el mapa (0...1).
    let regionShare: Double
    /// Cuota de este color DENTRO de su región (peso final / cuota de la región).
    let shareInRegion: Double
    let mergedClusters: Int
    let pixels: Int
    let tones: [GarmentToneRow]
    /// Por qué el motor lo dejó en un solo color (o en dos).
    let reason: String
    var id: Int { index }
}

/// Un cluster de Lloyd que no llegó tal cual a la paleta.
struct ClusterRow: Identifiable, Sendable {
    let index: Int
    let hex: String
    let rgb: (UInt8, UInt8, UInt8)
    let weight: Double
    let pixels: Int
    let fate: ClusterFate
    /// Motivo en lenguaje claro.
    let reason: String
    var id: Int { index }
}

/// Por qué una combinación del top-3 tiene su score.
struct ExplanationCard: Identifiable, Sendable {
    struct SwatchLine: Identifiable, Sendable {
        let swatch: Int
        let swatchHex: String
        let swatchWeight: Double
        let colorIndex: Int
        let colorName: String
        let colorHex: String
        let deltaE: Double
        var id: Int { swatch }
    }

    struct ColorLine: Identifiable, Sendable {
        let colorIndex: Int
        let colorName: String
        let colorHex: String
        let nearestSwatch: Int
        let swatchHex: String
        let deltaE: Double
        var id: Int { colorIndex }
    }

    let rank: Int
    let comboId: Int
    let title: String
    let comboHexes: [String]
    let score: Double
    let fitTerm: Double
    let coverageTerm: Double
    let hypothesisPenalty: Double
    let exposureEV: Double
    let illuminant: Int
    /// "Sin corrección", "Exposición +0,5 EV", "Luz A (tungsteno) sin balance de blancos"...
    let hypothesis: String
    let swatchLines: [SwatchLine]
    let colorLines: [ColorLine]
    /// Resumen en lenguaje claro.
    let summary: String
    var id: Int { rank }
}

struct LayerStack: Sendable {
    let photo: CGImage
    let rasterWidth: Int
    let rasterHeight: Int
    let layers: [InspectorLayer]
    /// Poses a dibujar sobre la capa 5 (en píxeles del raster) con su color.
    let poses: [(pose: Pose, colorIndex: Int)]
    let swatches: [SwatchRow]
    /// Colores por prenda de la capa 8 (vacío en el camino clásico, sin pose).
    let garments: [GarmentRow]
    let clusters: [ClusterRow]
    let explanations: [ExplanationCard]
    /// Swatch por píxel de la reducida (para aislar un swatch).
    let labelMap: [UInt8]
    let reducedWidth: Int
    let reducedHeight: Int
    let notice: MaskStepsText.Notice
    let header: [String]

    func layer(_ kind: InspectorLayer.Kind) -> InspectorLayer? { layers.first { $0.kind == kind } }

    /// Número con coma decimal (es_ES) y `digits` decimales.
    static func num(_ value: Double, _ digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(Locale(identifier: "es_ES")))
    }

    /// Construye las 12 capas. Puro y síncrono: llamar fuera del MainActor.
    static func build(outcome o: ScanOutcome, dictionary: WadaDictionary,
                      paletteOptions: PaletteOptions = .default, matchOptions: MatchOptions = EngineBridge.appMatchOptions) -> LayerStack {
        let w = o.raster.width, h = o.raster.height
        let s = o.subject
        let opts = o.subjectOptions
        let photo = o.image
        var layers: [InspectorLayer] = []
        let pct = { (v: Double) in SubjectExplanation.percent(v) }

        // 1. Foto.
        layers.append(InspectorLayer(
            kind: .photo, title: "Foto",
            meaning: "La imagen tal como llegó a la app, ya girada según su orientación.",
            facts: ["\(photo.width) × \(photo.height) px"]))

        // 2. Lo que ve el motor.
        layers.append(InspectorLayer(
            kind: .raster, title: "Lo que ve el motor",
            meaning: "Los píxeles convertidos a sRGB de 8 bits y reducidos a 1024 px como máximo: la misma imagen para Vision y para el motor de color.",
            facts: ["\(w) × \(h) px · sRGB · \(o.raster.stride / max(1, w)) bytes por píxel",
                    "Rasterizado en \(num(o.timings.rasterMs, 0)) ms"],
            overlay: PNGCoding.cgImage(from: o.raster), defaultOpacity: 1))

        // 3. Imagen reducida.
        var reduced = InspectorLayer(
            kind: .reduced, title: "Imagen reducida",
            meaning: "Lo que se agrupa en colores: cada píxel es la media de un bloque del raster (256 px como máximo).")
        if let d = o.debug {
            let rw = d.debug.reducedWidth, rh = d.debug.reducedHeight
            let block = (max(w, h) + Int(paletteOptions.maxSide) - 1) / max(1, Int(paletteOptions.maxSide))
            reduced.overlay = LayerBitmaps.rgbImage(width: rw, height: rh, rgb: d.reducedRGB)
            reduced.pixelated = true
            reduced.facts = ["\(rw) × \(rh) px (bloques de \(max(1, block)) × \(max(1, block)) px)",
                             "\(d.debug.clusters.count) clusters de Lloyd (k inicial \(paletteOptions.kInit)) · \(d.debug.lloydIterations) iteraciones"]
        } else {
            reduced.warning = "Sin capas del motor en este resultado."
        }
        layers.append(reduced)

        // 4. Personas detectadas.
        var peopleLayer = InspectorLayer(
            kind: .people, title: "Personas detectadas",
            meaning: "Vision separa a cada persona de la foto (hasta 4); cada una va de un color y la que se usa va resaltada con contorno. Las siluetas sin cuerpo (sin pose, cara ni forma de persona) se descartan.")
        let chosenIds: Set<Int> = {
            if opts.mode == .allPeople { return Set(s.people.map(\.id)) }
            if let i = s.chosenIndex, i < s.people.count { return [s.people[i].id] }
            return []
        }()
        if !s.people.isEmpty {
            peopleLayer.overlay = LayerBitmaps.people(overlay: s.layers.allPeopleOverlay, width: w, height: h,
                                                      people: s.people, highlightIds: chosenIds)
            peopleLayer.defaultOpacity = 0.85
        }
        let peopleText = SubjectExplanation.peopleLayer(options: opts, result: s, chosenIds: chosenIds, visionMs: o.timings.visionMs)
        peopleLayer.facts = peopleText.facts
        peopleLayer.warning = peopleText.warning
        layers.append(peopleLayer)

        // 5. Pose y región de ropa.
        var poseLayer = InspectorLayer(
            kind: .pose, title: "Pose y región de ropa",
            meaning: "Con el esqueleto de la pose el motor se queda con torso, brazos y piernas y quita cabeza y manos, siempre dentro de la silueta del cuerpo (contorno blanco). Si faltan las caderas, se estiman.")
        let regionMasks = s.layers.persons.compactMap(\.regionMask)
        if let union = MaskOps.union(regionMasks) {
            poseLayer.overlay = LayerBitmaps.regionWithSilhouette(
                region: union, silhouette: MaskOps.union(s.layers.persons.compactMap(\.silhouetteMask)), width: w, height: h)
        }
        var poses: [(pose: Pose, colorIndex: Int)] = []
        for person in s.layers.persons {
            if let pose = SubjectExplanation.drawnPose(person) { poses.append((pose, person.personIndex)) }
        }
        poseLayer.defaultOpacity = 0.8
        let poseText = SubjectExplanation.poseLayer(options: opts, result: s)
        poseLayer.facts = poseText.facts
        poseLayer.warning = poseText.warning
        layers.append(poseLayer)

        // 6. Piel excluida.
        var skinLayer = InspectorLayer(
            kind: .skin, title: "Piel excluida",
            meaning: "El motor aprende el tono de piel de la cara de cada persona (contorno amarillo; si no se le ve la cara, el de otra persona de la foto) y quita de la región los píxeles de ese tono (magenta).")
        let removed = MaskOps.union(s.layers.persons.compactMap(\.skinRemovedMask))
        let samples = MaskOps.union(s.layers.persons.compactMap(\.faceSampleMask))
        if removed != nil || samples != nil {
            skinLayer.overlay = LayerBitmaps.skin(removed: removed, faceSample: samples, width: w, height: h)
        }
        let skinText = SubjectExplanation.skinLayer(options: opts, result: s)
        skinLayer.facts = skinText.facts
        skinLayer.warning = skinText.warning
        layers.append(skinLayer)

        // 7. Máscara final.
        var maskLayer = InspectorLayer(
            kind: .finalMask, title: "Máscara final",
            meaning: "Lo único que mira el motor: fuera de la máscara (oscuro) los píxeles no cuentan. La región de ropa basta si es una parte suficiente de la silueta de la propia persona.")
        if let mask = s.mask {
            maskLayer.overlay = LayerBitmaps.dimOutside(mask: mask, width: w, height: h)
        }
        let maskText = SubjectExplanation.maskLayer(options: opts, result: s, maskMs: o.timings.maskMs)
        maskLayer.facts = maskText.facts
        maskLayer.warning = maskText.warning
        layers.append(maskLayer)

        // 8. Prendas (paleta por prenda, ADR-011).
        var garmentLayer = InspectorLayer(
            kind: .garments, title: "Prendas",
            meaning: "Con la pose, la máscara se reparte en la parte de arriba (torso y brazos) y la de abajo (caderas a tobillos). Dentro de cada prenda, los tonos de la MISMA tela con distinta luz —sombra, pliegues— se juntan en un color y se muestra el tono iluminado, no la media.")
        var garmentRows: [GarmentRow] = []
        if o.usesGarments {
            garmentRows = Self.garmentRows(o, dictionary: dictionary)
            if let g = o.garmentLayers {
                garmentLayer.overlay = LayerBitmaps.garmentRegions(g.regionMap, width: g.reducedWidth, height: g.reducedHeight)
                garmentLayer.pixelated = true
                garmentLayer.defaultOpacity = 0.75
            }
            garmentLayer.facts = Self.garmentFacts(o, rows: garmentRows)
            if garmentRows.contains(where: { $0.region == GarmentRegion.whole.rawValue }) {
                garmentLayer.facts.append("Arriba y abajo salieron del mismo color: el motor las juntó en una sola prenda (vestido o mono).")
            }
        } else {
            garmentLayer.warning = maskedWithoutPose(s)
                ? "Sin pose utilizable en esta foto: no hay regiones de prenda y la paleta sale del camino clásico (un color por grupo de tonos de toda la máscara)."
                : "Esta foto se analizó sin regiones de prenda (sin persona, sin pose o con la foto completa): paleta clásica."
        }
        layers.append(garmentLayer)

        // 9. Peso por píxel.
        var weightLayer = InspectorLayer(
            kind: .weights, title: "Peso por píxel",
            meaning: "Cuánto cuenta cada píxel al agrupar: máscara × preferencia por el centro. Amarillo cuenta mucho, negro nada.")
        // 10. Asignación a colores.
        var labelLayer = InspectorLayer(
            kind: .labels, title: "Asignación a colores",
            meaning: "A qué color de la paleta alimenta cada píxel. Gris rayado: su grupo se descartó; oscuro: no pesa. Toca un color para aislar sus píxeles.")
        var swatchRows: [SwatchRow] = []
        var clusterRows: [ClusterRow] = []
        var labelMap: [UInt8] = []
        var rw = 0, rh = 0
        if let d = o.debug {
            rw = d.debug.reducedWidth
            rh = d.debug.reducedHeight
            labelMap = d.labelMap
            weightLayer.overlay = LayerBitmaps.heatmap(weights: d.weightMap, width: rw, height: rh)
            weightLayer.pixelated = true
            weightLayer.defaultOpacity = 0.9
            weightLayer.facts = [
                "Gaussiana al centro: σ = \(num(d.debug.centerSigmaPx, 1)) px de la reducida (\(num(paletteOptions.centerSigma, 2)) del lado)",
                "Peso 0 en \(pct(d.debug.zeroWeightFraction)) de la imagen reducida",
            ]
            let labelCounts = DiagnosticsSubject.counts(d.labelMap)
            let clusterCounts = DiagnosticsSubject.counts(d.clusterMap)
            labelLayer.overlay = LayerBitmaps.labels(d.labelMap, width: rw, height: rh, swatches: d.analysis.swatches)
            labelLayer.pixelated = true
            labelLayer.defaultOpacity = 0.9
            labelLayer.facts = [
                "\(d.analysis.swatches.count) colores · \(labelCounts[Int(paletteLabelDiscarded)] ?? 0) px descartados · \(labelCounts[Int(paletteLabelNone)] ?? 0) px sin peso",
                "Fusión si ΔE00 < \(num(paletteOptions.mergeDeltaE, 1)) · descarte si el grupo pesa < \(num(paletteOptions.minWeight * 100, 0)) % · máximo \(paletteOptions.maxColors) colores",
            ]
            for (i, sw) in d.analysis.swatches.enumerated() {
                let near = nearestDictionaryColor(sw.lab)
                let c = dictionary.color(index: near.index)
                swatchRows.append(SwatchRow(index: i, swatch: sw, pixels: labelCounts[i] ?? 0,
                                            nearestColorName: c?.name ?? "Color \(near.index)",
                                            nearestColorHex: c?.hex ?? "", nearestDeltaE: near.deltaE))
            }
            for (i, c) in d.debug.clusters.enumerated() where c.fate != .kept {
                let reason: String
                switch c.fate {
                case .kept:
                    reason = ""
                case .merged:
                    let target = c.finalIndex.map { "el color \($0 + 1)" } ?? "otro color"
                    reason = "Fusionado en \(target): a menos de \(num(paletteOptions.mergeDeltaE, 1)) ΔE00 del representante de su grupo."
                case .discarded:
                    reason = "Descartado: su grupo pesaba menos del \(num(paletteOptions.minWeight * 100, 0)) % del total."
                case .truncated:
                    reason = "Recortado: la paleta ya tenía \(paletteOptions.maxColors) colores más pesados."
                }
                clusterRows.append(ClusterRow(index: i, hex: c.hex, rgb: (c.r, c.g, c.b), weight: c.weight,
                                              pixels: clusterCounts[i] ?? 0, fate: c.fate, reason: reason))
            }
            weightLayer.facts.append("Motor (paleta + match + capas): \(num(o.timings.engineMs, 0)) ms")
        } else {
            weightLayer.warning = "Sin capas del motor en este resultado."
            labelLayer.warning = "Sin capas del motor en este resultado."
        }
        layers.append(weightLayer)
        layers.append(labelLayer)

        // 11. Paleta final.
        var paletteLayer = InspectorLayer(
            kind: .palette, title: "Paleta final",
            meaning: "Los colores que el motor compara con el diccionario y cuánto pesa cada uno.")
        paletteLayer.facts = o.result.swatches.enumerated().map { i, sw in
            "\(i + 1). \(sw.hex.uppercased()) · \(num(sw.weight * 100, 1)) %"
        }
        layers.append(paletteLayer)

        // 12. Por qué ganó.
        var whyLayer = InspectorLayer(
            kind: .explanation, title: "Por qué ganó",
            meaning: "Para cada una de las 3 mejores: qué color de la combinación explica cada color de la foto, cuánto falta por cubrir y qué corrección de luz se supuso.")
        let cards = explanationCards(o, dictionary: dictionary, matchOptions: matchOptions)
        if cards.isEmpty { whyLayer.warning = "Sin explicación del match en este resultado." }
        whyLayer.facts = o.result.ambiguous ? ["Resultado ambiguo: las dos primeras están a menos de \(num(matchOptions.ambiguousGap, 1)) de score."] : []
        layers.append(whyLayer)

        let notice = SubjectExplanation.notice(options: opts, result: s)
        var header = ["Motor \(o.scan.engineVersion) · diccionario \(o.scan.dictVersion)",
                      "Tiempos: Vision \(num(o.timings.visionMs, 0)) ms · máscara \(num(o.timings.maskMs, 0)) ms · motor \(num(o.timings.engineMs, 0)) ms · total \(num(o.timings.totalMs, 0)) ms"]
        header.insert("Recorte: \(opts.mode.rawValue) · \(opts.region.rawValue) · piel \(opts.adaptiveSkin ? "sí" : "no") — \(notice.text)", at: 0)
        return LayerStack(photo: photo, rasterWidth: w, rasterHeight: h, layers: layers, poses: poses,
                          swatches: swatchRows, garments: garmentRows, clusters: clusterRows, explanations: cards,
                          labelMap: labelMap, reducedWidth: rw, reducedHeight: rh, notice: notice, header: header)
    }

    /// true si hubo máscara de persona pero sin pose utilizable: es el caso en el que la capa
    /// «Prendas» no existe aunque sí hay recorte (recorte de cabeza).
    private static func maskedWithoutPose(_ s: SubjectMaskResult) -> Bool {
        s.mask != nil && !s.people.isEmpty && s.garmentRegions == nil
    }

    /// Filas de la capa 8: un color por prenda con los tonos que se agruparon en él.
    static func garmentRows(_ o: ScanOutcome, dictionary: WadaDictionary) -> [GarmentRow] {
        let labelCounts = o.debug.map { DiagnosticsSubject.counts($0.labelMap) } ?? [:]
        let clusterCounts = o.debug.map { DiagnosticsSubject.counts($0.clusterMap) } ?? [:]
        let clusters = o.debug?.debug.clusters ?? []
        return o.garments.enumerated().map { i, g in
            let tones = clusters.enumerated()
                .filter { $0.element.finalIndex == i }
                .map { j, c in
                    GarmentToneRow(index: j, hex: c.hex.uppercased(), rgb: (c.r, c.g, c.b), weight: c.weight,
                                   pixels: clusterCounts[j] ?? 0)
                }
            let share = g.regionShare > 0 ? min(1, g.swatch.weight / g.regionShare) : g.swatch.weight
            return GarmentRow(index: i, swatch: g.swatch, region: g.region.rawValue,
                              regionLabel: GarmentText.regionLabel(g.region), regionShare: g.regionShare,
                              shareInRegion: share, mergedClusters: g.mergedClusterCount,
                              pixels: labelCounts[i] ?? 0, tones: tones,
                              reason: GarmentText.groupingReason(mergedClusters: g.mergedClusterCount))
        }
    }

    /// Números de la capa 8: mapa de la pose, regiones y un renglón por color de prenda.
    static func garmentFacts(_ o: ScanOutcome, rows: [GarmentRow]) -> [String] {
        var facts: [String] = []
        if let stats = o.subject.layers.primary?.garmentRegionStats {
            let total = max(1, stats.maskPixels)
            facts.append("Mapa de la pose: arriba \(SubjectExplanation.count(stats.upperPixels)) px · abajo "
                         + "\(SubjectExplanation.count(stats.lowerPixels)) px de \(SubjectExplanation.count(total)) px de la máscara")
            if stats.lowerMergedIntoUpper {
                facts.append("Caderas estimadas (no se ve la parte de abajo): sus \(SubjectExplanation.count(stats.mergedLowerPixels)) px pasaron a la parte de arriba.")
            }
        }
        let regions = Set(rows.map(\.region)).count
        facts.append("\(regions) \(regions == 1 ? "prenda" : "prendas") · \(rows.count) \(rows.count == 1 ? "color" : "colores") en total")
        for row in rows {
            facts.append("\(row.index + 1). \(row.regionLabel): \(row.swatch.hex.uppercased()) · "
                         + "\(SubjectExplanation.percent(row.shareInRegion)) de su prenda · "
                         + "\(row.mergedClusters) \(row.mergedClusters == 1 ? "tono agrupado" : "tonos agrupados")")
        }
        return facts
    }

    static func illuminantText(_ illuminant: Int) -> String {
        switch illuminant {
        case 0: "luz A (tungsteno)"
        case 1: "luz D50 (día cálido)"
        case 2: "luz D65 (día)"
        case 3: "luz D75 (sombra, fría)"
        case 4: "luz F2 (fluorescente)"
        default: "luz \(illuminant)"
        }
    }

    static func hypothesisText(exposureEV: Double, illuminant: Int) -> String {
        var parts: [String] = []
        if exposureEV != 0 {
            parts.append("exposición \(exposureEV > 0 ? "+" : "")\(num(exposureEV, 1)) EV")
        }
        if illuminant >= 0 {
            parts.append("\(illuminantText(illuminant)) sin balance de blancos")
        }
        return parts.isEmpty ? "Sin corrección (la foto tal cual)" : MaskStepsText.capitalizedFirst(parts.joined(separator: " y "))
    }

    static func explanationCards(_ o: ScanOutcome, dictionary: WadaDictionary, matchOptions: MatchOptions) -> [ExplanationCard] {
        guard let d = o.debug else { return [] }
        let swatches = d.analysis.swatches
        let best = d.explanations.first?.score
        return d.explanations.enumerated().map { rank, e in
            let combo = dictionary.combo(id: e.comboId)
            let swatchLines = e.perSwatch.enumerated().map { i, p -> ExplanationCard.SwatchLine in
                let c = dictionary.color(index: p.nearestColorIndex)
                return ExplanationCard.SwatchLine(swatch: i, swatchHex: i < swatches.count ? swatches[i].hex : "",
                                                  swatchWeight: i < swatches.count ? swatches[i].weight : 0,
                                                  colorIndex: p.nearestColorIndex, colorName: c?.name ?? "Color \(p.nearestColorIndex)",
                                                  colorHex: c?.hex ?? "", deltaE: p.deltaE)
            }
            let colorLines = e.perColor.map { p -> ExplanationCard.ColorLine in
                let c = dictionary.color(index: p.colorIndex)
                return ExplanationCard.ColorLine(colorIndex: p.colorIndex, colorName: c?.name ?? "Color \(p.colorIndex)",
                                                 colorHex: c?.hex ?? "", nearestSwatch: p.nearestSwatch,
                                                 swatchHex: p.nearestSwatch < swatches.count ? swatches[p.nearestSwatch].hex : "",
                                                 deltaE: p.deltaE)
            }
            let hypothesis = hypothesisText(exposureEV: e.exposureEV, illuminant: e.illuminant)
            var summary = "Score \(num(e.score, 2)) = ajuste \(num(e.fitTerm, 2)) + cobertura \(num(e.coverageTerm, 2)) + penalización \(num(e.hypothesisPenalty, 2)). "
            summary += "Ajuste: de media, cada color de la foto está a \(num(e.fitTerm, 2)) ΔE00 de su color más cercano de la combinación. "
            let meanCoverage = matchOptions.coverageLambda > 0 ? e.coverageTerm / matchOptions.coverageLambda : 0
            summary += "Cobertura: cada color de la combinación está, de media, a \(num(meanCoverage, 2)) ΔE00 del color más cercano de la foto. "
            if e.hypothesisPenalty > 0 {
                summary += "Se supuso \(hypothesis.lowercased()) (penalización \(num(e.hypothesisPenalty, 2))). "
            } else {
                summary += "Sin corrección de luz. "
            }
            if rank == 0 {
                summary += "Gana por tener el score más bajo."
            } else if let best {
                summary += "Queda a \(num(e.score - best, 2)) de la primera."
            }
            return ExplanationCard(rank: rank + 1, comboId: e.comboId, title: dictionary.displayName(id: e.comboId),
                                   comboHexes: combo.map { dictionary.colors(of: $0).map(\.hex) } ?? [],
                                   score: e.score, fitTerm: e.fitTerm, coverageTerm: e.coverageTerm,
                                   hypothesisPenalty: e.hypothesisPenalty, exposureEV: e.exposureEV,
                                   illuminant: e.illuminant, hypothesis: hypothesis, swatchLines: swatchLines,
                                   colorLines: colorLines, summary: summary)
        }
    }
}
