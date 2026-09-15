// Modelo de Resultado (PLAN §7.3): feedback ("sí, es eso" / "no" -> tabla
// feedback + copia PNG sRGB de 256 px del raster para el diagnóstico),
// desbloqueo (tabla unlocks con el origen del scan) y tarjeta compartible.
import Foundation
import Combine
import UIKit
import ColorEngine

@MainActor
final class ResultViewModel: ObservableObject {
    enum UnlockState: Equatable {
        case unknown
        case locked
        case unlockedNow
        case alreadyUnlocked
    }

    let outcome: ScanOutcome
    let dictionary: WadaDictionary
    private let feedbackRepository: FeedbackRepository
    private let unlockRepository: UnlockRepository
    private let imageStore: FeedbackImageStore

    @Published private(set) var verdict: FeedbackVerdict?
    @Published private(set) var unlockState: UnlockState = .unknown
    @Published private(set) var busy = false
    @Published var errorMessage: String?

    init(outcome: ScanOutcome, env: AppEnvironment, imageStore: FeedbackImageStore = .shared) {
        self.outcome = outcome
        self.dictionary = env.dictionary
        self.feedbackRepository = env.feedback
        self.unlockRepository = env.unlocks
        self.imageStore = imageStore
    }

    // MARK: Derivados

    var hits: [Hit] { outcome.result.hits }
    var topHit: Hit? { hits.first }
    var top1Combo: WadaCombo? { topHit.flatMap { dictionary.combo(id: $0.comboId) } }
    var otherHits: [Hit] { Array(hits.dropFirst()) }

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

    func comboHeadline(_ combo: WadaCombo) -> String {
        if dictionary.curatedName(id: combo.id) != nil {
            return "\(WadaDictionary.numberLabel(combo.id)) · \(comboSubtitle(combo))"
        }
        return comboSubtitle(combo)
    }

    // MARK: Acciones

    /// Estado persistido: último veredicto del scan y si el top-1 ya está desbloqueado.
    func load() async {
        do {
            verdict = try await feedbackRepository.latest(forScan: outcome.scan.id)?.verdict
            if let top = topHit {
                unlockState = try await unlockRepository.isUnlocked(comboId: top.comboId) ? .alreadyUnlocked : .locked
            } else {
                unlockState = .locked
            }
        } catch {
            errorMessage = ErrorText.describe(error)
        }
    }

    func vote(_ newVerdict: FeedbackVerdict) async {
        guard verdict == nil, !busy else { return }
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
        guard let top = topHit, !busy else { return }
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

    func makeShareImage() -> UIImage? {
        ShareCardRenderer.render(ShareCardRenderer.card(for: outcome, dictionary: dictionary))
    }

    /// Copia PNG sRGB de 256 px del raster que vio el motor (diagnóstico). Lo
    /// mejor que se pueda: un fallo aquí no afecta al veredicto ya guardado.
    private func saveFeedbackImage() {
        guard let cg = PNGCoding.cgImage(from: outcome.raster) else { return }
        let store = imageStore
        let scanId = outcome.scan.id
        Task.detached(priority: .utility) {
            guard let png = try? PNGCoding.srgbPNG(from: cg, maxSide: 256) else { return }
            try? store.save(png: png, scanId: scanId)
        }
    }
}
