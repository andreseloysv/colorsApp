// Flujo de una captura (PLAN §7.2 + recorte de sujeto, ADR-010): rasterizar UNA
// vez (EngineBridge, sRGB ≤ 1024 px), recorte de sujeto con SubjectKit sobre ese
// mismo buffer RGBA (Vision detecta personas, pose y caras; el motor recorta la
// ropa y excluye la piel), ce_analyze con la máscara resultante y las capas de
// depuración del motor, todo en un Task.detached con un ce_ctx por llamada;
// después se guarda el scan (ScanRepository) con los datos del recorte y se
// registran los tiempos (TimingLog: total, Vision, máscara y motor).
// Lo usan Extraer (picker/cámara), los atajos de depuración, el Feed (reanálisis) y los tests.
import Foundation
import CoreGraphics
import ColorEngine
import SubjectKit

/// Tiempos de un análisis, en milisegundos.
struct AnalysisTimings: Equatable, Sendable {
    /// Rasterizado sRGB (0 si se reutiliza el raster).
    var rasterMs = 0.0
    /// Detección de Vision (instancias, pose, caras). 0 con el modo off o al reutilizar personas.
    var visionMs = 0.0
    /// Cadena de máscaras (regiones, cabeza, piel y cobertura: motor C).
    var maskMs = 0.0
    /// Paleta + match + capas de depuración (motor C).
    var engineMs = 0.0
    /// Total de pared.
    var totalMs = 0.0

    static let zero = AnalysisTimings()
}

/// Resultado completo de una captura: imagen vertical (≤ 1024 px), raster que
/// vio el motor, recorte de sujeto, análisis con sus capas, scan persistido y tiempos.
struct ScanOutcome: Identifiable, Hashable, Sendable {
    let image: CGImage
    let raster: EngineBridge.Raster
    let result: AnalysisResult
    let scan: ScanRecord
    /// Opciones con las que se calculó la máscara (modo, región, piel, persona elegida).
    let subjectOptions: SubjectOptions
    /// Personas, pasos, máscara y capas de SubjectKit (Vision se ejecuta una sola vez por foto).
    let subject: SubjectMaskResult
    /// Capas de depuración del motor del mismo análisis (nil en outcomes construidos a mano).
    let debug: PaletteDebugLayers?
    let timings: AnalysisTimings

    init(image: CGImage, raster: EngineBridge.Raster, result: AnalysisResult, scan: ScanRecord,
         subjectOptions: SubjectOptions = SubjectOptions(mode: .off),
         subject: SubjectMaskResult? = nil, debug: PaletteDebugLayers? = nil, timings: AnalysisTimings = .zero) {
        self.image = image
        self.raster = raster
        self.result = result
        self.scan = scan
        self.subjectOptions = subjectOptions
        self.subject = subject ?? ScanAnalyzer.emptySubject(width: raster.width, height: raster.height, steps: [.none])
        self.debug = debug
        self.timings = timings
    }

    var id: String { scan.id }

    /// Se aplicó una máscara de sujeto.
    var maskApplied: Bool { subject.mask != nil }

    /// Aviso con los pasos del recorte ("Solo ropa · piel excluida"...).
    var maskNotice: MaskStepsText.Notice { MaskStepsText.notice(options: subjectOptions, result: subject) }

    var elapsedMs: Int { Int(timings.totalMs.rounded()) }

    static func == (lhs: ScanOutcome, rhs: ScanOutcome) -> Bool { lhs.scan.id == rhs.scan.id }

    func hash(into hasher: inout Hasher) { hasher.combine(scan.id) }
}

enum ScanAnalyzer {
    /// Parte pura del análisis (sin base de datos).
    struct Analysis: Sendable {
        let raster: EngineBridge.Raster
        let options: SubjectOptions
        let subject: SubjectMaskResult
        let result: AnalysisResult
        let debug: PaletteDebugLayers?
        let timings: AnalysisTimings

        var maskApplied: Bool { subject.mask != nil }
        var elapsedMs: Int { Int(timings.totalMs.rounded()) }
    }

    /// Rasteriza, recorta el sujeto y analiza. `people` nil = detectar con Vision
    /// (si el modo no es off); un array = reutilizar esas personas sin Vision.
    /// `layers` = calcular también las capas de depuración (mismo ce_analyze).
    /// Síncrono y sin estado compartido: llamar desde `Task.detached`.
    static func analyze(image: CGImage, subject options: SubjectOptions, people: [PersonInstance]? = nil,
                        layers: Bool = true, topK: Int = 3) throws -> Analysis {
        let clock = Clock()
        let raster = try EngineBridge.rasterize(image)
        let rasterMs = clock.ms
        var analysis = try analyze(raster: raster, image: image, subject: options, people: people,
                                   layers: layers, topK: topK)
        var timings = analysis.timings
        timings.rasterMs = rasterMs
        timings.totalMs = clock.ms
        analysis = Analysis(raster: raster, options: options, subject: analysis.subject, result: analysis.result,
                            debug: analysis.debug, timings: timings)
        return analysis
    }

