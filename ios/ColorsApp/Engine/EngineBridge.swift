// Puente CGImage -> motor C. Rasteriza cualquier CGImage (HEIC/JPEG/PNG del
// carrete, cámara, PhotosPicker) en un CGContext sRGB de 8 bits, formato
// RGBX (`noneSkipLast`, 4 bytes por píxel, alpha ignorada por el motor),
// reducido a `maxSide` (1024 por defecto) conservando el aspecto, y llama a
// `ColorEngine.analyze` / `extractPalette`. Nada de lógica de color en Swift.
//
// Conversión de espacio de color: al dibujar en un contexto sRGB, CoreGraphics
// convierte los píxeles del espacio de la imagen (Display P3 en las fotos del
// iPhone, ICC embebido en los PNG) a sRGB con ColorSync. Es la conversión
// esperada por PLAN §7 y la mide `EngineParityTests` (PNG Display P3 vs PPM
// sRGB del mismo fixture). Una imagen ya sRGB dibujada a escala 1:1 llega al
// motor byte a byte (también lo comprueba el test).
//
// Todas las funciones son síncronas, puras y sin estado compartido: se pueden
// llamar desde `Task.detached` (CGImage es Sendable) con un `ce_ctx` por
// llamada, como exige el motor (un contexto por tarea).
import Foundation
import CoreGraphics
import ColorEngine

enum EngineBridgeError: Error, Equatable, Sendable {
    /// CoreGraphics no pudo crear el contexto o el espacio de color.
    case contextUnavailable
    /// El CGImage tiene 0 píxeles.
    case emptyImage
}

enum EngineBridge {
    /// Lado mayor tras la reducción (PLAN §7: <= 1024 px antes del motor, que
    /// a su vez reduce a 256 por defecto).
    static let defaultMaxSide = 1024

    /// Píxeles RGBX sRGB de 8 bits tal como los recibe el motor.
    struct Raster: Equatable, Sendable {
        let width: Int
        let height: Int
        /// Bytes por fila (= width * 4).
        let stride: Int
        let pixels: [UInt8]

        /// Solo los bytes RGB (para comparar con un PPM o volcarlo).
        var rgb: [UInt8] {
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

        var ppm: PPMImage { PPMImage(width: width, height: height, rgb: rgb) }
    }

    /// Dimensiones tras reducir a `maxSide` conservando el aspecto (sin
    /// ampliar nunca; mínimo 1 px por lado).
    static func targetSize(width: Int, height: Int, maxSide: Int) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard maxSide >= 1, longest > maxSide else { return (max(1, width), max(1, height)) }
        let scale = Double(maxSide) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    /// Dibuja `image` en un CGContext sRGB RGBX de `targetSize(maxSide:)` píxeles.
    /// Fondo blanco (las zonas transparentes de un PNG quedan blancas, no negras).
    static func rasterize(_ image: CGImage, maxSide: Int = defaultMaxSide) throws -> Raster {
        guard image.width >= 1, image.height >= 1 else { throw EngineBridgeError.emptyImage }
        let size = targetSize(width: image.width, height: image.height, maxSide: maxSide)
        let stride = size.width * 4
        var pixels = [UInt8](repeating: 0, count: stride * size.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw EngineBridgeError.contextUnavailable }
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
        guard ok else { throw EngineBridgeError.contextUnavailable }
        return Raster(width: size.width, height: size.height, stride: stride, pixels: pixels)
    }

    /// Rasteriza una máscara (cualquier CGImage: la salida de Vision como
    /// CGImage, o una imagen en escala de grises) a `width` x `height` bytes
    /// de luminancia 0..255, empaquetados sin stride: el formato de `ce_image.mask`.
    static func rasterizeMask(_ mask: CGImage, width: Int, height: Int) throws -> [UInt8] {
        guard width >= 1, height >= 1 else { throw EngineBridgeError.emptyImage }
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
        guard ok else { throw EngineBridgeError.contextUnavailable }
        return bytes
    }

    /// Paleta + match (ce_analyze) de un CGImage. `mask` opcional (se reescala
    /// a la imagen rasterizada; 0 anula el píxel, 255 peso pleno). `topK` 1...10.
    /// Síncrono: llamar desde `Task.detached` para no bloquear la UI.
    static func analyze(cgImage: CGImage, maxSide: Int = defaultMaxSide,
                        paletteOptions: PaletteOptions = .default, matchOptions: MatchOptions = .default,
                        topK: Int = 3, mask: CGImage? = nil) throws -> AnalysisResult {
        let raster = try rasterize(cgImage, maxSide: maxSide)
        let maskBytes = try mask.map { try rasterizeMask($0, width: raster.width, height: raster.height) }
        return try analyze(raster: raster, paletteOptions: paletteOptions, matchOptions: matchOptions,
                           topK: topK, mask: maskBytes)
    }

