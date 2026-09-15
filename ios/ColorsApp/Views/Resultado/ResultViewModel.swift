// Modelo de Resultado (PLAN §7.3 + recorte de sujeto): feedback ("sí, es eso" /
// "no" -> tabla feedback + copia PNG sRGB de 256 px del raster y sus máscaras,
// JSON y capas para el diagnóstico), desbloqueo (tabla unlocks con el origen del
// scan), tarjeta compartible, selector de persona (re-analiza con las personas
// que ya detectó Vision, sin volver a ejecutarlo, y actualiza el scan), "Ver
// máscara" e inspector de capas del último análisis.
import Foundation
import Combine
import CoreGraphics
import UIKit
import ColorEngine
import SubjectKit

@MainActor
final class ResultViewModel: ObservableObject {
    enum UnlockState: Equatable {
        case unknown
        case locked
        case unlockedNow
        case alreadyUnlocked
    }

    /// Opción de la fila "Personas".
    enum PersonChoice: Hashable, Sendable {
        /// Todas las personas (allPeople).
        case all
        /// Persona `index` de `subject.people` (selectedPerson).
        case person(Int)
    }

    /// Último análisis (cambia al elegir otra persona).
    @Published private(set) var outcome: ScanOutcome
    let dictionary: WadaDictionary
    private let feedbackRepository: FeedbackRepository
    private let unlockRepository: UnlockRepository
    private let scanRepository: ScanRepository
    private let imageStore: FeedbackImageStore
    private let timing: TimingLog

    @Published private(set) var verdict: FeedbackVerdict?
    @Published private(set) var unlockState: UnlockState = .unknown
    @Published private(set) var busy = false
    /// Re-análisis en curso tras elegir persona.
    @Published private(set) var reanalyzing = false
    @Published var errorMessage: String?
    /// "Ver máscara": superpone la máscara usada a la foto.
    @Published var showMask = false
    /// Miniaturas de cada persona (recorte del raster por su bbox), en el orden de `subject.people`.
    @Published private(set) var personThumbnails: [CGImage] = []
    /// Capa oscura fuera de la máscara del análisis actual (nil sin máscara).
    @Published private(set) var maskOverlay: CGImage?
    /// Tarea en segundo plano de la copia del diagnóstico (tests).
    private(set) var feedbackImageTask: Task<Void, Never>?

    init(outcome: ScanOutcome, env: AppEnvironment, imageStore: FeedbackImageStore = .shared, timing: TimingLog = .shared) {
        self.outcome = outcome
        self.dictionary = env.dictionary
        self.feedbackRepository = env.feedback
        self.unlockRepository = env.unlocks
        self.scanRepository = env.scans
        self.imageStore = imageStore
        self.timing = timing
    }

    // MARK: Derivados

    var hits: [Hit] { outcome.result.hits }
    var topHit: Hit? { hits.first }
    var top1Combo: WadaCombo? { topHit.flatMap { dictionary.combo(id: $0.comboId) } }
    var otherHits: [Hit] { Array(hits.dropFirst()) }
    var people: [PersonInstance] { outcome.subject.people }

    var title: String {
        topHit.map { dictionary.displayName(id: $0.comboId) } ?? "Sin resultado"
    }

    var shareTitle: String {
        topHit.map { "colorsApp · Wada \(WadaDictionary.numberLabel($0.comboId))" } ?? "colorsApp"
    }

    /// "Entre Nº 012 y Nº 178" cuando el motor marca el resultado como ambiguo.
    var ambiguityText: String? {
        guard outcome.result.ambiguous, hits.count >= 2 else { return nil }
        return "Entre \(dictionary.displayName(id: hits[0].comboId)) y \(dictionary.displayName(id: hits[1].comboId))"
    }

    /// Aviso con los pasos del recorte.
    var maskNotice: MaskStepsText.Notice { outcome.maskNotice }

    /// Fila "Personas": solo con dos o más personas.
    var showsPeopleRow: Bool { people.count >= 2 }

    /// Persona (o "Todas") del análisis actual.
    var currentChoice: PersonChoice {
        if outcome.subjectOptions.mode == .allPeople { return .all }
        return .person(outcome.subject.chosenIndex ?? 0)
    }

    /// Cambiar de persona reescribe el scan: no se permite tras votar (el
    /// veredicto se refiere a lo que se vio) ni con otra acción en curso.
    var canChangePerson: Bool { verdict == nil && !busy && !reanalyzing }

    func comboHeadline(_ combo: WadaCombo) -> String {
        if dictionary.curatedName(id: combo.id) != nil {
            return "\(WadaDictionary.numberLabel(combo.id)) · \(comboSubtitle(combo))"
        }
        return comboSubtitle(combo)
    }

    // MARK: Acciones

