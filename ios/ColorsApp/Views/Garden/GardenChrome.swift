// Marco del Jardín con los valores de my_garden_vault…/code.html (FIDELITY.md §6):
// cabecera esmerilada con el logotipo y el wordmark de ChromaSol, sol con destello
// (acción real: escanear el carrete) y avatar local con filo de luz e insignia «✦» que
// solo aparece si hay combinaciones nuevas desde la última visita; retrato del jardín
// (brote en maceta que se balancea, anillo con degradado y halo) con su compañera, la
// semilla solar que bota; segmentos con sombra interior; carpetas; títulos de sección y
// toast musgo con el icono girando. Personajes originales de Design/Brand.
import SwiftUI

// MARK: - Cabecera

/// Cabecera del Jardín: `header.h-16.px-margin bg-surface/85 backdrop-blur-xl` + logotipo `h-8`,
/// «ChromaSol» / «JARDÍN», sol `w-11 h-11` y avatar `p-0.5 bg-secondary-fixed` con filo de luz.
struct GardenHeader: View {
    /// Combinaciones desbloqueadas desde la última visita (insignia «✦»; 0 = sin insignia).
    var newUnlocks: Int
    var onScan: () -> Void
    var onAvatar: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ChromaSolLockup(section: "Jardín", showsDot: false, animated: false)
            Spacer(minLength: Spacing.sm)
            GardenSunButton(action: onScan)
            GardenHeaderAvatar(newUnlocks: newUnlocks, action: onAvatar)
        }
        .padding(.horizontal, Spacing.margin)
        .frame(minHeight: Sizes.header)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background { FrostedHeaderBackground() }
        .accessibilityIdentifier("jardin.header")
    }
}

/// Sol de la cabecera: `sunny` 20 px `text-secondary` en un botón de 44 pt, con el destello solar
/// de la marca (12 s, 0 → 180 → 0°, halo ámbar 6 → 14 px) y el glifo de la acción abajo a la derecha.
struct GardenSunButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "sun.max")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.secondary)
                    .solarSparkle()
                    .frame(width: Sizes.headerButton, height: Sizes.headerButton)
                Image(systemName: "photo.stack")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .padding(2)
                    .background(Circle().fill(Theme.surface))
                    .offset(x: -3, y: -4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel("Escanear carrete")
        .accessibilityIdentifier("jardin.header.scan")
    }
}

/// Avatar local de la cabecera (`relative p-0.5 rounded-full bg-secondary-fixed
/// shadow-[inset_0_1px_1px_rgba(255,255,255,0.7)]` + `w-8 h-8` + insignia `-top-0.5 -right-0.5`).
struct GardenHeaderAvatar: View {
    var newUnlocks: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GardenPortrait(diameter: Sizes.avatar)
                .padding(2)
                .background(Circle().fill(Color(light: 0xFFDCC6, dark: 0x713700)))
                .insetSunGlint(Circle())
                .overlay(alignment: .topTrailing) {
                    if newUnlocks > 0 {
                        GardenSparkBadge().offset(x: 2, y: -2)
                    }
                }
                .frame(width: Sizes.headerButton, height: Sizes.headerButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel(newUnlocks > 0
            ? "Tu jardín, \(newUnlocks) \(newUnlocks == 1 ? "combinación nueva" : "combinaciones nuevas")"
            : "Tu jardín")
        .accessibilityIdentifier("jardin.header.avatar")
    }
}

/// Insignia «✦» (`w-3.5 h-3.5 rounded-full bg-secondary-container text-[8px] text-on-secondary shadow-sm`).
struct GardenSparkBadge: View {
    var diameter: CGFloat = 14
    var glyph: CGFloat = 8

    var body: some View {
        Circle()
            .fill(Theme.secondaryContainer)
            .frame(width: diameter, height: diameter)
            .overlay {
                Text("✦").font(.system(size: glyph, weight: .bold)).foregroundStyle(Color(light: 0xFFFFFF, dark: 0xFFDCC6))
            }
            .gardenShadow(GardenShadow.sm)
            .accessibilityHidden(true)
    }
}

// MARK: - Retrato del jardín

/// Retrato local (no hay fotos de perfil): cielo cálido que se vuelve menta y el brote en maceta
/// de la marca. `pose` = pose del brote (reposo por defecto).
struct GardenPortrait: View {
    let diameter: CGFloat
    var pose: TabIconPose = .rest

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(light: 0xFFF6E3, dark: 0x3C372E), Color(light: 0xBCEFC7, dark: 0x224F32)],
                                         center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: diameter * 0.75))
            BrandTabIconFrame(kind: .jardin, pose: pose, size: diameter * 0.98)
                .offset(y: diameter * 0.03)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Insignia del perfil: `div.relative.p-1.rounded-full.bg-gradient-to-tr.from-secondary-fixed.via-primary-fixed
/// .to-secondary-container/40.shadow-md` (+ halo) con el retrato de 56 pt y la compañera
/// `span.absolute.-bottom-1.-right-1.w-5.h-5.rounded-full.bg-inverse-surface.border-2.border-surface.shadow-md`.
/// El brote se balancea (2,6 s) y la semilla bota (2,2 s) y parpadea (3,4 s).
struct GardenProfileBadge: View {
    var diameter: CGFloat = Sizes.profileBadge

