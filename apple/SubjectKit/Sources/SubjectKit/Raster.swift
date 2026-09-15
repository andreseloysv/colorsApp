// Raster que ve el motor y reescalado de máscaras de Vision. Copia la forma de
// ios/ColorsApp/Engine/EngineBridge.swift (rasterize / rasterizeMask) y de
// ios/ColorsApp/Support/PersonMask.swift (grayImage) para que visionmask y los
// tests produzcan exactamente los píxeles de la app: CGContext sRGB de 8 bits
// `noneSkipLast` (RGBX), lado mayor <= maxSide, fondo blanco, interpolación
// alta solo si hay reescalado.
import CoreGraphics
import CoreVideo
import Foundation

/// Píxeles RGBX sRGB de 8 bits tal como los recibe el motor.
public struct SubjectRaster: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Bytes por fila (= width * 4).
    public let stride: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, stride: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.stride = stride
        self.pixels = pixels
    }

    /// Lado mayor por defecto (el de la app).
    public static let defaultMaxSide = 1024

    /// Solo los bytes RGB (para escribir el PPM).
    public var rgb: [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let s = y * stride + x * 4
                let d = (y * width + x) * 3
                out[d] = pixels[s]
                out[d + 1] = pixels[s + 1]
                out[d + 2] = pixels[s + 2]
            }
        }
        return out
    }

    /// Dimensiones tras reducir a `maxSide` conservando el aspecto (nunca amplía).
    public static func targetSize(width: Int, height: Int, maxSide: Int) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard maxSide >= 1, longest > maxSide else { return (max(1, width), max(1, height)) }
        let scale = Double(maxSide) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    /// Dibuja `image` en un CGContext sRGB RGBX de `targetSize(maxSide:)` píxeles.
    public static func rasterize(_ image: CGImage, maxSide: Int = defaultMaxSide) throws -> SubjectRaster {
        guard image.width >= 1, image.height >= 1 else {
            throw SubjectError.invalidDimensions(width: image.width, height: image.height)
        }
        let size = targetSize(width: image.width, height: image.height, maxSide: maxSide)
        let stride = size.width * 4
        var pixels = [UInt8](repeating: 0, count: stride * size.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw SubjectError.graphicsUnavailable }
        let ok: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: size.width, height: size.height,
                                      bitsPerComponent: 8, bytesPerRow: stride, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            let scaled = size.width != image.width || size.height != image.height
            ctx.interpolationQuality = scaled ? .high : .none
            ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1]) ?? CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            return true
        }
        guard ok else { throw SubjectError.graphicsUnavailable }
        return SubjectRaster(width: size.width, height: size.height, stride: stride, pixels: pixels)
    }
}

/// Máscaras de Vision -> bytes del raster.
public enum MaskRaster {
    /// Rasteriza una máscara (CGImage en gris) a `width` x `height` bytes 0...255
    /// sin stride (formato de `ce_image.mask`), como EngineBridge.rasterizeMask.
    public static func rasterizeMask(_ mask: CGImage, width: Int, height: Int) throws -> [UInt8] {
        guard width >= 1, height >= 1 else { throw SubjectError.invalidDimensions(width: width, height: height) }
        var bytes = [UInt8](repeating: 0, count: width * height)
        let space = CGColorSpaceCreateDeviceGray()
        let ok: Bool = bytes.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width, space: space,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { throw SubjectError.graphicsUnavailable }
        return bytes
    }

    /// Máscara de un CVPixelBuffer de Vision (OneComponent8 u OneComponent32Float
    /// 0...1) reescalada al raster.
    public static func rasterizeMask(_ buffer: CVPixelBuffer, width: Int, height: Int) throws -> [UInt8] {
        try rasterizeMask(grayImage(from: buffer), width: width, height: height)
    }

    /// CGImage en gris de 8 bits con el contenido del pixel buffer (copia de
    /// PersonMask.grayImage de la app).
    public static func grayImage(from buffer: CVPixelBuffer) throws -> CGImage {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw SubjectError.graphicsUnavailable
        }
        var packed = [UInt8](repeating: 0, count: width * height)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        switch format {
        case kCVPixelFormatType_OneComponent8:
            for y in 0..<height {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width { packed[y * width + x] = row[x] }
            }
        case kCVPixelFormatType_OneComponent32Float:
            for y in 0..<height {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
                for x in 0..<width {
                    let v = row[x].isFinite ? row[x] : 0
                    packed[y * width + x] = UInt8(max(0, min(255, (v * 255).rounded())))
                }
            }
        default:
            throw SubjectError.unsupportedPixelFormat(format)
        }
        guard let provider = CGDataProvider(data: Data(packed) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                                  bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent) else {
            throw SubjectError.graphicsUnavailable
        }
        return image
    }
}

/// Lectura y escritura de PNM binario (P6 RGB / P5 gris, maxval 255): el
/// formato de entrada de la CLI `ce`.
public enum PNM {
    public static func ppm(width: Int, height: Int, rgb: [UInt8]) -> Data {
        var d = Data("P6\n\(width) \(height)\n255\n".utf8)
        d.append(contentsOf: rgb.prefix(width * height * 3))
        return d
    }

    public static func pgm(width: Int, height: Int, gray: [UInt8]) -> Data {
        var d = Data("P5\n\(width) \(height)\n255\n".utf8)
        d.append(contentsOf: gray.prefix(width * height))
        return d
    }

    /// Lee un P5/P6 con maxval 255 (cabecera sin comentarios, como la escribe `ce`
    /// y este módulo). Devuelve (ancho, alto, canales, bytes) o nil.
    public static func read(_ data: Data) -> (width: Int, height: Int, channels: Int, bytes: [UInt8])? {
        let bytes = [UInt8](data)
        var pos = 0
        func token() -> String? {
            while pos < bytes.count, [0x20, 0x0a, 0x0d, 0x09].contains(bytes[pos]) { pos += 1 }
            let start = pos
            while pos < bytes.count, ![0x20, 0x0a, 0x0d, 0x09].contains(bytes[pos]) { pos += 1 }
            return pos > start ? String(decoding: bytes[start..<pos], as: UTF8.self) : nil
        }
        guard let magic = token(), magic == "P5" || magic == "P6",
              let w = token().flatMap({ Int($0) }), let h = token().flatMap({ Int($0) }),
              let maxval = token().flatMap({ Int($0) }), maxval == 255, w >= 1, h >= 1 else { return nil }
        pos += 1
        let channels = magic == "P6" ? 3 : 1
        let n = w * h * channels
        guard bytes.count - pos >= n else { return nil }
        return (w, h, channels, Array(bytes[pos..<(pos + n)]))
    }
}
