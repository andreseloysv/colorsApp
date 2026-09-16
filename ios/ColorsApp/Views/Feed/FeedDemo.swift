// Datos de EJEMPLO del Feed (solo DEBUG): `-uiScreen feed-demo` arranca la app con una
// base de datos EN MEMORIA (nada toca la base de datos real del teléfono), fotos en un
// directorio temporal y un Jardín en memoria, y siembra tres análisis reales del motor:
// la foto de grupo embebida en Debug (harness/people/06_group_courier_street.png, CC0)
// sin recorte y las escenas sintéticas de una y dos personas (SyntheticPersonScene, con
// la cadena real de máscaras del motor). Todas se marcan «Ejemplo» en la cabecera.
// `-uiScreen feed-empty` usa la misma base en memoria sin sembrar (estado vacío).
#if DEBUG
import SwiftUI
import SubjectKit

struct FeedDemoRoot: View {
    let base: AppEnvironment
    let seeded: Bool

    @State private var demo: FeedDemo?

    var body: some View {
        Group {
            if let demo {
                RootTabContainer(initialTab: .feed, feed: {
                    FeedView(garden: demo.garden, photoStore: demo.photos, exampleIds: demo.exampleIds)
                })
                .environmentObject(demo.env)
            } else {
                ProgressView("Preparando ejemplos…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.surface.ignoresSafeArea())
            }
        }
        .task {
            guard demo == nil else { return }
            demo = await FeedDemo.make(seeded: seeded) ?? FeedDemo(env: base, garden: .shared, photos: .shared, exampleIds: [])
        }
    }
}

@MainActor
struct FeedDemo {
    let env: AppEnvironment
    let garden: GardenStore
    let photos: ScanPhotoStore
    let exampleIds: Set<String>

    static func make(seeded: Bool, now: Date = Date()) async -> FeedDemo? {
        guard let env = try? AppEnvironment.forTesting(bundle: .main) else { return nil }
        // Escaneo del carrete real pero sobre la base en memoria (solo al pulsarlo).
        _ = env.installPhotoKitScanRunner()
        let photos = ScanPhotoStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("feed-demo-photos", isDirectory: true))
        photos.removeAll()
        let garden = GardenStore(url: nil)
        // Jardín «sin visitar» en los ejemplos: el avatar muestra la insignia de combinaciones nuevas.
        UserDefaults.standard.removeObject(forKey: FeedView.gardenSeenDemoKey)
        guard seeded else { return FeedDemo(env: env, garden: garden, photos: photos, exampleIds: []) }
        let timing = TimingLog(url: FileManager.default.temporaryDirectory.appendingPathComponent("feed-demo-times.txt"))
        var ids: [String] = []

        func add(_ image: CGImage?, source: ScanSource, subject: SubjectOptions, people: [PersonInstance]?,
                 hoursAgo: Double) async -> ScanOutcome? {
            guard let image else { return nil }
            guard let outcome = try? await ScanAnalyzer.run(image: image, source: source, subject: subject, people: people,
                                                            env: env, timing: timing,
                                                            now: now.addingTimeInterval(-hoursAgo * 3600), photoStore: nil)
            else { return nil }
            try? photos.save(image, scanId: outcome.scan.id)
            ids.append(outcome.scan.id)
            return outcome
        }

        // 1) Foto de grupo real (CC0) sin recorte: foto completa, guardada y con «Sí, es eso».
        if let group = await add(DebugLaunch.groupPhoto(), source: .picker, subject: SubjectOptions(mode: .off), people: nil,
                                 hoursAgo: 1.2) {
            _ = try? await env.feedback.record(scanId: group.scan.id, verdict: .yes)
            garden.save(scanId: group.scan.id)
            if let top = group.scan.top1 { _ = try? await env.unlocks.unlock(comboId: top, source: .picker, scanId: group.scan.id) }
        }
        // 2) Escena sintética de una persona: solo ropa con pose y piel adaptativa, sin votar.
        let single = SyntheticPersonScene.make()
        _ = await add(single.image, source: .camera, subject: .default, people: [single.person], hoursAgo: 26)
        // 3) Dos personas, todas: votada «No».
        let two = SyntheticPersonScene.makeTwo()
        var all = SubjectOptions.default
        all.mode = .allPeople
        if let pair = await add(two.image, source: .library, subject: all, people: two.people, hoursAgo: 75) {
            _ = try? await env.feedback.record(scanId: pair.scan.id, verdict: .no)
        }
        // Algunas combinaciones en la rejilla (incluida la del día) para el estado «En tu rejilla».
        _ = try? await env.unlocks.unlock(comboIds: [DayPick.comboId(for: now), 12, 67], source: .manual)
        return FeedDemo(env: env, garden: garden, photos: photos, exampleIds: Set(ids))
    }
}
#endif
