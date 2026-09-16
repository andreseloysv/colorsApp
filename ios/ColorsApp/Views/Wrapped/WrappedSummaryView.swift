// Resumen «Tu carrete en color» tras el escaneo del día 0 (PLAN §7.6) con el estilo del
// sistema de diseño (docs/design/DESIGN_SYSTEM.md): portada con la cifra de fotos, color
// firma, 5 colores más frecuentes, combinaciones desbloqueadas, las que más se repiten,
// contador n/348 y «Ver rejilla». Todo color de datos va en un pocillo neutro (§1.4).
// Vista pura sobre `ScanSummary` + `WadaDictionary` (sin base de datos).
import SwiftUI

struct WrappedSummaryView: View {
    let summary: ScanSummary
    let dictionary: WadaDictionary
    var totalCombos: Int = WadaDictionary.expectedComboCount
    var onShowGrid: (() -> Void)? = nil

    private let maxUnlockTiles = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                if summary.scanned == 0 {
                    emptyState
                } else {
                    signature
                    topColors
                    unlockedCombos
                    frequentCombos
                }
                counter
                if let onShowGrid {
                    SolarPrimaryButton(title: "Ver rejilla", systemImage: "square.grid.2x2", luminous: true, action: onShowGrid)
                        .accessibilityIdentifier("wrapped.showGrid")
                }
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .background(Theme.surface.ignoresSafeArea())
        .accessibilityIdentifier("wrapped.summary")
    }

    // MARK: Secciones

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                // Emblema de la marca en vez del SF Symbol `sun.max.fill` (FIDELITY.md §2.1).
                ChromaSolLogo(size: 28, animated: true)
                Text("Escaneo del carrete").textRole(.overline).foregroundStyle(Theme.secondary)
            }
            Text("Tu carrete en color")
                .textRole(.headlineXLMobile)
                .foregroundStyle(Theme.primary)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("\(summary.scanned)")
                    .textRole(.headlineXL)
                    .monospacedDigit()
                    .foregroundStyle(Theme.onSurface)
                Text(summary.scanned == 1 ? "foto analizada" : "fotos analizadas")
                    .textRole(.labelLG)
                    .foregroundStyle(Theme.onSurfaceVariant)
            }
            Text(statsLine)
                .textRole(.bodySM)
                .foregroundStyle(Theme.onSurfaceVariant)
                .accessibilityIdentifier("wrapped.stats")
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card)
                SolarWash(kind: .warm, diameter: 170, blur: 44).offset(x: 60, y: -70)
                SolarWash(kind: .green, diameter: 140, blur: 36).offset(x: -210, y: 90)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .elevation(.restStrong)
        }
        .glowCard(cornerRadius: Radius.card)
        .sunGlint(cornerRadius: Radius.card)
    }

    var statsLine: String {
        var parts = ["\(summary.scanned) fotos analizadas"]
        if summary.skipped > 0 { parts.append("\(summary.skipped) omitidas") }
        if summary.failed > 0 { parts.append("\(summary.failed) fallidas") }
        parts.append(Self.durationText(summary.duration))
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label {
                Text("No había fotos que analizar").textRole(.headlineSM)
            } icon: {
                Image(systemName: "photo")
            }
            .foregroundStyle(Theme.primary)
            Text("Haz fotos de lo que llevas puesto o elige algunas del carrete y vuelve a intentarlo.")
                .textRole(.bodyMD)
                .foregroundStyle(Theme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solarCard(fill: Theme.container, elevation: .flat)
    }

    @ViewBuilder
    private var signature: some View {
        if let index = summary.signatureColorIndex, let color = dictionary.color(index: index) {
            let count = summary.topColors.first { $0.colorIndex == index }?.count ?? 0
            let swatch = PaletteColor(id: 0, wada: color)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "Tu color firma", systemImage: "seal")
                SwatchWell(padding: Spacing.md, cornerRadius: Radius.card) {
                    HStack(spacing: Spacing.margin) {
                        RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
                            .fill(swatch.color)
                            .overlay(SwatchHairline(shape: RoundedRectangle(cornerRadius: Radius.block, style: .continuous)))
                            .frame(width: 96, height: 96)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(color.name)
                                .textRole(.headlineMD)
                                .foregroundStyle(Theme.wellText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(swatch.hex)
                                .textRole(.hex)
                                .foregroundStyle(Theme.wellTextSecondary)
                            Text(count == 1 ? "en 1 foto" : "en \(count) fotos")
                                .textRole(.labelMD)
                                .foregroundStyle(Theme.wellTextSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .accessibilityIdentifier("wrapped.signature")
        }
    }

    @ViewBuilder
    private var topColors: some View {
        let top = Array(summary.topColors.prefix(5)).compactMap { entry -> (ColorCount, WadaColor)? in
            dictionary.color(index: entry.colorIndex).map { (entry, $0) }
        }
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "Tus 5 colores", systemImage: "paintpalette")
                SwatchWell(padding: Spacing.sm, cornerRadius: Radius.card) {
                    HStack(alignment: .top, spacing: Spacing.xs) {
                        ForEach(top, id: \.0.colorIndex) { entry, color in
                            let swatch = PaletteColor(id: entry.colorIndex, wada: color)
                            VStack(spacing: Spacing.xs) {
                                Circle()
                                    .fill(swatch.color)
                                    .overlay(SwatchHairline(shape: Circle()))
                                    .frame(width: 48, height: 48)
                                    .padding(.top, 2)
                                Text(color.name)
                                    .textRole(.labelSM)
                                    .foregroundStyle(Theme.wellText)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                Text("×\(entry.count)")
                                    .textRole(.labelSM)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.wellTextSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .accessibilityIdentifier("wrapped.topColors")
        }
    }

    @ViewBuilder
    private var unlockedCombos: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: summary.newUnlocks.count == 1 ? "1 combinación desbloqueada" : "\(summary.newUnlocks.count) combinaciones desbloqueadas",
                          systemImage: "checkmark.seal")
            if summary.newUnlocks.isEmpty {
                Text("Ninguna foto se parecía lo bastante a una combinación de Wada (resultados ambiguos o lejanos no desbloquean).")
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SwatchWell(padding: Spacing.sm, cornerRadius: Radius.card) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 96), spacing: Spacing.sm)], spacing: Spacing.sm) {
                        ForEach(summary.newUnlocks.prefix(maxUnlockTiles), id: \.self) { id in
                            VStack(spacing: Spacing.xs) {
                                PaletteRibbon(colors: PaletteColor.combo(id, in: dictionary), style: .stripes, height: 56,
                                              inWell: false)
                                Text(WadaDictionary.numberLabel(id))
                                    .textRole(.labelSM)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.wellTextSecondary)
                                    .lineLimit(1)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Combinación \(WadaDictionary.numberLabel(id)), \(GardenText.comboTitle(id, dictionary: dictionary))")
                        }
                    }
                }
                if summary.newUnlocks.count > maxUnlockTiles {
                    Text("y \(summary.newUnlocks.count - maxUnlockTiles) más en la rejilla")
                        .textRole(.bodySM)
                        .foregroundStyle(Theme.onSurfaceVariant)
                }
            }
        }
        .accessibilityIdentifier("wrapped.unlocks")
    }

    @ViewBuilder
    private var frequentCombos: some View {
        let top = Array(summary.topCombos.prefix(5)).filter { dictionary.combo(id: $0.comboId) != nil }
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "Las que más se repiten", systemImage: "repeat")
                VStack(spacing: 0) {
                    ForEach(Array(top.enumerated()), id: \.element.comboId) { i, entry in
                        if i > 0 {
                            Rectangle().fill(Theme.outlineVariant.opacity(0.6)).frame(height: 1)
                        }
                        HStack(spacing: Spacing.md) {
                            PaletteRibbon(colors: PaletteColor.combo(entry.comboId, in: dictionary), style: .strip,
                                          height: 28, wellPadding: 6, wellCornerRadius: Radius.block)
                                .frame(width: 104)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(GardenText.comboTitle(entry.comboId, dictionary: dictionary))
                                    .textRole(.labelLG)
                                    .foregroundStyle(Theme.onSurface)
                                    .lineLimit(2)
                                Text(WadaDictionary.numberLabel(entry.comboId))
                                    .textRole(.bodySM)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.onSurfaceVariant)
                            }
                            Spacer(minLength: Spacing.xs)
                            Text(entry.count == 1 ? "1 foto" : "\(entry.count) fotos")
                                .textRole(.labelMD)
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondary)
                        }
                        .padding(.vertical, Spacing.sm)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .solarCard(elevation: .rest)
            }
            .accessibilityIdentifier("wrapped.topCombos")
        }
    }

    private var counter: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(Self.counterText(unlocked: summary.totalUnlocked, total: totalCombos))
                    .textRole(.headlineXL)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primary)
                    .accessibilityIdentifier("wrapped.counter")
                Text("combinaciones de Sanzo Wada en tu rejilla")
                    .textRole(.labelMD)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GardenProgressBar(fraction: Double(summary.totalUnlocked) / Double(max(1, totalCombos)), height: 8)
                .accessibilityHidden(true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solarCard(fill: Theme.container, elevation: .small)
    }

    /// "41/348".
    static func counterText(unlocked: Int, total: Int) -> String { "\(unlocked)/\(total)" }

    /// "3,2 s" / "1 min 12 s".
    static func durationText(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1f s", seconds).replacingOccurrences(of: ".", with: ",")
        }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m) min \(s) s"
    }
}
