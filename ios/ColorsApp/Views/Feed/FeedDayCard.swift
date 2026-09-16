// Combinación del día del Feed con las luces del ejemplo (docs/design/FIDELITY.md §3
// F14–F24; `solar_feed…/code.html`, «Hero Quick-Pick Banner»):
// - tarjeta `rounded-xl bg-surface-container p-space-md` con halo que respira ámbar ↔ verde
//   azulado y borde que cambia de color (4 s), y los anillos de reloj de sol (144 pt,
//   `-right-6 -top-6`, opacidad 0,6, giro de 25 s) en el fondo;
// - rótulo con icono de sol que late (`animate-pulse`), punto verde azulado con
//   `animate-ping` mientras es la de hoy e insignia «Nº» con filo ámbar al 20 % y `shadow-sm`;
// - tira de la combinación en su pocillo neutro (sin anillo ámbar ni sombra: zona neutra):
//   tocar un segmento copia su hex y, al barajar, los colores cambian en 500 ms;
// - pie «✦ nombre» + estado en mayúsculas;
// - botón de latón «Otra combinación»: halo ámbar `0 0 18px` 40 % (24 px 60 % al pulsar),
//   filo `amber-300/40`, barrido de luz de 2,5 s bajo el texto, destellos girando (6 s) y
//   `active:scale-[0.98]`. Hay ≥ 16 pt entre el pocillo y el botón (FIDELITY §0.2).
import SwiftUI

struct FeedDayCard: View {
    let eyebrow: String
    /// Es la combinación de hoy (punto con ping); false tras «Otra combinación».
    let isToday: Bool
    let comboId: Int
    let numberLabel: String
    let name: String
    let colors: [PaletteColor]
    /// «2 colores · En tu rejilla».
    let status: String
    var onShuffle: () -> Void
    var onOpen: (() -> Void)?
    var onCopyColor: ((PaletteColor) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            eyebrowRow
            VStack(alignment: .leading, spacing: 6) {
                ribbon
                footer
            }
            FeedBrassButton(title: "Otra combinación", systemImage: "sparkles", action: onShuffle)
                .padding(.top, Spacing.xs)
                .accessibilityIdentifier("feed.day.shuffle")
        }
        .padding(Spacing.md)
        .background {
            ZStack(alignment: .topTrailing) {
                shape.fill(Theme.container)
                SunDialRings()
                    .offset(x: MotionSpec.SunDial.offset, y: -MotionSpec.SunDial.offset)
            }
            .clipShape(shape)
        }
        .glowPulse(shape)
    }

    // MARK: Rótulo

    private var eyebrowRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "sun.max")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .pulse()
                .accessibilityHidden(true)
            HStack(spacing: Spacing.xs) {
                Text(eyebrow)
                    .textRole(.overline)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if isToday {
                    PingDot(color: TailwindColor.teal400.color, size: 6, keepsCore: false)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: Spacing.sm)
            FeedNumberBadge(title: numberLabel)
        }
    }

    // MARK: Tira

    private var ribbon: some View {
        let strip = RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
        return SwatchWell(padding: Spacing.wellPadding, cornerRadius: Radius.block) {
            HStack(spacing: Spacing.swatchDivider) {
                ForEach(Array(colors.enumerated()), id: \.offset) { i, color in
                    segment(color, index: i)
                }
            }
            .frame(height: Sizes.dayRibbon)
            .clipShape(strip)
            .animation(reduceMotion ? .easeOut(duration: MotionSpec.reducedFadeDuration)
                                    : .timingCurve(0.4, 0, 0.2, 1, duration: 0.5), value: comboId)
        }
        // Margen del color de la tarjeta alrededor del pocillo: los anillos giratorios del fondo
        // no llegan a 8 pt de la tira (zona neutra).
        .background(
            RoundedRectangle(cornerRadius: Radius.block + Spacing.sm, style: .continuous)
                .fill(Theme.container)
                .padding(-Spacing.sm)
        )
        .feedNeutralMargin(cornerRadius: Radius.block)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.day.ribbon")
    }

    @ViewBuilder private func segment(_ color: PaletteColor, index: Int) -> some View {
        let fill = Rectangle().fill(color.color).overlay(SwatchHairline(shape: Rectangle()))
        let label = DesignFormat.accessibilityLabel(color, position: index, total: colors.count)
        if let onCopyColor {
            Button { onCopyColor(color) } label: { fill.contentShape(Rectangle()) }
                .buttonStyle(.pressScale)
                .accessibilityLabel(label)
                .accessibilityHint("Copia el hex")
        } else {
            fill.accessibilityElement().accessibilityLabel(label)
        }
    }

    // MARK: Pie

    private var footer: some View {
        let content = ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                nameLabel
                Spacer(minLength: Spacing.sm)
                statusLabel
            }
            VStack(alignment: .leading, spacing: 2) {
                nameLabel
                statusLabel
            }
        }
        return Group {
            if let onOpen {
                Button(action: onOpen) { content.contentShape(Rectangle()) }
                    .buttonStyle(.pressScaleWide)
                    .accessibilityHint("Abre la combinación")
            } else {
                content
            }
        }
        .accessibilityIdentifier("feed.day.name")
    }

    private var nameLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("✦")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
            Text(name)
                .textRole(.headlineSM)
                .foregroundStyle(Theme.onSurface)
                .lineLimit(2)
        }
    }

    private var statusLabel: some View {
        Text(status)
            .textRole(.feedDayStatus)
            .foregroundStyle(Theme.onSurfaceVariant)
            .lineLimit(1)
            .fixedSize()
            // Los anillos del fondo pasan por detrás del texto, no lo tachan (legibilidad AA).
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.container))
            .padding(.horizontal, -Spacing.xs)
    }
}

