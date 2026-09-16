// Textos del recorte de sujeto sacados de lo que SubjectKit hizo DE VERDAD en un
// análisis: los pasos (`MaskFallback`), la decisión de región de cada persona
// (`RegionDecision`: regiones de la pose o silueta del cuerpo, caderas estimadas,
// fracción real del recorte de cabeza, brazos fuera), el respaldo cuando la máscara
// final no llega al suelo (`fallbackSource`), el donante del modelo de piel
// (`skinSampleSource`) y las siluetas sin cuerpo que se descartaron
// (`rejectedPhantoms`). Lo usan el aviso de Extraer/Resultado y las capas 4–7 del
// inspector. Sin lógica de color: solo lee resultados de SubjectKit y del motor.
//
// Casos nuevos de los enums de SubjectKit (su API crece de forma aditiva): cada
// `switch` lleva `@unknown default` con el nombre crudo del caso, así un paso nuevo se ve
// en la interfaz con su identificador en lugar de romper la compilación.
import Foundation
import ColorEngine
import SubjectKit

enum SubjectExplanation {
    /// Datos y aviso de una capa.
    struct LayerText: Equatable, Sendable {
        var facts: [String] = []
        var warning: String?
    }

    /// Por debajo de esta fracción de la foto una región de ropa se llama «pequeña»
    /// en la capa 7. Es la regla absoluta antigua (2 % del raster) que descartaba la
    /// ropa de personas pequeñas: se cita para explicar que ahora la suficiencia se
    /// mide contra la silueta de la propia persona y no contra la foto.
    static let smallRegionFraction = 0.02

    // MARK: Formato (coma decimal, espacio antes de %)

    private static let spanish = Locale(identifier: "es_ES")

    /// 0,036 → "3,6 %"; `digits` decimales.
    static func percent(_ fraction: Double, digits: Int = 1) -> String {
        let value = (fraction * 100).formatted(.number.precision(.fractionLength(digits)).locale(spanish))
        return "\(value)\u{00A0}%"
    }

    /// 12345 → "12.345".
    static func count(_ n: Int) -> String {
        n.formatted(.number.locale(spanish))
    }

