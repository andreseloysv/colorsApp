// Botones, chips, píldoras e insignias del marco (docs/design/DESIGN_SYSTEM.md §4
// n.º 3, 4, 5, 15, 20, 21, 22, 28). Ninguno contiene colores de datos.
import SwiftUI

// MARK: - Botones

/// CTA principal (§4 n.º 20): cápsula musgo o ámbar, `label-lg`, filo de luz y E3.
struct SolarPrimaryButton: View {
    enum Variant: Sendable { case moss, amber }
    enum Size: Sendable { case regular, compact }

    let title: String
    var systemImage: String?
    var variant: Variant = .moss
    var size: Size = .regular
    var fullWidth: Bool = true
    /// E3 flotante. Poner false si el botón comparte tarjeta con un pocillo.
    var elevated: Bool = true
    var isLoading: Bool = false
    /// Botón de latón luminoso del ejemplo (Design/Motion): halo ámbar `0 0 18px` 40 % (24 px 60 %
    /// al pulsar), filo `amber-300/40`, barrido de luz de 2,5 s e icono girando (6 s). Solo en el
    /// marco: si el botón comparte tarjeta con un pocillo, dejar ≥ 16 pt de separación.
    var luminous: Bool = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: size == .regular ? 17 : 14, weight: .semibold))
                        .modifier(LuminousIconSpin(active: luminous && isEnabled))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .textRole(size == .regular ? .labelLG : .labelMD)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .regular ? Spacing.lg : Spacing.margin)
            .padding(.vertical, size == .regular ? Spacing.ctaVertical : Spacing.sm)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size == .regular ? 48 : 36)
            .background {
                Capsule().fill(background).elevation(elevated && isEnabled && !luminous ? .floating : .flat)
            }
            .modifier(LuminousButtonLight(active: luminous && isEnabled))
            .sunGlint(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.solarPress)
        .disabled(isLoading)
    }

    private var background: Color {
        guard isEnabled else { return Theme.onSurface.opacity(0.12) }
        return variant == .moss ? Theme.primary : Theme.secondary
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.onSurface.opacity(0.38) }
        return variant == .moss ? Theme.onPrimary : Theme.onSecondary
    }
}

/// Botón secundario en píldora (§4 n.º 21): `container`, texto `primary`, icono `secondary`, E2.
struct SolarSecondaryButton: View {
    let title: String
    var systemImage: String?
    var isDone: Bool = false
    var fullWidth: Bool = true
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isDone {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.primary)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.secondary)
                }
                Text(title).textRole(.labelMD).foregroundStyle(Theme.primary).lineLimit(1)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.buttonVertical)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Sizes.minTouch)
            .background { Capsule().fill(Theme.container).elevation(.small) }
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Capsule())
        }
        .buttonStyle(.solarPress)
    }
}

/// Botón fantasma con filigrana (§4 n.º 22): `surface`, borde latón 35 %, texto `primary`.
struct GhostButton: View {
    let title: String
    var systemImage: String?
    var fullWidth: Bool = true
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .medium)).accessibilityHidden(true)
                }
                Text(title).textRole(.labelLG).lineLimit(1)
            }
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Sizes.minTouch)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(Color(light: 0xC29B38, dark: 0xC29B38, lightOpacity: 0.35, darkOpacity: 0.45), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Capsule())
        }
        .buttonStyle(.solarPress)
    }
}

/// Botón de icono circular (cabecera 44 pt, menú 32 pt con área táctil de 44).
struct SolarIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var size: CGFloat = Sizes.headerButton
    var iconSize: CGFloat = 20
    var foreground: Color = Theme.onSurfaceVariant
    var background: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background { if let background { Circle().fill(background) } }
                .frame(minWidth: Sizes.minTouch, minHeight: Sizes.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.solarPress)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Chips y segmentos

