// Pestaña Rejilla (docs/design/DESIGN_SYSTEM.md §5.3; captura «la_rejilla» del ejemplo del
// usuario). Fusiona la antigua Rejilla y Explorar:
//   · cabecera con logotipo y wordmark ChromaSol, sol con destello (otra combinación al azar) y
//     avatar con anillo (Jardín) — `RejillaHeader`
//   · buscador fijo esmerilado por nombre, número o #hex (color de Wada más cercano según el motor)
//     y hoja «Buscar por color» (ColorPicker)
//   · tarjeta «Al azar» con reloj de sol, orbes, puntos de luz, fichas que se barajan y «Otra»
//     luminoso — `RejillaRandomCard` (FIDELITY.md §5)
//   · chips de tamaño (2/3/4) y estado (desbloqueadas/bloqueadas) con «12 de 120 desbloqueadas»
//   · cuadrícula de 2 columnas (1 con tamaños de accesibilidad) de las 348 combinaciones con
//     sus franjas en pocillo neutro, nombre curado o propuesto (marcado), número y estado
//   · detalle en hoja (`RejillaComboDetailView`) y «Guardar» en el Jardín (`GardenStore`)
// Datos reales: desbloqueos y análisis de la base de datos; los de ejemplo solo en DEBUG con
// `-uiScreen rejilla-demo` (ver RejillaLaunch.swift), en memoria y con insignia.
import SwiftUI

