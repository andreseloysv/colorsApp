// Estudio de exportación del Jardín (FIDELITY.md §6, G30–G33) con los valores de
// my_garden_vault…/code.html: `section.rounded-xl.bg-surface-container.p-space-md.shadow-sm`,
// cabecera con `handyman` ámbar y «HERRAMIENTAS», y fichas `button.relative.overflow-hidden.p-space-sm
// .rounded-lg.bg-surface-container-lowest.border.border-outline-variant/30.active:scale-98` con orbe de
// esquina (`-right-2 -top-2 w-10 h-10 …/20 blur-md`, `/40` al pulsar), disco de icono con halo
// (`shadow-[0_0_10px_rgba(…,0.6)]`, escala 1,05 al pulsar) y filo del tono al pulsar. Acciones
// reales: compartir la tarjeta, copiar hex, exportar el diagnóstico y escanear el carrete.
import SwiftUI

struct GardenStudioSection<Tiles: View>: View {
    @ViewBuilder var tiles: Tiles

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            GardenSectionTitle(title: "Estudio de exportación", systemImage: "wrench.and.screwdriver", iconColor: Theme.secondary,
                               trailing: dynamicTypeSize.isAccessibilitySize ? nil : "Herramientas",
                               trailingRole: .overline, trailingColor: Theme.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.sm) {
                tiles
            }
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Theme.container)
                .gardenShadow(GardenShadow.sm)
        }
    }

    /// 2 columnas; 1 con tamaños de accesibilidad.
    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)]
    }
}

/// Ficha del estudio. `state == .ready` con `shareURL` la convierte en `ShareLink`.
struct GardenStudioTile: View {
    let title: String
    let detail: String
    let systemImage: String
    var accent: GardenAccent = .moss
    var state: ExportTile.State = .idle
    var shareURL: URL?
    let action: () -> Void

    var body: some View {
        Group {
            if state == .ready, let shareURL {
                ShareLink(item: shareURL) { label }
            } else {
                Button(action: action) { label }
                    .disabled(state == .disabled || state == .working)
            }
        }
        .buttonStyle(.pressScaleWide)
    }

    private var label: some View {
        GardenStudioTileLabel(title: title, detail: detail, systemImage: systemImage, accent: accent, state: state)
    }
}

/// Etiqueta de la ficha (lee `\.solarButtonPressed` para el orbe, el filo y el disco).
private struct GardenStudioTileLabel: View {
    let title: String
    let detail: String
    let systemImage: String
    let accent: GardenAccent
    let state: ExportTile.State

    @Environment(\.solarButtonPressed) private var pressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                OuterGlow(shape: Circle(), shadows: [accent.discGlow])
                Circle().fill(accent.disc)
                if state == .working {
                    ProgressView().controlSize(.small).tint(accent.ink)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent.ink)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 32, height: 32)
            .scaleEffect(pressed && !reduceMotion ? 1.05 : 1)
            .padding(.bottom, Spacing.sm)
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
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background {
            ZStack {
                shape.fill(Theme.card).gardenShadow(GardenShadow.tile)
                GeometryReader { geo in
                    Circle().fill(accent.orb.opacity(pressed ? 0.4 : 0.2))
                        .frame(width: 40, height: 40)
                        .blur(radius: 12)
                        .position(x: geo.size.width + 8 - 20, y: -8 + 20)
                }
                .clipShape(shape)
            }
        }
        .overlay(shape.strokeBorder(pressed ? accent.pressedBorder : Theme.outlineVariant.opacity(0.3), lineWidth: 1))
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: MotionSpec.Press.duration), value: pressed)
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
