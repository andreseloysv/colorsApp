// Buscador de la Rejilla (docs/design/DESIGN_SYSTEM.md §5.3), que sustituye a Explorar:
//   número  «12», « 012 », «Nº 12», «n.12» → esa combinación (Intro abre su detalle)
//   hex     «#C5A56E» o «c5a56e» → color de Wada más cercano según el MOTOR
//           (`srgbToLab` + `nearestDictionaryColor`, vía `ColorSearch.nearest(hex:)`) y las
//           combinaciones que lo contienen
//   texto   sin mayúsculas ni tildes sobre el nombre de la combinación (curado o propuesto),
//           su número y los nombres de sus colores (Ridgway, en inglés)
// Funciones puras (sin estado de vista) para poder probarlas.
import Foundation

enum RejillaSearch {
    enum Query: Equatable, Sendable {
        case empty
        /// Número válido (1…total).
        case number(Int)
        /// Parece un número pero no existe esa combinación.
        case numberOutOfRange(Int)
        /// Hex válido: color de Wada más cercano (motor).
        case color(ColorSearch.Match)
        /// Texto ya normalizado (`fold`).
        case text(String)
    }

    // Regex no es Sendable: se construye en cada consulta (barato para un campo de búsqueda).
    private static var numberPattern: Regex<AnyRegexOutput> { try! Regex(#"^\s*(?:[nN][º°oO.]?\s*)?(\d{1,3})\s*$"#) }
    private static var hexPattern: Regex<AnyRegexOutput> { try! Regex(#"^\s*#?([0-9a-fA-F]{6})\s*$"#) }

    /// "12", " 012 ", "Nº 12" → 12; nil si no es un número de 1 a `count`.
    static func parseNumber(_ text: String, count: Int) -> Int? {
        guard let n = numberValue(text), n >= 1, n <= count else { return nil }
        return n
    }

    /// Valor numérico si el texto tiene forma de número de combinación (sin validar el rango).
    static func numberValue(_ text: String) -> Int? {
        guard let match = text.wholeMatch(of: numberPattern), match.output.count > 1,
              let digits = match.output[1].substring else { return nil }
        return Int(digits)
    }

    /// "#c5a56e" / "C5A56E" → "#C5A56E"; nil si no son 6 dígitos hex.
    static func normalizedHex(_ text: String) -> String? {
        guard let match = text.wholeMatch(of: hexPattern), match.output.count > 1,
              let digits = match.output[1].substring else { return nil }
        return "#" + digits.uppercased()
    }

    /// Minúsculas, sin tildes, espacios colapsados.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "es_ES"))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Interpreta el texto del buscador. Un hex de 6 dígitos gana a un número («123456» es color).
    static func interpret(_ raw: String, count: Int) -> Query {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if let hex = normalizedHex(trimmed), let match = ColorSearch.nearest(hex: hex) {
            return .color(match)
        }
        if let n = numberValue(trimmed) {
            return (1...max(count, 1)).contains(n) ? .number(n) : .numberOutOfRange(n)
        }
        let folded = fold(trimmed)
        return folded.isEmpty ? .empty : .text(folded)
    }

    /// Texto normalizado en el que se busca cada combinación: nombre, «nº 012» y colores.
    struct Index: Sendable {
        let haystacks: [Int: String]

        init(dictionary: WadaDictionary, naming: ComboNaming) {
            var map: [Int: String] = [:]
            for combo in dictionary.combinations {
                let name = naming.name(for: combo.id, in: dictionary).text
                let colors = dictionary.colors(of: combo).map(\.name).joined(separator: " | ")
                map[combo.id] = RejillaSearch.fold("\(name) | \(WadaDictionary.numberLabel(combo.id)) | \(colors)")
            }
            haystacks = map
        }
    }

    /// Combinaciones que cumplen la consulta, en orden de número.
    static func filter(_ combos: [WadaCombo], query: Query, index: Index) -> [WadaCombo] {
        switch query {
        case .empty:
            return combos
        case .number(let id):
            return combos.filter { $0.id == id }
        case .numberOutOfRange:
            return []
        case .color(let match):
            return combos.filter { $0.colors.contains(match.index) }
        case .text(let needle):
            return combos.filter { index.haystacks[$0.id]?.contains(needle) == true }
        }
    }
}