struct GridView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var model = RejillaModel()
    @ObservedObject private var garden: GardenStore
    @ObservedObject private var requests = RejillaRequests.shared
    @State private var demoEnv: AppEnvironment?
    @State private var detail: ComboRoute?
    @State private var showColorSearch = false
    @State private var randomId: Int
    @State private var launchApplied = false
    @State private var detailDetent: PresentationDetent = .medium
    /// Sube hasta la tarjeta «Al azar» cada vez que cambia.
    @State private var scrollToTop = 0
    /// Recuento de desbloqueadas ya vistas en el Jardín (insignia «✦» del avatar); −1 = nunca.
    @AppStorage(RejillaAvatarBadge.lastSeenKey) private var lastSeenUnlocks = -1
    @Environment(\.selectTab) private var selectTab
    private let options: RejillaLaunchOptions

    /// Ruta a una combinación (hoja de detalle).
    struct ComboRoute: Identifiable, Hashable {
        let id: Int
    }

    init() {
        let options = RejillaLaunchOptions.current
        self.options = options
        #if DEBUG
        _garden = ObservedObject(wrappedValue: options.demo ? RejillaDemo.makeGarden() : GardenStore.shared)
        _randomId = State(initialValue: options.demo ? RejillaDemo.randomComboId : RejillaRandom.next(after: nil, total: WadaDictionary.expectedComboCount))
        #else
        _garden = ObservedObject(wrappedValue: GardenStore.shared)
        _randomId = State(initialValue: RejillaRandom.next(after: nil, total: WadaDictionary.expectedComboCount))
        #endif
    }

    /// Entorno activo: el de ejemplo (DEBUG) o el real.
    private var source: AppEnvironment { demoEnv ?? env }

    var body: some View {
        NavigationStack {
            RejillaContentView(model: model, dictionary: env.dictionary, naming: .bundled,
                               randomId: randomId, savedComboIds: garden.savedComboIds,
                               isDemo: demoEnv != nil, scrollTo: options.scrollTo, scrollToTop: scrollToTop,
                               onSelect: { detail = ComboRoute(id: $0.id) },
                               onShuffle: { shuffle() },
                               onToggleSave: { garden.toggle(comboId: $0) },
                               onColorSearch: { showColorSearch = true })
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) { header }
                .background(Theme.surface.ignoresSafeArea())
        }
        .sheet(item: $detail) { route in
            detailSheet(route.id)
        }
        .sheet(isPresented: $showColorSearch) {
            ColorSearchView(onShowInGrid: { hex in
                model.searchText = hex
                model.statusFilter = nil
                showColorSearch = false
            }, onClose: { showColorSearch = false })
            .environmentObject(source)
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(Radius.sheet)
            .presentationBackground(Theme.containerLow)
            .presentationDragIndicator(.visible)
        }
        .modifier(RejillaMotionDebug(options: options))
        .task { await start() }
        .onAppear(perform: applyRequest)
        .onChange(of: requests.pending) { _, _ in applyRequest() }
    }

    /// Petición de otra pestaña (`RejillaRequests`): filtros, búsqueda o detalle.
    private func applyRequest() {
        guard let request = requests.consume() else { return }
        model.sizeFilter = request.size
        model.statusFilter = request.status
        model.searchText = request.search ?? ""
        if let id = request.comboId, env.dictionary.combo(id: id) != nil {
            detail = ComboRoute(id: id)
        }
    }

    // MARK: Cabecera

    private var header: some View {
        RejillaHeader(section: demoEnv == nil ? SolarTabs.rejillaTitle : "\(SolarTabs.rejillaTitle) · ejemplo",
                      onSun: sunTapped,
                      onAvatar: openGarden,
                      newUnlocks: RejillaAvatarBadge.newUnlocks(unlocked: model.unlockedCount,
                                                                lastSeen: lastSeenUnlocks < 0 ? nil : lastSeenUnlocks))
    }

    /// Sol: otra combinación al azar. Sin búsqueda, sube hasta la tarjeta y baraja; con búsqueda
    /// (la tarjeta está oculta), abre directamente el detalle de la combinación elegida.
    private func sunTapped() {
        shuffle()
        if case .empty = model.query(total: env.dictionary.combinations.count) {
            scrollToTop += 1
        } else {
            detail = ComboRoute(id: randomId)
        }
    }

    /// Avatar: Jardín. Marca como vistas las desbloqueadas (la insignia se apaga); nunca con datos de ejemplo.
    private func openGarden() {
        if demoEnv == nil { lastSeenUnlocks = model.unlockedCount }
        selectTab(.jardin)
    }

    // MARK: Hojas

    private func detailSheet(_ id: Int) -> some View {
        Group {
            if let combo = env.dictionary.combo(id: id) {
                RejillaComboDetailView(combo: combo, naming: .bundled, garden: garden,
                                       onSearchColor: { color in
                                           model.searchText = PaletteColor(id: color.index, wada: color).hex
                                           model.statusFilter = nil
                                           detail = nil
                                       },
                                       onClose: { detail = nil })
            } else {
                Text("No existe la combinación \(id)")
                    .textRole(.bodyMD)
                    .foregroundStyle(Theme.onSurfaceVariant)
            }
        }
        .environmentObject(source)
        .presentationDetents([.medium, .large], selection: $detailDetent)
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(Theme.containerLow)
        .presentationDragIndicator(.visible)
        .onDisappear { detailDetent = .medium }
    }

    /// La tarjeta anima el cambio (fichas, sol y respiración): aquí se cambia sin transacción.
    private func shuffle() {
        randomId = RejillaRandom.next(after: randomId, total: env.dictionary.combinations.count)
    }

    // MARK: Arranque

    private func start() async {
        #if DEBUG
        if options.demo {
            if demoEnv == nil {
                do {
                    let demo = try RejillaDemo.makeEnvironment(dictionary: env.dictionary)
                    try await RejillaDemo.seed(demo)
                    demoEnv = demo
                } catch {
                    // Sin datos de ejemplo: se queda con la base de datos real.
                }
            }
            // Los atajos se aplican con los datos de ejemplo ya sembrados (la hoja lee el entorno activo).
            applyLaunchOptions()
            await model.observe(source.unlocks)
            return
        }
        #endif
        applyLaunchOptions()
        await model.observe(env.unlocks)
    }

    #if DEBUG
    /// `-uiRejillaAutoShuffle <s>`: baraja una vez tras `s` segundos (capturas del barajado).
    private func scheduleAutoShuffle() {
        guard let delay = options.autoShuffleAfter else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { shuffle() }
    }
    #endif

    private func applyLaunchOptions() {
        guard !launchApplied else { return }
        launchApplied = true
        #if DEBUG
        scheduleAutoShuffle()
        #endif
        if let search = options.search { model.searchText = search }
        if let size = options.size { model.sizeFilter = size }
        if let status = options.status { model.statusFilter = status }
        if options.colorSearch {
            showColorSearch = true
        } else if let id = options.detailId, detail == nil {
            if options.detailLarge { detailDetent = .large }
            detail = ComboRoute(id: id)
        }
    }
}

/// Contenido desplazable de la Rejilla, sin NavigationStack ni cabecera (capturas y tests).
struct RejillaContentView: View {
    @ObservedObject var model: RejillaModel
    let dictionary: WadaDictionary
    var naming: ComboNaming = .bundled
    /// Combinación de la tarjeta «Al azar»; nil la oculta.
    var randomId: Int? = nil
    var savedComboIds: Set<Int> = []
    var isDemo: Bool = false
    var scrollTo: Int? = nil
    /// Cada cambio sube hasta el principio (sol de la cabecera).
    var scrollToTop: Int = 0
    var onSelect: ((WadaCombo) -> Void)? = nil
    var onShuffle: (() -> Void)? = nil
    var onToggleSave: ((Int) -> Void)? = nil
    var onColorSearch: (() -> Void)? = nil

