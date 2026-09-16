// Evidencia corporal sin Vision: formas sintéticas (bloques, bandas, siluetas, vestido en percha),
// poses, caras y rectángulos de persona construidos a mano; el paso `.rejectedPhantom` de `mask(detection:)`.
import CoreGraphics
import XCTest
import ColorEngine
@testable import SubjectKit

final class PhantomEvidenceTests: XCTestCase {
    static let W = 200, H = 200

    private static func mask(_ fill: (Int, Int) -> Bool) -> [UInt8] {
        var m = [UInt8](repeating: 0, count: W * H)
        for y in 0..<H { for x in 0..<W where fill(x, y) { m[y * W + x] = 255 } }
        return m
    }

    /// Silueta de pie: cabeza (círculo), cuello, torso, brazos separados del cuerpo y dos piernas.
    private static func silhouette(dy: Int = 0, scale: Double = 1) -> [UInt8] {
        mask { x, y in
            let fx = (Double(x) - 100) / scale + 100, fy = (Double(y - dy)) / scale
            let head = (fx - 100) * (fx - 100) + (fy - 30) * (fy - 30) <= 13 * 13
            let neck = abs(fx - 100) <= 5 && fy >= 42 && fy < 50
            let torso = abs(fx - 100) <= 22 && fy >= 50 && fy < 110
            let arms = (abs(fx - 70) <= 5 || abs(fx - 130) <= 5) && fy >= 52 && fy < 105
            let legs = (abs(fx - 89) <= 8 || abs(fx - 111) <= 8) && fy >= 110 && fy < 185
            return head || neck || torso || arms || legs
        }
    }

    private func evidence(_ m: [UInt8], pose: Pose? = nil, face: CGRect? = nil,
                          options: PhantomOptions = .default) -> PersonEvidence {
        SubjectExtractor.bodyEvidence(for: PersonInstance(id: 1, mask: m, width: Self.W, height: Self.H, pose: pose, faceBox: face),
                                      width: Self.W, height: Self.H, options: options)
    }

    func testBlocksBandsAndFullFrameAreRejected() {
        let block = evidence(Self.mask { x, y in x >= 40 && x < 100 && y >= 60 && y < 150 })
        XCTAssertEqual(block.kind, .none)
        XCTAssertEqual(block.extent, 1)
        XCTAssertEqual(block.solidity, 1, accuracy: 1e-12)
        let band = evidence(Self.mask { x, _ in x >= 30 && x < 90 })            // banda vertical de borde a borde
        XCTAssertEqual(band.kind, .none)
        XCTAssertEqual(band.heightSpan, 1)
        let full = evidence([UInt8](repeating: 255, count: Self.W * Self.H))
        XCTAssertEqual(full.kind, .none)
        XCTAssertEqual(full.coverage, 1)
        // Mancha convexa (disco): rellena su envolvente.
        let disc = evidence(Self.mask { x, y in (x - 100) * (x - 100) + (y - 100) * (y - 100) <= 60 * 60 })
        XCTAssertEqual(disc.kind, .none)
        XCTAssertGreaterThan(disc.solidity, 0.95)
        // Silueta de Vision sobre bandas (sim_c047): alta pero de borde a borde, sin cabeza ni piernas.
        let ghost = evidence(Self.mask { x, y in abs(Double(x) - 100 - 10 * sin(Double(y) / 30)) <= 18 + Double(y % 40) / 4 })
        XCTAssertEqual(ghost.kind, .none)
    }

    func testShapeAloneIsNotEnoughByDefault() {
        // Silueta humana plausible sin pose ni cara: por defecto NO es persona (un vestido colgado
        // tiene esta forma); la regla de forma sigue disponible con `acceptShapeOnly`.
        let e = evidence(Self.silhouette())
        XCTAssertEqual(e.kind, .none, "\(e)")
        XCTAssertTrue(e.plausibleShape)
        XCTAssertGreaterThan(e.aspect, 1.2)
        XCTAssertLessThan(e.extent, 0.8)
        XCTAssertLessThan(e.solidity, 0.88)
        XCTAssertLessThan(e.heightSpan, 0.95)
        XCTAssertFalse(PhantomOptions.default.acceptShapeOnly)
        XCTAssertEqual(evidence(Self.silhouette(), options: PhantomOptions(acceptShapeOnly: true)).kind, .shape)
        // Diminuta (< 1 % del raster): tampoco con la regla de forma.
        XCTAssertEqual(evidence(Self.silhouette(scale: 0.15), options: PhantomOptions(acceptShapeOnly: true)).kind, .none)
        // Cortada arriba y abajo por el encuadre sin pose ni cara: no.
        let tall = evidence(Self.mask { x, y in
            (abs(x - 100) <= 22 && y < 150) || ((abs(x - 89) <= 8 || abs(x - 111) <= 8) && y >= 150) || (abs(x - 70) <= 5 && y < 120)
        }, options: PhantomOptions(acceptShapeOnly: true))
        XCTAssertEqual(tall.kind, .none)
        // Vestido en percha (trapecio con tirantes): forma plausible, fantasma por defecto.
        let dress = Self.mask { x, y in
            let fy = Double(y)
            let half = fy < 60 ? 12.0 : 12 + (fy - 60) * 0.35
            return y >= 30 && y < 180 && abs(Double(x) - 100) <= half && !(y < 60 && abs(x - 100) < 6)
        }
        let dressEvidence = evidence(dress)
        XCTAssertEqual(dressEvidence.kind, .none, "\(dressEvidence)")
        // Filtro desactivado: todo es persona.
        let block = PersonInstance(id: 2, mask: Self.mask { x, y in x < 50 && y < 50 }, width: Self.W, height: Self.H)
        let people = [PersonInstance(id: 1, mask: Self.silhouette(), width: Self.W, height: Self.H), block]
        XCTAssertEqual(SubjectExtractor.rejectPhantoms(people, width: Self.W, height: Self.H).people.map(\.id), [])
        XCTAssertEqual(SubjectExtractor.rejectPhantoms(people, width: Self.W, height: Self.H,
                                                       options: PhantomOptions(acceptShapeOnly: true)).people.map(\.id), [1])
        XCTAssertEqual(SubjectExtractor.rejectPhantoms(people, width: Self.W, height: Self.H,
                                                       options: PhantomOptions(enabled: false)).people.map(\.id), [1, 2])
    }

