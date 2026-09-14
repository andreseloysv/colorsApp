// Tests XCTest del wrapper Swift: tres pares de Sharma (tolerancia 1e-4),
// blanco -> L = 100, y un round-trip básico. La batería completa (34 pares,
// golden files, round-trip exhaustivo) vive en engine/tests/test_math.c.
import XCTest
@testable import ColorEngine

final class ColorEngineTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(colorEngineVersion, "0.1.0")
    }

    func testSharmaPairs() {
        // Pares 1, 7 y 17 de Sharma, Wu y Dalal (2005).
        let cases: [(Lab, Lab, Double)] = [
            (Lab(L: 50.0000, a: 2.6772, b: -79.7751), Lab(L: 50.0000, a: 0.0000, b: -82.7485), 2.0425),
            (Lab(L: 50.0000, a: 0.0000, b: 0.0000), Lab(L: 50.0000, a: -1.0000, b: 2.0000), 2.3669),
            (Lab(L: 50.0000, a: 2.5000, b: 0.0000), Lab(L: 50.0000, a: 3.1736, b: 0.5854), 1.0000),
        ]
        for (x, y, expected) in cases {
            XCTAssertEqual(deltaE2000(x, y), expected, accuracy: 1e-4)
            XCTAssertEqual(deltaE2000(y, x), expected, accuracy: 1e-4)
        }
    }

    func testWhiteIsL100() {
        let w = srgbToLab(r: 255, g: 255, b: 255)
        XCTAssertEqual(w.L, 100.0, accuracy: 1e-9)
        XCTAssertEqual(w.a, 0.0, accuracy: 1e-9)
        XCTAssertEqual(w.b, 0.0, accuracy: 1e-9)
    }

    func testBlackIsZero() {
        let k = srgbToLab(r: 0, g: 0, b: 0)
        XCTAssertEqual(k.L, 0.0, accuracy: 1e-12)
        XCTAssertEqual(k.a, 0.0, accuracy: 1e-12)
        XCTAssertEqual(k.b, 0.0, accuracy: 1e-12)
    }

    func testRoundTrip() {
        let samples: [(UInt8, UInt8, UInt8)] = [(0, 0, 0), (255, 255, 255), (255, 0, 0), (12, 200, 77), (128, 128, 128)]
        for (r, g, b) in samples {
            let back = labToSrgb8(srgbToLab(r: r, g: g, b: b))
            XCTAssertEqual(back.r, r)
            XCTAssertEqual(back.g, g)
            XCTAssertEqual(back.b, b)
        }
    }

    func testDeltaEProperties() {
        let x = Lab(L: 41.5, a: 52.6, b: 26.9)
        let y = Lab(L: 60.0, a: -10.0, b: 5.0)
        XCTAssertEqual(deltaE2000(x, x), 0.0)
        XCTAssertEqual(deltaE2000(x, y), deltaE2000(y, x))
        XCTAssertGreaterThan(deltaE76(x, y), 0.0)
        XCTAssertLessThanOrEqual(deltaE2000(x, y, kL: 2, kC: 1, kH: 1), deltaE2000(x, y))
    }
}
