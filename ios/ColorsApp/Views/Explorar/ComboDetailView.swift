// Detalle de una combinación (hoja de la Rejilla; también empujado desde otras pantallas),
// docs/design/DESIGN_SYSTEM.md §4 n.º 33: tira de 180 pt en pocillo neutro, nombre curado o
// propuesto (con la etiqueta «Nombre propuesto»), número y tamaño, estado en tu rejilla
// (fecha y origen del desbloqueo), dónde la ha visto el motor en tus análisis, «Copiar hex» y
// «Guardar» en el Jardín, y por cada color su ficha en pocillo: nombre de Ridgway tal cual,
// hex, RGB y el Lab D65 que calcula el MOTOR (`dictionaryColorLab`).
import SwiftUI
import UIKit
import ColorEngine

struct ComboDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let comboId: Int
    var naming: ComboNaming = .bundled
    /// Jardín donde guardar la combinación (nil oculta «Guardar»).
    var garden: GardenStore?
    /// «En N combinaciones» de un color: busca ese color en la Rejilla (nil lo oculta).
    var onSearchColor: ((WadaColor) -> Void)?
    /// Botón de cerrar (hojas); nil lo oculta.
    var onClose: (() -> Void)?

    @State private var unlock: UnlockRecord?
    @State private var loaded = false
    @State private var seen: [ScanRecord] = []
    @State private var copied = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let combo = env.dictionary.combo(id: comboId) {
                content(combo)
            } else {
                missing
            }
        }
        .background(Theme.containerLow.ignoresSafeArea())
        .navigationTitle(naming.name(for: comboId, in: env.dictionary).text)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(comboId)|\(ObjectIdentifier(env).hashValue)") {
            unlock = try? await env.unlocks.record(comboId: comboId)
            seen = (try? await env.scans.scans(withTop1: comboId, limit: 50)) ?? []
            loaded = true
        }
        .accessibilityIdentifier("combo.detail")
    }

    private var missing: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "questionmark.square.dashed").font(.system(size: 32)).foregroundStyle(Theme.secondary)
            Text("No existe la combinación \(comboId)").textRole(.headlineSM).foregroundStyle(Theme.primary)
            Text("El diccionario tiene \(env.comboCount) combinaciones (1 – \(env.comboCount)).")
                .textRole(.bodyMD).foregroundStyle(Theme.onSurfaceVariant)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ combo: WadaCombo) -> some View {
        let wadaColors = env.dictionary.colors(of: combo)
        let colors = wadaColors.enumerated().map { PaletteColor(id: $0.offset, wada: $0.element) }
        let name = naming.name(for: combo.id, in: env.dictionary)
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                topRow(combo)
                PaletteRibbon(colors: colors, style: .strip, height: 180 - 2 * Spacing.wellPadding,
                              wellCornerRadius: Radius.card)
                    .accessibilityIdentifier("combo.swatches")
                titleBlock(combo, name: name)
                statusCard
                actions(colors)
                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader(title: "Colores", systemImage: "paintpalette", trailing: "\(wadaColors.count)")
                    ForEach(wadaColors) { color in
                        let count = env.dictionary.combos(containingColor: color.index).count
                        WadaColorCard(color: color, comboCount: count,
                                      onSearch: onSearchColor.map { search in { search(color) } })
                    }
                }
                Text("Lab D65 calculado por el motor (ce_dict_color_lab) a partir del sRGB del diccionario \(env.dictVersion).")
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.top, onClose == nil ? Spacing.md : Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .overlay(alignment: .bottom) {
            if copied {
                SolarToast(title: "Hex copiados", luminous: true)
                    .padding(.bottom, Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }

    private func topRow(_ combo: WadaCombo) -> some View {
        HStack(spacing: Spacing.sm) {
            // Mismo rótulo luminoso de la Rejilla (FIDELITY.md §5 R10): estrella de ocho puntas que
            // gira en 8 s con resplandor ámbar `drop-shadow-[0_0_4px_rgba(217,119,36,0.6)]`.
            SolarCompassStar()
                .fill(Theme.secondary)
                .frame(width: 15, height: 15)
                .shadow(color: Color(brand: RejillaLight.ember, opacity: 0.6), radius: 2)
                .spinning(duration: MotionSpec.Spin.lensChip)
                .accessibilityHidden(true)
            Text("Combinación de Sanzo Wada")
                .textRole(.overline)
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            Spacer(minLength: Spacing.sm)
            SolarBadge(title: WadaDictionary.numberLabel(combo.id))
            if let onClose {
                SolarIconButton(systemImage: "xmark", accessibilityLabel: "Cerrar", size: 32, iconSize: 14,
                                foreground: Theme.onSurfaceVariant, background: Theme.containerHigh, action: onClose)
                    .accessibilityIdentifier("combo.close")
            }
        }
    }

    private func titleBlock(_ combo: WadaCombo, name: ComboName) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(name.text)
                .textRole(.headlineLG)
                .foregroundStyle(Theme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Spacing.sm) {
                switch name.kind {
                case .proposed:
                    SolarBadge(title: "Nombre propuesto", systemImage: "lightbulb.fill",
                               fill: Tone.amber.badgeFill, foreground: Tone.amber.onBadge)
                        .accessibilityIdentifier("combo.proposedName")
                case .curated:
                    SolarBadge(title: "Tu nombre", systemImage: "checkmark", fill: Tone.moss.badgeFill, foreground: Tone.moss.onBadge)
                case .number:
                    EmptyView()
                }
                Text(DesignFormat.comboSubtitle(id: combo.id, size: combo.size))
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .lineLimit(1)
            }
            if name.isProposed {
                Text("Propuesta de la app mientras no elijas un nombre para esta combinación.")
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Estado en tu rejilla + análisis en los que el motor la eligió como top-1.
    private var statusCard: some View {
        let unlocked = unlock != nil
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Circle()
                    .fill(unlocked ? Tone.moss.badgeFill : Theme.containerHighest)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: unlocked ? "checkmark.seal.fill" : "lock")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(unlocked ? Tone.moss.onBadge : Theme.onSurfaceVariant)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unlocked ? "En tu rejilla" : (loaded ? "Todavía no está en tu rejilla" : "Comprobando…"))
                        .textRole(.labelLG)
                        .foregroundStyle(unlocked ? Theme.primary : Theme.onSurface)
                    Text(statusDetail)
                        .textRole(.bodySM)
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let last = seen.first {
                Label {
                    Text(seen.count == 1
                         ? "Vista en 1 análisis · \(RejillaDateText.short(last.scannedAt)) (\(last.source.label))"
                         : "Vista en \(seen.count) análisis · el último \(RejillaDateText.short(last.scannedAt)) (\(last.source.label))")
                        .textRole(.bodySM)
                } icon: {
                    Image(systemName: "sparkle.magnifyingglass").font(.system(size: 13, weight: .medium))
                }
                .labelStyle(TightLabelStyle())
                .foregroundStyle(Theme.onSurfaceVariant)
                .accessibilityIdentifier("combo.seen")
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // En oscuro la hoja ya es `containerLow` (= `card`): la tarjeta sube un escalón.
        .solarCard(fill: scheme == .dark ? Theme.containerHigh : Theme.card)
        // Halo de tarjeta del ejemplo (L1): la hoja habla el mismo idioma que las cuatro pestañas.
        .glowCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("combo.status")
    }

    private var statusDetail: String {
        if let unlock {
            return "Desde el \(RejillaDateText.long(unlock.firstSeenAt)) · \(unlock.source.label)"
        }
        return "Fotografía ropa con estos colores o escanea tu carrete: se desbloquea cuando el motor la reconoce."
    }

    private func actions(_ colors: [PaletteColor]) -> some View {
        HStack(spacing: Spacing.gutter) {
            SolarSecondaryButton(title: copied ? "Copiados" : "Copiar hex", systemImage: "doc.on.doc", isDone: copied) {
                UIPasteboard.general.string = DesignFormat.hexList(colors)
                withAnimation(.easeOut(duration: 0.2)) { copied = true }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    withAnimation(.easeIn(duration: 0.2)) { copied = false }
                }
            }
            .accessibilityIdentifier("combo.copy")
            if let garden {
                GardenSaveButton(garden: garden, comboId: comboId)
            }
        }
    }
}

