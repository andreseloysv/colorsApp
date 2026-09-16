// Tokens de color del sistema de diseño (docs/design/DESIGN_SYSTEM.md §1).
// Claro = valores del ejemplo del usuario (solarpunk_meadow/DESIGN.md, sin cambios);
// oscuro = «Solarpunk Night» (§1.2). Los colores de DATOS (paleta del motor,
// colores de Wada) NO se crean con estos tokens: van en `PaletteColor` y siempre
// dentro de un pocillo neutro (`Theme.well*`, §1.4). Sin lógica de color: solo
// valores sRGB fijos y resolución por tema.
import SwiftUI
import UIKit

/// Un token con su valor sRGB8 empaquetado (0xRRGGBB) y opacidad por tema.
/// Los tests leen `ThemeTokens.all` para comprobar hex, contraste WCAG y neutralidad.
struct ThemeToken: Sendable, Hashable {
    let name: String
    let light: UInt32
    let dark: UInt32
    var lightOpacity: Double = 1
    var darkOpacity: Double = 1

    init(_ name: String, light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.name = name
        self.light = light
        self.dark = dark
        self.lightOpacity = lightOpacity
        self.darkOpacity = darkOpacity
    }

    /// Token igual en ambos temas (familia «fixed»).
    init(fixed name: String, _ value: UInt32) {
        self.init(name, light: value, dark: value)
    }

    func value(for scheme: ColorScheme) -> UInt32 { scheme == .dark ? dark : light }
    func opacity(for scheme: ColorScheme) -> Double { scheme == .dark ? darkOpacity : lightOpacity }

    /// Componentes sRGB8 del tema pedido.
    func rgb8(for scheme: ColorScheme) -> (r: UInt8, g: UInt8, b: UInt8) {
        let v = value(for: scheme)
        return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }

    /// "#RRGGBB" del tema pedido (mayúsculas).
    func hex(for scheme: ColorScheme) -> String {
        String(format: "#%06X", value(for: scheme))
    }

    var color: Color { Color(light: light, dark: dark, lightOpacity: lightOpacity, darkOpacity: darkOpacity) }
}

extension UIColor {
    /// UIColor sRGB desde 0xRRGGBB.
    convenience init(rgbHex v: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }

    /// UIColor dinámico que sigue `userInterfaceStyle` (claro u oscuro).
    convenience init(light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.init { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgbHex: dark, alpha: CGFloat(darkOpacity))
                : UIColor(rgbHex: light, alpha: CGFloat(lightOpacity))
        }
    }
}

extension Color {
    /// Color que cambia con el tema (entorno SwiftUI o trait collection). `light`/`dark` en 0xRRGGBB.
    init(light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.init(uiColor: UIColor(light: light, dark: dark, lightOpacity: lightOpacity, darkOpacity: darkOpacity))
    }
}

/// Tabla cruda de tokens (§1.1, §1.3, §1.4). Fuente única de los valores.
enum ThemeTokens {
    // MARK: Superficies (marco cálido)
    static let surface = ThemeToken("surface", light: 0xFCF9F1, dark: 0x15130E)
    static let surfaceDim = ThemeToken("surfaceDim", light: 0xDCDAD2, dark: 0x15130E)
    static let surfaceBright = ThemeToken("surfaceBright", light: 0xFCF9F1, dark: 0x3C372E)
    static let containerLowest = ThemeToken("containerLowest", light: 0xFFFFFF, dark: 0x0F0D09)
    static let containerLow = ThemeToken("containerLow", light: 0xF6F3EB, dark: 0x1C1913)
    static let container = ThemeToken("container", light: 0xF1EEE6, dark: 0x221F18)
    static let containerHigh = ThemeToken("containerHigh", light: 0xEBE8E0, dark: 0x2C2820)
    static let containerHighest = ThemeToken("containerHighest", light: 0xE5E2DB, dark: 0x37322A)
    static let surfaceVariant = ThemeToken("surfaceVariant", light: 0xE5E2DB, dark: 0x37322A)
    static let surfaceTint = ThemeToken("surfaceTint", light: 0x3B6849, dark: 0xA1D2AC)
    /// Fondo de toda tarjeta: `containerLowest` en claro, `containerLow` en oscuro.
    static let card = ThemeToken("card", light: 0xFFFFFF, dark: 0x1C1913)

