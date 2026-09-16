// Argumento de lanzamiento de depuración (solo DEBUG): `-uiScreen <pantalla>` abre
// la app directamente en una pestaña o pantalla para capturas y verificación.
// RootTabView elige la pestaña inicial con `DebugLaunch.initialTab` y cada pestaña
// consume lo suyo empujando rutas en su NavigationStack:
//   Feed      `feed`                pestaña Feed con la base de datos real
//             `feed-demo`           Feed con publicaciones de EJEMPLO (base de datos en memoria,
//                                   marcadas «Ejemplo»: foto de grupo de Debug y escenas sintéticas)
//             `feed-empty`          Feed vacío (base de datos en memoria)
//   Extraer   `extraer`, `result-demo` (imagen sintética de la combinación 12), `result-people`,
//             `result-people-mask`, `result-demo-person`, `result-demo-people`,
//             `result-demo-people-mask`, `layers-demo`, `layers-people` (con `-uiLayer <n>`, 1...11)
//   Rejilla   `rejilla`, `rejilla-demo`, `explorar-<id>` (detalle de esa combinación; alias histórico)
//   Jardín    `jardin`, `jardin-demo`, `ajustes` (Jardín › Ajustes)
// Otros valores con prefijo de pestaña («rejilla-…», «jardin-…», «extraer-…», «feed-…») abren
// esa pestaña aunque no tengan caso propio aquí: los interpreta la pestaña.
//   xcrun simctl launch <udid> com.andreseloy.colorsapp -uiScreen feed-demo
import Foundation
import CoreGraphics
import ImageIO

enum DebugLaunch {
    enum Screen: Equatable, Sendable {
        case resultDemo
        case explorar(Int)
        case ajustes
        case resultPeople
        case resultPeopleMask
        case layersPeople
        case layersDemo
        case resultDemoPerson
        case resultDemoPeople
        case resultDemoPeopleMask
        case feed
        case feedDemo
        case feedEmpty
        case extraer
        case rejilla
        case jardin
    }

    static let argument = "-uiScreen"
    static let layerArgument = "-uiLayer"
    static let demoComboId = 12
    /// Foto de grupo embebida solo en Debug (project.yml la excluye en Release).
    static let groupPhotoResource = "06_group_courier_street"

    static func screen(from arguments: [String]) -> Screen? {
        guard let i = arguments.firstIndex(of: argument), i + 1 < arguments.count else { return nil }
        let value = arguments[i + 1]
        switch value {
        case "result-demo": return .resultDemo
        case "ajustes": return .ajustes
        case "result-people": return .resultPeople
        case "result-people-mask": return .resultPeopleMask
        case "layers-people": return .layersPeople
        case "layers-demo": return .layersDemo
        case "result-demo-person": return .resultDemoPerson
        case "result-demo-people": return .resultDemoPeople
        case "result-demo-people-mask": return .resultDemoPeopleMask
        case "feed": return .feed
        case "feed-demo": return .feedDemo
        case "feed-empty": return .feedEmpty
        case "extraer": return .extraer
        case "rejilla": return .rejilla
        case "jardin": return .jardin
        default: break
        }
        if value.hasPrefix("explorar-"), let id = Int(value.dropFirst("explorar-".count)) { return .explorar(id) }
        return nil
    }

    /// Capa inicial del inspector (`-uiLayer n`, 1...11).
    static func layer(from arguments: [String]) -> Int? {
        guard let i = arguments.firstIndex(of: layerArgument), i + 1 < arguments.count,
              let n = Int(arguments[i + 1]), (1...InspectorLayer.Kind.allCases.count).contains(n) else { return nil }
        return n
    }

    static var requestedLayer: Int? {
        #if DEBUG
        return layer(from: ProcessInfo.processInfo.arguments)
        #else
        return nil
        #endif
    }

