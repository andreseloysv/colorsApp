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

// MARK: - Capa 2 (paleta)

final class PaletteTests: XCTestCase {
    /// Imagen RGBA sintética de tres bandas horizontales 50/30/20 con relleno
    /// de stride y alpha basura (deben ignorarse).
    private func threeBlockImage(width: Int, height: Int, stride: Int) -> [UInt8] {
        let colors: [(UInt8, UInt8, UInt8)] = [(200, 30, 40), (30, 60, 200), (40, 180, 60)]
        var px = [UInt8](repeating: 0x5A, count: stride * height)
        for y in 0..<height {
            let block = y < height / 2 ? 0 : (y < (height * 8) / 10 ? 1 : 2)
            for x in 0..<width {
                let o = y * stride + x * 4
                px[o] = colors[block].0
                px[o + 1] = colors[block].1
                px[o + 2] = colors[block].2
                px[o + 3] = UInt8((x * 7 + y) & 0xFF)
            }
        }
        return px
    }

    func testContextSizeBudget() {
        XCTAssertLessThanOrEqual(colorEngineContextSize, 2 * 1024 * 1024)
        XCTAssertEqual(colorEngineContextSize % 16, 0)
    }

    func testDefaultOptions() {
        let o = PaletteOptions.default
        XCTAssertEqual(o.kInit, 6)
        XCTAssertEqual(o.maxIters, 20)
        XCTAssertEqual(o.maxColors, 5)
        XCTAssertEqual(o.maxSide, 256)
        XCTAssertEqual(o.centerSigma, 0.35)
        XCTAssertEqual(o.mergeDeltaE, 5.0)
        XCTAssertEqual(o.minWeight, 0.05)
        XCTAssertFalse(o.skinRule)
        XCTAssertEqual(o.mergeLightDeltaE, 0.0) // experimento de fusión de sombras: apagado
        // Ida y vuelta por el struct C con el campo nuevo.
        var shades = o
        shades.mergeLightDeltaE = 6.0
        XCTAssertEqual(PaletteOptions(shades.cValue), shades)
        XCTAssertEqual(PaletteOptions(kInit: 6, maxIters: 20, maxColors: 5, maxSide: 256, centerSigma: 0.35,
                                      mergeDeltaE: 5.0, minWeight: 0.05, skinRule: false), o)
    }

    func testThreeBlocksUniform() throws {
        let width = 120, height = 120, stride = width * 4 + 8
        let px = threeBlockImage(width: width, height: height, stride: stride)
        var opts = PaletteOptions.default
        opts.centerSigma = 0 // uniforme: pesos = fracción de área
        let palette = try px.withUnsafeBufferPointer { buf in
            try extractPalette(rgba: buf, width: width, height: height, stride: stride, options: opts)
        }
        XCTAssertEqual(palette.count, 3)
        let expected: [(Lab, Double)] = [
            (srgbToLab(r: 200, g: 30, b: 40), 0.5),
            (srgbToLab(r: 30, g: 60, b: 200), 0.3),
            (srgbToLab(r: 40, g: 180, b: 60), 0.2),
        ]
        for (sw, (lab, weight)) in zip(palette, expected) {
            XCTAssertLessThan(deltaE2000(sw.lab, lab), 1.0)
            XCTAssertEqual(sw.weight, weight, accuracy: 0.02)
        }
        XCTAssertEqual(palette.map(\.weight).reduce(0, +), 1.0, accuracy: 1e-12)
        XCTAssertEqual(palette[0].hex, "#c81e28")
        XCTAssertEqual(palette[1].r, 30)
        // Con peso al centro el conjunto de colores se mantiene (ΔE00 < 1).
        let centered = try px.withUnsafeBufferPointer { buf in
            try extractPalette(rgba: buf, width: width, height: height, stride: stride)
        }
        XCTAssertEqual(centered.count, 3)
        for (lab, _) in expected {
            XCTAssertLessThan(centered.map { deltaE2000($0.lab, lab) }.min()!, 1.0)
        }
    }