    /// Variante sobre un raster ya calculado (p. ej. para volcar los píxeles y
    /// analizar sin rasterizar dos veces). `mask`: width * height bytes o nil.
    static func analyze(raster: Raster, paletteOptions: PaletteOptions = .default,
                        matchOptions: MatchOptions = .default, topK: Int = 3,
                        mask: [UInt8]? = nil) throws -> AnalysisResult {
        try raster.pixels.withUnsafeBufferPointer { px in
            try withOptionalMask(mask) { m in
                try ColorEngine.analyze(rgba: px, width: raster.width, height: raster.height, stride: raster.stride,
                                        paletteOptions: paletteOptions, matchOptions: matchOptions, topK: topK, mask: m)
            }
        }
    }

    /// `analyze` + capas de depuración del motor (imagen reducida, peso por píxel,
    /// swatch y cluster por píxel, clusters descartados/fusionados y la
    /// explicación de cada hit) en un único `ce_analyze` y un único `ce_ctx`:
    /// `analysis` es idéntico (hash incluido) al de `analyze` con los mismos
    /// argumentos. Lo usa el inspector de capas de Resultado.
    /// Opciones de match que usa la app (no las del motor por defecto).
    /// La hipótesis de iluminante queda DESACTIVADA: las fotos del iPhone ya llegan
    /// con balance de blancos y "compensar" una luz cálida inexistente convertía
    /// rosas en azules (caso real del usuario, 2026-09-15: pantalón rosa palo +
    /// camiseta negra -> Nº 067 azul claro + azul marino por la hipótesis A).
    /// La hipótesis de exposición se mantiene (solo cambia la luminosidad).
    static var appMatchOptions: MatchOptions {
        var o = MatchOptions.default
        o.illuminantSearch = false
        return o
    }

    static func analyzeWithLayers(raster: Raster, paletteOptions: PaletteOptions = .default,
                                  matchOptions: MatchOptions = .default, topK: Int = 3,
                                  mask: [UInt8]? = nil) throws -> PaletteDebugLayers {
        try raster.pixels.withUnsafeBufferPointer { px in
            try withOptionalMask(mask) { m in
                try ColorEngine.paletteDebugLayers(rgba: px, width: raster.width, height: raster.height,
                                                   stride: raster.stride, paletteOptions: paletteOptions,
                                                   matchOptions: matchOptions, topK: topK, mask: m)
            }
        }
    }

    /// Solo la paleta (ce_palette_extract), sin match: "Extraer de una foto" en Explorar.
    static func extractPalette(cgImage: CGImage, maxSide: Int = defaultMaxSide,
                               options: PaletteOptions = .default, mask: CGImage? = nil) throws -> [Swatch] {
        let raster = try rasterize(cgImage, maxSide: maxSide)
        let maskBytes = try mask.map { try rasterizeMask($0, width: raster.width, height: raster.height) }
        return try raster.pixels.withUnsafeBufferPointer { px in
            try withOptionalMask(maskBytes) { m in
                try ColorEngine.extractPalette(rgba: px, width: raster.width, height: raster.height,
                                               stride: raster.stride, options: options, mask: m)
            }
        }
    }

    /// `analyze` en un `Task.detached` (prioridad userInitiated): la forma
    /// recomendada de llamarlo desde una vista.
    static func analyzeDetached(cgImage: CGImage, maxSide: Int = defaultMaxSide,
                                paletteOptions: PaletteOptions = .default, matchOptions: MatchOptions = .default,
                                topK: Int = 3, mask: CGImage? = nil) async throws -> AnalysisResult {
        try await Task.detached(priority: .userInitiated) {
            try analyze(cgImage: cgImage, maxSide: maxSide, paletteOptions: paletteOptions,
                        matchOptions: matchOptions, topK: topK, mask: mask)
        }.value
    }

    private static func withOptionalMask<T>(_ mask: [UInt8]?, _ body: (UnsafeBufferPointer<UInt8>?) throws -> T) rethrows -> T {
        if let mask {
            return try mask.withUnsafeBufferPointer { try body($0) }
        }
        return try body(nil)
    }
}
