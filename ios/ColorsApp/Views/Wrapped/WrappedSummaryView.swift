// Resumen tipo "tu carrete en color" tras el escaneo del día 0 (PLAN §7.6):
// color firma, top 5 colores del diccionario, combinaciones desbloqueadas,
// combinaciones más frecuentes, contador n/348 y botón "Ver rejilla".
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
            VStack(alignment: .leading, spacing: 24) {
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
                    Button(action: onShowGrid) {
                        Text("Ver rejilla")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("wrapped.showGrid")
                }
            }
            .padding()
        }
        .accessibilityIdentifier("wrapped.summary")
    }

    // MARK: Secciones

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tu carrete en color")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text(statsLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("wrapped.stats")
        }
    }

    var statsLine: String {
        var parts = ["\(summary.scanned) fotos analizadas"]
        if summary.skipped > 0 { parts.append("\(summary.skipped) omitidas") }
        if summary.failed > 0 { parts.append("\(summary.failed) fallidas") }
        parts.append(Self.durationText(summary.duration))
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No había fotos que analizar", systemImage: "photo")
                .font(.headline)
            Text("Haz fotos de lo que llevas puesto o elige algunas del carrete y vuelve a intentarlo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var signature: some View {
        if let index = summary.signatureColorIndex, let color = dictionary.color(index: index) {
            let count = summary.topColors.first { $0.colorIndex == index }?.count ?? 0
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Tu color firma")
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(wada: color))
                        .frame(width: 110, height: 110)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(color.name)
                            .font(.title2.bold())
                        Text(color.hex.uppercased())
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(count == 1 ? "en 1 foto" : "en \(count) fotos")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .accessibilityIdentifier("wrapped.signature")
        }
    }

    @ViewBuilder
    private var topColors: some View {
        let top = Array(summary.topColors.prefix(5))
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Tus 5 colores")
                HStack(alignment: .top, spacing: 10) {
                    ForEach(top, id: \.colorIndex) { entry in
                        if let color = dictionary.color(index: entry.colorIndex) {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(Color(wada: color))
                                    .frame(width: 52, height: 52)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.1)))
                                Text(color.name)
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                Text("×\(entry.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .accessibilityIdentifier("wrapped.topColors")
        }
    }

    @ViewBuilder
    private var unlockedCombos: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(summary.newUnlocks.count == 1 ? "1 combinación desbloqueada" : "\(summary.newUnlocks.count) combinaciones desbloqueadas")
            if summary.newUnlocks.isEmpty {
                Text("Ninguna foto se parecía lo bastante a una combinación de Wada (resultados ambiguos o lejanos no desbloquean).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 96), spacing: 8)], spacing: 8) {
                    ForEach(summary.newUnlocks.prefix(maxUnlockTiles), id: \.self) { id in
                        if let combo = dictionary.combo(id: id) {
                            VStack(spacing: 4) {
                                ComboTile(combo: combo, colors: dictionary.colors(of: combo), unlocked: true)
                                Text(dictionary.displayName(id: id))
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                if summary.newUnlocks.count > maxUnlockTiles {
                    Text("y \(summary.newUnlocks.count - maxUnlockTiles) más en la rejilla")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("wrapped.unlocks")
    }

    @ViewBuilder
    private var frequentCombos: some View {
        let top = Array(summary.topCombos.prefix(5))
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Las que más se repiten")
                ForEach(top, id: \.comboId) { entry in
                    if let combo = dictionary.combo(id: entry.comboId) {
                        HStack(spacing: 12) {
                            HStack(spacing: 0) {
                                ForEach(dictionary.colors(of: combo)) { color in
                                    Color(wada: color)
                                }
                            }
                            .frame(width: 72, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text(dictionary.displayName(id: combo.id))
                            Spacer()
                            Text(entry.count == 1 ? "1 foto" : "\(entry.count) fotos")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .accessibilityIdentifier("wrapped.topCombos")
        }
    }

    private var counter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(RejillaModel.counterText(unlocked: summary.totalUnlocked, total: totalCombos))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("wrapped.counter")
                Text("combinaciones de Sanzo Wada")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(summary.totalUnlocked), total: Double(max(1, totalCombos)))
                .tint(.primary)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
    }

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