extension TextRole {
    /// Estado de la tarjeta del día (`font-label-sm tracking-wider`, en mayúsculas).
    static let feedDayStatus = TextRole(id: "feed-day-status", family: .sans, weight: .semibold, size: 11, lineHeight: 13,
                                        tracking: 0.55, textStyle: .caption2, uppercase: true)
}

/// Insignia «Nº 098» (F19): `px-2 py-0.5 rounded-full bg-surface-container-highest border
/// border-amber-500/20 shadow-sm`, texto `onSurfaceVariant` (el `outline` del ejemplo no llega a AA).
struct FeedNumberBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .textRole(.labelSM)
            .monospacedDigit()
            .foregroundStyle(Theme.onSurfaceVariant)
            .lineLimit(1)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(Theme.containerHighest)
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
            }
            .overlay(Capsule().strokeBorder(TailwindColor.amber500.opacity(0.2).color, lineWidth: 1))
    }
}

// MARK: - Botón de latón

/// Botón de latón luminoso del ejemplo (F22–F24) con las medidas exactas (`py-2.5 px-space-md`,
/// `gap-2`, `label-lg`): cápsula `secondary`, halo ámbar, filo `amber-300/40`, barrido de luz
/// en el FONDO (el texto no pierde contraste), icono `amber-200` girando cada 6 s y pulsación 0,98.
/// Área táctil de 44 pt aunque la cápsula mida 40.
struct FeedBrassButton: View {
    let title: String
    /// `magic_button` del ejemplo: en la captura se lee como un destello de cuatro puntas con chispas.
    var systemImage: String = "sparkles"
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(light: 0xFDE68A, dark: 0x713700))
                    .spinning(duration: MotionSpec.Spin.brassButton)
                    .accessibilityHidden(true)
                Text(title)
                    .textRole(.labelLG)
                    .foregroundStyle(Theme.onSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
                Capsule()
                    .fill(Theme.secondary)
                    .shimmerSweep(Capsule())
            }
            .overlay(Capsule().strokeBorder(MotionSpec.brassButtonBorder.color, lineWidth: 1).allowsHitTesting(false))
            .warmShadow(.brassButton, in: Capsule())
            .opacity(isEnabled ? 1 : 0.5)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressScaleWide)
    }
}
