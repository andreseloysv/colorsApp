// Navegación raíz (docs/design/DESIGN_SYSTEM.md §6.2; luces y personajes en
// docs/design/FIDELITY.md §2.3 y §3 F45–F50): cuatro pestañas, Feed · Extraer · Rejilla ·
// Jardín, con la barra propia `RootTabBar`: pergamino esmerilado al 90 % y, en cada pestaña,
// su personaje ORIGINAL animado de la marca (semilla solar, libélula, gotita de rocío y brote
// en maceta: `BrandTabIcon`) con el halo verde de la activa. Con el Feed a la vista la barra
// lleva la variante luminosa del ejemplo (sombra ámbar `0 -3px 16px` y filo ámbar al 15 %);
// en el resto, la sombra sepia `0 -2px 12px` al 5 %. Cada pestaña vive en su fichero y la
// escribe su equipo: FeedView (Views/Feed), ExtractView, GridView y GardenView. Una
// pestaña se crea la primera vez que se abre y se conserva viva (su NavigationStack y su
// desplazamiento no se pierden al cambiar de pestaña); las ocultas pausan su movimiento
// ambiental con `.ambientMotion(false)` (quedan con opacidad 0 y no reciben `onDisappear`).
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case feed, extraer, rejilla, jardin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: SolarTabs.feedTitle
        case .extraer: SolarTabs.extraerTitle
        case .rejilla: SolarTabs.rejillaTitle
        case .jardin: SolarTabs.jardinTitle
        }
    }

    var systemImage: String {
        switch self {
        case .feed: SolarTabs.feedSymbol
        case .extraer: SolarTabs.extraerSymbol
        case .rejilla: SolarTabs.rejillaSymbol
        case .jardin: SolarTabs.jardinSymbol
        }
    }

    /// Personaje de la marca que dibuja el icono de la pestaña.
    var brandKind: BrandTabIconKind {
        switch self {
        case .feed: .feed
        case .extraer: .extraer
        case .rejilla: .rejilla
        case .jardin: .jardin
        }
    }
}

/// Acción para cambiar de pestaña desde una vista hija (p. ej. «Analizar una foto» del Feed
/// abre Extraer; «Ver rejilla» del escaneo abre la Rejilla).
struct SelectTabAction {
    let action: @MainActor (AppTab) -> Void

    @MainActor
    func callAsFunction(_ tab: AppTab) { action(tab) }
}

private struct SelectTabKey: EnvironmentKey {
    static var defaultValue: SelectTabAction { SelectTabAction(action: { _ in }) }
}

private struct ActiveRootTabKey: EnvironmentKey {
    static let defaultValue: AppTab? = nil
}

extension EnvironmentValues {
    var selectTab: SelectTabAction {
        get { self[SelectTabKey.self] }
        set { self[SelectTabKey.self] = newValue }
    }

    /// Pestaña visible de `RootTabContainer` (nil fuera de él): p. ej. el Feed marca como vistas
    /// las combinaciones nuevas cuando se visita el Jardín.
    var activeRootTab: AppTab? {
        get { self[ActiveRootTabKey.self] }
        set { self[ActiveRootTabKey.self] = newValue }
    }
}

struct RootTabView: View {
    #if DEBUG
    @EnvironmentObject private var env: AppEnvironment
    #endif

    var body: some View {
        #if DEBUG
        switch DebugLaunch.requested {
        case .feedDemo:
            FeedDemoRoot(base: env, seeded: true)
        case .feedEmpty:
            FeedDemoRoot(base: env, seeded: false)
        default:
            RootTabContainer()
        }
        #else
        RootTabContainer()
        #endif
    }
}

