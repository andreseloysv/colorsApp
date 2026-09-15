// Componentes compartidos por Explorar, Resultado y Hoy: tira de swatches,
// barras de paleta con peso, fila de combinación y color de texto legible
// (usa la L de CIELAB del motor: nada de lógica de color propia en Swift).
import SwiftUI
import ColorEngine

/// Negro o blanco según la luminosidad L* (CIELAB, motor) del fondo.
func legibleTextColor(r: UInt8, g: UInt8, b: UInt8) -> Color {
    srgbToLab(r: r, g: g, b: b).L > 60 ? .black : .white
}

/// Descripción corta de una combinación: "2 colores · Japón".
func comboSubtitle(_ combo: WadaCombo) -> String {
    var s = "\(combo.size) colores"
    if let collection = combo.collection, !collection.isEmpty {
        s += " · \(collection)"
    }
    return s
}

/// Tira horizontal de colores a partes iguales.
struct SwatchStrip: View {
    let colors: [Color]
    var height: CGFloat = 28
    var cornerRadius: CGFloat = 6

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Rectangle().fill(color)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.quaternary))
    }
}

/// Barras proporcionales al peso de cada swatch de una paleta del motor.
struct PaletteBars: View {
    struct Entry: Identifiable, Hashable {
        let id: Int
        let hex: String
        let weight: Double
        let r: UInt8
        let g: UInt8
        let b: UInt8

        var color: Color { Color(rgb8: r, g, b) }
    }

    let entries: [Entry]

    static func entries(from swatches: [Swatch]) -> [Entry] {
        swatches.enumerated().map { i, s in
            Entry(id: i, hex: s.hex, weight: s.weight, r: s.r, g: s.g, b: s.b)
        }
    }

    static func entries(from palette: [PaletteEntry]) -> [Entry] {
        palette.enumerated().compactMap { i, p in
            guard let c = parseHexRGB(p.hex) else { return nil }
            return Entry(id: i, hex: p.hex, weight: p.weight, r: c.r, g: c.g, b: c.b)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(entries) { e in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(e.color)
                        .frame(width: 30, height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(e.color)
                                .frame(width: max(6, geo.size.width * min(1, max(0, e.weight))))
                        }
                    }
                    .frame(height: 14)
                    Text(String(format: "%.0f %%", e.weight * 100))
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                    Text(e.hex)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                }
            }
        }
    }
}

/// Fila de combinación para listas: swatches, nombre curado o "Nº 012", tamaño.
struct ComboRow: View {
    @EnvironmentObject private var env: AppEnvironment
    let combo: WadaCombo
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            SwatchStrip(colors: env.dictionary.colors(of: combo).map { Color(wada: $0) }, height: 34)
                .frame(width: 104)
            VStack(alignment: .leading, spacing: 2) {
                Text(env.dictionary.displayName(id: combo.id))
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        if env.dictionary.curatedName(id: combo.id) != nil {
            return "\(WadaDictionary.numberLabel(combo.id)) · \(comboSubtitle(combo))"
        }
        return comboSubtitle(combo)
    }
}
