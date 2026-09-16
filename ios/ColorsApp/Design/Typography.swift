// Tipografía por rol (docs/design/DESIGN_SYSTEM.md §2): Literata (titulares,
// nombres, marca) y Plus Jakarta Sans (cuerpo, etiquetas, botones), ambas SIL OFL
// 1.1 y empaquetadas en Resources/Fonts (UIAppFonts en Info.plist). Hex y valores
// Lab en SF Mono del sistema. Todo escala con Dynamic Type (`relativeTo:`).
// Si las fuentes no se registran, `FontRegistry` intenta registrarlas desde el
// bundle y, si aun así faltan, cae a la serif y la redondeada del sistema.
import SwiftUI
import UIKit
import CoreText
import os

/// Familia de un rol.
enum FontFamily: String, Sendable {
    case serif, sans, mono
}

/// Peso de un rol (independiente de SwiftUI para poder usarlo en UIKit y en tests).
enum RoleWeight: Int, Sendable, Comparable {
    case regular = 400, medium = 500, semibold = 600, bold = 700

    static func < (a: RoleWeight, b: RoleWeight) -> Bool { a.rawValue < b.rawValue }

    var font: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    var uiKit: UIFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

/// Estilo de Dynamic Type de referencia (sendable, con equivalentes SwiftUI y UIKit).
enum RoleTextStyle: String, Sendable {
    case largeTitle, title, title2, title3, headline, subheadline, callout, caption, caption2

    var font: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .caption: .caption
        case .caption2: .caption2
        }
    }

    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .caption: .caption1
        case .caption2: .caption2
        }
    }
}

/// Un rol tipográfico de §2.2: familia, peso, tamaño base (pt a tamaño Large),
/// altura de línea objetivo, tracking en pt y estilo de Dynamic Type.
struct TextRole: Sendable, Hashable {
    let id: String
    let family: FontFamily
    let weight: RoleWeight
    let size: CGFloat
    let lineHeight: CGFloat
    let tracking: CGFloat
    let textStyle: RoleTextStyle
    var uppercase: Bool = false

    /// Altura natural (ascendente + descendente + interlínea) en em, medida con CoreText (§8).
    var naturalLineHeightEm: CGFloat {
        switch family {
        case .serif: 1.485
        case .sans: 1.26
        case .mono: 1.19
        }
    }

    /// `lineSpacing` de SwiftUI: objetivo − natural si es positivo (SwiftUI no puede reducirla).
    var lineSpacing: CGFloat {
        max(0, (lineHeight - size * naturalLineHeightEm).rounded(toPlaces: 2))
    }

    // MARK: Roles (§2.2)
    static let headlineXL = TextRole(id: "headline-xl", family: .serif, weight: .semibold, size: 36, lineHeight: 44, tracking: -0.72, textStyle: .largeTitle)
    static let headlineXLMobile = TextRole(id: "headline-xl-mobile", family: .serif, weight: .semibold, size: 28, lineHeight: 36, tracking: -0.28, textStyle: .title)
    static let headlineLG = TextRole(id: "headline-lg", family: .serif, weight: .semibold, size: 30, lineHeight: 38, tracking: 0, textStyle: .title)
    static let headlineLGMobile = TextRole(id: "headline-lg-mobile", family: .serif, weight: .semibold, size: 24, lineHeight: 32, tracking: 0, textStyle: .title2)
    static let headlineMD = TextRole(id: "headline-md", family: .serif, weight: .medium, size: 20, lineHeight: 28, tracking: 0, textStyle: .title3)
    static let headlineSM = TextRole(id: "headline-sm", family: .serif, weight: .medium, size: 18, lineHeight: 24, tracking: 0, textStyle: .headline)
    /// Marca «ChromaSol» en la cabecera (`headline-sm` + `tracking-tight`).
    static let brand = TextRole(id: "brand", family: .serif, weight: .medium, size: 18, lineHeight: 24, tracking: -0.45, textStyle: .headline)
    static let cardTitle = TextRole(id: "card-title", family: .serif, weight: .semibold, size: 15, lineHeight: 19, tracking: 0, textStyle: .subheadline)
    static let bodyLG = TextRole(id: "body-lg", family: .sans, weight: .regular, size: 16, lineHeight: 24, tracking: 0, textStyle: .callout)
    static let bodyMD = TextRole(id: "body-md", family: .sans, weight: .regular, size: 14, lineHeight: 20, tracking: 0, textStyle: .subheadline)
    static let bodySM = TextRole(id: "body-sm", family: .sans, weight: .regular, size: 12, lineHeight: 16, tracking: 0, textStyle: .caption)
    static let labelLG = TextRole(id: "label-lg", family: .sans, weight: .semibold, size: 14, lineHeight: 18, tracking: 0.14, textStyle: .subheadline)
    static let labelMD = TextRole(id: "label-md", family: .sans, weight: .semibold, size: 12, lineHeight: 16, tracking: 0.24, textStyle: .caption)
    /// Mínimo 11 pt en iOS (el ejemplo usa 10 px).
    static let labelSM = TextRole(id: "label-sm", family: .sans, weight: .bold, size: 11, lineHeight: 13, tracking: 0.44, textStyle: .caption2)
    static let overline = TextRole(id: "overline", family: .sans, weight: .bold, size: 11, lineHeight: 13, tracking: 1.10, textStyle: .caption2, uppercase: true)
    /// Hex y valores Lab: SF Mono 500, 12 pt (siempre mayúsculas en los datos).
    static let hex = TextRole(id: "hex", family: .mono, weight: .medium, size: 12, lineHeight: 16, tracking: 0, textStyle: .caption)

