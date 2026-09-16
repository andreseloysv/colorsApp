// Separación de instancias fusionadas sin Vision: instancias (PersonInstance),
// poses, caras y semillas construidas a mano. Comprueba las semillas del
// contrato, la regla de separación (2 o más semillas, eje dentro, etiquetas
// pequeñas reasignadas), la unión de partes de una misma semilla, splitFrom,
// ids, cobertura y bbox recalculados, el límite de 8 personas y los pasos
// .splitByPose / .splitByFace en la cadena.
import CoreGraphics
import XCTest
import ColorEngine
@testable import SubjectKit

final class SplitTests: XCTestCase {
    let w = 120, h = 100

    /// Rectángulo x0...x1, y0...y1 (inclusivos) a 255.
    private func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> [UInt8] {
        var m = [UInt8](repeating: 0, count: w * h)
        for y in y0...y1 { for x in x0...x1 { m[y * w + x] = 255 } }
        return m
    }

    /// Pose de frente de SyntheticScene centrada en x = cx: cuello (cx, 30), hombros
    /// cx ± 10 (anchura 20), caderas cx ± 8 a y = 60, nariz (cx, 15).
    private func pose(_ cx: Double, hips: Bool = true) -> Pose {
        var p = Pose()
        func set(_ j: Joint, _ x: Double, _ y: Double) { p[j] = Keypoint(x: cx + x, y: y, confidence: 0.9) }
        set(.nose, 0, 15); set(.neck, 0, 30)
        set(.leftShoulder, 10, 30); set(.rightShoulder, -10, 30)
        set(.leftElbow, 15, 45); set(.rightElbow, -15, 45)
        if hips {
            set(.leftHip, 8, 60); set(.rightHip, -8, 60); set(.root, 0, 60)
        }
        return p
    }