    func testErrors() throws {
        let px = [UInt8](repeating: 0, count: 16)
        try px.withUnsafeBufferPointer { buf in
            XCTAssertThrowsError(try extractPalette(rgba: buf, width: 4, height: 4, stride: 16)) { error in
                XCTAssertEqual(error as? ColorEngineError, .bufferTooSmall(required: 64, actual: 16))
            }
            XCTAssertThrowsError(try extractPalette(rgba: buf, width: 0, height: 1, stride: 4))
            XCTAssertThrowsError(try extractPalette(rgba: buf, width: 2, height: 2, stride: 4))
            // stride fuera del rango de Int32: error, nunca trap (el buffer de 16 bytes pasa el
            // check de tamaño porque height == 1).
            XCTAssertThrowsError(try extractPalette(rgba: buf, width: 1, height: 1, stride: Int(Int32.max) + 1)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -4)) // CE_ERR_STRIDE
            }
            var opts = PaletteOptions.default
            opts.kInit = 0
            XCTAssertThrowsError(try extractPalette(rgba: buf, width: 2, height: 2, stride: 8, options: opts)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -6))
            }
        }
    }

    func testNearestDictionaryColor() {
        let lab = srgbToLab(r: 249, g: 193, b: 206) // color 0, Hermosa Pink
        let (index, de) = nearestDictionaryColor(lab)
        XCTAssertEqual(index, 0)
        XCTAssertEqual(de, 0.0)
    }
}

// MARK: - Capa 3 (match)

final class MatchTests: XCTestCase {
    /// Imagen RGBA 120x120 (stride con relleno y alpha basura) de bandas
    /// verticales con proporciones iguales de los colores sRGB8 exactos de la
    /// combinación `id`.
    private func comboImage(id: Int, width: Int, height: Int, stride: Int) -> [UInt8]? {
        guard let colors = dictionaryCombo(id: id) else { return nil }
        let rgb = colors.compactMap { dictionaryColorRGB(index: $0) }
        guard rgb.count == colors.count else { return nil }
        var px = [UInt8](repeating: 0x5A, count: stride * height)
        for y in 0..<height {
            for x in 0..<width {
                let band = (x * rgb.count) / width
                let o = y * stride + x * 4
                px[o] = rgb[band].r
                px[o + 1] = rgb[band].g
                px[o + 2] = rgb[band].b
                px[o + 3] = UInt8((x * 7 + y) & 0xFF)
            }
        }
        return px
    }

    func testDefaultMatchOptions() {
        let m = MatchOptions.default
        XCTAssertEqual(m.kL, 1.0)
        XCTAssertEqual(m.kC, 1.0)
        XCTAssertEqual(m.kH, 1.0)
        XCTAssertEqual(m.coverageLambda, 1.0)
        XCTAssertEqual(m.ambiguousGap, 1.0)
        XCTAssertEqual(m.exposureEVMax, 1.0)
        XCTAssertEqual(m.exposurePenalty, 2.0)
        // ADR-009 (2026-09-15): hipótesis de iluminante desactivada por defecto (también en el init).
        XCTAssertFalse(m.illuminantSearch)
        XCTAssertEqual(m.illuminantPenalty, 2.0)
        XCTAssertEqual(MatchOptions(kL: 1, kC: 1, kH: 1, coverageLambda: 1, ambiguousGap: 1), m)
        // Ida y vuelta por el struct C.
        var v0 = m
        v0.exposureEVMax = 0
        v0.illuminantSearch = false
        XCTAssertEqual(MatchOptions(v0.cValue), v0)
        XCTAssertEqual(colorEngineMaxHits, 10)
    }

    /// Caso real rosa palo + negro (CONTEXT §11), solo hex y pesos: con las opciones por
    /// defecto Nº 337 puntúa mejor que Nº 067 (azul); con la hipótesis de iluminante, al revés.
    func testPinkAndBlackPaletteDefaultsAvoidBlue() throws {
        let hexes: [(UInt8, UInt8, UInt8, Double)] = [
            (0x22, 0x25, 0x24, 0.394), (0xb4, 0x9a, 0xa2, 0.227), (0x91, 0x7a, 0x7e, 0.162),
            (0xd5, 0xb8, 0xc0, 0.134), (0x6b, 0x5a, 0x57, 0.083),
        ]
        let swatches = hexes.map { Swatch(lab: srgbToLab(r: $0.0, g: $0.1, b: $0.2), r: $0.0, g: $0.1, b: $0.2, weight: $0.3) }
        let pink337 = try explainMatch(swatches: swatches, comboId: 337)
        let blue067 = try explainMatch(swatches: swatches, comboId: 67)
        XCTAssertLessThan(pink337.score, blue067.score)
        XCTAssertEqual(blue067.illuminant, -1)
        var illum = MatchOptions.default
        illum.illuminantSearch = true
        let blueIllum = try explainMatch(swatches: swatches, options: illum, comboId: 67)
        let pinkIllum = try explainMatch(swatches: swatches, options: illum, comboId: 337)
        XCTAssertLessThan(blueIllum.score, pinkIllum.score)
        XCTAssertEqual(blueIllum.illuminant, 0) // CE_ILL_A: "compensa" una luz de tungsteno inexistente
    }

