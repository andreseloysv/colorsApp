// Nombres de las combinaciones para la Rejilla (docs/design/DESIGN_SYSTEM.md §2.4 regla 4 y
// §5.5-3): el curado y aceptado de names.es.json (ruta protegida, vía WadaDictionary) →
// el propuesto de data/wada/names.suggested.json (`name_es`, recurso de solo lectura del
// bundle) marcado como «Nombre propuesto» → «Nº 067». Nunca se inventan nombres en Swift.
import Foundation

/// Nombre a mostrar de una combinación y de dónde sale.
struct ComboName: Hashable, Sendable {
    enum Kind: String, Sendable {
        /// Aceptado por el usuario en names.es.json.
        case curated
        /// Propuesta de names.suggested.json (pendiente de que el usuario elija).
        case proposed
        /// Sin nombre: «Nº 067».
        case number
    }

    let text: String
    let kind: Kind

    var isProposed: Bool { kind == .proposed }

    /// Rótulo corto del origen para tarjetas y hojas.
    var kindLabel: String {
        switch kind {
        case .curated: "Tu nombre"
        case .proposed: "Nombre propuesto"
        case .number: "Sin nombre"
        }
    }
}

/// Nombres propuestos cargados del bundle (names.suggested.json) + reglas de prioridad.
struct ComboNaming: Sendable {
    static let suggestedResource = "names.suggested"

    /// id de combinación → `name_es` propuesto (recortado, no vacío).
    let proposed: [Int: String]

    init(proposed: [Int: String]) {
        self.proposed = proposed
    }

    /// Sin propuestas (todo cae al nombre curado o al número).
    static let empty = ComboNaming(proposed: [:])
    /// Alias de `empty` (lo usan otras pantallas y sus tests; escribir `ComboNaming.none` con el tipo explícito).
    static let none = empty

    /// Propuestas del bundle principal (se leen una vez).
    static let bundled: ComboNaming = load(bundle: .main)

    private struct File: Decodable {
        struct Suggestion: Decodable {
            let id: Int
            let nameEs: String

            enum CodingKeys: String, CodingKey {
                case id
                case nameEs = "name_es"
            }
        }

        let suggestions: [Suggestion]
    }

    /// Lee names.suggested.json del bundle; sin fichero o con JSON inválido, sin propuestas.
    static func load(bundle: Bundle) -> ComboNaming {
        guard let url = bundle.url(forResource: suggestedResource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return .empty }
        return (try? decode(data)) ?? .empty
    }

    static func decode(_ data: Data) throws -> ComboNaming {
        let file = try JSONDecoder().decode(File.self, from: data)
        var map: [Int: String] = [:]
        for s in file.suggestions {
            let name = s.nameEs.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, map[s.id] == nil { map[s.id] = name }
        }
        return ComboNaming(proposed: map)
    }

    /// Curado → propuesto → «Nº 067».
    func name(for id: Int, in dictionary: WadaDictionary) -> ComboName {
        if let curated = dictionary.curatedName(id: id) {
            return ComboName(text: curated, kind: .curated)
        }
        if let proposal = proposed[id] {
            return ComboName(text: proposal, kind: .proposed)
        }
        return ComboName(text: WadaDictionary.numberLabel(id), kind: .number)
    }
}
