// Regiones de prenda (SubjectOptions.computeGarmentRegions -> SubjectMaskResult.garmentRegions)
// y paleta por prenda del motor (analyzeGarments, ADR-011) a través de la cadena de SubjectKit.
//
// 1. Sintéticos sin Vision (GarmentScene, deterministas): la persona del tranvía (CONTEXT §13:
//    camiseta #2b2c2c y pantalón #ddc0c8 con sombreado lambertiano y pliegues), camisa de rayas,
//    vestido, plano medio (caderas estimadas), sin pose, persona completa y allPeople.
// 2. Vision real sobre harness/people: por foto con pose, colores por prenda y ΔE00 a la prenda
//    anotada en expected.json frente al camino clásico (tabla ANTES/DESPUÉS en la salida) y el gate
//    del pantalón liso: <= 1 color en la parte de abajo salvo estampado anotado.
import CoreGraphics
import Foundation
import XCTest
import ColorEngine
@testable import SubjectKit

/// Persona sintética de 240 x 400 px (o varias en un lienzo más ancho) con ropa sombreada en luz lineal.
struct GarmentScene {
    static let personWidth = 240
    static let height = 400
    let width: Int
    var rgba: [UInt8]

    enum Top {
        case plain([UInt8])
        /// Rayas horizontales de `period / 2` px de cada color.
        case stripes([UInt8], [UInt8], period: Int)
    }

    static let skinBase: [UInt8] = [205, 152, 122]
    static let backgroundA: [UInt8] = [122, 138, 106]
    static let backgroundB: [UInt8] = [201, 183, 156]

    init(people: Int = 1) {
        width = Self.personWidth * people
        rgba = [UInt8](repeating: 255, count: width * Self.height * 4)
        for y in 0..<Self.height {
            for x in 0..<width {
                // Fondo con textura diagonal de dos colores (fuera de la máscara).
                paint(x: x, y: y, ((x + y) / 6) % 2 == 0 ? Self.backgroundA : Self.backgroundB, factor: 1)
            }
        }
    }

