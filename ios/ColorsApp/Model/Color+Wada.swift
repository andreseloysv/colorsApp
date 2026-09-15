// Colores SwiftUI/UIKit a partir de hex "#rrggbb" y de sRGB8. Sin lógica de
// color: solo conversión de representación para pintar swatches.
import SwiftUI
import UIKit
import ColorEngine

/// Parsea "#rrggbb" o "rrggbb" (mayúsculas o minúsculas). nil si no es válido.
func parseHexRGB(_ hex: String) -> (r: UInt8, g: UInt8, b: UInt8)? {
    var s = Substring(hex.trimmingCharacters(in: .whitespacesAndNewlines))
    if s.hasPrefix("#") { s = s.dropFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
}

extension Color {
    /// Color sRGB desde componentes de 8 bits.
    init(rgb8 r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }

    /// Color sRGB desde "#rrggbb"; nil si el hex no es válido.
    init?(hex: String) {
        guard let c = parseHexRGB(hex) else { return nil }
        self.init(rgb8: c.r, c.g, c.b)
    }

    /// Color de un `WadaColor` (usa `rgb`, con `hex` como respaldo; negro si nada vale).
    init(wada: WadaColor) {
        if wada.rgb.count == 3, wada.rgb.allSatisfy({ (0...255).contains($0) }) {
            self.init(rgb8: UInt8(wada.rgb[0]), UInt8(wada.rgb[1]), UInt8(wada.rgb[2]))
        } else if let c = Color(hex: wada.hex) {
            self = c
        } else {
            self.init(rgb8: 0, 0, 0)
        }
    }

    /// Color de un swatch de la paleta del motor.
    init(swatch: Swatch) {
        self.init(rgb8: swatch.r, swatch.g, swatch.b)
    }
}

extension UIColor {
    convenience init(rgb8 r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    convenience init?(hex: String) {
        guard let c = parseHexRGB(hex) else { return nil }
        self.init(rgb8: c.r, c.g, c.b)
    }

    convenience init(wada: WadaColor) {
        if wada.rgb.count == 3, wada.rgb.allSatisfy({ (0...255).contains($0) }) {
            self.init(rgb8: UInt8(wada.rgb[0]), UInt8(wada.rgb[1]), UInt8(wada.rgb[2]))
        } else if let c = parseHexRGB(wada.hex) {
            self.init(rgb8: c.r, c.g, c.b)
        } else {
            self.init(rgb8: 0, 0, 0)
        }
    }
}
