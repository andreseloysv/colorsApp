// Acciones del Feed que tocan datos (docs/design/DESIGN_SYSTEM.md §5.5-4 y §5.5-5):
// votar desde una publicación (tabla feedback + copia de 256 px para el diagnóstico, como
// Resultado), «Abrir en Extraer» (reanaliza la foto guardada SIN crear otro scan) y borrar
// del Feed (borrado suave + foto + guardado). Nada de red.
import Foundation
import CoreGraphics
import ColorEngine
import SubjectKit

enum FeedServices {
    /// Opciones de recorte con las que se calculó un scan (las de Ajustes si el scan es anterior a v2).
    static func subjectOptions(for scan: ScanRecord, fallback: SubjectOptions = SubjectSettings.default.subjectOptions) -> SubjectOptions {
        var options = fallback
        if let raw = scan.subjectMode, let mode = SubjectMode(rawValue: raw) {
            options.mode = mode
            options.selectedIndex = mode == .selectedPerson ? scan.personIndex : nil
        }
        if let raw = scan.regionMode, let region = RegionMode(rawValue: raw) { options.region = region }
        if let skin = scan.adaptiveSkin { options.adaptiveSkin = skin }
        return options
    }

    /// Resultado de «Abrir en Extraer».
    struct Reopened: Sendable {
        let outcome: ScanOutcome
        /// El motor actual da otro top-1 o la versión del motor cambió: se avisa «Recalculado con el motor actual».
        let recalculated: Bool
        /// El scan se había analizado con otra versión del motor, del diccionario o de la
        /// política (`AnalysisPolicy.needsReanalysis`) y se ha guardado ACTUALIZADO.
        let updated: Bool

        /// Aviso discreto de Resultado; nil si no hay nada que contar.
        var banner: String? {
            if updated { return "Actualizado con el motor nuevo" }
            return recalculated ? "Recalculado con el motor actual" : nil
        }
    }

    /// Reanaliza la foto de un scan con sus opciones guardadas (Vision + motor) y construye
    /// el `ScanOutcome` (nunca inserta un scan nuevo: jamás `ScanAnalyzer.run`).
    ///
    /// RE-ANÁLISIS DE SCANS ANTIGUOS (CONTEXT §13): si el scan se guardó con otra versión del
    /// motor, del diccionario o de la política de análisis (`AnalysisPolicy.needsReanalysis`)
    /// y se le pasa `scans`, el resultado nuevo SUSTITUYE al guardado (mismo id, rev + 1, con
    /// la paleta por prenda y las versiones actuales) y `updated` es true para que Resultado
    /// avise «Actualizado con el motor nuevo». Sin `scans` (o sin foto, que ni siquiera llega
    /// aquí) el scan se queda como estaba y la publicación sigue marcada «Análisis antiguo».
    static func reopen(scan: ScanRecord, image: CGImage, fallback: SubjectOptions,
                       scans: ScanRepository? = nil, now: Date = Date()) async throws -> Reopened {
        let options = subjectOptions(for: scan, fallback: fallback)
        let analysis = try await Task.detached(priority: .userInitiated) {
            try ScanAnalyzer.analyze(image: image, subject: options)
        }.value
        let recalculated = analysis.result.hits.first?.comboId != scan.top1 || scan.engineVersion != colorEngineVersion
        var record = scan
        var updated = false
        if scan.needsReanalysis, let scans {
            let info = ScanSubjectInfo(options: options, result: analysis.subject)
            record = scan.updated(with: analysis.result, subject: info, now: now,
                                  garments: analysis.garmentInfo, policyVersion: AnalysisPolicy.current,
                                  engineVersion: colorEngineVersion, dictVersion: dictionaryVersion)
            try await scans.update(record)
            updated = true
        }
        let outcome = ScanOutcome(image: image, raster: analysis.raster, result: analysis.result, scan: record,
                                  subjectOptions: options, subject: analysis.subject, debug: analysis.debug,
                                  timings: analysis.timings, garments: analysis.garments,
                                  garmentRegionCount: analysis.garmentRegionCount,
                                  garmentLayers: analysis.garmentLayers)
        return Reopened(outcome: outcome, recalculated: recalculated, updated: updated)
    }

    /// Voto desde el Feed: registra el veredicto y, en segundo plano, guarda la copia PNG de
    /// 256 px y sus extras para «Exportar diagnóstico» (lo mejor que se pueda; un fallo aquí
    /// no afecta al voto).
    @MainActor
    static func vote(_ verdict: FeedbackVerdict, scan: ScanRecord, env: AppEnvironment,
                     photoStore: ScanPhotoStore = .shared, imageStore: FeedbackImageStore = .shared) async throws {
        _ = try await env.feedback.record(scanId: scan.id, verdict: verdict)
        let fallback = ((try? await env.settings.subjectSettings()) ?? .default).subjectOptions
        Task.detached(priority: .utility) {
            await saveDiagnosticsCopy(scan: scan, photoStore: photoStore, imageStore: imageStore, fallback: fallback)
        }
    }

    static func saveDiagnosticsCopy(scan: ScanRecord, photoStore: ScanPhotoStore, imageStore: FeedbackImageStore,
                                    fallback: SubjectOptions) async {
        if let asset = scan.assetLocalId,
           let attachment = await PhotoLibraryImages.attachment(assetLocalId: asset, scan: scan, fallbackOptions: fallback) {
            try? imageStore.save(png: attachment.png, scanId: scan.id)
            try? imageStore.save(extras: attachment.extras, scanId: scan.id)
            return
        }
        guard let image = photoStore.image(scanId: scan.id),
              let png = try? PNGCoding.srgbPNG(from: image, maxSide: DiagnosticsSubject.exportSide) else { return }
        try? imageStore.save(png: png, scanId: scan.id)
        let options = subjectOptions(for: scan, fallback: fallback)
        if let analysis = try? ScanAnalyzer.analyze(image: image, subject: options),
           let extras = try? DiagnosticsSubject.extras(.init(scanId: scan.id, analysis: analysis, origin: "feed")) {
            try? imageStore.save(extras: extras, scanId: scan.id)
        }
    }

    /// «Borrar del Feed»: borrado suave del scan, su foto y su guardado en el Jardín.
    @MainActor
    static func delete(scan: ScanRecord, env: AppEnvironment, garden: GardenStore, photoStore: ScanPhotoStore = .shared) async throws {
        try await env.scans.softDelete(id: scan.id)
        photoStore.remove(scanId: scan.id)
        garden.remove(scanId: scan.id)
    }
}
