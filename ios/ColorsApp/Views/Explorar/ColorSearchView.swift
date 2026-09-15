// "Buscar por color" (PLAN §7.7): ColorPicker de SwiftUI (o un hex) ->
// srgbToLab + nearestDictionaryColor del motor -> color de Wada más cercano
// (ΔE00) y las combinaciones que lo contienen.
import SwiftUI
import UIKit
import ColorEngine

enum ColorSearch {
    struct Match: Equatable, Sendable {
        let index: Int
        let deltaE: Double
        let lab: Lab
        let r: UInt8
        let g: UInt8
        let b: UInt8

        var hex: String { String(format: "#%02x%02x%02x", Int(r), Int(g), Int(b)) }
    }

    static func nearest(r: UInt8, g: UInt8, b: UInt8) -> Match {
        let lab = srgbToLab(r: r, g: g, b: b)
        let n = nearestDictionaryColor(lab)
        return Match(index: n.index, deltaE: n.deltaE, lab: lab, r: r, g: g, b: b)
    }

    static func nearest(hex: String) -> Match? {
        guard let c = parseHexRGB(hex) else { return nil }
        return nearest(r: c.r, g: c.g, b: c.b)
    }

    /// sRGB8 de un Color de SwiftUI (convertido a sRGB por CoreGraphics y redondeado).
    @MainActor
    static func srgb8(from color: Color) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = UIColor(color).cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3 else { return nil }
        func q(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return (q(components[0]), q(components[1]), q(components[2]))
    }
}

struct ColorSearchView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var color = Color(rgb8: 197, 165, 110)
    @State private var hexText = "#c5a56e"
    @State private var hexError: String?
    @State private var match: ColorSearch.Match?

    var body: some View {
        List {
            Section("Color") {
                ColorPicker("Elegir color", selection: $color, supportsOpacity: false)
                HStack {
                    TextField("#rrggbb", text: $hexText)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit(applyHex)
                    Button("Buscar", action: applyHex)
                        .buttonStyle(.bordered)
                }
                if let hexError {
                    Text(hexError).font(.footnote).foregroundStyle(.red)
                }
            }
            if let match, let wada = env.dictionary.color(index: match.index) {
                Section("Color de Wada más cercano") {
                    HStack(spacing: 12) {
                        swatch(Color(rgb8: match.r, match.g, match.b), caption: "Elegido\n\(match.hex)")
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        swatch(Color(wada: wada), caption: "\(wada.name)\n\(wada.hex)")
                    }
                    LabeledContent("ΔE00", value: String(format: "%.2f", match.deltaE))
                    LabeledContent("Lab del color elegido", value: String(format: "%.2f  %.2f  %.2f", match.lab.L, match.lab.a, match.lab.b))
                    if let lab = dictionaryColorLab(index: wada.index) {
                        LabeledContent("Lab de \(wada.name)", value: String(format: "%.2f  %.2f  %.2f", lab.L, lab.a, lab.b))
                    }
                }
                let combos = env.dictionary.combos(containingColor: match.index)
                Section("\(combos.count) combinaciones con \(wada.name)") {
                    ForEach(combos) { combo in
                        NavigationLink(value: combo.id) {
                            ComboRow(combo: combo)
                        }
                    }
                }
            }
        }
        .navigationTitle("Buscar por color")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: color) { _, newColor in
            guard let rgb = ColorSearch.srgb8(from: newColor) else { return }
            let m = ColorSearch.nearest(r: rgb.r, g: rgb.g, b: rgb.b)
            hexText = m.hex
            hexError = nil
            match = m
        }
        .onAppear {
            if match == nil { match = ColorSearch.nearest(hex: hexText) }
        }
    }

    private func swatch(_ color: Color, caption: String) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(color)
                .frame(width: 84, height: 64)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            Text(caption)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func applyHex() {
        guard let m = ColorSearch.nearest(hex: hexText) else {
            hexError = "Hex no válido: usa #rrggbb."
            return
        }
        hexError = nil
        match = m
        color = Color(rgb8: m.r, m.g, m.b)
    }
}