    /// Estado persistido (último veredicto, desbloqueo) y miniaturas/máscara del análisis.
    func load() async {
        await refreshDerivedImages()
        do {
            verdict = try await feedbackRepository.latest(forScan: outcome.scan.id)?.verdict
            try await refreshUnlockState()
        } catch {
            errorMessage = ErrorText.describe(error)
        }
    }

    private func refreshUnlockState() async throws {
        if let top = topHit {
            unlockState = try await unlockRepository.isUnlocked(comboId: top.comboId) ? .alreadyUnlocked : .locked
        } else {
            unlockState = .locked
        }
    }

    func vote(_ newVerdict: FeedbackVerdict) async {
        guard verdict == nil, !busy, !reanalyzing else { return }
        busy = true
        defer { busy = false }
        do {
            try await feedbackRepository.record(scanId: outcome.scan.id, verdict: newVerdict)
            verdict = newVerdict
            saveFeedbackImage()
        } catch {
            errorMessage = ErrorText.describe(error)
        }
    }

    func unlock() async {
        guard let top = topHit, !busy, !reanalyzing else { return }
        busy = true
        defer { busy = false }
        do {
            let fresh = try await unlockRepository.unlock(comboId: top.comboId, source: outcome.scan.source,
                                                          assetLocalId: outcome.scan.assetLocalId,
                                                          scanId: outcome.scan.id)
            unlockState = fresh ? .unlockedNow : .alreadyUnlocked
        } catch {
            errorMessage = ErrorText.describe(error)
        }
    }

    /// Re-analiza con otra persona (o todas) reutilizando `subject.people`: sin
    /// Vision, solo la cadena de máscaras y el motor sobre el mismo raster. Guarda
    /// el scan actualizado (person_index, pasos, resultado) y recalcula las capas.
    func choose(_ choice: PersonChoice) async {
        guard canChangePerson, choice != currentChoice else { return }
        var options = outcome.subjectOptions
        switch choice {
        case .all:
            options.mode = .allPeople
            options.selectedIndex = nil
        case .person(let index):
            guard index >= 0, index < people.count else { return }
            options.mode = .selectedPerson
            options.selectedIndex = index
        }
        reanalyzing = true
        defer { reanalyzing = false }
        let current = outcome
        let opts = options
        do {
            let analysis = try await Task.detached(priority: .userInitiated) {
                try ScanAnalyzer.analyze(raster: current.raster, image: nil, subject: opts, people: current.subject.people)
            }.value
            let info = ScanSubjectInfo(options: opts, result: analysis.subject)
            let scan = current.scan.updated(with: analysis.result, subject: info)
            try await scanRepository.update(scan)
            ScanAnalyzer.record(analysis.timings, label: "reanalyze.person", timing: timing, now: Date())
            outcome = ScanOutcome(image: current.image, raster: current.raster, result: analysis.result, scan: scan,
                                  subjectOptions: opts, subject: analysis.subject, debug: analysis.debug,
                                  timings: analysis.timings)
            await refreshDerivedImages()
            try await refreshUnlockState()
        } catch {
            errorMessage = ErrorText.describe(error)
        }
    }

    func makeShareImage() -> UIImage? {
        ShareCardRenderer.render(ShareCardRenderer.card(for: outcome, dictionary: dictionary))
    }

    /// Miniaturas de personas y capa de "Ver máscara" del análisis actual (en segundo plano).
    private func refreshDerivedImages() async {
        let o = outcome
        let (thumbnails, overlay) = await Task.detached(priority: .userInitiated) { () -> ([CGImage], CGImage?) in
            let base = PNGCoding.cgImage(from: o.raster)
            let thumbs = base.map { image in o.subject.people.compactMap { LayerBitmaps.crop(image, bbox: $0.bbox) } } ?? []
            let overlay = o.subject.mask.flatMap { LayerBitmaps.dimOutside(mask: $0, width: o.raster.width, height: o.raster.height) }
            return (thumbs, overlay)
        }.value
        guard outcome.scan.rev == o.scan.rev else { return }
        personThumbnails = thumbnails
        maskOverlay = overlay
    }

    /// Copia PNG sRGB de 256 px del raster que vio el motor y sus extras
    /// (máscaras de las variantes, JSON del recorte, label map, debug.json) para
    /// el diagnóstico. Lo mejor que se pueda: un fallo aquí no afecta al veredicto.
    private func saveFeedbackImage() {
        guard let cg = PNGCoding.cgImage(from: outcome.raster) else { return }
        let store = imageStore
        let input = DiagnosticsSubject.Input(outcome: outcome)
        let scanId = outcome.scan.id
        feedbackImageTask = Task.detached(priority: .utility) {
            guard let png = try? PNGCoding.srgbPNG(from: cg, maxSide: DiagnosticsSubject.exportSide) else { return }
            try? store.save(png: png, scanId: scanId)
            if let extras = try? DiagnosticsSubject.extras(input) {
                try? store.save(extras: extras, scanId: scanId)
            }
        }
    }
}
