// Copias PNG sRGB de 256 px para el diagnóstico (PLAN §7.8: "mismos píxeles
// que vio el motor, ya convertidos por el CGContext sRGB; nunca HEIC"):
// (1) FeedbackImageStore guarda, al votar en Resultado, el raster que vio el
// motor reducido a 256 px y sus extras (máscaras de las variantes, JSON del
// recorte, label map y debug.json: DiagnosticsSubject), calculados con las
// personas que ya detectó Vision; (2) para scans del carrete sin copia local,
// PhotoLibraryImages la recupera por asset_local_id con PHImageManager si hay
// permiso de Fotos y sin red (isNetworkAccessAllowed = false) y recalcula el
// recorte (Vision + motor) sobre esa imagen.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Photos
import UIKit
import ColorEngine
import SubjectKit

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

    /// Guarda los extras como `<scan_id>.<sufijo>` junto al PNG.
    func save(extras: [DiagnosticsSubject.Extra], scanId: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for extra in extras {
            try extra.data.write(to: directory.appendingPathComponent("\(scanId).\(extra.suffix)"), options: .atomic)
        }
    }

    /// Extras guardados de un scan (todo `<scan_id>.*` salvo el PNG), por sufijo.
    func extras(scanId: String) -> [DiagnosticsSubject.Extra] {
        let prefix = "\(scanId)."
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) && $0 != "\(scanId).png" }.sorted().compactMap { name in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
            return DiagnosticsSubject.Extra(suffix: String(name.dropFirst(prefix.count)), data: data)
        }
    }

    /// PNG y extras de un scan; nil sin PNG.
    func attachment(scanId: String) -> Diagnostics.PhotoAttachment? {
        guard let png = data(scanId: scanId) else { return nil }
        return Diagnostics.PhotoAttachment(png: png, extras: extras(scanId: scanId))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

enum PhotoLibraryImages {
    /// PNG de 256 px de un asset del carrete y sus extras: la imagen se pide a
    /// 512 px, el recorte (Vision + motor, con el modo guardado en el scan o el de
    /// Ajustes) se calcula sobre ella y las máscaras se reescalan al PNG.
    static func attachment(assetLocalId: String, scan: ScanRecord,
                           fallbackOptions: SubjectOptions = SubjectSettings.default.subjectOptions) async -> Diagnostics.PhotoAttachment? {
        guard let image = await uprightImage(assetLocalId: assetLocalId, maxSide: 2 * DiagnosticsSubject.exportSide) else {
            return nil
        }
        var options = fallbackOptions
        if let raw = scan.subjectMode, let mode = SubjectMode(rawValue: raw) {
            options.mode = mode == .selectedPerson ? .largestPerson : mode
            options.selectedIndex = nil
        }
        if let raw = scan.regionMode, let region = RegionMode(rawValue: raw) { options.region = region }
        if let skin = scan.adaptiveSkin { options.adaptiveSkin = skin }
        if scan.subjectMode == SubjectMode.selectedPerson.rawValue, let index = scan.personIndex {
            options.mode = .selectedPerson
            options.selectedIndex = index
        }
        let opts = options
        let scanId = scan.id
        return await Task.detached(priority: .utility) { () -> Diagnostics.PhotoAttachment? in
            guard let png = try? PNGCoding.srgbPNG(from: image, maxSide: DiagnosticsSubject.exportSide) else { return nil }
            guard let analysis = try? ScanAnalyzer.analyze(image: image, subject: opts),
                  let extras = try? DiagnosticsSubject.extras(.init(scanId: scanId, analysis: analysis, origin: "export"))
            else {
                return Diagnostics.PhotoAttachment(png: png)
            }
            return Diagnostics.PhotoAttachment(png: png, extras: extras)
        }.value
    }

    /// PNG sRGB de `maxSide` px de un asset del carrete; nil sin permiso, sin asset
    /// o sin datos locales (nunca descarga de iCloud).
    static func srgbPNG(assetLocalId: String, maxSide: Int = 256) async -> Data? {
        guard let image = await uprightImage(assetLocalId: assetLocalId, maxSide: maxSide) else { return nil }
        return try? PNGCoding.srgbPNG(from: image, maxSide: maxSide)
    }

    /// CGImage vertical ≤ `maxSide` px de un asset (nil sin permiso, sin asset o solo en iCloud).
    static func uprightImage(assetLocalId: String, maxSide: Int) async -> CGImage? {
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
        return await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            var resumed = false
            PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFit,
                                                  options: options) { image, _ in
                guard !resumed else { return }
                resumed = true
                guard let image, let cg = ImageLoading.upright(image, maxSide: maxSide) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: cg)
            }
        }
    }
}
