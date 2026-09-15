// Flujo de una captura (PLAN §7.2): rasterizar (EngineBridge), máscara de
// persona opcional (PersonMask, Vision), ce_analyze en un Task.detached con un
// ce_ctx por llamada, guardar el scan (ScanRepository) y registrar el tiempo
// (TimingLog). Lo usan Hoy (picker/cámara), el modo demo y los tests.
import Foundation
import CoreGraphics
import ColorEngine

/// Resultado completo de una captura: imagen vertical (≤ 1024 px), raster que
/// vio el motor, análisis, scan ya persistido y notas de la máscara.
struct ScanOutcome: Identifiable, Hashable, Sendable {
    let image: CGImage
    let raster: EngineBridge.Raster
    let result: AnalysisResult
    let scan: ScanRecord
    let maskApplied: Bool
    let maskNote: String?
    let elapsedMs: Int

    var id: String { scan.id }

    static func == (lhs: ScanOutcome, rhs: ScanOutcome) -> Bool { lhs.scan.id == rhs.scan.id }

    func hash(into hasher: inout Hasher) { hasher.combine(scan.id) }
}

enum ScanAnalyzer {
    /// Parte pura del análisis (sin base de datos).
    struct Analysis: Sendable {
        let raster: EngineBridge.Raster
        let result: AnalysisResult
        let maskApplied: Bool
        let maskNote: String?
        let elapsedMs: Int
    }

    /// Rasteriza, calcula la máscara si se pide y analiza. Síncrono y sin
    /// estado compartido: llamar desde `Task.detached`.
    static func analyze(image: CGImage, personMask: Bool, topK: Int = 3) throws -> Analysis {
        let start = Date()
        let raster = try EngineBridge.rasterize(image)
        var maskBytes: [UInt8]?
        var applied = false
        var note: String?
        if personMask {
            do {
                let mask = try PersonMask.compute(for: image, width: raster.width, height: raster.height)
                if mask.isUsable {
                    maskBytes = mask.bytes
                    applied = true
                    note = String(format: "Máscara de persona aplicada (%.0f %% de la imagen).", mask.coverage * 100)
                } else {
                    note = String(format: "Máscara de persona ignorada: Vision solo encontró un %.1f %% de persona; análisis sin máscara.",
                                  mask.coverage * 100)
                }
            } catch {
                note = "Máscara de persona no disponible (\(error.localizedDescription)); análisis sin máscara."
            }
        }
        let result = try EngineBridge.analyze(raster: raster, topK: topK, mask: maskBytes)
        let elapsed = Int((Date().timeIntervalSince(start) * 1000).rounded())
        return Analysis(raster: raster, result: result, maskApplied: applied, maskNote: note, elapsedMs: elapsed)
    }

    /// Flujo completo: análisis en segundo plano (userInitiated), scan guardado
    /// y tiempo registrado. `personMask` nil = leer el ajuste `person_mask`.
    @MainActor
    static func run(image: CGImage, source: ScanSource, assetLocalId: String? = nil, personMask: Bool? = nil,
                    env: AppEnvironment, timing: TimingLog = .shared, now: Date = Date()) async throws -> ScanOutcome {
        let useMask: Bool
        if let personMask {
            useMask = personMask
        } else {
            useMask = (try? await env.settings.bool(.personMask)) ?? false
        }
        let analysis = try await Task.detached(priority: .userInitiated) {
            try analyze(image: image, personMask: useMask)
        }.value
        let scan = ScanRecord.make(from: analysis.result, source: source, assetLocalId: assetLocalId, now: now)
        try await env.scans.insert(scan)
        timing.record("analyze.\(source.rawValue)", ms: analysis.elapsedMs, now: now)
        return ScanOutcome(image: image, raster: analysis.raster, result: analysis.result, scan: scan,
                           maskApplied: analysis.maskApplied, maskNote: analysis.maskNote,
                           elapsedMs: analysis.elapsedMs)
    }
}
