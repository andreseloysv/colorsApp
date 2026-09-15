// Cadena de máscaras sin Vision: personas sintéticas (máscaras, poses y
// muestras de cara construidas a mano) sobre un raster RGBA sintético.
import CoreGraphics
import XCTest
import ColorEngine
@testable import SubjectKit

/// Raster sintético con una o dos personas de 60 x 100 px.
struct SyntheticScene {
    static let personWidth = 60
    static let height = 100
    let width: Int
    var rgba: [UInt8]
    var stride: Int { width * 4 }

    static let background: [UInt8] = [128, 128, 128]
    static let shirt: [UInt8] = [30, 60, 160]
    /// Tonos de piel con una variación determinista pequeña (covarianza no degenerada).
    static let skinTones: [[UInt8]] = (0..<9).map { (k: Int) -> [UInt8] in
        let r: Int = 200 + (k % 3) * 3
        let g: Int = 150 + (k / 3) * 3
        return [UInt8(r), UInt8(g), 120]
    }

    init(people: Int = 1) {
        self.init(width: Self.personWidth * people)
    }

    /// Lienzo de `width` x 100 px (para personas pequeñas respecto al raster).
    init(width: Int) {
        self.width = width
        rgba = [UInt8](repeating: 255, count: width * Self.height * 4)
        for i in 0..<(width * Self.height) {
            rgba[4 * i] = Self.background[0]
            rgba[4 * i + 1] = Self.background[1]
            rgba[4 * i + 2] = Self.background[2]
        }
    }

    mutating func paint(x: Int, y: Int, _ c: [UInt8]) {
        let i = 4 * (y * width + x)
        rgba[i] = c[0]
        rgba[i + 1] = c[1]
        rgba[i + 2] = c[2]
    }

    func color(x: Int, y: Int) -> [UInt8] {
        let i = 4 * (y * width + x)
        return [rgba[i], rgba[i + 1], rgba[i + 2]]
    }

    static func skin(_ x: Int, _ y: Int) -> [UInt8] { skinTones[(x + 3 * y) % skinTones.count] }

    /// Persona k: rectángulo x 8...52, y 5...99 (desplazado 60·k), camisa azul y cara de piel.
    mutating func addPerson(_ k: Int, skinBody: Bool = false) -> (mask: [UInt8], pose: Pose, face: [UInt8]) {
        let ox = Self.personWidth * k
        var mask = [UInt8](repeating: 0, count: width * Self.height)
        var face = [UInt8](repeating: 0, count: width * Self.height)
        for y in 5...99 {
            for x in (8 + ox)...(52 + ox) {
                mask[y * width + x] = 255
                let isFace = y < 28 && x >= 22 + ox && x <= 38 + ox
                paint(x: x, y: y, isFace || skinBody ? Self.skin(x, y) : Self.shirt)
                if isFace && y >= 8 && y <= 24 && x >= 24 + ox && x <= 36 + ox { face[y * width + x] = 255 }
            }
        }
        var pose = Pose()
        func set(_ j: Joint, _ x: Double, _ y: Double) { pose[j] = Keypoint(x: x + Double(ox), y: y, confidence: 0.9) }
        set(.nose, 30, 15); set(.neck, 30, 30)
        set(.leftShoulder, 40, 30); set(.rightShoulder, 20, 30)
        set(.leftElbow, 45, 45); set(.rightElbow, 15, 45)
        set(.leftWrist, 46, 58); set(.rightWrist, 14, 58)
        set(.leftHip, 38, 60); set(.rightHip, 22, 60); set(.root, 30, 60)
        set(.leftKnee, 36, 80); set(.rightKnee, 24, 80)
        set(.leftAnkle, 36, 97); set(.rightAnkle, 24, 97)
        return (mask, pose, face)
    }
}

final class ChainTests: XCTestCase {
    private func run(_ scene: SyntheticScene, _ people: [PersonInstance], _ options: SubjectOptions) throws -> SubjectMaskResult {
        try scene.rgba.withUnsafeBufferPointer { px in
            try SubjectExtractor.mask(people: people, rgba: px, width: scene.width, height: SyntheticScene.height,
                                      stride: scene.stride, options: options)
        }
    }

    private func count(_ m: [UInt8]?) -> Int { m.map { MaskOps.nonZero($0) } ?? 0 }

    func testDefaultOptions() {
        let o = SubjectOptions.default
        XCTAssertEqual(o.mode, .largestPerson)
        XCTAssertEqual(o.region, .clothing)
        XCTAssertTrue(o.adaptiveSkin)
        XCTAssertNil(o.selectedIndex)
        XCTAssertEqual(o.regionOptions, RegionOptions.default)
        XCTAssertEqual(o.skinOptions, SkinOptions.default)
        XCTAssertEqual(o.minCoverage, 0.0005)
        XCTAssertEqual(o.minRegionFraction, 0.15)
        XCTAssertEqual(o.bareArmsSkinFraction, 0.25)
        XCTAssertTrue(o.shareSkinModel)
        XCTAssertEqual(SubjectExtractor.headCutFraction, 0.18)
        XCTAssertEqual(SubjectExtractor.estimatedTorsoLength, 1.2)
        XCTAssertEqual(SubjectExtractor.estimatedHipWidth, 0.75)
        XCTAssertEqual(SubjectExtractor.minPersonCoverage, 0.0005)
    }

    func testNoPeopleGivesNoMask() throws {
        let scene = SyntheticScene()
        let r = try run(scene, [], .default)
        XCTAssertNil(r.mask)
        XCTAssertEqual(r.steps, [.noPeople])
        XCTAssertNil(r.chosenIndex)
        XCTAssertEqual(r.layers.allPeopleOverlay.count, scene.width * SyntheticScene.height)
        XCTAssertTrue(r.layers.allPeopleOverlay.allSatisfy { $0 == 0 })
        XCTAssertTrue(r.layers.persons.isEmpty)
    }