    /// Pestaña en la que arranca la app para una pantalla de depuración.
    static func tab(for screen: Screen) -> AppTab {
        switch screen {
        case .feed, .feedDemo, .feedEmpty: .feed
        case .extraer, .resultDemo, .resultPeople, .resultPeopleMask, .layersPeople, .layersDemo,
             .resultDemoPerson, .resultDemoPeople, .resultDemoPeopleMask: .extraer
        case .rejilla, .explorar: .rejilla
        case .jardin, .ajustes: .jardin
        }
    }

    /// Pestaña para el valor crudo de `-uiScreen`: la de su pantalla si se reconoce y, si no,
    /// por prefijo («rejilla-demo» → Rejilla, «jardin-demo» → Jardín, «extraer-…» → Extraer),
    /// para que cada pestaña pueda añadir sus propios atajos sin tocar este enum.
    static func tab(forRawScreen value: String) -> AppTab? {
        if let screen = screen(from: [argument, value]) { return tab(for: screen) }
        for tab in AppTab.allCases where value == tab.rawValue || value.hasPrefix(tab.rawValue + "-") {
            return tab
        }
        return nil
    }

    /// Pestaña inicial para unos argumentos de proceso (Feed sin atajo).
    static func initialTab(from arguments: [String]) -> AppTab {
        guard let i = arguments.firstIndex(of: argument), i + 1 < arguments.count else { return .feed }
        return tab(forRawScreen: arguments[i + 1]) ?? .feed
    }

    /// Pestaña inicial del proceso actual (siempre Feed en Release).
    static var initialTab: AppTab {
        #if DEBUG
        return initialTab(from: ProcessInfo.processInfo.arguments)
        #else
        return .feed
        #endif
    }

    /// Foto de grupo del bundle (solo existe en Debug).
    static func groupPhoto(bundle: Bundle = .main) -> CGImage? {
        guard let url = bundle.url(forResource: groupPhotoResource, withExtension: "png") else { return nil }
        return try? ImageLoading.cgImage(from: url)
    }

    /// Pantalla pedida por los argumentos del proceso; siempre nil en Release.
    static var requested: Screen? {
        #if DEBUG
        return screen(from: ProcessInfo.processInfo.arguments)
        #else
        return nil
        #endif
    }
}

/// Imágenes sintéticas en memoria (demo y tests): bloques con los colores
/// sRGB8 exactos de una combinación, sin ruido.
enum SyntheticImage {
    struct RGB: Equatable, Sendable {
        let r: UInt8
        let g: UInt8
        let b: UInt8
    }

    /// `size` x `size` px en una rejilla `grid` x `grid` de bloques; el bloque
    /// k lleva el color k mod n (2 colores => franjas verticales).
    static func blocks(colors: [RGB], size: Int = 256, grid: Int = 4) -> CGImage? {
        guard !colors.isEmpty, size > 0, grid > 0 else { return nil }
        let cell = max(1, size / grid)
        var rgb = [UInt8](repeating: 0, count: size * size * 3)
        for y in 0..<size {
            for x in 0..<size {
                let c = colors[((y / cell) * grid + (x / cell)) % colors.count]
                let i = (y * size + x) * 3
                rgb[i] = c.r
                rgb[i + 1] = c.g
                rgb[i + 2] = c.b
            }
        }
        return PPMImage(width: size, height: size, rgb: rgb).makeCGImage()
    }

    /// Bloques con los colores de la combinación `comboId`; nil si no existe.
    static func blocks(comboId: Int, dictionary: WadaDictionary, size: Int = 256) -> CGImage? {
        let colors = dictionary.colors(ofComboId: comboId).compactMap { c -> RGB? in
            guard c.rgb.count == 3, c.rgb.allSatisfy({ (0...255).contains($0) }) else { return nil }
            return RGB(r: UInt8(c.rgb[0]), g: UInt8(c.rgb[1]), b: UInt8(c.rgb[2]))
        }
        return blocks(colors: colors, size: size)
    }
}
