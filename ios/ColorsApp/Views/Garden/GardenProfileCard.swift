// Tarjeta de perfil local del Jardín (FIDELITY.md §6, G4–G15), con los valores de
// my_garden_vault…/code.html: `section.relative.rounded-xl.bg-surface-container-lowest.p-space-md`
// con sombra sepia E1, dos orbes difusos (`-right-8 -top-8 w-36 h-36 bg-secondary-fixed/40 blur-2xl`
// y `left-1/3 -bottom-10 w-32 h-32 bg-primary-fixed/40 blur-xl`), tres luciérnagas (M18), la
// insignia con el retrato del jardín, nombre con la insignia «Local», subtítulo, línea de
// acierto con punto que late (`animate-ping`) y el carril de tres contadores reales con sus
// puntos de tono. Sin nombres de persona ni contadores sociales (§0.2 B).
import SwiftUI

/// Un contador de la tarjeta de perfil (`span.font-headline-sm.font-semibold` + rótulo con punto `w-1.5 h-1.5`).
struct GardenStat: Identifiable {
    let id: String
    let value: String
    let label: String
    let valueColor: Color
    let dotColor: Color
    var action: (() -> Void)?
}

struct GardenProfileCard: View {
    var title: String = "Tu jardín"
    var subtitle: String = "Solo en este teléfono · sin cuenta"
    /// Votos del usuario (`Acierto: 75 % (3 de 4 votos)`); sin votos, invitación a votar.
    let yesVotes: Int
    let noVotes: Int
    let stats: [GardenStat]
    var onSettings: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.card, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            metricsRail
                .padding(.top, Spacing.md)
                // Tres contadores de una línea en una fila fija: crecen hasta xLarge.
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                shape.fill(Theme.card).gardenShadow(GardenShadow.profile)
                decoration.clipShape(shape)
            }
        }
        .accessibilityIdentifier("jardin.profile")
    }

    // MARK: Fondo

    private var decoration: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                // -right-8 -top-8 w-36 h-36 bg-secondary-fixed/40 blur-2xl
                Circle().fill(Theme.washWarm).frame(width: 144, height: 144).blur(radius: 40)
                    .position(x: w + 32 - 72, y: -32 + 72)
                // left-1/3 -bottom-10 w-32 h-32 bg-primary-fixed/40 blur-xl
                Circle().fill(Theme.washGreen).frame(width: 128, height: 128).blur(radius: 24)
                    .position(x: w / 3 + 64, y: h + 40 - 64)
                GardenFirefliesLayer()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Fila superior

    @ViewBuilder private var topRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Tamaños de accesibilidad: insignia y ajustes arriba, textos debajo a todo el ancho.
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top) {
                    GardenProfileBadge()
                    Spacer(minLength: Spacing.sm)
                    settingsButton
                }
                texts
            }
        } else {
            HStack(alignment: .top, spacing: Spacing.sm) {
                HStack(alignment: .center, spacing: Spacing.md) {
                    GardenProfileBadge()
                    texts
                }
                Spacer(minLength: 0)
                settingsButton
            }
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameRow
            Text(subtitle)
                .textRole(GardenType.labelWide)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            accuracyLine.padding(.top, 2)
        }
    }

    @ViewBuilder private var settingsButton: some View {
        if let onSettings {
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 36, height: 36)
                    .background { Circle().fill(Theme.container).gardenShadow(GardenShadow.sm) }
                    .frame(width: Sizes.minTouch, height: Sizes.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressScale)
            .padding(-4)
            .accessibilityLabel("Ajustes")
            .accessibilityIdentifier("jardin.settings")
        }
    }

    @ViewBuilder private var nameRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                nameText.fixedSize(horizontal: false, vertical: true)
                localBadge
            }
        } else {
            HStack(spacing: 6) {
                nameText.lineLimit(1)
                localBadge
            }
        }
    }

    private var nameText: some View {
        Text(title)
            .textRole(GardenType.headlineTight)
            .foregroundStyle(Theme.primary)
            .accessibilityAddTraits(.isHeader)
    }

    /// `span.px-1.5.py-0.5.rounded-full.bg-secondary-fixed/50.text-[10px].font-label-sm.text-secondary` + `eco`.
    private var localBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "leaf.fill").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
            Text("Local").textRole(.labelSM, weight: .semibold).lineLimit(1).fixedSize()
        }
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color(light: 0xFFDCC6, dark: 0x713700, lightOpacity: 0.5, darkOpacity: 0.6)))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Local, sin cuenta")
    }

    /// `p.font-body-sm.text-on-surface-variant.flex.gap-1.mt-0.5` + punto `w-2 h-2 bg-primary
    /// shadow-[0_0_6px_#144226] animate-ping` + `local_florist` 14 px + valor `font-semibold text-primary`.
    private var accuracyLine: some View {
        let hasVotes = yesVotes + noVotes > 0
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            ZStack {
                OuterGlow(shape: Circle(), shadows: [ShadowSpec(TailwindColor.primary.opacity(0.9), blur: 6)])
                if hasVotes {
                    PingDot(color: Theme.primary, size: 8)
                } else {
                    Circle().fill(Theme.primary.opacity(0.5))
                }
            }
            .frame(width: 8, height: 8)
            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
            Image(systemName: "leaf.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.primary)
                .accessibilityHidden(true)
            if let parts = GardenText.accuracyParts(yes: yesVotes, no: noVotes) {
                (Text(parts.label + " ").foregroundStyle(Theme.onSurfaceVariant)
                    + Text(parts.value).fontWeight(.semibold).foregroundStyle(Theme.primary))
                    .textRole(.bodySM)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(GardenText.accuracy(yes: yesVotes, no: noVotes))
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("jardin.accuracy")
    }

    // MARK: Contadores

    /// `div.grid.grid-cols-3.gap-space-xs.mt-space-md.bg-gradient-to-r.from-surface-container-low.via-surface-container
    /// .to-surface-container-low.rounded-lg.p-space-sm.border.border-outline-variant/30`; celda central `border-x /40`.
    private var metricsRail: some View {
        let rail = RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
        return HStack(spacing: Spacing.xs) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { i, stat in
                statCell(stat)
                    .overlay {
                        if i == 1 {
                            HStack {
                                Rectangle().fill(Theme.outlineVariant.opacity(0.4)).frame(width: 1)
                                Spacer(minLength: 0)
                                Rectangle().fill(Theme.outlineVariant.opacity(0.4)).frame(width: 1)
                            }
                            .allowsHitTesting(false)
                        }
                    }
            }
        }
        .padding(Spacing.sm)
        .background {
            // Algo translúcido: el orbe verde del fondo asoma como en la captura del ejemplo.
            rail.fill(LinearGradient(colors: [Theme.containerLow, Theme.container, Theme.containerLow],
                                     startPoint: .leading, endPoint: .trailing))
                .opacity(0.88)
        }
        .overlay(rail.strokeBorder(Theme.outlineVariant.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder private func statCell(_ stat: GardenStat) -> some View {
        let cell = VStack(spacing: Spacing.xs) {
            Text(stat.value)
                .textRole(.headlineSM, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(stat.valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                Circle().fill(stat.dotColor).frame(width: 6, height: 6).accessibilityHidden(true)
                Text(stat.label)
                    .textRole(.labelSM)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        if let action = stat.action {
            Button(action: action) { cell.contentShape(Rectangle()) }
                .buttonStyle(.pressScale)
                .accessibilityIdentifier("jardin.stat.\(stat.id)")
        } else {
            cell
        }
    }
}