    var body: some View {
        AmbientTimeline(frameInterval: GardenMotion.characterFrameInterval) { t in
            GardenPortrait(diameter: diameter,
                           pose: t.map { BrandMotion.pose(.jardin, at: $0, active: true, reduceMotion: false) } ?? .rest)
        }
        .padding(4)
        .background {
            Circle()
                .fill(LinearGradient(stops: [.init(color: Color(light: 0xFFDCC6, dark: 0x713700), location: 0),
                                             .init(color: Color(light: 0xBCEFC7, dark: 0x2D5A3C), location: 0.5),
                                             .init(color: Color(light: 0xFD933F, dark: 0xFD933F, lightOpacity: 0.4, darkOpacity: 0.5), location: 1)],
                                     startPoint: .bottomLeading, endPoint: .topTrailing))
                .gardenShadow(GardenShadow.md)
        }
        .background { OuterGlow(shape: Circle(), shadows: GardenShadow.portraitGlow) }
        .overlay(alignment: .bottomTrailing) {
            GardenCompanion().offset(x: 4, y: 4)
        }
        .accessibilityHidden(true)
    }
}

/// Semilla solar de la pestaña Feed en un disco `inverse-surface` de 20 pt con borde `surface` de 2 pt.
struct GardenCompanion: View {
    var body: some View {
        AmbientTimeline(frameInterval: GardenMotion.characterFrameInterval) { t in
            BrandTabIconFrame(kind: .feed,
                              pose: t.map { BrandMotion.pose(.feed, at: $0, active: true, reduceMotion: false) } ?? .rest,
                              size: 13)
        }
        .frame(width: 16, height: 16)
        .background(Circle().fill(Theme.inverseSurface))
        .clipShape(Circle())
        .padding(2)
        .background(Circle().fill(Theme.surface))
        .gardenShadow(GardenShadow.md)
        .accessibilityHidden(true)
    }
}

// MARK: - Segmentos, carpetas y títulos

/// Segmentos: `div.flex.items-center.p-1.bg-surface-container-high.rounded-full.shadow-inner` >
/// activo `button.flex-1.py-1.5.px-space-xs.rounded-full.bg-primary.text-on-primary.font-label-md.shadow-sm`.
struct GardenSegmentBar: View {
    @Binding var selection: GardenModel.Segment
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GardenModel.Segment.allCases) { item in
                let selected = item == selection
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: MotionSpec.reducedFadeDuration)
                                               : .timingCurve(0.4, 0, 0.2, 1, duration: MotionSpec.Press.slowDuration)) {
                        selection = item
                    }
                } label: {
                    Text(item.title)
                        .textRole(.labelMD)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(selected ? Theme.onPrimary : Theme.onSurfaceVariant)
                        .padding(.vertical, 6)
                        .padding(.horizontal, Spacing.xs)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background {
                            if selected {
                                Capsule().fill(Theme.primary)
                                    .gardenShadow(GardenShadow.sm)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("jardin.segment.\(item.rawValue)")
            }
        }
        .padding(Spacing.xs)
        .background(Capsule().fill(Theme.containerHigh.shadow(.inner(color: .black.opacity(0.05), radius: 2, x: 0, y: 2))))
    }
}

/// Carpeta: `div.flex.items-center.gap-2.px-3.py-2.rounded-full.bg-surface-container-lowest.text-on-surface
/// .shadow-[0_2px_8px_-1px_rgba(68,48,28,0.06)]` + punto `w-2.5 h-2.5` + `label-md` + contador
/// `label-sm px-1.5 py-0.5 rounded-full bg-surface-container`.
struct GardenFolderPill: View {
    let title: String
    var count: String?
    let dot: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Circle().fill(dot).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(title).textRole(.labelMD).foregroundStyle(Theme.onSurface).lineLimit(1)
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
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background { Capsule().fill(Theme.card).gardenShadow(GardenShadow.folder) }
            .contentShape(Capsule())
        }
        .buttonStyle(.pressScale)
    }
}

/// Título de sección: icono 18 px `text-primary` + `h3.font-headline-sm.text-primary.tracking-tight`
/// + rótulo `label-sm` a la derecha.
struct GardenSectionTitle: View {
    let title: String
    let systemImage: String
    var iconColor: Color = Theme.primary
    var trailing: String?
    var trailingRole: TextRole = .labelSM
    var trailingColor: Color = Theme.onSurfaceVariant

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            Text(title)
                .textRole(GardenType.headlineTight)
                .foregroundStyle(Theme.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.sm)
            if let trailing {
                Text(trailing).textRole(trailingRole).foregroundStyle(trailingColor).lineLimit(1)
            }
        }
    }
}

// MARK: - Toast

/// Toast del Jardín: `div#toast.fixed.bottom-20 … px-4 py-2 rounded-full bg-primary text-on-primary
/// font-label-md shadow-xl gap-2` + `auto_awesome` 16 px `text-primary-fixed` (girando 3 s como el
/// toast luminoso del Feed). Aparece y se va solo con opacidad (300 ms, visible 2 200 ms).
struct GardenToast: View {
    let title: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(light: 0xBCEFC7, dark: 0x144226))
                .spinning(duration: MotionSpec.Spin.toast)
                .accessibilityHidden(true)
            Text(title).textRole(.labelMD).foregroundStyle(Theme.onPrimary).lineLimit(2)
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.vertical, Spacing.sm)
        .background { Capsule().fill(Theme.primary).gardenShadow(GardenShadow.xl) }
        .accessibilityElement(children: .combine)
    }
}
