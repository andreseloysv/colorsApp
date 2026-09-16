// Atajos de captura del Feed (solo DEBUG; se combinan con `-uiScreen feed`, `feed-demo` o
// `feed-empty` y con `xcrun simctl ui <udid> appearance light|dark`):
//   -uiFeedScroll <n>[-bottom|@f]  desplaza hasta la publicación n (0-based): arriba, abajo o
//                                al punto f de la publicación alineado con el del visor (0 arriba, 1 abajo; admite -2…2)
//   -uiFeedFilter <filtro>       chip activo: all, two, three, four, saved, unvoted
//   -uiFeedShare <n>             abre «Compartir tarjeta» de la publicación n
//   -uiShareFormat post|story    formato inicial de esa hoja
//   -uiFeedCombo <id>            abre la hoja de detalle de la combinación
//   -uiFeedOpen <n>              «Abrir en Extraer» de la publicación n (reanaliza y empuja Resultado)
//   -uiFeedToast <texto>         muestra el toast con ese texto
//   xcrun simctl launch <udid> com.andreseloy.colorsapp -uiScreen feed-demo -uiFeedScroll 0-bottom
import SwiftUI

struct FeedLaunchOptions: Equatable {
    struct Scroll: Equatable {
        let index: Int
        /// Punto de la publicación que se alinea con el mismo punto del visor (0 arriba … 1 abajo).
        let fraction: Double

        var anchor: UnitPoint { UnitPoint(x: 0.5, y: fraction) }
    }

    var scroll: Scroll?
    var filter: FeedFilter?
    var shareIndex: Int?
    var shareFormat: ShareCardFormat = .post
    var comboSheet: Int?
    var openIndex: Int?
    var toast: String?

    static let none = FeedLaunchOptions()
    static let topAnchor = "feed.top"

    static func parse(_ args: [String]) -> FeedLaunchOptions {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        var o = FeedLaunchOptions()
        if let raw = value("-uiFeedScroll") {
            // «1», «0-bottom» o «0@0.6».
            let parts = raw.replacingOccurrences(of: "-bottom", with: "@1").split(separator: "@")
            if let n = parts.first.flatMap({ Int($0) }) {
                let fraction = parts.count > 1 ? (Double(parts[1]) ?? 0) : 0
                o.scroll = Scroll(index: n, fraction: min(max(fraction, -2), 2))
            }
        }
        o.filter = value("-uiFeedFilter").flatMap(FeedFilter.init(rawValue:))
        o.shareIndex = value("-uiFeedShare").flatMap(Int.init)
        o.shareFormat = value("-uiShareFormat").flatMap(ShareCardFormat.init(rawValue:)) ?? .post
        o.comboSheet = value("-uiFeedCombo").flatMap(Int.init)
        o.openIndex = value("-uiFeedOpen").flatMap(Int.init)
        o.toast = value("-uiFeedToast")
        return o
    }

    /// Opciones del proceso actual; siempre vacías en Release.
    static var current: FeedLaunchOptions {
        #if DEBUG
        return parse(ProcessInfo.processInfo.arguments)
        #else
        return .none
        #endif
    }
}
