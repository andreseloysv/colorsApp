// Datos de EJEMPLO del Jardín, solo en DEBUG (capturas y verificación visual):
//   xcrun simctl launch <udid> com.andreseloy.colorsapp -uiScreen jardin-demo
//   (mientras DebugLaunch no mapee `jardin-demo` a la pestaña: -uiScreen jardin -uiGardenDemo 1)
// Opciones: `-uiGardenSegment fotos|guardadas|colecciones`, `-uiGardenPage ajustes|acerca|scan|wrapped`,
// `-uiGardenScroll segmento|cosechas|estudio`,
// `-uiGardenEmpty 1` (Jardín vacío). Todo vive en una base de datos EN MEMORIA y un
// GardenStore sin fichero: nada se escribe en la base de datos, el almacén de fotos ni el
// Jardín reales, y la pantalla lo avisa («Datos de ejemplo») y marca cada cosecha «Ejemplo».
// Las paletas y combinaciones son las que calcula el motor sobre imágenes de Debug: la foto
// de grupo embebida (harness/people, CC0), escenas sintéticas con personas y bloques con los
// colores exactos de combinaciones de Wada.
#if DEBUG
import SwiftUI
import SubjectKit

enum GardenDemoLaunch {
    static let screenValue = "jardin-demo"
    static let demoArgument = "-uiGardenDemo"
    static let segmentArgument = "-uiGardenSegment"
    static let pageArgument = "-uiGardenPage"
    static let emptyArgument = "-uiGardenEmpty"

    static var isRequested: Bool {
        isRequested(in: ProcessInfo.processInfo.arguments)
    }

    static func isRequested(in args: [String]) -> Bool {
        if let i = args.firstIndex(of: "-uiScreen"), i + 1 < args.count, args[i + 1] == screenValue { return true }
        return value(after: demoArgument, in: args) == "1"
    }

    static var segment: GardenModel.Segment {
        value(after: segmentArgument, in: ProcessInfo.processInfo.arguments).flatMap(GardenModel.Segment.init(rawValue:)) ?? .fotos
    }

    /// Pantalla encima del Jardín: «ajustes», «scan» o «wrapped».
    static var page: String? { value(after: pageArgument, in: ProcessInfo.processInfo.arguments) }

    /// Desplazamiento inicial para capturas: «segmento», «cosechas» o «estudio».
    static var scroll: String? { value(after: "-uiGardenScroll", in: ProcessInfo.processInfo.arguments) }

    static var isEmpty: Bool { value(after: emptyArgument, in: ProcessInfo.processInfo.arguments) == "1" }

    static func value(after argument: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: argument), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

/// Siembra el entorno de ejemplo y muestra el Jardín sobre él.
struct GardenDemoHost: View {
    let base: AppEnvironment
    var onOpenGrid: ((Int?) -> Void)?
    var onOpenCombo: ((Int) -> Void)?

    @State private var demo: GardenDemo.Seeded?
    @State private var failure: String?
    @State private var showWrapped = false

    var body: some View {
        Group {
            if let demo {
                GardenScreen(store: demo.store, photos: demo.photos, isExample: true, initialSegment: GardenDemoLaunch.segment,
                             onOpenGrid: onOpenGrid, onOpenCombo: onOpenCombo)
                    .environmentObject(demo.env)
                    .sheet(isPresented: $showWrapped) {
                        NavigationStack {
                            WrappedSummaryView(summary: demo.summary, dictionary: demo.env.dictionary,
                                               totalCombos: demo.env.comboCount, onShowGrid: { showWrapped = false })
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        Button("Cerrar") { showWrapped = false }
                                    }
                                }
                        }
                    }
            } else {
                VStack(spacing: Spacing.md) {
                    if let failure {
                        Text(failure).textRole(.bodyMD).foregroundStyle(Theme.error)
                    } else {
                        ProgressView().tint(Theme.primary)
                        Text("Sembrando datos de ejemplo…").textRole(.labelLG).foregroundStyle(Theme.onSurfaceVariant)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.surface.ignoresSafeArea())
            }
        }
        .task {
            guard demo == nil else { return }
            do {
                demo = try await GardenDemo.seed(dictionary: base.dictionary, launches: base.launches,
                                                 empty: GardenDemoLaunch.isEmpty)
                if GardenDemoLaunch.page == "wrapped" {
                    try? await Task.sleep(for: .milliseconds(400))
                    showWrapped = true
                }
            } catch {
                failure = String(describing: error)
            }
        }
    }
}

enum GardenDemo {
    struct Seeded {
        let env: AppEnvironment
        let store: GardenStore
        let photos: GardenPhotos
        /// Resumen de escaneo del carrete construido con las cosechas de ejemplo.
        let summary: ScanSummary
    }

    /// Una cosecha de ejemplo: imagen, recorte y cuándo/cómo se analizó.
    private struct Sample: Sendable {
        let image: CGImage
        let subject: SubjectOptions
        let people: [PersonInstance]?
        let source: ScanSource
        let daysAgo: Double
        let verdict: FeedbackVerdict?
        let saved: Bool
    }

