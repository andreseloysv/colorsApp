// ScanAnalyzer con SubjectKit:
//  - dos fotos reales de harness/people (03 pareja de espaldas, 02 vestido con
//    piel) por la ruta completa (Vision + motor). En el simulador iOS 27 Vision no
//    crea el contexto de inferencia (VNGeneratePersonInstanceMaskRequest: "Could
//    not create inference context"), así que se comprueba el retorno
//    `visionUnavailable` sin crash (mask nil, análisis de la foto completa
//    idéntico a analizar sin máscara) y la parte de personas se marca con
//    XCTSkip; en un dispositivo se exigen personas, pasos y máscara.
//  - la cadena real (regiones de la pose, piel adaptativa) con personas
//    sintéticas: el scan guarda modo, región, piel, personas, persona usada,
//    pasos y cobertura, y TimingLog los tiempos de Vision, máscara y motor.
//  - elegir persona en Resultado reutiliza `subject.people` sin Vision.
//  - personas fantasma: una instancia sin pose, cara ni silueta plausible (el cartel)
//    se descarta; sin nadie más, la foto se analiza completa con los pasos
//    [.rejectedPhantom, .noPeople], que el scan guarda y relee.
import XCTest
import ImageIO
import ColorEngine
import SubjectKit
@testable import ColorsApp

