// Textos del recorte de sujeto (aviso de Extraer y capas 4–7) frente a lo que SubjectKit hizo
// de verdad, rama por rama, con capas construidas a mano (PersonLayers, RegionDecision) y una
// escena de la cadena real con una persona pequeña pegada a un objeto grande de otro color
// (el caso del bebé en el cochecito, CONTEXT §12):
//  - región pequeña pero suficiente frente a la silueta de la pose y recorte a la silueta;
//  - silueta del cuerpo cuando las regiones no llegan al 15 % de la silueta;
//  - recorte de cabeza con la fracción REAL (no el 18 % fijo) y su motivo (sin pose / pose
//    que no describe a la persona);
//  - respaldo a la silueta (no «persona completa») cuando la máscara final no llega al suelo;
//  - caderas estimadas, modelo de piel de otra persona, brazos fuera sin modelo de piel;
//  - siluetas sin cuerpo descartadas y Vision no disponible.
import XCTest
import ColorEngine
import SubjectKit
@testable import ColorsApp

final class SubjectExplanationTests: XCTestCase {
    private let w = 100, h = 100

    private func mask(_ pixels: Int) -> [UInt8] {
        var m = [UInt8](repeating: 0, count: w * h)
        for i in 0..<min(pixels, m.count) { m[i] = 255 }
        return m
    }

    private func person(id: Int = 1, pixels: Int = 2_000, pose: Pose? = Pose(), face: Bool = true) -> PersonInstance {
        PersonInstance(id: id, mask: mask(pixels), width: w, height: h, pose: pose, faceSampleMask: face ? mask(60) : nil)
    }

    private func decision(_ source: RegionSource, body: Int = 2_000, required: Int = 90, poseRegions: Int? = 150,
                          silhouette: Int? = 600, region: Int = 150, hips: Bool = false, headCut: Double? = nil,
                          upperArmsDropped: Bool = false, sleeve: (Int, Int)? = nil) -> RegionDecision {
        RegionDecision(source: source, bodyPixels: body, requiredPixels: required, poseRegionPixels: poseRegions,
                       silhouettePixels: silhouette, regionPixels: region, regionPose: nil, hipsEstimated: hips,
                       headCutFraction: headCut, regionOptions: .default, upperArmsDropped: upperArmsDropped,
                       sleevePixels: sleeve?.1, sleeveMatchPixels: sleeve?.0)
    }

    private let skinModel = SkinModel(mean: Lab(L: 62, a: 14, b: 18), covariance: [Double](repeating: 0, count: 9),
                                      inverseCovariance: [Double](repeating: 0, count: 9), sampleCount: 120)

    private func layer(_ p: PersonInstance, index: Int = 0, steps: [MaskFallback], decision: RegionDecision?,
                       final: Int = 150, excluded: Int = 0, model: SkinModel? = nil, sample: Bool = true,
                       sampleSource: Int? = nil, fallback: RegionSource? = nil) -> PersonLayers {
        PersonLayers(personIndex: index, instanceId: p.id, personMask: p.mask, pose: p.pose, regionMask: mask(final),
                     faceSampleMask: sample ? mask(60) : nil, skinRemovedMask: excluded > 0 ? mask(excluded) : nil,
                     finalMask: mask(final), steps: steps, skinModel: model, skinExcludedPixels: excluded, skinNote: nil,
                     regionDecision: decision, skinSampleSource: sample ? (sampleSource ?? index) : nil,
                     silhouetteMask: decision?.silhouettePixels.map(mask), fallbackSource: fallback)
    }

    private func result(people: [PersonInstance], persons: [PersonLayers], steps: [MaskFallback], mask finalMask: [UInt8]?,
                        chosen: Int? = 0, rejected: [RejectedPerson] = []) -> SubjectMaskResult {
        SubjectMaskResult(width: w, height: h, people: people, chosenIndex: chosen, mask: finalMask, steps: steps,
                          timings: [:], maskCoverage: finalMask.map { MaskOps.coverage($0, width: w, height: h) } ?? 0,
                          layers: SubjectLayers(width: w, height: h, persons: persons,
                                                allPeopleOverlay: [UInt8](repeating: 0, count: w * h), finalMask: finalMask),
                          rejectedPhantoms: rejected)
    }