    // MARK: Texto y contornos
    static let onSurface = ThemeToken("onSurface", light: 0x1C1C17, dark: 0xEDE6D6)
    static let onSurfaceVariant = ThemeToken("onSurfaceVariant", light: 0x414942, dark: 0xCDC5B3)
    static let outline = ThemeToken("outline", light: 0x717971, dark: 0x979080)
    static let outlineVariant = ThemeToken("outlineVariant", light: 0xC1C9BF, dark: 0x4B463B)

    // MARK: Primario (musgo)
    static let primary = ThemeToken("primary", light: 0x144226, dark: 0xA1D2AC)
    static let onPrimary = ThemeToken("onPrimary", light: 0xFFFFFF, dark: 0x0B3A1D)
    static let primaryContainer = ThemeToken("primaryContainer", light: 0x2D5A3C, dark: 0x224F32)
    static let onPrimaryContainer = ThemeToken("onPrimaryContainer", light: 0x9ED0AA, dark: 0xBCEFC7)
    static let inversePrimary = ThemeToken("inversePrimary", light: 0xA1D2AC, dark: 0x2D5A3C)

    // MARK: Secundario (ámbar solar / terracota)
    static let secondary = ThemeToken("secondary", light: 0x954A00, dark: 0xFFB785)
    static let onSecondary = ThemeToken("onSecondary", light: 0xFFFFFF, dark: 0x4F2500)
    static let secondaryContainer = ThemeToken("secondaryContainer", light: 0xFD933F, dark: 0x713700)
    static let onSecondaryContainer = ThemeToken("onSecondaryContainer", light: 0x693300, dark: 0xFFDCC6)

    // MARK: Terciario (celadón)
    static let tertiary = ThemeToken("tertiary", light: 0x144136, dark: 0xA2D0C0)
    static let onTertiary = ThemeToken("onTertiary", light: 0xFFFFFF, dark: 0x07372B)
    static let tertiaryContainer = ThemeToken("tertiaryContainer", light: 0x2D594C, dark: 0x224E42)
    static let onTertiaryContainer = ThemeToken("onTertiaryContainer", light: 0xA0CEBE, dark: 0xBDECDC)

    // MARK: Error
    static let error = ThemeToken("error", light: 0xBA1A1A, dark: 0xFFB4AB)
    static let onError = ThemeToken("onError", light: 0xFFFFFF, dark: 0x690005)
    static let errorContainer = ThemeToken("errorContainer", light: 0xFFDAD6, dark: 0x93000A)
    static let onErrorContainer = ThemeToken("onErrorContainer", light: 0x93000A, dark: 0xFFDAD6)

    // MARK: Fijos (iguales en ambos temas)
    static let primaryFixed = ThemeToken(fixed: "primaryFixed", 0xBCEFC7)
    static let primaryFixedDim = ThemeToken(fixed: "primaryFixedDim", 0xA1D2AC)
    static let onPrimaryFixed = ThemeToken(fixed: "onPrimaryFixed", 0x00210E)
    static let onPrimaryFixedVariant = ThemeToken(fixed: "onPrimaryFixedVariant", 0x224F32)
    static let secondaryFixed = ThemeToken(fixed: "secondaryFixed", 0xFFDCC6)
    static let secondaryFixedDim = ThemeToken(fixed: "secondaryFixedDim", 0xFFB785)
    static let onSecondaryFixed = ThemeToken(fixed: "onSecondaryFixed", 0x301400)
    static let onSecondaryFixedVariant = ThemeToken(fixed: "onSecondaryFixedVariant", 0x713700)
    static let tertiaryFixed = ThemeToken(fixed: "tertiaryFixed", 0xBDECDC)
    static let tertiaryFixedDim = ThemeToken(fixed: "tertiaryFixedDim", 0xA2D0C0)
    static let onTertiaryFixed = ThemeToken(fixed: "onTertiaryFixed", 0x002019)
    static let onTertiaryFixedVariant = ThemeToken(fixed: "onTertiaryFixedVariant", 0x224E42)

