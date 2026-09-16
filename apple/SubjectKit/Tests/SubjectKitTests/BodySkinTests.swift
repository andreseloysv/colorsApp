// Piel del cuerpo aprendida, halo de la piel y prueba de mangas con personas sintéticas
// (sin Vision). Casos de harness/people: cara iluminada y cuerpo en sombra (07: hombros,
// escote y brazos que el modelo de la cara no alcanzaba), bordes piel/prenda que arrastran
// un swatch hacia la piel (02, 05) y mangas de espaldas sin modelo de piel (03).
import CoreGraphics
import XCTest
import ColorEngine
@testable import SubjectKit

final class BodySkinTests: XCTestCase {
    private func run(_ scene: SyntheticScene, _ people: [PersonInstance], _ options: SubjectOptions) throws -> SubjectMaskResult {
        try scene.rgba.withUnsafeBufferPointer { px in
            try SubjectExtractor.mask(people: people, rgba: px, width: scene.width, height: SyntheticScene.height,
                                      stride: scene.stride, options: options)
        }
    }

    /// Color de piel `SyntheticScene.skin(x, y)` oscurecido por `factor` (sombra).
    private static func shaded(_ x: Int, _ y: Int, _ factor: Double) -> [UInt8] {
        SyntheticScene.skin(x, y).map { UInt8((Double($0) * factor).rounded()) }
    }

    /// Cara con sombreado realista (factor 0,86...1,04 en diagonal): la muestra de las
    /// mejillas de una cara real tiene una desviación típica de L* de 5–9, no la de un parche liso.
    private static func shadeFace(_ scene: inout SyntheticScene, ox: Int = 0) {
        for y in 5..<28 {
            for x in (22 + ox)...(38 + ox) {
                let t = Double((x - ox - 22) + (y - 5)) / Double(16 + 22)
                scene.paint(x: x, y: y, shaded(x, y, 0.86 + 0.18 * t))
            }
        }
    }

