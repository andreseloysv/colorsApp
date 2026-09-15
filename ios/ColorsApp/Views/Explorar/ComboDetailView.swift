// Detalle de una combinación (Explorar, Resultado y la hoja de la Rejilla):
// swatches grandes, nombre curado o "Nº 012", tamaño y colección, estado en la
// rejilla (fecha y origen del desbloqueo) y por cada color su nombre inglés
// (Ridgway, tal cual), hex, RGB y el Lab D65 que calcula el motor (dictionaryColorLab).
import SwiftUI
import ColorEngine

struct ComboDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let comboId: Int
    @State private var unlocked: Bool?
    @State private var unlock: UnlockRecord?

    var body: some View {
        Group {
            if let combo = env.dictionary.combo(id: comboId) {
                content(combo)
            } else {
                ContentUnavailableView("No existe la combinación \(comboId)", systemImage: "questionmark.square.dashed",
                                       description: Text("El diccionario tiene \(env.comboCount) combinaciones (1 – \(env.comboCount))."))
            }
        }
        .navigationTitle(env.dictionary.displayName(id: comboId))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            unlock = try? await env.unlocks.record(comboId: comboId)
            unlocked = unlock != nil
        }
    }

    private func content(_ combo: WadaCombo) -> some View {
        let colors = env.dictionary.colors(of: combo)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SwatchStrip(colors: colors.map { Color(wada: $0) }, height: 180, cornerRadius: 16)
                    .accessibilityIdentifier("combo.swatches")
                VStack(alignment: .leading, spacing: 4) {
                    Text(env.dictionary.displayName(id: combo.id))
                        .font(.title.bold())
                    Text(headline(combo))
                        .foregroundStyle(.secondary)
                    if let unlock {
                        Label("En tu rejilla desde el \(unlock.firstSeenAt.formatted(date: .abbreviated, time: .shortened)) · \(unlock.source.label)",
                              systemImage: "checkmark.seal.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .padding(.top, 4)
                    } else if unlocked == false {
                        Label("Todavía no está en tu rejilla: fotografía estos colores o escanea tu carrete.", systemImage: "lock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Colores")
                        .font(.headline)
                    ForEach(colors) { color in
                        WadaColorCard(color: color, comboCount: env.dictionary.combos(containingColor: color.index).count)
                    }
                }
                Text("Lab D65 calculado por el motor (ce_dict_color_lab) a partir del sRGB del diccionario \(env.dictVersion).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func headline(_ combo: WadaCombo) -> String {
        if env.dictionary.curatedName(id: combo.id) != nil {
            return "\(WadaDictionary.numberLabel(combo.id)) · \(comboSubtitle(combo))"
        }
        return comboSubtitle(combo)
    }
}

/// Ficha de un color del diccionario.
struct WadaColorCard: View {
    let color: WadaColor
    var comboCount: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(wada: color))
                .frame(width: 64, height: 64)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            VStack(alignment: .leading, spacing: 3) {
                Text(color.name)
                    .font(.headline)
                Text("\(color.hex)  ·  RGB \(color.rgb.map(String.init).joined(separator: " "))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let lab = dictionaryColorLab(index: color.index) {
                    Text(String(format: "Lab %.2f  %.2f  %.2f", lab.L, lab.a, lab.b))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(comboCount > 0 ? "Índice \(color.index) · en \(comboCount) combinaciones" : "Índice \(color.index)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
