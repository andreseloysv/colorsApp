// «Exportar diagnóstico» compartido por Ajustes y el estudio de exportación del Jardín
// (PLAN §7.8): zip con feedback.csv, scans.csv, times.txt y la copia de 256 px de cada
// foto votada con sus máscaras y capas. Solo por acción explícita; se entrega con
// ShareLink (AirDrop, Archivos…). La app sigue sin usar red.
import Foundation

enum DiagnosticsExportAction {
    /// Construye el zip con las fotos votadas (copia local o asset del carrete con el recorte guardado).
    @MainActor
    static func run(env: AppEnvironment) async throws -> Diagnostics.Export {
        let subject = (try? await env.settings.subjectSettings()) ?? .default
        let store = FeedbackImageStore.shared
        let fallbackOptions = subject.subjectOptions
        let provider: Diagnostics.PhotoProvider = { scan in
            if let attachment = store.attachment(scanId: scan.id) { return attachment }
            if let asset = scan.assetLocalId {
                return await PhotoLibraryImages.attachment(assetLocalId: asset, scan: scan, fallbackOptions: fallbackOptions)
            }
            return nil
        }
        return try await Diagnostics.export(scans: env.scans, feedback: env.feedback, timings: .shared,
                                            photoProvider: provider)
    }

    /// «3 veredictos · 42 scans · 3 fotos».
    static func summary(_ export: Diagnostics.Export) -> String {
        "\(export.feedbackRows) \(export.feedbackRows == 1 ? "veredicto" : "veredictos") · \(export.scanRows) scans · \(export.images) \(export.images == 1 ? "foto" : "fotos")"
    }
}
