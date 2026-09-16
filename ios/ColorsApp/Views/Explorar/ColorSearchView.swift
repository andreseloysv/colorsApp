// «Buscar por color» (PLAN §7.7; hoja desde el botón de ajustes del buscador de la Rejilla):
// ColorPicker de SwiftUI o un hex → `srgbToLab` + `nearestDictionaryColor` del MOTOR →
// color de Wada más cercano (ΔE00) y «Ver N combinaciones en la rejilla», que escribe ese
// hex en el buscador. Los colores se muestran en pocillo neutro (§1.4).
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
    /// Escribe el hex elegido en el buscador de la Rejilla (nil oculta el botón).
    var onShowInGrid: ((String) -> Void)?
    var onClose: (() -> Void)?

    @State private var color = Color(rgb8: 197, 165, 110)
    @State private var hexText = "#C5A56E"
    @State private var hexError: String?
    @State private var match: ColorSearch.Match?
    @FocusState private var hexFocused: Bool
    @Environment(\.colorScheme) private var scheme

    private static let spanish = Locale(identifier: "es_ES")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                pickerCard
                if let match, let wada = env.dictionary.color(index: match.index) {
                    result(match, wada: wada)
                }
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        // La acción queda fija abajo: visible también con la hoja a media altura.
        .safeAreaInset(edge: .bottom, spacing: 0) { showInGridBar }
        .background(Theme.containerLow.ignoresSafeArea())
        .navigationTitle("Buscar por color")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: color) { _, newColor in
            guard let rgb = ColorSearch.srgb8(from: newColor) else { return }
            let m = ColorSearch.nearest(r: rgb.r, g: rgb.g, b: rgb.b)
            hexText = m.hex.uppercased()
            hexError = nil
            match = m
        }
        .onAppear {
            if match == nil { match = ColorSearch.nearest(hex: hexText) }
        }
        .accessibilityIdentifier("rejilla.colorSearch")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "eyedropper.halffull")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .accessibilityHidden(true)
                Text("Buscar por color")
                    .textRole(.headlineMD)
                    .foregroundStyle(Theme.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.sm)
                if let onClose {
                    SolarIconButton(systemImage: "xmark", accessibilityLabel: "Cerrar", size: 32, iconSize: 14,
                                    foreground: Theme.onSurfaceVariant, background: Theme.containerHigh, action: onClose)
                }
            }
            Text("Elige un color o escribe su hex: el motor busca el color de Sanzo Wada más cercano (ΔE00) y las combinaciones que lo usan.")
                .textRole(.bodySM)
                .foregroundStyle(Theme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pickerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ColorPicker(selection: $color, supportsOpacity: false) {
                Text("Elegir color").textRole(.labelLG).foregroundStyle(Theme.onSurface)
            }
            .accessibilityIdentifier("colorSearch.picker")
            HStack(spacing: Spacing.sm) {
                TextField("", text: $hexText, prompt: Text("#RRGGBB").foregroundStyle(Theme.onSurfaceVariant))
                    .textRole(.hex)
                    .foregroundStyle(Theme.onSurface)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .focused($hexFocused)
                    .submitLabel(.search)
                    .onSubmit(applyHex)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: Sizes.minTouch)
                    .background(Capsule().fill(Theme.containerHigh))
                    .accessibilityLabel("Hex")
                    .accessibilityIdentifier("colorSearch.hex")
                SolarPrimaryButton(title: "Buscar", systemImage: "magnifyingglass", size: .compact, fullWidth: false,
                                   elevated: false, action: applyHex)
            }
            if let hexError {
                Label(hexError, systemImage: "exclamationmark.triangle")
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.error)
            }
        }
        .padding(Spacing.md)
        .solarCard(fill: scheme == .dark ? Theme.containerHigh : Theme.card)
    }

    private func result(_ match: ColorSearch.Match, wada: WadaColor) -> some View {
        let combos = env.dictionary.combos(containingColor: match.index)
        let picked = PaletteColor(id: -1, r: match.r, g: match.g, b: match.b)
        let nearest = PaletteColor(id: wada.index, wada: wada)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Color de Wada más cercano").textRole(.overline).foregroundStyle(Theme.onSurfaceVariant)
            SwatchWell(padding: Spacing.md, cornerRadius: Radius.card) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        swatch(picked, title: "Tu color", subtitle: picked.hex)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.wellTextSecondary)
                            .padding(.top, 26)
                            .accessibilityHidden(true)
                        swatch(nearest, title: wada.name, subtitle: nearest.hex)
                    }
                    HStack(spacing: Spacing.sm) {
                        Text(DesignFormat.deltaE(match.deltaE))
                            .textRole(.labelSM)
                            .foregroundStyle(Theme.wellText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: Radius.tag, style: .continuous).fill(Theme.wellFillAlt))
                        Text("Lab \(n(match.lab.L)) · \(n(match.lab.a)) · \(n(match.lab.b))")
                            .textRole(.hex)
                            .foregroundStyle(Theme.wellTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("colorSearch.result")
            if onShowInGrid == nil {
                Text(combos.count == 1 ? "En 1 combinación" : "En \(combos.count) combinaciones")
                    .textRole(.bodyMD)
                    .foregroundStyle(Theme.onSurfaceVariant)
            }
        }
    }

    @ViewBuilder private var showInGridBar: some View {
        if let onShowInGrid, let match {
            let count = env.dictionary.combos(containingColor: match.index).count
            SolarPrimaryButton(title: count == 1 ? "Ver 1 combinación en la rejilla" : "Ver \(count) combinaciones en la rejilla",
                               systemImage: "square.grid.2x2", elevated: false) {
                onShowInGrid(match.hex.uppercased())
            }
            .accessibilityIdentifier("colorSearch.showInGrid")
            .padding(.horizontal, Spacing.margin)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.md)
            .background(Theme.containerLow)
        }
    }

    private func swatch(_ c: PaletteColor, title: String, subtitle: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            shape.fill(c.color)
                .overlay(SwatchHairline(shape: shape))
                .frame(height: 64)
            Text(title)
                .textRole(.labelMD)
                .foregroundStyle(Theme.wellText)
                .lineLimit(2)
            Text(subtitle)
                .textRole(.hex)
                .foregroundStyle(Theme.wellTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(subtitle)")
    }

    private func n(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(2)).locale(Self.spanish))
    }

    private func applyHex() {
        guard let m = ColorSearch.nearest(hex: hexText) else {
            hexError = "Hex no válido: usa #RRGGBB."
            return
        }
        hexFocused = false
        hexError = nil
        hexText = m.hex.uppercased()
        match = m
        color = Color(rgb8: m.r, m.g, m.b)
    }
}