    static func toLinear(_ v: UInt8) -> Double {
        let c = Double(v) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func toSRGB8(_ l: Double) -> Int {
        let c = min(1, max(0, l))
        let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        return Int((v * 255).rounded())
    }

    /// Ruido determinista en -2...2 (sin RNG).
    static func noise(_ x: Int, _ y: Int, _ channel: Int) -> Int {
        let h = (x &* 73_856_093) ^ (y &* 19_349_663) ^ (channel &* 83_492_791)
        return ((h % 5) + 5) % 5 - 2
    }

    /// Pinta `color` multiplicado por `factor` en luz lineal (sombra), con ruido.
    mutating func paint(x: Int, y: Int, _ color: [UInt8], factor: Double) {
        let i = 4 * (y * width + x)
        for c in 0..<3 {
            let v = Self.toSRGB8(Self.toLinear(color[c]) * factor) + Self.noise(x, y, c)
            rgba[i + c] = UInt8(min(255, max(0, v)))
        }
    }

    static func distanceToSegment(_ px: Double, _ py: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        let vx = bx - ax, vy = by - ay
        let t = max(0, min(1, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy)))
        let dx = px - (ax + t * vx), dy = py - (ay + t * vy)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Sombreado de un cilindro iluminado de frente: `minFactor` en los bordes, 1 en el centro.
    static func cylinder(_ u: Double, minFactor: Double) -> Double {
        minFactor + (1 - minFactor) * max(0, 1 - u * u).squareRoot()
    }

    /// Dibuja la persona k (desplazada 240·k) y devuelve su máscara, pose y muestra de cara.
    /// `hips`: false borra caderas, rodillas y tobillos de la pose (plano medio: el motor recibe
    /// caderas estimadas).
    mutating func addPerson(_ k: Int = 0, top: Top, bottom: [UInt8], hips: Bool = true)
        -> (mask: [UInt8], pose: Pose, face: [UInt8]) {
        let ox = Double(Self.personWidth * k)
        var mask = [UInt8](repeating: 0, count: width * Self.height)
        var face = [UInt8](repeating: 0, count: width * Self.height)
        let x0 = Self.personWidth * k, x1 = x0 + Self.personWidth
        for y in 0..<Self.height {
            for x in x0..<x1 {
                let px = Double(x) + 0.5 - ox, py = Double(y) + 0.5
                var color: [UInt8]? = nil
                var factor = 1.0
                let head = ((px - 120) * (px - 120) + (py - 48) * (py - 48)).squareRoot() <= 28
                let neck = px >= 110 && px < 130 && py >= 70 && py < 86
                let torso = px >= 80 && px < 160 && py >= 86 && py < 212
                let sleeve = Self.distanceToSegment(px, py, 82, 92, 58, 150) <= 12
                    || Self.distanceToSegment(px, py, 158, 92, 182, 150) <= 12
                let forearm = Self.distanceToSegment(px, py, 58, 150, 54, 205) <= 10
                    || Self.distanceToSegment(px, py, 182, 150, 186, 205) <= 10
                let hand = ((px - 53) * (px - 53) + (py - 218) * (py - 218)).squareRoot() <= 11
                    || ((px - 187) * (px - 187) + (py - 218) * (py - 218)).squareRoot() <= 11
                let leftLeg = px >= 92 && px < 118 && py >= 212 && py < 392
                let rightLeg = px >= 122 && px < 148 && py >= 212 && py < 392
                if torso || sleeve {
                    switch top {
                    case .plain(let c): color = c
                    case .stripes(let a, let b, let period): color = (y / (period / 2)) % 2 == 0 ? a : b
                    }
                    // Cilindro del torso y pliegues horizontales.
                    factor = torso ? Self.cylinder((px - 120) / 40, minFactor: 0.35) : 0.7
                    if (py >= 150 && py < 156) || (py >= 190 && py < 194) { factor *= 0.7 }
                } else if leftLeg || rightLeg {
                    color = bottom
                    let cx = leftLeg ? 105.0 : 135.0
                    factor = Self.cylinder((px - cx) / 13, minFactor: 0.4)
                    // Pliegues en la rodilla y el tobillo, y la pierna izquierda un poco en sombra.
                    if (py >= 280 && py < 288) || (py >= 336 && py < 342) { factor *= 0.6 }
                    if leftLeg { factor *= 0.85 }
                } else if head || neck || forearm || hand {
                    let v = (x * 7 + y * 13) % 7 - 3
                    color = Self.skinBase.map { UInt8(Int($0) + v) }
                    factor = 1
                    if head, ((px - 120) * (px - 120) + (py - 52) * (py - 52)).squareRoot() <= 14 {
                        face[y * width + x] = 255
                    }
                }
                if let color {
                    paint(x: x, y: y, color, factor: factor)
                    mask[y * width + x] = 255
                }
            }
        }
        var pose = Pose()
        func set(_ j: Joint, _ x: Double, _ y: Double) { pose[j] = Keypoint(x: x + ox, y: y, confidence: 0.9) }
        set(.nose, 120, 50); set(.neck, 120, 90)
        set(.leftShoulder, 160, 92); set(.rightShoulder, 80, 92)
        set(.leftElbow, 182, 150); set(.rightElbow, 58, 150)
        set(.leftWrist, 186, 205); set(.rightWrist, 54, 205)
        if hips {
            set(.leftHip, 135, 212); set(.rightHip, 105, 212); set(.root, 120, 212)
            set(.leftKnee, 135, 300); set(.rightKnee, 105, 300)
            set(.leftAnkle, 135, 388); set(.rightAnkle, 105, 388)
        }
        return (mask, pose, face)
    }
}

func hexLab(_ hex: String) -> Lab {
    let v = UInt32(hex.dropFirst(), radix: 16)!
    return srgbToLab(r: UInt8(v >> 16 & 0xff), g: UInt8(v >> 8 & 0xff), b: UInt8(v & 0xff))
}

final class GarmentRegionsTests: XCTestCase {
    static let tShirt = "#2b2c2c"
    static let pinkPants = "#ddc0c8"

    private func run(_ scene: GarmentScene, _ people: [PersonInstance], _ options: SubjectOptions) throws -> SubjectMaskResult {
        try scene.rgba.withUnsafeBufferPointer { px in
            try SubjectExtractor.mask(people: people, rgba: px, width: scene.width, height: GarmentScene.height,
                                      stride: scene.width * 4, options: options)
        }
    }