    func testSmallButSufficientRegionIsRelativeToPoseSilhouette() {
        // 150 px de región = 1,5 % de la foto (< 2 %), pero el 25 % de la silueta de 600 px (mínimo 15 %).
        let p = person()
        let l = layer(p, steps: [.poseRegions, .skinExcluded], decision: decision(.poseRegions), excluded: 12, model: skinModel)
        let r = result(people: [p], persons: [l], steps: l.steps, mask: mask(150))
        let options = SubjectOptions.default
        XCTAssertEqual(SubjectExplanation.notice(options: options, result: r).text, "Solo ropa · piel excluida")
        let text = SubjectExplanation.maskLayer(options: options, result: r, maskMs: 1)
        let facts = text.facts.joined(separator: "\n")
        XCTAssertTrue(facts.contains("Región de ropa pequeña pero suficiente para esta persona: 150 px, el 25\u{00A0}% de la silueta de su pose (600 px; mínimo 15\u{00A0}% (90 px))"), facts)
        XCTAssertTrue(facts.contains("Se recortó a la silueta del cuerpo: se excluyen objetos pegados"), facts)
        XCTAssertTrue(facts.contains("Quedan fuera \(SubjectExplanation.count(1_400)) px de la máscara de Vision (70\u{00A0}%)"), facts)
        XCTAssertTrue(facts.contains("Pasos: Regiones de la pose → Piel excluida"), facts)
        XCTAssertNil(text.warning)
    }

    func testSilhouetteWhenRegionsAreBelowFifteenPercent() {
        let p = person()
        let d = decision(.poseSilhouette, poseRegions: 48, silhouette: 600, region: 600)
        let l = layer(p, steps: [.poseRegions], decision: d, final: 600)
        let r = result(people: [p], persons: [l], steps: [.poseRegions], mask: mask(600))
        let options = SubjectOptions(adaptiveSkin: false)
        XCTAssertEqual(SubjectExplanation.notice(options: options, result: r).text, "Silueta del cuerpo")
        XCTAssertEqual(SubjectExplanation.stepTitles(result: r), ["Silueta del cuerpo (pose)"])
        let facts = SubjectExplanation.maskLayer(options: options, result: r, maskMs: 1).facts.joined(separator: "\n")
        XCTAssertTrue(facts.contains("Se usó la silueta del cuerpo: la región de ropa (48 px) era solo el 8\u{00A0}% de la silueta de la pose (600 px; mínimo 15\u{00A0}% (90 px))"), facts)
        XCTAssertFalse(facts.contains("Persona completa"), facts)
    }

    func testHeadCutUsesRealFractionAndReason() {
        // Sin pose, con cara: la fracción la fija la cara (27 %), no el 18 % fijo.
        let noPose = person(pose: nil)
        let d = decision(.headCut, poseRegions: nil, silhouette: nil, region: 1_460, headCut: 0.2727)
        let l = layer(noPose, steps: [.headCut, .skinExcluded], decision: d, final: 1_400, excluded: 60, model: skinModel)
        let r = result(people: [noPose], persons: [l], steps: l.steps, mask: mask(1_400))
        let pose = SubjectExplanation.poseLayer(options: .default, result: r)
        XCTAssertEqual(pose.warning, "Sin pose: se quitó el 27\u{00A0}% superior de la persona (hasta la barbilla según la cara) en lugar de usar la pose.")
        XCTAssertEqual(SubjectExplanation.stepTitles(result: r), ["Recorte de cabeza (27\u{00A0}% superior)", "Piel excluida"])
        XCTAssertEqual(SubjectExplanation.notice(options: .default, result: r).text, "Sin la cabeza (sin pose) · piel excluida")

        // Con pose cuya silueta no llega al suelo (0,05 % de 10.000 px = 5 px): la pose no describe a la persona.
        let withPose = person()
        let d2 = decision(.headCut, poseRegions: 2, silhouette: 3, region: 1_640, headCut: SubjectExtractor.headCutFraction)
        let l2 = layer(withPose, steps: [.poseRegions, .headCut], decision: d2, final: 1_640, sample: false)
        let r2 = result(people: [withPose], persons: [l2], steps: l2.steps, mask: mask(1_640))
        let options = SubjectOptions(adaptiveSkin: false)
        XCTAssertEqual(SubjectExplanation.poseLayer(options: options, result: r2).warning,
                       "La pose no describe a esta persona (su silueta mide 3 px, mínimo 5 px): se quitó el 18\u{00A0}% superior de la persona.")
        XCTAssertEqual(SubjectExplanation.stepTitles(result: r2), ["Pose sin silueta útil", "Recorte de cabeza (18\u{00A0}% superior)"])
        XCTAssertEqual(SubjectExplanation.notice(options: options, result: r2).text, "Sin la cabeza (pose incompleta)")
    }

