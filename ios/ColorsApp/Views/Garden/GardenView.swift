// Pestaña Jardín (docs/design/DESIGN_SYSTEM.md §5.4; fidelidad a my_garden_vault según
// docs/design/FIDELITY.md §6): cabecera con el logotipo, sol con destello y avatar local;
// perfil local sin cuenta con retrato animado, luciérnagas, acierto con punto que late y
// contadores reales; segmentos Fotos · Guardadas · Colecciones; colecciones por tamaño y
// guardadas; cosechas (scans con su paleta en pocillo neutro, combinación, fecha y origen)
// en las tres tarjetas del ejemplo; y estudio de exportación con acciones reales (tarjeta,
// hex de la última cosecha, diagnóstico y escaneo del carrete). El engranaje empuja
// Ajustes. Sin retratos, perfiles ajenos ni contadores sociales (§0.2 B).
// DEBUG: `-uiScreen jardin-demo` (o `-uiScreen jardin -uiGardenDemo 1`) siembra datos de
// EJEMPLO en una base de datos en memoria (GardenDemo.swift).
import SwiftUI
import UIKit

struct GardenView: View {
    @EnvironmentObject private var env: AppEnvironment
    /// Abre la Rejilla con el tamaño 2, 3 o 4 como filtro (nil = todas). nil = `RejillaRequests` + `selectTab(.rejilla)`.
    var onOpenGrid: ((Int?) -> Void)?
    /// Abre el detalle de una combinación. nil = hoja de detalle de la Rejilla (`RejillaRequests`).
    var onOpenCombo: ((Int) -> Void)?

    init(onOpenGrid: ((Int?) -> Void)? = nil, onOpenCombo: ((Int) -> Void)? = nil) {
        self.onOpenGrid = onOpenGrid
        self.onOpenCombo = onOpenCombo
    }

    var body: some View {
        #if DEBUG
        if GardenDemoLaunch.isRequested {
            GardenDemoHost(base: env, onOpenGrid: onOpenGrid, onOpenCombo: onOpenCombo)
        } else {
            GardenScreen(store: .shared, onOpenGrid: onOpenGrid, onOpenCombo: onOpenCombo)
        }
        #else
        GardenScreen(store: .shared, onOpenGrid: onOpenGrid, onOpenCombo: onOpenCombo)
        #endif
    }
}