    private func garments(_ scene: GarmentScene, mask: [UInt8], regions: [UInt8]?) throws -> GarmentAnalysisResult {
        try scene.rgba.withUnsafeBufferPointer { px in
            try mask.withUnsafeBufferPointer { mb in
                if let regions {
                    return try regions.withUnsafeBufferPointer { rb in
                        try analyzeGarments(rgba: px, width: scene.width, height: GarmentScene.height,
                                            stride: scene.width * 4, mask: mb, regions: rb, regionCount: garmentMaxRegions)
                    }
                }
                return try analyzeGarments(rgba: px, width: scene.width, height: GarmentScene.height,
                                           stride: scene.width * 4, mask: mb, regions: nil)
            }
        }
    }

    private func classic(_ scene: GarmentScene, mask: [UInt8]) throws -> AnalysisResult {
        try scene.rgba.withUnsafeBufferPointer { px in
            try mask.withUnsafeBufferPointer { mb in
                try analyze(rgba: px, width: scene.width, height: GarmentScene.height, stride: scene.width * 4, mask: mb)
            }
        }
    }

    private func person(_ p: (mask: [UInt8], pose: Pose, face: [UInt8]), id: Int = 1, width: Int, pose: Bool = true) -> PersonInstance {
        PersonInstance(id: id, mask: p.mask, width: width, height: GarmentScene.height, pose: pose ? p.pose : nil,
                       faceSampleMask: p.face)
    }

    private func colors(_ g: GarmentAnalysisResult, _ region: GarmentRegion) -> [GarmentSwatch] {
        g.garments.filter { $0.region == region }
    }

    private func describe(_ g: [GarmentSwatch]) -> String {
        g.map { "\($0.region)=\($0.swatch.hex) \(String(format: "%.0f", $0.swatch.weight * 100)) % (\($0.mergedClusterCount) clusters)" }
            .joined(separator: ", ")
    }

    /// Mapa válido: sus píxeles > 0 son exactamente los de la máscara y solo hay 0, 1 y 2.
    private func assertMapCoversMask(_ map: [UInt8], _ mask: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(map.count, mask.count, file: file, line: line)
        var mismatch = 0, invalid = 0
        for i in 0..<min(map.count, mask.count) {
            if (map[i] > 0) != (mask[i] > 0) { mismatch += 1 }
            if map[i] > 2 { invalid += 1 }
        }
        XCTAssertEqual(mismatch, 0, "píxeles del mapa distintos de los de la máscara", file: file, line: line)
        XCTAssertEqual(invalid, 0, "valores fuera de 0...2", file: file, line: line)
    }

    func testDefaultOptionsDoNotComputeGarmentRegions() throws {
        XCTAssertFalse(SubjectOptions.default.computeGarmentRegions)
        var scene = GarmentScene()
        let p = scene.addPerson(top: .plain([43, 44, 44]), bottom: [221, 192, 200])
        let r = try run(scene, [person(p, width: scene.width)], .default)
        XCTAssertNil(r.garmentRegions)
        XCTAssertNil(r.layers.primary?.garmentRegions)
        XCTAssertFalse(r.steps.contains(.garmentRegions))
        XCTAssertNil(r.timings["garments"])
    }