    func testFallbackToSilhouetteIsNotCalledWholePerson() {
        let p = person()
        // Regiones de 80 px (20 % de la silueta de 400 px: suficientes), pero tras quitar la piel la
        // máscara final se queda en 3 px, por debajo del suelo de 5 px: respaldo a la silueta.
        let d = decision(.poseRegions, required: 60, poseRegions: 80, silhouette: 400, region: 80)
        let l = layer(p, steps: [.poseRegions, .wholePerson], decision: d, final: 3, fallback: .poseSilhouette)
        let r = result(people: [p], persons: [l], steps: l.steps, mask: mask(400))
        let options = SubjectOptions(adaptiveSkin: false)
        let notice = SubjectExplanation.notice(options: options, result: r)
        XCTAssertEqual(notice.text, "Solo ropa · recorte demasiado pequeño: silueta del cuerpo")
        XCTAssertTrue(notice.isFallback)
        XCTAssertEqual(SubjectExplanation.stepTitles(result: r), ["Regiones de la pose", "Respaldo: silueta del cuerpo"])
        let warning = SubjectExplanation.maskLayer(options: options, result: r, maskMs: 1).warning ?? ""
        XCTAssertTrue(warning.contains("La máscara final (3 px) no llegaba al mínimo de 5 px"), warning)
        XCTAssertTrue(warning.contains("se usó la silueta del cuerpo según la pose"), warning)
    }

    func testHipsDonorSkinAndArmsWithoutSkinModel() {
        // Persona 1 sin cara con el modelo de la cara de la persona 2 y caderas estimadas.
        let a = person(id: 1, face: false), b = person(id: 2, pixels: 1_500)
        let la = layer(a, index: 0, steps: [.poseRegions, .skinExcluded], decision: decision(.poseRegions, hips: true),
                       excluded: 20, model: skinModel, sampleSource: 1)
        let r = result(people: [a, b], persons: [la], steps: la.steps, mask: mask(130))
        XCTAssertEqual(SubjectExplanation.notice(options: .default, result: r).text,
                       "Persona principal de 2 · solo ropa · piel excluida con la cara de la persona 2")
        let skin = SubjectExplanation.skinLayer(options: .default, result: r).facts.joined(separator: "\n")
        XCTAssertTrue(skin.contains("Sin cara utilizable: modelo de la cara de la persona 2 (120 muestras"), skin)
        let pose = SubjectExplanation.poseLayer(options: .default, result: r).facts.joined(separator: "\n")
        XCTAssertTrue(pose.contains("Caderas estimadas (plano medio: la pose no las veía); sin piernas"), pose)

        // Sin cara en la foto: sin modelo de piel, los brazos se quitan (no parecen mangas).
        let c = person(face: false)
        let lc = layer(c, steps: [.poseRegions], decision: decision(.poseRegions, upperArmsDropped: true, sleeve: (40, 200)),
                       sample: false)
        let rc = result(people: [c], persons: [lc], steps: lc.steps, mask: mask(150))
        XCTAssertEqual(SubjectExplanation.notice(options: .default, result: rc).text,
                       "Solo ropa · sin cara visible: piel sin excluir · brazos fuera")
        XCTAssertTrue(SubjectExplanation.poseLayer(options: .default, result: rc).facts
            .contains("Sin modelo de piel, brazos fuera: solo el 20\u{00A0}% se parece a la prenda del torso (mangas desde 70\u{00A0}%)"))
        XCTAssertEqual(SubjectExplanation.skinLayer(options: .default, result: rc).warning,
                       "No se ve ninguna cara utilizable (de espaldas, gafas, mascarilla) ni hay otra persona con cara: piel sin excluir; los brazos se quitaron de la región (capa 5).")
    }

    func testRejectedPhantomsAndVisionUnavailable() {
        let phantom = PersonInstance(id: 1, mask: mask(3_000), width: w, height: h)
        let evidence = PersonEvidence(kind: .none, torsoJointsInside: 0, hasFace: false, coverage: 0.3, aspect: 1,
                                      extent: 1, solidity: 1)
        let r = result(people: [], persons: [], steps: [.rejectedPhantom, .noPeople], mask: nil, chosen: nil,
                       rejected: [RejectedPerson(instance: phantom, evidence: evidence)])
        let notice = SubjectExplanation.notice(options: .default, result: r)
        XCTAssertEqual(notice.text, "Sin persona (1 silueta sin cuerpo descartada): foto completa")
        XCTAssertTrue(notice.isFallback)
        XCTAssertEqual(SubjectExplanation.stepTitles(result: r), ["Siluetas sin cuerpo descartadas (1)", "Sin personas"])
        let people = SubjectExplanation.peopleLayer(options: .default, result: r, chosenIds: [], visionMs: 0)
        XCTAssertEqual(people.warning, "Vision devolvió 1 silueta sin cuerpo (personas fantasma): se descartó y se analiza la foto completa.")
        XCTAssertTrue(people.facts.contains("Descartada 1: 30,0\u{00A0}% de la foto"), people.facts.joined(separator: "\n"))

        let unavailable = result(people: [], persons: [], steps: [.visionUnavailable], mask: nil, chosen: nil)
        XCTAssertEqual(SubjectExplanation.notice(options: .default, result: unavailable).text, "Vision no disponible: foto completa")
        XCTAssertEqual(SubjectExplanation.maskLayer(options: .default, result: unavailable, maskMs: 0).warning,
                       "Sin máscara: el motor analiza la foto completa.")
    }

