// Lector/escritor PPM P6 (binario, maxval 255): el formato de las fixtures del
// harness (harness/golden/fixtures, `ce match foto.ppm`). Lo usan los tests de
// paridad y sirve para volcar exactamente los píxeles que vio el motor.
import Foundation
import CoreGraphics

struct PPMImage: Equatable, Sendable {
    let width: Int
    let height: Int
    /// width * height * 3 bytes RGB, sin stride.
    let rgb: [UInt8]

    init(width: Int, height: Int, rgb: [UInt8]) {
        self.width = width
        self.height = height
        self.rgb = rgb
    }

    /// Los mismos píxeles como RGBX (4 bytes por píxel, X = 255): el formato
    /// que `EngineBridge` entrega al motor (CE_RGBA8, alpha ignorada).
    var rgbx: [UInt8] {
        var out = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            out[i * 4] = rgb[i * 3]
            out[i * 4 + 1] = rgb[i * 3 + 1]
            out[i * 4 + 2] = rgb[i * 3 + 2]
        }
        return out
    }

    /// CGImage sRGB de 24 bits (sin alpha) con estos píxeles; nil si CoreGraphics falla.
    func makeCGImage() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(rgb) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                       bytesPerRow: width * 3, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

enum PPMError: Error, Equatable, Sendable {
    case badMagic
    case badHeader
    case unsupportedMaxval(Int)
    case truncated(expected: Int, actual: Int)
}

enum PPM {
    /// Parsea P6 con maxval 255. Admite comentarios `#` en la cabecera.
    static func parse(_ data: Data) throws -> PPMImage {
        let bytes = [UInt8](data)
        var pos = 0

        func skipSpaceAndComments() {
            while pos < bytes.count {
                let c = bytes[pos]
                if c == UInt8(ascii: "#") {
                    while pos < bytes.count, bytes[pos] != UInt8(ascii: "\n") { pos += 1 }
                } else if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                    pos += 1
                } else {
                    return
                }
            }
        }

        func token() -> String? {
            skipSpaceAndComments()
            let start = pos
            while pos < bytes.count, !(bytes[pos] == 0x20 || bytes[pos] == 0x09 || bytes[pos] == 0x0A || bytes[pos] == 0x0D) {
                pos += 1
            }
            return start < pos ? String(decoding: bytes[start..<pos], as: UTF8.self) : nil
        }

        guard token() == "P6" else { throw PPMError.badMagic }
        guard let w = token().flatMap(Int.init), let h = token().flatMap(Int.init),
              let maxval = token().flatMap(Int.init), w >= 1, h >= 1 else { throw PPMError.badHeader }
        guard maxval == 255 else { throw PPMError.unsupportedMaxval(maxval) }
        pos += 1 // un único byte de espacio tras maxval
        let expected = w * h * 3
        guard bytes.count - pos >= expected else {
            throw PPMError.truncated(expected: expected, actual: max(0, bytes.count - pos))
        }
        return PPMImage(width: w, height: h, rgb: Array(bytes[pos..<(pos + expected)]))
    }

    static func read(url: URL) throws -> PPMImage {
        try parse(Data(contentsOf: url))
    }

    /// Serializa a P6 (cabecera "P6\n<w> <h>\n255\n").
    static func write(_ image: PPMImage) -> Data {
        var data = Data("P6\n\(image.width) \(image.height)\n255\n".utf8)
        data.append(contentsOf: image.rgb)
        return data
    }
}