    func testDictionaryAccessors() {
        XCTAssertEqual(dictionaryComboCount, 348)
        XCTAssertEqual(dictionaryColorCount, 159)
        XCTAssertEqual(dictionaryVersion.count, 12)
        XCTAssertNil(dictionaryCombo(id: 0))
        XCTAssertNil(dictionaryCombo(id: 349))
        XCTAssertNil(dictionaryColorRGB(index: -1))
        XCTAssertNil(dictionaryColorRGB(index: 159))
        XCTAssertNil(dictionaryColorLab(index: 159))
        XCTAssertNil(dictionaryColorName(index: 159))
        guard let combo = dictionaryCombo(id: 12) else { return XCTFail("combo 12") }
        XCTAssertTrue(combo.count >= 2 && combo.count <= 7)
        XCTAssertEqual(combo, combo.sorted())
        for index in combo {
            guard let rgb = dictionaryColorRGB(index: index), let lab = dictionaryColorLab(index: index) else {
                return XCTFail("color \(index)")
            }
            // Mismo Lab que la conversión de la foto (bit a bit).
            XCTAssertEqual(lab, srgbToLab(r: rgb.r, g: rgb.g, b: rgb.b))
            XCTAssertFalse((dictionaryColorName(index: index) ?? "").isEmpty)
        }
    }

    func testAnalyzeExactComboImage() throws {
        let id = 12
        let width = 120, height = 120, stride = width * 4 + 8
        guard let px = comboImage(id: id, width: width, height: height, stride: stride),
              let colors = dictionaryCombo(id: id) else { return XCTFail("fixture") }
        var po = PaletteOptions.default
        po.centerSigma = 0 // uniforme: pesos = fracción de área exacta
        let r = try px.withUnsafeBufferPointer { buf in
            try analyze(rgba: buf, width: width, height: height, stride: stride, paletteOptions: po, topK: 3)
        }
        XCTAssertEqual(r.swatches.count, colors.count)
        XCTAssertEqual(r.swatches.map(\.weight).reduce(0, +), 1.0, accuracy: 1e-12)
        XCTAssertEqual(r.hits.count, 3)
        XCTAssertEqual(r.hits[0].comboId, id)
        XCTAssertLessThan(r.hits[0].score, 1e-9) // exacto salvo el redondeo de la media de Lloyd
        XCTAssertLessThan(r.hits[0].score, r.hits[1].score)
        XCTAssertLessThanOrEqual(r.hits[1].score, r.hits[2].score)
        XCTAssertFalse(r.ambiguous)
        // Cada swatch es un color de la combinación (ΔE00 ~ 0).
        for sw in r.swatches {
            let best = colors.compactMap { dictionaryColorLab(index: $0) }.map { deltaE2000($0, sw.lab) }.min()!
            XCTAssertLessThan(best, 1e-9)
        }
        // Determinismo run-a-run: resultado y hash idénticos.
        let r2 = try px.withUnsafeBufferPointer { buf in
            try analyze(rgba: buf, width: width, height: height, stride: stride, paletteOptions: po, topK: 3)
        }
        XCTAssertEqual(r, r2)
        XCTAssertEqual(r.hash, r2.hash)
        // topK 10: prefijo idéntico, otro hash (cubre los K hits devueltos).
        let r10 = try px.withUnsafeBufferPointer { buf in
            try analyze(rgba: buf, width: width, height: height, stride: stride, paletteOptions: po, topK: 10)
        }
        XCTAssertEqual(r10.hits.count, 10)
        XCTAssertEqual(Array(r10.hits.prefix(3)), r.hits)
        XCTAssertNotEqual(r10.hash, r.hash)
        // Con peso al centro (defecto) el top-1 se mantiene.
        let centered = try px.withUnsafeBufferPointer { buf in
            try analyze(rgba: buf, width: width, height: height, stride: stride)
        }
        XCTAssertEqual(centered.hits[0].comboId, id)
        // kL = 2 (textiles) y λ = 0 también aciertan sobre bloques exactos.
        let textiles = MatchOptions(kL: 2, kC: 1, kH: 1, coverageLambda: 0, ambiguousGap: 1)
        let rt = try px.withUnsafeBufferPointer { buf in
            try analyze(rgba: buf, width: width, height: height, stride: stride, paletteOptions: po,
                        matchOptions: textiles, topK: 1)
        }
        XCTAssertEqual(rt.hits.count, 1)
        XCTAssertEqual(rt.hits[0].comboId, id)
        XCTAssertFalse(rt.ambiguous)
    }

