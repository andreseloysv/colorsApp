// Color de DATOS para los componentes (paleta del motor o color de Wada): sRGB8 +
// nombre + peso. Sin lógica de color en Swift: el nombre de Wada más cercano y su
// ΔE00 vienen del motor (`nearestDictionaryColor` sobre `srgbToLab`).
import SwiftUI
import ColorEngine

struct PaletteColor: Identifiable, Hashable, Sendable {
    /// Posición en la paleta (0-based) o índice estable que elija el llamador.
    let id: Int
    let r: UInt8
    let g: UInt8
    let b: UInt8
    /// Nombre a mostrar (color de Wada exacto o el más cercano); nil = solo hex.
    var name: String?
    /// Peso en la paleta (0…1); nil si no aplica (colores de una combinación).
    var weight: Double?
    /// ΔE00 al color de Wada nombrado (nil si el color ES de Wada o no se calculó).
    var deltaE: Double?

    init(id: Int, r: UInt8, g: UInt8, b: UInt8, name: String? = nil, weight: Double? = nil, deltaE: Double? = nil) {
        self.id = id
        self.r = r
        self.g = g
        self.b = b
        self.name = name
        self.weight = weight
        self.deltaE = deltaE
    }

    /// Desde "#rrggbb"; nil si el hex no es válido.
    init?(id: Int, hex: String, name: String? = nil, weight: Double? = nil, deltaE: Double? = nil) {
        guard let c = parseHexRGB(hex) else { return nil }
        self.init(id: id, r: c.r, g: c.g, b: c.b, name: name, weight: weight, deltaE: deltaE)
    }

    /// Color de Wada tal cual (nombre de Ridgway del diccionario).
    init(id: Int, wada: WadaColor) {
        let rgb = wada.rgb.count == 3 && wada.rgb.allSatisfy({ (0...255).contains($0) })
            ? (UInt8(wada.rgb[0]), UInt8(wada.rgb[1]), UInt8(wada.rgb[2]))
            : (parseHexRGB(wada.hex).map { ($0.r, $0.g, $0.b) } ?? (0, 0, 0))
        self.init(id: id, r: rgb.0, g: rgb.1, b: rgb.2, name: wada.name)
    }

    /// Swatch del motor con su peso; `dictionary` nombra el color de Wada más cercano (motor).
    init(id: Int, swatch: Swatch, dictionary: WadaDictionary?) {
        self.init(id: id, r: swatch.r, g: swatch.g, b: swatch.b, weight: swatch.weight)
        if let dictionary {
            let nearest = nearestDictionaryColor(swatch.lab)
            name = dictionary.color(index: nearest.index)?.name
            deltaE = nearest.deltaE
        }
    }

    /// Nombra el color con el color de Wada más cercano según el motor (ΔE00).
    func namedByNearestWada(in dictionary: WadaDictionary) -> PaletteColor {
        var copy = self
        let nearest = nearestDictionaryColor(srgbToLab(r: r, g: g, b: b))
        copy.name = dictionary.color(index: nearest.index)?.name
        copy.deltaE = nearest.deltaE
        return copy
    }

    var color: Color { Color(rgb8: r, g, b) }

    /// "#RRGGBB" en mayúsculas (así se muestra y se copia).
    var hex: String { String(format: "#%02X%02X%02X", Int(r), Int(g), Int(b)) }

    /// Colores de una combinación en el orden del diccionario.
    static func combo(_ id: Int, in dictionary: WadaDictionary) -> [PaletteColor] {
        dictionary.colors(ofComboId: id).enumerated().map { PaletteColor(id: $0.offset, wada: $0.element) }
    }
}

/// Formatos de la interfaz en español (coma decimal, espacio antes de %).
enum DesignFormat {
    private static let spanish = Locale(identifier: "es_ES")

    /// 0,392 → "39 %".
    static func percent(_ weight: Double) -> String {
        "\(Int((weight * 100).rounded()))\u{00A0}%"
    }

    /// 2,34 → "ΔE 2,3".
    static func deltaE(_ value: Double) -> String {
        "ΔE\u{00A0}" + value.formatted(.number.precision(.fractionLength(1)).locale(spanish))
    }

    /// Score del match con coma decimal: 19,56.
    static func score(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(spanish))
    }

    /// Hex separados por espacios (lo que copia «Copiar hex»).
    static func hexList(_ colors: [PaletteColor]) -> String {
        colors.map(\.hex).joined(separator: " ")
    }

    /// "Nº 067 · 2 colores".
    static func comboSubtitle(id: Int, size: Int) -> String {
        "\(WadaDictionary.numberLabel(id)) · \(size) \(size == 1 ? "color" : "colores")"
    }

    /// Etiqueta de VoiceOver de un swatch: "Color 1 de 5, Black, #222524, 39 por ciento".
    static func accessibilityLabel(_ c: PaletteColor, position: Int, total: Int) -> String {
        var parts = ["Color \(position + 1) de \(total)"]
        if let name = c.name { parts.append(name) }
        parts.append(c.hex)
        if let w = c.weight { parts.append("\(Int((w * 100).rounded())) por ciento") }
        return parts.joined(separator: ", ")
    }
}
