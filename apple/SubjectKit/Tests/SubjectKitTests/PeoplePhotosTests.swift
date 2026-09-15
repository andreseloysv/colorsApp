// Vision real sobre harness/people (8 fotos CC0, 1024 px) en macOS.
//
// Cifras reales medidas (make subject-test, macOS 26 / Xcode 27, 2026-09-15):
//
//   foto                           Vision  anotadas  con pose  con muestra de cara  nota
//   01_single_black_outfit            1        1         1          1 (32 px: < 50, sin piel)
//   02_single_dress_umbrella          1        1         1          1
//   03_couple_denim_street            2        2         2          0     de espaldas
//   04_two_women_backlit              2        2         2          0     perfil / espaldas
//   05_three_friends_closeup          3        3         2          2     gafas de sol en la central
//   06_group_courier_street           4        5         4          1     Vision da como mucho 4 instancias
//   07_group_mural_white_outfits      4        6         4          4     idem: fusiona a tres mujeres en una
//   08_artist_colorful_mural          1        1         1          0     mascarilla
//
// Por eso el criterio de cantidad es |detectadas − min(anotadas, 4)| <= 1.
// En 07 la instancia más grande fusiona a tres mujeres y no contiene el centro
// de bbox_hint sino el de la otra mayor anotada como empate (annotatedTies).
// La tabla de color dominante (ΔE00 frente a expected.json) se imprime en la
// salida del test.
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import XCTest
import ColorEngine
@testable import SubjectKit

struct ExpectedPhoto: Decodable {
    struct Garment: Decodable {
        let part: String
        let color_hex: String
        let name: String
    }
    struct Largest: Decodable {
        let bbox_hint: [Int]
        let garments: [Garment]
    }
    let file: String
    let people: Int
    let largest_person: Largest
    let notes: String
}

struct PhotoData: @unchecked Sendable {
    let expected: ExpectedPhoto
    let image: CGImage
    let raster: SubjectRaster
    let detection: PeopleDetection
}

/// Detecta una sola vez por foto (Vision tarda ~0,1–0,7 s por foto).
final class PhotoCache: @unchecked Sendable {
    static let shared = PhotoCache()
    private let lock = NSLock()
    private var photos: [PhotoData]?
    private var failure: String?

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func load() throws -> [PhotoData] {
        lock.lock()
        defer { lock.unlock() }
        if let photos { return photos }
        if let failure { throw NSError(domain: "PhotoCache", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
        let dir = Self.repoRoot.appendingPathComponent("harness/people")
        do {
            let data = try Data(contentsOf: dir.appendingPathComponent("expected.json"))
            let expected = try JSONDecoder().decode([ExpectedPhoto].self, from: data)
            var out: [PhotoData] = []
            for e in expected {
                let url = dir.appendingPathComponent(e.file)
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                    throw NSError(domain: "PhotoCache", code: 2, userInfo: [NSLocalizedDescriptionKey: "no se pudo leer \(url.path)"])
                }
                let raster = try SubjectRaster.rasterize(image, maxSide: 1024)
                let detection = try SubjectExtractor.detectPeopleDetailed(in: image, rasterWidth: raster.width,
                                                                          rasterHeight: raster.height)
                out.append(PhotoData(expected: e, image: image, raster: raster, detection: detection))
            }
            photos = out
            return out
        } catch {
            failure = "\(error)"
            throw error
        }
    }
}

final class PeoplePhotosTests: XCTestCase {
    /// Empates anotados en expected.json («notes»): otra persona de tamaño casi igual.
    static let annotatedTies: [String: [[Int]]] = [
        "03_couple_denim_street.png": [[365, 283, 582, 950]],   // «casi empatado con el hombre de la derecha»
        "07_group_mural_white_outfits.png": [[432, 165, 610, 620]], // «la de la izquierda y la central delantera»
    ]

    private func photos() throws -> [PhotoData] { try PhotoCache.shared.load() }

    private func mask(_ p: PhotoData, _ options: SubjectOptions) throws -> SubjectMaskResult {
        try p.raster.pixels.withUnsafeBufferPointer { px in
            try SubjectExtractor.mask(people: p.detection.people, rgba: px, width: p.raster.width,
                                      height: p.raster.height, stride: p.raster.stride, options: options)
        }
    }