    static let all: [TextRole] = [
        headlineXL, headlineXLMobile, headlineLG, headlineLGMobile, headlineMD, headlineSM, brand, cardTitle,
        bodyLG, bodyMD, bodySM, labelLG, labelMD, labelSM, overline, hex,
    ]
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let m = pow(10, CGFloat(places))
        return (self * m).rounded() / m
    }
}

/// Estado del registro de fuentes (se calcula una vez, en el primer uso de `Typography`).
struct FontRegistryStatus: Sendable, Equatable {
    /// Literata disponible (por UIAppFonts o registrada en tiempo de ejecución).
    var literata: Bool
    /// Plus Jakarta Sans disponible.
    var jakarta: Bool
    /// true si hubo que registrarlas con CoreText porque UIAppFonts no las cargó.
    var registeredAtRuntime: Bool

    var allCustomFontsAvailable: Bool { literata && jakarta }
}

/// Registro y comprobación de las fuentes empaquetadas.
enum FontRegistry {
    static let literataFamily = "Literata"
    static let jakartaFamily = "Plus Jakarta Sans"
    /// Ficheros (sin extensión .ttf) listados en UIAppFonts.
    static let fontFiles = ["Literata-VF", "PlusJakartaSans-VF"]
    /// Licencias OFL empaquetadas junto a las fuentes (sin extensión .txt).
    static let licenseFiles = ["Literata-OFL", "PlusJakartaSans-OFL"]
    /// Instancias con nombre que deben existir tras el registro (PostScript).
    static let requiredInstances = ["Literata-Regular", "Literata-Regular_Medium", "Literata-Regular_SemiBold",
                                    "PlusJakartaSans-Regular", "PlusJakartaSans-Regular_SemiBold", "PlusJakartaSans-Regular_Bold"]

    private static let log = Logger(subsystem: "com.andreseloy.colorsapp", category: "design.fonts")

    /// Resultado de la comprobación (perezoso: el primer texto con estilo la dispara al arrancar).
    static let status: FontRegistryStatus = verify(bundle: .main)

    /// Dispara la comprobación explícitamente (idempotente) y devuelve el estado.
    @discardableResult
    static func bootstrap() -> FontRegistryStatus { status }

    static func isAvailable(family: String) -> Bool {
        !UIFont.fontNames(forFamilyName: family).isEmpty
    }

    /// Comprueba las familias; si falta alguna, intenta registrar los TTF del bundle
    /// (ámbito de proceso) y vuelve a comprobar. Registra el resultado en el log.
    static func verify(bundle: Bundle) -> FontRegistryStatus {
        var literata = isAvailable(family: literataFamily)
        var jakarta = isAvailable(family: jakartaFamily)
        var runtime = false
        if !(literata && jakarta) {
            for file in fontFiles {
                guard let url = bundle.url(forResource: file, withExtension: "ttf") else {
                    log.error("Fuente \(file, privacy: .public).ttf ausente del bundle")
                    continue
                }
                var error: Unmanaged<CFError>?
                if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                    runtime = true
                } else {
                    let message = error?.takeRetainedValue().localizedDescription ?? "desconocido"
                    log.error("No se pudo registrar \(file, privacy: .public): \(message, privacy: .public)")
                }
            }
            literata = isAvailable(family: literataFamily)
            jakarta = isAvailable(family: jakartaFamily)
        }
        let result = FontRegistryStatus(literata: literata, jakarta: jakarta, registeredAtRuntime: runtime)
        if result.allCustomFontsAvailable {
            log.info("Fuentes listas: Literata y Plus Jakarta Sans (registro en tiempo de ejecución: \(runtime))")
        } else {
            log.error("Fuentes no disponibles (Literata \(literata), Plus Jakarta Sans \(jakarta)): se usa la serif/redondeada del sistema")
        }
        return result
    }
}