    /// CONTEXT §13: el pantalón rosa palo sombreado es UN color (su tono iluminado) en la parte de
    /// abajo; la camiseta negra, uno arriba. La máscara y los pasos previos no cambian.
    func testTramPantsGiveOneLitColorPerGarment() throws {
        var scene = GarmentScene()
        let p = scene.addPerson(top: .plain([0x2b, 0x2c, 0x2c]), bottom: [0xdd, 0xc0, 0xc8])
        let people = [person(p, width: scene.width)]
        let base = try run(scene, people, .default)
        var options = SubjectOptions.default
        options.computeGarmentRegions = true
        let r = try run(scene, people, options)
        XCTAssertEqual(r.mask, base.mask, "calcular las regiones no cambia la máscara")
        XCTAssertEqual(r.steps, base.steps + [.garmentRegions])
        XCTAssertEqual(r.steps.last, .garmentRegions)
        XCTAssertNotNil(r.timings["garments"])
        let mask = try XCTUnwrap(r.mask)
        let map = try XCTUnwrap(r.garmentRegions)
        assertMapCoversMask(map, mask)
        let layer = try XCTUnwrap(r.layers.primary)
        XCTAssertEqual(layer.garmentRegions, map)
        XCTAssertEqual(layer.steps.last, .garmentRegions)
        let stats = try XCTUnwrap(layer.garmentRegionStats)
        XCTAssertFalse(stats.lowerMergedIntoUpper)
        XCTAssertEqual(stats.upperPixels + stats.lowerPixels, stats.maskPixels)
        XCTAssertEqual(stats.options, SubjectExtractor.silhouetteOptions(try XCTUnwrap(layer.regionDecision?.regionOptions)))
        XCTAssertGreaterThan(stats.upperPixels, 0)
        XCTAssertGreaterThan(stats.lowerPixels, 0)
        // Abajo = filas de las piernas (y >= 212: más allá de la línea de caderas); arriba = torso y mangas.
        var lowerAboveHips = 0, upperBelowHips = 0
        for (i, v) in map.enumerated() {
            let y = i / scene.width
            if v == 2 && y < 212 { lowerAboveHips += 1 }
            if v == 1 && y >= 212 { upperBelowHips += 1 }
        }
        XCTAssertEqual(lowerAboveHips, 0)
        XCTAssertEqual(upperBelowHips, 0)
        // Mismo mapa que la función del motor con las entradas de la capa.
        let direct = try ColorEngine.garmentRegions(pose: stats.pose, options: stats.options, personMask: mask,
                                                    width: scene.width, height: GarmentScene.height)
        XCTAssertEqual(direct.regions, map)

        let g = try garments(scene, mask: mask, regions: map)
        let before = try classic(scene, mask: mask)
        let pink = hexLab(Self.pinkPants), black = hexLab(Self.tShirt)
        let lower = colors(g, .lower), upper = colors(g, .upper)
        let pinkClassic = before.swatches.filter { deltaE2000($0.lab, pink) < deltaE2000($0.lab, black) }
        print("\nPRENDAS SINTÉTICAS | tranvía | clásico: \(before.swatches.map { "\($0.hex) \(String(format: "%.0f", $0.weight * 100)) %" }.joined(separator: ", ")) | top-3 \(before.hits.map(\.comboId))")
        print("PRENDAS SINTÉTICAS | tranvía | por prenda: \(describe(g.garments)) | top-3 \(g.analysis.hits.map(\.comboId))")
        let lowerDE = lower.first.map { deltaE2000($0.swatch.lab, pink) } ?? .infinity
        let upperDE = upper.first.map { deltaE2000($0.swatch.lab, black) } ?? .infinity
        let classicPinkDE = pinkClassic.map { deltaE2000($0.lab, pink) }.min() ?? .infinity
        print(String(format: "PRENDAS SINTÉTICAS | tranvía | pantalón: clásico %d swatches rosas (ΔE00 mín. %.2f) -> por prenda %d (ΔE00 %.2f) | camiseta ΔE00 %.2f",
                     pinkClassic.count, classicPinkDE, lower.count, lowerDE, upperDE))
        XCTAssertGreaterThanOrEqual(pinkClassic.count, 2, "el camino clásico ya no reparte el pantalón en tonos: el test no mide nada")
        XCTAssertEqual(lower.count, 1, "el pantalón liso debe dar un solo color: \(describe(g.garments))")
        XCTAssertLessThan(lowerDE, 4, "tono iluminado del pantalón lejos de #ddc0c8")
        XCTAssertEqual(upper.count, 1, "la camiseta lisa debe dar un solo color: \(describe(g.garments))")
        XCTAssertLessThan(upperDE, 4, "tono de la camiseta lejos de #2b2c2c")
        XCTAssertTrue(colors(g, .whole).isEmpty, "camiseta y pantalón no son la misma prenda")
        XCTAssertEqual(g.analysis.swatches.count, g.garments.count)
    }

