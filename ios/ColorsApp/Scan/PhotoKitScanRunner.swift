// Escaneo del carrete (día 0, PLAN §7.6 y §8 F7) con PhotoKit:
//
//  1. `PHPhotoLibrary.requestAuthorization(for: .readWrite)`.
//     - `.authorized`: se enumeran las últimas `limit` fotos (PHFetchOptions con
//       fetchLimit, creationDate descendente, solo imágenes).
//     - `.limited`: no se puede enumerar el carrete; se devuelve un resumen vacío
//       con `needsPicker = true` y la UI ofrece `PhotosPicker` (`scan(pickerItems:)`
//       procesa lo elegido por la misma ruta).
//     - `.denied` / `.restricted`: `ScanError.accessDenied` (la UI enlaza a Ajustes).
//  2. Cada foto se pide a `PHImageManager` a 256×256 (`aspectFill`, `fastFormat`,
//     `resizeMode .fast`, `isSynchronous` dentro de una tarea de fondo,
//     `isNetworkAccessAllowed = false`: las fotos que solo están en iCloud se
//     cuentan como omitidas).
//  3. Un `TaskGroup` con `policy.concurrency` (3) tareas concurrentes: cada una
//     rasteriza la foto una vez, calcula el recorte de sujeto con SubjectKit
//     sobre ese buffer (Vision + motor; modo de Ajustes: persona principal por
//     defecto, o desactivado / todas las personas si así está) y llama a
//     `EngineBridge.analyze` con la máscara, con su propio `ce_ctx` por llamada:
//     sin estáticos mutables, sin contexto compartido. Vision y el motor corren
//     fuera del MainActor.
//  4. Cada resultado se guarda como `ScanRecord` (source `.library`,
//     `asset_local_id`, modo/región/piel, personas, persona usada, pasos y
//     cobertura de la máscara) y, si cumple la regla de desbloqueo (`ScanPolicy`),
//     su top-1 se desbloquea (`UnlockRepository.unlock`, que ya ignora repetidos).
//  5. Al terminar: `scan.done <n> <ms>` en os.Logger (con los tiempos de Vision,
//     máscara y motor y el recuento de pasos), `scan.done`, `scan.vision`,
//     `scan.mask` y `scan.engine` en TimingLog, settings
//     `initial_scan_done/at/count`, y `ScanSummary` con desbloqueos nuevos,
//     combinaciones y colores más frecuentes y color firma.
//
// Regla de desbloqueo (documentada también en ScanPolicy): el top-1 de una foto
// se desbloquea solo si el resultado NO es `ambiguous` (gap top-1/top-2 ≥ 1,0 ΔE)
// y su score es ≤ `unlockMaxScore` (ajuste `unlock_max_score` de Ajustes, 12,0 por
// defecto; el escaneo lo lee al empezar. Informativo: el score es la
// suma ponderada de ΔE00 de ajuste + cobertura, PLAN §6 / engine/README.md; las
// fotos sintéticas limpias puntúan ≈ 0 y BENCHLOG no tiene todavía la
// distribución en fotos reales, que fijará F8). Las fotos ambiguas o lejanas se
// guardan como scans (para "Hoy" y el feedback) pero no desbloquean nada.
import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UIKit
import os
import ColorEngine
import SubjectKit

/// Parámetros del escaneo y regla de desbloqueo.
struct ScanPolicy: Equatable, Sendable {
    /// Umbral por defecto del score del top-1 para desbloquear (informativo, ver
    /// arriba); el valor efectivo es el ajuste `unlock_max_score`.
    static let defaultUnlockMaxScore = 12.0

    /// Score máximo del top-1 para desbloquearlo (el escaneo lo sustituye por el ajuste).
    var unlockMaxScore: Double = defaultUnlockMaxScore
    /// Solo desbloquea si el resultado no es ambiguo.
    var requireUnambiguous: Bool = true
    /// Lado de la imagen pedida a PhotoKit (256×256, PLAN §7.6).
    var targetSide: Int = 256
    /// Tareas concurrentes del TaskGroup (un ce_ctx cada una).
    var concurrency: Int = 3
    /// Hits guardados por scan (top1..top3).
    var topK: Int = 3

    static let `default` = ScanPolicy()

    /// Combinación a desbloquear para un resultado, o nil si no cumple la regla.
    func unlockCandidate(_ result: AnalysisResult) -> Int? {
        guard let top = result.hits.first else { return nil }
        if requireUnambiguous && result.ambiguous { return nil }
        guard top.score <= unlockMaxScore else { return nil }
        return top.comboId
    }
}