    /// Cadena real: una persona pequeña (la escena sintética en una esquina de 1024 × 1024) cuya
    /// máscara de instancia incluye un objeto grande marrón oscuro pegado a ella (más grande que su
    /// ropa). La región se juzga contra la silueta de la propia persona (sin respaldo a la persona
    /// completa), la silueta deja fuera el objeto y la paleta no contiene su color.
    func testSmallPersonAttachedToLargeObjectKeepsClothingAndDropsObject() async throws {
        let scene = SyntheticPersonScene.make()
        let size = 1024, ox = 0, oy = 600
        let brown = (r: UInt8(59), g: UInt8(40), b: UInt8(28))
        var rgb = [UInt8](repeating: 0, count: size * size * 3)
        var instance = [UInt8](repeating: 0, count: size * size)
        var sample = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let d = (y * size + x) * 3
                (rgb[d], rgb[d + 1], rgb[d + 2]) = (217, 211, 199)
            }
        }
        for y in 0..<scene.height {
            for x in 0..<scene.width {
                let s = (y * scene.width + x) * 3
                let t = ((y + oy) * size + x + ox)
                (rgb[t * 3], rgb[t * 3 + 1], rgb[t * 3 + 2]) = (scene.rgb[s], scene.rgb[s + 1], scene.rgb[s + 2])
                instance[t] = scene.personMask[y * scene.width + x]
                sample[t] = scene.faceSample[y * scene.width + x]
            }
        }
        // Objeto pegado a la persona (a la altura de sus manos y piernas), en la misma instancia (cochecito).
        for y in 870..<1000 {
            for x in 226..<640 {
                let t = y * size + x
                (rgb[t * 3], rgb[t * 3 + 1], rgb[t * 3 + 2]) = (brown.r, brown.g, brown.b)
                instance[t] = 255
            }
        }
        var pose = scene.pose
        for j in Joint.allCases {
            let k = pose[j]
            pose[j] = Keypoint(x: k.x + Double(ox), y: k.y + Double(oy), confidence: k.confidence)
        }
        let person = PersonInstance(id: 1, mask: instance, width: size, height: size, pose: pose, faceSampleMask: sample)
        let image = try XCTUnwrap(PPMImage(width: size, height: size, rgb: rgb).makeCGImage())
        let analysis = try await Task.detached {
            try ScanAnalyzer.analyze(image: image, subject: .default, people: [person])
        }.value
        let s = analysis.subject
        let chosen = try XCTUnwrap(s.layers.persons.first?.regionDecision)
        XCTAssertTrue(s.steps.contains(.poseRegions), "\(s.steps)")
        XCTAssertFalse(s.steps.contains(.wholePerson), "\(s.steps)")
        let text = SubjectExplanation.maskLayer(options: .default, result: s, maskMs: 1)
        let facts = text.facts.joined(separator: "\n")
        let small = Double(chosen.regionPixels) / Double(size * size) < SubjectExplanation.smallRegionFraction
        switch chosen.source {
        case .poseRegions:
            XCTAssertTrue(facts.contains(small ? "Región de ropa pequeña pero suficiente para esta persona" : "Región de ropa suficiente"), facts)
        default:
            XCTAssertTrue(facts.contains("Se usó la silueta del cuerpo"), facts)
        }
        XCTAssertLessThan(Double(chosen.regionPixels) / Double(size * size), 0.05, "persona pequeña en la foto")
        XCTAssertTrue(facts.contains("Se recortó a la silueta del cuerpo: se excluyen objetos pegados"), facts)
        let objectLab = srgbToLab(r: brown.r, g: brown.g, b: brown.b)
        let nearest = analysis.result.swatches.map { deltaE2000($0.lab, objectLab) }.min() ?? .infinity
        XCTAssertGreaterThan(nearest, 10, "la paleta no contiene el marrón del objeto: \(analysis.result.swatches.map(\.hex))")
        print("SubjectExplanationTests: pasos \(s.steps.map(\.rawValue)); \(facts.replacingOccurrences(of: "\n", with: " | ")); paleta \(analysis.result.swatches.map(\.hex))")
    }
}