    /// Combinaciones desbloqueadas de ejemplo además de los top-1 (tamaños 2, 3 y 4).
    static let extraUnlocks = [12, 27, 44, 67, 69, 101, 152, 160, 199, 222, 227, 241, 254, 255, 270, 299, 301, 320, 337]
    /// Combinaciones guardadas de ejemplo.
    static let savedCombos = [337, 254]

    @MainActor
    static func seed(dictionary: WadaDictionary, launches: Int, empty: Bool = false, now: Date = Date()) async throws -> Seeded {
        let env = AppEnvironment(dictionary: dictionary, database: try AppDatabase.inMemory(), scanRunner: NoopScanRunner(),
                                 launches: launches)
        let store = GardenStore(url: nil)
        let photos = GardenPhotos()
        guard !empty else {
            return Seeded(env: env, store: store, photos: photos, summary: .empty(startedAt: now, finishedAt: now))
        }
        var samples: [Sample] = []
        let people = SubjectSettings.default.subjectOptions
        if let group = DebugLaunch.groupPhoto() {
            samples.append(Sample(image: group, subject: people, people: nil, source: .library, daysAgo: 0.05,
                                  verdict: .yes, saved: true))
        }
        let one = SyntheticPersonScene.make()
        if let image = one.image {
            samples.append(Sample(image: image, subject: people, people: [one.person], source: .camera, daysAgo: 1.1,
                                  verdict: nil, saved: false))
        }
        let two = SyntheticPersonScene.makeTwo()
        if let image = two.image {
            samples.append(Sample(image: image, subject: people, people: two.people, source: .picker, daysAgo: 3.2,
                                  verdict: .no, saved: true))
        }
        for (i, combo) in [27, 152, 254, 69].enumerated() {
            if let image = SyntheticImage.blocks(comboId: combo, dictionary: dictionary, size: 256) {
                samples.append(Sample(image: image, subject: SubjectOptions(mode: .off), people: nil, source: .library,
                                      daysAgo: 5.4 + Double(i) * 4, verdict: i < 2 ? .yes : nil, saved: false))
            }
        }

        var topCombos: [Int: Int] = [:]
        var firstTop: [Int] = []
        for sample in samples {
            let analysis = try await Task.detached(priority: .userInitiated) {
                try ScanAnalyzer.analyze(image: sample.image, subject: sample.subject, people: sample.people, layers: false)
            }.value
            let date = now.addingTimeInterval(-sample.daysAgo * 86_400)
            let info = ScanSubjectInfo(options: sample.subject, result: analysis.subject)
            let scan = ScanRecord.make(from: analysis.result, source: sample.source, subject: info, now: date)
            try await env.scans.insert(scan)
            photos.pin(GardenPhotos.downscaled(sample.image, maxSide: 1080), scanId: scan.id)
            if let verdict = sample.verdict {
                try await env.feedback.record(scanId: scan.id, verdict: verdict, at: date.addingTimeInterval(60))
            }
            if sample.saved {
                store.save(scanId: scan.id, now: date.addingTimeInterval(120))
            }
            if let top1 = scan.top1 {
                topCombos[top1, default: 0] += 1
                if !analysis.result.ambiguous {
                    try await env.unlocks.unlock(comboId: top1, source: sample.source, scanId: scan.id, at: date)
                    firstTop.append(top1)
                }
            }
        }
        for (i, id) in extraUnlocks.enumerated() {
            try await env.unlocks.unlock(comboId: id, source: .manual, at: now.addingTimeInterval(-Double(i + 2) * 86_400 * 1.7))
        }
        for id in savedCombos {
            store.toggle(comboId: id, now: now.addingTimeInterval(-3600))
        }
        let total = try await env.unlocks.count()
        let top = topCombos.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { ComboCount(comboId: $0.key, count: $0.value) }
        let colorCounts = colorCounts(topCombos: top, dictionary: dictionary)
        let summary = ScanSummary(scanned: samples.count, skipped: 2, failed: 0,
                                  newUnlocks: Array(Set(firstTop + extraUnlocks.prefix(6))).sorted(),
                                  totalUnlocked: total, topCombos: top,
                                  startedAt: now.addingTimeInterval(-42.4), finishedAt: now,
                                  topColors: colorCounts, signatureColorIndex: colorCounts.first?.colorIndex)
        return Seeded(env: env, store: store, photos: photos, summary: summary)
    }

    /// Colores del diccionario más frecuentes en los top-1 (como el resumen real del escaneo).
    private static func colorCounts(topCombos: [ComboCount], dictionary: WadaDictionary) -> [ColorCount] {
        var counts: [Int: Int] = [:]
        for entry in topCombos {
            for index in dictionary.combo(id: entry.comboId)?.colors ?? [] {
                counts[index, default: 0] += entry.count
            }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { ColorCount(colorIndex: $0.key, count: $0.value) }
    }
}
#endif
