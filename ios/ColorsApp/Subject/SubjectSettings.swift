// Recorte de sujeto en la app (docs/DECISIONS.md, ADR-010): ajustes persistidos,
// lo que se guarda de cada scan y el aviso en lenguaje claro con los pasos que
// aplicó la cadena de SubjectKit. Vision solo detecta personas, pose y caras; la
// región de ropa y la exclusión de piel las calcula el motor C.
import Foundation
import ColorEngine
import SubjectKit

/// Ajustes del recorte y del desbloqueo (tabla `settings`, claves
/// `subject_mode`, `region_mode`, `adaptive_skin`, `unlock_max_score`).
struct SubjectSettings: Equatable, Sendable {
    /// off | allPeople | largestPerson (`selectedPerson` solo existe en Resultado).
    var mode: SubjectMode = .largestPerson
    var region: RegionMode = .clothing
    var adaptiveSkin = true
    /// Score máximo del top-1 para desbloquear en el escaneo del carrete
    /// (informativo, ver ScanPolicy).
    var unlockMaxScore = ScanPolicy.defaultUnlockMaxScore

    /// Persona más grande + solo ropa + piel adaptativa + umbral 12,0 (decisión del usuario).
    static let `default` = SubjectSettings()

    /// Modos que ofrece Ajustes, en orden.
    static let settingsModes: [SubjectMode] = [.off, .allPeople, .largestPerson]

    /// Opciones de SubjectKit (cobertura mínima y opciones del motor por defecto).
    var subjectOptions: SubjectOptions {
        SubjectOptions(mode: mode, region: region, adaptiveSkin: adaptiveSkin)
    }

    /// Política del escaneo del carrete con el umbral de estos ajustes.
    func scanPolicy(base: ScanPolicy = .default) -> ScanPolicy {
        var policy = base
        policy.unlockMaxScore = unlockMaxScore
        return policy
    }
}

extension SubjectMode {
    /// Texto de Ajustes.
    var settingsTitle: String {
        switch self {
        case .off: "Desactivado"
        case .allPeople: "Todas las personas"
        case .largestPerson: "Persona principal"
        case .selectedPerson: "Persona elegida"
        }
    }
}

extension RegionMode {
    var settingsTitle: String {
        switch self {
        case .wholePerson: "Persona completa"
        case .clothing: "Solo ropa"
        }
    }
}

/// Lo que se persiste del recorte de un scan (columnas v2 de `scans`).
struct ScanSubjectInfo: Equatable, Sendable {
    var mode: SubjectMode
    var region: RegionMode
    var adaptiveSkin: Bool
    var peopleCount: Int
    var personIndex: Int?
    var steps: [MaskFallback]
    var maskCoverage: Double

    init(mode: SubjectMode, region: RegionMode, adaptiveSkin: Bool, peopleCount: Int, personIndex: Int?,
         steps: [MaskFallback], maskCoverage: Double) {
        self.mode = mode
        self.region = region
        self.adaptiveSkin = adaptiveSkin
        self.peopleCount = peopleCount
        self.personIndex = personIndex
        self.steps = steps
        self.maskCoverage = maskCoverage
    }

    init(options: SubjectOptions, result: SubjectMaskResult) {
        self.init(mode: options.mode, region: options.region, adaptiveSkin: options.adaptiveSkin,
                  peopleCount: result.people.count, personIndex: result.chosenIndex, steps: result.steps,
                  maskCoverage: result.maskCoverage)
    }
}

/// Aviso discreto de Resultado con los pasos aplicados, p. ej. "Solo ropa ·
/// piel excluida", "Sin persona: foto completa", "Prenda parecida a la piel:
/// no se excluyó".
enum MaskStepsText {
    struct Notice: Equatable, Sendable {
        let text: String
        /// SF Symbol.
        let systemImage: String
        /// true si la máscara no se aplicó como se pidió (retorno a foto completa, salvaguarda...).
        let isFallback: Bool
    }

    static func notice(options: SubjectOptions, result: SubjectMaskResult) -> Notice {
        let steps = result.steps
        if steps.contains(.visionUnavailable) {
            return Notice(text: "Vision no disponible: foto completa", systemImage: "eye.slash", isFallback: true)
        }
        if options.mode == .off {
            return Notice(text: "Recorte desactivado: foto completa", systemImage: "photo", isFallback: false)
        }
        if steps.contains(.noPeople) || result.people.isEmpty {
            return Notice(text: "Sin persona: foto completa", systemImage: "person.slash", isFallback: true)
        }
        var parts: [String] = []
        let n = result.people.count
        if options.mode == .allPeople {
            parts.append(n == 1 ? "1 persona" : "Todas las personas (\(n))")
        } else if n >= 2 {
            let index = result.chosenIndex ?? 0
            parts.append(index == 0 ? "Persona principal de \(n)" : "Persona \(index + 1) de \(n)")
        }
        if steps.contains(.poseRegions) && steps.contains(.headCut) {
            parts.append("solo ropa (pose o sin cabeza)")
        } else if steps.contains(.poseRegions) {
            parts.append("solo ropa")
        } else if steps.contains(.headCut) {
            parts.append("solo ropa (sin pose: sin la cabeza)")
        } else if options.region == .wholePerson {
            parts.append("persona completa")
        }
        var fallback = false
        if steps.contains(.skinGuard) {
            parts.append("prenda parecida a la piel: no se excluyó")
            fallback = true
        } else if steps.contains(.skinExcluded) {
            parts.append("piel excluida")
        } else if options.adaptiveSkin {
            let persons = result.layers.persons
            if persons.contains(where: { $0.skinNote != nil }) {
                parts.append("cara pequeña: piel sin excluir")
            } else if !persons.isEmpty, persons.allSatisfy({ $0.faceSampleMask == nil }) {
                parts.append("sin cara visible: piel sin excluir")
            }
        }
        if steps.contains(.wholePerson) {
            parts.append("recorte demasiado pequeño: persona completa")
            fallback = true
        }
        if steps.contains(.none) {
            parts.append("persona demasiado pequeña: foto completa")
            fallback = true
        }
        let text = capitalizedFirst(parts.joined(separator: " · "))
        let icon = result.mask == nil ? "person.crop.rectangle.badge.xmark" : "person.crop.rectangle"
        return Notice(text: text.isEmpty ? "Persona" : text, systemImage: icon, isFallback: fallback)
    }

    /// Nombre corto de un paso (inspector de capas y diagnóstico).
    static func stepTitle(_ step: MaskFallback) -> String {
        switch step {
        case .none: "Sin máscara"
        case .noPeople: "Sin personas"
        case .poseRegions: "Regiones de la pose"
        case .headCut: "Recorte de cabeza (sin pose)"
        case .wholePerson: "Persona completa (cobertura baja)"
        case .skinExcluded: "Piel excluida"
        case .skinGuard: "Salvaguarda de piel"
        case .visionUnavailable: "Vision no disponible"
        case .rejectedPhantom: "Persona fantasma descartada"
        case .garmentRegions: "Regiones de prenda (arriba / abajo)"
        }
    }

    static func capitalizedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}
