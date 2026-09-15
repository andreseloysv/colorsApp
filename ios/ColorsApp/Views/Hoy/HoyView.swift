// Pestaña Hoy (PLAN §7): "Elegir foto" (PhotosPicker) y "Cámara"
// (UIImagePickerController) -> CGImage con orientación EXIF -> recorte de sujeto
// (SubjectKit) + ce_analyze en segundo plano -> scan guardado -> Resultado.
// Debajo, el escaneo del carrete ("Escanear carrete", progreso y contador) y los
// últimos scans con su veredicto. La primera vez (sin escaneo inicial hecho ni
// saltado) presenta ScanOnboardingView con la opción "Ahora no".
import SwiftUI
import PhotosUI
import UIKit
import SubjectKit

/// Ruta del NavigationStack de Hoy hacia Resultado.
struct ResultRoute: Hashable {
    let outcome: ScanOutcome
    /// "Ver máscara" activado al abrir (atajo de depuración).
    var showMask = false
}

/// Ruta de depuración (-uiScreen ajustes): Ajustes empujado en la pila de Hoy.
struct AjustesRoute: Hashable {}

struct HoyView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var path = NavigationPath()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var capture: CaptureState = .idle
    @State private var recent: [ScanRecord] = []
    @State private var verdicts: [String: FeedbackVerdict] = [:]
    @State private var unlockedCount = 0
    @State private var debugHandled = false
    @State private var showScanOnboarding = false
    @State private var onboardingChecked = false
    @Environment(\.selectTab) private var selectTab

    enum CaptureState: Equatable {
        case idle
        case working(String)
        case failed(String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                captureSection
                librarySection
                recentSection
            }
            .navigationTitle("Hoy")
            .navigationDestination(for: ResultRoute.self) { route in
                ResultView(model: {
                    let model = ResultViewModel(outcome: route.outcome, env: env)
                    model.showMask = route.showMask
                    return model
                }())
            }
            .navigationDestination(for: LayersRoute.self) { route in
                LayersInspectorView(model: LayersInspectorModel(outcome: route.outcome, dictionary: env.dictionary),
                                    initialLayer: route.initialLayer)
            }
            .navigationDestination(for: Int.self) { comboId in
                ComboDetailView(comboId: comboId)
            }
            .navigationDestination(for: AjustesRoute.self) { _ in
                AjustesForm()
                    .navigationTitle("Ajustes")
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await handle(pickerItem: item) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image {
                    Task { await handle(cameraImage: image) }
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showScanOnboarding, onDismiss: { Task { await onboardingDismissed() } }) {
            ScanOnboardingView(onShowGrid: {
                showScanOnboarding = false
                selectTab(.rejilla)
            }, onSkip: {
                showScanOnboarding = false
            })
            .environmentObject(env)
        }
        .task { await observeRecentScans() }
        .task { await observeUnlockCount() }
        .task { await handleDebugLaunch() }
        .task { await presentOnboardingIfNeeded() }
    }

    // MARK: Escaneo inicial

    /// Presentar la hoja del escaneo del carrete al abrir Hoy: solo si no se ha
    /// hecho ni saltado, sin atajo de depuración y fuera de XCTest.
    nonisolated static func shouldPresentOnboarding(initialScanDone: Bool, skipped: Bool, debugScreen: Bool,
                                                    runningTests: Bool) -> Bool {
        !initialScanDone && !skipped && !debugScreen && !runningTests
    }

    private func presentOnboardingIfNeeded() async {
        guard !onboardingChecked else { return }
        onboardingChecked = true
        let done = (try? await env.settings.bool(.initialScanDone)) ?? false
        let skipped = (try? await env.settings.bool(.scanOnboardingSkipped)) ?? false
        if Self.shouldPresentOnboarding(initialScanDone: done, skipped: skipped, debugScreen: DebugLaunch.requested != nil,
                                        runningTests: AppEnvironment.isRunningTests) {
            showScanOnboarding = true
        }
    }

    /// Al cerrar la hoja sin haber escaneado, no se vuelve a presentar sola
    /// (queda "Escanear carrete" en la sección Carrete).
    private func onboardingDismissed() async {
        await HoyOnboarding.markDismissed(settings: env.settings)
    }

    // MARK: Secciones

    private var isWorking: Bool {
        if case .working = capture { return true }
        return false
    }

    private var captureSection: some View {
        Section {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Elegir foto", systemImage: "photo.on.rectangle")
            }
            .disabled(isWorking)
            .accessibilityIdentifier("hoy.pick")
            if CameraPicker.isAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label("Cámara", systemImage: "camera")
                }
                .disabled(isWorking)
                .accessibilityIdentifier("hoy.camera")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Cámara", systemImage: "camera")
                        .foregroundStyle(.secondary)
                    Text("No hay cámara en este dispositivo (simulador).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            switch capture {
            case .idle:
                EmptyView()
            case .working(let text):
                HStack(spacing: 10) {
                    ProgressView()
                    Text(text)
                }
                .accessibilityIdentifier("hoy.progress")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("hoy.error")
            }
        } header: {
            Text("Analizar una foto")
        } footer: {
            Text("La foto se procesa en el teléfono; nada sale del dispositivo.")
        }
    }

    private var librarySection: some View {
        Section("Carrete") {
            if env.scanRunner is NoopScanRunner {
                Label("El escaneo del carrete no está disponible en esta build.", systemImage: "clock")
                    .foregroundStyle(.secondary)
            } else {
                switch env.scanProgress.phase {
                case .idle, .finished, .failed:
                    Button {
                        showScanOnboarding = true
                    } label: {
                        Label("Escanear carrete", systemImage: "photo.stack")
                    }
                    .disabled(isWorking)
                    .accessibilityIdentifier("hoy.scanLibrary")
                case .requestingAccess:
                    Label("Pidiendo acceso a Fotos…", systemImage: "photo.stack")
                case .fetching:
                    Label("Buscando las últimas fotos…", systemImage: "photo.stack")
                case .analyzing:
                    ProgressView(value: env.scanProgress.fraction) {
                        Text("Analizando \(env.scanProgress.processed)/\(env.scanProgress.total) fotos")
                    }
                }
            }
            LabeledContent("Combinaciones en tu rejilla", value: "\(unlockedCount)/\(env.comboCount)")
        }
    }

    private var recentSection: some View {
        Section("Últimos análisis") {
            if recent.isEmpty {
                Text("Todavía no has analizado ninguna foto.")
                    .foregroundStyle(.secondary)
            }
            ForEach(recent) { scan in
                if let top1 = scan.top1 {
                    NavigationLink(value: top1) {
                        ScanHistoryRow(scan: scan, verdict: verdicts[scan.id])
                    }
                } else {
                    ScanHistoryRow(scan: scan, verdict: verdicts[scan.id])
                }
            }
        }
    }

    // MARK: Captura

    private func handle(pickerItem item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        capture = .working("Cargando la foto…")
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ImageLoadingError.unreadable
            }
            let image = try await Task.detached(priority: .userInitiated) {
                try ImageLoading.cgImage(from: data)
            }.value
            await analyze(image: image, source: .picker, assetLocalId: item.itemIdentifier)
        } catch {
            capture = .failed(ErrorText.describe(error))
        }
    }

    private func handle(cameraImage image: UIImage) async {
        capture = .working("Preparando la foto…")
        guard let cg = ImageLoading.upright(image) else {
            capture = .failed(ErrorText.describe(ImageLoadingError.empty))
            return
        }
        await analyze(image: cg, source: .camera, assetLocalId: nil)
    }

    private func analyze(image: CGImage, source: ScanSource, assetLocalId: String?) async {
        capture = .working("Analizando…")
        do {
            let outcome = try await ScanAnalyzer.run(image: image, source: source, assetLocalId: assetLocalId, env: env)
            capture = .idle
            path.append(ResultRoute(outcome: outcome))
        } catch {
            capture = .failed(ErrorText.describe(error))
        }
    }

    // MARK: Observación

    private func observeRecentScans() async {
        do {
            for try await scans in env.scans.observeRecent(limit: 20) {
                recent = scans
                verdicts = await latestVerdicts()
            }
        } catch {
            // La lista se queda como esté; no hay nada más que hacer.
        }
    }

    private func latestVerdicts() async -> [String: FeedbackVerdict] {
        guard let all = try? await env.feedback.all() else { return [:] }
        var out: [String: FeedbackVerdict] = [:]
        for f in all where out[f.scanId] == nil { // all(): más reciente primero
            out[f.scanId] = f.verdict
        }
        return out
    }

    private func observeUnlockCount() async {
        do {
            for try await n in env.unlocks.observeCount() {
                unlockedCount = n
            }
        } catch {
            // Contador sin actualizar.
        }
    }

    // MARK: Depuración (-uiScreen)

    private func handleDebugLaunch() async {
        guard !debugHandled, let screen = DebugLaunch.requested else { return }
        debugHandled = true
        switch screen {
        case .resultDemo:
            guard let image = SyntheticImage.blocks(comboId: DebugLaunch.demoComboId, dictionary: env.dictionary) else { return }
            await debugAnalyze(image: image, subject: SubjectOptions(mode: .off)) { path.append(ResultRoute(outcome: $0)) }
        case .explorar(let id):
            path.append(id)
        case .ajustes:
            path.append(AjustesRoute())
        case .resultPeople, .resultPeopleMask, .layersPeople:
            guard let image = DebugLaunch.groupPhoto() else {
                capture = .failed("La foto de grupo de depuración no está en el bundle (solo en Debug).")
                return
            }
            await debugAnalyze(image: image, subject: nil) { outcome in
                path.append(ResultRoute(outcome: outcome, showMask: screen == .resultPeopleMask))
                if screen == .layersPeople {
                    path.append(LayersRoute(outcome: outcome, initialLayer: DebugLaunch.requestedLayer))
                }
            }
        case .layersDemo, .resultDemoPerson:
            let scene = SyntheticPersonScene.make()
            guard let image = scene.image else { return }
            await debugAnalyze(image: image, subject: .default, people: [scene.person]) { outcome in
                path.append(ResultRoute(outcome: outcome))
                if screen == .layersDemo {
                    path.append(LayersRoute(outcome: outcome, initialLayer: DebugLaunch.requestedLayer))
                }
            }
        case .resultDemoPeople, .resultDemoPeopleMask:
            let scene = SyntheticPersonScene.makeTwo()
            guard let image = scene.image else { return }
            await debugAnalyze(image: image, subject: .default, people: scene.people) { outcome in
                path.append(ResultRoute(outcome: outcome, showMask: screen == .resultDemoPeopleMask))
            }
        }
    }

    /// Análisis de un atajo de depuración (scan .manual) y navegación.
    private func debugAnalyze(image: CGImage, subject: SubjectOptions?, people: [PersonInstance]? = nil,
                              then navigate: (ScanOutcome) -> Void) async {
        capture = .working("Demo…")
        do {
            let outcome = try await ScanAnalyzer.run(image: image, source: .manual, subject: subject, people: people, env: env)
            capture = .idle
            navigate(outcome)
        } catch {
            capture = .failed(ErrorText.describe(error))
        }
    }
}

