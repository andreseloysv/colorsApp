// Componentes del Jardín (docs/design/DESIGN_SYSTEM.md §4 n.º 24–27): cabecera con
// contadores reales, colecciones, cosechas y fichas del estudio de exportación.
// Sin retratos, perfiles ajenos ni contadores sociales (§0.2 B).
import SwiftUI

/// Un contador de `StatHeader` («Fotos analizadas 42»).
struct StatItem: Identifiable {
    let id: String
    let value: String
    let label: String
    var tone: Tone = .moss
    var action: (() -> Void)?
}

/// Tarjeta de perfil local con tres contadores (§4 n.º 24).
struct StatHeader: View {
    var title: String = "Tu jardín"
    var subtitle: String = "Solo en este teléfono · sin cuenta"
    /// Línea de acierto: «Acierto: 82 % (41 de 50 votos)».
    var detail: String?
    let stats: [StatItem]
    var onSettings: (() -> Void)?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Circle()
                    .fill(Tone.moss.badgeFill)
                    .frame(width: Sizes.profileBadge, height: Sizes.profileBadge)
                    .overlay {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Tone.moss.onBadge)
                    }
                    .padding(3)
                    .background(Circle().fill(Tone.amber.badgeFill))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).textRole(.headlineSM).foregroundStyle(Theme.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle).textRole(.labelMD).foregroundStyle(Theme.secondary)
                    if let detail {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(Theme.primary)
                                .accessibilityHidden(true)
                            Text(detail).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant)
                        }
                        .padding(.top, 1)
                    }
                }
                Spacer(minLength: 0)
                if let onSettings {
                    SolarIconButton(systemImage: "gearshape", accessibilityLabel: "Ajustes", size: 36, iconSize: 17,
                                    foreground: Theme.primary, background: Theme.container, action: onSettings)
                        .accessibilityIdentifier("jardin.settings")
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.element.id) { i, stat in
                    if i > 0 {
                        Rectangle().fill(Theme.outlineVariant.opacity(0.6)).frame(width: 1 / max(displayScale, 1), height: 32)
                    }
                    statCell(stat)
                }
            }
            .padding(.vertical, Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.containerLow, Theme.container, Theme.containerLow],
                                         startPoint: .leading, endPoint: .trailing))
            }
            .overlay(RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
                .strokeBorder(Theme.outlineVariant.opacity(0.3), lineWidth: 1 / max(displayScale, 1)))
        }
        .padding(Spacing.md)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card)
                SolarWash(kind: .warm, diameter: 150, blur: 40).offset(x: 60, y: -70)
                SolarWash(kind: .green, diameter: 130, blur: 34).offset(x: -170, y: 110)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .elevation(.rest)
        }
    }

    @ViewBuilder private func statCell(_ stat: StatItem) -> some View {
        let cell = VStack(spacing: 3) {
            Text(stat.value)
                .textRole(.headlineSM, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(stat.tone.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(stat.label)
                .textRole(.labelSM)
                .foregroundStyle(Theme.onSurfaceVariant)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        if let action = stat.action {
            Button(action: action) { cell.contentShape(Rectangle()) }.buttonStyle(.solarPress)
        } else {
            cell
        }
    }
}

/// Píldora de colección (§4 n.º 25): punto de tono (no de datos), título y contador.
struct CollectionPill: View {
    enum Kind: Sendable, Equatable {
        case collection(Tone)
        /// «Nueva carpeta».
        case create
    }

    let title: String
    var count: String?
    var kind: Kind = .collection(.moss)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                switch kind {
                case .collection(let tone):
                    Circle().fill(dotColor(tone)).frame(width: 10, height: 10).accessibilityHidden(true)
                case .create:
                    Image(systemName: "folder.badge.plus").font(.system(size: 14, weight: .medium)).accessibilityHidden(true)
                }
                Text(title).textRole(.labelMD).lineLimit(1)
                if let count {
                    Text(count)
                        .textRole(.labelSM)
                        .monospacedDigit()
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.container))
                }
            }
            .foregroundStyle(kind == .create ? Theme.primary : Theme.onSurface)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: 36)
            .background {
                Capsule().fill(kind == .create ? Theme.containerHigh : Theme.card).elevation(.small)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.solarPress)
    }

    private func dotColor(_ tone: Tone) -> Color {
        switch tone {
        case .moss: Theme.primary
        case .amber: Color(light: 0xFD933F, dark: 0xFFB785)
        case .celadon: Theme.tertiary
        }
    }
}

/// Cosecha: un análisis guardado en el Jardín (§4 n.º 26).
struct HarvestRow: View {
    enum Variant: Sendable, Equatable {
        /// Gotas con hex y fila «Dominante» (la más reciente).
        case droplets
        /// Barra de proporción + micro-píldoras (resto).
        case proportion
    }

