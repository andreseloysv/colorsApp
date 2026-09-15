// Copias PNG sRGB de 256 px para el diagnóstico (PLAN §7.8: "mismos píxeles
// que vio el motor, ya convertidos por el CGContext sRGB; nunca HEIC"):
// (1) FeedbackImageStore guarda, al votar en Resultado, el raster que vio el
// motor reducido a 256 px; (2) para scans del carrete sin copia local,
// PhotoLibraryImages la recupera por asset_local_id con PHImageManager si hay
// permiso de Fotos y sin red (isNetworkAccessAllowed = false).
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Photos
import UIKit

enum PNGCoding {
    /// PNG de un CGImage (con el perfil del CGImage: sRGB si viene de EngineBridge).
    static func png(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// CGImage sRGB (RGBX, 32 bits) con los píxeles de un raster de EngineBridge.
    static func cgImage(from raster: EngineBridge.Raster) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(raster.pixels) as CFData) else { return nil }
        return CGImage(width: raster.width, height: raster.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: raster.stride, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// PNG sRGB de `image` reducido a `maxSide` px (256: el formato del set dorado, PLAN §6 L4).
    static func srgbPNG(from image: CGImage, maxSide: Int = 256) throws -> Data {
        let raster = try EngineBridge.rasterize(image, maxSide: maxSide)
        guard let cg = cgImage(from: raster), let png = png(from: cg) else {
            throw EngineBridgeError.contextUnavailable
        }
        return png
    }
}

/// Copias locales de las fotos con veredicto: Application Support/ColorsApp/feedback-images/<scan_id>.png.
struct FeedbackImageStore: Sendable {
    let directory: URL

    static let shared = FeedbackImageStore(
        directory: AppDatabase.defaultURL.deletingLastPathComponent()
            .appendingPathComponent("feedback-images", isDirectory: true))

    init(directory: URL) {
        self.directory = directory
    }

    func url(scanId: String) -> URL {
        directory.appendingPathComponent("\(scanId).png")
    }

    func save(png: Data, scanId: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: url(scanId: scanId), options: .atomic)
    }

    func data(scanId: String) -> Data? {
        try? Data(contentsOf: url(scanId: scanId))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

enum PhotoLibraryImages {
    /// PNG sRGB de `maxSide` px de un asset del carrete; nil sin permiso, sin asset
    /// o sin datos locales (nunca descarga de iCloud).
    static func srgbPNG(assetLocalId: String, maxSide: Int = 256) async -> Data? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalId], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isSynchronous = false
        let target = CGSize(width: maxSide * 2, height: maxSide * 2)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            var resumed = false
            PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFit,
                                                  options: options) { image, _ in
                guard !resumed else { return }
                resumed = true
                guard let image, let cg = ImageLoading.upright(image, maxSide: maxSide),
                      let png = try? PNGCoding.srgbPNG(from: cg, maxSide: maxSide) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: png)
            }
        }
    }
}
