// Acciones reales del «Estudio de exportación» del Jardín (DESIGN_SYSTEM.md §5.4):
// tarjeta compartible de la última cosecha (ShareCardRenderer, 1080 × 1350 PNG en tmp,
// entregada por ShareLink), copiar sus hex y exportar el diagnóstico (el mismo zip de
// Ajustes). Fotos de las cosechas: `ScanPhotoLoader` (almacén de fotos del análisis,
// carrete sin iCloud o copia de 256 px de las fotos votadas); sin red.
import SwiftUI
import UIKit
import ColorEngine

/// Fotos de las cosechas (miniaturas y tarjeta) con caché en memoria.
@MainActor
final class GardenPhotos: ObservableObject {
    /// Imágenes ya resueltas por clave «<scanId>@<lado>».
    @Published private(set) var images: [String: CGImage] = [:]
    private var misses: Set<String> = []
    /// Fotos fijadas en memoria (datos de ejemplo de DEBUG), por scan.
    private var pinned: [String: CGImage] = [:]

    init() {}

    func pin(_ image: CGImage, scanId: String) {
        pinned[scanId] = image
    }

    func cached(_ scan: ScanRecord, maxSide: Int) -> CGImage? {
        pinned[scan.id] ?? images[key(scan, maxSide)]
    }

    /// Carga (una vez) la foto del scan a `maxSide` px.
    func load(_ scan: ScanRecord, maxSide: Int) async -> CGImage? {
        if let image = cached(scan, maxSide: maxSide) { return image }
        let k = key(scan, maxSide)
        guard !misses.contains(k) else { return nil }
        let image = await Self.photo(for: scan, maxSide: maxSide)
        if let image {
            images[k] = image
        } else {
            misses.insert(k)
        }
        return image
    }

    private func key(_ scan: ScanRecord, _ maxSide: Int) -> String { "\(scan.id)@\(maxSide)" }

    /// Foto de un scan (almacén de fotos del análisis → carrete → copia de 256 px de las fotos
    /// votadas, `ScanPhotoLoader`), reducida a `maxSide` px para no retener fotos grandes.
    nonisolated static func photo(for scan: ScanRecord, maxSide: Int) async -> CGImage? {
        guard let image = await ScanPhotoLoader.image(for: scan, maxSide: maxSide) else { return nil }
        return await Task.detached(priority: .utility) { downscaled(image, maxSide: maxSide) }.value
    }

    /// Copia sRGB con el lado mayor ≤ `maxSide` (la misma imagen si ya cabe).
    nonisolated static func downscaled(_ image: CGImage, maxSide: Int) -> CGImage {
        guard max(image.width, image.height) > maxSide else { return image }
        let target = EngineBridge.targetSize(width: image.width, height: image.height, maxSide: maxSide)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: target.width, height: target.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
        return ctx.makeImage() ?? image
    }
}

enum GardenExport {
    enum ExportError: Error, LocalizedError {
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .renderFailed: "No se ha podido dibujar la tarjeta."
            }
        }
    }

    /// Tarjeta de un scan guardado (§5.5-6, `ShareCardRenderer`): foto, paleta con su peso y top-1.
    @MainActor
    static func card(for scan: ScanRecord, photo: CGImage?, dictionary: WadaDictionary) -> ShareCardView {
        ShareCardRenderer.card(for: scan, photo: photo, dictionary: dictionary, format: .post)
    }

    /// Dibuja la tarjeta (1080 × 1350 px) y la escribe como PNG en `directory`.
    @MainActor
    static func writeCard(for scan: ScanRecord, photo: CGImage?, dictionary: WadaDictionary,
                          directory: URL = FileManager.default.temporaryDirectory, now: Date = Date()) throws -> URL {
        guard let image = ShareCardRenderer.render(card(for: scan, photo: photo, dictionary: dictionary)),
              let data = image.pngData() else {
            throw ExportError.renderFailed
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(fileSlug(AppBrand.name))-tarjeta-\(Diagnostics.fileStamp(now)).png")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Hex de la paleta separados por espacios («#222524 #B49AA2 …»).
    static func hexList(_ scan: ScanRecord) -> String {
        DesignFormat.hexList(GardenText.palette(scan, dictionary: nil))
    }

    /// «Copiado #222524» / «Copiados 5 hex».
    static func copiedToast(count: Int, single: String? = nil) -> String {
        if count == 1, let single { return "Copiado \(single)" }
        return "Copiados \(count) hex"
    }

    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }

    /// «ChromaSol» → «chromasol».
    static func fileSlug(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