    func testStripedShirtKeepsTwoColorsOnTop() throws {
        var scene = GarmentScene()
        let p = scene.addPerson(top: .stripes([0x1f, 0x2a, 0x44], [0xe6, 0xe2, 0xda], period: 16), bottom: [0x3d, 0x5b, 0x7d])
        var options = SubjectOptions.default
        options.computeGarmentRegions = true
        let r = try run(scene, [person(p, width: scene.width)], options)
        let mask = try XCTUnwrap(r.mask), map = try XCTUnwrap(r.garmentRegions)
        assertMapCoversMask(map, mask)
        let g = try garments(scene, mask: mask, regions: map)
        print("PRENDAS SINTÉTICAS | rayas | por prenda: \(describe(g.garments))")
        let upper = colors(g, .upper)
        XCTAssertEqual(upper.count, 2, "camisa de rayas bicolor: \(describe(g.garments))")
        XCTAssertEqual(colors(g, .lower).count, 1, "vaquero liso: \(describe(g.garments))")
        let navy = hexLab("#1f2a44"), white = hexLab("#e6e2da")
        XCTAssertLessThan(upper.map { deltaE2000($0.swatch.lab, navy) }.min() ?? .infinity, 6)
        XCTAssertLessThan(upper.map { deltaE2000($0.swatch.lab, white) }.min() ?? .infinity, 6)
    }

    func testDressFusesIntoWholeGarment() throws {
        var scene = GarmentScene()
        let blue: [UInt8] = [0x5a, 0x82, 0xb3]
        let p = scene.addPerson(top: .plain(blue), bottom: blue)
        var options = SubjectOptions.default
        options.computeGarmentRegions = true
        let r = try run(scene, [person(p, width: scene.width)], options)
        let mask = try XCTUnwrap(r.mask), map = try XCTUnwrap(r.garmentRegions)
        let g = try garments(scene, mask: mask, regions: map)
        print("PRENDAS SINTÉTICAS | vestido | por prenda: \(describe(g.garments))")
        XCTAssertEqual(g.garments.map(\.region), [.whole], "vestido de un color: \(describe(g.garments))")
        XCTAssertLessThan(deltaE2000(g.garments[0].swatch.lab, hexLab("#5a82b3")), 4)
    }

    /// Plano medio: sin caderas en la pose el motor recibe caderas estimadas; no hay parte de
    /// abajo y la franja del torso más allá de las caderas inventadas pasa a la de arriba.
    func testEstimatedHipsGiveOnlyUpperRegion() throws {
        var scene = GarmentScene()
        let p = scene.addPerson(top: .plain([0x2b, 0x2c, 0x2c]), bottom: [0xdd, 0xc0, 0xc8], hips: false)
        var options = SubjectOptions.default
        options.computeGarmentRegions = true
        let r = try run(scene, [person(p, width: scene.width)], options)
        let layer = try XCTUnwrap(r.layers.primary)
        XCTAssertEqual(layer.regionDecision?.hipsEstimated, true)
        let map = try XCTUnwrap(r.garmentRegions), mask = try XCTUnwrap(r.mask)
        assertMapCoversMask(map, mask)
        XCTAssertFalse(map.contains(2))
        let stats = try XCTUnwrap(layer.garmentRegionStats)
        XCTAssertTrue(stats.lowerMergedIntoUpper)
        XCTAssertEqual(stats.lowerPixels, 0)
        let direct = try ColorEngine.garmentRegions(pose: stats.pose, options: stats.options, personMask: mask,
                                                    width: scene.width, height: GarmentScene.height)
        XCTAssertEqual(stats.mergedLowerPixels, direct.regions.filter { $0 == 2 }.count)
        XCTAssertEqual(direct.regions.map { $0 == 2 ? 1 : $0 }, map)
        print("PRENDAS SINTÉTICAS | caderas estimadas | arriba \(stats.upperPixels) px, abajo del motor unidos a arriba \(stats.mergedLowerPixels) px")
    }

