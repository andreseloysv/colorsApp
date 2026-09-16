// Vision real (macOS) sobre imágenes SIN personas: VNGeneratePersonInstanceMaskRequest
// devuelve instancias en bandas de color, degradados y texturas; la evidencia corporal
// (PersonEvidence) las descarta y la foto se analiza completa.
//
//   - ios/ColorsAppTests/Fixtures/sim_media: los 20 PNG del carrete del simulador -> 0 personas.
//   - harness/out/nopeople: 148 sintéticas de harness/people/nopeople/build_nopeople.py (bloques,
//     degradados, texturas y 48 prendas en percha, perchero, planas y en puerta; make subject-test
//     las genera y exige; con `swift test` suelto se omiten si faltan) -> 0 personas en >= 98 %
//     del conjunto y en >= 98 % de las prendas.
//   - PNG liso grande y PNG con alfa (los casos del verificador) -> 0 personas.
// Cada tabla imprime las instancias de Vision antes (sin filtro) y después.
import CoreGraphics
import Foundation
import ImageIO
import XCTest
import ColorEngine
@testable import SubjectKit

final class NoPeopleVisionTests: XCTestCase {
    private func load(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw NSError(domain: "NoPeopleVisionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "no se pudo leer \(url.path)"])
        }
        return image
    }

    /// Instancias de Vision sin filtro («antes») y detección por defecto («después»: evidencia
    /// corporal con rectángulos de persona). `shapeOnly` = personas que aceptaría la regla de forma
    /// sola de la versión anterior (sin pose, cara ni rectángulo).
    private func screen(_ image: CGImage) throws -> (raster: SubjectRaster, vision: [PersonInstance], people: [PersonInstance],
                                                    rejected: [RejectedPerson], shapeOnly: Int) {
        let raster = try SubjectRaster.rasterize(image)
        let unfiltered = try SubjectExtractor.detectPeopleDetailed(in: image, rasterWidth: raster.width, rasterHeight: raster.height,
                                                                   phantomOptions: PhantomOptions(enabled: false))
        let detection = try SubjectExtractor.detectPeopleDetailed(in: image, rasterWidth: raster.width, rasterHeight: raster.height)
        let old = SubjectExtractor.rejectPhantoms(unfiltered.people, width: raster.width, height: raster.height,
                                                  options: PhantomOptions(acceptShapeOnly: true, humanRectangles: false))
        return (raster, unfiltered.people, detection.people, detection.rejectedPhantoms, old.people.count)
    }

    private func row(_ name: String, _ r: (raster: SubjectRaster, vision: [PersonInstance], people: [PersonInstance],
                                           rejected: [RejectedPerson], shapeOnly: Int)) -> String {
        let ev = r.rejected.map { e in
            String(format: "cob %.3f alto/ancho %.2f relleno %.2f solidez %.2f alto %.2f forma %@ rectángulo %@", e.evidence.coverage,
                   e.evidence.aspect, e.evidence.extent, e.evidence.solidity, e.evidence.heightSpan,
                   e.evidence.plausibleShape ? "sí" : "no", e.evidence.humanBox == nil ? "no" : "sí")
        }.joined(separator: "; ")
        return "SIN PERSONAS | \(name) | \(r.raster.width)x\(r.raster.height) | Vision \(r.vision.count) | solo forma (antes) \(r.shapeOnly) | aceptadas \(r.people.count) | fantasmas \(r.rejected.count)\(ev.isEmpty ? "" : " (\(ev))")"
    }

