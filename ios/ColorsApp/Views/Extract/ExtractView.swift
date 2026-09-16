// Pestaña Extraer (docs/design/DESIGN_SYSTEM.md §5.2 y §6.2; ejemplo del usuario
// «clothing_extractor»): captura ⇄ resultado en la misma pantalla.
//   - Captura: visor con «Elegir foto» (PhotosPicker), «Cámara» (UIImagePickerController) y
//     «Escanear carrete (200 fotos)» (ScanOnboardingView), progreso y errores sobre el visor.
//   - Resultado: `ExtractResultContent` (foto con alfileres, recorte, personas, colores de la
//     ropa, top-3, guardar, copiar hex y capas) con el `ResultViewModel` del análisis.
// El análisis es `ScanAnalyzer.run` (Vision + motor en segundo plano, scan guardado). La
// cabecera (`ExtractHeader`) lleva el emblema y «ChromaSol» con el rótulo «EXTRAER», el sol en
// disco con la acción contextual (escanear carrete en captura, «Nueva foto» en resultado) y el
// avatar del jardín con anillo. Capturas DEBUG: `-uiExtractMotionTime <s>` congela todo el
// movimiento ambiental de la pestaña en ese instante y `-uiExtractReduceMotion 1` fuerza el
// comportamiento de «Reducir movimiento».
// Atajos de depuración que abren esta pestaña (DebugLaunch): `extraer`, `result-demo`,
// `result-people`, `result-people-mask`, `result-demo-person`, `result-demo-people`,
// `result-demo-people-mask`, `layers-demo` y `layers-people` (`-uiLayer n`). Los análisis
// de esos atajos se marcan «Ejemplo».
import SwiftUI
import PhotosUI
import UIKit
import SubjectKit