    func testWithoutPoseOrWholePersonThereIsNoMap() throws {
        var scene = GarmentScene()
        let p = scene.addPerson(top: .plain([0x2b, 0x2c, 0x2c]), bottom: [0xdd, 0xc0, 0xc8])
        var options = SubjectOptions.default
        options.computeGarmentRegions = true
        let noPose = try run(scene, [person(p, width: scene.width, pose: false)], options)
        XCTAssertTrue(noPose.steps.contains(.headCut))
        XCTAssertNotNil(noPose.mask)
        XCTAssertNil(noPose.garmentRegions, "sin pose: camino clásico")
        XCTAssertFalse(noPose.steps.contains(.garmentRegions))
        var whole = options
        whole.region = .wholePerson
        let wp = try run(scene, [person(p, width: scene.width)], whole)
        XCTAssertNotNil(wp.mask)
        XCTAssertNil(wp.garmentRegions, "persona completa pedida: sin regiones de prenda")
        XCTAssertFalse(wp.steps.contains(.garmentRegions))
        var off = options
        off.mode = .off
        XCTAssertNil(try run(scene, [person(p, width: scene.width)], off).garmentRegions)
    }

    func testAllPeopleGivesOneMapPerPerson() throws {
        var scene = GarmentScene(people: 2)
        let a = scene.addPerson(0, top: .plain([0x2b, 0x2c, 0x2c]), bottom: [0xdd, 0xc0, 0xc8])
        let b = scene.addPerson(1, top: .plain([0x5a, 0x82, 0xb3]), bottom: [0x3d, 0x5b, 0x7d])
        var options = SubjectOptions(mode: .allPeople)
        options.computeGarmentRegions = true
        let r = try run(scene, [person(a, id: 1, width: scene.width), person(b, id: 2, width: scene.width)], options)
        XCTAssertNil(r.garmentRegions, "allPeople: el mapa va por persona")
        XCTAssertEqual(r.steps.last, .garmentRegions)
        let mask = try XCTUnwrap(r.mask)
        XCTAssertEqual(r.layers.persons.count, 2)
        var union = [UInt8](repeating: 0, count: mask.count)
        for layer in r.layers.persons {
            let map = try XCTUnwrap(layer.garmentRegions)
            assertMapCoversMask(map, layer.finalMask)
            XCTAssertEqual(layer.steps.last, .garmentRegions)
            for i in 0..<map.count where map[i] > 0 { union[i] = map[i] }
            // Cada mapa se analiza por separado (la persona con su propia máscara).
            let g = try garments(scene, mask: layer.finalMask, regions: map)
            print("PRENDAS SINTÉTICAS | allPeople persona \(layer.personIndex) | \(describe(g.garments))")
            XCTAssertEqual(colors(g, .lower).count + colors(g, .whole).count, 1)
        }
        XCTAssertEqual(union.map { $0 > 0 }, mask.map { $0 > 0 })
    }

    func testSelectedPersonGetsItsOwnMap() throws {
        var scene = GarmentScene(people: 2)
        let a = scene.addPerson(0, top: .plain([0x2b, 0x2c, 0x2c]), bottom: [0xdd, 0xc0, 0xc8])
        let b = scene.addPerson(1, top: .plain([0x5a, 0x82, 0xb3]), bottom: [0x3d, 0x5b, 0x7d])
        var options = SubjectOptions(mode: .selectedPerson, selectedIndex: 1)
        options.computeGarmentRegions = true
        let people = [person(a, id: 1, width: scene.width), person(b, id: 2, width: scene.width)]
        let r = try run(scene, people, options)
        let chosen = try XCTUnwrap(r.chosenIndex)
        let map = try XCTUnwrap(r.garmentRegions), mask = try XCTUnwrap(r.mask)
        assertMapCoversMask(map, mask)
        let expectedX = r.people[chosen].id == 1 ? 0..<240 : 240..<480
        for (i, v) in map.enumerated() where v > 0 {
            XCTAssertTrue(expectedX.contains(i % scene.width))
            if !expectedX.contains(i % scene.width) { break }
        }
    }
}

/// Vision real sobre harness/people: colores por prenda frente al camino clásico.
final class PeopleGarmentsTests: XCTestCase {
    /// Partes anotadas -> regiones de la paleta por prenda (una prenda entera vale en las dos).
    static func regions(for part: String) -> Set<GarmentRegion> {
        switch part {
        case "torso": [.upper, .whole]
        case "legs": [.lower, .whole]
        default: [.upper, .lower, .whole]
        }
    }

