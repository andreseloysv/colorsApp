// Foto de cada análisis para el Feed, el Jardín y «Abrir en Extraer»
// (docs/design/DESIGN_SYSTEM.md §5.5-1). La tabla `scans` no guarda la foto: las de la
// cámara y las elegidas se copian aquí al analizarlas (ScanAnalyzer.run) como JPEG sRGB de
// lado ≤ 1080 px sin metadatos, en Application Support/ColorsApp/scan-photos/<scanId>.jpg.
// Las del carrete se piden a PhotoKit por `assetLocalId` (sin red ni diálogo de permiso).
// Nunca entran en el zip de diagnóstico (ese guarda sus propias copias de 256 px).
//
// Uso: `await ScanPhotoLoader.image(for: scan)` (almacén → carrete → copia de 256 px del
// diagnóstico) o `ScanPhotoStore.shared.image(scanId:)`.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct ScanPhotoStore: Sendable {
    let directory: URL

    /// Lado máximo guardado (px).
    static let maxSide = 1080
    static let jpegQuality = 0.86

    static let shared = ScanPhotoStore(
        directory: AppDatabase.defaultURL.deletingLastPathComponent().appendingPathComponent("scan-photos", isDirectory: true))

    init(directory: URL) {
        self.directory = directory
    }

    func url(scanId: String) -> URL {
        directory.appendingPathComponent("\(scanId).jpg")
    }

    func exists(scanId: String) -> Bool {
        FileManager.default.fileExists(atPath: url(scanId: scanId).path)
    }

    /// Guarda la foto (reducida a ≤ `maxSide`, sRGB, sin EXIF ni GPS).
    func save(_ image: CGImage, scanId: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.jpeg(from: image)
        try data.write(to: url(scanId: scanId), options: .atomic)
    }

    /// Foto guardada de un scan (nil si no existe o no se puede leer).
    func image(scanId: String) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url(scanId: scanId) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    func remove(scanId: String) {
        try? FileManager.default.removeItem(at: url(scanId: scanId))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// JPEG sRGB de lado ≤ `maxSide` sin metadatos.
    static func jpeg(from image: CGImage, maxSide: Int = maxSide) throws -> Data {
        let target = EngineBridge.targetSize(width: image.width, height: image.height, maxSide: maxSide)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: target.width, height: target.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ScanPhotoStoreError.encodingFailed }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
        guard let scaled = ctx.makeImage() else { throw ScanPhotoStoreError.encodingFailed }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ScanPhotoStoreError.encodingFailed
        }
        CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ScanPhotoStoreError.encodingFailed }
        return data as Data
    }
}

enum ScanPhotoStoreError: Error, Equatable, Sendable {
    case encodingFailed
}

/// Foto de un scan desde la mejor fuente disponible, sin red ni diálogos.
enum ScanPhotoLoader {
    /// 1) almacén de fotos del análisis, 2) carrete por `assetLocalId` (solo con acceso ya
    /// concedido), 3) copia de 256 px del diagnóstico (fotos votadas). nil si no hay ninguna.
    static func image(for scan: ScanRecord, store: ScanPhotoStore = .shared, maxSide: Int = ScanPhotoStore.maxSide,
                      feedbackImages: FeedbackImageStore = .shared) async -> CGImage? {
        let id = scan.id
        if let stored = await Task.detached(priority: .userInitiated, operation: { store.image(scanId: id) }).value {
            return stored
        }
        if let asset = scan.assetLocalId, let image = await PhotoLibraryImages.uprightImage(assetLocalId: asset, maxSide: maxSide) {
            return image
        }
        return await Task.detached(priority: .utility) { () -> CGImage? in
            guard let data = feedbackImages.data(scanId: id) else { return nil }
            return try? ImageLoading.cgImage(from: data)
        }.value
    }
}