    func testAnalyzeErrors() throws {
        let px = [UInt8](repeating: 0, count: 64)
        try px.withUnsafeBufferPointer { buf in
            XCTAssertThrowsError(try analyze(rgba: buf, width: 4, height: 4, stride: 16, topK: 0)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -1)) // CE_ERR_ARG
            }
            XCTAssertThrowsError(try analyze(rgba: buf, width: 4, height: 4, stride: 16, topK: 11)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -1))
            }
            XCTAssertThrowsError(try analyze(rgba: buf, width: 8, height: 8, stride: 32)) { error in
                XCTAssertEqual(error as? ColorEngineError, .bufferTooSmall(required: 256, actual: 64))
            }
            XCTAssertThrowsError(try analyze(rgba: buf, width: 0, height: 4, stride: 16))
            var mo = MatchOptions.default
            mo.coverageLambda = -1
            XCTAssertThrowsError(try analyze(rgba: buf, width: 4, height: 4, stride: 16, matchOptions: mo)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -6)) // CE_ERR_OPTS
            }
            mo = MatchOptions.default
            mo.kL = .nan
            XCTAssertThrowsError(try analyze(rgba: buf, width: 4, height: 4, stride: 16, matchOptions: mo)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -6))
            }
            var po = PaletteOptions.default
            po.maxColors = 9
            XCTAssertThrowsError(try analyze(rgba: buf, width: 4, height: 4, stride: 16, paletteOptions: po)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -6))
            }
            // Caso válido mínimo: imagen negra 4x4 -> 1 swatch, 3 hits ordenados.
            let r = try analyze(rgba: buf, width: 4, height: 4, stride: 16)
            XCTAssertEqual(r.swatches.count, 1)
            XCTAssertEqual(r.hits.count, 3)
            XCTAssertLessThanOrEqual(r.hits[0].score, r.hits[1].score)
        }
    }
}

// MARK: - Máscara opcional (fase 6: EngineBridge de la app la usa para la
// segmentación de persona)

