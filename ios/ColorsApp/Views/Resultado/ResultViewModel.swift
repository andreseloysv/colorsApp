// Modelo del resultado de Extraer (PLAN §7.3 + recorte de sujeto; docs/design/DESIGN_SYSTEM.md
// §5.2): feedback ("sí, es eso" / "no" -> tabla feedback + copia PNG sRGB de 256 px del
// raster y sus máscaras, JSON y capas para el diagnóstico), desbloqueo (tabla unlocks con
// el origen del scan), tarjeta compartible, selector de persona (re-analiza con las
// personas que ya detectó Vision, sin volver a ejecutarlo, y actualiza el scan), "Ver
// máscara", alfileres en el centroide de los píxeles de cada swatch (label map del motor)
// con el nombre del color de Wada más cercano, aislar un swatch sobre la foto, «Guardar en
// el jardín» (GardenStore local), «Copiar hex» e inspector de capas del último análisis.
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

    /// Paleta del análisis actual con el nombre de Wada más cercano y su ΔE00 (motor).
    @Published private(set) var palette: [PaletteColor] = []
    /// Alfileres (uno por swatch con píxeles en el label map), en el orden de la paleta.
    @Published private(set) var pins: [PhotoPin] = []
    /// Swatch seleccionado (alfiler o tarjeta de prenda).
    @Published var selectedSwatch: Int?
    /// Swatch aislado sobre la foto mientras se mantiene pulsado su alfiler.
    @Published private(set) var isolatedSwatch: Int?
    /// Capa (imagen reducida) que oscurece todo menos el swatch aislado.
    @Published private(set) var isolationOverlay: CGImage?
    /// Guardado en el Jardín (colección local).
    @Published private(set) var isSaved = false
    /// Aviso extra sobre el resultado (p. ej. «Recalculado con el motor actual» al reabrir desde el Feed).
    @Published var banner: String?
    /// Datos de ejemplo (atajos de depuración): se marca «Ejemplo» sobre la foto.
    var isExample = false

    private let garden: GardenStore
    private let naming: ComboNaming

    init(outcome: ScanOutcome, env: AppEnvironment, imageStore: FeedbackImageStore = .shared, timing: TimingLog = .shared,
         garden: GardenStore? = nil, naming: ComboNaming = .bundled) {
        self.outcome = outcome
        self.dictionary = env.dictionary
        self.feedbackRepository = env.feedback
        self.unlockRepository = env.unlocks
        self.scanRepository = env.scans
        self.imageStore = imageStore
        self.timing = timing
        self.garden = garden ?? .shared
        self.naming = naming
        self.palette = Self.palette(for: outcome, dictionary: env.dictionary)
        self.isSaved = self.garden.isSaved(scanId: outcome.scan.id)
    }

    // MARK: Derivados

    var hits: [Hit] { outcome.result.hits }
    var topHit: Hit? { hits.first }
    var top1Combo: WadaCombo? { topHit.flatMap { dictionary.combo(id: $0.comboId) } }
    var otherHits: [Hit] { Array(hits.dropFirst()) }
    var people: [PersonInstance] { outcome.subject.people }

    var title: String {
        topHit.map { comboName($0.comboId).text } ?? "Sin resultado"
    }

    var shareTitle: String {
        topHit.map { "\(AppBrand.name) · Wada \(WadaDictionary.numberLabel($0.comboId))" } ?? AppBrand.name
    }

    /// Nombre de una combinación: aceptado → propuesto → «Nº 067».
    func comboName(_ id: Int) -> ComboName {
        naming.name(for: id, in: dictionary)
    }

    /// "Entre Nº 012 y Nº 178" cuando el motor marca el resultado como ambiguo.
    var ambiguityText: String? {
        guard outcome.result.ambiguous, hits.count >= 2 else { return nil }
        return "Entre \(WadaDictionary.numberLabel(hits[0].comboId)) y \(WadaDictionary.numberLabel(hits[1].comboId))"
    }

    /// Aviso con los pasos reales del recorte (SubjectExplanation: pasos, región, respaldo y piel).
    var maskNotice: MaskStepsText.Notice { SubjectExplanation.notice(options: outcome.subjectOptions, result: outcome.subject) }

    /// Top-3 como resúmenes para las tarjetas (nombre, colores de Wada y ambigüedad en el primero).
    var matches: [ComboMatchSummary] {
        hits.enumerated().map { i, hit in
            ComboMatchSummary(comboId: hit.comboId, name: comboName(hit.comboId).text,
                              colors: PaletteColor.combo(hit.comboId, in: dictionary),
                              ambiguityText: i == 0 ? ambiguityText : nil)
        }
    }

    /// «Colores de la ropa» con máscara de sujeto; «Colores de la foto» sin ella.
    var paletteTitle: String { outcome.maskApplied ? "Colores de la ropa" : "Colores de la foto" }

    /// «5 colores · 12,3 % de la foto» o «3 colores · foto completa».
    var paletteSummary: String {
        let n = palette.count
        let colors = "\(n) \(n == 1 ? "color" : "colores")"
        guard outcome.maskApplied else { return "\(colors) · foto completa" }
        return "\(colors) · \(SubjectExplanation.percent(outcome.subject.maskCoverage)) de la foto"
    }

    /// Hex de la paleta separados por espacios (lo que copia «Copiar hex»).
    var paletteHexList: String { DesignFormat.hexList(palette) }

    /// Pie técnico: versiones y tiempos con coma decimal.
    var technicalFooter: String {
        let t = outcome.timings
        return "Motor \(outcome.scan.engineVersion) · diccionario \(outcome.scan.dictVersion) · \(outcome.elapsedMs) ms "
            + "(Vision \(Int(t.visionMs.rounded())) · máscara \(Int(t.maskMs.rounded())) · motor \(Int(t.engineMs.rounded())))"
    }

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
            palette = Self.palette(for: outcome, dictionary: dictionary)
            selectedSwatch = nil
            isolatedSwatch = nil
            isolationOverlay = nil
            await refreshDerivedImages()
            try await refreshUnlockState()
        } catch {
            errorMessage = ErrorText.describe(error)
        }
    }

    // MARK: Colores, alfileres y jardín

    /// Copia los hex de la paleta al portapapeles; devuelve el texto del toast.
    @discardableResult
    func copyPalette(pasteboard: UIPasteboard = .general) -> String {
        pasteboard.string = paletteHexList
        return palette.count == 1 ? "Copiado \(paletteHexList)" : "Copiados \(palette.count) hex"
    }

    /// Copia el hex de un color y lo selecciona; devuelve el texto del toast.
    @discardableResult
    func copy(_ color: PaletteColor, pasteboard: UIPasteboard = .general) -> String {
        pasteboard.string = color.hex
        selectedSwatch = color.id
        return "Copiado \(color.hex)"
    }

    /// «Guardar en el jardín» ⇄ quitar; devuelve el texto del toast.
    @discardableResult
    func toggleSave() -> String {
        isSaved = garden.toggle(scanId: outcome.scan.id)
        return isSaved ? "Guardado en el Jardín" : "Quitado del Jardín"
    }

    /// Pulsación larga en un alfiler: aísla sus píxeles sobre la foto mientras se mantiene.
    func setIsolation(_ swatch: Int, active: Bool) {
        guard active else {
            if isolatedSwatch == swatch {
                isolatedSwatch = nil
                isolationOverlay = nil
            }
            return
        }
        guard let d = outcome.debug else { return }
        isolatedSwatch = swatch
        selectedSwatch = swatch
        isolationOverlay = LayerBitmaps.isolateSwatch(labelMap: d.labelMap, width: d.debug.reducedWidth,
                                                      height: d.debug.reducedHeight, swatch: swatch)
    }

    /// Paleta con nombres de Wada (motor: `nearestDictionaryColor`).
    nonisolated static func palette(for outcome: ScanOutcome, dictionary: WadaDictionary) -> [PaletteColor] {
        outcome.result.swatches.enumerated().map { PaletteColor(id: $0.offset, swatch: $0.element, dictionary: dictionary) }
    }

    /// Alfileres en el centroide de los píxeles de cada swatch (ajustado al píxel más cercano
    /// con esa etiqueta); sin capas del motor no hay alfileres.
    nonisolated static func pins(for outcome: ScanOutcome, palette: [PaletteColor]) -> [PhotoPin] {
        guard let d = outcome.debug, !palette.isEmpty else { return [] }
        let positions = PinOverlay.positions(labelMap: d.labelMap, width: d.debug.reducedWidth,
                                             height: d.debug.reducedHeight, swatchCount: palette.count)
        return palette.compactMap { c in
            guard let p = positions[c.id] else { return nil }
            return PhotoPin(id: c.id, position: p, color: c, title: c.name ?? c.hex,
                            detail: c.weight.map(DesignFormat.percent))
        }
    }

    func makeShareImage() -> UIImage? {
        ShareCardRenderer.render(ShareCardRenderer.card(for: outcome, dictionary: dictionary))
    }

    /// Miniaturas de personas y capa de "Ver máscara" del análisis actual (en segundo plano).
    private func refreshDerivedImages() async {
        let o = outcome
        let colors = palette
        let (thumbnails, overlay, newPins) = await Task.detached(priority: .userInitiated) { () -> ([CGImage], CGImage?, [PhotoPin]) in
            let base = PNGCoding.cgImage(from: o.raster)
            let thumbs = base.map { image in o.subject.people.compactMap { LayerBitmaps.crop(image, bbox: $0.bbox) } } ?? []
            let overlay = o.subject.mask.flatMap { LayerBitmaps.dimOutside(mask: $0, width: o.raster.width, height: o.raster.height) }
            return (thumbs, overlay, Self.pins(for: o, palette: colors))
        }.value
        guard outcome.scan.rev == o.scan.rev else { return }
        personThumbnails = thumbnails
        maskOverlay = overlay
        pins = newPins
        if maskOverlay == nil { showMask = false }
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