/// Estado de la presentación del escaneo inicial en Hoy.
enum HoyOnboarding {
    /// Tras cerrar la hoja: si el escaneo inicial no se hizo, se marca como saltado.
    static func markDismissed(settings: SettingsRepository) async {
        let done = (try? await settings.bool(.initialScanDone)) ?? false
        if !done {
            try? await settings.setBool(.scanOnboardingSkipped, true)
        }
    }
}

/// Fila de un scan reciente: paleta, top-1, origen, fecha y veredicto.
struct ScanHistoryRow: View {
    @EnvironmentObject private var env: AppEnvironment
    let scan: ScanRecord
    let verdict: FeedbackVerdict?

    var body: some View {
        HStack(spacing: 12) {
            SwatchStrip(colors: scan.palette.compactMap { Color(hex: $0.hex) }, height: 36)
                .frame(width: 96)
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.top1.map { env.dictionary.displayName(id: $0) } ?? "Sin resultado")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            verdictBadge
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let top1 = scan.top1, env.dictionary.curatedName(id: top1) != nil {
            parts.append(WadaDictionary.numberLabel(top1))
        }
        parts.append(sourceLabel)
        parts.append(scan.scannedAt.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }

    private var sourceLabel: String {
        switch scan.source {
        case .camera: "Cámara"
        case .picker: "Foto"
        case .library: "Carrete"
        case .manual: "Manual"
        }
    }

    @ViewBuilder
    private var verdictBadge: some View {
        switch verdict {
        case .yes:
            Image(systemName: "hand.thumbsup.fill").foregroundStyle(.green)
                .accessibilityLabel("Sí, es eso")
        case .no:
            Image(systemName: "hand.thumbsdown.fill").foregroundStyle(.orange)
                .accessibilityLabel("No")
        case nil:
            Image(systemName: "minus.circle").foregroundStyle(.tertiary)
                .accessibilityLabel("Sin veredicto")
        }
    }
}