/// Chip de filtro (§4 n.º 3): cápsula 12 × 6, `label-md`; activa musgo con icono.
struct FilterChip: View {
    let title: String
    var systemImage: String?
    var count: String?
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color(light: 0xFBBF24, dark: 0x0B3A1D) : Theme.onSurfaceVariant)
                        .modifier(SelectedChipIconPulse(active: isSelected && isEnabled))
                        .accessibilityHidden(true)
                }
                Text(title).textRole(.labelMD).lineLimit(1)
                if let count {
                    Text(count).textRole(.labelMD).monospacedDigit().opacity(0.85)
                }
            }
            .foregroundStyle(isSelected ? Theme.onPrimary : Theme.onSurfaceVariant)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.chipVertical + 1)
            .background { Capsule().fill(isSelected ? Theme.primary : Theme.containerHigh) }
            // Chip activo del ejemplo: `shadow-[0_0_12px_rgba(45,90,60,0.3)] border border-emerald-400/30`.
            .modifier(SelectedChipLight(active: isSelected && isEnabled))
            .opacity(isEnabled ? 1 : 0.5)
            .frame(minHeight: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(.solarPress)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Un chip de `FilterChipRow`.
struct FilterChipItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var systemImage: String?
    var count: String?
}

/// Fila horizontal desplazable de chips con selección única (Feed, Rejilla).
struct FilterChipRow<ID: Hashable>: View {
    let items: [FilterChipItem<ID>]
    @Binding var selection: ID
    var accessibilityIdentifier: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(items) { item in
                    FilterChip(title: item.title, systemImage: item.systemImage, count: item.count,
                               isSelected: item.id == selection) {
                        selection = item.id
                    }
                }
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.vertical, Spacing.xs)
        }
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

/// Segmentos en píldora (§4 n.º 4, Jardín): carril `containerHigh`, activo musgo.
struct SegmentedPill<ID: Hashable>: View {
    let items: [(id: ID, title: String)]
    @Binding var selection: ID

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.id) { item in
                let selected = item.id == selection
                Button {
                    selection = item.id
                } label: {
                    Text(item.title)
                        .textRole(.labelMD)
                        .lineLimit(1)
                        .foregroundStyle(selected ? Theme.onPrimary : Theme.onSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background { if selected { Capsule().fill(Theme.primary).elevation(.small) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Spacing.xs)
        .background(Capsule().fill(Theme.containerHigh))
    }
}

// MARK: - Píldoras, insignias, buscador, toast

/// Píldora esmerilada sobre la foto (§4 n.º 15).
struct HUDPill: View {
    enum Kind: Sendable { case notice, fallback, toggle(isOn: Bool) }
    let title: String
    var systemImage: String?
    var kind: Kind = .notice
    var uppercase: Bool = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let icon = kind.isFallback ? "exclamationmark.triangle" : systemImage {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
            }
            Text(title)
                .textRole(uppercase ? .overline : .labelSM)
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if case .toggle(true) = kind {
                Capsule().fill(Theme.primary)
            } else {
                Color.clear.parchmentFrost(Capsule())
            }
        }
        .elevation(.overPhoto)
    }

    private var textColor: Color {
        switch kind {
        case .notice: Theme.onSurface
        case .fallback: Theme.secondary
        case .toggle(let on): on ? Theme.onPrimary : Theme.primary
        }
    }

    private var iconColor: Color {
        switch kind {
        case .notice: Theme.secondary
        case .fallback: Theme.secondary
        case .toggle(let on): on ? Theme.onPrimary : Theme.primary
        }
    }
}

private extension HUDPill.Kind {
    var isFallback: Bool { if case .fallback = self { true } else { false } }
}

/// Insignia pequeña en cápsula (número «Nº 104», «Ambigua», veredictos).
struct SolarBadge: View {
    let title: String
    var systemImage: String?
    var fill: Color = Theme.containerHighest
    var foreground: Color = Theme.onSurfaceVariant

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
            }
            Text(title).textRole(.labelSM).monospacedDigit().lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 3)
        .background(Capsule().fill(fill))
    }
}

/// Veredicto de un análisis («Sí, es eso» / «No» / «Sin votar»).
enum Verdict: String, Sendable, Hashable {
    case yes, no
}

struct VerdictBadge: View {
    let verdict: Verdict?