final class MaskTests: XCTestCase {
    /// Dos bandas horizontales 50/50: rojo arriba, azul abajo.
    private func twoBlockImage(width: Int, height: Int, stride: Int) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: stride * height)
        for y in 0..<height {
            let c: (UInt8, UInt8, UInt8) = y < height / 2 ? (200, 30, 40) : (30, 60, 200)
            for x in 0..<width {
                let o = y * stride + x * 4
                px[o] = c.0
                px[o + 1] = c.1
                px[o + 2] = c.2
                px[o + 3] = 255
            }
        }
        return px
    }

    func testMaskDropsMaskedPixels() throws {
        let width = 64, height = 64, stride = width * 4
        let px = twoBlockImage(width: width, height: height, stride: stride)
        var opts = PaletteOptions.default
        opts.centerSigma = 0
        // Máscara: solo la mitad superior (roja) cuenta.
        var mask = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height / 2) { mask[i] = 255 }
        let palette = try px.withUnsafeBufferPointer { buf in
            try mask.withUnsafeBufferPointer { m in
                try extractPalette(rgba: buf, width: width, height: height, stride: stride, options: opts, mask: m)
            }
        }
        XCTAssertEqual(palette.count, 1)
        XCTAssertEqual(palette[0].hex, "#c81e28")
        XCTAssertEqual(palette[0].weight, 1.0, accuracy: 1e-12)
        // Sin máscara: dos swatches 50/50.
        let full = try px.withUnsafeBufferPointer { buf in
            try extractPalette(rgba: buf, width: width, height: height, stride: stride, options: opts)
        }
        XCTAssertEqual(full.count, 2)
        // analyze con la misma máscara devuelve la misma paleta.
        let r = try px.withUnsafeBufferPointer { buf in
            try mask.withUnsafeBufferPointer { m in
                try analyze(rgba: buf, width: width, height: height, stride: stride, paletteOptions: opts, mask: m)
            }
        }
        XCTAssertEqual(r.swatches, palette)
        XCTAssertEqual(r.hits.count, 3)
    }

    /// Mitades izquierda/derecha (la máscara varía dentro de cada fila): el
    /// swatch enmascarado debe ser exacto igual que con mitades arriba/abajo.
    func testMaskLeftRightHalvesExact() throws {
        let width = 64, height = 64, stride = width * 4
        var px = [UInt8](repeating: 0, count: stride * height)
        var mask = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let c: (UInt8, UInt8, UInt8) = x < width / 2 ? (200, 30, 40) : (30, 60, 200)
                let o = y * stride + x * 4
                px[o] = c.0
                px[o + 1] = c.1
                px[o + 2] = c.2
                px[o + 3] = 255
                mask[y * width + x] = x < width / 2 ? 255 : 0
            }
        }
        var opts = PaletteOptions.default
        opts.centerSigma = 0
        let palette = try px.withUnsafeBufferPointer { buf in
            try mask.withUnsafeBufferPointer { m in
                try extractPalette(rgba: buf, width: width, height: height, stride: stride, options: opts, mask: m)
            }
        }
        XCTAssertEqual(palette.count, 1)
        XCTAssertEqual(palette[0].hex, "#c81e28")
        XCTAssertEqual(palette[0].weight, 1.0, accuracy: 1e-12)
        XCTAssertEqual(palette[0].lab, srgbToLab(r: 200, g: 30, b: 40))
        // Con sigma por defecto (0,35) el swatch sigue siendo exactamente rojo.
        let centered = try px.withUnsafeBufferPointer { buf in
            try mask.withUnsafeBufferPointer { m in
                try extractPalette(rgba: buf, width: width, height: height, stride: stride, mask: m)
            }
        }
        XCTAssertEqual(centered.count, 1)
        XCTAssertEqual(centered[0].hex, "#c81e28")
    }

    func testMaskAllZeroGivesMeanColor() throws {
        let width = 32, height = 32, stride = width * 4
        let px = twoBlockImage(width: width, height: height, stride: stride)
        let mask = [UInt8](repeating: 0, count: width * height)
        let palette = try px.withUnsafeBufferPointer { buf in
            try mask.withUnsafeBufferPointer { m in
                try extractPalette(rgba: buf, width: width, height: height, stride: stride, mask: m)
            }
        }
        XCTAssertEqual(palette.count, 1)
        XCTAssertEqual(palette[0].weight, 1.0, accuracy: 1e-12)
        // Media (sin ponderar) de (200,30,40) y (30,60,200): (115, 45, 120).
        XCTAssertEqual(Int(palette[0].r), 115)
        XCTAssertEqual(Int(palette[0].g), 45)
        XCTAssertEqual(Int(palette[0].b), 120)
    }

    func testMaskTooSmallThrows() throws {
        let width = 8, height = 8, stride = width * 4
        let px = twoBlockImage(width: width, height: height, stride: stride)
        let mask = [UInt8](repeating: 255, count: width * height - 1)
        try px.withUnsafeBufferPointer { buf in
            try mask.withUnsafeBufferPointer { m in
                XCTAssertThrowsError(try extractPalette(rgba: buf, width: width, height: height, stride: stride, mask: m)) { error in
                    XCTAssertEqual(error as? ColorEngineError, .maskTooSmall(required: 64, actual: 63))
                }
                XCTAssertThrowsError(try analyze(rgba: buf, width: width, height: height, stride: stride, mask: m)) { error in
                    XCTAssertEqual(error as? ColorEngineError, .maskTooSmall(required: 64, actual: 63))
                }
            }
        }
    }
}

// MARK: - Paleta por prenda