/// Contenido del Jardín sobre el `AppEnvironment` del entorno y un `GardenStore`.
struct GardenScreen: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.selectTab) private var selectTab
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var store: GardenStore
    @StateObject private var photos: GardenPhotos
    @StateObject private var model = GardenModel()

    /// Datos de ejemplo (DEBUG): aviso arriba y «Ejemplo» en los metadatos.
    var isExample = false
    var onOpenGrid: ((Int?) -> Void)?
    var onOpenCombo: ((Int) -> Void)?

    @State private var path = NavigationPath()
    @State private var segment: GardenModel.Segment
    @State private var showScan = false
    @State private var toast: String?
    @State private var copiedScanId: String?
    @State private var cardState: ExportTile.State = .idle
    @State private var cardURL: URL?
    @State private var hexState: ExportTile.State = .idle
    @State private var diagState: ExportTile.State = .idle
    @State private var diagExport: Diagnostics.Export?
    @State private var debugHandled = false
    /// Desbloqueos que había al terminar la última visita (insignia «✦» del avatar del Jardín). Lo escribe
    /// el Jardín al dejar de verse (pestaña oculta o desaparece) o al tocar el avatar. Clave propia: el Feed
    /// actualiza `jardin.lastSeenUnlockCount` al ENTRAR en el Jardín y la insignia se apagaría al llegar.
    @AppStorage(GardenScreen.visitUnlocksKey) private var lastSeenUnlockCount = 0
    /// false mientras la pestaña está oculta (`RootTabContainer` pone `.ambientMotion(selection == tab)`).
    @Environment(\.ambientMotionEnabled) private var isTabVisible

    static let visitUnlocksKey = "jardin.avatar.seenUnlockCount"

    init(store: GardenStore, photos: GardenPhotos? = nil, isExample: Bool = false,
         initialSegment: GardenModel.Segment = .fotos,
         onOpenGrid: ((Int?) -> Void)? = nil, onOpenCombo: ((Int) -> Void)? = nil) {
        self.store = store
        _photos = StateObject(wrappedValue: photos ?? GardenPhotos())
        self.isExample = isExample
        _segment = State(initialValue: initialSegment)
        self.onOpenGrid = onOpenGrid
        self.onOpenCombo = onOpenCombo
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    content
                        .padding(.horizontal, Spacing.margin)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.xl)
                }
                .scrollIndicators(.hidden)
                .tabBarClearance()
                .task { await scrollForDebugLaunch(proxy) }
                .safeAreaInset(edge: .top, spacing: 0) {
                    GardenHeader(newUnlocks: newUnlocks, onScan: { showScan = true }, onAvatar: {
                        markUnlocksSeen()
                        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.35)) {
                            proxy.scrollTo(GardenAnchor.top, anchor: .top)
                        }
                    })
                }
            }
            .background(Theme.surface.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AjustesRoute.self) { _ in
                AjustesForm()
            }
            .navigationDestination(for: GardenAboutRoute.self) { _ in
                AboutView()
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                GardenToast(title: toast)
                    .padding(.horizontal, Spacing.margin)
                    .padding(.bottom, Spacing.margin)
                    .transition(.opacity)
                    .accessibilityIdentifier("jardin.toast")
                    .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.success, trigger: toast) { _, new in new != nil }
        .sheet(isPresented: $showScan) {
            ScanOnboardingView(onShowGrid: {
                showScan = false
                openGrid(nil)
            })
            .environmentObject(env)
        }
        .task(id: model.limit) { await model.observeScans(env: env, store: store) }
        .task { await model.observeUnlocks(env: env) }
        .task { handleDebugLaunch() }
        .onAppear {
            Task { await model.refreshCounts(env: env) }
        }
        .onChange(of: store.items) { _, _ in
            Task { await model.refreshSaved(env: env, store: store) }
        }
        .onChange(of: model.latestScan?.id) { _, _ in
            cardState = .idle
            cardURL = nil
        }
        .onChange(of: isTabVisible) { _, visible in
            if !visible { markUnlocksSeen() }
        }
        .onDisappear { markUnlocksSeen() }
        .onChange(of: model.unlocks.count) { _, count in
            if !isExample, count < lastSeenUnlockCount { lastSeenUnlockCount = count }
        }
        .accessibilityIdentifier("jardin.root")
    }

    // MARK: Contenido

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if isExample { exampleNotice }
            GardenProfileCard(yesVotes: model.yesVotes, noVotes: model.noVotes, stats: stats,
                              onSettings: { path.append(AjustesRoute()) })
                .id(GardenAnchor.top)
            segmentPicker
                .accessibilityIdentifier("jardin.segments")
            collectionsRow
            Group {
                switch segment {
                case .fotos: photosSection
                case .guardadas: savedSection
                case .colecciones: collectionsSection
                }
            }
            .id(GardenAnchor.segment)
            exportStudio
                .id(GardenAnchor.studio)
                .background(alignment: .bottom) {
                    Color.clear.frame(height: 1).offset(y: Spacing.xl).id(GardenAnchor.end)
                }
        }
    }

    private var isAX: Bool { dynamicTypeSize.isAccessibilitySize }

    /// Segmentos en píldora; con tamaños de accesibilidad, chips apilados (no caben tres en una fila).
    @ViewBuilder private var segmentPicker: some View {
        if isAX {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(GardenModel.Segment.allCases) { item in
                    FilterChip(title: item.title, isSelected: segment == item) { segment = item }
                }
            }
        } else {
            GardenSegmentBar(selection: $segment)
        }
    }

    private var exampleNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            Text("Datos de ejemplo · no se guardan")
                .textRole(.labelSM)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Tone.amber.onBadge)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: dynamicTypeSize.isAccessibilitySize ? Radius.card : 100, style: .continuous)
            .fill(Tone.amber.badgeFill))
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("jardin.example")
    }

    /// Contadores con los colores del ejemplo: valor `primary` / `secondary` / `primary-container` y
    /// puntos `bg-primary` / `bg-secondary-container` / `bg-primary-fixed-dim`.
    private var stats: [GardenStat] {
        [
            GardenStat(id: "fotos", value: model.loaded ? "\(model.scanCount)" : "—", label: "Fotos analizadas",
                       valueColor: Theme.primary, dotColor: Theme.primary, action: { segment = .fotos }),
            GardenStat(id: "rejilla", value: WrappedSummaryView.counterText(unlocked: model.unlocks.count, total: env.comboCount),
                       label: "Desbloqueadas", valueColor: Theme.secondary, dotColor: Color(light: 0xFD933F, dark: 0xFFB785),
                       action: { openGrid(nil, unlockedOnly: true) }),
            GardenStat(id: "si", value: "\(model.yesVotes)", label: "Sí, es eso",
                       valueColor: Color(light: 0x2D5A3C, dark: 0xBCEFC7), dotColor: Theme.primaryFixedDim,
                       action: { segment = .fotos }),
        ]
    }

    /// Insignia «✦» del avatar: desbloqueos nuevos desde la última visita. Con datos de ejemplo (base de
    /// datos recién sembrada) todos lo son y no se escribe nada.
    private var newUnlocks: Int {
        GardenText.newUnlocks(current: model.unlocks.count, lastSeen: isExample ? 0 : lastSeenUnlockCount)
    }

    private func markUnlocksSeen() {
        guard !isExample, model.loaded, lastSeenUnlockCount != model.unlocks.count else { return }
        lastSeenUnlockCount = model.unlocks.count
    }

    // MARK: Colecciones (fila)

    private var sizeCollections: [GardenModel.SizeCollection] { model.sizeCollections(env.dictionary) }

    private var savedCount: Int { model.savedScans.count + store.savedComboIds.count }

    private var collectionsRow: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Colecciones").textRole(.overline).foregroundStyle(Theme.onSurfaceVariant)
                if !isAX {
                    Spacer(minLength: Spacing.sm)
                    Text("\(sizeCollections.count + 1) colecciones").textRole(.labelSM).foregroundStyle(Theme.secondary)
                }
            }
            // `div.flex.gap-space-sm.overflow-x-auto.pb-1.5.pt-0.5.-mx-margin.px-margin`
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    GardenFolderPill(title: "Guardadas", count: "\(savedCount)", dot: Color(light: 0xFD933F, dark: 0xFFB785)) {
                        segment = .guardadas
                    }
                    .accessibilityIdentifier("jardin.collection.saved")
                    ForEach(sizeCollections) { c in
                        GardenFolderPill(title: c.title, count: c.countText, dot: dotColor(forSize: c.size)) {
                            openGrid(c.size)
                        }
                        .accessibilityIdentifier("jardin.collection.size\(c.size)")
                    }
                }
                .padding(.horizontal, Spacing.margin)
                .padding(.top, 2)
                .padding(.bottom, 10)
            }
            .padding(.horizontal, -Spacing.margin)
            .padding(.bottom, -4)
        }
    }

    /// Puntos de carpeta del ejemplo: `bg-secondary-container`, `bg-tertiary`, `bg-primary` (marco, no datos).
    private func dotColor(forSize size: Int) -> Color {
        switch size {
        case 2: Theme.tertiary
        case 3: Theme.primary
        default: Color(light: 0xD97724, dark: 0xFBBF24)
        }
    }

    // MARK: Fotos

    @ViewBuilder private var photosSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            GardenSectionTitle(title: "Cosechas", systemImage: "paintpalette", trailing: isAX ? nil : "Más recientes")
            if model.loaded && model.scans.isEmpty {
                GardenEmptyState(title: "Tu jardín está por sembrar",
                                 message: "Analiza una foto en Extraer o escanea el carrete: cada análisis aparece aquí con la paleta de la ropa y su combinación de Wada.",
                                 primaryTitle: "Escanear carrete", primaryImage: "photo.stack",
                                 primaryAction: { showScan = true },
                                 secondaryTitle: "Analizar una foto", secondaryImage: "drop.halffull",
                                 secondaryAction: { selectTab(.extraer) })
            } else {
                // VStack: páginas de 20 cosechas (las anclas de desplazamiento necesitan las filas creadas).
                VStack(spacing: Spacing.md) {
                    ForEach(Array(model.scans.enumerated()), id: \.element.id) { i, scan in
                        harvestRow(scan, variant: .forIndex(i), isLatest: i == 0)
                            .background(alignment: .top) {
                                if i == 1 { Color.clear.frame(height: 1).id(GardenAnchor.secondHarvest) }
                            }
                    }
                }
                if model.hasMore {
                    SolarSecondaryButton(title: "Ver más cosechas", systemImage: "chevron.down") {
                        model.limit += GardenModel.pageSize
                    }
                    .accessibilityIdentifier("jardin.more")
                }
            }
        }
    }

    private func harvestRow(_ scan: ScanRecord, variant: GardenHarvestCard.Variant, isLatest: Bool = false) -> some View {
        let palette = model.palette(for: scan, dictionary: env.dictionary)
        let thumbnail = photos.cached(scan, maxSide: 144).map { Image(decorative: $0, scale: 1) }
        let title = GardenText.comboTitle(scan.top1, dictionary: env.dictionary)
        let metadata = GardenText.harvestMetadata(scan, isExample: isExample)
        let parts = GardenText.harvestMetadataParts(scan, isExample: isExample)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Tamaños de accesibilidad: tarjeta apilada sin textos recortados (§2.4 regla 3).
                GardenHarvestStackedRow(thumbnail: thumbnail, title: title, metadata: metadata,
                                        verdict: model.verdict(for: scan), palette: palette,
                                        tags: GardenText.harvestTags(scan), isSaved: store.isSaved(scanId: scan.id),
                                        isCopied: copiedScanId == scan.id,
                                        onCopyDominant: { copyDominant(scan, palette: palette) },
                                        onToggleSave: { toggleSave(scan) })
            } else {
                GardenHarvestCard(thumbnail: thumbnail, title: title, date: parts.date, origin: parts.origin,
                                  verdict: model.verdict(for: scan), palette: palette, variant: variant,
                                  comboLabel: scan.top1.map(WadaDictionary.numberLabel), ambiguous: scan.ambiguous,
                                  isLatest: isLatest, isSaved: store.isSaved(scanId: scan.id),
                                  isCopied: copiedScanId == scan.id,
                                  onCopyColor: { copyColor(scan, color: $0) },
                                  onCopyAll: { copyAll(scan, palette: palette) },
                                  onOpenCombo: scan.top1.map { id in { openCombo(id) } },
                                  onToggleSave: { toggleSave(scan) })
            }
        }
            .task(id: scan.id) { _ = await photos.load(scan, maxSide: 144) }
            .contextMenu {
                Button {
                    copyAll(scan, palette: palette)
                } label: {
                    Label("Copiar hex de la paleta", systemImage: "doc.on.doc")
                }
                if let top1 = scan.top1 {
                    Button {
                        openCombo(top1)
                    } label: {
                        Label("Ver combinación \(WadaDictionary.numberLabel(top1))", systemImage: "square.grid.2x2")
                    }
                }
                Button {
                    toggleSave(scan)
                } label: {
                    Label(store.isSaved(scanId: scan.id) ? "Quitar del Jardín" : "Guardar en el Jardín",
                          systemImage: store.isSaved(scanId: scan.id) ? "leaf.fill" : "leaf")
                }
            }
            .accessibilityIdentifier("jardin.harvest.\(scan.id)")
    }

    // MARK: Guardadas

    @ViewBuilder private var savedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            GardenSectionTitle(title: "Guardadas", systemImage: "leaf", trailing: isAX ? nil : GardenText.savedCount(savedCount))
            if model.savedScans.isEmpty && store.savedComboIds.isEmpty {
                GardenEmptyState(title: "Nada guardado todavía",
                                 message: "Toca la hoja de una cosecha (o de una combinación en la Rejilla) para guardarla aquí. Se queda solo en este teléfono.",
                                 primaryTitle: "Ver cosechas", primaryImage: "paintpalette",
                                 primaryAction: { segment = .fotos })
            } else {
                LazyVStack(spacing: Spacing.md) {
                    ForEach(model.savedScans) { scan in
                        harvestRow(scan, variant: .distribution)
                    }
                }
                let combos = store.items.filter { $0.kind == .combo }.compactMap { Int($0.id) }
                if !combos.isEmpty {
                    Text("Combinaciones guardadas").textRole(.overline).foregroundStyle(Theme.onSurfaceVariant)
                        .padding(.top, Spacing.xs)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.gutter), GridItem(.flexible(), spacing: Spacing.gutter)],
                              spacing: Spacing.gutter) {
                        ForEach(combos, id: \.self) { id in
                            savedComboCard(id)
                        }
                    }
                }
            }
        }
    }

    private func savedComboCard(_ id: Int) -> some View {
        let colors = PaletteColor.combo(id, in: env.dictionary)
        let unlock = model.unlocks[id]
        return PaletteGridCard(title: GardenText.comboTitle(id, dictionary: env.dictionary),
                               subtitle: DesignFormat.comboSubtitle(id: id, size: colors.count),
                               colors: colors,
                               state: unlock.map { .unlocked(since: GardenText.shortDate($0.firstSeenAt)) } ?? .locked,
                               revealsColors: true, isSaved: true,
                               onToggleSave: { store.toggle(comboId: id); flash("Quitada del Jardín") })
            .onTapGesture { openCombo(id) }
    }

    // MARK: Colecciones (segmento)

    @ViewBuilder private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            GardenSectionTitle(title: "Colecciones", systemImage: "folder", trailing: isAX ? nil : "Por tamaño")
            ForEach(sizeCollections) { c in
                collectionCard(c)
            }
            savedCollectionCard
        }
    }

    private func collectionCard(_ c: GardenModel.SizeCollection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).textRole(.overline).foregroundStyle(Theme.secondary)
                    Text("Combinaciones de \(c.size) colores").textRole(.headlineSM).foregroundStyle(Theme.onSurface)
                }
                Spacer(minLength: Spacing.sm)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(c.countText).textRole(.headlineSM, weight: .semibold).monospacedDigit().foregroundStyle(Theme.primary)
                    Text("en tu rejilla").textRole(.labelSM).foregroundStyle(Theme.onSurfaceVariant)
                }
                .accessibilityElement(children: .combine)
            }
            GardenProgressBar(fraction: c.fraction)
                .accessibilityElement()
                .accessibilityLabel(GardenText.collectionProgress(c))
            if c.recentUnlocked.isEmpty {
                Text("Aún no tienes ninguna de \(c.size) colores en tu rejilla.")
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
            } else {
                SwatchWell(padding: Spacing.sm, cornerRadius: Radius.block) {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        ForEach(0..<4, id: \.self) { slot in
                            if slot < c.recentUnlocked.count {
                                let id = c.recentUnlocked[slot]
                                VStack(spacing: Spacing.xs) {
                                    PaletteRibbon(colors: PaletteColor.combo(id, in: env.dictionary), style: .stripes,
                                                  height: 44, inWell: false)
                                    Text(WadaDictionary.numberLabel(id))
                                        .textRole(.labelSM)
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.wellTextSecondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture { openCombo(id) }
                            } else {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                            }
                        }
                    }
                }
            }
            SolarSecondaryButton(title: "Ver en la Rejilla", systemImage: "square.grid.2x2", fullWidth: false) {
                openGrid(c.size)
            }
            .accessibilityIdentifier("jardin.collection.open\(c.size)")
        }
        .padding(Spacing.md)
        .solarCard(elevation: .rest)
    }

    private var savedCollectionCard: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(Tone.amber.badgeFill)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "leaf.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(Tone.amber.onBadge)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Guardadas").textRole(.headlineSM).foregroundStyle(Theme.onSurface)
                Text("\(GardenText.savedCount(model.savedScans.count)) · \(store.savedComboIds.count) \(store.savedComboIds.count == 1 ? "combinación" : "combinaciones")")
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
            }
            Spacer(minLength: Spacing.sm)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onSurfaceVariant)
                .accessibilityHidden(true)
        }
        .padding(Spacing.md)
        .solarCard(elevation: .rest)
        .contentShape(Rectangle())
        .onTapGesture { segment = .guardadas }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Estudio de exportación

    private var exportStudio: some View {
        GardenStudioSection {
            GardenStudioTile(title: "Compartir tarjeta", detail: cardDetail, systemImage: "square.and.arrow.up", accent: .moss,
                             state: model.latestScan == nil ? .disabled : cardState, shareURL: cardURL) {
                prepareCard()
            }
            .accessibilityIdentifier("jardin.share")
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            GardenStudioTile(title: "Copiar hex", detail: "Los colores de la última cosecha", systemImage: "doc.on.doc",
                             accent: .amber, state: model.latestScan == nil ? .disabled : hexState) {
                copyLatestHex()
            }
            .accessibilityIdentifier("jardin.copyHex")
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            GardenStudioTile(title: "Exportar diagnóstico", detail: diagDetail, systemImage: "doc.zipper", accent: .celadon,
                             state: diagState, shareURL: diagExport?.url) {
                exportDiagnostics()
            }
            .accessibilityIdentifier("jardin.export")
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            GardenStudioTile(title: "Escanear carrete", detail: "Últimas 200 fotos, en el teléfono", systemImage: "photo.stack",
                             accent: .sun) {
                showScan = true
            }
            .accessibilityIdentifier("jardin.scan")
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }

    private var cardDetail: String {
        switch cardState {
        case .working: "Dibujando la tarjeta…"
        case .ready: "Lista: toca para compartir"
        default: "Imagen 1080 × 1350 de la última cosecha"
        }
    }

    private var diagDetail: String {
        switch diagState {
        case .working: "Preparando el zip…"
        case .ready: diagExport.map { "Listo: \(DiagnosticsExportAction.summary($0))" } ?? "Listo"
        default: "Zip con veredictos, tiempos y fotos votadas"
        }
    }

    // MARK: Acciones

    /// Rejilla con el filtro de tamaño (`RejillaRequests`) o solo las desbloqueadas (contador x/348).
    private func openGrid(_ size: Int?, unlockedOnly: Bool = false) {
        if let onOpenGrid {
            onOpenGrid(size)
            return
        }
        RejillaRequests.shared.open(size: size, status: unlockedOnly ? .unlocked : nil)
        selectTab(.rejilla)
    }

    /// Detalle de una combinación: el del integrador o la hoja de la Rejilla.
    private func openCombo(_ id: Int) {
        if let onOpenCombo {
            onOpenCombo(id)
            return
        }
        RejillaRequests.shared.open(comboId: id)
        selectTab(.rejilla)
    }

    private func toggleSave(_ scan: ScanRecord) {
        let saved = store.toggle(scanId: scan.id)
        flash(saved ? "Guardado en el Jardín" : "Quitado del Jardín")
    }

    private func copyDominant(_ scan: ScanRecord, palette: [PaletteColor]) {
        guard let dominant = palette.first else { return }
        copyColor(scan, color: dominant)
    }

    /// Copia el hex de una gota (o del dominante) y marca la cosecha como copiada.
    private func copyColor(_ scan: ScanRecord, color: PaletteColor) {
        GardenExport.copy(color.hex)
        markCopied(scan)
        flash(GardenExport.copiedToast(count: 1, single: color.hex))
    }

    private func copyAll(_ scan: ScanRecord, palette: [PaletteColor]) {
        guard !palette.isEmpty else { return }
        GardenExport.copy(DesignFormat.hexList(palette))
        markCopied(scan)
        flash(GardenExport.copiedToast(count: palette.count, single: palette.first?.hex))
    }

    private func copyLatestHex() {
        guard let scan = model.latestScan else { return }
        let palette = model.palette(for: scan, dictionary: env.dictionary)
        guard !palette.isEmpty else { return }
        GardenExport.copy(DesignFormat.hexList(palette))
        flash(GardenExport.copiedToast(count: palette.count, single: palette.first?.hex))
        hexState = .ready
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            hexState = .idle
        }
    }

    private func markCopied(_ scan: ScanRecord) {
        copiedScanId = scan.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if copiedScanId == scan.id { copiedScanId = nil }
        }
    }

    private func prepareCard() {
        guard let scan = model.latestScan else { return }
        cardState = .working
        Task { @MainActor in
            let photo = await photos.load(scan, maxSide: 1080)
            do {
                cardURL = try GardenExport.writeCard(for: scan, photo: photo, dictionary: env.dictionary)
                cardState = .ready
            } catch {
                cardState = .failed(ErrorText.describe(error))
            }
        }
    }

    private func exportDiagnostics() {
        diagState = .working
        Task { @MainActor in
            do {
                diagExport = try await DiagnosticsExportAction.run(env: env)
                diagState = .ready
            } catch {
                diagState = .failed(ErrorText.describe(error))
            }
        }
    }

    /// Toast del ejemplo: solo opacidad, 300 ms `cubic-bezier(0.4, 0, 0.2, 1)`, visible 2 200 ms.
    private func flash(_ text: String) {
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.3)) { toast = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if toast == text {
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.3)) { toast = nil }
            }
        }
    }

    /// DEBUG: `-uiGardenScroll segmento|cosechas|estudio|fin` desplaza la pantalla para capturas.
    private func scrollForDebugLaunch(_ proxy: ScrollViewProxy) async {
        #if DEBUG
        guard let target = GardenDemoLaunch.scroll else { return }
        try? await Task.sleep(for: .seconds(2.5))
        let anchor: String = switch target {
        case "cosechas": GardenAnchor.secondHarvest
        case "estudio": GardenAnchor.studio
        case "fin": GardenAnchor.end
        default: GardenAnchor.segment
        }
        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(anchor, anchor: target == "fin" ? .bottom : .top) }
        #endif
    }

    private func handleDebugLaunch() {
        #if DEBUG
        guard !debugHandled else { return }
        debugHandled = true
        if DebugLaunch.requested == .ajustes || GardenDemoLaunch.page == "ajustes" {
            path.append(AjustesRoute())
        } else if GardenDemoLaunch.page == "acerca" {
            path.append(AjustesRoute())
            path.append(GardenAboutRoute())
        } else if GardenDemoLaunch.page == "scan" {
            showScan = true
        }
        #endif
    }
}

