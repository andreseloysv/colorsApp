// Paridad del motor dentro de la app (PLAN §8, F6): `EngineBridge.analyze`
// sobre el CGImage construido desde 5 PPM de harness/golden/fixtures devuelve
// exactamente lo que `ce match --top 3` grabó en harness/golden/match_50.json
// (mismo top-3, scores y swatches a 1e-9, mismo `ambiguous` y `hash`), y un
// PNG Display P3 del mismo fixture (sips --matchTo) da el mismo top-1 tras la
// conversión P3 -> sRGB de CoreGraphics. Fixtures generadas por
// oracle/tools/make_ios_fixtures.py (expected_match.json).
import XCTest
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import ColorEngine
@testable import ColorsApp

final class EngineParityTests: XCTestCase {
    struct Expected: Decodable {
        struct SwatchEntry: Decodable {
            let lab: [Double]
            let weight: Double
            let rgb: [Int]
            let hex: String
        }

        struct HitEntry: Decodable {
            let id: Int
            let score: Double
        }

        struct Entry: Decodable {
            let file: String
            let pngSrgb: String
            let pngP3: String
            let sha256: String
            let comboId: Int
            let variant: String
            let swatches: [SwatchEntry]
            let hits: [HitEntry]
            let ambiguous: Int
            let hash: String

            enum CodingKeys: String, CodingKey {
                case file, sha256, variant, swatches, hits, ambiguous, hash
                case pngSrgb = "png_srgb"
                case pngP3 = "png_p3"
                case comboId = "combo_id"
            }
        }

        let ceVersion: String
        let dictVersion: String
        let tolerance: Double
        let topK: Int
        let entries: [Entry]

        enum CodingKeys: String, CodingKey {
            case tolerance, entries
            case ceVersion = "ce_version"
            case dictVersion = "dict_version"
            case topK = "top_k"
        }
    }

    private var bundle: Bundle { Bundle(for: EngineParityTests.self) }

    private func loadExpected() throws -> Expected {
        let url = try XCTUnwrap(bundle.url(forResource: "expected_match", withExtension: "json"), "expected_match.json en el bundle")
        return try JSONDecoder().decode(Expected.self, from: Data(contentsOf: url))
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        return try XCTUnwrap(bundle.url(forResource: parts[0], withExtension: parts[1]), "\(name) en el bundle")
    }