/// Contenedor de las cuatro pestañas con la barra `RootTabBar` abajo.
struct RootTabContainer: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var selection: AppTab
    /// Pestañas ya abiertas (se crean al primer uso y se mantienen).
    @State private var opened: Set<AppTab>
    private let feedView: @MainActor () -> FeedView

    init(initialTab: AppTab = DebugLaunch.initialTab, feed: @escaping @MainActor () -> FeedView = { FeedView() }) {
        _selection = State(initialValue: initialTab)
        _opened = State(initialValue: [initialTab])
        feedView = feed
    }

    var body: some View {
        // La barra va DEBAJO del contenido (VStack) y no como `safeAreaInset`: el margen de un
        // `safeAreaInset` antepasado no llega a las listas dentro de un NavigationStack (medido:
        // el ScrollView del Feed veía 34 pt abajo, no 98) y la última publicación quedaba tapada.
        VStack(spacing: 0) {
            ZStack {
                ForEach(AppTab.allCases) { tab in
                    if opened.contains(tab) {
                        content(for: tab)
                            // Una pestaña oculta sigue viva con opacidad 0: sus relojes ambientales se pausan.
                            .ambientMotion(selection == tab)
                            .opacity(selection == tab ? 1 : 0)
                            .allowsHitTesting(selection == tab)
                            .accessibilityHidden(selection != tab)
                            .zIndex(selection == tab ? 1 : 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            RootTabBar(items: tabItems, selection: tabBinding, style: selection == .feed ? .luminous : .standard)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(Theme.surface.ignoresSafeArea())
        .tint(Theme.primary)
        .accessibilityIdentifier("root.tabs")
        .environment(\.selectTab, SelectTabAction(action: { tab in select(tab) }))
        .environment(\.activeRootTab, selection)
        .modifier(RootMotionDebugOverrides())
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .feed: feedView()
        case .extraer: ExtractView()
        case .rejilla: GridView()
        case .jardin: GardenView()
        }
    }

    private var tabBinding: Binding<AppTab> {
        Binding(get: { selection }, set: { select($0) })
    }

    private func select(_ tab: AppTab) {
        opened.insert(tab)
        selection = tab
    }

    /// Pestañas estándar; mientras se escanea el carrete, Extraer lleva el número de fotos analizadas.
    private var tabItems: [SolarTabItem<AppTab>] {
        var items = SolarTabs.standard(feed: AppTab.feed, extraer: .extraer, rejilla: .rejilla, jardin: .jardin)
        if let badge = Self.scanBadge(env.scanProgress), let i = items.firstIndex(where: { $0.tag == .extraer }) {
            items[i].badge = badge
        }
        return items
    }

    /// Insignia de Extraer durante el escaneo del carrete: fotos analizadas («37»); nil fuera de él.
    nonisolated static func scanBadge(_ progress: ScanProgress) -> String? {
        switch progress.phase {
        case .analyzing: "\(progress.processed)"
        case .requestingAccess, .fetching: "…"
        case .idle, .finished, .failed: nil
        }
    }
}

// MARK: - Barra de pestañas

/// Barra de pestañas de la app (F45–F50): `h-16 px-gutter justify-around`, elementos de
/// 64 × 48 pt (`w-16 h-12 gap-0.5`) con el personaje de la marca (24 pt de viewBox dibujado a
/// 28 pt) y la etiqueta `label-sm`. Solo la pestaña activa se anima (bote y parpadeo, aleteo,
/// balanceo o vaivén con los tiempos del ejemplo) y lleva el halo verde que late; las demás
/// quedan quietas en su pose de reposo (sin reloj). Pulsación 0,95.
struct RootTabBar: View {
    enum Style: Sendable, Equatable {
        /// Feed: sombra ámbar `0 -3px 16px rgba(234,179,8,0.12)` y filo superior ámbar al 15 %.
        case luminous
        /// Extraer, Rejilla y Jardín: `shadow-[0_-2px_12px_rgba(68,48,28,0.05)]`, sin filo.
        case standard

        var bar: MotionSpec.FrostedBar {
            switch self {
            case .luminous: MotionSpec.tabBar
            case .standard: MotionSpec.FrostedBar(tintOpacity: 0.9, shadow: ShadowSpec(TailwindColor.sepia.opacity(0.05), blur: 12, y: -2),
                                                  hairline: TailwindColor.sepia.opacity(0))
            }
        }
    }

    let items: [SolarTabItem<AppTab>]
    @Binding var selection: AppTab
    var style: Style = .luminous

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let selected = item.tag == selection
                Button {
                    selection = item.tag
                } label: {
                    label(for: item, selected: selected)
                }
                .buttonStyle(.pressScale)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(item.badge.map { "\(item.title), \($0)" } ?? item.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .frame(height: Sizes.tabBar)
        .background { FrostedBarBackground(spec: style.bar, hairlineEdge: .top) }
    }

    private func label(for item: SolarTabItem<AppTab>, selected: Bool) -> some View {
        VStack(spacing: 2) {
            BrandTabIcon(kind: item.tag.brandKind, isActive: selected)
                .overlay(alignment: .topTrailing) {
                    if let badge = item.badge {
                        Text(badge)
                            .textRole(.labelSM)
                            .monospacedDigit()
                            .foregroundStyle(Theme.onSecondary)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(Theme.secondary))
                            .fixedSize()
                            .offset(x: 10, y: -3)
                    }
                }
            if !dynamicTypeSize.isAccessibilitySize {
                Text(item.title)
                    .textRole(.labelSM, weight: selected ? .bold : .medium)
                    .foregroundStyle(selected ? Theme.primary : Theme.onSurfaceVariant)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(width: 64, height: 48)
        .contentShape(Rectangle())
    }
}

// MARK: - Capturas deterministas (solo DEBUG)

/// `-uiMotionTime <s>` congela todo el movimiento de la app (efectos ambientales y personajes
/// de la marca) en ese instante; `-uiReduceMotion 1` fuerza «Reducir movimiento». Mismos
/// argumentos que la galería de movimiento. Sin argumentos no cambia nada.
struct RootMotionDebugOverrides: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        let options = Self.parse(ProcessInfo.processInfo.arguments)
        content
            .motionTime(options.time)
            .environment(\.brandFrozenTime, options.time)
            .forceReducedMotion(options.reduceMotion)
            .environment(\.brandReduceMotionOverride, options.reduceMotion ? true : nil)
        #else
        content
        #endif
    }

    nonisolated static func parse(_ args: [String]) -> (time: Double?, reduceMotion: Bool) {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        return (value("-uiMotionTime").flatMap(Double.init), value("-uiReduceMotion") == "1")
    }
}