/// Entrada de una foto al escaneo: un PHAsset, los bytes de un PhotosPickerItem
/// o un CGImage ya decodificado (tests). Todas se procesan por la misma ruta.
enum ScanInput: Sendable {
    case asset(AssetRef)
    case data(Data, id: String?)
    case image(CGImage, id: String?)

    var id: String? {
        switch self {
        case .asset(let ref): ref.localIdentifier
        case .data(_, let id): id
        case .image(_, let id): id
        }
    }
}

/// PHAsset envuelto para cruzar a las tareas del TaskGroup: los objetos de
/// PhotoKit son inmutables y PHImageManager es seguro entre hilos.
struct AssetRef: @unchecked Sendable {
    let asset: PHAsset
    var localIdentifier: String { asset.localIdentifier }

    init(_ asset: PHAsset) { self.asset = asset }
}

@MainActor
final class PhotoKitScanRunner: ScanRunning {
    /// Resultado de una tarea del TaskGroup.
    enum WorkerResult: Sendable {
        case analyzed(id: String?, AnalysisResult, subject: ScanSubjectInfo, timings: AnalysisTimings, usedFallback: Bool)
        /// No hay imagen disponible sin red (iCloud) o no se pudo decodificar.
        case skipped(id: String?, reason: String)
        /// El motor o el puente fallaron.
        case failed(id: String?, error: String)
    }

    nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.andreseloy.colorsapp",
                                       category: "scan")

    private(set) var progress: ScanProgress = .idle
    var onProgress: (@MainActor (ScanProgress) -> Void)?
    /// Último resumen devuelto (para volver a mostrar el Wrapped sin reescanear).
    private(set) var lastSummary: ScanSummary?
    /// Milisegundos del último escaneo completo (lo que registra `scan.done`).
    private(set) var lastDurationMs: Double = 0
    /// Fotos del último escaneo que necesitaron el fallback `.highQualityFormat`.
    private(set) var lastFallbacks = 0
    /// Recuento de pasos del recorte (MaskFallback.rawValue -> fotos) del último escaneo.
    private(set) var lastStepCounts: [String: Int] = [:]
    /// Suma de tiempos (Vision, máscara, motor) del último escaneo.
    private(set) var lastTimings = AnalysisTimings.zero

    let policy: ScanPolicy
    private let scans: ScanRepository
    private let unlocks: UnlockRepository
    private let settings: SettingsRepository
    private let dictionary: WadaDictionary
    private let timing: TimingLog

    init(scans: ScanRepository, unlocks: UnlockRepository, settings: SettingsRepository,
         dictionary: WadaDictionary, policy: ScanPolicy = .default, timing: TimingLog = .shared) {
        self.scans = scans
        self.unlocks = unlocks
        self.settings = settings
        self.dictionary = dictionary
        self.policy = policy
        self.timing = timing
    }

    convenience init(environment: AppEnvironment, policy: ScanPolicy = .default) {
        self.init(scans: environment.scans, unlocks: environment.unlocks, settings: environment.settings,
                  dictionary: environment.dictionary, policy: policy)
    }

    // MARK: ScanRunning

    func runInitialScan(limit: Int) async throws -> ScanSummary {
        let startedAt = Date()
        publish(ScanProgress(phase: .requestingAccess, startedAt: startedAt))
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        switch status {
        case .authorized:
            break
        case .limited:
            // Sin enumeración del carrete: la UI ofrece PhotosPicker (scan(pickerItems:)).
            let total = try await unlocks.count()
            let summary = ScanSummary.empty(needsPicker: true, totalUnlocked: total, startedAt: startedAt, finishedAt: Date())
            lastSummary = summary
            publish(ScanProgress(phase: .finished, startedAt: startedAt))
            Self.logger.notice("scan.limited: acceso limitado a Fotos, se ofrece el picker")
            return summary
        case .denied, .restricted, .notDetermined:
            publish(ScanProgress(phase: .failed, startedAt: startedAt))
            throw ScanError.accessDenied
        @unknown default:
            publish(ScanProgress(phase: .failed, startedAt: startedAt))
            throw ScanError.accessDenied
        }
        publish(ScanProgress(phase: .fetching, startedAt: startedAt))
        let assets = Self.fetchLatestImageAssets(limit: limit)
        return try await scan(inputs: assets.map { .asset(AssetRef($0)) }, startedAt: startedAt)
    }

    /// Fotos elegidas con `PhotosPicker` (acceso limitado): se cargan sus bytes y
    /// siguen la misma ruta que el carrete (source `.library`, `asset_local_id`
    /// = `itemIdentifier` si el picker se creó con `photoLibrary: .shared()`).
    func scan(pickerItems: [PhotosPickerItem]) async throws -> ScanSummary {
        let startedAt = Date()
        publish(ScanProgress(phase: .fetching, startedAt: startedAt))
        var inputs: [ScanInput] = []
        var unreadable = 0
        for item in pickerItems {
            if let data = try? await item.loadTransferable(type: Data.self) {
                inputs.append(.data(data, id: item.itemIdentifier))
            } else {
                unreadable += 1
            }
        }
        return try await scan(inputs: inputs, startedAt: startedAt, alreadySkipped: unreadable)
    }

    /// Imágenes ya decodificadas (tests y otras rutas de la app).
    func scan(images: [(id: String?, image: CGImage)]) async throws -> ScanSummary {
        try await scan(inputs: images.map { .image($0.image, id: $0.id) }, startedAt: Date())
    }

    // MARK: Pipeline

    /// Analiza `inputs` con `policy.concurrency` tareas y persiste scans y unlocks.
    func scan(inputs: [ScanInput], startedAt: Date, alreadySkipped: Int = 0) async throws -> ScanSummary {
        var state = ScanProgress(phase: .analyzing, processed: 0, total: inputs.count, skipped: alreadySkipped,
                                 unlocked: 0, startedAt: startedAt)
        publish(state)
        var scanned = 0
        var failed = 0
        var newUnlocks: [Int] = []
        var comboCounts: [Int: Int] = [:]
        var fallbacks = 0
        var totals = AnalysisTimings.zero
        var stepCounts: [String: Int] = [:]
        // Ajustes leídos una vez al empezar: modo del recorte (persona principal por
        // defecto; desactivado o todas las personas si así está) y umbral de desbloqueo.
        let subjectSettings = (try? await settings.subjectSettings()) ?? .default
        let policy = subjectSettings.scanPolicy(base: self.policy)
        let subjectOptions = subjectSettings.subjectOptions
        let concurrency = max(1, policy.concurrency)

        do {
            try await withThrowingTaskGroup(of: WorkerResult.self) { group in
                var next = 0
                for _ in 0..<min(concurrency, inputs.count) {
                    let input = inputs[next]
                    next += 1
                    group.addTask { await Self.analyze(input, policy: policy, subject: subjectOptions) }
                }
                while let result = try await group.next() {
                    try Task.checkCancellation()
                    switch result {
                    case .analyzed(let id, let analysis, let subject, let t, let usedFallback):
                        totals.visionMs += t.visionMs
                        totals.maskMs += t.maskMs
                        totals.engineMs += t.engineMs
                        totals.rasterMs += t.rasterMs
                        for step in subject.steps { stepCounts[step.rawValue, default: 0] += 1 }
                        if usedFallback { fallbacks += 1 }
                        let record = ScanRecord.make(from: analysis, source: .library, assetLocalId: id, subject: subject)
                        try await scans.insert(record)
                        scanned += 1
                        if let top = analysis.hits.first {
                            comboCounts[top.comboId, default: 0] += 1
                        }
                        if let candidate = policy.unlockCandidate(analysis),
                           try await unlocks.unlock(comboId: candidate, source: .library, assetLocalId: id,
                                                    scanId: record.id) {
                            newUnlocks.append(candidate)
                        }
                    case .skipped(let id, let reason):
                        state.skipped += 1
                        Self.logger.debug("scan.skip \(id ?? "-", privacy: .public): \(reason, privacy: .public)")
                    case .failed(let id, let error):
                        failed += 1
                        Self.logger.error("scan.fail \(id ?? "-", privacy: .public): \(error, privacy: .public)")
                    }
                    state.processed += 1
                    state.unlocked = newUnlocks.count
                    publish(state)
                    if next < inputs.count {
                        let input = inputs[next]
                        next += 1
                        group.addTask { await Self.analyze(input, policy: policy, subject: subjectOptions) }
                    }
                }
            }
        } catch is CancellationError {
            state.phase = .failed
            publish(state)
            throw ScanError.cancelled
        } catch {
            state.phase = .failed
            publish(state)
            throw error
        }

        let finishedAt = Date()
        let totalUnlocked = try await unlocks.count()
        let colorCounts = Self.colorCounts(comboCounts: comboCounts, dictionary: dictionary)
        let summary = ScanSummary(
            scanned: scanned,
            skipped: state.skipped,
            failed: failed,
            newUnlocks: newUnlocks,
            totalUnlocked: totalUnlocked,
            topCombos: Self.sortedCounts(comboCounts).map { ComboCount(comboId: $0.key, count: $0.value) },
            startedAt: startedAt,
            finishedAt: finishedAt,
            topColors: colorCounts.map { ColorCount(colorIndex: $0.key, count: $0.value) },
            signatureColorIndex: colorCounts.first?.key,
            needsPicker: false
        )
        let ms = finishedAt.timeIntervalSince(startedAt) * 1000
        totals.totalMs = ms
        lastDurationMs = ms
        lastFallbacks = fallbacks
        lastStepCounts = stepCounts
        lastTimings = totals
        lastSummary = summary
        timing.record("scan.done", ms: Int(ms.rounded()), now: finishedAt)
        timing.record("scan.vision", ms: Int(totals.visionMs.rounded()), now: finishedAt)
        timing.record("scan.mask", ms: Int(totals.maskMs.rounded()), now: finishedAt)
        timing.record("scan.engine", ms: Int(totals.engineMs.rounded()), now: finishedAt)
        try await settings.setBool(.initialScanDone, true)
        try await settings.set(.initialScanAt, ISO8601DateFormatter().string(from: finishedAt))
        try await settings.setInt(.initialScanCount, scanned)
        state.phase = .finished
        publish(state)
        Self.logger.notice("scan.done \(scanned, privacy: .public) \(Int(ms.rounded()), privacy: .public)ms (omitidas \(state.skipped, privacy: .public), fallidas \(failed, privacy: .public), nuevas \(newUnlocks.count, privacy: .public), total \(totalUnlocked, privacy: .public), vision \(Int(totals.visionMs.rounded()), privacy: .public)ms, máscara \(Int(totals.maskMs.rounded()), privacy: .public)ms, motor \(Int(totals.engineMs.rounded()), privacy: .public)ms, recorte \(subjectOptions.mode.rawValue, privacy: .public)/\(subjectOptions.region.rawValue, privacy: .public)/piel \(subjectOptions.adaptiveSkin, privacy: .public), pasos \(Self.stepsText(stepCounts), privacy: .public), fallback highQuality \(fallbacks, privacy: .public))")
        return summary
    }

    private func publish(_ p: ScanProgress) {
        progress = p
        onProgress?(p)
    }

    // MARK: PhotoKit

    /// Últimas `limit` imágenes del carrete por fecha de creación descendente.
    nonisolated static func fetchLatestImageAssets(limit: Int) -> [PHAsset] {
        let options = PHFetchOptions()
        options.fetchLimit = max(0, limit)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.includeHiddenAssets = false
        let result = PHAsset.fetchAssets(with: .image, options: options)
        guard result.count > 0 else { return [] }
        return result.objects(at: IndexSet(0..<result.count))
    }

    /// Imagen de un asset a `side`×`side` (aspectFill) sin red, síncrona: se
    /// llama desde una tarea de fondo. Primero `.fastFormat` (la miniatura que
    /// Fotos ya tiene, PLAN §7.6); si falla por algo que no sea "solo en iCloud"
    /// se repite con `.highQualityFormat` (decodificación reducida, `resizeMode
    /// .fast`). Medido en el simulador iOS 27: `.fastFormat` devuelve
    /// PHPhotosErrorDomain 3303 ("No resource found matching image request spec")
    /// para todos los assets, también los de ejemplo; el fallback da 256×256.
    /// nil si solo está en iCloud o ninguna de las dos rutas da imagen.
    nonisolated static func requestImage(_ asset: PHAsset, side: Int) -> (image: CGImage?, reason: String, usedFallback: Bool) {
        let fast = requestImage(asset, side: side, delivery: .fastFormat)
        if let image = fast.image { return (image, fast.reason, false) }
        if fast.inCloud { return (nil, fast.reason, false) }
        let high = requestImage(asset, side: side, delivery: .highQualityFormat)
        return (high.image, high.image == nil ? "\(fast.reason); \(high.reason)" : high.reason, true)
    }

    private nonisolated static func requestImage(_ asset: PHAsset, side: Int,
                                                 delivery: PHImageRequestOptionsDeliveryMode) -> (image: CGImage?, reason: String, inCloud: Bool) {
        let options = PHImageRequestOptions()
        options.deliveryMode = delivery
        options.resizeMode = .fast
        options.isSynchronous = true
        options.isNetworkAccessAllowed = false
        options.version = .current
        // isSynchronous: el handler se ejecuta una sola vez, antes de volver.
        let box = ResultBox()
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                              contentMode: .aspectFill, options: options) { ui, info in
            if let cg = ui?.cgImage {
                box.image = cg
            } else if let ci = ui?.ciImage, let cg = CIContext().createCGImage(ci, from: ci.extent) {
                box.image = cg
            }
            if (info?[PHImageResultIsInCloudKey] as? Bool) == true {
                box.inCloud = true
                box.reason = "solo en iCloud (sin red)"
            } else if let error = info?[PHImageErrorKey] as? NSError {
                box.reason = "\(error.domain) \(error.code)"
            } else if (info?[PHImageCancelledKey] as? Bool) == true {
                box.reason = "cancelada"
            }
        }
        return (box.image, box.reason, box.inCloud)
    }

    /// Miniatura ≤ `side` px de unos bytes de imagen (ruta del PhotosPicker).
    nonisolated static func decodeThumbnail(_ data: Data, side: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
            kCGImageSourceShouldCache: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Caja para el handler síncrono de PHImageManager (referencia, no captura mutable).
    private final class ResultBox: @unchecked Sendable {
        var image: CGImage?
        var reason = "sin imagen"
        var inCloud = false
    }

    /// "headCut 3, noPeople 17" (orden alfabético).
    nonisolated static func stepsText(_ counts: [String: Int]) -> String {
        counts.isEmpty ? "-" : counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }

    /// Trabajo de una tarea del TaskGroup: imagen + recorte de sujeto (SubjectKit
    /// sobre el raster) + `EngineBridge.analyze` con la máscara (un ce_ctx por
    /// llamada). `nonisolated async`: corre siempre en el executor genérico, nunca
    /// en el MainActor (SE-0338).
    nonisolated static func analyze(_ input: ScanInput, policy: ScanPolicy,
                                    subject options: SubjectOptions = SubjectSettings.default.subjectOptions) async -> WorkerResult {
        let id = input.id
        let image: CGImage?
        var reason = "sin imagen"
        var usedFallback = false
        switch input {
        case .asset(let ref):
            let r = requestImage(ref.asset, side: policy.targetSide)
            image = r.image
            reason = r.reason
            usedFallback = r.usedFallback
        case .data(let data, _):
            image = decodeThumbnail(data, side: policy.targetSide)
            reason = "no se pudo decodificar"
        case .image(let cg, _):
            image = cg
        }
        guard let image else { return .skipped(id: id, reason: reason) }
        do {
            // Sin capas de depuración en el carrete: solo el resultado y los pasos.
            let analysis = try ScanAnalyzer.analyze(image: image, subject: options, layers: false, topK: policy.topK)
            let info = ScanSubjectInfo(options: options, result: analysis.subject)
            if !analysis.subject.steps.isEmpty {
                logger.debug("scan.subject \(id ?? "-", privacy: .public): \(analysis.subject.steps.map(\.rawValue).joined(separator: ","), privacy: .public) personas \(analysis.subject.people.count, privacy: .public)")
            }
            return .analyzed(id: id, analysis.result, subject: info, timings: analysis.timings, usedFallback: usedFallback)
        } catch {
            return .failed(id: id, error: String(describing: error))
        }
    }

    // MARK: Resumen

    /// Cuenta cada color del diccionario en los top-1 (ponderado por fotos),
    /// ordenado por recuento descendente y desempate por índice ascendente.
    nonisolated static func colorCounts(comboCounts: [Int: Int], dictionary: WadaDictionary) -> [(key: Int, value: Int)] {
        var counts: [Int: Int] = [:]
        for (comboId, n) in comboCounts {
            guard let combo = dictionary.combo(id: comboId) else { continue }
            for index in combo.colors {
                counts[index, default: 0] += n
            }
        }
        return sortedCounts(counts)
    }

    nonisolated static func sortedCounts(_ counts: [Int: Int]) -> [(key: Int, value: Int)] {
        counts.sorted { a, b in a.value != b.value ? a.value > b.value : a.key < b.key }
    }
}

extension AppEnvironment {
    /// Instala `PhotoKitScanRunner` (fase 7) si el runner actual no lo es y lo
    /// devuelve. Las vistas que lanzan el escaneo (ScanOnboardingView) lo llaman
    /// antes de `runInitialScan`; `bootstrap` puede instalarlo directamente.
    @discardableResult
    func installPhotoKitScanRunner(policy: ScanPolicy = .default) -> PhotoKitScanRunner {
        if let current = scanRunner as? PhotoKitScanRunner, current.policy == policy {
            return current
        }
        let runner = PhotoKitScanRunner(environment: self, policy: policy)
        setScanRunner(runner)
        return runner
    }
}
