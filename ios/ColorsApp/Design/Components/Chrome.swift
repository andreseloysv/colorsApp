// Cabecera de marca, barra de pestañas y barra de progreso de historias
// (docs/design/DESIGN_SYSTEM.md §4 n.º 1, 2 y 30; §3.6 iconos). Sin criaturas ni
// logotipos ilustrados: sol, gota, rejilla y brote de SF Symbols.
import SwiftUI
import UIKit

// MARK: - Cabecera

/// Cabecera de las pestañas raíz (§4 n.º 1): 64 pt, pergamino esmerilado, marca
/// `AppBrand.name` con el sol, rótulo de sección y, a la derecha, el botón de sol y el
/// avatar local (el jardín del teléfono: sin cuentas ni fotos de perfil).
/// Uso: `.safeAreaInset(edge: .top, spacing: 0) { AppHeader(section: "Feed") }`.
struct AppHeader: View {
    /// Rótulo de sección en mayúsculas («FEED», «EXTRAER»…); nil lo oculta.
    let section: String?
    /// Símbolo del botón contextual de la derecha (por defecto el sol).
    var sunSymbol: String = "sun.max"
    var sunAccessibilityLabel: String = "Acción"
    /// Acción del botón de sol; nil = no se muestra.
    var sunAction: (() -> Void)?
    /// Acción del avatar local (p. ej. abrir el Jardín); nil = no se muestra.
    var avatarAction: (() -> Void)?
    var avatarAccessibilityLabel: String = "Tu jardín"

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: Spacing.sm) {
            BrandMark()
            VStack(alignment: .leading, spacing: 1) {
                Text(AppBrand.name)
                    .textRole(.brand)
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                if let section, !dynamicTypeSize.isAccessibilitySize {
                    Text(section)
                        .textRole(.overline)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.sm)
            if let sunAction {
                Button(action: sunAction) {
                    ZStack {
                        Circle().fill(ThemeTokens.amberBadge.color).frame(width: 34, height: 34)
                        Image(systemName: sunSymbol)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(ThemeTokens.onAmberBadge.color)
                    }
                    .frame(width: Sizes.headerButton, height: Sizes.headerButton)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.solarPress)
                .accessibilityLabel(sunAccessibilityLabel)
            }
            if let avatarAction {
                Button(action: avatarAction) {
                    LocalAvatar(size: Sizes.avatar)
                        .frame(width: Sizes.headerButton, height: Sizes.headerButton)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.solarPress)
                .accessibilityLabel(avatarAccessibilityLabel)
            }
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: Sizes.header)
        .frame(maxWidth: .infinity)
        // La cabecera crece con Dynamic Type hasta AX1 (como una barra de navegación).
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background {
            ZStack(alignment: .bottom) {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Theme.frostTint)
                Rectangle().fill(Theme.brassHairline).frame(height: 1 / max(displayScale, 1))
            }
            .ignoresSafeArea(edges: .top)
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
        }
    }
}

/// Marca: sol relleno `secondary` en un cuadrado de 32 pt `secondaryFixed` (radio 8).
struct BrandMark: View {
    var size: CGFloat = Sizes.brandMark

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
            .fill(ThemeTokens.amberBadge.color)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: AppBrand.symbol)
                    .font(.system(size: size * 0.56, weight: .semibold))
                    .foregroundStyle(Color(light: 0xD97724, dark: 0xFFB785))
            }
            .accessibilityHidden(true)
    }
}

/// Avatar local: brote en círculo musgo con aro ámbar (sin foto ni nombre de persona).
struct LocalAvatar: View {
    var size: CGFloat = Sizes.avatar

    var body: some View {
        Circle()
            .fill(Tone.moss.badgeFill)
            .overlay {
                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(Tone.moss.onBadge)
            }
            .padding(2)
            .background(Circle().fill(Tone.amber.badgeFill))
            .frame(width: size + 4, height: size + 4)
            .accessibilityHidden(true)
    }
}

// MARK: - Barra de pestañas

/// Una pestaña de `SolarTabBar`.
struct SolarTabItem<Tag: Hashable>: Identifiable {
    let tag: Tag
    let title: String
    let systemImage: String
    let selectedSystemImage: String
    var badge: String?
    var accessibilityIdentifier: String?

    var id: Tag { tag }
}

/// Las cuatro pestañas de la app (§6.2) con sus símbolos (§3.6).
enum SolarTabs {
    static let feedTitle = "Feed"
    static let extraerTitle = "Extraer"
    static let rejillaTitle = "Rejilla"
    static let jardinTitle = "Jardín"

    static let feedSymbol = "sun.max"
    static let extraerSymbol = "drop.halffull"
    static let rejillaSymbol = "square.grid.2x2"
    static let jardinSymbol = "leaf"