// MARK: - Piezas del Jardín

/// Margen inferior para que el final de una lista no quede bajo la barra de pestañas propia
/// (`SolarTabBar` en `safeAreaInset` de la raíz): si el área segura que llega al ScrollView ya
/// incluye la barra no añade nada; si no (la pila de navegación no la propaga), añade su alto.
struct TabBarClearance: ViewModifier {
    @State private var extra: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, extra, for: .scrollContent)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { update(geo.safeAreaInsets.bottom) }
                        .onChange(of: geo.safeAreaInsets.bottom) { _, value in update(value) }
                }
            }
    }

    private func update(_ inset: CGFloat) {
        let windowInset = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? 0
        extra = Self.extra(scrollInset: inset, windowInset: windowInset)
    }

    /// Alto que falta para despejar la barra (0 si el área segura ya la cuenta).
    nonisolated static func extra(scrollInset: CGFloat, windowInset: CGFloat, tabBar: CGFloat = Sizes.tabBar) -> CGFloat {
        max(0, tabBar - max(0, scrollInset - windowInset))
    }
}

extension View {
    /// Ver `TabBarClearance`.
    func tabBarClearance() -> some View {
        modifier(TabBarClearance())
    }
}

/// «Acerca de» empujado en la pila del Jardín (Ajustes › Acerca de).
struct GardenAboutRoute: Hashable {}

