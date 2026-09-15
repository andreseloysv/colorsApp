// Diccionario de Wada en el bundle de la app: recuentos 159/348, dict_version
// igual a la del motor, nombres ("Nº 001" hasta que haya curados), colecciones
// por tamaño y coherencia color a color con el motor C.
import XCTest
import SwiftUI
import UIKit
import ColorEngine
@testable import ColorsApp

final class DictionaryTests: XCTestCase {
    private func loadDictionary() throws -> WadaDictionary {
        try WadaDictionary.load(from: Bundle(for: AppDatabase.self))
    }

    func testCounts() throws {
        let d = try loadDictionary()
        XCTAssertEqual(d.colors.count, 159)
        XCTAssertEqual(d.combinations.count, 348)
        XCTAssertEqual(d.schema, 1)
        XCTAssertEqual(d.colors.count, dictionaryColorCount)
        XCTAssertEqual(d.combinations.count, dictionaryComboCount)
        // Ids 1...348 sin huecos, tamaños 2/3/4 = 120/120/108.
        XCTAssertEqual(d.combinations.map(\.id), Array(1...348))
        let bySize = Dictionary(grouping: d.combinations, by: \.size).mapValues(\.count)
        XCTAssertEqual(bySize, [2: 120, 3: 120, 4: 108])
        XCTAssertEqual(d.colors.map(\.index), Array(0..<159))
    }

    func testDictVersionMatchesEngine() throws {
        let d = try loadDictionary()
        XCTAssertEqual(d.dictVersion, dictionaryVersion)
        XCTAssertEqual(WadaDictionary.engineDictVersion, dictionaryVersion)
        XCTAssertTrue(d.matchesEngine)
        XCTAssertNoThrow(try d.checkEngineVersion())
        XCTAssertEqual(d.dictVersion.count, 12)
    }

    func testVersionMismatchIsDetected() throws {
        let d = try loadDictionary()
        let other = WadaDictionary(schema: d.schema, source: d.source, dictVersion: "000000000000", status: d.status,
                                   colors: d.colors, combinations: d.combinations, names: [])
        XCTAssertFalse(other.matchesEngine)
        XCTAssertThrowsError(try other.checkEngineVersion()) { error in
            XCTAssertEqual(error as? WadaDictionaryError,
                           .versionMismatch(bundle: "000000000000", engine: dictionaryVersion))
        }
    }

    func testColorsAndCombosAgreeWithEngine() throws {
        let d = try loadDictionary()
        for c in d.colors {
            let rgb = try XCTUnwrap(dictionaryColorRGB(index: c.index))
            XCTAssertEqual([Int(rgb.r), Int(rgb.g), Int(rgb.b)], c.rgb, "color \(c.index) \(c.name)")
            XCTAssertEqual(dictionaryColorName(index: c.index), c.name)
            XCTAssertEqual(c.hex, String(format: "#%02x%02x%02x", c.rgb[0], c.rgb[1], c.rgb[2]))
        }
        for combo in d.combinations {
            XCTAssertEqual(dictionaryCombo(id: combo.id), combo.colors, "combo \(combo.id)")
            XCTAssertEqual(combo.colors.count, combo.size)
            XCTAssertEqual(d.colors(of: combo).count, combo.size)
        }
        XCTAssertEqual(d.combo(id: 348)?.colors, [52, 106, 109, 151])
        XCTAssertNil(d.combo(id: 349))
        XCTAssertNil(d.color(index: 159))
        XCTAssertEqual(d.color(index: 0)?.name, "Hermosa Pink")
    }

    func testDisplayNameFallback() throws {
        let d = try loadDictionary()
        XCTAssertEqual(WadaDictionary.numberLabel(1), "Nº 001")
        XCTAssertEqual(d.displayName(id: 1), "Nº 001")
        XCTAssertEqual(d.displayName(id: 12), "Nº 012")
        XCTAssertEqual(d.displayName(id: 348), "Nº 348")
        XCTAssertNil(d.curatedName(id: 1))
        // names.es.json está en el bundle y tiene las 348 entradas (todas pending hoy).
        XCTAssertEqual(d.names.count, 348)
        XCTAssertEqual(d.names[12]?.status, "pending")
    }