final class GarmentTests: XCTestCase {
    /// Camiseta negra en dos tonos arriba y pantalón rosa en tres tonos (luz 50 %, media
    /// sombra 30 %, sombra 20 %: los de la foto real del tranvía) abajo, en bandas verticales.
    private func pantsImage(width: Int, height: Int) -> (px: [UInt8], regions: [UInt8]) {
        var px = [UInt8](repeating: 255, count: width * 4 * height)
        var regions = [UInt8](repeating: 0, count: width * height)
        let top: [(UInt8, UInt8, UInt8)] = [(0x2b, 0x2c, 0x2c), (0x20, 0x21, 0x21)]
        let bottom: [(UInt8, UInt8, UInt8)] = [(0xd5, 0xb8, 0xc0), (0xb4, 0x9a, 0xa2), (0x91, 0x7a, 0x7e)]
        for y in 0..<height {
            let upper = y < height * 2 / 5
            for x in 0..<width {
                let c = upper ? top[x < width * 3 / 5 ? 0 : 1]
                              : bottom[x < width / 2 ? 0 : (x < width * 4 / 5 ? 1 : 2)]
                let o = (y * width + x) * 4
                px[o] = c.0
                px[o + 1] = c.1
                px[o + 2] = c.2
                regions[y * width + x] = upper ? 1 : 2
            }
        }
        return (px, regions)
    }

    private func frontPose() -> Pose {
        var pose = Pose()
        let pts: [(Double, Double, Double)] = [
            (100, 50, 0.9), (100, 90, 0.9), (140, 90, 0.9), (60, 90, 0.9), (152.25, 150.5, 0.8), (47.75, 150.5, 0.8),
            (158.5, 205.25, 0.7), (41.5, 205.25, 0.7), (124, 210, 0.9), (76, 210, 0.9), (126.25, 290.75, 0.8),
            (73.75, 290.75, 0.8), (128.5, 370.5, 0.8), (71.5, 370.5, 0.8), (100, 210, 0.9),
        ]
        for (i, p) in pts.enumerated() {
            pose.joints[i] = Keypoint(x: p.0, y: p.1, confidence: p.2)
        }
        return pose
    }

    func testDefaultGarmentOptions() {
        let o = GarmentOptions.default
        XCTAssertEqual(o.shadeKL, 3.0)
        XCTAssertEqual(o.shadeMergeDeltaE, 6.5)
        XCTAssertEqual(o.litLowPercentile, 0.75)
        XCTAssertEqual(o.litHighPercentile, 0.95)
        XCTAssertEqual(o.secondaryMinShare, 0.25)
        XCTAssertEqual(o.maxColorsPerRegion, 2)
        XCTAssertEqual(garmentMaxRegions, 2)
    }

    func testPinkPantsOneColorPerGarment() throws {
        let width = 100, height = 200
        let (px, regions) = pantsImage(width: width, height: height)
        let garments = try px.withUnsafeBufferPointer { buf in
            try regions.withUnsafeBufferPointer { r in
                try extractGarments(rgba: buf, width: width, height: height, stride: width * 4, regions: r)
            }
        }
        XCTAssertEqual(garments.count, 2, "\(garments)")
        XCTAssertEqual(Set(garments.map(\.region)), [.upper, .lower])
        let lower = try XCTUnwrap(garments.first { $0.region == .lower })
        let upper = try XCTUnwrap(garments.first { $0.region == .upper })
        XCTAssertLessThan(deltaE2000(lower.swatch.lab, srgbToLab(r: 0xdd, g: 0xc0, b: 0xc8)), 4.0)
        XCTAssertLessThan(deltaE2000(upper.swatch.lab, srgbToLab(r: 0x2b, g: 0x2c, b: 0x2c)), 6.0)
        XCTAssertGreaterThanOrEqual(lower.mergedClusterCount, 2)
        XCTAssertEqual(garments.reduce(0) { $0 + $1.swatch.weight }, 1.0, accuracy: 1e-12)
        // La paleta clásica reparte el pantalón en varios tonos.
        let classic = try px.withUnsafeBufferPointer { buf in
            try extractPalette(rgba: buf, width: width, height: height, stride: width * 4)
        }
        XCTAssertGreaterThanOrEqual(classic.count, 3)
        // Sin mapa: una región (.none).
        let single = try px.withUnsafeBufferPointer { buf in
            try extractGarments(rgba: buf, width: width, height: height, stride: width * 4)
        }
        XCTAssertTrue(single.allSatisfy { $0.region == .none })
        XCTAssertEqual(garmentHash(garments), garmentHash(garments))
        XCTAssertNotEqual(garmentHash(garments), garmentHash(single))
    }