/// Anclas de desplazamiento del Jardín.
enum GardenAnchor {
    static let top = "jardin.anchor.top"
    static let segment = "jardin.anchor.segment"
    static let secondHarvest = "jardin.anchor.harvest2"
    static let studio = "jardin.anchor.studio"
    static let end = "jardin.anchor.end"
}

/// Cosecha apilada para tamaños de accesibilidad: los mismos datos que `HarvestRow` (título,
/// metadatos, veredicto, guardar, paleta proporcional en pocillo, colores y copiar el dominante)
/// en una columna, sin límites de línea.
struct GardenHarvestStackedRow: View {
    let thumbnail: Image?
    let title: String
    let metadata: String
    var verdict: Verdict?
    let palette: [PaletteColor]
    var tags: [String] = []
    var isSaved = false
    var isCopied = false
    var onCopyDominant: (() -> Void)?
    var onToggleSave: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Group {
                    if let thumbnail {
                        thumbnail.resizable().scaledToFill()
                    } else {
                        Theme.containerLow.overlay { Image(systemName: "photo").foregroundStyle(Theme.onSurfaceVariant) }
                    }
                }
                .frame(width: Sizes.harvestThumb, height: Sizes.harvestThumb)
                .clipShape(RoundedRectangle(cornerRadius: Radius.block, style: .continuous))
                .accessibilityHidden(true)
                Spacer(minLength: Spacing.xs)
                if let onToggleSave {
                    SolarIconButton(systemImage: isSaved ? "leaf.fill" : "leaf",
                                    accessibilityLabel: isSaved ? "Guardada: quitar del jardín" : "Guardar en tu jardín",
                                    foreground: isSaved ? Theme.primary : Theme.onSurfaceVariant, action: onToggleSave)
                }
            }
            Text(title).textRole(.headlineSM).foregroundStyle(Theme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Text(metadata).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            VerdictBadge(verdict: verdict)
            SwatchWell(padding: Spacing.sm, cornerRadius: Radius.block) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(palette.compactMap { $0.weight.map(DesignFormat.percent) }.joined(separator: " · "))
                        .textRole(.bodySM)
                        .monospacedDigit()
                        .foregroundStyle(Theme.wellTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PaletteRibbon(colors: palette, style: .weights, height: Sizes.weightBar, inWell: false)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(palette.prefix(3)) { MicroColorPill(color: $0, showsHex: false) }
            }
            ForEach(tags, id: \.self) { tag in
                SolarBadge(title: tag, fill: tag == "Ambigua" ? Theme.secondaryFixed : Theme.container,
                           foreground: tag == "Ambigua" ? Theme.onSecondaryFixedVariant : Theme.primary)
            }
            if let dominant = palette.first, let onCopyDominant {
                SolarSecondaryButton(title: isCopied ? "Copiado" : "Copiar \(dominant.hex)", systemImage: "doc.on.doc",
                                     isDone: isCopied, action: onCopyDominant)
                    .accessibilityLabel("Copiar hex dominante \(dominant.hex)")
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card).elevation(.restStrong) }
    }
}