    func testEachPhotoDetectsPeopleNearAnnotatedCount() throws {
        let all = try photos()
        XCTAssertEqual(all.count, 8)
        print("\nPERSONAS | foto | Vision | anotadas | con pose | con cara | detección ms")
        for p in all {
            let n = p.detection.people.count
            let expected = min(p.expected.people, 4)
            let poses = p.detection.people.filter { $0.pose != nil }.count
            let faces = p.detection.people.filter { $0.faceSampleMask != nil }.count
            print("PERSONAS | \(p.expected.file) | \(n) | \(p.expected.people) | \(poses) | \(faces) | \(Int(p.detection.timings["detect"] ?? 0))")
            XCTAssertGreaterThanOrEqual(n, 1, p.expected.file)
            XCTAssertLessThanOrEqual(abs(n - expected), 1, "\(p.expected.file): \(n) personas frente a \(p.expected.people) anotadas")
            XCTAssertEqual(p.detection.people.map(\.coverage), p.detection.people.map(\.coverage).sorted(by: >))
            for person in p.detection.people {
                XCTAssertEqual(person.mask.count, p.raster.width * p.raster.height)
            }
        }
    }

    func testLargestPersonContainsBboxHintCenter() throws {
        for p in try photos() {
            let largest = try XCTUnwrap(p.detection.people.first, p.expected.file)
            let W = p.raster.width, H = p.raster.height
            // bbox_hint es aproximado (p. ej. en 08 el centro cae entre el brazo
            // extendido y la camiseta): se acepta un píxel >= 128 a una distancia
            // de Chebyshev <= max(8, 10 % del lado menor del bbox) del centro.
            func contains(_ box: [Int]) -> Bool {
                let cx = (box[0] + box[2]) / 2, cy = (box[1] + box[3]) / 2
                let r = max(8, min(box[2] - box[0], box[3] - box[1]) / 10)
                for y in max(0, cy - r)...min(H - 1, cy + r) {
                    for x in max(0, cx - r)...min(W - 1, cx + r) where largest.mask[y * W + x] >= 128 {
                        return true
                    }
                }
                return false
            }
            let primary = contains(p.expected.largest_person.bbox_hint)
            let tie = (Self.annotatedTies[p.expected.file] ?? []).contains(where: contains)
            print("MAYOR | \(p.expected.file) | bbox_hint \(primary ? "sí" : "no") | empate anotado \(tie ? "sí" : "no") | bbox \(largest.bbox)")
            XCTAssertTrue(primary || tie, "\(p.expected.file): la persona más grande no contiene el centro de bbox_hint ni de un empate anotado")
        }
    }

    func testClothingHasNothingAboveShouldersOrHeadBand() throws {
        for p in try photos() {
            let W = p.raster.width
            let r = try mask(p, SubjectOptions(mode: .allPeople, adaptiveSkin: false))
            for layer in r.layers.persons {
                let region = try XCTUnwrap(layer.regionMask)
                let d = try XCTUnwrap(layer.regionDecision)
                var outside = 0, soft = 0
                region.withUnsafeBufferPointer { rb in
                    layer.personMask.withUnsafeBufferPointer { pb in
                        for i in 0..<rb.count {
                            if rb[i] > 0 && pb[i] == 0 { outside += 1 }
                            if pb[i] != 0 && pb[i] != 255 { soft += 1 }
                        }
                    }
                }
                XCTAssertEqual(soft, 0, "persona binaria")
                XCTAssertEqual(outside, 0, "\(p.expected.file) persona \(layer.personIndex): región fuera de la persona binaria (halo)")
                if let silhouette = layer.silhouetteMask {
                    XCTAssertEqual(MaskOps.nonZero(silhouette), d.silhouettePixels)
                    XCTAssertEqual(MaskOps.nonZero(MaskOps.removed(before: silhouette, after: layer.personMask)), 0,
                                   "\(p.expected.file) persona \(layer.personIndex): silueta fuera de la persona binaria")
                }
                let share = String(format: "%.0f %%", 100 * Double(d.regionPixels) / Double(max(1, d.bodyPixels)))
                switch d.source {
                case .poseRegions, .poseSilhouette:
                    let pose = try XCTUnwrap(d.regionPose)
                    let geom = try XCTUnwrap(ShoulderGeometry(pose), "\(p.expected.file): pose aceptada por el motor sin hombros")
                    var above = 0
                    for (i, v) in region.enumerated() where v > 0 {
                        if geom.side(x: Double(i % W) + 0.5, y: Double(i / W) + 0.5) < 0 { above += 1 }
                    }
                    let silShare = String(format: "%.0f %%", 100 * Double(d.silhouettePixels ?? 0) / Double(max(1, d.bodyPixels)))
                    print("ROPA | \(p.expected.file) | persona \(layer.personIndex) | \(d.source.rawValue)\(d.hipsEstimated ? " (caderas estimadas)" : "") | píxeles \(d.regionPixels) = \(share) de la persona | regiones \(d.poseRegionPixels ?? 0) (mínimo \(d.requiredPixels) = 15 % de la silueta \(d.silhouettePixels ?? 0), \(silShare) de la persona) | por encima de hombros \(above)")
                    XCTAssertEqual(above, 0, "\(p.expected.file) persona \(layer.personIndex)")
                case .headCut:
                    let fraction = try XCTUnwrap(d.headCutFraction)
                    var y0 = Int.max, y1 = -1
                    for (i, v) in layer.personMask.enumerated() where v > 0 {
                        y0 = min(y0, i / W)
                        y1 = max(y1, i / W)
                    }
                    let c = Int((fraction * Double(y1 - y0 + 1) + 0.5).rounded(.down))
                    var inBand = 0
                    for y in y0..<(y0 + c) { for x in 0..<W where region[y * W + x] > 0 { inBand += 1 } }
                    print("ROPA | \(p.expected.file) | persona \(layer.personIndex) | headCut \(String(format: "%.3f", fraction))\(layer.steps.contains(.poseRegions) ? " (silueta de la pose \(d.silhouettePixels ?? 0) px < suelo \(d.requiredPixels))" : "") | píxeles \(d.regionPixels) = \(share) de la persona | en la franja de la cabeza \(inBand)")
                    XCTAssertEqual(inBand, 0, "\(p.expected.file) persona \(layer.personIndex)")
                case .wholePerson:
                    XCTFail("\(p.expected.file): región de ropa pedida y se obtuvo la persona completa")
                }
            }
        }
    }