    // MARK: Inversos (toasts)
    static let inverseSurface = ThemeToken("inverseSurface", light: 0x31312B, dark: 0xEDE6D6)
    static let inverseOnSurface = ThemeToken("inverseOnSurface", light: 0xF3F1E9, dark: 0x2C2820)

    // MARK: Pocillo neutro de juicio de color (§1.4): acromáticos, R = G = B
    static let wellFill = ThemeToken("wellFill", light: 0xFFFFFF, dark: 0x303030)
    static let wellFillAlt = ThemeToken("wellFillAlt", light: 0xF2F2F2, dark: 0x333333)
    static let wellEdge = ThemeToken("wellEdge", light: 0xD6D6D6, dark: 0x4A4A4A)
    static let wellText = ThemeToken("wellText", light: 0x1F1F1F, dark: 0xEDEDED)
    static let wellTextSecondary = ThemeToken("wellTextSecondary", light: 0x5C5C5C, dark: 0xB0B0B0)
    static let wellPlaceholder = ThemeToken("wellPlaceholder", light: 0xE6E6E6, dark: 0x3D3D3D)
    static let wellPlaceholderStripe = ThemeToken("wellPlaceholderStripe", light: 0xDEDEDE, dark: 0x454545)
    /// Borde de cada swatch: negro al 12 % en claro, blanco al 14 % en oscuro.
    static let swatchHairline = ThemeToken("swatchHairline", light: 0x000000, dark: 0xFFFFFF,
                                           lightOpacity: 0.12, darkOpacity: 0.14)

    // MARK: Acentos decorativos del marco (§1.3): nunca junto a un swatch
    static let brassHairline = ThemeToken("brassHairline", light: 0xC29B38, dark: 0xC29B38,
                                          lightOpacity: 0.25, darkOpacity: 0.30)
    static let sepiaShadow = ThemeToken("sepiaShadow", light: 0x44301C, dark: 0x000000)
    static let sunAmber = ThemeToken("sunAmber", light: 0xF59E0B, dark: 0xFBBF24)
    static let sunAmberSoft = ThemeToken(fixed: "sunAmberSoft", 0xFBBF24)
    static let mossGlow = ThemeToken("mossGlow", light: 0x2D5A3C, dark: 0xA1D2AC, lightOpacity: 0.16, darkOpacity: 0.12)
    static let amberGlow = ThemeToken("amberGlow", light: 0xD97724, dark: 0x000000, lightOpacity: 0.10, darkOpacity: 0)
    static let chipCeladon = ThemeToken("chipCeladon", light: 0xE9EDE4, dark: 0x242A23)
    /// Oscuro al 78 % (el documento dice 72 %): con 72 % `primary` quedaba en 4,37:1 en el peor caso
    /// (tinte sobre blanco puro); con 78 % pasa AA (test de contraste).
    static let frostTint = ThemeToken("frostTint", light: 0xF9F6EE, dark: 0x15130E, lightOpacity: 0.78, darkOpacity: 0.78)
    /// Lavados difusos de fondo (§1.3).
    static let washWarm = ThemeToken("washWarm", light: 0xFFDCC6, dark: 0x713700, lightOpacity: 0.40, darkOpacity: 0.25)
    static let washGreen = ThemeToken("washGreen", light: 0xBCEFC7, dark: 0x224F32, lightOpacity: 0.40, darkOpacity: 0.35)
    /// Fondo neutro del visor de capas a pantalla completa (§4 n.º 30), igual en ambos temas.
    static let storyBackdrop = ThemeToken(fixed: "storyBackdrop", 0x121212)

    // MARK: Tonos de insignia (círculos de icono, chips de estado): fijo en claro, contenedor en oscuro
    static let mossBadge = ThemeToken("mossBadge", light: 0xBCEFC7, dark: 0x224F32)
    static let onMossBadge = ThemeToken("onMossBadge", light: 0x144226, dark: 0xBCEFC7)
    static let amberBadge = ThemeToken("amberBadge", light: 0xFFDCC6, dark: 0x713700)
    static let onAmberBadge = ThemeToken("onAmberBadge", light: 0x713700, dark: 0xFFDCC6)
    static let celadonBadge = ThemeToken("celadonBadge", light: 0xBDECDC, dark: 0x224E42)
    static let onCeladonBadge = ThemeToken("onCeladonBadge", light: 0x144136, dark: 0xBDECDC)