    /// Cara sin landmarks (solo rectángulo), como las que Vision da en un perfil.
    private func face(_ cx: Double, _ cy: Double, size: Double) -> FaceLandmarkPoints {
        FaceLandmarkPoints(leftEye: [], rightEye: [], outerLips: [],
                           boundingBox: CGRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size))
    }

    /// Rectángulo de persona de Vision que ES el cuerpo de esa cara (cabeza arriba, cuerpo
    /// debajo): lo que la regla `requireBodyForFaceSeeds` exige a una semilla de cara.
    private func body(of f: FaceLandmarkPoints) -> CGRect {
        let b = f.boundingBox
        return CGRect(x: b.minX - b.width, y: b.minY, width: 3 * b.width, height: 6 * b.height)
    }

    /// Opciones sin la regla de evidencia corporal: las caras sintéticas de estos tests no
    /// llevan rectángulo de persona (la regla tiene sus propios tests más abajo).
    private let relaxed = SplitOptions(requireBodyForFaceSeeds: false)

    private func pixels(_ m: [UInt8]) -> Int { m.filter { $0 >= 128 }.count }

    // MARK: - Semillas

    func testSeedsFromPosesAndFaces() {
        // Pose con caderas: cuello -> raíz, half_width 0,55 · 20, ancho de cara estimado 0,45 · 20.
        var s = PersonSplitter.seeds(poses: [pose(30)], faces: [])
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].kind, .pose)
        XCTAssertEqual(s[0].seed, PersonSeed(x0: 30, y0: 30, x1: 30, y1: 60, halfWidth: 0.55 * 20))
        XCTAssertEqual(s[0].faceWidth, 0.45 * 20, accuracy: 1e-12)
        XCTAssertEqual(s[0].poseIndex, 0)

        // Sin caderas: extrapolado 1,6 · anchura de hombros hacia abajo.
        s = PersonSplitter.seeds(poses: [pose(30, hips: false)], faces: [])
        XCTAssertEqual(s[0].seed.y1, 30 + 1.6 * 20, accuracy: 1e-12)
        XCTAssertEqual(s[0].seed.x1, 30)

        // Un solo hombro + cuello: anchura = 2 · |hombro − cuello|; sin cuello ni dos hombros: sin semilla.
        var one = pose(30)
        one[.rightShoulder] = .missing
        XCTAssertEqual(PersonSplitter.seeds(poses: [one], faces: [])[0].seed.halfWidth, 0.55 * 20, accuracy: 1e-12)
        var none = pose(30)
        none[.neck] = .missing
        none[.rightShoulder] = .missing
        XCTAssertTrue(PersonSplitter.seeds(poses: [none], faces: []).isEmpty)
        // Hombro bajo la confianza mínima (0,3): no cuenta.
        var low = pose(30)
        low[.neck] = Keypoint(x: 30, y: 30, confidence: 0.29)
        low[.rightShoulder] = Keypoint(x: 20, y: 30, confidence: 0.29)
        XCTAssertTrue(PersonSplitter.seeds(poses: [low], faces: []).isEmpty)

        // Fuera del contrato del motor (semiancho 0,55 · 2e6 > 2^20, NaN): se descarta sin lanzar.
        var huge = pose(30)
        huge[.leftShoulder] = Keypoint(x: 1_000_000, y: 30, confidence: 0.9)
        huge[.rightShoulder] = Keypoint(x: -1_000_000, y: 30, confidence: 0.9)
        XCTAssertTrue(PersonSplitter.seeds(poses: [huge], faces: []).isEmpty)
        XCTAssertFalse(PersonSplitter.engineAccepts(PersonSeed(x0: .nan, y0: 0, x1: 0, y1: 0, halfWidth: 1)))
        XCTAssertFalse(PersonSplitter.engineAccepts(PersonSeed(x0: 0, y0: 0, x1: 0, y1: 0, halfWidth: 0)))
        XCTAssertTrue(PersonSplitter.engineAccepts(PersonSeed(x0: 1_048_576, y0: 0, x1: 0, y1: 0, halfWidth: 1_048_576)))

        // Cara a < 0,8 · ancho de la nariz: una sola semilla (la de la pose) con esa cara;
        // half_width = max(0,55 · 20, 0,6 · 30) = 18.
        s = PersonSplitter.seeds(poses: [pose(30)], faces: [face(33, 14, size: 30)])
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].kind, .pose)
        XCTAssertEqual(s[0].faceIndex, 0)
        XCTAssertEqual(s[0].seed.halfWidth, 18, accuracy: 1e-12)
        XCTAssertEqual(s[0].faceWidth, 30)

        // Cara lejos (a 0,8 · ancho o más): semilla de cara aparte desde la base del
        // rectángulo, 3 · alto hacia abajo, half_width 1,1 · ancho. Orden: poses y luego caras.
        s = PersonSplitter.seeds(poses: [pose(30)], faces: [face(90, 14, size: 16)])
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[1].kind, .face)
        XCTAssertNil(s[1].pose)
        XCTAssertEqual(s[1].seed.x0, 90, accuracy: 1e-12)
        XCTAssertEqual(s[1].seed.y0, 22, accuracy: 1e-12)
        XCTAssertEqual(s[1].seed.y1, 22 + 3 * 16, accuracy: 1e-12)
        XCTAssertEqual(s[1].seed.halfWidth, 1.1 * 16, accuracy: 1e-12)
        // Justo en el límite (distancia = 0,8 · ancho) no se emparejan.
        s = PersonSplitter.seeds(poses: [pose(30)], faces: [face(30 + 0.8 * 20, 15, size: 20)])
        XCTAssertEqual(s.map(\.kind), [.pose, .face])
        // Dos caras cerca de la misma pose: la más cercana se fusiona; la otra es semilla de cara.
        s = PersonSplitter.seeds(poses: [pose(30)], faces: [face(38, 15, size: 20), face(31, 15, size: 20)])
        XCTAssertEqual(s.map(\.kind), [.pose, .face])
        XCTAssertEqual(s[0].faceIndex, 1)
    }

    // MARK: - Separación

    func testFusedInstanceSplitsIntoTwoPeople() throws {
        let fused = rect(8, 5, 112, 99)
        let inst = PersonInstance(id: 1, mask: fused, width: w, height: h)
        let poses = [pose(30), pose(90)]
        let seeds = PersonSplitter.seeds(poses: poses, faces: [])
        let out = try PersonSplitter.apply(instances: [inst], poses: poses, faces: [], seeds: seeds, width: w, height: h)
        XCTAssertEqual(out.people.count, 2)
        XCTAssertEqual(out.people.map(\.splitFrom), [1, 1])
        XCTAssertEqual(Set(out.people.map(\.id)), [2, 3], "ids nuevos mayores que los de Vision")
        XCTAssertEqual(out.splits.count, 1)
        XCTAssertEqual(out.splits[0].step, .splitByPose)
        XCTAssertEqual(out.splits[0].labelPixels.reduce(0, +), pixels(fused))
        XCTAssertEqual(out.unassignedPoses, 0)
        // Disjuntas, su unión es la instancia, frontera en el punto medio (mismo semiancho).
        let a = try XCTUnwrap(out.people.first { $0.pose == poses[0] })
        let b = try XCTUnwrap(out.people.first { $0.pose == poses[1] })
        for i in 0..<(w * h) {
            XCTAssertFalse(a.mask[i] != 0 && b.mask[i] != 0)
            XCTAssertEqual(fused[i] >= 128, a.mask[i] >= 128 || b.mask[i] >= 128)
        }
        XCTAssertEqual(a.bbox, CGRect(x: 8, y: 5, width: 52, height: 95), "bbox recalculada: x 8...59")
        XCTAssertEqual(b.bbox, CGRect(x: 60, y: 5, width: 53, height: 95))
        XCTAssertEqual(a.coverage, Double(52 * 95) / Double(w * h), accuracy: 1e-12)
        XCTAssertEqual(out.people.map(\.coverage), out.people.map(\.coverage).sorted(by: >), "orden por cobertura")
        XCTAssertEqual(a.splitStep, .splitByPose)

        // La cadena marca el paso y recorta la ropa de la persona separada con su pose.
        let rgba = [UInt8](repeating: 200, count: w * h * 4)
        let r = try rgba.withUnsafeBufferPointer { px in
            try SubjectExtractor.mask(people: out.people, rgba: px, width: w, height: h,
                                      stride: w * 4, options: SubjectOptions(adaptiveSkin: false))
        }
        XCTAssertEqual(r.steps.first, .splitByPose)
        XCTAssertTrue(r.steps.contains(.poseRegions))
        XCTAssertEqual(r.layers.primary?.instanceId, out.people[0].id)
        XCTAssertEqual(r.layers.primary?.steps.first, .splitByPose)
    }

    func testHeadSegmentKeepsEachFaceWithItsPerson() throws {
        // Pose izquierda con su cara encima del cuello y una cara ancha sin pose a la derecha:
        // sin el segmento de cabeza, el centro de la cara izquierda (30, 15) quedaría más cerca
        // (normalizado) del eje de la cara derecha (1,35) que del cuello de su pose (1,36).
        let fused = rect(8, 0, 112, 99)
        let inst = PersonInstance(id: 1, mask: fused, width: w, height: h)
        let poses = [pose(30)]
        let faces = [face(30, 15, size: 16), face(70, 20, size: 30)]
        let seeds = PersonSplitter.seeds(poses: poses, faces: faces)
        XCTAssertEqual(seeds.map(\.kind), [.pose, .face])
        XCTAssertEqual(PersonSplitter.headSegment(seeds[0]), PersonSeed(x0: 30, y0: 15, x1: 30, y1: 30, halfWidth: 8))
        XCTAssertEqual(PersonSplitter.headSegment(seeds[1]), PersonSeed(x0: 70, y0: 20, x1: 70, y1: 35, halfWidth: 15))
        let out = try PersonSplitter.apply(instances: [inst], poses: poses, faces: faces, seeds: seeds, width: w,
                                           height: h, humanBoxes: faces.map(body), options: .default)
        let split = try XCTUnwrap(out.splits.first)
        XCTAssertEqual(split.segments.count, 4)
        XCTAssertEqual(split.segmentOwner, [0, 1, 0, 1])
        XCTAssertEqual(split.step, .splitByFace)
        XCTAssertEqual(out.people.count, 2)
        let left = try XCTUnwrap(out.people.first { $0.pose != nil })
        let right = try XCTUnwrap(out.people.first { $0.pose == nil })
        for f in faces {
            let inLeft = MaskOps.value(left.mask, width: w, height: h, x: Double(f.center.x), y: Double(f.center.y)) >= 128
            let inRight = MaskOps.value(right.mask, width: w, height: h, x: Double(f.center.x), y: Double(f.center.y)) >= 128
            XCTAssertNotEqual(inLeft, inRight)
        }
        XCTAssertEqual(left.mask[15 * w + 30], 255, "la cara izquierda es de la pose izquierda")
        XCTAssertEqual(right.mask[20 * w + 70], 255)
        XCTAssertEqual(out.faces[out.people.firstIndex(of: left)!]?.boundingBox, faces[0].boundingBox)
        // Etiquetas del motor por segmento, reproducibles.
        let again = try splitInstance(mask: fused, width: w, height: h, seeds: split.segments)
        XCTAssertEqual(again.labels, split.labels)
    }

    func testSingleSeedOrEmptyDoesNotSplit() throws {
        let fused = rect(8, 5, 112, 99)
        let inst = PersonInstance(id: 4, mask: fused, width: w, height: h)
        let poses = [pose(30)]
        let out = try PersonSplitter.apply(instances: [inst], poses: poses, faces: [],
                                           seeds: PersonSplitter.seeds(poses: poses, faces: []), width: w, height: h)
        XCTAssertEqual(out.people.count, 1)
        XCTAssertNil(out.people[0].splitFrom)
        XCTAssertEqual(out.people[0].id, 4)
        XCTAssertEqual(out.people[0].pose, poses[0], "asociación de siempre")
        XCTAssertTrue(out.splits.isEmpty)
        let empty = try PersonSplitter.apply(instances: [inst], poses: [], faces: [], seeds: [], width: w, height: h)
        XCTAssertEqual(empty.people, [PersonInstance(id: 4, mask: fused, width: w, height: h)])
    }

    func testSeedCountsOnlyWithAxisInside() throws {
        // Persona izquierda sola (x 8...52). Semilla de cara con el punto superior a 3 px
        // del borde (dentro de la máscara dilatada 0,25 · 40 = 10) pero el eje fuera: no cuenta.
        let left = PersonInstance(id: 1, mask: rect(8, 5, 52, 99), width: w, height: h)
        let poses = [pose(30)]
        var seeds = PersonSplitter.seeds(poses: poses, faces: [])
        let outside = SubjectSeed(seed: PersonSeed(x0: 55.5, y0: 20.5, x1: 55.5, y1: 90, halfWidth: 20), kind: .face,
                                  face: face(55.5, 10, size: 40), faceWidth: 40)
        let m = PersonSplitter.membership(outside, mask: left.mask, width: w, height: h)
        XCTAssertTrue(m.touches)
        XCTAssertFalse(m.faceInside)
        XCTAssertEqual(m.topDistance, 3, accuracy: 1e-12)
        XCTAssertEqual(m.axisInside, 0)
        XCTAssertFalse(m.counts)
        var out = try PersonSplitter.apply(instances: [left], poses: poses, faces: [], seeds: seeds + [outside],
                                           width: w, height: h, options: relaxed)
        XCTAssertEqual(out.people.count, 1)
        XCTAssertTrue(out.splits.isEmpty)
        XCTAssertEqual(out.seedInstance, [0, nil])

        // El mismo eje dentro de la máscara (x = 46) sí cuenta y separa por cara.
        let inside = SubjectSeed(seed: PersonSeed(x0: 46, y0: 20, x1: 46, y1: 90, halfWidth: 4), kind: .face,
                                 face: face(46, 10, size: 12), faceWidth: 12)
        seeds.append(inside)
        out = try PersonSplitter.apply(instances: [left], poses: poses, faces: [], seeds: seeds, width: w, height: h,
                                       options: relaxed)
        XCTAssertEqual(out.people.count, 2)
        XCTAssertEqual(out.splits.first?.step, .splitByFace)
        let facePerson = try XCTUnwrap(out.people.first { $0.pose == nil })
        XCTAssertEqual(facePerson.splitStep, .splitByFace)
        XCTAssertEqual(out.faces[out.people.firstIndex(of: facePerson)!]?.boundingBox, inside.face?.boundingBox)
    }

    func testSmallLabelIsReassignedToLargestNeighbor() throws {
        let fused = rect(8, 5, 112, 99)
        let inst = PersonInstance(id: 1, mask: fused, width: w, height: h)
        let poses = [pose(30), pose(90)]
        // Tercera semilla diminuta (un punto con half_width 0,5) en la frontera: < 0,5 % del raster.
        let tiny = SubjectSeed(seed: PersonSeed(x0: 50.5, y0: 50.5, x1: 50.5, y1: 50.5, halfWidth: 0.5), kind: .face,
                               faceWidth: 2)
        let seeds = PersonSplitter.seeds(poses: poses, faces: []) + [tiny]
        let out = try PersonSplitter.apply(instances: [inst], poses: poses, faces: [], seeds: seeds, width: w, height: h,
                                           options: relaxed)
        XCTAssertEqual(out.people.count, 2)
        let split = try XCTUnwrap(out.splits.first)
        XCTAssertEqual(split.seeds.count, 3)
        // `apply` marca la evidencia corporal de cada semilla, así que se busca por su eje.
        let tinyIndex = try XCTUnwrap(split.seeds.firstIndex { $0.seed == tiny.seed })
        XCTAssertGreaterThan(split.labelPixels[tinyIndex], 0)
        XCTAssertLessThan(Double(split.labelPixels[tinyIndex]), PersonSplitter.minSplitCoverage * Double(w * h))
        // Sus píxeles van a la vecina: la unión de las dos personas sigue siendo la instancia entera.
        XCTAssertEqual(out.people.map { pixels($0.mask) }.reduce(0, +), pixels(fused))
        XCTAssertEqual(split.personIdBySeed[tinyIndex], out.people.first { $0.pose == poses[0] }?.id,
                       "la etiqueta pequeña toca a la izquierda (la mayor de sus vecinas)")
        XCTAssertEqual(split.step, .splitByPose, "la semilla de cara reasignada no cuenta como separación por cara")
    }

    func testSeedInOverlappingInstancesMergesItsParts() throws {
        // Vision da dos instancias que se pisan (x 8...100 y 20...112) y una tercera que
        // solo contiene a la persona derecha (x 84...112, y 25...99).
        let a = PersonInstance(id: 1, mask: rect(8, 5, 100, 99), width: w, height: h)
        let b = PersonInstance(id: 2, mask: rect(20, 5, 112, 99), width: w, height: h)
        let c = PersonInstance(id: 3, mask: rect(84, 25, 112, 99), width: w, height: h)
        let poses = [pose(30), pose(90)]
        let seeds = PersonSplitter.seeds(poses: poses, faces: [])
        let out = try PersonSplitter.apply(instances: [a, b, c], poses: poses, faces: [], seeds: seeds, width: w, height: h)
        XCTAssertEqual(out.splits.map(\.instanceId), [1, 2])
        XCTAssertEqual(out.absorbedInstances, [3])
        XCTAssertEqual(out.people.count, 2, "una persona por semilla")
        XCTAssertEqual(Set(out.people.map(\.id)), [4, 5])
        let union = MaskOps.union([a.mask, b.mask, c.mask])!
        XCTAssertEqual(out.people.map { pixels($0.mask) }.reduce(0, +), pixels(union))
        let left = try XCTUnwrap(out.people.first { $0.pose == poses[0] })
        let right = try XCTUnwrap(out.people.first { $0.pose == poses[1] })
        XCTAssertEqual(left.bbox.minX, 8)
        XCTAssertEqual(right.bbox.maxX, 113)
        XCTAssertEqual(right.mask[99 * w + 112], 255, "incluye la instancia absorbida")
    }

    func testAtMostEightPeople() throws {
        var instances: [PersonInstance] = []
        for k in 0..<9 {
            instances.append(PersonInstance(id: k + 1, mask: rect(k * 12, 0, k * 12 + 10, 20 + k), width: w, height: h))
        }
        let out = try PersonSplitter.apply(instances: instances, poses: [], faces: [], seeds: [], width: w, height: h)
        XCTAssertEqual(out.people.count, PersonSplitter.maxPeople)
        XCTAssertFalse(out.people.contains { $0.id == 1 }, "se descarta la de menos cobertura")
    }

    // MARK: - Evidencia corporal de las semillas de cara (ADR-010)

    /// Semilla de cara dentro de la máscara de una persona real: sin cuerpo que la respalde
    /// no crea persona (retrato, pantalla o cara estampada); con su propio rectángulo de
    /// persona, sí.
    func testFaceSeedNeedsBodyEvidence() throws {
        let inst = PersonInstance(id: 1, mask: rect(8, 5, 52, 99), width: w, height: h)
        let poses = [pose(30)]
        // Cara estampada en el pecho: a media altura de la persona, no en su cabeza.
        let fake = face(46, 60, size: 12)
        let seeds = PersonSplitter.seeds(poses: poses, faces: []) +
            [SubjectSeed(seed: PersonSeed(x0: 46, y0: 66, x1: 46, y1: 96, halfWidth: 4), kind: .face, face: fake,
                         faceWidth: 12)]

        // (a) Sin rectángulos ni poses libres: la semilla de cara se descarta.
        var out = try PersonSplitter.apply(instances: [inst], poses: poses, faces: [], seeds: seeds, width: w, height: h)
        XCTAssertEqual(out.people.count, 1)
        XCTAssertTrue(out.splits.isEmpty)
        XCTAssertEqual(out.faceSeedsWithoutBody.count, 1)
        XCTAssertEqual(out.faceSeedsWithoutBody[0].bodyEvidence, .none)
        XCTAssertEqual(out.seeds.count, 1, "solo queda la semilla de pose")

        // (b) Con SU rectángulo de persona (cabeza arriba, cuerpo debajo): separa.
        out = try PersonSplitter.apply(instances: [inst], poses: poses, faces: [], seeds: seeds, width: w, height: h,
                                       humanBoxes: [body(of: fake)])
        XCTAssertEqual(out.people.count, 2)
        XCTAssertEqual(out.seeds.last?.bodyEvidence, .humanRectangle)
        XCTAssertTrue(out.faceSeedsWithoutBody.isEmpty)

        // (c) El rectángulo de la persona de VERDAD (empieza en su cabeza, muy por encima de
        //     la cara estampada) no vale: es el caso poster_on_torso de harness/people/faces.
        let realBody = CGRect(x: 8, y: 5, width: 45, height: 95)
        XCTAssertFalse(PersonSplitter.rectangleIsBody(of: fake.boundingBox, rect: realBody))
        out = try PersonSplitter.apply(instances: [inst], poses: poses, faces: [], seeds: seeds, width: w, height: h,
                                       humanBoxes: [realBody])
        XCTAssertEqual(out.people.count, 1)
        XCTAssertEqual(out.faceSeedsWithoutBody.count, 1)

        // (d) Con la regla apagada vuelve el comportamiento de la copia preliminar.
        out = try PersonSplitter.apply(instances: [inst], poses: poses, faces: [], seeds: seeds, width: w, height: h,
                                       options: relaxed)
        XCTAssertEqual(out.people.count, 2)
    }

    /// Una pose que NO es semilla (sin cuello ni hombros: solo caderas y rodillas) debajo de
    /// la cara y dentro de su eje también acredita el cuerpo.
    func testPoseJointsBackFaceSeed() throws {
        let inst = PersonInstance(id: 1, mask: rect(8, 5, 52, 99), width: w, height: h)
        let poses = [pose(30)]
        let fake = face(46, 14, size: 12)
        let faceSeed = SubjectSeed(seed: PersonSeed(x0: 46, y0: 20, x1: 46, y1: 90, halfWidth: 6), kind: .face,
                                   face: fake, faceWidth: 12)
        var legs = Pose()
        legs[.leftHip] = Keypoint(x: 47, y: 45, confidence: 0.8)
        legs[.rightHip] = Keypoint(x: 45, y: 46, confidence: 0.8)
        XCTAssertEqual(PersonSplitter.bodyEvidence(for: faceSeed, humanBoxes: [], poses: [legs]), .poseJoints)
        // Un solo punto no basta (faceSeedMinPoseJoints 2).
        var one = Pose()
        one[.leftHip] = Keypoint(x: 47, y: 45, confidence: 0.8)
        XCTAssertEqual(PersonSplitter.bodyEvidence(for: faceSeed, humanBoxes: [], poses: [one]), SeedBodyEvidence.none)
        // Los puntos de la pose que YA es semilla no cuentan: `apply` solo mira las libres.
        let out = try PersonSplitter.apply(instances: [inst], poses: poses, faces: [],
                                           seeds: PersonSplitter.seeds(poses: poses, faces: []) + [faceSeed],
                                           width: w, height: h)
        XCTAssertEqual(out.people.count, 1, "la pose de la persona real no acredita la cara estampada")
    }

    func testRectangleIsBodyGeometry() {
        let f = CGRect(x: 40, y: 20, width: 20, height: 20)
        XCTAssertTrue(PersonSplitter.rectangleIsBody(of: f, rect: CGRect(x: 30, y: 18, width: 40, height: 100)))
        // Empieza demasiado arriba (más de 1 alto de cara): la cara no es su cabeza.
        XCTAssertFalse(PersonSplitter.rectangleIsBody(of: f, rect: CGRect(x: 30, y: -10, width: 40, height: 120)))
        // No baja lo suficiente (menos de 1 alto de cara por debajo).
        XCTAssertFalse(PersonSplitter.rectangleIsBody(of: f, rect: CGRect(x: 30, y: 18, width: 40, height: 40)))
        // No contiene el centro de la cara.
        XCTAssertFalse(PersonSplitter.rectangleIsBody(of: f, rect: CGRect(x: 0, y: 18, width: 20, height: 100)))
    }

    /// `PhantomOptions.requireBodyForFaceOnly` (apagada por defecto): una instancia cuya única
    /// evidencia es una cara necesita el rectángulo de persona de esa cara. Es el caso
    /// `poster_alone` / `screen_alone` de harness/people/faces.
    func testFaceOnlyInstanceNeedsBodyWithOption() {
        let poster = PersonInstance(id: 1, mask: rect(40, 30, 80, 70), width: w, height: h,
                                    faceBox: CGRect(x: 50, y: 40, width: 20, height: 20))
        XCTAssertEqual(SubjectExtractor.bodyEvidence(for: poster, width: w, height: h).kind, .face,
                       "por defecto, una cara basta (comportamiento actual)")
        let strict = PhantomOptions(requireBodyForFaceOnly: true)
        XCTAssertEqual(SubjectExtractor.bodyEvidence(for: poster, width: w, height: h, options: strict,
                                                     humanBox: nil).kind, PersonEvidence.Kind.none)
        // Con el rectángulo de persona de esa cara sí es persona.
        let bodyBox = CGRect(x: 30, y: 38, width: 60, height: 60)
        XCTAssertEqual(SubjectExtractor.bodyEvidence(for: poster, width: w, height: h, options: strict,
                                                     humanBox: bodyBox).kind, .face)
        // (El rectángulo de OTRA persona que empieza mucho más arriba no acredita la cara; si
        //  además cubre la instancia, la acepta la regla 3 —el detector de personas de Vision
        //  dice que ahí hay alguien—, que es independiente de la cara: ver
        //  `testRectangleIsBodyGeometry`.)
    }
}