/// Fuentes de SwiftUI y UIKit por rol.
enum Typography {
    /// `Font` del rol, escalada con Dynamic Type relativa a su estilo.
    static func font(_ role: TextRole) -> Font {
        font(role, status: FontRegistry.status)
    }

    /// Variante con estado inyectable (tests del fallback).
    static func font(_ role: TextRole, status: FontRegistryStatus) -> Font {
        switch role.family {
        case .serif:
            if status.literata {
                return .custom(FontRegistry.literataFamily, size: role.size, relativeTo: role.textStyle.font)
                    .weight(role.weight.font)
            }
            return .system(role.textStyle.font, design: .serif, weight: role.weight.font)
        case .sans:
            if status.jakarta {
                return .custom(FontRegistry.jakartaFamily, size: role.size, relativeTo: role.textStyle.font)
                    .weight(role.weight.font)
            }
            return .system(role.textStyle.font, design: .rounded, weight: role.weight.font)
        case .mono:
            // SF Mono con Dynamic Type: el estilo `.caption` mide 12 pt a tamaño Large.
            return .system(role.textStyle.font, design: .monospaced, weight: role.weight.font)
        }
    }

    /// `UIFont` escalada con `UIFontMetrics` (barras de navegación, `UITabBarAppearance`, CoreText).
    static func uiFont(_ role: TextRole, compatibleWith traits: UITraitCollection? = nil) -> UIFont {
        let status = FontRegistry.status
        let base: UIFont
        switch role.family {
        case .serif where status.literata:
            base = familyFont(FontRegistry.literataFamily, size: role.size, weight: role.weight)
        case .sans where status.jakarta:
            base = familyFont(FontRegistry.jakartaFamily, size: role.size, weight: role.weight)
        case .serif:
            let d = UIFont.systemFont(ofSize: role.size, weight: role.weight.uiKit).fontDescriptor.withDesign(.serif)
            base = d.map { UIFont(descriptor: $0, size: role.size) } ?? .systemFont(ofSize: role.size, weight: role.weight.uiKit)
        case .sans:
            let d = UIFont.systemFont(ofSize: role.size, weight: role.weight.uiKit).fontDescriptor.withDesign(.rounded)
            base = d.map { UIFont(descriptor: $0, size: role.size) } ?? .systemFont(ofSize: role.size, weight: role.weight.uiKit)
        case .mono:
            base = .monospacedSystemFont(ofSize: role.size, weight: role.weight.uiKit)
        }
        return UIFontMetrics(forTextStyle: role.textStyle.uiKit).scaledFont(for: base, compatibleWith: traits)
    }

    /// Fuente por familia + rasgo de peso: CoreText elige la instancia del eje `wght`.
    static func familyFont(_ family: String, size: CGFloat, weight: RoleWeight) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [UIFontDescriptor.TraitKey.weight: weight.uiKit],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

/// Aplica fuente, tracking, interlineado y mayúsculas de un rol.
struct TextRoleModifier: ViewModifier {
    let role: TextRole
    var weight: RoleWeight?

    func body(content: Content) -> some View {
        content
            .font(Typography.font(weight.map { TextRole(id: role.id, family: role.family, weight: $0, size: role.size,
                                                        lineHeight: role.lineHeight, tracking: role.tracking,
                                                        textStyle: role.textStyle, uppercase: role.uppercase) } ?? role))
            .tracking(role.tracking)
            .lineSpacing(role.lineSpacing)
            .textCase(role.uppercase ? .uppercase : nil)
    }
}

extension View {
    /// `Text("PALETA DE LA ROPA").textRole(.overline)`; `weight` sustituye el peso del rol.
    func textRole(_ role: TextRole, weight: RoleWeight? = nil) -> some View {
        modifier(TextRoleModifier(role: role, weight: weight))
    }
}