    /// Todos los tokens (para tests y la galería).
    static let all: [ThemeToken] = [
        surface, surfaceDim, surfaceBright, containerLowest, containerLow, container, containerHigh,
        containerHighest, surfaceVariant, surfaceTint, card,
        onSurface, onSurfaceVariant, outline, outlineVariant,
        primary, onPrimary, primaryContainer, onPrimaryContainer, inversePrimary,
        secondary, onSecondary, secondaryContainer, onSecondaryContainer,
        tertiary, onTertiary, tertiaryContainer, onTertiaryContainer,
        error, onError, errorContainer, onErrorContainer,
        primaryFixed, primaryFixedDim, onPrimaryFixed, onPrimaryFixedVariant,
        secondaryFixed, secondaryFixedDim, onSecondaryFixed, onSecondaryFixedVariant,
        tertiaryFixed, tertiaryFixedDim, onTertiaryFixed, onTertiaryFixedVariant,
        inverseSurface, inverseOnSurface,
        wellFill, wellFillAlt, wellEdge, wellText, wellTextSecondary, wellPlaceholder, wellPlaceholderStripe,
        swatchHairline,
        brassHairline, sepiaShadow, sunAmber, sunAmberSoft, mossGlow, amberGlow, chipCeladon, frostTint,
        washWarm, washGreen, storyBackdrop,
        mossBadge, onMossBadge, amberBadge, onAmberBadge, celadonBadge, onCeladonBadge,
    ]

    /// Tokens del pocillo neutro (deben ser acromáticos en ambos temas).
    static let neutralWell: [ThemeToken] = [
        wellFill, wellFillAlt, wellEdge, wellText, wellTextSecondary, wellPlaceholder, wellPlaceholderStripe, swatchHairline,
    ]
}