    func testAdaptiveSkinFractionBelowGuardOrGuardAnnotated() throws {
        var applied = 0
        for p in try photos() {
            let r = try mask(p, SubjectOptions(mode: .allPeople, adaptiveSkin: true))
            for layer in r.layers.persons {
                let input = layer.regionMask ?? layer.personMask
                let fraction = Double(layer.skinExcludedPixels) / Double(max(1, MaskOps.nonZero(input)))
                let status = layer.steps.contains(.skinExcluded) ? "skinExcluded" :
                    layer.steps.contains(.skinGuard) ? "skinGuard" :
                    (layer.skinModel != nil ? "modelo sin piel en la región" : (layer.skinNote ?? "sin muestra"))
                let source = layer.skinSampleSource.map { $0 == layer.personIndex ? "propia" : "de la persona \($0)" } ?? "–"
                let arms: String
                if let d = layer.regionDecision, let n = d.armPixels {
                    arms = "brazos \(d.bareArmsDropped ? "desnudos, fuera" : "se quedan") (piel \(d.armSkinPixels ?? 0)/\(n) = \(String(format: "%.0f", 100 * Double(d.armSkinPixels ?? 0) / Double(max(1, n)))) %)"
                } else {
                    arms = layer.regionDecision?.upperArmsDropped == true ? "brazos fuera (sin modelo)" : "brazos sin prueba"
                }
                print("PIEL | \(p.expected.file) | persona \(layer.personIndex) | \(status) | muestra \(layer.faceSampleMask.map { MaskOps.nonZero($0) } ?? 0) (\(source)) | \(arms) | excluida \(String(format: "%.1f", fraction * 100)) %")
                if layer.steps.contains(.skinExcluded) {
                    applied += 1
                    XCTAssertLessThanOrEqual(fraction, 0.35, p.expected.file)
                    XCTAssertEqual(MaskOps.nonZero(try XCTUnwrap(layer.skinRemovedMask)), layer.skinExcludedPixels)
                } else if layer.steps.contains(.skinGuard) {
                    XCTAssertNil(layer.skinRemovedMask)
                } else if layer.skinModel != nil {
                    XCTAssertEqual(layer.skinExcludedPixels, 0, p.expected.file)
                    XCTAssertNil(layer.skinRemovedMask)
                }
                if layer.skinModel == nil {
                    XCTAssertEqual(layer.regionDecision?.upperArmsDropped, layer.regionDecision?.regionPose != nil,
                                   "\(p.expected.file): sin modelo de piel, la región de la pose va sin brazos")
                }
            }
        }
        XCTAssertGreaterThan(applied, 0, "ninguna persona llegó a excluir piel en harness/people")
    }

    /// Referencias de piel y fondo (apple/SubjectKit/Fixtures/people_references.json).
    struct References: Decodable {
        struct Patch: Decodable { let x: Int; let y: Int; let hex: String; let name: String }
        struct Photo: Decodable { let sha256: String; let skin: [Patch]; let background: [Patch] }
        let photos: [String: Photo]
    }

