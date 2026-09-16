// Pestaña Feed (docs/design/DESIGN_SYSTEM.md §5.1; fidelidad visual al ejemplo «solar feed»
// del usuario en docs/design/FIDELITY.md §3): los análisis guardados como publicaciones.
// Cabecera luminosa de marca (FeedHeader), chips de filtro, banner del escaneo del carrete,
// combinación del día con «Otra combinación» (FeedDayCard) y una publicación por scan
// (FeedLuminousPostCard): foto a sangre, paleta en pocillo neutro, combinación ganadora y
// acciones reales («Sí, es eso» / «No», Guardar en el Jardín, Copiar hex, Compartir tarjeta
// 4:5 o 9:16). Sin «me gusta», contadores ni perfiles: todo local. Sobre el contenido flotan
// las cinco motas de luz del ejemplo, por debajo de la cabecera y sin pisar los pocillos.
// La primera vez presenta el escaneo del carrete (ScanOnboardingView) con «Ahora no».
import SwiftUI
import UIKit
import SubjectKit

struct FeedView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.selectTab) private var selectTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.forceReducedMotion) private var forcedReduceMotion
    /// false mientras la pestaña está oculta (RootTabContainer): la marca deja de animarse.
    @Environment(\.ambientMotionEnabled) private var ambientMotionEnabled
    @Environment(\.activeRootTab) private var activeRootTab
    @ObservedObject private var garden: GardenStore
    /// Combinaciones desbloqueadas la última vez que se abrió el Jardín (insignia «✦» del avatar).
    @AppStorage private var gardenSeenUnlocks: Int
    private let photoStore: ScanPhotoStore
    /// Publicaciones de ejemplo (atajo DEBUG `-uiScreen feed-demo`): llevan «Ejemplo» delante.
    private let exampleIds: Set<String>

    init(garden: GardenStore = .shared, photoStore: ScanPhotoStore = .shared, exampleIds: Set<String> = []) {
        self.garden = garden
        self.photoStore = photoStore
        self.exampleIds = exampleIds
        _gardenSeenUnlocks = AppStorage(wrappedValue: 0, exampleIds.isEmpty ? Self.gardenSeenKey : Self.gardenSeenDemoKey)
    }

    static let gardenSeenKey = "jardin.lastSeenUnlockCount"
    /// Clave aparte para los datos de ejemplo (base en memoria) del atajo `feed-demo`.
    static let gardenSeenDemoKey = "jardin.lastSeenUnlockCount.demo"

    /// Combinaciones nuevas desde la última visita al Jardín (nunca negativo).
    nonisolated static func newUnlocks(total: Int, seen: Int) -> Int { max(0, total - max(0, seen)) }

    static let pageSize = 50

    @State private var path = NavigationPath()
    @State private var filter: FeedFilter = .all
    @State private var limit = FeedView.pageSize
    @State private var items: [FeedItem] = []
    @State private var itemCache: [String: FeedItem] = [:]
    @State private var loaded = false
    @State private var verdicts: [String: FeedbackVerdict] = [:]
    @State private var unlockedIds: Set<Int> = []
    @State private var shuffle: (day: Int, comboId: Int)?
    @State private var comboSheet: FeedComboSheet?
    @State private var shareRequest: ShareCardRequest?
    @State private var toast: String?
    @State private var toastTrigger = 0
    @State private var copiedPostId: String?
    @State private var showScanOnboarding = false
    @State private var onboardingChecked = false
    @State private var deleteCandidate: ScanRecord?
    @State private var reopeningId: String?
    @State private var launchApplied = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id(FeedLaunchOptions.topAnchor)
                    FeedFilterChips(selection: $filter)
                        .padding(.bottom, Spacing.xs)
                    if FeedScanBanner.isVisible(env.scanProgress) {
                        FeedScanBanner(progress: env.scanProgress)
                            .padding(.horizontal, Spacing.margin)
                            .padding(.bottom, Spacing.md)
                    }
                    dayCard
                        .padding(.horizontal, Spacing.margin)
                        .padding(.bottom, Spacing.lg)
                    posts
                }
                .padding(.bottom, Spacing.lg)
            }
            .task(id: loaded) {
                guard loaded, !launchApplied else { return }
                launchApplied = true
                await applyLaunchOptions(proxy: proxy)
            }
            }
            .scrollIndicators(.hidden)
            .background(Theme.surface.ignoresSafeArea())
            // Motas de luz sobre el contenido y bajo la cabecera (se recortan sobre los pocillos).
            .lightMotes()
            .safeAreaInset(edge: .top, spacing: 0) {
                FeedHeader(animated: ambientMotionEnabled,
                           newUnlocks: Self.newUnlocks(total: unlockedIds.count, seen: gardenSeenUnlocks),
                           onAnalyze: { selectTab(.extraer) },
                           onGarden: {
                               gardenSeenUnlocks = unlockedIds.count
                               selectTab(.jardin)
                           })
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ResultRoute.self) { route in
                ResultView(model: {
                    let model = ResultViewModel(outcome: route.outcome, env: env)
                    model.showMask = route.showMask
                    model.banner = route.banner
                    return model
                }())
            }
            .navigationDestination(for: LayersRoute.self) { route in
                LayersInspectorView(model: LayersInspectorModel(outcome: route.outcome, dictionary: env.dictionary),
                                    initialLayer: route.initialLayer)
            }
        }
        // Toast arriba, 16 pt bajo la cabecera (`fixed top-20`), como en el ejemplo.
        .overlay(alignment: .top) { toastView }
        .sensoryFeedback(.success, trigger: toastTrigger)
        .sheet(item: $comboSheet) { item in
            if let combo = env.dictionary.combo(id: item.id) {
                RejillaComboDetailView(combo: combo)
                    .environmentObject(env)
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(Radius.sheet)
            }
        }
        .sheet(item: $shareRequest) { request in
            ShareCardSheet(request: request, dictionary: env.dictionary)
                .presentationCornerRadius(Radius.sheet)
        }
        .sheet(isPresented: $showScanOnboarding, onDismiss: { Task { await FeedOnboarding.markDismissed(settings: env.settings) } }) {
            ScanOnboardingView(onShowGrid: {
                showScanOnboarding = false
                selectTab(.rejilla)
            }, onSkip: {
                showScanOnboarding = false
            })
            .environmentObject(env)
        }
        .confirmationDialog("¿Borrar esta publicación del Feed?", isPresented: deleteDialogBinding, titleVisibility: .visible,
                            presenting: deleteCandidate) { scan in
            Button("Borrar", role: .destructive) { delete(scan) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Se borra el análisis y su foto de la app. La foto original del carrete no se toca.")
        }
        .task(id: limit) { await observeScans(limit: limit) }
        .task { await observeUnlocks() }
        .task { await presentOnboardingIfNeeded() }
        .onChange(of: activeRootTab) { old, new in
            // Visitar el Jardín (entrar o salir de su pestaña) marca como vistas las combinaciones.
            if old == .jardin || new == .jardin { gardenSeenUnlocks = unlockedIds.count }
        }
        .onChange(of: unlockedIds.count) { _, count in
            if count < gardenSeenUnlocks { gardenSeenUnlocks = count }
        }
        .accessibilityIdentifier("feed.root")
    }

    // MARK: Combinación del día

    private var dayComboId: Int {
        let today = DayPick.localDaysSince1970(Date())
        if let shuffle, shuffle.day == today { return shuffle.comboId }
        return DayPick.comboId(for: Date())
    }

    private var dayCard: some View {
        let id = dayComboId
        let size = env.dictionary.combo(id: id)?.size ?? 0
        let isShuffled = shuffle?.day == DayPick.localDaysSince1970(Date())
        let eyebrow = isShuffled ? "Combinación al azar" : "Combinación del día"
        let name = FeedComboName.name(id, in: env.dictionary)
        let colors = PaletteColor.combo(id, in: env.dictionary)
        let status = FeedPostText.dayStatus(size: size, unlocked: unlockedIds.contains(id))
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                FeedAccessibleDayCard(eyebrow: eyebrow, numberLabel: WadaDictionary.numberLabel(id), name: name, colors: colors,
                                      status: status, onShuffle: shuffleDay, onOpen: { comboSheet = FeedComboSheet(id: id) })
            } else {
                // La tarjeta no se sustituye al barajar: cambian sus colores y textos (500 ms).
                FeedDayCard(eyebrow: eyebrow, isToday: !isShuffled, comboId: id, numberLabel: WadaDictionary.numberLabel(id),
                            name: name, colors: colors, status: status, onShuffle: shuffleDay,
                            onOpen: { comboSheet = FeedComboSheet(id: id) },
                            onCopyColor: { color in copy([color], postId: nil) })
            }
        }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed.day")
    }

    private var reducesMotion: Bool { reduceMotion || forcedReduceMotion }

    private func shuffleDay() {
        let today = DayPick.localDaysSince1970(Date())
        withAnimation(reducesMotion ? .easeOut(duration: MotionSpec.reducedFadeDuration)
                                    : .timingCurve(0.4, 0, 0.2, 1, duration: 0.5)) {
            shuffle = (today, DayPick.another(than: dayComboId, count: env.comboCount))
        }
    }

    // MARK: Publicaciones

    private var visibleItems: [FeedItem] {
        items.filter { filter.includes(top1Size: $0.top1Size, verdict: verdicts[$0.id], isSaved: garden.isSaved(scanId: $0.id)) }
    }

    @ViewBuilder private var posts: some View {
        if !loaded {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xl)
        } else if items.isEmpty {
            FeedEmptyState(onAnalyze: { selectTab(.extraer) },
                           onScanLibrary: env.scanRunner is NoopScanRunner ? nil : { showScanOnboarding = true })
                .padding(.horizontal, Spacing.margin)
        } else {
            let visible = visibleItems
            if visible.isEmpty {
                Text(filter.emptyText)
                    .textRole(.bodyMD)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.xl)
                    .accessibilityIdentifier("feed.filterEmpty")
            }
            ForEach(visible) { item in
                FeedPostRow(item: item, verdict: verdicts[item.id], isSaved: garden.isSaved(scanId: item.id),
                            isCopied: copiedPostId == item.id, isReopening: reopeningId == item.id,
                            photoStore: photoStore, handlers: handlers(for: item))
                    .padding(.horizontal, Spacing.margin)
                    .padding(.bottom, Spacing.xl)
                    .onAppear { loadMoreIfNeeded(after: item) }
            }
        }
    }

    private func loadMoreIfNeeded(after item: FeedItem) {
        guard item.id == items.last?.id, items.count >= limit else { return }
        limit += Self.pageSize
    }

    private func handlers(for item: FeedItem) -> FeedPostHandlers {
        FeedPostHandlers(
            vote: { verdict in vote(verdict, item: item) },
            toggleSave: {
                let saved = garden.toggle(scanId: item.id)
                flash(saved ? "Guardado en el Jardín" : "Quitado del Jardín", systemImage: saved ? "leaf.fill" : "leaf")
            },
            copyCombo: {
                guard let match = item.match else { return }
                copy(match.colors, postId: item.id)
            },
            copyPalette: { copy(item.palette, postId: nil) },
            copyColor: { color in copy([color], postId: nil) },
            openInExtract: { photo in reopen(item: item, photo: photo) },
            openCombo: { id in comboSheet = FeedComboSheet(id: id) },
            share: { photo in shareRequest = ShareCardRequest(scan: item.scan, photo: photo) },
            delete: { deleteCandidate = item.scan })
    }

    // MARK: Acciones

    private func vote(_ verdict: FeedbackVerdict, item: FeedItem) {
        guard verdicts[item.id] == nil else { return }
        verdicts[item.id] = verdict // un solo voto: se refleja al instante
        Task {
            do {
                try await FeedServices.vote(verdict, scan: item.scan, env: env, photoStore: photoStore)
                flash(verdict == .yes ? "Gracias. Marcado como acierto" : "Gracias. Lo tendremos en cuenta",
                      systemImage: verdict == .yes ? "heart.fill" : "hand.thumbsdown.fill")
            } catch {
                verdicts[item.id] = nil
                flash(ErrorText.describe(error), systemImage: "exclamationmark.triangle.fill")
            }
        }
    }

    private func copy(_ colors: [PaletteColor], postId: String?) {
        guard !colors.isEmpty else { return }
        UIPasteboard.general.string = DesignFormat.hexList(colors)
        flash(FeedPostText.copiedToast(count: colors.count, single: colors.first?.hex), systemImage: "doc.on.doc.fill")
        if let postId {
            copiedPostId = postId
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                if copiedPostId == postId { copiedPostId = nil }
            }
        }
    }

    private func reopen(item: FeedItem, photo: CGImage?) {
        guard reopeningId == nil else { return }
        guard let photo else {
            flash("La foto de este análisis no está disponible", systemImage: "photo")
            return
        }
        reopeningId = item.id
        Task {
            defer { reopeningId = nil }
            do {
                let fallback = ((try? await env.settings.subjectSettings()) ?? .default).subjectOptions
                // Con un scan de una versión anterior, `reopen` lo re-analiza Y lo guarda
                // actualizado (CONTEXT §13: no seguir enseñando resultados como el Nº 067).
                let reopened = try await FeedServices.reopen(scan: item.scan, image: photo, fallback: fallback,
                                                             scans: env.scans)
                path.append(ResultRoute(outcome: reopened.outcome, banner: reopened.banner))
                if let banner = reopened.banner {
                    flash(banner, systemImage: "arrow.triangle.2.circlepath")
                }
            } catch {
                flash(ErrorText.describe(error), systemImage: "exclamationmark.triangle.fill")
            }
        }
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
    }

    private func delete(_ scan: ScanRecord) {
        deleteCandidate = nil
        Task {
            do {
                try await FeedServices.delete(scan: scan, env: env, garden: garden, photoStore: photoStore)
                flash("Borrado del Feed", systemImage: "trash.fill")
            } catch {
                flash(ErrorText.describe(error), systemImage: "exclamationmark.triangle.fill")
            }
        }
    }

    // MARK: Toast

    @State private var toastIcon = "checkmark.circle.fill"

    /// Toast luminoso del ejemplo: halo ámbar `0 0 20px` 40 %, filo `amber-400/30` y destellos
    /// girando cada 3 s; aparece bajando 8 pt con fundido (300 ms) y dura 2,2 s. Los avisos de
    /// error van sin luces y con su icono quieto.
    @ViewBuilder private var toastView: some View {
        if let toast {
            let isError = toastIcon.hasPrefix("exclamationmark")
            SolarToast(title: toast, systemImage: isError ? toastIcon : "sparkles", luminous: !isError)
                .padding(.horizontal, Spacing.margin)
                .padding(.top, Sizes.header + Spacing.margin)
                .transition(reducesMotion ? .opacity : .opacity.combined(with: .offset(y: -8)))
                .accessibilityIdentifier("feed.toast")
        }
    }

    private func flash(_ text: String, systemImage: String = "checkmark.circle.fill") {
        withAnimation(reducesMotion ? .easeOut(duration: MotionSpec.reducedFadeDuration)
                                    : .timingCurve(0.4, 0, 0.2, 1, duration: 0.3)) {
            toastIcon = systemImage
            toast = text
        }
        toastTrigger += 1
        let trigger = toastTrigger
        UIAccessibility.post(notification: .announcement, argument: text)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard toastTrigger == trigger else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.3)) { toast = nil }
        }
    }

    // MARK: Atajos de depuración (capturas)

    private func applyLaunchOptions(proxy: ScrollViewProxy) async {
        #if DEBUG
        let options = FeedLaunchOptions.current
        guard options != FeedLaunchOptions.none else { return }
        if let raw = options.filter { filter = raw }
        try? await Task.sleep(for: .milliseconds(800))
        if let scroll = options.scroll, items.indices.contains(scroll.index) {
            // Dos pasos: la pila perezosa crea la fila y después se ancla con precisión.
            proxy.scrollTo(items[scroll.index].id, anchor: .top)
            try? await Task.sleep(for: .milliseconds(500))
            proxy.scrollTo(items[scroll.index].id, anchor: scroll.anchor)
        }
        if let index = options.shareIndex, items.indices.contains(index) {
            let item = items[index]
            let photo = await ScanPhotoLoader.image(for: item.scan, store: photoStore)
            shareRequest = ShareCardRequest(scan: item.scan, photo: photo, initialFormat: options.shareFormat)
        }
        if let id = options.comboSheet { comboSheet = FeedComboSheet(id: id) }
        if let index = options.openIndex, items.indices.contains(index) {
            let item = items[index]
            reopen(item: item, photo: await ScanPhotoLoader.image(for: item.scan, store: photoStore))
        }
        if let text = options.toast { flash(text, systemImage: "doc.on.doc.fill") }
        #endif
    }

    // MARK: Observación

    private func observeScans(limit: Int) async {
        do {
            for try await scans in env.scans.observeRecent(limit: limit) {
                var cache = itemCache
                items = scans.map { scan in
                    let key = "\(scan.id)#\(scan.rev)"
                    if let cached = cache[key] { return cached }
                    let item = FeedItem(scan: scan, dictionary: env.dictionary, isExample: exampleIds.contains(scan.id))
                    cache[key] = item
                    return item
                }
                itemCache = cache
                verdicts = await latestVerdicts()
                loaded = true
            }
        } catch {
            loaded = true
        }
    }

    private func latestVerdicts() async -> [String: FeedbackVerdict] {
        guard let all = try? await env.feedback.all() else { return verdicts }
        var out: [String: FeedbackVerdict] = [:]
        for f in all where out[f.scanId] == nil { // all(): más reciente primero
            out[f.scanId] = f.verdict
        }
        // Votos recién hechos en esta pantalla que aún no han llegado a la lectura.
        for (id, v) in verdicts where out[id] == nil { out[id] = v }
        return out
    }

    private func observeUnlocks() async {
        do {
            for try await ids in env.unlocks.observeUnlockedIds() {
                unlockedIds = ids
            }
        } catch {
            // Estado de desbloqueo sin actualizar.
        }
    }

    private func presentOnboardingIfNeeded() async {
        guard !onboardingChecked else { return }
        onboardingChecked = true
        guard !(env.scanRunner is NoopScanRunner) else { return }
        let done = (try? await env.settings.bool(.initialScanDone)) ?? false
        let skipped = (try? await env.settings.bool(.scanOnboardingSkipped)) ?? false
        if FeedOnboarding.shouldPresent(initialScanDone: done, skipped: skipped, debugScreen: DebugLaunch.requested != nil,
                                        runningTests: AppEnvironment.isRunningTests) {
            showScanOnboarding = true
        }
    }
}

/// Hoja de detalle de una combinación.
struct FeedComboSheet: Identifiable, Hashable {
    let id: Int
}