@MainActor
final class ScanAnalyzerSubjectTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("colorsapp-subject-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func env() throws -> AppEnvironment {
        try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
    }

    private func photo(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle(for: ScanAnalyzerSubjectTests.self).url(forResource: name, withExtension: "png"),
                                "\(name).png en el bundle de tests (project.yml: ../harness/people)")
        return try ImageLoading.cgImage(from: url)
    }

    /// Persona sintética de la escena y una segunda "persona" sin pose ni cara (el cartel amarillo).
    private func twoPeople(_ scene: SyntheticPersonScene) -> [PersonInstance] {
        var sign = [UInt8](repeating: 0, count: scene.width * scene.height)
        for y in 28..<92 {
            for x in 222..<290 { sign[y * scene.width + x] = 255 }
        }
        return [scene.person, PersonInstance(id: 2, mask: sign, width: scene.width, height: scene.height)]
    }

    func testTwoHarnessPhotosWithSubjectKit() async throws {
        var visionUnavailable = 0
        var report: [String] = []
        for name in ["03_couple_denim_street", "02_single_dress_umbrella"] {
            let image = try photo(name)
            let analysis = try await Task.detached {
                try ScanAnalyzer.analyze(image: image, subject: .default)
            }.value
            XCTAssertEqual(analysis.raster.width, image.width, name)
            XCTAssertFalse(analysis.result.hits.isEmpty, "\(name): el motor devuelve hits")
            XCTAssertNotNil(analysis.debug, "\(name): capas del mismo análisis")
            XCTAssertEqual(analysis.debug?.analysis, analysis.result)
            report.append("\(name): pasos \(analysis.subject.steps.map(\.rawValue)) personas \(analysis.subject.people.count) cobertura \(analysis.subject.maskCoverage) vision \(Int(analysis.timings.visionMs)) ms motor \(Int(analysis.timings.engineMs)) ms")
            if analysis.subject.steps == [.visionUnavailable] {
                visionUnavailable += 1
                XCTAssertNil(analysis.subject.mask, "\(name): sin Vision no hay máscara")
                XCTAssertTrue(analysis.subject.people.isEmpty)
                XCTAssertEqual(MaskStepsText.notice(options: .default, result: analysis.subject).text,
                               "Vision no disponible: foto completa")
                let plain = try EngineBridge.analyze(raster: analysis.raster, matchOptions: EngineBridge.appMatchOptions)
                XCTAssertEqual(plain, analysis.result, "\(name): retorno = foto completa sin máscara (hash incluido)")
            } else {
                XCTAssertFalse(analysis.subject.people.isEmpty, "\(name): Vision encuentra personas")
                XCTAssertNotNil(analysis.subject.mask, "\(name): máscara de la persona principal")
                XCTAssertTrue(analysis.subject.steps.contains(.poseRegions) || analysis.subject.steps.contains(.headCut)
                              || analysis.subject.steps.contains(.wholePerson), "\(name): \(analysis.subject.steps)")
            }
        }
        print("ScanAnalyzerSubjectTests: " + report.joined(separator: " | "))
        add(XCTAttachment(string: report.joined(separator: "\n")))
        if visionUnavailable > 0 {
            throw XCTSkip("Vision no disponible en este destino (simulador iOS: \"Could not create inference context\"): comprobado el retorno visionUnavailable sin crash en \(visionUnavailable)/2 fotos; la detección de personas se prueba en dispositivo y en macOS (make subject-test).")
        }
    }

    func testRunPersistsSubjectColumnsAndTimings() async throws {
        let env = try env()
        let scene = SyntheticPersonScene.make()
        let image = try XCTUnwrap(scene.image)
        let timing = TimingLog(url: dir.appendingPathComponent("times.txt"))
        let outcome = try await ScanAnalyzer.run(image: image, source: .picker, subject: .default, people: [scene.person],
                                                 env: env, timing: timing, now: Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertEqual(outcome.subject.steps, [.poseRegions, .skinExcluded], "pose -> regiones de ropa; cara -> piel excluida")
        XCTAssertEqual(outcome.subject.chosenIndex, 0)
        let mask = try XCTUnwrap(outcome.subject.mask)
        XCTAssertGreaterThan(outcome.subject.maskCoverage, 0.05)
        let primary = try XCTUnwrap(outcome.subject.layers.primary)
        XCTAssertGreaterThan(primary.skinExcludedPixels, 100, "escote y cuello de piel dentro de la región")
        XCTAssertNotNil(primary.regionMask)
        // La máscara no incluye la cabeza ni las manos.
        XCTAssertEqual(mask[80 * scene.width + 150], 0, "cara fuera")
        XCTAssertEqual(mask[248 * scene.width + 232], 0, "mano fuera")
        XCTAssertEqual(mask[200 * scene.width + 150], 255, "camiseta dentro")
        XCTAssertEqual(outcome.maskNotice.text, "Solo ropa · piel excluida")
        XCTAssertEqual(outcome.result.hits.first?.comboId, 12, "camiseta Green Blue + pantalón Isabella = Nº 012")
        XCTAssertEqual(outcome.debug?.analysis, outcome.result)

        let storedOptional = try await env.scans.fetch(id: outcome.scan.id)
        let stored = try XCTUnwrap(storedOptional)
        XCTAssertEqual(stored.subjectMode, "largestPerson")
        XCTAssertEqual(stored.regionMode, "clothing")
        XCTAssertEqual(stored.adaptiveSkin, true)
        XCTAssertEqual(stored.peopleCount, 1)
        XCTAssertEqual(stored.personIndex, 0)
        XCTAssertEqual(stored.maskStepValues, [.poseRegions, .skinExcluded])
        XCTAssertEqual(stored.maskCoverage ?? -1, outcome.subject.maskCoverage, accuracy: 1e-12)
        let times = timing.text()
        for label in ["analyze.picker ", "analyze.picker.vision ", "analyze.picker.mask ", "analyze.picker.engine "] {
            XCTAssertTrue(times.contains(label), "times.txt: \(label)\n\(times)")
        }
        XCTAssertGreaterThan(outcome.timings.engineMs, 0)
        XCTAssertGreaterThanOrEqual(outcome.timings.totalMs, outcome.timings.engineMs)

        // Modo off: sin máscara, mismos píxeles que analizar sin recorte.
        let off = try ScanAnalyzer.analyze(image: image, subject: SubjectOptions(mode: .off), people: [scene.person])
        XCTAssertNil(off.subject.mask)
        XCTAssertEqual(off.result, try EngineBridge.analyze(raster: off.raster, matchOptions: EngineBridge.appMatchOptions))
        XCTAssertEqual(MaskStepsText.notice(options: SubjectOptions(mode: .off), result: off.subject).text,
                       "Recorte desactivado: foto completa")
    }

    func testSelectedPersonReusesPeopleWithoutVision() async throws {
        let env = try env()
        let scene = SyntheticPersonScene.make()
        let image = try XCTUnwrap(scene.image)
        let people = twoPeople(scene)
        let outcome = try await ScanAnalyzer.run(image: image, source: .camera, subject: .default, people: people, env: env,
                                                 timing: TimingLog(url: dir.appendingPathComponent("t.txt")))
        XCTAssertEqual(outcome.subject.people.map(\.id), [1, 2], "ordenadas por cobertura")
        XCTAssertEqual(outcome.subject.chosenIndex, 0, "por defecto la más grande")
        let store = FeedbackImageStore(directory: dir.appendingPathComponent("images", isDirectory: true))
        let model = ResultViewModel(outcome: outcome, env: env, imageStore: store, timing: TimingLog(url: dir.appendingPathComponent("t2.txt")))
        await model.load()
        XCTAssertTrue(model.showsPeopleRow)
        XCTAssertEqual(model.personThumbnails.count, 2)
        XCTAssertEqual(model.currentChoice, .person(0))
        XCTAssertNotNil(model.maskOverlay, "Ver máscara tiene capa")
        XCTAssertEqual(model.maskNotice.text, "Persona principal de 2 · solo ropa · piel excluida")

        // Persona 2: sin pose (recorte de cabeza) ni cara. Sin Vision: en el simulador
        // Vision no está disponible, así que si se ejecutara los pasos serían visionUnavailable.
        await model.choose(.person(1))
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.currentChoice, .person(1))
        XCTAssertEqual(model.outcome.subject.people.map(\.id), [1, 2], "mismas personas reutilizadas")
        XCTAssertEqual(model.outcome.subject.steps, [.headCut])
        XCTAssertFalse(model.outcome.subject.steps.contains(.visionUnavailable))
        XCTAssertEqual(model.outcome.scan.id, outcome.scan.id, "mismo scan")
        let direct = try ScanAnalyzer.analyze(raster: outcome.raster, image: nil,
                                              subject: SubjectOptions(mode: .selectedPerson, selectedIndex: 1), people: people)
        XCTAssertEqual(model.outcome.result, direct.result, "idéntico a la cadena + motor directos (hash incluido)")
        XCTAssertEqual(model.outcome.subject.mask, direct.subject.mask)
        XCTAssertNotEqual(model.outcome.subject.mask, outcome.subject.mask)
        XCTAssertEqual(model.outcome.debug?.analysis, direct.result, "capas recalculadas")
        let updatedOptional = try await env.scans.fetch(id: outcome.scan.id)
        let updated = try XCTUnwrap(updatedOptional)
        XCTAssertEqual(updated.personIndex, 1)
        XCTAssertEqual(updated.subjectMode, "selectedPerson")
        XCTAssertEqual(updated.maskStepValues, [.headCut])
        XCTAssertEqual(updated.rev, 2)
        XCTAssertEqual(updated.top1, direct.result.hits.first?.comboId)
        XCTAssertEqual(updated.scannedAt.timeIntervalSince1970, outcome.scan.scannedAt.timeIntervalSince1970, accuracy: 0.001,
                       "la fecha del scan no cambia (GRDB guarda milisegundos)")

        // "Todas": allPeople, sin persona elegida.
        await model.choose(.all)
        XCTAssertEqual(model.currentChoice, .all)
        XCTAssertNil(model.outcome.subject.chosenIndex)
        let allOptional = try await env.scans.fetch(id: outcome.scan.id)
        let all = try XCTUnwrap(allOptional)
        XCTAssertEqual(all.subjectMode, "allPeople")
        XCTAssertNil(all.personIndex)
        XCTAssertEqual(all.rev, 3)
        XCTAssertTrue(model.maskNotice.text.hasPrefix("Todas las personas (2)"), model.maskNotice.text)

        // Tras votar ya no se cambia de persona (el veredicto es de lo que se vio).
        await model.vote(.yes)
        XCTAssertFalse(model.canChangePerson)
        await model.choose(.person(0))
        XCTAssertEqual(model.currentChoice, .all)
        await model.feedbackImageTask?.value
    }

    func testTwoSyntheticPeopleEachGetsItsClothes() async throws {
        let env = try env()
        let scene = SyntheticPersonScene.makeTwo()
        XCTAssertEqual(scene.people.count, 2)
        let outcome = try await ScanAnalyzer.run(image: try XCTUnwrap(scene.image), source: .manual, subject: .default,
                                                 people: scene.people, env: env,
                                                 timing: TimingLog(url: dir.appendingPathComponent("t.txt")))
        XCTAssertEqual(outcome.subject.steps, [.poseRegions, .skinExcluded])
        let first = Set(outcome.result.swatches.map(\.hex))
        print("ScanAnalyzerSubjectTests: dos personas, persona 1 paleta \(outcome.result.swatches.map { "\($0.hex) \($0.weight)" }) top \(outcome.result.hits.map(\.comboId))")
        XCTAssertTrue(first.contains { $0.hasPrefix("#0a9") || $0.hasPrefix("#099") }, "persona 1: camiseta Green Blue: \(first)")
        XCTAssertEqual(outcome.result.hits.first?.comboId, 12, "persona 1: Green Blue + Isabella = Nº 012")
        XCTAssertEqual(outcome.subject.people.map(\.coverage)[0], outcome.subject.people.map(\.coverage)[1], accuracy: 1e-12)
        let model = ResultViewModel(outcome: outcome, env: env, timing: TimingLog(url: dir.appendingPathComponent("t2.txt")))
        await model.choose(.person(1))
        XCTAssertEqual(model.outcome.subject.steps, [.poseRegions, .skinExcluded])
        let hexes = Set(model.outcome.result.swatches.map(\.hex))
        XCTAssertFalse(hexes.contains { $0.hasPrefix("#0a9") || $0.hasPrefix("#099") }, "la persona 2 no aporta el Green Blue de la 1: \(hexes)")
        print("ScanAnalyzerSubjectTests: persona 2 paleta \(model.outcome.result.swatches.map { "\($0.hex) \($0.weight)" }) top \(model.outcome.result.hits.map(\.comboId))")
        XCTAssertNotEqual(model.outcome.result.hits.first?.comboId, outcome.result.hits.first?.comboId)
        XCTAssertEqual(model.outcome.subject.layers.primary?.instanceId, 2)
    }

    func testPhantomOnlyDetectionAnalyzesFullPhoto() async throws {
        let env = try env()
        let scene = SyntheticPersonScene.make()
        let image = try XCTUnwrap(scene.image)
        let raster = try EngineBridge.rasterize(image)
        let sign = twoPeople(scene)[1]
        // El cartel (bloque sin pose ni cara) no es una persona; la persona sintética sí (pose).
        let screened = SubjectExtractor.rejectPhantoms([scene.person, sign], width: raster.width, height: raster.height)
        XCTAssertEqual(screened.people.map(\.id), [scene.person.id])
        XCTAssertEqual(screened.rejected.map(\.instance.id), [2])
        XCTAssertEqual(screened.rejected.first?.evidence.kind, PersonEvidence.Kind.none)
        XCTAssertEqual(SubjectExtractor.bodyEvidence(for: scene.person, width: raster.width, height: raster.height).kind, .pose)

        let detection = PeopleDetection(people: [], rejectedPhantoms: SubjectExtractor.rejectPhantoms([sign], width: raster.width,
                                                                                                       height: raster.height).rejected)
        let subject = try raster.pixels.withUnsafeBufferPointer { px in
            try SubjectExtractor.mask(detection: detection, rgba: px, width: raster.width, height: raster.height,
                                      stride: raster.stride, options: .default)
        }
        XCTAssertEqual(subject.steps, [.rejectedPhantom, .noPeople])
        XCTAssertNil(subject.mask)
        XCTAssertEqual(subject.rejectedPhantoms.count, 1)
        XCTAssertEqual(MaskStepsText.notice(options: .default, result: subject).text, "Sin persona: foto completa")
        // Foto completa: el mismo análisis que sin recorte.
        let plain = try EngineBridge.analyze(raster: raster, matchOptions: EngineBridge.appMatchOptions)
        let masked = try EngineBridge.analyze(raster: raster, matchOptions: EngineBridge.appMatchOptions, mask: subject.mask)
        XCTAssertEqual(masked, plain)
        // El scan guarda los pasos y 0 personas.
        let info = ScanSubjectInfo(options: .default, result: subject)
        let scan = ScanRecord.make(from: plain, source: .library, assetLocalId: "sim-phantom", subject: info)
        try await env.scans.insert(scan)
        let storedOptional = try await env.scans.fetch(id: scan.id)
        let stored = try XCTUnwrap(storedOptional)
        XCTAssertEqual(stored.maskStepValues, [.rejectedPhantom, .noPeople])
        XCTAssertEqual(stored.maskSteps, "[\"rejectedPhantom\",\"noPeople\"]")
        XCTAssertEqual(stored.peopleCount, 0)
        XCTAssertNil(stored.personIndex)
        XCTAssertEqual(stored.maskCoverage, 0)
        print("ScanAnalyzerSubjectTests: fantasma \(screened.rejected.map { "\($0.evidence)" }) -> pasos \(subject.steps.map(\.rawValue)), top \(plain.hits.map(\.comboId))")
    }

    func testMaskStepsNotices() throws {
        let w = 4, h = 4
        let person = PersonInstance(id: 1, mask: [UInt8](repeating: 255, count: w * h), width: w, height: h)
        func result(_ steps: [MaskFallback], people: [PersonInstance], chosen: Int?, mask: [UInt8]?,
                    persons: [PersonLayers] = []) -> SubjectMaskResult {
            SubjectMaskResult(width: w, height: h, people: people, chosenIndex: chosen, mask: mask, steps: steps, timings: [:],
                              maskCoverage: mask == nil ? 0 : 1,
                              layers: SubjectLayers(width: w, height: h, persons: persons, allPeopleOverlay: [], finalMask: mask))
        }
        let full = [UInt8](repeating: 255, count: w * h)
        XCTAssertEqual(MaskStepsText.notice(options: .default, result: result([.noPeople], people: [], chosen: nil, mask: nil)).text,
                       "Sin persona: foto completa")
        let guardLayer = PersonLayers(personIndex: 0, instanceId: 1, personMask: full, pose: nil, regionMask: full,
                                      faceSampleMask: full, skinRemovedMask: nil, finalMask: full,
                                      steps: [.poseRegions, .skinGuard], skinModel: nil, skinExcludedPixels: 0, skinNote: nil)
        let guarded = MaskStepsText.notice(options: .default,
                                           result: result([.poseRegions, .skinGuard], people: [person], chosen: 0, mask: full,
                                                          persons: [guardLayer]))
        XCTAssertEqual(guarded.text, "Solo ropa · prenda parecida a la piel: no se excluyó")
        XCTAssertTrue(guarded.isFallback)
        let whole = MaskStepsText.notice(options: SubjectOptions(region: .wholePerson, adaptiveSkin: false),
                                         result: result([], people: [person], chosen: 0, mask: full))
        XCTAssertEqual(whole.text, "Persona completa")
        let tooSmall = MaskStepsText.notice(options: .default,
                                            result: result([.headCut, .none], people: [person], chosen: 0, mask: nil))
        XCTAssertEqual(tooSmall.text, "Solo ropa (sin pose: sin la cabeza) · persona demasiado pequeña: foto completa")
    }
}