    static func lab(_ hex: String) -> Lab? {
        guard hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return srgbToLab(r: UInt8(v >> 16 & 0xff), g: UInt8(v >> 8 & 0xff), b: UInt8(v & 0xff))
    }

    /// Evidencia de que el recorte ayuda, con dos medidas por variante:
    /// 1. color dominante de la paleta (ColorEngine.extractPalette con la máscara)
    ///    frente a la prenda anotada;
    /// 2. reparto del peso de la paleta: cada swatch va a la referencia más cercana
    ///    (ΔE00 <= 10) entre prendas anotadas, parches de piel y parches de fondo u
    ///    objetos; si no, «otro». El dominante solo no ve un 40 % de piel en la paleta.
    /// Gates (fallan el test): la variante por defecto acerca el dominante frente a sin
    /// máscara, deja menos piel y menos fondo de media que la persona completa, y ninguna
    /// foto pasa del 35 % de peso de piel. Las cifras se imprimen (COLOR, PESO).
    func testDominantColorTable() throws {
        let variants: [(String, SubjectOptions?)] = [
            ("none", nil),
            ("allPeople", SubjectOptions(mode: .allPeople, region: .wholePerson, adaptiveSkin: false)),
            ("largest", SubjectOptions(mode: .largestPerson, region: .wholePerson, adaptiveSkin: false)),
            ("largest-clothing", SubjectOptions(mode: .largestPerson, region: .clothing, adaptiveSkin: false)),
            ("largest-clothing-skin", SubjectOptions.default),
        ]
        let refURL = PhotoCache.repoRoot.appendingPathComponent("apple/SubjectKit/Fixtures/people_references.json")
        let references = try JSONDecoder().decode(References.self, from: Data(contentsOf: refURL))
        var sums: [String: [Double]] = [:]
        var classes: [String: [String: [Double]]] = [:]
        var lines = ["", "COLOR | foto | variante | pasos | dominante (peso) | prenda 1 | ΔE00 prenda 1 | ΔE00 mín.",
                     "PESO | foto | variante | prenda | piel | fondo | otro"]
        for p in try photos() {
            let garments = p.expected.largest_person.garments.compactMap { Self.lab($0.color_hex) }
            let ref = try XCTUnwrap(references.photos[p.expected.file], "\(p.expected.file) sin referencias")
            let png = try Data(contentsOf: PhotoCache.repoRoot.appendingPathComponent("harness/people/\(p.expected.file)"))
            XCTAssertEqual(SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(), ref.sha256,
                           "\(p.expected.file): la foto no es la de las referencias")
            var refs: [(cls: String, lab: Lab)] = garments.map { ("prenda", $0) }
            refs += ref.skin.compactMap { Self.lab($0.hex).map { ("piel", $0) } }
            refs += ref.background.compactMap { Self.lab($0.hex).map { ("fondo", $0) } }
            for (name, options) in variants {
                var m: [UInt8]? = nil
                var steps = "–"
                if let options {
                    let r = try mask(p, options)
                    m = r.mask
                    steps = r.steps.map(\.rawValue).joined(separator: "+")
                    if let mm = r.mask { XCTAssertEqual(r.layers.finalMask, mm) }
                }
                let swatches = try p.raster.pixels.withUnsafeBufferPointer { px -> [Swatch] in
                    if let m {
                        return try m.withUnsafeBufferPointer { mb in
                            try extractPalette(rgba: px, width: p.raster.width, height: p.raster.height,
                                               stride: p.raster.stride, mask: mb)
                        }
                    }
                    return try extractPalette(rgba: px, width: p.raster.width, height: p.raster.height,
                                              stride: p.raster.stride)
                }
                let dom = try XCTUnwrap(swatches.first)
                let deMain = deltaE2000(dom.lab, garments[0])
                let deMin = garments.map { deltaE2000(dom.lab, $0) }.min() ?? deMain
                sums[name, default: []].append(deMin)
                var weight: [String: Double] = ["prenda": 0, "piel": 0, "fondo": 0, "otro": 0]
                for sw in swatches {
                    let nearest = refs.map { ($0.cls, deltaE2000(sw.lab, $0.lab)) }.min { $0.1 < $1.1 }
                    let cls = nearest.flatMap { $0.1 <= 10 ? $0.0 : nil } ?? "otro"
                    weight[cls, default: 0] += sw.weight
                }
                for (k, v) in weight { classes[name, default: [:]][k, default: []].append(v) }
                lines.append("COLOR | \(p.expected.file) | \(name) | \(steps.isEmpty ? "–" : steps) | \(dom.hex) (\(Int((dom.weight * 100).rounded())) %) | \(p.expected.largest_person.garments[0].color_hex) | \(String(format: "%.1f", deMain)) | \(String(format: "%.1f", deMin))")
                lines.append("PESO | \(p.expected.file) | \(name) | " + ["prenda", "piel", "fondo", "otro"].map {
                    String(format: "%.0f %%", 100 * (weight[$0] ?? 0))
                }.joined(separator: " | "))
            }
        }
        func mean(_ xs: [Double]?) -> Double { (xs ?? []).reduce(0, +) / Double(max(1, xs?.count ?? 0)) }
        lines.append("COLOR | media ΔE00 mín. por variante: " + variants.map { v in
            "\(v.0) \(String(format: "%.1f", mean(sums[v.0])))"
        }.joined(separator: ", "))
        for (name, _) in variants {
            let c = classes[name] ?? [:]
            lines.append("PESO | media \(name) | prenda \(String(format: "%.1f", 100 * mean(c["prenda"]))) % | piel \(String(format: "%.1f", 100 * mean(c["piel"]))) % (máx \(String(format: "%.1f", 100 * (c["piel"]?.max() ?? 0))) %) | fondo \(String(format: "%.1f", 100 * mean(c["fondo"]))) % (máx \(String(format: "%.1f", 100 * (c["fondo"]?.max() ?? 0))) %) | otro \(String(format: "%.1f", 100 * mean(c["otro"]))) %")
        }
        print(lines.joined(separator: "\n"))
        let def = classes["largest-clothing-skin"] ?? [:], whole = classes["largest"] ?? [:]
        XCTAssertLessThan(mean(sums["largest-clothing-skin"]), mean(sums["none"]),
                          "el recorte por defecto no acerca el dominante a la prenda anotada")
        XCTAssertLessThan(mean(def["piel"]), mean(whole["piel"]), "la variante por defecto no deja menos piel que la persona completa")
        XCTAssertLessThan(mean(def["fondo"]), mean(whole["fondo"]), "la variante por defecto no deja menos fondo que la persona completa")
        XCTAssertLessThanOrEqual(def["piel"]?.max() ?? 1, 0.35, "alguna foto conserva más del 35 % de peso de piel con la variante por defecto")
    }