    func testAnalyzeGarmentsAndDebugLayers() throws {
        let width = 100, height = 200
        let (px, regions) = pantsImage(width: width, height: height)
        let (result, layers, extracted) = try px.withUnsafeBufferPointer { buf in
            try regions.withUnsafeBufferPointer { r in
                (try analyzeGarments(rgba: buf, width: width, height: height, stride: width * 4, topK: 5, regions: r),
                 try garmentDebugLayers(rgba: buf, width: width, height: height, stride: width * 4, topK: 5, regions: r),
                 try extractGarments(rgba: buf, width: width, height: height, stride: width * 4, regions: r))
            }
        }
        XCTAssertEqual(result.garments, extracted)
        XCTAssertEqual(result.analysis.swatches, extracted.map(\.swatch))
        XCTAssertEqual(result.analysis.hits.count, 5)
        XCTAssertEqual(layers.result, result)
        XCTAssertEqual(layers.layers.analysis, result.analysis)
        XCTAssertEqual(layers.layers.explanations.count, 5)
        let n = layers.layers.debug.reducedWidth * layers.layers.debug.reducedHeight
        XCTAssertEqual(layers.garmentMap.count, n)
        XCTAssertEqual(layers.regionMap.count, n)
        for i in 0..<n where layers.garmentMap[i] != paletteLabelNone {
            let g = Int(layers.garmentMap[i])
            XCTAssertLessThan(g, extracted.count)
            XCTAssertEqual(Int(layers.regionMap[i]), extracted[g].region.rawValue)
        }
        // El mismo match que analyze con los swatches de prenda.
        XCTAssertEqual(layers.layers.explanations.map(\.comboId), result.analysis.hits.map(\.comboId))
    }

    func testGarmentRegionsMatchClothingSupport() throws {
        let width = 200, height = 400
        let person = [UInt8](repeating: 255, count: width * height)
        let pose = frontPose()
        let (regions, pixels) = try garmentRegions(pose: pose, personMask: person, width: width, height: height)
        let (cloth, clothPixels) = try clothingRegions(pose: pose, mask: person, width: width, height: height)
        XCTAssertEqual(pixels, clothPixels)
        XCTAssertEqual(regions.map { $0 != 0 }, cloth.map { $0 != 0 })
        XCTAssertEqual(regions[150 * width + 100], 1)
        XCTAssertEqual(regions[250 * width + 125], 2)
        XCTAssertEqual(regions[60 * width + 100], 0)
        var noHips = pose
        noHips[.leftHip] = .missing
        noHips[.rightHip] = .missing
        XCTAssertThrowsError(try garmentRegions(pose: noHips, personMask: person, width: width, height: height)) { error in
            XCTAssertEqual(error as? ColorEngineError, .poseMissing)
        }
        XCTAssertThrowsError(try garmentRegions(pose: pose, personMask: [1, 2, 3], width: width, height: height)) { error in
            XCTAssertEqual(error as? ColorEngineError, .maskTooSmall(required: width * height, actual: 3))
        }
    }

    func testGarmentErrors() throws {
        let width = 16, height = 16
        let (px, regions) = pantsImage(width: width, height: height)
        try px.withUnsafeBufferPointer { buf in
            try regions.withUnsafeBufferPointer { r in
                XCTAssertThrowsError(try extractGarments(rgba: buf, width: width, height: height, stride: width * 4,
                                                         regions: r, regionCount: 3)) { error in
                    XCTAssertEqual(error as? ColorEngineError, .engine(code: -1))
                }
                var bad = GarmentOptions.default
                bad.litLowPercentile = 0.99 // > litHighPercentile por defecto (0,95)
                XCTAssertThrowsError(try extractGarments(rgba: buf, width: width, height: height, stride: width * 4,
                                                         garmentOptions: bad, regions: r)) { error in
                    XCTAssertEqual(error as? ColorEngineError, .engine(code: -6))
                }
                XCTAssertThrowsError(try analyzeGarments(rgba: buf, width: width, height: height, stride: width * 4,
                                                         topK: 0, regions: r)) { error in
                    XCTAssertEqual(error as? ColorEngineError, .engine(code: -1))
                }
            }
            let short = [UInt8](repeating: 1, count: width * height - 1)
            try short.withUnsafeBufferPointer { r in
                XCTAssertThrowsError(try extractGarments(rgba: buf, width: width, height: height, stride: width * 4,
                                                         regions: r)) { error in
                    XCTAssertEqual(error as? ColorEngineError, .maskTooSmall(required: width * height, actual: width * height - 1))
                }
            }
        }
    }
}