    /// Estampado anotado en una parte: dos colores anotados para ella o el nombre lo dice.
    static func patterned(_ garments: [ExpectedPhoto.Garment], part: String) -> Bool {
        let g = garments.filter { $0.part == part }
        return g.count > 1 || g.contains { $0.name.range(of: "estampad|rayas|cuadros|print", options: .regularExpression) != nil }
    }

    /// Límites conocidos del MOTOR (no de SubjectKit) medidos en esta foto: el gate sigue activo con
    /// XCTExpectFailure estricto (si la foto deja de fallar, el test falla y hay que quitarla de aquí).
    /// Vacío: el motor arregló el último (06, vaquero liso al sol y a la sombra, con el modelo
    /// de sombra cromática de exterior CE_GARMENT_SKY_W_MAX / CE_GARMENT_SKY_W_SLOPE), y el
    /// XCTExpectFailure estricto avisó («Expected failure ... but none recorded»).
    static let knownEngineLimits: [String: String] = [:]

    func testGarmentColorsPerPhotoBeforeAfter() throws {
        let photos = try PhotoCache.shared.load()
        var options = SubjectOptions.default
        options.computeGarmentRegions = true
        var lines = ["", "PRENDAS | foto | pasos | mapa (arriba / abajo px) | clásico: swatches | por prenda: arriba / abajo / entera | prenda anotada | ΔE00 clásico (swatch más cercano) | ΔE00 por prenda (swatch de su región) | top-3 clásico | top-3 por prenda"]
        var withPose = 0
        var deClassic: [Double] = [], deGarment: [Double] = []
        var countClassic: [Int] = [], countGarment: [Int] = []
        for p in photos {
            let W = p.raster.width, H = p.raster.height
            let plain = try p.raster.pixels.withUnsafeBufferPointer { px in
                try SubjectExtractor.mask(people: p.detection.people, rgba: px, width: W, height: H, stride: p.raster.stride,
                                          options: .default)
            }
            let r = try p.raster.pixels.withUnsafeBufferPointer { px in
                try SubjectExtractor.mask(people: p.detection.people, rgba: px, width: W, height: H, stride: p.raster.stride,
                                          options: options)
            }
            XCTAssertEqual(r.mask, plain.mask, "\(p.expected.file): calcular las regiones no cambia la máscara")
            let file = p.expected.file
            guard let mask = r.mask else {
                lines.append("PRENDAS | \(file) | \(r.steps.map(\.rawValue).joined(separator: "+")) | sin máscara | – | – | – | – | – | – | –")
                continue
            }
            let before = try p.raster.pixels.withUnsafeBufferPointer { px in
                try mask.withUnsafeBufferPointer { mb in
                    try analyze(rgba: px, width: W, height: H, stride: p.raster.stride, mask: mb)
                }
            }
            guard let map = r.garmentRegions else {
                XCTAssertEqual(r.steps, plain.steps, file)
                XCTAssertFalse(r.layers.primary?.regionDecision?.source == .poseRegions
                               || r.layers.primary?.regionDecision?.source == .poseSilhouette,
                               "\(file): región de la pose sin mapa de prendas")
                lines.append("PRENDAS | \(file) | \(r.steps.map(\.rawValue).joined(separator: "+")) | sin pose: camino clásico | \(before.swatches.count) | – | – | – | – | \(before.hits.map(\.comboId)) | –")
                continue
            }
            withPose += 1
            XCTAssertEqual(r.steps, plain.steps + [.garmentRegions], file)
            var mismatch = 0
            for i in 0..<mask.count where (map[i] > 0) != (mask[i] > 0) { mismatch += 1 }
            XCTAssertEqual(mismatch, 0, "\(file): el mapa no cubre exactamente la máscara")
            let stats = try XCTUnwrap(r.layers.primary?.garmentRegionStats)
            XCTAssertEqual(stats.upperPixels + stats.lowerPixels, stats.maskPixels, file)
            let after = try p.raster.pixels.withUnsafeBufferPointer { px in
                try mask.withUnsafeBufferPointer { mb in
                    try map.withUnsafeBufferPointer { rb in
                        try analyzeGarments(rgba: px, width: W, height: H, stride: p.raster.stride, mask: mb, regions: rb,
                                            regionCount: garmentMaxRegions)
                    }
                }
            }
            let n = { (region: GarmentRegion) in after.garments.filter { $0.region == region }.count }
            let annotated = p.expected.largest_person.garments
            var deC: [String] = [], deG: [String] = []
            for g in annotated {
                let lab = hexLab(g.color_hex)
                let c = before.swatches.map { deltaE2000($0.lab, lab) }.min() ?? .infinity
                let pool = after.garments.filter { Self.regions(for: g.part).contains($0.region) }
                let gd = (pool.isEmpty ? after.garments : pool).map { deltaE2000($0.swatch.lab, lab) }.min() ?? .infinity
                deClassic.append(c)
                deGarment.append(gd)
                deC.append(String(format: "%.1f", c))
                deG.append(String(format: "%.1f", gd))
            }
            countClassic.append(before.swatches.count)
            countGarment.append(after.garments.count)
            let garmentsText = after.garments.map { "\($0.region)=\($0.swatch.hex) \(String(format: "%.0f", $0.swatch.weight * 100)) %" }.joined(separator: ", ")
            lines.append("PRENDAS | \(file) | \(r.steps.map(\.rawValue).joined(separator: "+")) | \(stats.upperPixels) / \(stats.lowerPixels)\(stats.lowerMergedIntoUpper ? " (caderas estimadas: \(stats.mergedLowerPixels) px de abajo unidos a arriba)" : "") | \(before.swatches.count) | \(n(.upper)) / \(n(.lower)) / \(n(.whole)) [\(garmentsText)] | \(annotated.map { "\($0.part) \($0.color_hex)" }.joined(separator: "; ")) | \(deC.joined(separator: "; ")) | \(deG.joined(separator: "; ")) | \(before.hits.map(\.comboId)) | \(after.analysis.hits.map(\.comboId))")
            if stats.lowerMergedIntoUpper {
                XCTAssertEqual(n(.lower), 0, "\(file): con caderas estimadas no hay parte de abajo")
            }
            // Gate del pantalón liso: una persona con pantalón anotado sin estampado da <= 1 color abajo
            // (la parte de abajo o, si arriba y abajo se fusionaron, la prenda entera).
            if annotated.contains(where: { $0.part == "legs" }), !Self.patterned(annotated, part: "legs") {
                let lowerColors = n(.lower) + n(.whole)
                if let limit = Self.knownEngineLimits[file] {
                    XCTExpectFailure("límite conocido del motor en \(file): \(limit)") {
                        XCTAssertLessThanOrEqual(lowerColors, 1, "\(file): pantalón liso con \(lowerColors) colores abajo: \(garmentsText)")
                    }
                } else {
                    XCTAssertLessThanOrEqual(lowerColors, 1, "\(file): pantalón liso con \(lowerColors) colores abajo: \(garmentsText)")
                }
                lines.append("PRENDAS | \(file) | gate pantalón liso | colores abajo \(lowerColors)\(lowerColors <= 1 ? " OK" : " FALLA")\(Self.knownEngineLimits[file] != nil ? " (límite conocido del motor)" : "")")
            }
        }
        func mean<T: BinaryInteger>(_ xs: [T]) -> Double { xs.isEmpty ? .nan : Double(xs.reduce(0, +)) / Double(xs.count) }
        func mean(_ xs: [Double]) -> Double { xs.isEmpty ? .nan : xs.reduce(0, +) / Double(xs.count) }
        func median(_ xs: [Double]) -> Double {
            let s = xs.sorted()
            return s.isEmpty ? .nan : (s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2)
        }
        lines.append(String(format: "PRENDAS | resumen | fotos con mapa %d de %d | swatches medios clásico %.2f -> por prenda %.2f | ΔE00 a la prenda anotada: clásico media %.2f mediana %.2f -> por prenda media %.2f mediana %.2f",
                            withPose, photos.count, mean(countClassic), mean(countGarment), mean(deClassic), median(deClassic),
                            mean(deGarment), median(deGarment)))
        print(lines.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(withPose, 6, "harness/people: se esperaban >= 6 fotos con mapa de prendas")
    }
}