    func testRasterIsExactForSRGBPNG() throws {
        // Las PNG de harness/people ya son sRGB de 1024 px: el raster es 1:1 (sin
        // reescalado) y conserva las dimensiones del fichero.
        for p in try photos() {
            XCTAssertEqual(p.raster.width, p.image.width)
            XCTAssertEqual(p.raster.height, p.image.height)
            XCTAssertEqual(max(p.raster.width, p.raster.height), 1024)
        }
    }
}

/// Recta de hombros de la pose con las reglas del motor (confianza >= 0,3 y
/// simetría con cuello/raíz): `side` > 0 en el lado de las caderas, 0 sobre la recta.
struct ShoulderGeometry {
    let a: (Double, Double), b: (Double, Double), sign: Double

    init?(_ pose: Pose, minConfidence: Double = RegionOptions.default.minConfidence) {
        func usable(_ k: Keypoint) -> (Double, Double)? {
            guard k.confidence.isFinite, k.confidence > 0, k.confidence >= minConfidence, k.x.isFinite, k.y.isFinite,
                  abs(k.x) <= 1_048_576, abs(k.y) <= 1_048_576 else { return nil }
            return (k.x, k.y)
        }
        func pair(_ l: Joint, _ r: Joint, _ mid: Joint) -> ((Double, Double), (Double, Double))? {
            let L = usable(pose[l]), R = usable(pose[r]), M = usable(pose[mid])
            if let L, let R { return (L, R) }
            if let L, let M { return (L, (2 * M.0 - L.0, 2 * M.1 - L.1)) }
            if let R, let M { return ((2 * M.0 - R.0, 2 * M.1 - R.1), R) }
            return nil
        }
        guard let s = pair(.leftShoulder, .rightShoulder, .neck), let h = pair(.leftHip, .rightHip, .root) else { return nil }
        a = s.0
        b = s.1
        let hm = ((h.0.0 + h.1.0) / 2, (h.0.1 + h.1.1) / 2)
        let c = (b.0 - a.0) * (hm.1 - a.1) - (b.1 - a.1) * (hm.0 - a.0)
        guard c != 0 else { return nil }
        sign = c > 0 ? 1 : -1
    }

    func side(x: Double, y: Double) -> Double {
        sign * ((b.0 - a.0) * (y - a.1) - (b.1 - a.1) * (x - a.0))
    }
}