    func testDisplayNameUsesAcceptedCuratedName() throws {
        let d = try loadDictionary()
        let names = [
            WadaName(id: 1, lang: "es", name: "Tejados de Lisboa", notes: "", status: "accepted"),
            WadaName(id: 2, lang: "es", name: "Propuesta sin aceptar", notes: "", status: "pending"),
            WadaName(id: 3, lang: "es", name: "   ", notes: "", status: "accepted"),
        ]
        let curated = WadaDictionary(schema: d.schema, source: d.source, dictVersion: d.dictVersion, status: d.status,
                                     colors: d.colors, combinations: d.combinations, names: names)
        XCTAssertEqual(curated.displayName(id: 1), "Tejados de Lisboa")
        XCTAssertEqual(curated.displayName(id: 2), "Nº 002")
        XCTAssertEqual(curated.displayName(id: 3), "Nº 003")
        XCTAssertEqual(curated.displayName(id: 4), "Nº 004")
    }

    func testCollectionsBySize() throws {
        let d = try loadDictionary()
        let collections = d.collections
        // Sin colecciones curadas todavía: solo las automáticas 2/3/4.
        XCTAssertEqual(collections.map(\.id), ["size:2", "size:3", "size:4"])
        XCTAssertEqual(collections.map { $0.comboIds.count }, [120, 120, 108])
        XCTAssertEqual(collections[0].title, "Combinaciones de 2 colores")
        XCTAssertEqual(Set(collections.flatMap(\.comboIds)).count, 348)
        // Colección curada sintética.
        let combos = d.combinations.map { c in
            WadaCombo(id: c.id, size: c.size, colors: c.colors, collection: c.id <= 3 ? "Japón" : nil)
        }
        let curated = WadaDictionary(schema: d.schema, source: d.source, dictVersion: d.dictVersion, status: d.status,
                                     colors: d.colors, combinations: combos, names: [])
        XCTAssertEqual(curated.collections.first?.id, "curated:Japón")
        XCTAssertEqual(curated.collections.first?.comboIds, [1, 2, 3])
        XCTAssertEqual(curated.collections.count, 4)
    }

    func testCombosContainingColor() throws {
        let d = try loadDictionary()
        let black = try XCTUnwrap(d.colors.first { $0.name == "Black" })
        let combos = d.combos(containingColor: black.index)
        XCTAssertEqual(combos.count, 23) // Black aparece en 23 combinaciones (make_fixtures.py)
        XCTAssertTrue(combos.allSatisfy { $0.colors.contains(black.index) })
    }

    func testDecodeWithoutNames() throws {
        let bundle = Bundle(for: AppDatabase.self)
        let url = try XCTUnwrap(bundle.url(forResource: "dictionary", withExtension: "json"))
        let d = try WadaDictionary.decode(dictionaryData: Data(contentsOf: url), namesData: nil)
        XCTAssertEqual(d.names.count, 0)
        XCTAssertEqual(d.displayName(id: 7), "Nº 007")
        XCTAssertNoThrow(try d.checkCounts())
    }

    func testColorFromHexAndRGB() throws {
        let c = try XCTUnwrap(parseHexRGB("#f9c1ce"))
        XCTAssertEqual([c.r, c.g, c.b], [249, 193, 206])
        XCTAssertNotNil(Color(hex: "F9C1CE"))
        XCTAssertNil(Color(hex: "#zz0000"))
        XCTAssertNil(Color(hex: "#fff"))
        XCTAssertNotNil(UIColor(hex: "#000000"))
        let d = try loadDictionary()
        let ui = UIColor(wada: try XCTUnwrap(d.color(index: 0)))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(ui.getRed(&r, green: &g, blue: &b, alpha: &a))
        XCTAssertEqual(Int((r * 255).rounded()), 249)
        XCTAssertEqual(Int((g * 255).rounded()), 193)
        XCTAssertEqual(Int((b * 255).rounded()), 206)
    }
}