    static func ms(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)).locale(spanish)) + "\u{00A0}ms"
    }

    private static func plural(_ n: Int, _ singular: String, _ pluralForm: String) -> String {
        "\(count(n)) \(n == 1 ? singular : pluralForm)"
    }

    private static func ratio(_ part: Int?, _ whole: Int?) -> Double? {
        guard let part, let whole, whole > 0 else { return nil }
        return Double(part) / Double(whole)
    }

    /// «Persona 2» (1-based) para textos de varias personas.
    private static func personName(_ index: Int) -> String { "Persona \(index + 1)" }

    // MARK: Aviso de Extraer / Resultado

    /// Aviso corto con los pasos reales («Solo ropa · piel excluida», «Persona 2 de 3 ·
    /// silueta del cuerpo · sin cara visible: piel sin excluir», «Sin persona: foto completa»…).
    static func notice(options: SubjectOptions, result: SubjectMaskResult) -> MaskStepsText.Notice {
        let steps = result.steps
        let phantoms = result.rejectedPhantoms.count
        if steps.contains(.visionUnavailable) {
            return .init(text: "Vision no disponible: foto completa", systemImage: "eye.slash", isFallback: true)
        }
        if options.mode == .off {
            return .init(text: "Recorte desactivado: foto completa", systemImage: "photo", isFallback: false)
        }
        if result.people.isEmpty || steps.contains(.noPeople) {
            let text = phantoms > 0
                ? "Sin persona (\(plural(phantoms, "silueta sin cuerpo descartada", "siluetas sin cuerpo descartadas"))): foto completa"
                : "Sin persona: foto completa"
            return .init(text: text, systemImage: "person.slash", isFallback: true)
        }
        var parts: [String] = []
        var fallback = false
        let n = result.people.count
        if options.mode == .allPeople {
            parts.append(n == 1 ? "1 persona" : "Todas las personas (\(n))")
        } else if n >= 2 {
            let index = result.chosenIndex ?? 0
            parts.append(index == 0 ? "Persona principal de \(n)" : "Persona \(index + 1) de \(n)")
        }
        let persons = result.layers.persons
        parts.append(contentsOf: unique(persons.compactMap { regionNotice($0, options: options) }))
        // Brazos fuera de la región (se ven en la paleta: mangas cortas o sin modelo de piel).
        if persons.contains(where: { $0.regionDecision?.bareArmsDropped == true }) {
            parts.append("brazos desnudos fuera")
        }
        if steps.contains(.skinGuard) {
            parts.append("prenda parecida a la piel: no se excluyó")
            fallback = true
        } else if steps.contains(.skinExcluded) {
            let donors = persons.compactMap { p -> Int? in
                guard p.skinExcludedPixels > 0, let s = p.skinSampleSource, s != p.personIndex else { return nil }
                return s
            }
            if let donor = donors.first {
                parts.append("piel excluida con la cara de la persona \(donor + 1)")
            } else {
                parts.append("piel excluida")
            }
        } else if options.adaptiveSkin, !persons.isEmpty {
            if persons.contains(where: { $0.skinNote != nil }) {
                parts.append("cara pequeña: piel sin excluir")
            } else if persons.allSatisfy({ $0.faceSampleMask == nil }) {
                parts.append("sin cara visible: piel sin excluir")
            }
        }
        if persons.contains(where: { $0.regionDecision?.upperArmsDropped == true }) {
            parts.append("brazos fuera")
        }
        if steps.contains(.wholePerson) {
            let silhouette = persons.contains { $0.fallbackSource == .poseSilhouette }
            parts.append(silhouette ? "recorte demasiado pequeño: silueta del cuerpo" : "recorte demasiado pequeño: persona completa")
            fallback = true
        }
        if steps.contains(.none) {
            parts.append("persona demasiado pequeña: foto completa")
            fallback = true
        }
        if phantoms > 0 {
            parts.append(plural(phantoms, "silueta sin cuerpo descartada", "siluetas sin cuerpo descartadas"))
        }
        let text = MaskStepsText.capitalizedFirst(parts.joined(separator: " · "))
        let icon = result.mask == nil ? "person.crop.rectangle.badge.xmark" : "person.crop.rectangle"
        return .init(text: text.isEmpty ? "Persona" : text, systemImage: icon, isFallback: fallback)
    }

    /// Región de una persona en el aviso.
    private static func regionNotice(_ p: PersonLayers, options: SubjectOptions) -> String? {
        if options.region == .wholePerson { return "persona completa" }
        guard let d = p.regionDecision else { return nil }
        switch d.source {
        case .poseRegions: return "solo ropa"
        case .poseSilhouette: return "silueta del cuerpo"
        case .headCut: return p.pose == nil ? "sin la cabeza (sin pose)" : "sin la cabeza (pose incompleta)"
        case .wholePerson: return "persona completa"
        @unknown default: return String(describing: d.source)
        }
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    // MARK: Pasos

    /// Nombre de cada paso tal como ocurrió en este análisis (capa 7, «Pasos: …»).
    static func stepTitles(result: SubjectMaskResult) -> [String] {
        let persons = result.layers.persons
        return result.steps.map { step in
            switch step {
            case .none:
                return "Sin máscara"
            case .noPeople:
                return "Sin personas"
            case .poseRegions:
                if persons.contains(where: { $0.regionDecision?.source == .poseSilhouette }) {
                    return "Silueta del cuerpo (pose)"
                }
                if persons.contains(where: { $0.steps.contains(.poseRegions) && $0.regionDecision?.source == .headCut }) {
                    return "Pose sin silueta útil"
                }
                return "Regiones de la pose"
            case .headCut:
                let fractions = persons.compactMap { $0.regionDecision?.headCutFraction }
                if fractions.count == 1, let f = fractions.first {
                    return "Recorte de cabeza (\(percent(f, digits: 0)) superior)"
                }
                return "Recorte de cabeza"
            case .wholePerson:
                return persons.contains(where: { $0.fallbackSource == .poseSilhouette })
                    ? "Respaldo: silueta del cuerpo" : "Respaldo: persona completa"
            case .skinExcluded:
                return "Piel excluida"
            case .skinGuard:
                return "Salvaguarda de piel"
            case .visionUnavailable:
                return "Vision no disponible"
            case .rejectedPhantom:
                return "Siluetas sin cuerpo descartadas (\(result.rejectedPhantoms.count))"
            case .garmentRegions:
                // Paso aditivo de SubjectKit (mapa de regiones de prenda con la pose: 1 arriba,
                // 2 abajo). No cambia la máscara; reparte sus píxeles entre prendas.
                return "Regiones de prenda (arriba / abajo)"
            @unknown default:
                return step.rawValue
            }
        }
    }

    // MARK: Capa 4 · Personas detectadas

    static func peopleLayer(options: SubjectOptions, result: SubjectMaskResult, chosenIds: Set<Int>,
                            visionMs: Double) -> LayerText {
        var t = LayerText()
        let people = result.people
        t.facts.append(people.count == 1 ? "1 persona" : "\(people.count) personas")
        for (i, p) in people.enumerated() {
            var line = "\(personName(i)): \(percent(p.coverage)) de la foto · pose \(p.pose != nil ? "sí" : "no") · cara \(p.faceSampleMask != nil ? "sí" : "no")"
            if chosenIds.contains(p.id) { line += " · usada" }
            t.facts.append(line)
        }
        let phantoms = result.rejectedPhantoms
        if !phantoms.isEmpty {
            t.facts.append("\(plural(phantoms.count, "silueta descartada", "siluetas descartadas")) por no tener cuerpo: sin pose con torso, sin cara y con forma de bloque o banda")
            for (i, r) in phantoms.enumerated() {
                t.facts.append("Descartada \(i + 1): \(percent(r.instance.coverage)) de la foto")
            }
        }
        if options.mode == .off {
            t.warning = "Recorte desactivado en Ajustes: no se buscan personas."
        } else if result.steps.contains(.visionUnavailable) {
            t.warning = "Vision no está disponible aquí (p. ej. en el simulador): se analiza la foto completa."
        } else if people.isEmpty, !phantoms.isEmpty {
            t.warning = "Vision devolvió \(plural(phantoms.count, "silueta", "siluetas")) sin cuerpo (personas fantasma): se \(phantoms.count == 1 ? "descartó" : "descartaron") y se analiza la foto completa."
        } else if people.isEmpty {
            t.warning = "Vision no encontró personas: se analiza la foto completa."
        }
        if result.timings["detect"] != nil {
            t.facts.append("Vision: \(ms(visionMs))")
        } else if !people.isEmpty {
            t.facts.append("Vision no se ejecutó en este análisis: personas reutilizadas (otra persona elegida o escena sintética).")
        }
        return t
    }

    // MARK: Capa 5 · Pose y región de ropa

    /// Pose que se dibuja: la que recibió el motor (con las caderas estimadas si hizo falta).
    static func drawnPose(_ p: PersonLayers) -> Pose? {
        p.regionDecision?.regionPose ?? p.pose
    }

    static func poseLayer(options: SubjectOptions, result: SubjectMaskResult) -> LayerText {
        var t = LayerText()
        let persons = result.layers.persons
        let w = result.width, h = result.height
        let many = persons.count > 1
        func who(_ p: PersonLayers) -> String { many ? "\(personName(p.personIndex)): " : "" }
        if let union = MaskOps.union(persons.compactMap(\.regionMask)) {
            t.facts.append("Región: \(percent(MaskOps.coverage(union, width: w, height: h))) de la foto")
        }
        if options.mode != .off, options.region == .wholePerson {
            t.facts.append("Región: persona completa (Ajustes > Recorte)")
        }
        var warnings: [String] = []
        for p in persons {
            guard let d = p.regionDecision else { continue }
            switch d.source {
            case .poseRegions:
                t.facts.append(who(p) + "regiones de la pose (\(regionParts(d.regionOptions))) · \(count(d.regionPixels)) px")
            case .poseSilhouette:
                t.facts.append(who(p) + "silueta del cuerpo según la pose · \(count(d.regionPixels)) px (capa 7)")
            case .headCut:
                warnings.append(who(p) + headCutText(p, d, options: options, width: w, height: h))
            case .wholePerson:
                t.facts.append(who(p) + "persona completa · \(count(d.regionPixels)) px")
            @unknown default:
                t.facts.append(who(p) + "región \(String(describing: d.source)) · \(count(d.regionPixels)) px")
            }
            if d.hipsEstimated {
                t.facts.append(who(p) + "caderas estimadas (plano medio: la pose no las veía); sin piernas")
            }
            if d.bareArmsDropped, let f = ratio(d.armSkinPixels, d.armPixels) {
                t.facts.append(who(p) + "brazos fuera: el \(percent(f, digits: 0)) de sus píxeles es piel (mínimo \(percent(options.bareArmsSkinFraction, digits: 0)))")
            }
            if d.upperArmsDropped {
                if let f = ratio(d.sleeveMatchPixels, d.sleevePixels) {
                    t.facts.append(who(p) + "sin modelo de piel, brazos fuera: solo el \(percent(f, digits: 0)) se parece a la prenda del torso (mangas desde \(percent(options.sleeveMatchFraction, digits: 0)))")
                } else {
                    t.facts.append(who(p) + "sin modelo de piel, brazos fuera (no se pudieron comparar con el torso)")
                }
            } else if d.sleevesKept, let f = ratio(d.sleeveMatchPixels, d.sleevePixels) {
                t.facts.append(who(p) + "sin modelo de piel, brazos dentro: el \(percent(f, digits: 0)) se parece a la prenda del torso (mangas)")
            }
        }
        if let ms = result.timings["regions"] { t.facts.append("Regiones: \(Self.ms(ms))") }
        if !warnings.isEmpty {
            t.warning = warnings.joined(separator: "\n")
        } else if persons.isEmpty {
            t.warning = options.mode == .off ? "Recorte desactivado: no hay región de ropa." : "Sin persona: no hay región de ropa."
        }
        t.facts = t.facts.map(MaskStepsText.capitalizedFirst)
        return t
    }

    private static func regionParts(_ o: RegionOptions?) -> String {
        guard let o else { return "torso" }
        var parts = ["torso"]
        if o.includeUpperArms { parts.append(o.includeForearms ? "brazos enteros" : "brazos") }
        if o.includeLegs { parts.append(o.includeLowerLegs ? "piernas" : "muslos") }
        return parts.joined(separator: ", ") + "; sin cabeza ni manos"
    }

    /// Por qué se usó el recorte de cabeza y con qué fracción real.
    private static func headCutText(_ p: PersonLayers, _ d: RegionDecision, options: SubjectOptions, width: Int, height: Int) -> String {
        let fraction = d.headCutFraction ?? SubjectExtractor.headCutFraction
        let cut = "se quitó el \(percent(fraction, digits: 0)) superior de la persona"
        let basis = fraction > SubjectExtractor.headCutFraction ? " (hasta la barbilla según la cara)" : ""
        if p.pose == nil {
            return "Sin pose: \(cut)\(basis) en lugar de usar la pose."
        }
        if let s = d.silhouettePixels {
            let floor = SubjectExtractor.floorPixels(options: options, width: width, height: height)
            return "La pose no describe a esta persona (su silueta mide \(count(s)) px, mínimo \(count(floor)) px): \(cut)\(basis)."
        }
        return "El motor no pudo usar la pose (faltan hombros o caderas con confianza): \(cut)\(basis)."
    }

    // MARK: Capa 6 · Piel excluida

    static func skinLayer(options: SubjectOptions, result: SubjectMaskResult) -> LayerText {
        var t = LayerText()
        let persons = result.layers.persons
        let many = persons.count > 1
        func who(_ p: PersonLayers) -> String { many ? "\(personName(p.personIndex)): " : "" }
        let excluded = persons.reduce(0) { $0 + $1.skinExcludedPixels }
        let halo = persons.reduce(0) { $0 + $1.skinHaloPixels }
        t.facts.append(halo > 0 ? "\(count(excluded)) px de piel quitados (\(count(halo)) del borde piel/prenda)"
                                : "\(count(excluded)) px de piel quitados")
        for p in persons {
            if let m = p.skinModel {
                let lab = "Lab medio \(fixed(m.mean.L)) \(fixed(m.mean.a)) \(fixed(m.mean.b))"
                if let source = p.skinSampleSource, source != p.personIndex {
                    t.facts.append(who(p) + "sin cara utilizable: modelo de la cara de la persona \(source + 1) (\(count(m.sampleCount)) muestras, \(lab))")
                } else {
                    t.facts.append(who(p) + "modelo de su cara con \(count(m.sampleCount)) muestras, \(lab)")
                }
                if !p.learnedSampleMasks.isEmpty {
                    t.facts.append(who(p) + "piel del cuerpo aprendida en \(plural(p.learnedSampleMasks.count, "pasada", "pasadas")) (brazos o piernas desnudos)")
                }
                if p.skinExcludedPixels == 0, !result.steps.contains(.skinGuard) {
                    t.facts.append(who(p) + "el modelo no encontró piel dentro de la región")
                }
            }
        }
        if let ms = result.timings["skin"] { t.facts.append("Piel: \(Self.ms(ms))") }
        let anyArmsDropped = persons.contains { $0.regionDecision?.upperArmsDropped == true }
        let anySleeves = persons.contains { $0.regionDecision?.sleevesKept == true }
        if !options.adaptiveSkin {
            t.warning = "Exclusión de piel desactivada en Ajustes."
        } else if result.steps.contains(.skinGuard) {
            t.warning = "Salvaguarda: se habría quitado más del \(percent(options.skinOptions.maxExcludedFraction, digits: 0)) de la región (prenda parecida a la piel), así que no se excluyó nada."
        } else if persons.contains(where: { $0.skinNote != nil }) {
            t.warning = "La muestra de la cara es demasiado pequeña (menos de \(SubjectExtractor.minSkinSamples) píxeles): piel sin excluir."
        } else if persons.isEmpty {
            t.warning = "Sin persona: no se excluye piel."
        } else if persons.allSatisfy({ $0.faceSampleMask == nil }) {
            var text = "No se ve ninguna cara utilizable (de espaldas, gafas, mascarilla) ni hay otra persona con cara: piel sin excluir"
            if anyArmsDropped {
                text += "; los brazos se quitaron de la región (capa 5)."
            } else if anySleeves {
                text += "; los brazos se quedan porque parecen mangas de la prenda del torso."
            } else {
                text += "."
            }
            t.warning = text
        }
        t.facts = t.facts.map(MaskStepsText.capitalizedFirst)
        return t
    }

    private static func fixed(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(1)).locale(spanish))
    }

    // MARK: Capa 7 · Máscara final

    static func maskLayer(options: SubjectOptions, result: SubjectMaskResult, maskMs: Double) -> LayerText {
        var t = LayerText()
        let w = result.width, h = result.height
        let rasterPixels = max(1, w * h)
        let floor = SubjectExtractor.floorPixels(options: options, width: w, height: h)
        let persons = result.layers.persons
        let many = persons.count > 1
        func who(_ p: PersonLayers) -> String { many ? "\(personName(p.personIndex)): " : "" }
        if result.mask != nil {
            t.facts.append("Cobertura: \(percent(result.maskCoverage)) de la foto")
        }
        var warnings: [String] = []
        for p in persons {
            guard let d = p.regionDecision else { continue }
            let minimum = "mínimo \(percent(options.minRegionFraction, digits: 0)) (\(count(d.requiredPixels)) px)"
            switch d.source {
            case .poseRegions:
                if let s = d.silhouettePixels, let f = ratio(d.regionPixels, s) {
                    let small = Double(d.regionPixels) / Double(rasterPixels) < smallRegionFraction
                    let head = small ? "Región de ropa pequeña pero suficiente para esta persona"
                                     : "Región de ropa suficiente"
                    t.facts.append(who(p) + "\(head): \(count(d.regionPixels)) px, el \(percent(f, digits: 0)) de la silueta de su pose (\(count(s)) px; \(minimum)). La suficiencia se mide contra la propia persona, no contra la foto.")
                }
            case .poseSilhouette:
                if let s = d.silhouettePixels {
                    let regions = d.poseRegionPixels ?? 0
                    let f = ratio(regions, s) ?? 0
                    t.facts.append(who(p) + "Se usó la silueta del cuerpo: la región de ropa (\(count(regions)) px) era solo el \(percent(f, digits: 0)) de la silueta de la pose (\(count(s)) px; \(minimum)).")
                }
            case .headCut:
                if p.pose == nil {
                    t.facts.append(who(p) + "Sin pose no hay silueta del cuerpo: los objetos pegados a la persona pueden quedar dentro.")
                } else if let s = d.silhouettePixels {
                    t.facts.append(who(p) + "La silueta de la pose (\(count(s)) px) no llega al mínimo de \(count(floor)) px: no se usa la pose.")
                }
            default:
                break
            }
            if let s = d.silhouettePixels, s >= floor, d.source != .headCut {
                let outside = max(0, d.bodyPixels - s)
                let f = ratio(outside, d.bodyPixels) ?? 0
                t.facts.append(who(p) + "Se recortó a la silueta del cuerpo: se excluyen objetos pegados (cochecito, bici, bolso). Quedan fuera \(count(outside)) px de la máscara de Vision (\(percent(f, digits: 0))), con la cabeza y las manos.")
            }
            if p.steps.contains(.wholePerson) || result.steps.contains(.wholePerson), let source = p.fallbackSource {
                let final = MaskOps.nonZero(p.finalMask)
                switch source {
                case .poseSilhouette:
                    warnings.append(who(p) + "La máscara final (\(count(final)) px) no llegaba al mínimo de \(count(floor)) px (\(percent(options.minCoverage, digits: 2)) de la foto): se usó la silueta del cuerpo según la pose.")
                case .wholePerson:
                    warnings.append(who(p) + "La máscara final (\(count(final)) px) no llegaba al mínimo de \(count(floor)) px (\(percent(options.minCoverage, digits: 2)) de la foto): se usó la persona completa de Vision (sin silueta de la pose; puede incluir objetos pegados).")
                default:
                    warnings.append(who(p) + "La máscara final no llegaba al mínimo de \(count(floor)) px: respaldo \(String(describing: source)).")
                }
            }
        }
        if result.mask == nil {
            if result.steps.contains(.none), !result.people.isEmpty {
                warnings.append("Ni la región ni su respaldo llegan a \(count(floor)) px (\(percent(options.minCoverage, digits: 2)) de la foto): sin máscara, se analiza la foto completa.")
            } else {
                warnings.append("Sin máscara: el motor analiza la foto completa.")
            }
        }
        let titles = stepTitles(result: result)
        t.facts.append("Pasos: " + (titles.isEmpty ? "—" : titles.joined(separator: " → ")))
        t.facts.append("Cadena de máscaras: \(ms(maskMs))")
        t.warning = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        return t
    }
}