    @State private var cache = RejillaIndexCache()
    private static let topAnchor = "rejilla.top"
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let total = dictionary.combinations.count
        let query = model.query(total: total)
        let results = RejillaSearch.filter(model.combos(in: dictionary), query: query,
                                           index: cache.index(dictionary: dictionary, naming: naming))
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.sm,
                           pinnedViews: dynamicTypeSize.isAccessibilitySize ? [] : [.sectionHeaders]) {
                    Section {
                        if let randomId, case .empty = query {
                            randomCard(randomId)
                                .padding(.top, 2)
                        }
                        RejillaFilterBar(size: $model.sizeFilter, status: $model.statusFilter)
                            .padding(.horizontal, -Spacing.margin)
                            .padding(.vertical, -Spacing.xs)
                        RejillaProgressRow(text: progressText(query, resultCount: results.count),
                                           value: model.unlockedCount(in: dictionary),
                                           total: model.sizeScope(in: dictionary).count)
                            .overlay(alignment: .topTrailing) {
                                if isDemo {
                                    SolarBadge(title: "Datos de ejemplo", systemImage: "testtube.2",
                                               fill: Tone.amber.badgeFill, foreground: Tone.amber.onBadge)
                                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                                        .offset(y: -3)
                                        .accessibilityIdentifier("rejilla.demo")
                                }
                            }
                            .padding(.bottom, 2)
                        if results.isEmpty {
                            emptyState(query)
                        } else {
                            grid(results)
                        }
                    } header: {
                        searchHeader(query, resultCount: results.count)
                    }
                }
                .padding(.horizontal, Spacing.margin)
                .padding(.bottom, Spacing.xl)
                .id(Self.topAnchor)
            }
            .scrollDismissesKeyboard(.interactively)
            .modifier(ScrollToTileOnAppear(id: scrollTo, proxy: proxy))
            .onChange(of: scrollToTop) { _, _ in
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45)) {
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                }
            }
        }
        .background(Theme.surface)
        .accessibilityIdentifier("rejilla.grid")
    }

    // MARK: Buscador fijo

    private func searchHeader(_ query: RejillaSearch.Query, resultCount: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            RejillaSearchField(placeholder: "Busca por nombre, número o #hex", text: $model.searchText,
                               onSubmit: { submit(query) }, onFilter: onColorSearch)
                .accessibilityIdentifier("rejilla.search")
            interpretation(query, resultCount: resultCount)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.horizontal, Spacing.margin)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        // `bg-surface/90 backdrop-blur-md`: pergamino al 90 % sobre el material; lo que pasa por
        // debajo apenas se intuye (no es zona de juicio de color).
        .background { RejillaStickyBarBackground() }
        .padding(.horizontal, -Spacing.margin)
    }

    /// «20 de 348 desbloqueadas», con el número de resultados delante si hay búsqueda.
    private func progressText(_ query: RejillaSearch.Query, resultCount: Int) -> String {
        let base = model.progressText(in: dictionary)
        if case .empty = query { return base }
        return "\(resultCount == 1 ? "1 resultado" : "\(resultCount) resultados") · \(base)"
    }

    @ViewBuilder
    private func interpretation(_ query: RejillaSearch.Query, resultCount: Int) -> some View {
        switch query {
        case .empty:
            EmptyView()
        case .number(let id):
            SolarBadge(title: "\(WadaDictionary.numberLabel(id)) · Intro abre el detalle", systemImage: "number",
                       fill: Theme.containerHigh, foreground: Theme.onSurfaceVariant)
        case .numberOutOfRange(let n):
            SolarBadge(title: "No existe la Nº \(n): hay \(dictionary.combinations.count)", systemImage: "exclamationmark.circle",
                       fill: Theme.containerHigh, foreground: Theme.onSurfaceVariant)
        case .color(let match):
            NearestColorChip(match: match, wada: dictionary.color(index: match.index), resultCount: resultCount)
        case .text:
            EmptyView()
        }
    }

    private func submit(_ query: RejillaSearch.Query) {
        if case .number(let id) = query, let combo = dictionary.combo(id: id) {
            onSelect?(combo)
        }
    }

    // MARK: Al azar

    private func randomCard(_ id: Int) -> some View {
        let name = naming.name(for: id, in: dictionary)
        return RejillaRandomCard(comboId: id, name: name.text, colors: PaletteColor.combo(id, in: dictionary),
                                 isUnlocked: model.isUnlocked(id), isProposedName: name.isProposed,
                                 total: dictionary.combinations.count,
                                 onShuffle: { onShuffle?() },
                                 onOpen: dictionary.combo(id: id).map { combo in { onSelect?(combo) } })
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rejilla.random")
    }

    // MARK: Cuadrícula

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Spacing.gutter, alignment: .top), count: count)
    }

    private func grid(_ combos: [WadaCombo]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.gutter) {
            ForEach(combos) { combo in
                ComboGridCard(comboId: combo.id,
                              name: naming.name(for: combo.id, in: dictionary),
                              colors: PaletteColor.combo(combo.id, in: dictionary),
                              state: state(for: combo.id),
                              isSaved: savedComboIds.contains(combo.id),
                              onOpen: { onSelect?(combo) },
                              onToggleSave: onToggleSave.map { toggle in { toggle(combo.id) } })
                    .id("tile-\(combo.id)")
                    .accessibilityIdentifier("rejilla.tile.\(combo.id)")
            }
        }
    }

    private func state(for id: Int) -> ComboGridCard.State {
        guard let unlock = model.unlock(for: id) else { return .locked }
        return .unlocked(since: RejillaDateText.short(unlock.firstSeenAt))
    }

    // MARK: Sin resultados

    private func emptyState(_ query: RejillaSearch.Query) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
            Text(emptyTitle(query))
                .textRole(.headlineSM)
                .foregroundStyle(Theme.primary)
                .multilineTextAlignment(.center)
            Text("Prueba con un número del 1 al \(dictionary.combinations.count), un #hex o el nombre de un color («Black», «Pink»).")
                .textRole(.bodyMD)
                .foregroundStyle(Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
            HStack(spacing: Spacing.sm) {
                if let onColorSearch {
                    SolarSecondaryButton(title: "Buscar por color", systemImage: "eyedropper.halffull", action: onColorSearch)
                }
                SolarSecondaryButton(title: "Quitar filtros", systemImage: "xmark") { model.clearFilters() }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .solarCard(fill: Theme.container, elevation: .flat)
        .accessibilityIdentifier("rejilla.empty")
    }

    private func emptyTitle(_ query: RejillaSearch.Query) -> String {
        switch query {
        case .empty: "Ninguna combinación con estos filtros"
        case .numberOutOfRange(let n): "No hay combinación Nº \(n)"
        case .text, .number, .color: "Sin resultados para «\(model.searchText.trimmingCharacters(in: .whitespacesAndNewlines))»"
        }
    }
}