    static func standard<Tag: Hashable>(feed: Tag, extraer: Tag, rejilla: Tag, jardin: Tag) -> [SolarTabItem<Tag>] {
        [
            SolarTabItem(tag: feed, title: feedTitle, systemImage: feedSymbol, selectedSystemImage: "sun.max.fill",
                         accessibilityIdentifier: "tab.feed"),
            SolarTabItem(tag: extraer, title: extraerTitle, systemImage: extraerSymbol, selectedSystemImage: "drop.halffull",
                         accessibilityIdentifier: "tab.extraer"),
            SolarTabItem(tag: rejilla, title: rejillaTitle, systemImage: rejillaSymbol, selectedSystemImage: "square.grid.2x2.fill",
                         accessibilityIdentifier: "tab.rejilla"),
            SolarTabItem(tag: jardin, title: jardinTitle, systemImage: jardinSymbol, selectedSystemImage: "leaf.fill",
                         accessibilityIdentifier: "tab.jardin"),
        ]
    }
}

/// Barra de pestañas propia (§4 n.º 2) con pergamino esmerilado, filo de latón y la
/// pestaña activa en musgo sobre una píldora. Para la `TabView` del sistema en iOS 17–25
/// usar `SolarTabBarAppearance.apply()`; en iOS 26+ la barra del sistema es Liquid Glass
/// y basta con `.tint(Theme.primary)`.
struct SolarTabBar<Tag: Hashable>: View {
    let items: [SolarTabItem<Tag>]
    @Binding var selection: Tag

    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let selected = item.tag == selection
                Button {
                    selection = item.tag
                } label: {
                    VStack(spacing: 2) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: selected ? item.selectedSystemImage : item.systemImage)
                                .font(.system(size: 20, weight: selected ? .semibold : .regular))
                                .frame(width: 52, height: 28)
                                .background {
                                    if selected { Capsule().fill(Tone.moss.badgeFill.opacity(0.55)) }
                                }
                            if let badge = item.badge {
                                Text(badge)
                                    .textRole(.labelSM)
                                    .foregroundStyle(Theme.onSecondary)
                                    .padding(.horizontal, 4)
                                    .background(Capsule().fill(Theme.secondary))
                                    .offset(x: 4, y: -4)
                            }
                        }
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text(item.title)
                                .textRole(.labelSM, weight: selected ? .bold : .semibold)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(selected ? Theme.primary : Theme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .frame(height: Sizes.tabBar)
        .background {
            ZStack(alignment: .top) {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Theme.frostTint)
                Rectangle().fill(Theme.brassHairline).frame(height: 1 / max(displayScale, 1))
            }
            .ignoresSafeArea(edges: .bottom)
            .shadow(color: Theme.sepia.opacity(0.05), radius: 6, x: 0, y: -2)
        }
    }
}

/// Apariencia de la `UITabBar` del sistema en iOS 17–25 (pergamino esmerilado + Plus Jakarta Sans).
enum SolarTabBarAppearance {
    @MainActor
    static func apply() {
        if #available(iOS 26, *) { return }
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor(light: 0xF9F6EE, dark: 0x15130E, lightOpacity: 0.78, darkOpacity: 0.78)
        appearance.shadowColor = UIColor(rgbHex: 0xC29B38, alpha: 0.15)
        let font = Typography.uiFont(.labelSM)
        let normal = UIColor(light: ThemeTokens.onSurfaceVariant.light, dark: ThemeTokens.onSurfaceVariant.dark)
        let selected = UIColor(light: ThemeTokens.primary.light, dark: ThemeTokens.primary.dark)
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            layout.normal.iconColor = normal
            layout.normal.titleTextAttributes = [.font: font, .foregroundColor: normal]
            layout.selected.iconColor = selected
            layout.selected.titleTextAttributes = [.font: font, .foregroundColor: selected]
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Historias

/// Segmentos de progreso del visor de capas (§4 n.º 30): uno por capa, sobre el fondo
/// neutro `storyBackdrop` (blanco sobre gris, sin tintes cálidos).
struct StoryProgressBar: View {
    let count: Int
    /// Índice 0-based de la capa actual.
    let current: Int
    /// Progreso de la capa actual (0…1). Sin avance automático: 1 por defecto.
    var progress: Double = 1
    var onSelect: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<max(count, 0), id: \.self) { i in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.32))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * fill(for: i))
                    }
                }
                .frame(height: 3)
                .contentShape(Rectangle().inset(by: -8))
                .onTapGesture { onSelect?(i) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Capa \(min(current + 1, count)) de \(count)")
    }

    private func fill(for index: Int) -> CGFloat {
        if index < current { return 1 }
        if index == current { return CGFloat(min(max(progress, 0), 1)) }
        return 0
    }
}
