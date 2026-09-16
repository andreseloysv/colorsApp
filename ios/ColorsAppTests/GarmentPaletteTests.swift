// Paleta POR PRENDA en la app (ADR-011, CONTEXT §13: «el pantalón es de un solo color») y
// re-análisis de los scans guardados con una versión anterior:
//
//  - la escena sintética con pose pasa por `ce_analyze_garments`: un color por prenda con su
//    región (arriba / abajo / prenda entera), los mismos swatches que la paleta del resultado,
//    y el scan guarda `garments_json`, `garment_regions` y `engine_policy_version`;
//  - sin pose (modo off) el análisis sigue el camino CLÁSICO, idéntico al de antes;
//  - las tarjetas de Extraer reciben la etiqueta de la prenda y el título cambia a
//    «Colores por prenda»;
//  - la tira del Feed y la tarjeta compartible usan esos colores con su prenda;
//  - un scan antiguo se re-analiza al abrirlo y se guarda actualizado («Actualizado con el
//    motor nuevo»); si no se le pasa el repositorio (no se puede actualizar) queda marcado
//    «Análisis antiguo».
import XCTest
import ColorEngine
import SubjectKit
@testable import ColorsApp

@MainActor
final class GarmentPaletteTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("colorsapp-garment-\(UUID().uuidString)",
                                                                            isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func env() throws -> AppEnvironment {
        try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
    }

    private func timing() -> TimingLog { TimingLog(url: dir.appendingPathComponent("t-\(UUID().uuidString).txt")) }

    // MARK: Análisis por prenda

    func testSyntheticSceneUsesGarmentPathAndPersistsIt() async throws {
        let env = try env()
        let scene = SyntheticPersonScene.make()
        let image = try XCTUnwrap(scene.image)
        let outcome = try await ScanAnalyzer.run(image: image, source: .picker,
                                                 subject: SubjectSettings.default.subjectOptions,
                                                 people: [scene.person], env: env, timing: timing())
        XCTAssertTrue(outcome.subject.steps.contains(.garmentRegions), "\(outcome.subject.steps)")
        XCTAssertNotNil(outcome.subject.garmentRegions, "mapa de regiones de SubjectKit")
        XCTAssertTrue(outcome.usesGarments)
        XCTAssertEqual(outcome.garmentRegionCount, garmentMaxRegions)
        XCTAssertEqual(outcome.garments.count, outcome.result.swatches.count, "un swatch por color de prenda")
        XCTAssertEqual(outcome.garments.map(\.swatch), outcome.result.swatches, "la paleta ES la de prendas")
        let regions = outcome.garments.map(\.region)
        XCTAssertTrue(regions.allSatisfy { $0 != .none }, "\(regions)")
        XCTAssertTrue(regions.contains(.upper) || regions.contains(.whole), "\(regions)")
        // Una prenda lisa con luz y sombra = UN color (varios tonos agrupados).
        XCTAssertTrue(outcome.garments.contains { $0.mergedClusterCount >= 2 },
                      outcome.garments.map { "\($0.swatch.hex) \($0.mergedClusterCount)" }.joined(separator: " "))
        let report = outcome.garments.map { "\(GarmentText.regionLabel($0.region)) \($0.swatch.hex) "
            + "\(DesignFormat.percent($0.swatch.weight)) \($0.mergedClusterCount) tonos" }.joined(separator: " | ")
        print("GarmentPaletteTests: " + report)
        add(XCTAttachment(string: report))

        // Capas del mismo análisis (un solo ce_analyze_garments).
        XCTAssertEqual(outcome.debug?.analysis, outcome.result)
        let maps = try XCTUnwrap(outcome.garmentLayers)
        XCTAssertEqual(maps.regionMap.count, maps.reducedWidth * maps.reducedHeight)
        XCTAssertEqual(maps.garmentMap.count, maps.reducedWidth * maps.reducedHeight)
        XCTAssertTrue(maps.regionMap.contains { $0 == 1 || $0 == 2 || $0 == 3 }, "el mapa reducido tiene regiones")

        // Guardado: columnas v4 + versión de la política.
        let storedOptional = try await env.scans.fetch(id: outcome.scan.id)
        let stored = try XCTUnwrap(storedOptional)
        XCTAssertEqual(stored.garmentRegions, garmentMaxRegions)
        XCTAssertEqual(stored.enginePolicyVersion, AnalysisPolicy.current)
        XCTAssertEqual(stored.garmentColors.count, outcome.garments.count)
        XCTAssertEqual(stored.garmentColors.map(\.hex), outcome.garments.map(\.swatch.hex))
        XCTAssertEqual(stored.garmentColors.map(\.region), outcome.garments.map(\.region.rawValue))
        XCTAssertFalse(stored.needsReanalysis, "recién analizado con esta build")

        // Tarjetas de Extraer: título, resumen y etiqueta de prenda por color.
        let model = ResultViewModel(outcome: outcome, env: env, timing: timing())
        XCTAssertTrue(model.usesGarments)
        XCTAssertEqual(model.paletteTitle, "Colores por prenda")
        XCTAssertTrue(model.paletteSummary.contains("prenda"), model.paletteSummary)
        for color in model.palette {
            let label = try XCTUnwrap(model.garmentRegionLabel(for: color), "color \(color.id) sin prenda")
            XCTAssertTrue(["Parte de arriba", "Parte de abajo", "Prenda entera"].contains(label), label)
        }
        // La tira del Feed y la tarjeta compartible: los MISMOS colores, con su prenda.
        let feedColors = FeedPostText.palette(stored, in: env.dictionary)
        XCTAssertEqual(feedColors.map(\.hex), outcome.garments.map { $0.swatch.hex.uppercased() })
        XCTAssertEqual(feedColors.compactMap(\.name), outcome.garments.map { GarmentText.shortRegionLabel($0.region) })
        XCTAssertEqual(FeedPostText.paletteTitle(stored), "Paleta por prenda")
        let card = ShareCardRenderer.card(for: outcome, dictionary: env.dictionary)
        XCTAssertEqual(card.palette.map(\.hex), feedColors.map(\.hex), "la tarjeta compartible usa los colores por prenda")
    }

    func testWithoutPoseKeepsClassicPath() throws {
        let scene = SyntheticPersonScene.make()
        let image = try XCTUnwrap(scene.image)
        var options = SubjectSettings.default.subjectOptions
        options.mode = .off
        let analysis = try ScanAnalyzer.analyze(image: image, subject: options, people: [scene.person])
        XCTAssertNil(analysis.subject.garmentRegions)
        XCTAssertFalse(analysis.usesGarments)
        XCTAssertTrue(analysis.garments.isEmpty)
        XCTAssertNil(analysis.garmentInfo)
        let plain = try EngineBridge.analyze(raster: analysis.raster, matchOptions: EngineBridge.appMatchOptions)
        XCTAssertEqual(analysis.result, plain, "camino clásico idéntico (hash incluido)")
    }

    // MARK: Textos de las regiones

    func testRegionLabelsCoverFutureValues() {
        XCTAssertEqual(GarmentText.regionLabel(GarmentRegion.upper), "Parte de arriba")
        XCTAssertEqual(GarmentText.regionLabel(GarmentRegion.lower), "Parte de abajo")
        XCTAssertEqual(GarmentText.regionLabel(GarmentRegion.whole), "Prenda entera")
        XCTAssertEqual(GarmentText.regionLabel(GarmentRegion.none), "Prenda")
        XCTAssertEqual(GarmentText.regionLabel(42), "Prenda", "valor futuro del motor: default, sin romper")
        XCTAssertEqual(GarmentText.shortRegionLabel(GarmentRegion.upper), "Arriba")
        XCTAssertEqual(GarmentText.shortRegionLabel(GarmentRegion.lower), "Abajo")
        XCTAssertEqual(GarmentText.shortRegionLabel(7), "Prenda")
        XCTAssertTrue(GarmentText.groupingReason(mergedClusters: 1).contains("Un solo tono"))
        XCTAssertTrue(GarmentText.groupingReason(mergedClusters: 4).contains("4 tonos"))
        // Pasos nuevos de SubjectKit (separación de personas y regiones de prenda).
        XCTAssertEqual(MaskStepsText.stepTitle(.garmentRegions), "Regiones de prenda (arriba / abajo)")
        XCTAssertEqual(MaskStepsText.stepTitle(.splitByPose), "Personas separadas por su pose")
        XCTAssertEqual(MaskStepsText.stepTitle(.splitByFace), "Personas separadas por su cara")
    }

    func testNoticeMentionsGarmentsAndPersonSplit() {
        let w = 4, h = 4
        let full = [UInt8](repeating: 255, count: w * h)
        let people = [PersonInstance(id: 1, mask: full, width: w, height: h),
                      PersonInstance(id: 2, mask: full, width: w, height: h)]
        let result = SubjectMaskResult(width: w, height: h, people: people, chosenIndex: 0, mask: full,
                                       steps: [.splitByPose, .poseRegions, .skinExcluded, .garmentRegions], timings: [:],
                                       maskCoverage: 1,
                                       layers: SubjectLayers(width: w, height: h, persons: [], allPeopleOverlay: [],
                                                             finalMask: full))
        let notice = MaskStepsText.notice(options: .default, result: result)
        XCTAssertTrue(notice.text.contains("personas separadas por su pose"), notice.text)
        XCTAssertTrue(notice.text.hasSuffix("un color por prenda"), notice.text)
        XCTAssertFalse(notice.isFallback)
        let explained = SubjectExplanation.notice(options: .default, result: result)
        XCTAssertTrue(explained.text.contains("personas separadas por su pose"), explained.text)
        XCTAssertTrue(explained.text.hasSuffix("un color por prenda"), explained.text)
        XCTAssertEqual(SubjectExplanation.stepTitles(result: result),
                       ["Personas separadas por su pose", "Regiones de la pose", "Piel excluida",
                        "Regiones de prenda (arriba / abajo)"])
    }

    // MARK: Re-análisis de scans antiguos

    /// Un scan como los que hay hoy en el iPhone del usuario: sin versión de política (v4 aún
    /// no existía) y con otro motor.
    private func oldScan(id: String) -> ScanRecord {
        let result = AnalysisResult(swatches: [Swatch(lab: Lab(L: 79.5, a: 8.1, b: 0.4), r: 0xdd, g: 0xc0, b: 0xc8, weight: 1)],
                                    hits: [Hit(comboId: 67, score: 17.18)], ambiguous: false, hash: 1)
        var scan = ScanRecord.make(from: result, source: .picker, now: Date(timeIntervalSince1970: 1_757_000_000), id: id)
        scan.engineVersion = "0.0.1-viejo"
        scan.enginePolicyVersion = nil
        return scan
    }

    func testReopenUpdatesOutdatedScanAndAnnouncesIt() async throws {
        let env = try env()
        let scene = SyntheticPersonScene.make()
        let image = try XCTUnwrap(scene.image)
        let scan = oldScan(id: "0190a000-0000-7000-8000-0000000000aa")
        try await env.scans.insert(scan)
        XCTAssertTrue(scan.needsReanalysis, "política nil + motor viejo")
        XCTAssertEqual(FeedPostText.outdatedNotice(scan), "Análisis antiguo")
        XCTAssertTrue(FeedItem(scan: scan, dictionary: env.dictionary).isOutdated)
        let pending = try await env.scans.needingReanalysis().map(\.id)
        XCTAssertEqual(pending, [scan.id])

        let reopened = try await FeedServices.reopen(scan: scan, image: image,
                                                     fallback: SubjectSettings.default.subjectOptions, scans: env.scans)
        XCTAssertTrue(reopened.updated)
        XCTAssertEqual(reopened.banner, "Actualizado con el motor nuevo")
        let storedOptional = try await env.scans.fetch(id: scan.id)
        let stored = try XCTUnwrap(storedOptional)
        XCTAssertEqual(stored.id, scan.id, "el mismo scan, no uno nuevo")
        XCTAssertEqual(stored.rev, 2)
        XCTAssertEqual(stored.engineVersion, colorEngineVersion)
        XCTAssertEqual(stored.dictVersion, dictionaryVersion)
        XCTAssertEqual(stored.enginePolicyVersion, AnalysisPolicy.current)
        XCTAssertEqual(stored.top1, reopened.outcome.result.hits.first?.comboId)
        XCTAssertEqual(stored.palette.map(\.hex), reopened.outcome.result.swatches.map(\.hex))
        XCTAssertFalse(stored.needsReanalysis, "ya no pide re-análisis")
        XCTAssertNil(FeedPostText.outdatedNotice(stored))
        XCTAssertEqual(stored.scannedAt.timeIntervalSince1970, scan.scannedAt.timeIntervalSince1970, accuracy: 0.001,
                       "la fecha del scan no cambia")
        XCTAssertEqual(reopened.outcome.scan.rev, 2, "Resultado abre el scan ya actualizado")
        let stillPending = try await env.scans.needingReanalysis()
        XCTAssertEqual(stillPending.count, 0)
    }

    func testReopenWithoutRepositoryLeavesScanMarkedAsOld() async throws {
        let env = try env()
        let image = try XCTUnwrap(SyntheticPersonScene.make().image)
        let scan = oldScan(id: "0190a000-0000-7000-8000-0000000000ab")
        try await env.scans.insert(scan)
        let reopened = try await FeedServices.reopen(scan: scan, image: image,
                                                     fallback: SubjectSettings.default.subjectOptions)
        XCTAssertFalse(reopened.updated)
        XCTAssertEqual(reopened.banner, "Recalculado con el motor actual", "se avisa, pero no se guarda")
        let storedOptional = try await env.scans.fetch(id: scan.id)
        let stored = try XCTUnwrap(storedOptional)
        XCTAssertEqual(stored.rev, 1, "sin repositorio no se escribe nada")
        XCTAssertTrue(stored.needsReanalysis)
        XCTAssertEqual(FeedPostText.outdatedNotice(stored), "Análisis antiguo")
    }

    func testReopenOfCurrentScanDoesNotRewriteIt() async throws {
        let env = try env()
        let scene = SyntheticPersonScene.make()
        let image = try XCTUnwrap(scene.image)
        let outcome = try await ScanAnalyzer.run(image: image, source: .picker,
                                                 subject: SubjectSettings.default.subjectOptions,
                                                 people: [scene.person], env: env, timing: timing())
        let reopened = try await FeedServices.reopen(scan: outcome.scan, image: image,
                                                     fallback: SubjectSettings.default.subjectOptions, scans: env.scans)
        XCTAssertFalse(reopened.updated)
        let storedOptional = try await env.scans.fetch(id: outcome.scan.id)
        let stored = try XCTUnwrap(storedOptional)
        XCTAssertEqual(stored.rev, 1, "un scan al día no se reescribe al abrirlo")
        XCTAssertFalse(stored.needsReanalysis)
    }
}