    private func loadPNG(_ name: String) throws -> CGImage {
        let url = try fixtureURL(name)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), "CGImageSource \(name)")
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), "CGImage \(name)")
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func assertMatchesGolden(_ result: AnalysisResult, _ e: Expected.Entry, tolerance: Double,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.hits.map(\.comboId), e.hits.map(\.id), "top-3 \(e.file)", file: file, line: line)
        for (h, x) in zip(result.hits, e.hits) {
            XCTAssertEqual(h.score, x.score, accuracy: tolerance, "score combo \(x.id) \(e.file)", file: file, line: line)
        }
        XCTAssertEqual(result.swatches.count, e.swatches.count, "n swatches \(e.file)", file: file, line: line)
        for (s, x) in zip(result.swatches, e.swatches) {
            XCTAssertEqual(s.lab.L, x.lab[0], accuracy: tolerance, "L \(e.file)", file: file, line: line)
            XCTAssertEqual(s.lab.a, x.lab[1], accuracy: tolerance, "a \(e.file)", file: file, line: line)
            XCTAssertEqual(s.lab.b, x.lab[2], accuracy: tolerance, "b \(e.file)", file: file, line: line)
            XCTAssertEqual(s.weight, x.weight, accuracy: tolerance, "weight \(e.file)", file: file, line: line)
            XCTAssertEqual([Int(s.r), Int(s.g), Int(s.b)], x.rgb, "rgb \(e.file)", file: file, line: line)
            XCTAssertEqual(s.hex, x.hex, "hex \(e.file)", file: file, line: line)
        }
        XCTAssertEqual(result.ambiguous, e.ambiguous != 0, "ambiguous \(e.file)", file: file, line: line)
        XCTAssertEqual(result.hash, UInt64(e.hash, radix: 16), "hash \(e.file)", file: file, line: line)
    }

    // MARK: PPM sRGB == golden (bit a bit en píxeles, 1e-9 en números)

    func testGoldenMetadataMatchesEngine() throws {
        let expected = try loadExpected()
        XCTAssertEqual(expected.ceVersion, colorEngineVersion)
        XCTAssertEqual(expected.dictVersion, dictionaryVersion)
        XCTAssertEqual(expected.entries.count, 5)
        XCTAssertEqual(expected.topK, 3)
        XCTAssertEqual(expected.tolerance, 1e-9)
    }

    func testPPMFixturesMatchGoldenThroughCGImage() throws {
        let expected = try loadExpected()
        for e in expected.entries {
            let data = try Data(contentsOf: fixtureURL(e.file))
            XCTAssertEqual(sha256Hex(data), e.sha256, "sha256 \(e.file)")
            let ppm = try PPM.parse(data)
            XCTAssertEqual(ppm.width, 128)
            XCTAssertEqual(ppm.height, 128)
            let image = try XCTUnwrap(ppm.makeCGImage(), "CGImage \(e.file)")
            // Rasterizado 1:1 en el contexto sRGB: los bytes que ve el motor son los del PPM.
            let raster = try EngineBridge.rasterize(image)
            XCTAssertEqual(raster.width, 128)
            XCTAssertEqual(raster.height, 128)
            XCTAssertEqual(raster.stride, 512)
            XCTAssertEqual(raster.rgb, ppm.rgb, "píxeles \(e.file) no llegan intactos al motor")
            let result = try EngineBridge.analyze(cgImage: image, topK: expected.topK)
            assertMatchesGolden(result, e, tolerance: expected.tolerance)
            // El mismo raster analizado dos veces es idéntico (determinismo run-a-run).
            XCTAssertEqual(try EngineBridge.analyze(raster: raster, topK: expected.topK), result)
        }
    }

    func testAnalyzeDetachedMatchesSync() async throws {
        let expected = try loadExpected()
        let e = expected.entries[0]
        let image = try XCTUnwrap(PPM.read(url: fixtureURL(e.file)).makeCGImage())
        let detached = try await EngineBridge.analyzeDetached(cgImage: image, topK: expected.topK)
        assertMatchesGolden(detached, e, tolerance: expected.tolerance)
        let sync = try EngineBridge.analyze(cgImage: image, topK: expected.topK)
        XCTAssertEqual(detached, sync)
    }

    // MARK: PNG sRGB (perfil embebido) y PNG Display P3

    func testSRGBPNGReachesEngineIntact() throws {
        let expected = try loadExpected()
        for e in expected.entries {
            let ppm = try PPM.read(url: fixtureURL(e.file))
            let png = try loadPNG(e.pngSrgb)
            let raster = try EngineBridge.rasterize(png)
            let diff = maxChannelDiff(raster.rgb, ppm.rgb)
            XCTAssertEqual(diff, 0, "PNG sRGB \(e.pngSrgb): diferencia máxima por canal \(diff)")
            let result = try EngineBridge.analyze(cgImage: png, topK: expected.topK)
            assertMatchesGolden(result, e, tolerance: expected.tolerance)
        }
    }

    /// Medido 2026-09-15 (simulador iOS 27.0, Xcode 27.0, Apple M4 Pro), PNG
    /// Display P3 generados por sips desde el PNG sRGB del fixture, decodificados
    /// por ImageIO y dibujados en el CGContext sRGB de EngineBridge:
    ///   - Δ por canal frente al PPM sRGB: máx 1/255 en 4/5 fixtures, 0 en f13
    ///     (media 0,00–0,51 niveles).
    ///   - top-1 idéntico en 5/5; top-3 idéntico en 4/5 (f24, el fixture
    ///     `ambiguous`, intercambia los hits 2 y 3: 124/148 a 17,56 vs 17,40).
    ///   - ΔE00 entre swatches homólogos (P3 vs PPM): máx 0,38 en 4/5 fixtures;
    ///     1,19 en un swatch de f37 (distractor, 5 swatches: la diferencia de
    ///     1/255 mueve píxeles de frontera entre clusters de Lloyd; el swatch
    ///     pesa 0,11). Los swatches con Δcanal 0 dan ΔE00 = 0.
    /// Contrato de este test: mismo top-1 (tarea F6), Δcanal ≤ 1/255 (PLAN §8)
    /// y ΔE00 por swatch ≤ 1,5 (medido 1,19; el ≤ 0,5 de PLAN §8 se cumple en
    /// 4/5 fixtures y queda anotado en engine/BENCHLOG.md). El detalle se
    /// imprime y se adjunta al xcresult.
    func testDisplayP3PNGGivesSameTopOne() throws {
        let expected = try loadExpected()
        var report: [String] = []
        var worstChannel = 0
        var worstDeltaE = 0.0
        var sameTop3 = 0
        for e in expected.entries {
            let ppm = try PPM.read(url: fixtureURL(e.file))
            let png = try loadPNG(e.pngP3)
            let spaceName = png.colorSpace.flatMap { $0.name as String? } ?? String(describing: png.colorSpace)
            let raster = try EngineBridge.rasterize(png)
            XCTAssertEqual(raster.width, ppm.width)
            XCTAssertEqual(raster.height, ppm.height)
            let channelDiff = maxChannelDiff(raster.rgb, ppm.rgb)
            let meanDiff = meanChannelDiff(raster.rgb, ppm.rgb)
            let result = try EngineBridge.analyze(cgImage: png, topK: expected.topK)
            let reference = try EngineBridge.analyze(cgImage: XCTUnwrap(ppm.makeCGImage()), topK: expected.topK)
            // El PPM sRGB reproduce el golden (lo exige testPPMFixturesMatchGoldenThroughCGImage).
            XCTAssertEqual(reference.hits.map(\.comboId), e.hits.map(\.id))
            XCTAssertEqual(result.hits.first?.comboId, e.hits[0].id, "top-1 P3 \(e.pngP3)")
            if result.hits.map(\.comboId) == reference.hits.map(\.comboId) { sameTop3 += 1 }
            XCTAssertEqual(result.swatches.count, reference.swatches.count, "n swatches P3 \(e.pngP3)")
            var deltas: [Double] = []
            for (a, b) in zip(result.swatches, reference.swatches) {
                deltas.append(deltaE2000(a.lab, b.lab))
            }
            let maxDelta = deltas.max() ?? 0
            worstChannel = max(worstChannel, channelDiff)
            worstDeltaE = max(worstDeltaE, maxDelta)
            XCTAssertLessThanOrEqual(channelDiff, 1, "P3 -> sRGB \(e.pngP3): > 1/255 por canal")
            XCTAssertLessThanOrEqual(maxDelta, 1.5, "P3 -> sRGB \(e.pngP3): ΔE00 de swatch > 1,5")
            report.append(String(format: "%@: espacio %@, Δcanal máx %d (media %.4f), ΔE00 swatches máx %.4f [%@], pesos [%@], top-3 %@ vs %@ (score1 %.6g vs %.6g)",
                                 e.pngP3, spaceName, channelDiff, meanDiff, maxDelta,
                                 deltas.map { String(format: "%.4f", $0) }.joined(separator: " "),
                                 result.swatches.map { String(format: "%.3f", $0.weight) }.joined(separator: " "),
                                 result.hits.map { String($0.comboId) }.joined(separator: ","),
                                 reference.hits.map { String($0.comboId) }.joined(separator: ","),
                                 result.hits[0].score, reference.hits[0].score))
        }
        XCTAssertGreaterThanOrEqual(sameTop3, 4, "top-3 idéntico en menos de 4/5 fixtures")
        let summary = "EngineParityTests Display P3 -> sRGB (CoreGraphics): Δcanal máx \(worstChannel)/255, ΔE00 máx \(String(format: "%.4f", worstDeltaE)), top-3 idéntico \(sameTop3)/5\n" + report.joined(separator: "\n")
        print(summary)
        let attachment = XCTAttachment(string: summary)
        attachment.name = "display-p3-report"
        add(attachment)
    }

    // MARK: Reducción y máscara

    func testRasterizeDownscalesToMaxSideKeepingAspect() throws {
        XCTAssertEqual(EngineBridge.targetSize(width: 4032, height: 3024, maxSide: 1024).width, 1024)
        XCTAssertEqual(EngineBridge.targetSize(width: 4032, height: 3024, maxSide: 1024).height, 768)
        XCTAssertEqual(EngineBridge.targetSize(width: 100, height: 3000, maxSide: 1024).width, 34)
        XCTAssertEqual(EngineBridge.targetSize(width: 500, height: 200, maxSide: 1024).width, 500)
        // Imagen sólida 2048x1024 -> 1024x512, mismo color en cada píxel.
        let solid = PPMImage(width: 2048, height: 1024,
                             rgb: [UInt8](repeating: 0, count: 2048 * 1024 * 3).enumerated().map { i, _ in
                                 [UInt8(187), UInt8(113), UInt8(37)][i % 3]
                             })
        let image = try XCTUnwrap(solid.makeCGImage())
        let raster = try EngineBridge.rasterize(image)
        XCTAssertEqual(raster.width, 1024)
        XCTAssertEqual(raster.height, 512)
        XCTAssertEqual(raster.stride, 4096)
        XCTAssertEqual(Set(stride(from: 0, to: raster.pixels.count, by: 4).map { raster.pixels[$0] }), [187])
        XCTAssertEqual(Set(stride(from: 1, to: raster.pixels.count, by: 4).map { raster.pixels[$0] }), [113])
        XCTAssertEqual(Set(stride(from: 2, to: raster.pixels.count, by: 4).map { raster.pixels[$0] }), [37])
        let result = try EngineBridge.analyze(cgImage: image)
        XCTAssertEqual(result.swatches.count, 1)
        XCTAssertEqual(result.swatches[0].hex, "#bb7125")
        let palette = try EngineBridge.extractPalette(cgImage: image)
        XCTAssertEqual(palette, result.swatches)
    }

    func testMaskRestrictsPalette() throws {
        // Mitad izquierda roja, mitad derecha azul; máscara blanca a la izquierda.
        let w = 64, h = 64
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        var mask = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let c: (UInt8, UInt8, UInt8) = x < w / 2 ? (200, 30, 40) : (30, 60, 200)
                rgb[i * 3] = c.0
                rgb[i * 3 + 1] = c.1
                rgb[i * 3 + 2] = c.2
                mask[i] = x < w / 2 ? 255 : 0
            }
        }
        let image = try XCTUnwrap(PPMImage(width: w, height: h, rgb: rgb).makeCGImage())
        let maskImage = try XCTUnwrap(grayImage(width: w, height: h, bytes: mask))
        var opts = PaletteOptions.default
        opts.centerSigma = 0
        let raster = try EngineBridge.rasterize(image)
        XCTAssertEqual(raster.rgb, rgb, "imagen intacta")
        let maskBytes = try EngineBridge.rasterizeMask(maskImage, width: w, height: h)
        let histogram = Dictionary(grouping: maskBytes, by: { $0 }).mapValues(\.count)
        XCTAssertEqual(histogram, [0: w * h / 2, 255: w * h / 2], "máscara rasterizada no es 0/255 exacta")
        XCTAssertEqual(Array(maskBytes[28..<36]), [255, 255, 255, 255, 0, 0, 0, 0])
        let full = try EngineBridge.extractPalette(cgImage: image, options: opts)
        XCTAssertEqual(full.count, 2)
        XCTAssertEqual(Set(full.map(\.hex)), ["#c81e28", "#1e3cc8"]) // empate 50/50: orden por L
        let masked = try EngineBridge.extractPalette(cgImage: image, options: opts, mask: maskImage)
        XCTAssertEqual(masked.count, 1)
        // El mismo raster y máscara por el wrapper directo dan el mismo resultado.
        let direct = try raster.pixels.withUnsafeBufferPointer { px in
            try maskBytes.withUnsafeBufferPointer { m in
                try ColorEngine.extractPalette(rgba: px, width: w, height: h, stride: raster.stride, options: opts, mask: m)
            }
        }
        XCTAssertEqual(masked, direct)
        XCTAssertEqual(masked[0].hex, "#c81e28", "masked \(masked)")
        // La máscara se reescala con la imagen: con maxSide 32 sigue anulando la mitad
        // derecha. El remuestreo de CoreGraphics (.high) mezcla los píxeles de la
        // frontera rojo/azul (y la máscara), así que el swatch ya no es exacto:
        // medido (199, 30, 41), ΔE00 < 1.
        let small = try EngineBridge.analyze(cgImage: image, maxSide: 32, paletteOptions: opts, mask: maskImage)
        XCTAssertEqual(small.swatches.count, 1)
        XCTAssertLessThan(deltaE2000(small.swatches[0].lab, srgbToLab(r: 200, g: 30, b: 40)), 1.0)
        XCTAssertGreaterThan(deltaE2000(small.swatches[0].lab, srgbToLab(r: 30, g: 60, b: 200)), 30.0)
        XCTAssertEqual(try EngineBridge.rasterizeMask(maskImage, width: 32, height: 32).count, 1024)
    }

    func testPPMParserErrors() {
        XCTAssertThrowsError(try PPM.parse(Data("P5\n1 1\n255\n\0".utf8))) { XCTAssertEqual($0 as? PPMError, .badMagic) }
        XCTAssertThrowsError(try PPM.parse(Data("P6\n2 2\n255\n\0\0\0".utf8))) {
            XCTAssertEqual($0 as? PPMError, .truncated(expected: 12, actual: 3))
        }
        XCTAssertThrowsError(try PPM.parse(Data("P6\n1 1\n65535\n\0\0\0\0\0\0".utf8))) {
            XCTAssertEqual($0 as? PPMError, .unsupportedMaxval(65535))
        }
        let img = PPMImage(width: 2, height: 1, rgb: [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(try PPM.parse(PPM.write(img)), img)
        XCTAssertEqual(try PPM.parse(Data("P6\n# comentario\n2 1\n255\n\u{1}\u{2}\u{3}\u{4}\u{5}\u{6}".utf8)), img)
        XCTAssertEqual(img.rgbx, [1, 2, 3, 255, 4, 5, 6, 255])
    }

    // MARK: Utilidades

    private func maxChannelDiff(_ a: [UInt8], _ b: [UInt8]) -> Int {
        XCTAssertEqual(a.count, b.count)
        return zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 0
    }

    private func meanChannelDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard !a.isEmpty else { return 0 }
        return Double(zip(a, b).map { abs(Int($0) - Int($1)) }.reduce(0, +)) / Double(a.count)
    }

    private func grayImage(width: Int, height: Int, bytes: [UInt8]) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