    var body: some View {
        switch verdict {
        case .yes:
            SolarBadge(title: "Sí, es eso", systemImage: "heart.fill", fill: Theme.primaryFixed, foreground: Theme.onPrimaryFixed)
        case .no:
            SolarBadge(title: "No", systemImage: "hand.thumbsdown.fill", fill: Theme.secondaryFixed, foreground: Theme.onSecondaryFixed)
        case nil:
            SolarBadge(title: "Sin votar", fill: Theme.containerHigh, foreground: Theme.onSurfaceVariant)
        }
    }
}

/// Buscador en cápsula (§4 n.º 5): lupa `secondary`, texto `body-md`, botón de ajustes.
struct SolarSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    var onFilter: (() -> Void)?

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.onSurfaceVariant))
                .textRole(.bodyMD)
                .foregroundStyle(Theme.onSurface)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.onSurfaceVariant)
                }
                .accessibilityLabel("Borrar búsqueda")
            }
            if let onFilter {
                Button(action: onFilter) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Buscar por color")
            }
        }
        .padding(.leading, Spacing.margin)
        .padding(.trailing, Spacing.sm)
        .padding(.vertical, 6)
        .frame(minHeight: Sizes.minTouch)
        .background { Capsule().fill(Theme.card).elevation(.rest) }
        .overlay { if focused { Capsule().strokeBorder(Theme.primary.opacity(0.4), lineWidth: 1) } }
    }
}

/// Toast (§4 n.º 28): cápsula `inverseSurface`, `label-md`, icono `secondaryFixedDim`, E3.
struct SolarToast: View {
    let title: String
    var systemImage: String = "checkmark.circle.fill"
    /// Toast luminoso del ejemplo: halo ámbar `0 0 20px` 40 %, filo `amber-400/30` e icono girando (3 s).
    var luminous: Bool = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondaryFixedDim)
                .modifier(LuminousIconSpin(active: luminous, duration: MotionSpec.Spin.toast))
                .accessibilityHidden(true)
            Text(title).textRole(.labelMD).foregroundStyle(Theme.inverseOnSurface)
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.vertical, 10)
        .background { Capsule().fill(Theme.inverseSurface).elevation(luminous ? .flat : .floating) }
        .modifier(LuminousToastLight(active: luminous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Luces opcionales de los controles (valores en Design/Motion/MotionSpecs.swift)

private struct LuminousIconSpin: ViewModifier {
    let active: Bool
    var duration: Double = MotionSpec.Spin.brassButton

    func body(content: Content) -> some View {
        if active { content.spinning(duration: duration) } else { content }
    }
}

private struct LuminousButtonLight: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .shimmerSweep(Capsule())
                .overlay(Capsule().strokeBorder(MotionSpec.brassButtonBorder.color, lineWidth: 1).allowsHitTesting(false))
                .warmShadow(.brassButton, in: Capsule())
        } else {
            content
        }
    }
}

private struct SelectedChipLight: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .overlay(Capsule().strokeBorder(MotionSpec.activeChipBorder.color, lineWidth: 1).allowsHitTesting(false))
                .warmShadow(.activeChip, in: Capsule())
        } else {
            content
        }
    }
}

private struct SelectedChipIconPulse: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active { content.pulse() } else { content }
    }
}

private struct LuminousToastLight: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .overlay(Capsule().strokeBorder(MotionSpec.toastBorder.color, lineWidth: 1).allowsHitTesting(false))
                .warmShadow(.toast, in: Capsule())
        } else {
            content
        }
    }
}

/// Título de sección del marco: icono + `headline-sm` `primary` + rótulo a la derecha.
struct SectionHeader: View {
    let title: String
    var systemImage: String?
    var trailing: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .textRole(.headlineSM)
                .foregroundStyle(Theme.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.sm)
            if let trailing {
                if let trailingAction {
                    Button(action: trailingAction) {
                        Text(trailing).textRole(.labelSM).foregroundStyle(Theme.secondary)
                    }
                } else {
                    Text(trailing).textRole(.labelSM).foregroundStyle(Theme.onSurfaceVariant)
                }
            }
        }
    }
}