    func testOffModeKeepsPeopleWithoutMask() throws {
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: SyntheticScene.height, pose: p.pose)
        let r = try run(scene, [person], SubjectOptions(mode: .off))
        XCTAssertNil(r.mask)
        XCTAssertEqual(r.steps, [.none])
        XCTAssertEqual(r.people.count, 1)
        XCTAssertEqual(r.maskCoverage, 0)
    }

    func testComputeOffDoesNotRunVision() throws {
        let scene = SyntheticScene()
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let image = ctx.makeImage()!
        let r = try scene.rgba.withUnsafeBufferPointer { px in
            try SubjectExtractor.compute(image: image, rgba: px, width: scene.width, height: SyntheticScene.height,
                                         stride: scene.stride, options: SubjectOptions(mode: .off))
        }
        XCTAssertEqual(r.steps, [.none])
        XCTAssertNil(r.timings["detect"])
    }

    func testInstanceStatsAndSorting() throws {
        let w = 10, h = 10
        var small = [UInt8](repeating: 0, count: 100)
        var big = [UInt8](repeating: 0, count: 100)
        for y in 2..<4 { for x in 3..<5 { small[y * w + x] = 255 } }
        for y in 5..<9 { for x in 1..<7 { big[y * w + x] = 200 } }
        big[0] = 100 // < 128: no cuenta
        let a = PersonInstance(id: 7, mask: small, width: w, height: h)
        let b = PersonInstance(id: 3, mask: big, width: w, height: h)
        XCTAssertEqual(a.coverage, 0.04)
        XCTAssertEqual(a.bbox, CGRect(x: 3, y: 2, width: 2, height: 2))
        XCTAssertEqual(b.coverage, 0.24)
        XCTAssertEqual(b.bbox, CGRect(x: 1, y: 5, width: 6, height: 4))
        let rgba = [UInt8](repeating: 0, count: w * h * 4)
        let r = try rgba.withUnsafeBufferPointer { px in
            try SubjectExtractor.mask(people: [a, b], rgba: px, width: w, height: h, stride: w * 4,
                                      options: SubjectOptions(region: .wholePerson, adaptiveSkin: false))
        }
        XCTAssertEqual(r.people.map(\.id), [3, 7])
        XCTAssertEqual(r.chosenIndex, 0)
        XCTAssertEqual(r.mask, MaskOps.binarize(big), "el motor recibe la persona binaria (200 -> 255, 100 -> 0)")
        XCTAssertEqual(r.mask?.filter { $0 != 0 }.count, 24)
        XCTAssertEqual(r.mask?[0], 0)
        XCTAssertEqual(r.steps, [])
        XCTAssertEqual(r.layers.allPeopleOverlay[5 * w + 1], 3)
        XCTAssertEqual(r.layers.allPeopleOverlay[2 * w + 3], 7)
        XCTAssertEqual(r.layers.allPeopleOverlay[0], 0)
    }

    func testSelectedPersonAndOutOfRange() throws {
        var scene = SyntheticScene(people: 2)
        let p0 = scene.addPerson(0)
        let p1 = scene.addPerson(1)
        var m1 = p1.mask
        for y in 90...99 { for x in 60..<120 { m1[y * scene.width + x] = 0 } } // persona 1 algo más pequeña
        let people = [PersonInstance(id: 1, mask: p0.mask, width: scene.width, height: 100, pose: p0.pose),
                      PersonInstance(id: 2, mask: m1, width: scene.width, height: 100, pose: p1.pose)]
        var o = SubjectOptions(mode: .selectedPerson, region: .wholePerson, adaptiveSkin: false, selectedIndex: 1)
        var r = try run(scene, people, o)
        XCTAssertEqual(r.chosenIndex, 1)
        XCTAssertEqual(r.mask, m1)
        XCTAssertEqual(r.layers.primary?.instanceId, 2)
        o.selectedIndex = 5
        r = try run(scene, people, o)
        XCTAssertEqual(r.chosenIndex, 0)
        XCTAssertEqual(r.mask, p0.mask)
    }

    func testClothingWithPoseMatchesEngineRegions() throws {
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose)
        let r = try run(scene, [person], SubjectOptions(adaptiveSkin: false))
        XCTAssertEqual(r.steps, [.poseRegions])
        let expected = try clothingRegions(pose: p.pose, mask: p.mask, width: scene.width, height: 100)
        XCTAssertEqual(r.mask, expected.mask)
        XCTAssertEqual(r.layers.primary?.regionMask, expected.mask)
        XCTAssertNil(r.layers.primary?.skinRemovedMask)
        XCTAssertGreaterThan(expected.pixels, 0)
        // Nada por encima de la línea de hombros (y = 30) ni en la cabeza.
        for y in 0..<30 { for x in 0..<scene.width { XCTAssertEqual(r.mask![y * scene.width + x], 0) } }
    }

    func testPoseWithoutHipsUsesEstimatedHips() throws {
        var scene = SyntheticScene()
        var p = scene.addPerson(0)
        p.pose[.leftHip] = .missing
        p.pose[.rightHip] = .missing
        p.pose[.root] = .missing
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose)
        let r = try run(scene, [person], SubjectOptions(adaptiveSkin: false))
        XCTAssertEqual(r.steps, [.poseRegions], "plano medio: hombros sin caderas -> caderas estimadas, no headCut")
        let d = try XCTUnwrap(r.layers.primary?.regionDecision)
        XCTAssertEqual(d.source, .poseRegions)
        XCTAssertTrue(d.hipsEstimated)
        // Hombros L (40, 30) y R (20, 30), nariz arriba: sw = 20, raíz = M + 1,2·20·(0, 1) = (30, 54),
        // caderas = raíz ± 0,75·10 en x; rodillas y tobillos borrados.
        let rp = try XCTUnwrap(d.regionPose)
        XCTAssertEqual(rp[.root].x, 30)
        XCTAssertEqual(rp[.root].y, 54)
        XCTAssertEqual(rp[.leftHip].x, 37.5)
        XCTAssertEqual(rp[.rightHip].x, 22.5)
        XCTAssertEqual(rp[.leftHip].y, 54)
        XCTAssertEqual(rp[.leftHip].confidence, 0.9)
        XCTAssertEqual(rp[.leftKnee].confidence, 0)
        XCTAssertEqual(rp[.rightAnkle].confidence, 0)
        let expected = try clothingRegions(pose: rp, mask: p.mask, width: scene.width, height: 100)
        XCTAssertEqual(r.mask, expected.mask)
        XCTAssertEqual(d.poseRegionPixels, expected.pixels)
        // Torso superior: nada por encima de los hombros (y = 30) ni por debajo de la
        // cadera estimada más el margen (54 + 0,12·20 = 56,4).
        for (i, v) in r.mask!.enumerated() where v > 0 {
            XCTAssertGreaterThanOrEqual(i / scene.width, 30)
            XCTAssertLessThanOrEqual(i / scene.width, 56)
        }
        // Sin nariz la normal apunta hacia abajo en la imagen: la misma región.
        var noNose = p.pose
        noNose[.nose] = .missing
        XCTAssertEqual(SubjectExtractor.regionPose(noNose).pose[.root].y, 54)
        // Con la nariz debajo de los hombros (persona boca abajo) la raíz va hacia arriba.
        var flipped = p.pose
        flipped[.nose] = Keypoint(x: 30, y: 45, confidence: 0.9)
        XCTAssertEqual(SubjectExtractor.regionPose(flipped).pose[.root].y, 6)
        // Caderas utilizables: la pose no cambia.
        let full = scene.addPerson(0).pose
        XCTAssertFalse(SubjectExtractor.regionPose(full).hipsEstimated)
        XCTAssertEqual(SubjectExtractor.regionPose(full).pose, full)
    }

    func testPoseWithoutShouldersOrHipsFallsBackToHeadCut() throws {
        var scene = SyntheticScene()
        var p = scene.addPerson(0)
        for j in [Joint.leftHip, .rightHip, .root, .leftShoulder, .rightShoulder] { p.pose[j] = .missing }
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose)
        let r = try run(scene, [person], SubjectOptions(adaptiveSkin: false))
        XCTAssertEqual(r.steps, [.headCut])
        let expected = cutHead(mask: p.mask, width: scene.width, height: 100, fraction: 0.18)
        XCTAssertEqual(r.mask, expected.mask)
        // bbox y 5...99 (H = 95): c = floor(0,18·95 + 0,5) = 17 filas anuladas (5...21).
        for y in 5...21 { XCTAssertEqual(r.mask![y * scene.width + 30], 0) }
        XCTAssertEqual(r.mask![22 * scene.width + 30], 255)
        XCTAssertEqual(r.layers.primary?.regionDecision?.headCutFraction, 0.18)
        XCTAssertNil(r.layers.primary?.regionDecision?.poseRegionPixels)
    }

    func testHeadCutHeightFromFaceBox() throws {
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        // Cara y 8...24 (alto 16): corte hasta 24 + 0,25·16 = 28, fracción (28 − 5)/95.
        let face = CGRect(x: 22, y: 8, width: 17, height: 16)
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, faceBox: face)
        let r = try run(scene, [person], SubjectOptions(adaptiveSkin: false))
        XCTAssertEqual(r.steps, [.headCut])
        let fraction = try XCTUnwrap(r.layers.primary?.regionDecision?.headCutFraction)
        XCTAssertEqual(fraction, 23.0 / 95.0, accuracy: 1e-15)
        XCTAssertEqual(r.mask, cutHead(mask: p.mask, width: scene.width, height: 100, fraction: fraction).mask)
        XCTAssertEqual(r.mask![27 * scene.width + 30], 0)
        XCTAssertEqual(r.mask![28 * scene.width + 30], 255)
        let body = CGRect(x: 8, y: 5, width: 45, height: 95)
        XCTAssertEqual(SubjectExtractor.cutHeadFraction(bodyBox: body, faceBox: nil), 0.18)
        XCTAssertEqual(SubjectExtractor.cutHeadFraction(bodyBox: body, faceBox: CGRect(x: 20, y: 5, width: 4, height: 4)), 0.18)
        XCTAssertEqual(SubjectExtractor.cutHeadFraction(bodyBox: body, faceBox: CGRect(x: 20, y: 30, width: 40, height: 60)), 0.5)
    }

    func testNoPoseFallsBackToHeadCut() throws {
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100)
        let r = try run(scene, [person], SubjectOptions(adaptiveSkin: false))
        XCTAssertEqual(r.steps, [.headCut])
        XCTAssertEqual(r.mask, cutHead(mask: p.mask, width: scene.width, height: 100, fraction: 0.18).mask)
    }

    func testAdaptiveSkinRemovesSkinPixels() throws {
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        // Antebrazo y mano "sueltos" dentro del torso: una franja de piel en la región.
        for y in 40...49 { for x in 18...23 { scene.paint(x: x, y: y, SyntheticScene.skin(x, y)) } }
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose,
                                    faceSampleMask: p.face)
        let r = try run(scene, [person], .default)
        XCTAssertEqual(r.steps, [.poseRegions, .skinExcluded])
        let layer = try XCTUnwrap(r.layers.primary)
        let region = try XCTUnwrap(layer.regionMask)
        let removed = try XCTUnwrap(layer.skinRemovedMask)
        var skinInRegion = 0
        for y in 0..<100 {
            for x in 0..<scene.width where region[y * scene.width + x] > 0 {
                let isSkin = SyntheticScene.skinTones.contains(scene.color(x: x, y: y))
                if isSkin { skinInRegion += 1 }
                XCTAssertEqual(removed[y * scene.width + x] == 255, isSkin, "(\(x), \(y))")
                XCTAssertEqual(r.mask![y * scene.width + x] == 0, isSkin, "(\(x), \(y))")
            }
        }
        XCTAssertGreaterThan(skinInRegion, 40)
        XCTAssertEqual(layer.skinExcludedPixels, skinInRegion)
        XCTAssertEqual(layer.faceSampleMask, p.face)
        XCTAssertEqual(layer.skinModel?.sampleCount, MaskOps.nonZero(p.face))
        XCTAssertLessThan(Double(layer.skinExcludedPixels) / Double(count(region)), 0.35)
        XCTAssertEqual(layer.finalMask, r.mask)
    }

    func testSkinGuardKeepsMask() throws {
        var scene = SyntheticScene()
        let p = scene.addPerson(0, skinBody: true) // prenda color piel
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose,
                                    faceSampleMask: p.face)
        let r = try run(scene, [person], .default)
        XCTAssertEqual(r.steps, [.poseRegions, .skinGuard])
        XCTAssertEqual(r.mask, r.layers.primary?.regionMask)
        XCTAssertNil(r.layers.primary?.skinRemovedMask)
        XCTAssertEqual(r.layers.primary?.skinExcludedPixels, 0)
    }

    func testTooFewSkinSamplesSkipsSkin() throws {
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        var sample = [UInt8](repeating: 0, count: p.face.count)
        for y in 10..<14 { for x in 26..<30 { sample[y * scene.width + x] = 255 } } // 16 < 50 muestras
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose,
                                    faceSampleMask: sample)
        let r = try run(scene, [person], .default)
        XCTAssertEqual(r.steps, [.poseRegions])
        XCTAssertEqual(r.layers.primary?.skinNote, "tooFewSkinSamples")
        XCTAssertNil(r.layers.primary?.skinModel)
        // Se pidió piel y no hay modelo: la región va sin brazos (manga corta = piel).
        let d = try XCTUnwrap(r.layers.primary?.regionDecision)
        XCTAssertTrue(d.upperArmsDropped)
        XCTAssertEqual(d.regionOptions?.includeUpperArms, false)
        var noArms = RegionOptions.default
        noArms.includeUpperArms = false
        XCTAssertEqual(r.mask, try clothingRegions(pose: p.pose, options: noArms, mask: p.mask, width: scene.width,
                                                   height: 100).mask)
        // Sin pedir piel se mantienen los brazos de las opciones de la app.
        let off = try run(scene, [person], SubjectOptions(adaptiveSkin: false))
        XCTAssertEqual(off.layers.primary?.regionDecision?.upperArmsDropped, false)
        XCTAssertEqual(off.mask, try clothingRegions(pose: p.pose, mask: p.mask, width: scene.width, height: 100).mask)
    }

    func testSharedSkinModelForPersonWithoutFace() throws {
        var scene = SyntheticScene(people: 2)
        let p0 = scene.addPerson(0)
        let p1 = scene.addPerson(1)
        // La persona 1 lleva el antebrazo de piel sobre el torso y no tiene cara utilizable.
        for y in 40...49 { for x in 78...83 { scene.paint(x: x, y: y, SyntheticScene.skin(x, y)) } }
        let people = [PersonInstance(id: 1, mask: p0.mask, width: scene.width, height: 100, pose: p0.pose,
                                     faceSampleMask: p0.face),
                      PersonInstance(id: 2, mask: p1.mask, width: scene.width, height: 100, pose: p1.pose)]
        let shared = try run(scene, people, SubjectOptions(mode: .selectedPerson, selectedIndex: 1))
        let layer = try XCTUnwrap(shared.layers.primary)
        XCTAssertEqual(shared.steps, [.poseRegions, .skinExcluded])
        XCTAssertEqual(layer.skinSampleSource, 0, "modelo de la cara de la persona 0")
        XCTAssertEqual(layer.faceSampleMask, p0.face)
        XCTAssertEqual(layer.regionDecision?.upperArmsDropped, false)
        XCTAssertGreaterThan(layer.skinExcludedPixels, 40, "antebrazo de piel (60 px pintados) quitado con el modelo compartido")
        // Sin compartir: sin modelo, sin paso de piel y sin brazos.
        var own = SubjectOptions(mode: .selectedPerson, selectedIndex: 1)
        own.shareSkinModel = false
        let alone = try run(scene, people, own)
        XCTAssertEqual(alone.steps, [.poseRegions])
        XCTAssertNil(alone.layers.primary?.skinSampleSource)
        XCTAssertEqual(alone.layers.primary?.regionDecision?.upperArmsDropped, true)
        // La persona 0 usa su propia cara.
        let first = try run(scene, people, .default)
        XCTAssertEqual(first.layers.primary?.skinSampleSource, 0)
        XCTAssertEqual(SubjectExtractor.skinDonors(people), [nil, 0])
    }

    func testSoftVisionMaskIsBinarizedBeforeRegionsAndHeadCut() throws {
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        // Halo blando (1...127) de 4 px alrededor, también por encima de la cabeza (y 1...4):
        // con la máscara blanda el bbox de cutHead empezaría en y = 1.
        var soft = p.mask
        for y in 1...99 {
            for x in 4...56 where soft[y * scene.width + x] == 0 { soft[y * scene.width + x] = UInt8(20 + (x + y) % 100) }
        }
        let person = PersonInstance(id: 1, mask: soft, width: scene.width, height: 100)
        let r = try run(scene, [person], SubjectOptions(adaptiveSkin: false))
        XCTAssertEqual(r.steps, [.headCut])
        XCTAssertEqual(r.mask, cutHead(mask: p.mask, width: scene.width, height: 100, fraction: 0.18).mask)
        XCTAssertTrue(r.mask!.allSatisfy { $0 == 0 || $0 == 255 })
        XCTAssertEqual(r.layers.primary?.personMask, p.mask, "la capa de persona es la binaria")
        XCTAssertEqual(r.people.first?.mask, soft, "la instancia conserva la máscara blanda de Vision")
        let whole = try run(scene, [person], SubjectOptions(region: .wholePerson, adaptiveSkin: false))
        XCTAssertEqual(whole.mask, p.mask, "persona completa: sin halo")
    }

    func testWholePersonRegionStillAppliesSkin() throws {
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose,
                                    faceSampleMask: p.face)
        let r = try run(scene, [person], SubjectOptions(region: .wholePerson))
        XCTAssertEqual(r.steps, [.skinExcluded])
        XCTAssertNil(r.layers.primary?.regionMask)
        // La cara (y 5...27, x 22...38) es piel y se quita: 23 · 17 = 391 píxeles.
        XCTAssertEqual(r.layers.primary?.skinExcludedPixels, 391)
    }

    func testRegionSufficiencyIsRelativeToSilhouette() throws {
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose)
        let body = MaskOps.nonZero(p.mask)
        let region = try clothingRegions(pose: p.pose, mask: p.mask, width: scene.width, height: 100)
        let silhouette = try clothingRegions(pose: p.pose, options: SubjectExtractor.silhouetteOptions(.default),
                                             mask: p.mask, width: scene.width, height: 100)
        XCTAssertLessThan(region.pixels, silhouette.pixels)
        XCTAssertLessThan(silhouette.pixels, body)
        var o = SubjectOptions(adaptiveSkin: false)
        var r = try run(scene, [person], o)
        var d = try XCTUnwrap(r.layers.primary?.regionDecision)
        XCTAssertEqual(d.source, .poseRegions)
        XCTAssertEqual(d.silhouettePixels, silhouette.pixels, "la silueta se calcula siempre que hay pose")
        XCTAssertEqual(d.requiredPixels, Int((0.15 * Double(silhouette.pixels)).rounded(.up)))
        XCTAssertEqual(r.layers.primary?.silhouetteMask, silhouette.mask)
        // Regiones por debajo del mínimo relativo a la silueta: la silueta.
        o.minRegionFraction = Double(region.pixels + 1) / Double(silhouette.pixels)
        r = try run(scene, [person], o)
        XCTAssertEqual(r.steps, [.poseRegions])
        d = try XCTUnwrap(r.layers.primary?.regionDecision)
        XCTAssertEqual(d.source, .poseSilhouette)
        XCTAssertEqual(d.poseRegionPixels, region.pixels)
        XCTAssertEqual(r.mask, silhouette.mask)
        // Silueta por debajo del suelo absoluto: la pose no describe a esta persona -> recorte de cabeza.
        let headCut = cutHead(mask: p.mask, width: scene.width, height: 100, fraction: 0.18)
        XCTAssertGreaterThan(headCut.pixels, silhouette.pixels + 1)
        o = SubjectOptions(adaptiveSkin: false)
        o.minCoverage = Double(silhouette.pixels + 1) / Double(scene.width * 100)
        r = try run(scene, [person], o)
        XCTAssertEqual(r.steps, [.poseRegions, .headCut])
        XCTAssertEqual(r.mask, headCut.mask)
        d = try XCTUnwrap(r.layers.primary?.regionDecision)
        XCTAssertEqual(d.requiredPixels, silhouette.pixels + 1)
        // Por encima del recorte de cabeza: sin silueta utilizable, el respaldo es la persona binaria.
        o.minCoverage = Double(headCut.pixels + 1) / Double(scene.width * 100)
        r = try run(scene, [person], o)
        XCTAssertEqual(r.steps, [.poseRegions, .headCut, .wholePerson])
        XCTAssertEqual(r.mask, p.mask)
        XCTAssertEqual(r.layers.primary?.fallbackSource, .wholePerson)
        XCTAssertEqual(r.layers.primary?.usedInMask, false)
        XCTAssertEqual(r.layers.finalMask, p.mask)
        o.minCoverage = Double(body + 1) / Double(scene.width * 100)
        r = try run(scene, [person], o)
        XCTAssertEqual(r.steps.last, MaskFallback.none)
        XCTAssertNil(r.mask)
        XCTAssertNil(r.layers.finalMask)
    }

    func testFloorFallbackWithPoseUsesSilhouetteNotVisionMask() throws {
        // Silueta elegida y la piel le quita tanto que la máscara final no llega al
        // suelo: con pose se vuelve a la silueta, nunca a la instancia cruda de Vision.
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        for y in 30...60 { for x in 8...52 { scene.paint(x: x, y: y, SyntheticScene.skin(x, y)) } }
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose,
                                    faceSampleMask: p.face)
        var o = SubjectOptions(minRegionFraction: 1, bareArmsSkinFraction: 1)
        o.regionOptions.includeUpperArms = false
        o.skinOptions.maxExcludedFraction = 1
        let silhouette = try clothingRegions(pose: p.pose, options: SubjectExtractor.silhouetteOptions(o.regionOptions),
                                             mask: p.mask, width: scene.width, height: 100)
        var probe = try run(scene, [person], o)
        XCTAssertEqual(probe.layers.primary?.regionDecision?.source, .poseSilhouette)
        XCTAssertEqual(probe.steps, [.poseRegions, .skinExcluded])
        let finalPixels = MaskOps.nonZero(try XCTUnwrap(probe.mask))
        XCTAssertLessThan(finalPixels, silhouette.pixels)
        o.minCoverage = Double(finalPixels + 1) / Double(scene.width * 100)
        probe = try run(scene, [person], o)
        XCTAssertEqual(probe.steps, [.poseRegions, .skinExcluded, .wholePerson])
        XCTAssertEqual(probe.mask, silhouette.mask)
        XCTAssertNotEqual(probe.mask, p.mask)
        XCTAssertEqual(probe.layers.primary?.fallbackSource, .poseSilhouette)
        XCTAssertEqual(probe.layers.primary?.usedInMask, false)
    }

    func testSmallChildInsideStrollerKeepsOnlyChildClothing() throws {
        // CONTEXT §12: bebé en un cochecito marrón oscuro; la instancia de Vision
        // incluye el cochecito. Las regiones del bebé son < 15 % de la instancia
        // (la regla relativa a la instancia las rechazaba y caía a la silueta o al
        // recorte de cabeza, con marrón), pero > 15 % de su silueta: se usan y la
        // paleta no contiene el color del cochecito.
        let W = 240, H = 240
        let brown: [UInt8] = [70, 45, 30], pink: [UInt8] = [230, 160, 180]
        var rgba = [UInt8](repeating: 255, count: W * H * 4)
        var mask = [UInt8](repeating: 0, count: W * H)
        var sample = [UInt8](repeating: 0, count: W * H)
        func paint(_ x: Int, _ y: Int, _ c: [UInt8]) {
            guard x >= 0, y >= 0, x < W, y < H else { return }
            let i = y * W + x
            rgba[4 * i] = c[0]; rgba[4 * i + 1] = c[1]; rgba[4 * i + 2] = c[2]
            mask[i] = 255
        }
        for i in 0..<(W * H) { rgba[4 * i] = 128; rgba[4 * i + 1] = 128; rgba[4 * i + 2] = 128 }
        func capsule(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ radius: Double, _ c: (Int, Int) -> [UInt8]) {
            for y in 0..<H {
                for x in 0..<W {
                    let px = Double(x) + 0.5, py = Double(y) + 0.5
                    let dx = bx - ax, dy = by - ay
                    let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / max(1e-9, dx * dx + dy * dy)))
                    let qx = ax + t * dx - px, qy = ay + t * dy - py
                    if qx * qx + qy * qy <= radius * radius { paint(x, y, c(x, y)) }
                }
            }
        }
        // Cochecito: cubeta, manillar y ruedas.
        for y in 90...205 { for x in 20...220 { paint(x, y, brown) } }
        capsule(215, 95, 232, 30, 6) { _, _ in brown }
        capsule(55, 215, 55, 215, 20) { _, _ in brown }
        capsule(185, 215, 185, 215, 20) { _, _ in brown }
        // Bebé delante: cabeza de piel, cuerpo, brazos y piernas rosas, manos de piel.
        capsule(110, 66, 110, 66, 16) { SyntheticScene.skin($0, $1) }
        for y in 84...142 { for x in 92...128 { paint(x, y, pink) } }
        capsule(98, 88, 92, 108, 8) { _, _ in pink }
        capsule(122, 88, 128, 108, 8) { _, _ in pink }
        capsule(92, 108, 90, 126, 7) { _, _ in pink }
        capsule(128, 108, 130, 126, 7) { _, _ in pink }
        capsule(90, 131, 90, 131, 5) { SyntheticScene.skin($0, $1) }
        capsule(130, 131, 130, 131, 5) { SyntheticScene.skin($0, $1) }
        capsule(101, 138, 99, 160, 8) { _, _ in pink }
        capsule(99, 160, 99, 182, 8) { _, _ in pink }
        capsule(119, 138, 121, 160, 8) { _, _ in pink }
        capsule(121, 160, 121, 182, 8) { _, _ in pink }
        for y in 0..<H { for x in 0..<W {
            let a = Double(x) + 0.5 - 104, b = Double(y) + 0.5 - 70, c = Double(x) + 0.5 - 116
            if a * a + b * b <= 36 || c * c + b * b <= 36 { sample[y * W + x] = 255 }
        } }
        var pose = Pose()
        func set(_ j: Joint, _ x: Double, _ y: Double) { pose[j] = Keypoint(x: x, y: y, confidence: 0.8) }
        set(.nose, 110, 66); set(.neck, 110, 86)
        set(.leftShoulder, 122, 88); set(.rightShoulder, 98, 88)
        set(.leftElbow, 128, 108); set(.rightElbow, 92, 108)
        set(.leftWrist, 130, 126); set(.rightWrist, 90, 126)
        set(.leftHip, 119, 138); set(.rightHip, 101, 138); set(.root, 110, 138)
        set(.leftKnee, 121, 160); set(.rightKnee, 99, 160)
        set(.leftAnkle, 121, 180); set(.rightAnkle, 99, 180)
        let person = PersonInstance(id: 1, mask: mask, width: W, height: H, pose: pose, faceSampleMask: sample)
        let r = try rgba.withUnsafeBufferPointer { px in
            try SubjectExtractor.mask(people: [person], rgba: px, width: W, height: H, stride: W * 4, options: .default)
        }
        let layer = try XCTUnwrap(r.layers.primary)
        let d = try XCTUnwrap(layer.regionDecision)
        let final = try XCTUnwrap(r.mask)
        func brownPixels(_ m: [UInt8]) -> Int {
            var n = 0
            for i in 0..<(W * H) where m[i] != 0 && rgba[4 * i] == brown[0] && rgba[4 * i + 1] == brown[1] { n += 1 }
            return n
        }
        let silhouette = try XCTUnwrap(layer.silhouetteMask)
        print("COCHECITO | persona \(d.bodyPixels) px | regiones \(d.poseRegionPixels ?? -1) | silueta \(d.silhouettePixels ?? -1) (marrón \(brownPixels(silhouette))) | requerido \(d.requiredPixels) | final \(MaskOps.nonZero(final)) (marrón \(brownPixels(final))) | pasos \(r.steps.map(\.rawValue))")
        XCTAssertLessThan(Double(try XCTUnwrap(d.poseRegionPixels)), 0.15 * Double(d.bodyPixels),
                          "el caso de §12: las regiones son < 15 % de la instancia con el cochecito")
        XCTAssertGreaterThan(brownPixels(silhouette), 0, "la silueta ancha ya toca el cochecito")
        XCTAssertEqual(d.source, .poseRegions)
        XCTAssertFalse(d.bareArmsDropped, "mangas rosas: los brazos no son piel")
        XCTAssertEqual(r.steps.first, .poseRegions)
        XCTAssertFalse(r.steps.contains(.headCut))
        XCTAssertFalse(r.steps.contains(.wholePerson))
        XCTAssertLessThanOrEqual(Double(brownPixels(final)), 0.01 * Double(MaskOps.nonZero(final)))
        let swatches = try rgba.withUnsafeBufferPointer { px in
            try final.withUnsafeBufferPointer { mb in
                try extractPalette(rgba: px, width: W, height: H, stride: W * 4, mask: mb)
            }
        }
        let brownLab = srgbToLab(r: brown[0], g: brown[1], b: brown[2])
        for sw in swatches {
            XCTAssertGreaterThan(deltaE2000(sw.lab, brownLab), 10, "swatch \(sw.hex) (\(sw.weight)) es el cochecito")
        }
        let pinkLab = srgbToLab(r: pink[0], g: pink[1], b: pink[2])
        XCTAssertLessThan(deltaE2000(try XCTUnwrap(swatches.first).lab, pinkLab), 2)
    }

    func testBareUpperArmsAreDroppedWithSkinModel() throws {
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose,
                                    faceSampleMask: p.face)
        var noArms = RegionOptions.default
        noArms.includeUpperArms = false
        let withArms = try clothingRegions(pose: p.pose, mask: p.mask, width: scene.width, height: 100)
        let without = try clothingRegions(pose: p.pose, options: noArms, mask: p.mask, width: scene.width, height: 100)
        let armPixels = withArms.pixels - without.pixels
        XCTAssertGreaterThan(armPixels, 0)
        // Manga larga (camisa en los brazos): la prueba se hace y los brazos se quedan.
        var r = try run(scene, [person], .default)
        var d = try XCTUnwrap(r.layers.primary?.regionDecision)
        XCTAssertEqual(d.armPixels, armPixels)
        XCTAssertEqual(d.armSkinPixels, 0)
        XCTAssertFalse(d.bareArmsDropped)
        XCTAssertEqual(r.layers.primary?.regionMask, withArms.mask)
        XCTAssertEqual(MaskOps.nonZero(try XCTUnwrap(r.layers.primary?.armsMask)), armPixels)
        // Sin mangas: los brazos fuera del torso son piel -> se quitan de la región.
        var bare = scene
        for (i, v) in MaskOps.removed(before: withArms.mask, after: without.mask).enumerated() where v != 0 {
            bare.paint(x: i % scene.width, y: i / scene.width, SyntheticScene.skin(i % scene.width, i / scene.width))
        }
        r = try run(bare, [person], .default)
        d = try XCTUnwrap(r.layers.primary?.regionDecision)
        XCTAssertEqual(d.armSkinPixels, armPixels)
        XCTAssertTrue(d.bareArmsDropped)
        XCTAssertEqual(d.regionOptions?.includeUpperArms, false)
        XCTAssertEqual(d.poseRegionPixels, without.pixels)
        XCTAssertEqual(r.layers.primary?.regionMask, without.mask)
        XCTAssertEqual(r.steps, [.poseRegions], "sin piel en el torso: no hay paso de piel")
        let silhouette = try clothingRegions(pose: p.pose, options: SubjectExtractor.silhouetteOptions(noArms),
                                             mask: p.mask, width: scene.width, height: 100)
        XCTAssertEqual(r.layers.primary?.silhouetteMask, silhouette.mask)
        // Umbral: ceil(fracción · brazos), al menos 1; con 1 solo si todo el brazo es piel.
        XCTAssertEqual(SubjectExtractor.bareArmsThreshold(armPixels: 10, options: .default), 3)
        XCTAssertEqual(SubjectExtractor.bareArmsThreshold(armPixels: 0, options: .default), 1)
        XCTAssertEqual(SubjectExtractor.bareArmsThreshold(armPixels: 7, options: SubjectOptions(bareArmsSkinFraction: 1)), 7)
        // Sin pedir piel no hay prueba.
        let off = try run(bare, [person], SubjectOptions(adaptiveSkin: false))
        XCTAssertNil(off.layers.primary?.regionDecision?.armPixels)
        XCTAssertEqual(off.layers.primary?.regionMask, withArms.mask)
    }

    func testSmallPersonKeepsClothingRegion() throws {
        // Persona de 45 x 95 px en un raster de 1800 x 100 (2,4 %): su región de ropa
        // cubre < 2 % del raster (con la regla absoluta anterior volvía a la persona
        // completa) pero > 15 % de la persona, así que se usa.
        var scene = SyntheticScene(width: 1800)
        let p = scene.addPerson(0)
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose)
        let r = try run(scene, [person], SubjectOptions(adaptiveSkin: false))
        let region = try clothingRegions(pose: p.pose, mask: p.mask, width: scene.width, height: 100)
        XCTAssertLessThan(MaskOps.coverage(region.mask, width: scene.width, height: 100), 0.02)
        XCTAssertEqual(r.steps, [.poseRegions])
        XCTAssertEqual(r.mask, region.mask)
        XCTAssertEqual(r.layers.primary?.usedInMask, true)
    }

    func testAllPeopleUnionOfChains() throws {
        var scene = SyntheticScene(people: 2)
        let p0 = scene.addPerson(0)
        let p1 = scene.addPerson(1)
        let people = [PersonInstance(id: 1, mask: p0.mask, width: scene.width, height: 100, pose: p0.pose,
                                     faceSampleMask: p0.face),
                      PersonInstance(id: 2, mask: p1.mask, width: scene.width, height: 100)] // sin pose ni cara
        let r = try run(scene, people, SubjectOptions(mode: .allPeople))
        XCTAssertNil(r.chosenIndex)
        XCTAssertEqual(r.layers.persons.count, 2)
        // Persona 0: regiones sin piel dentro (la cara queda fuera) -> sin paso de piel.
        // Persona 1: sin cara propia, usa la de la 0 y quita la barbilla que deja el 18 %.
        XCTAssertEqual(r.steps, [.poseRegions, .headCut, .skinExcluded])
        XCTAssertEqual(r.layers.persons.map(\.skinSampleSource), [0, 0])
        var expected = [UInt8]()
        for idx in 0..<2 {
            let single = try run(scene, people, SubjectOptions(mode: .selectedPerson, selectedIndex: idx))
            let chain = try XCTUnwrap(single.layers.primary?.finalMask)
            expected = expected.isEmpty ? chain : zip(expected, chain).map { max($0, $1) }
            XCTAssertEqual(r.layers.persons[idx].finalMask, chain)
        }
        XCTAssertEqual(r.mask, expected)
        XCTAssertEqual(Set(r.layers.allPeopleOverlay), [0, 1, 2])
    }

    func testValidationErrors() throws {
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        let short = PersonInstance(id: 9, mask: Array(p.mask.prefix(10)), coverage: 0.5, bbox: .zero, pose: nil,
                                   faceSampleMask: nil)
        XCTAssertThrowsError(try run(scene, [short], .default)) { e in
            XCTAssertEqual(e as? SubjectError, .maskSizeMismatch(personId: 9, expected: 6000, actual: 10))
        }
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100)
        var o = SubjectOptions.default
        o.minCoverage = .nan
        XCTAssertThrowsError(try run(scene, [person], o)) { e in
            XCTAssertEqual(e as? SubjectError, .invalidOptions("minCoverage debe estar en 0...1"))
        }
        o = .default
        o.minRegionFraction = 1.5
        XCTAssertThrowsError(try run(scene, [person], o)) { e in
            XCTAssertEqual(e as? SubjectError, .invalidOptions("minRegionFraction debe estar en 0...1"))
        }
        o = .default
        o.bareArmsSkinFraction = -0.1
        XCTAssertThrowsError(try run(scene, [person], o)) { e in
            XCTAssertEqual(e as? SubjectError, .invalidOptions("bareArmsSkinFraction debe estar en 0...1"))
        }
        let tiny = [UInt8](repeating: 0, count: 8)
        XCTAssertThrowsError(try tiny.withUnsafeBufferPointer { px in
            try SubjectExtractor.mask(people: [person], rgba: px, width: scene.width, height: 100, stride: scene.width * 4,
                                      options: .default)
        }) { e in
            XCTAssertEqual(e as? ColorEngineError, .bufferTooSmall(required: 99 * 240 + 240, actual: 8))
        }
        let posed = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose)
        XCTAssertThrowsError(try run(scene, [posed], SubjectOptions(regionOptions: RegionOptions(
            minConfidence: 2, torsoMargin: 0.12, limbWidth: 0.45, includeUpperArms: true, includeForearms: false,
            includeLegs: true, includeLowerLegs: true))).steps)
    }

    func testPoseAssociation() {
        let w = 20, h = 10
        var left = [UInt8](repeating: 0, count: w * h), right = left, both = left
        for y in 0..<h {
            for x in 0..<w {
                if x < 10 { left[y * w + x] = 255 } else { right[y * w + x] = 255 }
                both[y * w + x] = 255
            }
        }
        func pose(_ cx: Double, scale: Double = 1) -> Pose {
            var p = Pose()
            p[.neck] = Keypoint(x: cx, y: 2, confidence: 1)
            p[.leftShoulder] = Keypoint(x: cx + 2 * scale, y: 2, confidence: 1)
            p[.rightShoulder] = Keypoint(x: cx - 2 * scale, y: 2, confidence: 1)
            p[.root] = Keypoint(x: cx, y: 7, confidence: 1)
            return p
        }
        // Una pose por instancia, cruzadas.
        XCTAssertEqual(SubjectExtractor.associatePoses([pose(15), pose(5)], masks: [left, right], width: w, height: h), [1, 0])
        // Pose sin torso dentro de ninguna máscara.
        var outside = Pose()
        outside[.nose] = Keypoint(x: 5, y: 5, confidence: 1)
        XCTAssertEqual(SubjectExtractor.associatePoses([outside], masks: [left], width: w, height: h), [nil])
        // Instancia fusionada con dos poses completas: gana el torso más grande.
        XCTAssertEqual(SubjectExtractor.associatePoses([pose(5, scale: 1), pose(12, scale: 1.5)], masks: [both],
                                                       width: w, height: h), [1])
        // Con una pose partida entre dos máscaras, va a la que tiene más esqueleto del torso.
        var split = pose(10)
        split[.rightShoulder] = Keypoint(x: 3, y: 2, confidence: 1)
        split[.neck] = Keypoint(x: 9.5, y: 2, confidence: 1)
        XCTAssertEqual(SubjectExtractor.associatePoses([split], masks: [left, right], width: w, height: h), [0, nil])
        // Abrazo (harness/people/05): cuello y un hombro débil caen en la instancia de
        // la izquierda, junto con una raíz de confianza 0,14; hombro fuerte, nariz y codo,
        // en la de la derecha. Contando puntos sueltos ganaba la izquierda; con el
        // esqueleto y solo los puntos que usa el motor (>= 0,3) gana la derecha.
        var hug = Pose()
        hug[.nose] = Keypoint(x: 15, y: 1, confidence: 0.8)
        hug[.neck] = Keypoint(x: 9.5, y: 3, confidence: 0.46)
        hug[.rightShoulder] = Keypoint(x: 8, y: 3, confidence: 0.36)
        hug[.leftShoulder] = Keypoint(x: 16, y: 3, confidence: 0.56)
        hug[.leftElbow] = Keypoint(x: 17, y: 8, confidence: 0.6)
        hug[.root] = Keypoint(x: 4, y: 3, confidence: 0.14)
        hug[.leftHip] = Keypoint(x: 14, y: 9, confidence: 0.27)
        XCTAssertEqual(SubjectExtractor.associatePoses([hug], masks: [left, right], width: w, height: h), [nil, 0])
        // Puntos sueltos del torso (cuello y un hombro sin el otro) siguen contando como torso.
        var partial = Pose()
        partial[.neck] = Keypoint(x: 4, y: 3, confidence: 0.4)
        partial[.rightShoulder] = Keypoint(x: 2, y: 3, confidence: 0.57)
        partial[.rightElbow] = Keypoint(x: 3, y: 8, confidence: 0.3)
        XCTAssertEqual(SubjectExtractor.associatePoses([partial], masks: [left, right], width: w, height: h), [0, nil])
    }

    func testFaceAssociation() {
        let w = 20, h = 10
        var left = [UInt8](repeating: 0, count: w * h), right = left
        for y in 0..<h { for x in 0..<w { if x < 10 { left[y * w + x] = 255 } else { right[y * w + x] = 255 } } }
        func face(_ box: CGRect) -> FaceLandmarkPoints {
            FaceLandmarkPoints(leftEye: [CGPoint(x: box.minX, y: box.midY)], rightEye: [CGPoint(x: box.maxX, y: box.midY)],
                               outerLips: [CGPoint(x: box.midX, y: box.maxY)], boundingBox: box)
        }
        let small = face(CGRect(x: 2, y: 2, width: 2, height: 2))
        let large = face(CGRect(x: 1, y: 1, width: 6, height: 6))
        let other = face(CGRect(x: 12, y: 2, width: 4, height: 4))
        XCTAssertEqual(SubjectExtractor.associateFaces([small, large, other], masks: [left, right], width: w, height: h), [1, 2])
        XCTAssertEqual(SubjectExtractor.associateFaces([other], masks: [left], width: w, height: h), [nil])

        // Cara fuera de su instancia (Vision la deja fuera) con el cuello y el pecho
        // dentro: asociación indirecta, que pierde frente a una cara directa.
        let W = 20, H = 20
        var body = [UInt8](repeating: 0, count: W * H)
        for y in 8..<20 { for x in 4..<16 { body[y * W + x] = 255 } }
        let outside = face(CGRect(x: 6, y: 1, width: 8, height: 7))
        let detailed = SubjectExtractor.associateFacesDetailed([outside], masks: [body], width: W, height: H)
        XCTAssertEqual(detailed.first??.face, 0)
        XCTAssertEqual(detailed.first??.direct, false)
        let inside = face(CGRect(x: 6, y: 9, width: 8, height: 5))
        XCTAssertEqual(SubjectExtractor.associateFaces([outside, inside], masks: [body], width: W, height: H), [1])
        // Por debajo tampoco hay persona: sin asociar.
        XCTAssertEqual(SubjectExtractor.associateFaces([face(CGRect(x: 0, y: 0, width: 3, height: 3))], masks: [right],
                                                       width: w, height: h), [nil])
    }

    func testPNMRoundTrip() {
        let gray: [UInt8] = [0, 1, 2, 255, 128, 64]
        let parsed = PNM.read(PNM.pgm(width: 3, height: 2, gray: gray))
        XCTAssertEqual(parsed?.width, 3)
        XCTAssertEqual(parsed?.channels, 1)
        XCTAssertEqual(parsed?.bytes, gray)
        let rgb: [UInt8] = Array(0..<12)
        let p6 = PNM.read(PNM.ppm(width: 2, height: 2, rgb: rgb))
        XCTAssertEqual(p6?.channels, 3)
        XCTAssertEqual(p6?.bytes, rgb)
        XCTAssertNil(PNM.read(Data("P5\n2 2\n65535\n".utf8)))
    }
}