    func testHumanRectangleEvidence() {
        let silhouette = Self.silhouette()
        let box = CGRect(x: 60, y: 10, width: 80, height: 180)     // cuerpo entero de la silueta
        var e = SubjectExtractor.bodyEvidence(for: PersonInstance(id: 1, mask: silhouette, width: Self.W, height: Self.H),
                                              width: Self.W, height: Self.H, options: .default, humanBox: box)
        XCTAssertEqual(e.kind, .humanRectangle, "\(e)")
        XCTAssertEqual(e.humanOverlap, 1, accuracy: 1e-12)
        XCTAssertGreaterThan(e.humanFill, 0.1)
        // Menos de la mitad de la instancia dentro: no.
        let top = CGRect(x: 60, y: 10, width: 80, height: 60)
        e = SubjectExtractor.bodyEvidence(for: PersonInstance(id: 1, mask: silhouette, width: Self.W, height: Self.H),
                                          width: Self.W, height: Self.H, options: .default, humanBox: top)
        XCTAssertEqual(e.kind, .none)
        XCTAssertLessThan(e.humanOverlap, 0.5)
        // Rectángulo enorme casi vacío (relleno < 10 %): no.
        let blob = Self.mask { x, y in (x - 100) * (x - 100) + (y - 100) * (y - 100) <= 10 * 10 }
        e = SubjectExtractor.bodyEvidence(for: PersonInstance(id: 3, mask: blob, width: Self.W, height: Self.H),
                                          width: Self.W, height: Self.H, options: .default,
                                          humanBox: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertEqual(e.kind, .none)
        XCTAssertEqual(e.humanOverlap, 1, accuracy: 1e-12)
        XCTAssertLessThan(e.humanFill, 0.1)
        // Regla desactivada.
        e = SubjectExtractor.bodyEvidence(for: PersonInstance(id: 1, mask: silhouette, width: Self.W, height: Self.H),
                                          width: Self.W, height: Self.H, options: PhantomOptions(humanRectangles: false), humanBox: box)
        XCTAssertEqual(e.kind, .none)
        // Asociación: el rectángulo va a la instancia con más píxeles dentro; una mancha pegada a
        // la persona dentro del mismo rectángulo no lo recibe y sigue siendo fantasma.
        let small = Self.mask { x, y in x >= 120 && x < 135 && y >= 150 && y < 170 && silhouette[y * Self.W + x] == 0 }
        let people = [PersonInstance(id: 7, mask: small, width: Self.W, height: Self.H),
                      PersonInstance(id: 8, mask: silhouette, width: Self.W, height: Self.H)]
        XCTAssertEqual(SubjectExtractor.associateHumanRectangles([box], masks: people.map(\.mask), width: Self.W, height: Self.H),
                       [nil, 0])
        let screened = SubjectExtractor.rejectPhantoms(people, width: Self.W, height: Self.H, options: .default, humanBoxes: [box])
        XCTAssertEqual(screened.people.map(\.id), [8])
        XCTAssertEqual(screened.rejected.map(\.instance.id), [7])
        // Dos rectángulos para la misma instancia: se queda el de más píxeles dentro.
        XCTAssertEqual(SubjectExtractor.associateHumanRectangles([top, box], masks: [silhouette], width: Self.W, height: Self.H), [1])
        XCTAssertEqual(SubjectExtractor.associateHumanRectangles([], masks: [silhouette], width: Self.W, height: Self.H), [nil])
        XCTAssertEqual(PersonEvidence.Kind(rawValue: "humanRectangle"), .humanRectangle)
    }

    func testPoseAndFaceEvidence() {
        // Un bloque (sin forma humana) con dos puntos del torso dentro: pose.
        let block = Self.mask { x, y in x >= 40 && x < 160 && y >= 40 && y < 160 }
        var pose = Pose()
        pose[.leftShoulder] = Keypoint(x: 120, y: 60, confidence: 0.8)
        pose[.rightShoulder] = Keypoint(x: 80, y: 60, confidence: 0.8)
        var e = evidence(block, pose: pose)
        XCTAssertEqual(e.kind, .pose)
        XCTAssertEqual(e.torsoJointsInside, 2)
        // Un solo punto del torso no basta.
        var one = pose
        one[.rightShoulder] = .missing
        XCTAssertEqual(evidence(block, pose: one).kind, .none)
        // Puntos por debajo de la confianza del motor (0,3) no cuentan.
        var weak = pose
        weak[.leftShoulder] = Keypoint(x: 120, y: 60, confidence: 0.2)
        XCTAssertEqual(evidence(block, pose: weak).torsoJointsInside, 1)
        // Tolerancia de 2 px: un hombro justo fuera del borde cuenta; a 5 px no.
        var edge = pose
        edge[.leftShoulder] = Keypoint(x: 161.5, y: 60, confidence: 0.8)
        XCTAssertEqual(evidence(block, pose: edge).torsoJointsInside, 2)
        edge[.leftShoulder] = Keypoint(x: 165.5, y: 60, confidence: 0.8)
        XCTAssertEqual(evidence(block, pose: edge).torsoJointsInside, 1)
        // Brazos y cabeza no son torso.
        var limbs = Pose()
        limbs[.nose] = Keypoint(x: 100, y: 50, confidence: 1)
        limbs[.leftElbow] = Keypoint(x: 120, y: 90, confidence: 1)
        limbs[.rightWrist] = Keypoint(x: 80, y: 120, confidence: 1)
        XCTAssertEqual(evidence(block, pose: limbs).torsoJointsInside, 0)
        // Cara asociada: persona aunque la forma sea un bloque.
        e = evidence(block, face: CGRect(x: 80, y: 20, width: 40, height: 40))
        XCTAssertEqual(e.kind, .face)
        XCTAssertTrue(e.hasFace)
        // Umbrales configurables.
        XCTAssertEqual(evidence(block, pose: pose, options: PhantomOptions(minTorsoJoints: 3)).kind, .none)
    }

    func testMaskDetectionPrefixesRejectedPhantomStep() throws {
        var scene = SyntheticScene(people: 2)
        let p0 = scene.addPerson(0)
        _ = scene.addPerson(1)
        let real = PersonInstance(id: 1, mask: p0.mask, width: scene.width, height: 100, pose: p0.pose, faceSampleMask: p0.face)
        var ghostMask = [UInt8](repeating: 0, count: scene.width * 100)
        for y in 0..<100 { for x in 60..<120 { ghostMask[y * scene.width + x] = 255 } }
        let ghost = PersonInstance(id: 2, mask: ghostMask, width: scene.width, height: 100)
        let screened = SubjectExtractor.rejectPhantoms([real, ghost], width: scene.width, height: 100)
        XCTAssertEqual(screened.people.map(\.id), [1])
        XCTAssertEqual(screened.rejected.first?.evidence.kind, PersonEvidence.Kind.none)
        var detection = PeopleDetection(people: screened.people, timings: [:], warnings: [], unassignedPoses: 0,
                                        unassignedFaces: 0, faces: [nil], discardedPeople: 0, orphanPoses: [], orphanFaces: [])
        detection.rejectedPhantoms = screened.rejected
        let r = try scene.rgba.withUnsafeBufferPointer { px in
            try SubjectExtractor.mask(detection: detection, rgba: px, width: scene.width, height: 100, stride: scene.stride,
                                      options: .default)
        }
        XCTAssertEqual(r.steps.first, .rejectedPhantom)
        XCTAssertEqual(Array(r.steps.dropFirst()), [.poseRegions], "la cadena de la persona real, sin cambios")
        XCTAssertEqual(r.rejectedPhantoms.map(\.instance.id), [2])
        XCTAssertEqual(r.people.map(\.id), [1])
        // Solo el fantasma: foto completa.
        var empty = PeopleDetection(people: [], timings: [:], warnings: [], unassignedPoses: 0, unassignedFaces: 0, faces: [],
                                    discardedPeople: 0, orphanPoses: [], orphanFaces: [])
        empty.rejectedPhantoms = screened.rejected
        let none = try scene.rgba.withUnsafeBufferPointer { px in
            try SubjectExtractor.mask(detection: empty, rgba: px, width: scene.width, height: 100, stride: scene.stride,
                                      options: .default)
        }
        XCTAssertEqual(none.steps, [.rejectedPhantom, .noPeople])
        XCTAssertNil(none.mask)
        XCTAssertEqual(MaskFallback(rawValue: "rejectedPhantom"), .rejectedPhantom)
        // mask(people:) no conoce la detección: sin paso de fantasma.
        let plain = try scene.rgba.withUnsafeBufferPointer { px in
            try SubjectExtractor.mask(people: [], rgba: px, width: scene.width, height: 100, stride: scene.stride, options: .default)
        }
        XCTAssertEqual(plain.steps, [.noPeople])
        XCTAssertTrue(plain.rejectedPhantoms.isEmpty)
    }
}