    func testSimulatorRollFixturesHaveNoPeople() throws {
        let dir = PhotoCache.repoRoot.appendingPathComponent("ios/ColorsAppTests/Fixtures/sim_media")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".png") }.sorted()
        XCTAssertEqual(files.count, 20)
        var before = 0, shapeBefore = 0, lines: [String] = []
        for f in files {
            let r = try screen(try load(dir.appendingPathComponent(f)))
            before += r.vision.isEmpty ? 0 : 1
            shapeBefore += r.shapeOnly > 0 ? 1 : 0
            lines.append(row(f, r))
            XCTAssertEqual(r.people.count, 0, "\(f): persona aceptada en una imagen sin personas")
            // La cadena por defecto sobre la detección filtrada analiza la foto completa.
            if !r.rejected.isEmpty {
                var detection = PeopleDetection(people: r.people, timings: [:], warnings: [], unassignedPoses: 0, unassignedFaces: 0,
                                                faces: [], discardedPeople: 0, orphanPoses: [], orphanFaces: [])
                detection.rejectedPhantoms = r.rejected
                let result = try r.raster.pixels.withUnsafeBufferPointer { px in
                    try SubjectExtractor.mask(detection: detection, rgba: px, width: r.raster.width, height: r.raster.height,
                                              stride: r.raster.stride, options: .default)
                }
                XCTAssertEqual(result.steps, [.rejectedPhantom, .noPeople], f)
                XCTAssertNil(result.mask, f)
            }
        }
        lines.append("SIN PERSONAS | sim_media | imágenes con instancias de Vision \(before)/20 | con personas por la regla de forma anterior \(shapeBefore)/20 | con personas aceptadas (después) 0/20")
        print(lines.joined(separator: "\n"))
    }

    func testSyntheticNoPeopleSet() throws {
        let dir = PhotoCache.repoRoot.appendingPathComponent("harness/out/nopeople")
        let manifestURL = PhotoCache.repoRoot.appendingPathComponent("harness/people/nopeople/nopeople.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let entries = try XCTUnwrap(manifest?["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 148)
        let required = ProcessInfo.processInfo.environment["COLORSAPP_NOPEOPLE_REQUIRED"] == "1"
        let missing = entries.compactMap { $0["file"] as? String }.filter {
            !FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
        if !missing.isEmpty {
            let message = "faltan \(missing.count) imágenes en \(dir.path): uv run --project oracle python harness/people/nopeople/build_nopeople.py build"
            if required { XCTFail(message); return }
            throw XCTSkip(message)
        }
        var withVision = 0, withShape = 0, withPeople = 0, lines: [String] = []
        var byFamily: [String: (n: Int, vision: Int, shape: Int, people: Int)] = [:]
        for e in entries {
            let f = try XCTUnwrap(e["file"] as? String), family = e["family"] as? String ?? "?"
            let r = try screen(try load(dir.appendingPathComponent(f)))
            if !r.vision.isEmpty { withVision += 1 }
            if r.shapeOnly > 0 { withShape += 1 }
            if !r.people.isEmpty { withPeople += 1 }
            var t = byFamily[family] ?? (0, 0, 0, 0)
            t.n += 1
            t.vision += r.vision.isEmpty ? 0 : 1
            t.shape += r.shapeOnly > 0 ? 1 : 0
            t.people += r.people.isEmpty ? 0 : 1
            byFamily[family] = t
            if !r.vision.isEmpty { lines.append(row(f, r)) }
        }
        for (family, t) in byFamily.sorted(by: { $0.key < $1.key }) {
            lines.append("SIN PERSONAS | familia \(family) | imágenes \(t.n) | con instancias de Vision \(t.vision) | con personas por la regla de forma anterior \(t.shape) | con personas aceptadas (después) \(t.people)")
            XCTAssertGreaterThanOrEqual(Double(t.n - t.people), 0.98 * Double(t.n), "familia \(family): personas aceptadas en imágenes sin personas")
        }
        let n = entries.count
        lines.append("SIN PERSONAS | nopeople | imágenes con instancias de Vision \(withVision)/\(n) | con personas por la regla de forma anterior \(withShape)/\(n) | con 0 personas aceptadas (después) \(n - withPeople)/\(n)")
        print(lines.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(Double(n - withPeople), 0.98 * Double(n), "personas aceptadas en imágenes sin personas")
    }

    func testFlatAndTransparentImagesHaveNoPeople() throws {
        func image(width: Int, height: Int, draw: (CGContext) -> Void) throws -> CGImage {
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            draw(ctx)
            return try XCTUnwrap(ctx.makeImage())
        }
        let flat = try image(width: 2048, height: 2048) { ctx in
            ctx.setFillColor(red: 230 / 255, green: 179 / 255, blue: 26 / 255, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 2048, height: 2048))
        }
        let alpha = try image(width: 640, height: 480) { ctx in
            ctx.setFillColor(red: 140 / 255, green: 153 / 255, blue: 204 / 255, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            ctx.clear(CGRect(x: 320, y: 240, width: 320, height: 240))
        }
        var lines: [String] = []
        for (name, img) in [("liso 2048x2048", flat), ("alfa 640x480", alpha)] {
            let r = try screen(img)
            lines.append(row(name, r))
            XCTAssertEqual(r.people.count, 0, name)
            let result = try r.raster.pixels.withUnsafeBufferPointer { px in
                try SubjectExtractor.compute(image: img, rgba: px, width: r.raster.width, height: r.raster.height,
                                             stride: r.raster.stride, options: .default)
            }
            XCTAssertNil(result.mask, name)
            XCTAssertEqual(result.steps.last, .noPeople, name)
            XCTAssertEqual(result.steps.first == .rejectedPhantom, !result.rejectedPhantoms.isEmpty, name)
        }
        print(lines.joined(separator: "\n"))
    }
}