/// «Guardar» / «Guardada» de una combinación en el Jardín (colección local).
private struct GardenSaveButton: View {
    @ObservedObject var garden: GardenStore
    let comboId: Int

    var body: some View {
        let saved = garden.isSaved(comboId: comboId)
        SolarSecondaryButton(title: saved ? "Guardada" : "Guardar", systemImage: saved ? "leaf.fill" : "leaf") {
            garden.toggle(comboId: comboId)
        }
        .accessibilityLabel(saved ? "Guardada en tu jardín" : "Guardar en tu jardín")
        .accessibilityIdentifier("combo.save")
    }
}

/// Ficha de un color del diccionario: toda la ficha es un pocillo neutro (§1.4).
struct WadaColorCard: View {
    let color: WadaColor
    var comboCount: Int = 0
    var onSearch: (() -> Void)?

    private static let spanish = Locale(identifier: "es_ES")

    var body: some View {
        let data = PaletteColor(id: color.index, wada: color)
        let swatchShape = RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
        SwatchWell(padding: Spacing.sm, cornerRadius: Radius.card) {
            HStack(alignment: .top, spacing: Spacing.md) {
                swatchShape
                    .fill(data.color)
                    .overlay(SwatchHairline(shape: swatchShape))
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(color.name)
                        .textRole(.headlineSM)
                        .foregroundStyle(Theme.wellText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(data.hex) · RGB \(color.rgb.map(String.init).joined(separator: " "))")
                        .textRole(.hex)
                        .foregroundStyle(Theme.wellTextSecondary)
                    if let lab = dictionaryColorLab(index: color.index) {
                        Text("Lab \(number(lab.L)) · \(number(lab.a)) · \(number(lab.b))")
                            .textRole(.hex)
                            .foregroundStyle(Theme.wellTextSecondary)
                    }
                    if comboCount > 0 {
                        searchRow
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var searchRow: some View {
        let title = comboCount == 1 ? "En 1 combinación" : "En \(comboCount) combinaciones"
        if let onSearch {
            Button(action: onSearch) {
                HStack(spacing: 3) {
                    Text(title).textRole(.labelMD)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Theme.wellText)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.solarPress)
            .accessibilityHint("Busca en la rejilla las combinaciones con \(color.name)")
        } else {
            Text(title).textRole(.labelMD).foregroundStyle(Theme.wellTextSecondary)
        }
    }

    private func number(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(2)).locale(Self.spanish))
    }
}
