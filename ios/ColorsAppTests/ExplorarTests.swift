// Búsqueda que heredó la Rejilla de Explorar: "Buscar por color" (hex exacto del
// diccionario -> ΔE00 0 y las combinaciones que lo contienen), conversión Color -> sRGB8,
// búsqueda por número (RejillaSearch), colecciones por tamaño y la extracción de paleta
// del motor sobre una imagen sintética (PaletteBars, que usan otras pantallas).
import XCTest
import SwiftUI
import ColorEngine
@testable import ColorsApp

final class ExplorarTests: XCTestCase {
    private func loadDictionary() throws -> WadaDictionary {
        try WadaDictionary.load(from: Bundle(for: AppDatabase.self))
    }

    func testNearestColorOfExactDictionaryHexIsZeroDeltaE() throws {
        let d = try loadDictionary()
        for color in d.colors {
            let match = try XCTUnwrap(ColorSearch.nearest(hex: color.hex), color.hex)
            XCTAssertEqual(match.index, color.index, "\(color.name) \(color.hex)")
            XCTAssertEqual(match.deltaE, 0, "\(color.name): ΔE00 debe ser exactamente 0")
            XCTAssertEqual(match.hex, color.hex)
            let lab = try XCTUnwrap(dictionaryColorLab(index: color.index))
            XCTAssertEqual(match.lab, lab, "\(color.name): mismo Lab que la caché del motor")
        }
    }

    func testCombosContainingNearestColor() throws {
        let d = try loadDictionary()
        // Isabella Color (#c5a56e, índice 50) forma parte de la combinación 12.
        let match = try XCTUnwrap(ColorSearch.nearest(hex: "#c5a56e"))
        XCTAssertEqual(match.index, 50)
        XCTAssertEqual(d.color(index: 50)?.name, "Isabella Color")
        let combos = d.combos(containingColor: match.index).map(\.id)
        XCTAssertTrue(combos.contains(12))
        XCTAssertEqual(combos, d.combinations.filter { $0.colors.contains(50) }.map(\.id))
        XCTAssertEqual(combos, combos.sorted())
        // Green Blue (#099197, índice 119): también en la 12.
        let green = try XCTUnwrap(ColorSearch.nearest(hex: "099197"))
        XCTAssertEqual(green.index, 119)
        XCTAssertTrue(d.combos(containingColor: 119).map(\.id).contains(12))
    }

    func testNearestColorOfPerturbedHexIsSmallButNonZero() throws {
        let match = try XCTUnwrap(ColorSearch.nearest(hex: "#c6a56e"))
        XCTAssertEqual(match.index, 50)
        XCTAssertGreaterThan(match.deltaE, 0)
        XCTAssertLessThan(match.deltaE, 1)
        XCTAssertNil(ColorSearch.nearest(hex: "#12"))
        XCTAssertNil(ColorSearch.nearest(hex: "zzzzzz"))
    }

    @MainActor
    func testSRGB8FromSwiftUIColor() throws {
        let rgb = try XCTUnwrap(ColorSearch.srgb8(from: Color(rgb8: 9, 145, 151)))
        XCTAssertEqual([rgb.r, rgb.g, rgb.b], [9, 145, 151])
        let white = try XCTUnwrap(ColorSearch.srgb8(from: Color(rgb8: 255, 255, 255)))
        XCTAssertEqual([white.r, white.g, white.b], [255, 255, 255])
        let black = try XCTUnwrap(ColorSearch.srgb8(from: Color(rgb8: 0, 0, 0)))
        XCTAssertEqual([black.r, black.g, black.b], [0, 0, 0])
    }

    func testNumberSearchParsing() {
        XCTAssertEqual(RejillaSearch.parseNumber("12", count: 348), 12)
        XCTAssertEqual(RejillaSearch.parseNumber(" 012 ", count: 348), 12)
        XCTAssertEqual(RejillaSearch.parseNumber("348", count: 348), 348)
        XCTAssertEqual(RejillaSearch.parseNumber("Nº 67", count: 348), 67)
        XCTAssertEqual(RejillaSearch.parseNumber("nº067", count: 348), 67)
        XCTAssertEqual(RejillaSearch.parseNumber("n.12", count: 348), 12)
        XCTAssertNil(RejillaSearch.parseNumber("0", count: 348))
        XCTAssertNil(RejillaSearch.parseNumber("349", count: 348))
        XCTAssertNil(RejillaSearch.parseNumber("doce", count: 348))
        XCTAssertNil(RejillaSearch.parseNumber("", count: 348))
        XCTAssertNil(RejillaSearch.parseNumber("1234", count: 348))
    }

    func testCollectionsCoverEveryCombination() throws {
        let d = try loadDictionary()
        let collections = d.collections
        XCTAssertEqual(collections.map(\.id), ["size:2", "size:3", "size:4"])
        XCTAssertEqual(Set(collections.flatMap(\.comboIds)), Set(1...348))
        XCTAssertEqual(comboSubtitle(try XCTUnwrap(d.combo(id: 12))), "2 colores")
        XCTAssertEqual(comboSubtitle(WadaCombo(id: 1, size: 3, colors: [0, 1, 2], collection: "Japón")), "3 colores · Japón")
    }

    @MainActor
    func testPaletteExtractionOnSyntheticImageHasNoMatch() throws {
        let d = try loadDictionary()
        let image = try XCTUnwrap(SyntheticImage.blocks(comboId: 12, dictionary: d))
        let swatches = try EngineBridge.extractPalette(cgImage: image)
        XCTAssertEqual(swatches.count, 2)
        XCTAssertEqual(swatches.map(\.weight).reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(Set(swatches.map(\.hex)), ["#c5a56e", "#099197"])
        let entries = PaletteBars.entries(from: swatches)
        XCTAssertEqual(entries.map(\.hex), swatches.map(\.hex))
        XCTAssertEqual(entries.map(\.id), [0, 1])
        let fromPalette = PaletteBars.entries(from: swatches.map(PaletteEntry.init(swatch:)))
        XCTAssertEqual(fromPalette.map(\.hex), entries.map(\.hex))
    }

    func testLegibleTextColorUsesEngineLightness() {
        XCTAssertEqual(legibleTextColor(r: 255, g: 255, b: 255), .black)
        XCTAssertEqual(legibleTextColor(r: 0, g: 0, b: 0), .white)
        XCTAssertEqual(legibleTextColor(r: 9, g: 145, b: 151), .white) // Green Blue, L ≈ 55
    }
}