/// Barra de progreso del marco (pista `surfaceVariant`, relleno musgo). No es color de datos.
struct GardenProgressBar: View {
    let fraction: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceVariant)
                Capsule().fill(Theme.primary)
                    .frame(width: max(fraction > 0 ? height : 0, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: height)
    }
}

/// Estado vacío (§4 n.º 32): icono `secondary`, título `headline-sm`, texto `body-lg` y botones.
struct GardenEmptyState: View {
    let title: String
    let message: String
    var systemImage: String = "leaf"
    var primaryTitle: String?
    var primaryImage: String?
    var primaryAction: (() -> Void)?
    var secondaryTitle: String?
    var secondaryImage: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Circle()
                .fill(Tone.moss.badgeFill)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: systemImage).font(.system(size: 20, weight: .semibold)).foregroundStyle(Tone.moss.onBadge)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).textRole(.headlineSM).foregroundStyle(Theme.primary)
                Text(message).textRole(.bodyLG).foregroundStyle(Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let primaryTitle, let primaryAction {
                SolarPrimaryButton(title: primaryTitle, systemImage: primaryImage, elevated: false, luminous: true, action: primaryAction)
            }
            if let secondaryTitle, let secondaryAction {
                GhostButton(title: secondaryTitle, systemImage: secondaryImage, action: secondaryAction)
            }
        }
        .padding(Spacing.margin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solarCard(elevation: .rest)
    }
}
