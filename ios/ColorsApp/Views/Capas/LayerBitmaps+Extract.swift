// Mapas de bits propios de Extraer y del visor de capas, construidos con las
// primitivas de LayerBitmaps (Subject/): la región de ropa con el contorno de la
// silueta del cuerpo (capa 5) y el aislamiento de los píxeles de un swatch sobre
// la foto (pulsación larga en un alfiler). Solo geometría de máscaras y etiquetas.
import CoreGraphics
import ColorEngine

extension LayerBitmaps {
    /// Contorno de la silueta del cuerpo (blanco).
    static let silhouetteOutline = RGB(r: 255, g: 255, b: 255)

    /// Región de ropa sombreada (cian, como `region`) y, encima, el contorno blanco de la
    /// silueta del cuerpo según la pose (lo que queda fuera no puede entrar en la máscara).
    static func regionWithSilhouette(region: [UInt8], silhouette: [UInt8]?, width: Int, height: Int) -> CGImage? {
        guard region.count == width * height else { return nil }
        let line = lineWidth(width: width, height: height)
        var px = tint(mask: region, width: width, height: height, color: regionTint, alpha: 120)
        paint(&px, where: outline(mask: region, width: width, height: height, thickness: line), color: regionTint)
        if let silhouette, silhouette.count == width * height {
            paint(&px, where: outline(mask: silhouette, width: width, height: height, thickness: line),
                  color: silhouetteOutline)
        }
        return rgbaImage(width: width, height: height, premultiplied: px)
    }

    /// Máscara de la imagen reducida con 255 donde el label map vale `swatch`.
    static func swatchMask(labelMap: [UInt8], swatch: Int) -> [UInt8] {
        guard swatch >= 0, swatch < Int(paletteLabelDiscarded) else { return [UInt8](repeating: 0, count: labelMap.count) }
        let label = UInt8(swatch)
        return labelMap.map { $0 == label ? 255 : 0 }
    }

    /// Oscurece todo menos los píxeles del swatch (imagen reducida; se muestra escalada sin
    /// interpolación sobre la foto).
    static func isolateSwatch(labelMap: [UInt8], width: Int, height: Int, swatch: Int) -> CGImage? {
        guard width > 0, height > 0, labelMap.count == width * height else { return nil }
        return dimOutside(mask: swatchMask(labelMap: labelMap, swatch: swatch), width: width, height: height)
    }
}
