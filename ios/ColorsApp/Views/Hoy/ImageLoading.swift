// Carga de imágenes para el motor: CGImageSource con la orientación EXIF
// aplicada y reducción al lado mayor de 1024 px (PLAN §7.2), y conversión de
// un UIImage de la cámara a un CGImage vertical en sRGB. CoreGraphics hace la
// conversión de espacio de color al dibujar en el contexto sRGB de EngineBridge.
import Foundation
import CoreGraphics
import ImageIO
import UIKit

enum ImageLoadingError: Error, Equatable, Sendable, LocalizedError {
    case unreadable
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable: "No se ha podido leer la imagen (formato no reconocido o fichero dañado)."
        case .empty: "La imagen no tiene píxeles."
        }
    }
}

enum ImageLoading {
    static let maxPixelSize = EngineBridge.defaultMaxSide

    /// Decodifica HEIC/JPEG/PNG... con la orientación EXIF aplicada, ≤ `maxPixelSize` en el lado mayor.
    static func cgImage(from data: Data, maxPixelSize: Int = maxPixelSize) throws -> CGImage {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageLoadingError.unreadable
        }
        return try cgImage(from: source, maxPixelSize: maxPixelSize)
    }

    static func cgImage(from url: URL, maxPixelSize: Int = maxPixelSize) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ImageLoadingError.unreadable }
        return try cgImage(from: source, maxPixelSize: maxPixelSize)
    }

    private static func cgImage(from source: CGImageSource, maxPixelSize: Int) throws -> CGImage {
        guard CGImageSourceGetCount(source) > 0 else { throw ImageLoadingError.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // orientación EXIF aplicada
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageLoadingError.unreadable
        }
        guard image.width > 0, image.height > 0 else { throw ImageLoadingError.empty }
        return image
    }

    /// UIImage (cámara, PHImageManager) -> CGImage vertical (orientación aplicada),
    /// ≤ `maxSide` px, dibujado en sRGB. nil si el UIImage está vacío.
    static func upright(_ image: UIImage, maxSide: Int = maxPixelSize) -> CGImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        if image.imageOrientation == .up, image.scale == 1, let cg = image.cgImage, max(cg.width, cg.height) <= maxSide {
            return cg
        }
        let pixelWidth = Int((size.width * image.scale).rounded())
        let pixelHeight = Int((size.height * image.scale).rounded())
        let target = EngineBridge.targetSize(width: pixelWidth, height: pixelHeight, maxSide: maxSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target.width, height: target.height), format: format)
        let drawn = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
        }
        return drawn.cgImage
    }
}