    /// Persona con camisa sin mangas: brazos de piel con un degradado de luz (del tono de
    /// la cara junto al hombro a `darkest` en el codo) y un escote en la sombra más oscura
    /// (filas 31...37 del torso, x 24...36). Devuelve la escena, la persona y la máscara del escote.
    private func sleevelessScene(darkest: Double = 0.8) throws -> (SyntheticScene, PersonInstance, [UInt8]) {
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        Self.shadeFace(&scene)
        var noArms = RegionOptions.default
        noArms.includeUpperArms = false
        let withArms = try clothingRegions(pose: p.pose, mask: p.mask, width: scene.width, height: 100)
        let without = try clothingRegions(pose: p.pose, options: noArms, mask: p.mask, width: scene.width, height: 100)
        for (i, v) in MaskOps.removed(before: withArms.mask, after: without.mask).enumerated() where v != 0 {
            let x = i % scene.width, y = i / scene.width
            let t = max(0, min(1, Double(y - 30) / 15))   // hombro (y 30) -> codo (y 45)
            scene.paint(x: x, y: y, Self.shaded(x, y, 1 - (1 - darkest) * t))
        }
        var neckline = [UInt8](repeating: 0, count: scene.width * 100)
        for y in 31...37 {
            for x in 24...36 {
                scene.paint(x: x, y: y, Self.shaded(x, y, darkest))
                neckline[y * scene.width + x] = 255
            }
        }
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose, faceSampleMask: p.face)
        return (scene, person, neckline)
    }

    func testBodySkinLearningRemovesShadedNecklineThatFaceModelMisses() throws {
        let (scene, person, neckline) = try sleevelessScene()
        let necklinePixels = MaskOps.nonZero(neckline)
        func kept(_ m: [UInt8]?) -> Int {
            guard let m else { return 0 }
            var n = 0
            for i in 0..<m.count where m[i] != 0 && neckline[i] != 0 { n += 1 }
            return n
        }
        func shirtRemoved(_ r: SubjectMaskResult) -> Int {
            // Camisa azul de la región que no está en la máscara final, sin contar el halo.
            guard let region = r.layers.primary?.regionMask, let excluded = r.layers.primary?.skinExcludedMask else { return 0 }
            var n = 0
            for i in 0..<region.count where region[i] != 0 && excluded[i] == 0 {
                if scene.color(x: i % scene.width, y: i / scene.width) == SyntheticScene.shirt { n += 1 }
            }
            return n
        }
        // Sin aprendizaje el modelo de la cara (iluminada) no alcanza el escote en sombra.
        var off = SubjectOptions.default
        off.skinLearningIterations = 0
        let before = try run(scene, [person], off)
        XCTAssertTrue(try XCTUnwrap(before.layers.primary).learnedSampleMasks.isEmpty)
        XCTAssertEqual(kept(before.mask), necklinePixels, "el modelo de la cara no quita el escote en sombra")
        // Por defecto: brazos desnudos -> se aprende la piel del cuerpo y el escote se va.
        let after = try run(scene, [person], .default)
        let layer = try XCTUnwrap(after.layers.primary)
        let d = try XCTUnwrap(layer.regionDecision)
        XCTAssertTrue(d.bareArmsDropped)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(d.armSkinPixels), SubjectExtractor.bareArmsThreshold(armPixels: try XCTUnwrap(d.armPixels), options: .default))
        XCTAssertFalse(layer.learnedSampleMasks.isEmpty, "brazos desnudos: aprendizaje")
        XCTAssertEqual(layer.learnedSampleMasks.count, layer.skinLearningPixels.count)
        XCTAssertEqual(kept(after.mask), 0, "escote en sombra quitado con la piel aprendida")
        XCTAssertEqual(shirtRemoved(after), 0, "la camisa azul no se toca (fuera del halo)")
        XCTAssertEqual(after.steps, [.poseRegions, .skinExcluded])
        print("PIEL DEL CUERPO | escote \(necklinePixels) px | sin aprendizaje queda \(kept(before.mask)) | con aprendizaje queda \(kept(after.mask)) | candidatos por pasada \(layer.skinLearningPixels) | halo \(layer.skinHaloPixels)")

        // Reproducible con el motor: cada pasada = candidatos de excludeSkin (Mahalanobis 3, sin
        // salvaguarda) con el modelo de la muestra anterior sobre la región con brazos, y el modelo
        // final = fitSkinModel de la última muestra.
        var zoneOptions = try XCTUnwrap(d.regionOptions)
        zoneOptions.includeUpperArms = true
        let zone = try clothingRegions(pose: try XCTUnwrap(d.regionPose), options: zoneOptions, mask: layer.personMask,
                                       width: scene.width, height: 100).mask
        try scene.rgba.withUnsafeBufferPointer { px in
            var sample = try XCTUnwrap(layer.faceSampleMask)
            for (k, learned) in layer.learnedSampleMasks.enumerated() {
                let model = try fitSkinModel(rgba: px, width: scene.width, height: 100, stride: scene.stride, sampleMask: sample)
                let c = try excludeSkin(rgba: px, width: scene.width, height: 100, stride: scene.stride, model: model,
                                        options: SkinOptions(maxMahalanobis: 3, maxExcludedFraction: 1), mask: zone)
                XCTAssertEqual(c.excluded, layer.skinLearningPixels[k], "pasada \(k + 1)")
                XCTAssertEqual(learned, MaskOps.union([sample, MaskOps.removed(before: zone, after: c.mask)]))
                sample = learned
            }
            XCTAssertEqual(layer.skinModel, try fitSkinModel(rgba: px, width: scene.width, height: 100, stride: scene.stride,
                                                             sampleMask: sample))
        }
    }

    func testLearningNeedsBareLimbsAndStopsOnSkinColoredGarment() throws {
        // Manga larga y pantalón (escena por defecto): no hay miembros desnudos, no se aprende.
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose, faceSampleMask: p.face)
        let plain = try run(scene, [person], .default)
        let d = try XCTUnwrap(plain.layers.primary?.regionDecision)
        XCTAssertEqual(d.armSkinPixels, 0)
        XCTAssertEqual(d.legSkinPixels, 0)
        XCTAssertNotNil(d.legPixels)
        XCTAssertTrue(try XCTUnwrap(plain.layers.primary).learnedSampleMasks.isEmpty)
        // Prenda color piel en todo el cuerpo: los brazos «desnudos» activan el aprendizaje, pero
        // los candidatos pasan de la salvaguarda (35 % de la región) y no se aprende nada.
        var skinSuit = SyntheticScene()
        let q = skinSuit.addPerson(0, skinBody: true)
        let suited = PersonInstance(id: 1, mask: q.mask, width: skinSuit.width, height: 100, pose: q.pose, faceSampleMask: q.face)
        let r = try run(skinSuit, [suited], .default)
        let layer = try XCTUnwrap(r.layers.primary)
        XCTAssertTrue(layer.learnedSampleMasks.isEmpty, "salvaguarda: no se aprende de una prenda color piel")
        XCTAssertEqual(r.steps.last, .skinGuard)
        XCTAssertEqual(layer.skinHaloPixels, 0, "sin halo con la salvaguarda")
    }

    func testBareLegsTriggerLearningAndLearningNeverTripsTheGuard() throws {
        // Pantalón corto: camisa en torso y brazos, pantorrillas (rodilla -> tobillo) de piel con
        // degradado de sombra hacia los tobillos.
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        Self.shadeFace(&scene)
        var noLower = RegionOptions.default
        noLower.includeLowerLegs = false
        var noLegs = noLower
        noLegs.includeLegs = false
        let full = try clothingRegions(pose: p.pose, mask: p.mask, width: scene.width, height: 100)
        let withoutLower = try clothingRegions(pose: p.pose, options: noLower, mask: p.mask, width: scene.width, height: 100)
        let without = try clothingRegions(pose: p.pose, options: noLegs, mask: p.mask, width: scene.width, height: 100)
        let calves = MaskOps.removed(before: full.mask, after: withoutLower.mask)
        let legs = MaskOps.removed(before: full.mask, after: without.mask)
        for (i, v) in calves.enumerated() where v != 0 {
            let x = i % scene.width, y = i / scene.width
            scene.paint(x: x, y: y, Self.shaded(x, y, 1 - 0.2 * max(0, min(1, Double(y - 80) / 17))))
        }
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose, faceSampleMask: p.face)
        func left(_ r: SubjectMaskResult) -> Int {
            var n = 0
            for i in 0..<calves.count where calves[i] != 0 && (r.mask?[i] ?? 0) != 0 { n += 1 }
            return n
        }
        let r = try run(scene, [person], .default)
        let layer = try XCTUnwrap(r.layers.primary)
        let d = try XCTUnwrap(layer.regionDecision)
        XCTAssertEqual(d.legPixels, MaskOps.nonZero(legs))
        XCTAssertEqual(layer.legsMask, legs)
        XCTAssertFalse(d.bareArmsDropped, "mangas de camisa")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(d.legSkinPixels), SubjectExtractor.bareArmsThreshold(armPixels: MaskOps.nonZero(legs), options: .default))
        XCTAssertFalse(layer.learnedSampleMasks.isEmpty, "pantorrillas desnudas: aprendizaje")
        // El aprendizaje se mide sin el crecimiento de la piel en sombra (que por sí solo ya alcanza
        // las pantorrillas en sombra conectadas): con crecimiento nunca queda más piel.
        var noGrow = SubjectOptions.default
        noGrow.skinGrowRadius = 0
        let learnedOnly = try run(scene, [person], noGrow)
        var off = noGrow
        off.skinLearningIterations = 0
        let base = try run(scene, [person], off)
        print("PIERNAS | pantorrillas \(MaskOps.nonZero(calves)) px de \(MaskOps.nonZero(legs)) de piernas, piel con el modelo de la cara \(d.legSkinPixels ?? -1) | quedan sin aprendizaje \(left(base)), con aprendizaje \(left(learnedOnly)), con aprendizaje y crecimiento \(left(r)) | candidatos \(layer.skinLearningPixels)")
        XCTAssertLessThan(left(learnedOnly), left(base))
        XCTAssertLessThanOrEqual(left(r), left(learnedOnly))
        XCTAssertEqual(r.steps, [.poseRegions, .skinExcluded])

        // Piernas enteras de piel (vestido muy corto en una persona sintética de piernas largas):
        // la piel aprendida marcaría más del 35 % de la región; esas pasadas no se aceptan y el
        // resultado nunca es la salvaguarda (que dejaría TODA la piel).
        var long = SyntheticScene()
        let q = long.addPerson(0)
        Self.shadeFace(&long)
        for (i, v) in legs.enumerated() where v != 0 {
            let x = i % long.width, y = i / long.width
            long.paint(x: x, y: y, Self.shaded(x, y, 1 - 0.2 * max(0, min(1, Double(y - 62) / 35))))
        }
        let longPerson = PersonInstance(id: 1, mask: q.mask, width: long.width, height: 100, pose: q.pose, faceSampleMask: q.face)
        let longRun = try run(long, [longPerson], .default)
        var longOff = SubjectOptions.default
        longOff.skinLearningIterations = 0
        let longBase = try run(long, [longPerson], longOff)
        XCTAssertEqual(longBase.steps, [.poseRegions, .skinExcluded])
        XCTAssertEqual(longRun.steps, [.poseRegions, .skinExcluded], "aprender no dispara la salvaguarda")
        var longLeft = 0, longLeftBase = 0
        for i in 0..<legs.count where legs[i] != 0 {
            if (longRun.mask?[i] ?? 0) != 0 { longLeft += 1 }
            if (longBase.mask?[i] ?? 0) != 0 { longLeftBase += 1 }
        }
        print("PIERNAS LARGAS | piernas \(MaskOps.nonZero(legs)) | quedan sin aprendizaje \(longLeftBase), con aprendizaje \(longLeft) | pasadas aceptadas \(longRun.layers.primary?.skinLearningPixels ?? [])")
        XCTAssertLessThanOrEqual(longLeft, longLeftBase)
    }

    func testHaloDilationMatchesBruteForce() {
        let w = 23, h = 17
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        for radius in 0...3 {
            var seeds = [UInt8](repeating: 0, count: w * h)
            var mask = [UInt8](repeating: 0, count: w * h)
            for i in 0..<(w * h) {
                if next() % 13 == 0 { seeds[i] = 255 }
                if next() % 3 != 0 { mask[i] = 255 }
            }
            let grown = MaskOps.dilate(seeds, width: w, height: h, radius: radius)
            var expected = [UInt8](repeating: 0, count: w * h)
            for y in 0..<h {
                for x in 0..<w {
                    var hit = false
                    for yy in max(0, y - radius)...min(h - 1, y + radius) {
                        for xx in max(0, x - radius)...min(w - 1, x + radius) where seeds[yy * w + xx] != 0 { hit = true }
                    }
                    expected[y * w + x] = hit ? 255 : 0
                }
            }
            XCTAssertEqual(grown, expected, "radio \(radius)")
            let halo = MaskOps.removeHalo(mask, around: seeds, width: w, height: h, radius: radius)
            var removed = 0
            for i in 0..<(w * h) where mask[i] != 0 && (radius > 0 && expected[i] != 0) { removed += 1 }
            XCTAssertEqual(halo.removed, removed, "radio \(radius)")
            XCTAssertEqual(MaskOps.nonZero(halo.mask), MaskOps.nonZero(mask) - removed)
        }
    }

    func testNewOptionValidation() throws {
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        let person = PersonInstance(id: 1, mask: p.mask, width: scene.width, height: 100, pose: p.pose, faceSampleMask: p.face)
        for (mutate, message) in [
            ({ (o: inout SubjectOptions) in o.skinLearningIterations = 9 }, "skinLearningIterations debe estar en 0...8"),
            ({ (o: inout SubjectOptions) in o.skinHaloRadius = -1 }, "skinHaloRadius debe estar en 0...8"),
            ({ (o: inout SubjectOptions) in o.sleeveMatchFraction = .nan }, "sleeveMatchFraction debe estar en 0...1"),
            ({ (o: inout SubjectOptions) in o.skinLearningMahalanobis = -1 },
             "skinLearningMahalanobis y sleeveMatchMahalanobis deben ser finitos y >= 0"),
        ] {
            var o = SubjectOptions.default
            mutate(&o)
            XCTAssertThrowsError(try run(scene, [person], o)) { e in
                XCTAssertEqual(e as? SubjectError, .invalidOptions(message))
            }
        }
    }

    /// Crecimiento de la piel en sombra (histéresis): una franja de piel en sombra pegada a piel
    /// iluminada (cuello / escote de harness/people 07, canto de la mano de 05) queda fuera del
    /// umbral estricto (2,75) pero dentro del de crecimiento (5) y se quita hasta `skinGrowRadius`
    /// pasos; un parche del MISMO color separado de la piel (prenda color piel) no se toca; con la
    /// salvaguarda superada no se crece.
    func testShadedSkinConnectedToRemovedSkinGrows() throws {
        var scene = SyntheticScene()
        let p = scene.addPerson(0)
        Self.shadeFace(&scene)
        let W = scene.width
        let model = try scene.rgba.withUnsafeBufferPointer { px in
            try fitSkinModel(rgba: px, width: W, height: 100, stride: scene.stride, sampleMask: p.face)
        }
        // Zonas (dentro de la región de ropa): piel iluminada (escote, 136 px), franja en sombra de 16
        // filas debajo (80 px; el crecimiento, 60 px, es < 0,5 de la piel quitada) y parche separado por
        // 3 filas de camisa.
        func zone(_ ys: ClosedRange<Int>, _ xs: ClosedRange<Int>) -> [UInt8] {
            var m = [UInt8](repeating: 0, count: W * 100)
            for y in ys { for x in xs { m[y * W + x] = 255 } }
            return m
        }
        let lit = zone(31...38, 22...38), band = zone(39...54, 28...32), patch = zone(58...61, 24...28)
        // Sombra que el umbral estricto no alcanza y el de crecimiento sí (comprobado con el motor).
        var factor: Double? = nil
        for f in Swift.stride(from: 0.9, through: 0.3, by: -0.01) {
            var probe = scene
            for i in 0..<(W * 100) where band[i] != 0 { probe.paint(x: i % W, y: i / W, Self.shaded(i % W, i / W, f)) }
            let (strict, loose) = try probe.rgba.withUnsafeBufferPointer { px in
                (try excludeSkin(rgba: px, width: W, height: 100, stride: probe.stride, model: model,
                                 options: SkinOptions(maxMahalanobis: 2.75, maxExcludedFraction: 1), mask: band).excluded,
                 try excludeSkin(rgba: px, width: W, height: 100, stride: probe.stride, model: model,
                                 options: SkinOptions(maxMahalanobis: 5, maxExcludedFraction: 1), mask: band).excluded)
            }
            if strict == 0 && loose == MaskOps.nonZero(band) {
                factor = f
                break
            }
        }
        let f = try XCTUnwrap(factor, "no hay sombra entre Mahalanobis 2,75 y 5 para el modelo de la cara")
        for i in 0..<(W * 100) {
            let x = i % W, y = i / W
            if lit[i] != 0 { scene.paint(x: x, y: y, Self.shaded(x, y, 0.95)) }
            if band[i] != 0 || patch[i] != 0 { scene.paint(x: x, y: y, Self.shaded(x, y, f)) }
        }
        let person = PersonInstance(id: 1, mask: p.mask, width: W, height: 100, pose: p.pose, faceSampleMask: p.face)
        func inside(_ m: [UInt8]?, _ z: [UInt8]) -> Int {
            guard let m else { return 0 }
            var n = 0
            for i in 0..<m.count where m[i] != 0 && z[i] != 0 { n += 1 }
            return n
        }
        var noGrow = SubjectOptions.default
        noGrow.skinGrowRadius = 0
        let before = try run(scene, [person], noGrow)
        XCTAssertEqual(inside(before.mask, lit), 0, "piel iluminada quitada por el umbral estricto")
        XCTAssertGreaterThan(inside(before.mask, band), 0, "sin crecimiento la franja en sombra queda")
        XCTAssertEqual(try XCTUnwrap(before.layers.primary).skinGrownPixels, 0)

        let after = try run(scene, [person], .default)
        let layer = try XCTUnwrap(after.layers.primary)
        let grown = try XCTUnwrap(layer.skinGrownMask)
        let radius = SubjectOptions.default.skinGrowRadius
        // Filas de la franja alcanzadas: 39 ... 38 + radio (un paso por fila desde la fila 38 de piel).
        let reached = zone(39...(38 + radius), 28...32), beyond = zone((39 + radius)...54, 28...32)
        XCTAssertEqual(inside(grown, reached), MaskOps.nonZero(reached), "franja en sombra crecida hasta el radio")
        XCTAssertEqual(inside(grown, beyond), 0, "más allá del radio no se crece")
        XCTAssertEqual(inside(grown, patch), 0, "parche del mismo color sin contacto con la piel: no se toca")
        XCTAssertEqual(inside(after.mask, patch), MaskOps.nonZero(patch), "el parche sigue en la máscara (lejos del halo)")
        XCTAssertEqual(layer.skinGrownPixels, MaskOps.nonZero(grown))
        XCTAssertEqual(layer.skinExcludedPixels,
                       MaskOps.nonZero(MaskOps.removed(before: try XCTUnwrap(layer.regionMask), after: try XCTUnwrap(layer.skinExcludedMask)))
                       + layer.skinGrownPixels + layer.skinHaloPixels)
        XCTAssertEqual(MaskOps.nonZero(try XCTUnwrap(layer.skinRemovedMask)), layer.skinExcludedPixels)
        // Candidatos = lo que cuenta el motor con el umbral de crecimiento sobre la máscara tras la exclusión.
        let candidates = try scene.rgba.withUnsafeBufferPointer { px in
            try excludeSkin(rgba: px, width: W, height: 100, stride: scene.stride, model: try XCTUnwrap(layer.skinModel),
                            options: SkinOptions(maxMahalanobis: 5, maxExcludedFraction: 1), mask: try XCTUnwrap(layer.skinExcludedMask)).excluded
        }
        XCTAssertEqual(layer.skinGrowCandidatePixels, candidates)
        XCTAssertEqual(after.steps, [.poseRegions, .skinExcluded])
        print("CRECIMIENTO | sombra x\(f) | franja \(MaskOps.nonZero(band)) px | quedan sin crecer \(inside(before.mask, band)) | crecidos \(layer.skinGrownPixels) | candidatos \(candidates) | parche intacto \(inside(after.mask, patch))/\(MaskOps.nonZero(patch))")

        // Salvaguarda: si piel + crecimiento superan maxExcludedFraction de la máscara, no se crece.
        var tight = SubjectOptions.default
        let regionPixels = MaskOps.nonZero(try XCTUnwrap(layer.regionMask))
        let strictPixels = layer.skinExcludedPixels - layer.skinGrownPixels - layer.skinHaloPixels
        tight.skinOptions.maxExcludedFraction = (Double(strictPixels) + 0.5) / Double(regionPixels)
        let guarded = try run(scene, [person], tight)
        let g = try XCTUnwrap(guarded.layers.primary)
        XCTAssertEqual(guarded.steps, [.poseRegions, .skinExcluded])
        XCTAssertEqual(g.skinGrownPixels, 0)
        XCTAssertNil(g.skinGrownMask)
        XCTAssertGreaterThan(inside(guarded.mask, band), 0)
        // Tope relativo: el crecimiento no puede superar skinGrowMaxRatio de la piel quitada.
        var ratio = SubjectOptions.default
        ratio.skinGrowMaxRatio = (Double(layer.skinGrownPixels) - 0.5) / Double(strictPixels)
        let capped = try XCTUnwrap(try run(scene, [person], ratio).layers.primary)
        XCTAssertEqual(capped.skinGrownPixels, 0)
        ratio.skinGrowMaxRatio = Double(layer.skinGrownPixels) / Double(strictPixels)
        XCTAssertEqual(try XCTUnwrap(try run(scene, [person], ratio).layers.primary).skinGrownPixels, layer.skinGrownPixels)
        // Opciones inválidas.
        var bad = SubjectOptions.default
        bad.skinGrowRadius = SubjectExtractor.maxGrowRadius + 1
        XCTAssertThrowsError(try run(scene, [person], bad))
        bad = .default
        bad.skinGrowMahalanobis = .nan
        XCTAssertThrowsError(try run(scene, [person], bad))
        bad = .default
        bad.skinGrowMaxRatio = 1.5
        XCTAssertThrowsError(try run(scene, [person], bad))
    }
}
