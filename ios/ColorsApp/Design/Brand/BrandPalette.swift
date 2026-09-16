// Colores fijos de la marca (logotipo, iconos de pestaña, icono de la app). Salen de la
// paleta del ejemplo del usuario (tokens de solarpunk_meadow/DESIGN.md y los ámbar,
// verde azulado y esmeralda de code.html). Son colores de ILUSTRACIÓN del marco: nunca se
// usan como color de datos ni junto a un swatch (zona neutra, DESIGN_SYSTEM.md §1.4).
// Solo SwiftUI (sin UIKit) para compilar también en el script de macOS del icono.
import SwiftUI

extension Color {
    /// Color sRGB de la marca desde 0xRRGGBB.
    init(brand hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// Tintas de ilustración por tema. En oscuro («Solarpunk Night») los trazos oscuros pasan a
/// tonos claros para que el dibujo no se pierda sobre el fondo; los rellenos luminosos
/// (sol, pétalos, gota) se mantienen.
struct BrandInk: Sendable {
    let dark: Bool

    init(_ scheme: ColorScheme) { dark = scheme == .dark }

    // MARK: Sol (ámbar de code.html: amber-200/300/400/500, #D97724 de la prosa)
    var sunLight: Color { Color(brand: 0xFEF3C7) }
    var sunSoft: Color { Color(brand: 0xFDE68A) }
    var sunGold: Color { Color(brand: 0xFBBF24) }
    var sunAmber: Color { Color(brand: 0xF59E0B) }
    var sunDeep: Color { Color(brand: 0xD97724) }
    /// Trazo del contorno de la semilla solar.
    var sunEdge: Color { dark ? Color(brand: 0xFCD34D) : Color(brand: 0xB45309) }
    /// Resplandor ámbar del destello (`rgba(245,158,11,…)`).
    var sunGlow: Color { Color(brand: 0xF59E0B) }

    // MARK: Hojas y musgo (primary #144226, primaryContainer #2D5A3C, sage #81B29A, primaryFixed)
    var mossDeep: Color { dark ? Color(brand: 0xBCEFC7) : Color(brand: 0x144226) }
    var moss: Color { dark ? Color(brand: 0x81B29A) : Color(brand: 0x2D5A3C) }
    var sage: Color { dark ? Color(brand: 0xA1D2AC) : Color(brand: 0x81B29A) }
    var mint: Color { Color(brand: 0xA1D2AC) }
    var mintPale: Color { Color(brand: 0xBCEFC7) }
    /// `rgba(188,239,199,…)`: halo verde claro de la pestaña activa.
    var haloGreen: Color { Color(brand: 0xBCEFC7) }

    // MARK: Celadón y verde azulado (tertiary, teal-300 #5EEAD4 de las motas)
    var celadon: Color { Color(brand: 0x7CA99A) }
    var celadonPale: Color { Color(brand: 0xBDECDC) }
    var celadonInk: Color { dark ? Color(brand: 0xBDECDC) : Color(brand: 0x2D594C) }
    var tealGlow: Color { Color(brand: 0x5EEAD4) }

    // MARK: Terracota y latón (secondary #954A00, onSecondaryFixedVariant #713700, brass #C29B38)
    var terracotta: Color { Color(brand: 0xC8644A) }
    var terracottaLight: Color { Color(brand: 0xE07A5F) }
    var peach: Color { Color(brand: 0xFFDCC6) }
    var clayInk: Color { dark ? Color(brand: 0xFFB785) : Color(brand: 0x713700) }
    var amberInk: Color { dark ? Color(brand: 0xFFB785) : Color(brand: 0x954A00) }
    var brass: Color { Color(brand: 0xC29B38) }

    // MARK: Caritas
    /// Ojos y boca (marrón cálido, nunca negro puro).
    var face: Color { Color(brand: 0x4A2308) }
    var faceCool: Color { Color(brand: 0x0F3A2E) }
    var cheek: Color { Color(brand: 0xF87171) }

    // MARK: Pergamino del emblema
    var parchmentTop: Color { dark ? Color(brand: 0x2C2820) : Color(brand: 0xFFF9EC) }
    var parchmentBottom: Color { dark ? Color(brand: 0x1C1913) : Color(brand: 0xF6ECD8) }
    var skyGlow: Color { dark ? Color(brand: 0xFBBF24, opacity: 0.30) : Color(brand: 0xFFE3A3, opacity: 0.95) }
    var hillBack: Color { dark ? Color(brand: 0x224F32) : Color(brand: 0xA1D2AC) }
    var hillFront: Color { dark ? Color(brand: 0x163A24) : Color(brand: 0x2D5A3C) }

    /// Espectro del prisma (terracota, trigo, salvia, verde azulado, anochecer): tonos de
    /// ilustración del ejemplo, no colores de Wada ni de datos.
    var spectrum: [Color] {
        [Color(brand: 0xE07A5F), Color(brand: 0xF2CC8F), Color(brand: 0x81B29A), Color(brand: 0x5FA8A0), Color(brand: 0x3D5A80)]
    }

    /// Rueda de color del núcleo del sol (seis gajos).
    var wheel: [Color] {
        [Color(brand: 0xC8644A), Color(brand: 0xE9B44C), Color(brand: 0x81B29A),
         Color(brand: 0x4E8F84), Color(brand: 0x3D5A80), Color(brand: 0xB5657B)]
    }
}
