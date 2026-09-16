// Regresión del caso real del usuario (2026-09-15): camiseta negra + pantalón rosa
// palo. Solo se usan los colores hex de la paleta que extrajo la app (con sus
// proporciones), nunca la foto. Con la hipótesis de iluminante del motor ganaba
// Nº 067 (Olympic Blue + Dark Tyrian Blue); desde ADR-009 el motor POR DEFECTO ya no
// la usa (y la app usa el motor por defecto), así que no puede ganar una combinación azul.
import XCTest
import CoreGraphics
import ColorEngine
@testable import ColorsApp

final class MatchPolicyTests: XCTestCase {
    /// Paleta del caso: (hex, ancho de franja sobre 1080 px).
    private let stripes: [(UInt8, UInt8, UInt8, Int)] = [
        (0x22, 0x25, 0x24, 425), (0xb4, 0x9a, 0xa2, 243), (0x91, 0x7a, 0x7f, 172),
        (0xd5, 0xb8, 0xc0, 146), (0x6b, 0x5a, 0x57, 94),
    ]

    private func stripesImage() throws -> CGImage {
        let w = 1080, h = 200
        var px = [UInt8](repeating: 255, count: w * h * 4)
        var x0 = 0
        for (r, g, b, width) in stripes {
            for y in 0..<h { for x in x0..<(x0 + width) {
                let i = (y * w + x) * 4
                px[i] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = 255
            } }
            x0 += width
        }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        return try XCTUnwrap(ctx.makeImage())
    }

    private func analyzeStripes(matchOptions: MatchOptions) throws -> AnalysisResult {
        let raster = try EngineBridge.rasterize(try stripesImage())
        var palette = PaletteOptions.default
        palette.centerSigma = 0
        return try EngineBridge.analyze(raster: raster, paletteOptions: palette, matchOptions: matchOptions, topK: 3)
    }

    /// La política de la app es el motor por defecto (appMatchOptions es un alias).
    func testAppPolicyIsEngineDefault() {
        XCTAssertEqual(EngineBridge.appMatchOptions, MatchOptions.default)
        XCTAssertFalse(MatchOptions.default.illuminantSearch)
        XCTAssertEqual(EngineBridge.appMatchOptions.exposureEVMax, 1.0)
    }

    /// Regresión: con el motor POR DEFECTO (y la app) rosa + negro nunca da la pareja azul.
    func testPinkAndBlackDoesNotBecomeBlue() throws {
        let engineDefault = try analyzeStripes(matchOptions: .default)
        XCTAssertNotEqual(engineDefault.hits.first?.comboId, 67)
        XCTAssertFalse(engineDefault.hits.map(\.comboId).contains(67))
        XCTAssertTrue([337, 27].contains(engineDefault.hits.first?.comboId ?? -1),
                      "top-1 inesperado: \(engineDefault.hits.map(\.comboId))")
        let app = try analyzeStripes(matchOptions: EngineBridge.appMatchOptions)
        XCTAssertEqual(app, engineDefault)
    }

    /// Documenta el fallo de la hipótesis de iluminante (sigue disponible como opción):
    /// con illuminantSearch = true sale Nº 067. Si algún día cambia, revisar ADR-009.
    func testIlluminantHypothesisStillPicks067() throws {
        var illuminant = MatchOptions.default
        illuminant.illuminantSearch = true
        let result = try analyzeStripes(matchOptions: illuminant)
        XCTAssertEqual(result.hits.first?.comboId, 67, "con illuminantSearch = true ya no sale Nº 067: revisar ADR-009")
    }
}