    /// Igual que `analyze(image:...)` sobre un raster ya calculado: el mismo buffer
    /// RGBA va a SubjectKit y al motor. `image` solo se usa si hay que ejecutar Vision.
    static func analyze(raster: EngineBridge.Raster, image: CGImage?, subject options: SubjectOptions,
                        people: [PersonInstance]?, layers: Bool = true, topK: Int = 3) throws -> Analysis {
        let clock = Clock()
        var timings = AnalysisTimings()
        let subject: SubjectMaskResult = try raster.pixels.withUnsafeBufferPointer { px in
            if let people {
                return try SubjectExtractor.mask(people: people, rgba: px, width: raster.width, height: raster.height,
                                                 stride: raster.stride, options: options)
            }
            if let image {
                return try SubjectExtractor.compute(image: image, rgba: px, width: raster.width, height: raster.height,
                                                    stride: raster.stride, options: options)
            }
            return try SubjectExtractor.mask(people: [], rgba: px, width: raster.width, height: raster.height,
                                             stride: raster.stride, options: options)
        }
        let subjectMs = clock.ms
        timings.maskMs = subject.timings["mask"] ?? 0
        timings.visionMs = max(0, subjectMs - timings.maskMs)
        let engineStart = clock.ms
        let result: AnalysisResult
        var debug: PaletteDebugLayers?
        if layers {
            let d = try EngineBridge.analyzeWithLayers(raster: raster, matchOptions: EngineBridge.appMatchOptions, topK: topK, mask: subject.mask)
            result = d.analysis
            debug = d
        } else {
            result = try EngineBridge.analyze(raster: raster, matchOptions: EngineBridge.appMatchOptions, topK: topK, mask: subject.mask)
        }
        timings.engineMs = clock.ms - engineStart
        timings.totalMs = clock.ms
        return Analysis(raster: raster, options: options, subject: subject, result: result, debug: debug,
                        timings: timings)
    }

    /// Flujo completo: análisis en segundo plano (userInitiated), scan guardado
    /// con los datos del recorte y tiempos registrados. `subject` nil = leer los
    /// ajustes (`subject_mode`, `region_mode`, `adaptive_skin`).
    /// `photoStore`: copia de la foto para el Feed y el Jardín (cámara, foto elegida y
    /// manual; las del carrete se leen de PhotoKit). nil = no guardar.
    @MainActor
    static func run(image: CGImage, source: ScanSource, assetLocalId: String? = nil, subject: SubjectOptions? = nil,
                    people: [PersonInstance]? = nil, env: AppEnvironment, timing: TimingLog = .shared,
                    now: Date = Date(), photoStore: ScanPhotoStore? = .shared) async throws -> ScanOutcome {
        let options: SubjectOptions
        if let subject {
            options = subject
        } else {
            options = ((try? await env.settings.subjectSettings()) ?? .default).subjectOptions
        }
        let analysis = try await Task.detached(priority: .userInitiated) {
            try analyze(image: image, subject: options, people: people)
        }.value
        let info = ScanSubjectInfo(options: options, result: analysis.subject)
        let scan = ScanRecord.make(from: analysis.result, source: source, assetLocalId: assetLocalId, subject: info,
                                   now: now)
        if let photoStore, source != .library {
            // Antes de publicar el scan: el Feed lo muestra en cuanto aparece en la base de datos.
            let scanId = scan.id
            try? await Task.detached(priority: .userInitiated) { try photoStore.save(image, scanId: scanId) }.value
        }
        try await env.scans.insert(scan)
        record(analysis.timings, label: "analyze.\(source.rawValue)", timing: timing, now: now)
        return ScanOutcome(image: image, raster: analysis.raster, result: analysis.result, scan: scan,
                           subjectOptions: options, subject: analysis.subject, debug: analysis.debug,
                           timings: analysis.timings)
    }

    /// `label` total y `label.vision`, `label.mask`, `label.engine` (times.txt del diagnóstico).
    static func record(_ t: AnalysisTimings, label: String, timing: TimingLog, now: Date) {
        timing.record(label, ms: Int(t.totalMs.rounded()), now: now)
        timing.record("\(label).vision", ms: Int(t.visionMs.rounded()), now: now)
        timing.record("\(label).mask", ms: Int(t.maskMs.rounded()), now: now)
        timing.record("\(label).engine", ms: Int(t.engineMs.rounded()), now: now)
    }

    /// Resultado de recorte vacío (sin personas ni máscara) para outcomes sin SubjectKit.
    static func emptySubject(width: Int, height: Int, steps: [MaskFallback]) -> SubjectMaskResult {
        let empty = [UInt8](repeating: 0, count: max(0, width) * max(0, height))
        let layers = SubjectLayers(width: width, height: height, persons: [], allPeopleOverlay: empty, finalMask: nil)
        return SubjectMaskResult(width: width, height: height, people: [], chosenIndex: nil, mask: nil, steps: steps,
                                 timings: [:], maskCoverage: 0, layers: layers)
    }

    /// Cronómetro monotónico en milisegundos.
    struct Clock {
        private let start = DispatchTime.now().uptimeNanoseconds
        var ms: Double { Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 }
    }
}