    let thumbnail: Image?
    let title: String
    /// «ayer · Carrete».
    let metadata: String
    var verdict: Verdict?
    let palette: [PaletteColor]
    var variant: Variant = .droplets
    /// Etiquetas reales («Nº 337», «Ambigua»).
    var tags: [String] = []
    var isSaved: Bool = false
    var isCopied: Bool = false
    var onCopyDominant: (() -> Void)?
    var onToggleSave: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            switch variant {
            case .droplets: dropletsBody
            case .proportion: proportionBody
            }
        }
        .padding(Spacing.md)
        .background { RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card).elevation(.restStrong) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Group {
                if let thumbnail {
                    thumbnail.resizable().scaledToFill()
                } else {
                    Theme.containerLow.overlay {
                        Image(systemName: "photo").foregroundStyle(Theme.onSurfaceVariant)
                    }
                }
            }
            .frame(width: Sizes.harvestThumb, height: Sizes.harvestThumb)
            .clipShape(RoundedRectangle(cornerRadius: Radius.block, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textRole(.headlineSM).foregroundStyle(Theme.onSurface).lineLimit(2)
                Text(metadata).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant).lineLimit(1)
            }
            Spacer(minLength: Spacing.xs)
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                VerdictBadge(verdict: verdict)
                if let onToggleSave {
                    Button(action: onToggleSave) {
                        Image(systemName: isSaved ? "leaf.fill" : "leaf")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(isSaved ? Theme.primary : Theme.onSurfaceVariant)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.solarPress)
                    .accessibilityLabel(isSaved ? "Guardada: quitar del jardín" : "Guardar en tu jardín")
                }
            }
        }
    }

    private var dropletsBody: some View {
        SwatchWell(padding: Spacing.sm, cornerRadius: Radius.block) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                PaletteRibbon(colors: palette, style: .droplets(names: false, hex: true, weights: false),
                              dropletSize: 48, inWell: false)
                if let dominant = palette.first {
                    Rectangle().fill(Theme.wellEdge).frame(height: 1)
                    HStack(spacing: Spacing.xs) {
                        Text(dominantText(dominant))
                            .textRole(.labelMD)
                            .foregroundStyle(Theme.wellText)
                            .lineLimit(2)
                        Spacer(minLength: Spacing.xs)
                        if let onCopyDominant {
                            Button(action: onCopyDominant) {
                                HStack(spacing: 3) {
                                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc").font(.system(size: 12, weight: .medium))
                                    Text(isCopied ? "Copiado" : "Copiar").textRole(.labelSM)
                                }
                                .foregroundStyle(Theme.wellText)
                                .frame(minHeight: 32)
                                .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Copiar hex dominante")
                        }
                    }
                }
            }
        }
    }

    private var proportionBody: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SwatchWell(padding: Spacing.sm, cornerRadius: Radius.block) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(palette.compactMap { $0.weight.map(DesignFormat.percent) }.joined(separator: " · "))
                        .textRole(.bodySM)
                        .monospacedDigit()
                        .foregroundStyle(Theme.wellTextSecondary)
                    PaletteRibbon(colors: palette, style: .weights, height: Sizes.weightBar, inWell: false)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(palette.prefix(3)) { c in MicroColorPill(color: c, showsHex: false) }
                }
            }
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        SolarBadge(title: tag, fill: tag == "Ambigua" ? Theme.secondaryFixed : Theme.container,
                                   foreground: tag == "Ambigua" ? Theme.onSecondaryFixedVariant : Theme.primary)
                    }
                }
            }
        }
    }

    private func dominantText(_ c: PaletteColor) -> String {
        var s = "Dominante: "
        if let name = c.name { s += "\(name) (\(c.hex))" } else { s += c.hex }
        if let w = c.weight { s += " · \(DesignFormat.percent(w))" }
        return s
    }
}

/// Ficha del estudio de exportación (§4 n.º 27): acciones reales (tarjeta, hex, diagnóstico, carrete).
struct ExportTile: View {
    enum State: Equatable {
        case idle
        case working
        /// Listo: si hay `shareURL` la ficha se convierte en `ShareLink`.
        case ready
        case failed(String)
        case disabled
    }

    let title: String
    let detail: String
    let systemImage: String
    var tone: Tone = .moss
    var state: State = .idle
    var shareURL: URL?
    let action: () -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if state == .ready, let shareURL {
                ShareLink(item: shareURL) { label }
            } else {
                Button(action: action) { label }
                    .disabled(state == .disabled || state == .working)
            }
        }
        .buttonStyle(.solarPress)
    }

    private var label: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
        return VStack(alignment: .leading, spacing: 2) {
            ZStack {
                Circle().fill(tone.badgeFill).frame(width: 32, height: 32)
                if state == .working {
                    ProgressView().controlSize(.small).tint(tone.onBadge)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tone.onBadge)
                }
            }
            .padding(.bottom, 6)
            Text(title)
                .textRole(.labelMD)
                .foregroundStyle(Theme.onSurface)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(detailText)
                .textRole(.bodySM)
                .foregroundStyle(isFailed ? Theme.error : Theme.onSurfaceVariant)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background { shape.fill(Theme.card).elevation(.small) }
        .overlay(shape.strokeBorder(Theme.outlineVariant.opacity(0.3), lineWidth: 1 / max(displayScale, 1)))
        .opacity(state == .disabled ? 0.5 : 1)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }

    private var isFailed: Bool { if case .failed = state { true } else { false } }

    private var iconName: String {
        switch state {
        case .ready: "checkmark"
        case .failed: "exclamationmark.triangle"
        default: systemImage
        }
    }

    private var detailText: String {
        if case .failed(let message) = state { return message }
        return detail
    }
}