/// Desplaza hasta una tarjeta al aparecer (atajo de capturas). Sin id no añade ningún
/// modificador de ciclo de vida (ImageRenderer y tests).
private struct ScrollToTileOnAppear: ViewModifier {
    let id: Int?
    let proxy: ScrollViewProxy

    func body(content: Content) -> some View {
        if let id {
            content.onAppear {
                // Dos intentos: la cuadrícula perezosa puede no haber medido aún sus filas.
                for delay in [0.4, 1.2] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        proxy.scrollTo("tile-\(id)", anchor: .top)
                    }
                }
            }
        } else {
            content
        }
    }
}

/// Índice de búsqueda construido una vez por diccionario y nombres (no se observa).
final class RejillaIndexCache {
    private var key: String?
    private var cached: RejillaSearch.Index?

    func index(dictionary: WadaDictionary, naming: ComboNaming) -> RejillaSearch.Index {
        let k = "\(dictionary.dictVersion)|\(dictionary.names.count)|\(naming.proposed.count)"
        if let cached, key == k { return cached }
        let built = RejillaSearch.Index(dictionary: dictionary, naming: naming)
        cached = built
        key = k
        return built
    }
}

/// Chip del buscador con un #hex: color escrito → color de Wada más cercano (motor) y ΔE00.
/// Todo en un pocillo neutro (`wellFillAlt` + filo), sin tintes cálidos junto a los colores.
struct NearestColorChip: View {
    let match: ColorSearch.Match
    let wada: WadaColor?
    var resultCount: Int

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 6) {
            SwatchBead(color: Color(rgb8: match.r, match.g, match.b), size: 18, ring: 2)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.wellTextSecondary)
                .accessibilityHidden(true)
            if let wada {
                SwatchBead(color: Color(wada: wada), size: 18, ring: 2)
                Text("Color más cercano: \(wada.name) · \(DesignFormat.deltaE(match.deltaE))")
                    .textRole(.labelSM)
                    .foregroundStyle(Theme.wellText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, Spacing.sm)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.wellFillAlt))
        .overlay(Capsule().strokeBorder(Theme.wellEdge, lineWidth: 1 / max(displayScale, 1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(wada.map { "Color más cercano: \($0.name), \(DesignFormat.deltaE(match.deltaE)), \(resultCount) combinaciones" } ?? "")
        .accessibilityIdentifier("rejilla.search.color")
    }
}
