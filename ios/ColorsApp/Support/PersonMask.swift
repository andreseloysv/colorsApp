// Máscara de persona con Vision (PLAN §7.2): VNGeneratePersonSegmentationRequest
// (.balanced) sobre la imagen vertical, convertida a una máscara de 8 bits del
// tamaño del raster que ve el motor (width * height bytes, sin stride: el
// formato de ce_image.mask; 0 anula el píxel, 255 peso pleno). Si Vision falla
// o casi no hay persona, ScanAnalyzer sigue sin máscara y lo anota.
import Foundation
import CoreGraphics
import CoreVideo
import Vision

enum PersonMaskError: Error, Equatable, Sendable {
    case noObservation
    case unsupportedPixelFormat(OSType)
    case bufferUnavailable
    case imageUnavailable
}

enum PersonMask {
    /// Fracción mínima de píxeles "persona" (>= 128) para aplicar la máscara:
    /// por debajo, el motor vería casi nada y devolvería el color medio.
    static let minCoverage = 0.02

    struct Mask: Equatable, Sendable {
        let bytes: [UInt8]
        let width: Int
        let height: Int
        /// Fracción de píxeles con valor >= 128.
        let coverage: Double

        var isUsable: Bool { coverage >= PersonMask.minCoverage }
    }

    /// Máscara de `width` x `height` bytes para `image` (vertical, ≤ 1024 px).
    /// Síncrono y sin estado: llamar fuera del MainActor.
    static func compute(for image: CGImage, width: Int, height: Int,
                        quality: VNGeneratePersonSegmentationRequest.QualityLevel = .balanced) throws -> Mask {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = quality
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else { throw PersonMaskError.noObservation }
        let gray = try grayImage(from: observation.pixelBuffer)
        let bytes = try EngineBridge.rasterizeMask(gray, width: width, height: height)
        return Mask(bytes: bytes, width: width, height: height, coverage: coverage(of: bytes))
    }

    static func coverage(of bytes: [UInt8]) -> Double {
        guard !bytes.isEmpty else { return 0 }
        var n = 0
        for b in bytes where b >= 128 { n += 1 }
        return Double(n) / Double(bytes.count)
    }

    /// CGImage en gris de 8 bits con el contenido del pixel buffer de Vision
    /// (OneComponent8 o OneComponent32Float, 0...1 -> 0...255).
    static func grayImage(from buffer: CVPixelBuffer) throws -> CGImage {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw PersonMaskError.bufferUnavailable
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
                    packed[y * width + x] = UInt8(max(0, min(255, (row[x] * 255).rounded())))
                }
            }
        default:
            throw PersonMaskError.unsupportedPixelFormat(format)
        }
        guard let provider = CGDataProvider(data: Data(packed) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                                  bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent) else {
            throw PersonMaskError.imageUnavailable
        }
        return image
    }
}