/// Tokens como `Color` de SwiftUI: `Theme.surface`, `Theme.primary`, `Theme.wellFill`…
/// (el documento de diseño los llama `Solar.*`; `Solar` es un alias de `Theme`).
enum Theme {
    // Superficies
    static let surface = ThemeTokens.surface.color
    static let surfaceDim = ThemeTokens.surfaceDim.color
    static let surfaceBright = ThemeTokens.surfaceBright.color
    static let containerLowest = ThemeTokens.containerLowest.color
    static let containerLow = ThemeTokens.containerLow.color
    static let container = ThemeTokens.container.color
    static let containerHigh = ThemeTokens.containerHigh.color
    static let containerHighest = ThemeTokens.containerHighest.color
    static let surfaceVariant = ThemeTokens.surfaceVariant.color
    static let surfaceTint = ThemeTokens.surfaceTint.color
    static let card = ThemeTokens.card.color
    // Texto y contornos
    static let onSurface = ThemeTokens.onSurface.color
    static let onSurfaceVariant = ThemeTokens.onSurfaceVariant.color
    static let outline = ThemeTokens.outline.color
    static let outlineVariant = ThemeTokens.outlineVariant.color
    // Primario
    static let primary = ThemeTokens.primary.color
    static let onPrimary = ThemeTokens.onPrimary.color
    static let primaryContainer = ThemeTokens.primaryContainer.color
    static let onPrimaryContainer = ThemeTokens.onPrimaryContainer.color
    static let inversePrimary = ThemeTokens.inversePrimary.color
    // Secundario
    static let secondary = ThemeTokens.secondary.color
    static let onSecondary = ThemeTokens.onSecondary.color
    static let secondaryContainer = ThemeTokens.secondaryContainer.color
    static let onSecondaryContainer = ThemeTokens.onSecondaryContainer.color
    // Terciario
    static let tertiary = ThemeTokens.tertiary.color
    static let onTertiary = ThemeTokens.onTertiary.color
    static let tertiaryContainer = ThemeTokens.tertiaryContainer.color
    static let onTertiaryContainer = ThemeTokens.onTertiaryContainer.color
    // Error
    static let error = ThemeTokens.error.color
    static let onError = ThemeTokens.onError.color
    static let errorContainer = ThemeTokens.errorContainer.color
    static let onErrorContainer = ThemeTokens.onErrorContainer.color
    // Fijos
    static let primaryFixed = ThemeTokens.primaryFixed.color
    static let primaryFixedDim = ThemeTokens.primaryFixedDim.color
    static let onPrimaryFixed = ThemeTokens.onPrimaryFixed.color
    static let onPrimaryFixedVariant = ThemeTokens.onPrimaryFixedVariant.color
    static let secondaryFixed = ThemeTokens.secondaryFixed.color
    static let secondaryFixedDim = ThemeTokens.secondaryFixedDim.color
    static let onSecondaryFixed = ThemeTokens.onSecondaryFixed.color
    static let onSecondaryFixedVariant = ThemeTokens.onSecondaryFixedVariant.color
    static let tertiaryFixed = ThemeTokens.tertiaryFixed.color
    static let tertiaryFixedDim = ThemeTokens.tertiaryFixedDim.color
    static let onTertiaryFixed = ThemeTokens.onTertiaryFixed.color
    static let onTertiaryFixedVariant = ThemeTokens.onTertiaryFixedVariant.color
    // Inversos
    static let inverseSurface = ThemeTokens.inverseSurface.color
    static let inverseOnSurface = ThemeTokens.inverseOnSurface.color
    // Pocillo neutro
    static let wellFill = ThemeTokens.wellFill.color
    static let wellFillAlt = ThemeTokens.wellFillAlt.color
    static let wellEdge = ThemeTokens.wellEdge.color
    static let wellText = ThemeTokens.wellText.color
    static let wellTextSecondary = ThemeTokens.wellTextSecondary.color
    static let wellPlaceholder = ThemeTokens.wellPlaceholder.color
    static let wellPlaceholderStripe = ThemeTokens.wellPlaceholderStripe.color
    static let swatchHairline = ThemeTokens.swatchHairline.color
    // Decorativos del marco
    static let brassHairline = ThemeTokens.brassHairline.color
    static let sunAmber = ThemeTokens.sunAmber.color
    static let sunAmberSoft = ThemeTokens.sunAmberSoft.color
    static let mossGlow = ThemeTokens.mossGlow.color
    static let chipCeladon = ThemeTokens.chipCeladon.color
    static let frostTint = ThemeTokens.frostTint.color
    static let washWarm = ThemeTokens.washWarm.color
    static let washGreen = ThemeTokens.washGreen.color
    static let storyBackdrop = ThemeTokens.storyBackdrop.color
    /// Sombra sepia `rgb(68,48,28)` sin opacidad (las elevaciones la aplican).
    static let sepia = Color(.sRGB, red: 68 / 255, green: 48 / 255, blue: 28 / 255, opacity: 1)
    /// Ámbar del segundo halo de E3 `rgb(217,119,36)`.
    static let amberGlowBase = Color(.sRGB, red: 217 / 255, green: 119 / 255, blue: 36 / 255, opacity: 1)
}

typealias Solar = Theme

/// Tono de acento para insignias, iconos en círculo, puntos de colección y valores.
enum Tone: String, Sendable, CaseIterable {
    case moss, amber, celadon

    /// Color de acento sobre el marco (texto o icono con significado).
    var accent: Color {
        switch self {
        case .moss: Theme.primary
        case .amber: Theme.secondary
        case .celadon: Theme.tertiary
        }
    }

    /// Relleno de insignia (fijo en claro, contenedor en oscuro).
    var badgeFill: Color {
        switch self {
        case .moss: ThemeTokens.mossBadge.color
        case .amber: ThemeTokens.amberBadge.color
        case .celadon: ThemeTokens.celadonBadge.color
        }
    }

    /// Texto o icono sobre `badgeFill` (AA en ambos temas).
    var onBadge: Color {
        switch self {
        case .moss: ThemeTokens.onMossBadge.color
        case .amber: ThemeTokens.onAmberBadge.color
        case .celadon: ThemeTokens.onCeladonBadge.color
        }
    }
}