struct ExtractView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.selectTab) private var selectTab

    @State private var result: ResultViewModel?
    @State private var capture: ExtractCaptureState = .idle
    @State private var pendingImage: CGImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var showCamera = false
    @State private var showScan = false
    @State private var layersRoute: LayersRoute?
    @State private var debugHandled = false
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        if let result {
                            ExtractResultContent(model: result, onOpenLayers: { layersRoute = LayersRoute(outcome: $0) }, toast: $toast)
                                .id(result.outcome.scan.id)
                        } else {
                            ExtractCaptureContent(state: capture, preview: pendingImage,
                                                  onPick: { showPicker = true },
                                                  onCamera: { showCamera = true },
                                                  onScan: { showScan = true })
                        }
                    }
                    .padding(.horizontal, Spacing.margin)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xl)
                    .id("extract.top")
                }
                .scrollIndicators(.hidden)
                // La pila de navegación no propaga el `safeAreaInset` de la barra de pestañas propia:
                // margen para que el final del resultado no quede bajo ella (TabBarClearance, Jardín).
                .tabBarClearance()
                .onChange(of: result?.outcome.scan.id) { _, _ in
                    proxy.scrollTo("extract.top", anchor: .top)
                    #if DEBUG
                    // Capturas: `-uiExtractScroll colors|match|actions|footer` desplaza el resultado a esa sección.
                    if let anchor = ExtractView.debugScrollAnchor {
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(3))
                            proxy.scrollTo(anchor, anchor: anchor == "extract.footer" ? .bottom : .top)
                        }
                    }
                    #endif
                }
            }
            .background(Theme.surface.ignoresSafeArea())
            .modifier(ExtractToastOverlay(toast: toast))
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .toolbar(.hidden, for: .navigationBar)
        }
        .modifier(ExtractDebugMotion())
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images, photoLibrary: .shared())
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
        .fullScreenCover(item: $layersRoute) { route in
            LayersInspectorView(model: LayersInspectorModel(outcome: route.outcome, dictionary: env.dictionary),
                                initialLayer: route.initialLayer)
        }
        .sheet(isPresented: $showScan) {
            ScanOnboardingView(onShowGrid: {
                showScan = false
                selectTab(.rejilla)
            })
            .environmentObject(env)
        }
        .task { await handleDebugLaunch() }
        .accessibilityIdentifier("extraer.root")
    }

    private var header: some View {
        ExtractHeader(isResult: result != nil,
                      onSun: {
                          if result == nil {
                              showScan = true
                          } else {
                              newPhoto()
                          }
                      },
                      onAvatar: { selectTab(.jardin) })
    }

    private func newPhoto() {
        withAnimation(.easeOut(duration: 0.2)) {
            result = nil
            capture = .idle
            pendingImage = nil
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
        pendingImage = image
        capture = .working("Analizando la ropa…")
        do {
            let outcome = try await ScanAnalyzer.run(image: image, source: source, assetLocalId: assetLocalId, env: env)
            show(outcome)
        } catch {
            capture = .failed(ErrorText.describe(error))
        }
    }

    private func show(_ outcome: ScanOutcome, showMask: Bool = false, example: Bool = false) {
        let model = ResultViewModel(outcome: outcome, env: env)
        model.showMask = showMask
        model.isExample = example
        capture = .idle
        pendingImage = nil
        result = model
    }

    // MARK: Depuración (-uiScreen)

    private func handleDebugLaunch() async {
        #if DEBUG
        guard !debugHandled, let screen = DebugLaunch.requested else { return }
        debugHandled = true
        let layer = DebugLaunch.requestedLayer
        switch screen {
        case .resultDemo:
            guard let image = SyntheticImage.blocks(comboId: DebugLaunch.demoComboId, dictionary: env.dictionary) else { return }
            await debugAnalyze(image: image, subject: SubjectOptions(mode: .off)) { show($0, example: true) }
        case .resultPeople, .resultPeopleMask, .layersPeople:
            guard let image = DebugLaunch.groupPhoto() else {
                capture = .failed("La foto de grupo de depuración no está en el bundle (solo en Debug).")
                return
            }
            await debugAnalyze(image: image, subject: nil) { outcome in
                show(outcome, showMask: screen == .resultPeopleMask, example: true)
                if screen == .layersPeople { layersRoute = LayersRoute(outcome: outcome, initialLayer: layer) }
            }
        case .layersDemo, .resultDemoPerson:
            let scene = SyntheticPersonScene.make()
            guard let image = scene.image else { return }
            await debugAnalyze(image: image, subject: .default, people: [scene.person]) { outcome in
                show(outcome, example: true)
                if screen == .layersDemo { layersRoute = LayersRoute(outcome: outcome, initialLayer: layer) }
            }
        case .resultDemoPeople, .resultDemoPeopleMask:
            let scene = SyntheticPersonScene.makeTwo()
            guard let image = scene.image else { return }
            await debugAnalyze(image: image, subject: .default, people: scene.people) { outcome in
                show(outcome, showMask: screen == .resultDemoPeopleMask, example: true)
            }
        default:
            break
        }
        #endif
    }

    /// Análisis de un atajo de depuración (scan `.manual`, marcado «Ejemplo» en pantalla).
    private func debugAnalyze(image: CGImage, subject: SubjectOptions?, people: [PersonInstance]? = nil,
                              then navigate: (ScanOutcome) -> Void) async {
        pendingImage = image
        capture = .working("Ejemplo: analizando…")
        do {
            let outcome = try await ScanAnalyzer.run(image: image, source: .manual, subject: subject, people: people, env: env)
            navigate(outcome)
        } catch {
            capture = .failed(ErrorText.describe(error))
        }
    }
}

/// Capturas deterministas (solo DEBUG): tiempo congelado y «Reducir movimiento» forzado.
private struct ExtractDebugMotion: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let time = args.firstIndex(of: "-uiExtractMotionTime").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil }
        let reduce = args.firstIndex(of: "-uiExtractReduceMotion").map { $0 + 1 < args.count && args[$0 + 1] == "1" } ?? false
        content
            .motionTime(time)
            .forceReducedMotion(reduce)
            .environment(\.brandFrozenTime, time)
            .environment(\.brandReduceMotionOverride, reduce ? true : nil)
        #else
        content
        #endif
    }
}

#if DEBUG
extension ExtractView {
    /// Sección a la que desplazar el resultado en capturas (`-uiExtractScroll colors|match|actions|footer`).
    static var debugScrollAnchor: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiExtractScroll"), i + 1 < args.count else { return nil }
        return "extract.\(args[i + 1])"
    }
}
#endif

/// Estado del visor de captura.
enum ExtractCaptureState: Equatable, Sendable {
    case idle
    case working(String)
    case failed(String)

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }
}
