// Argumento de lanzamiento de depuración (solo DEBUG): `-uiScreen result-demo`
// abre Resultado con el análisis de una imagen sintética de la combinación 12;
// `-uiScreen explorar-<id>` abre el detalle de esa combinación y
// `-uiScreen ajustes` la pantalla de Ajustes (empujada, sin cambiar de pestaña).
// Recorte de sujeto y capas:
//   `result-people`       Resultado de la foto de grupo embebida en Debug
//                         (harness/people/06_group_courier_street.png) con los ajustes actuales
//   `result-people-mask`  lo mismo con "Ver máscara" activado
//   `layers-people`       inspector de capas de esa foto de grupo
//   `layers-demo`         inspector de capas de la escena sintética con una persona
//                         (SyntheticPersonScene: pose y cara sin Vision, cadena real del motor)
//   `result-demo-person`  Resultado de esa escena sintética
//   `result-demo-people`  Resultado de la escena sintética con dos personas (fila "Personas")
//   `result-demo-people-mask`  lo mismo con "Ver máscara" activado
// y `-uiLayer <n>` desplaza el inspector a la capa n (1...11). Lo consume HoyView
// (primera pestaña) empujando la ruta en su NavigationStack, así el verificador
// captura la pantalla sin navegar:
//   xcrun simctl launch <udid> com.andreseloy.colorsapp -uiScreen layers-demo -uiLayer 6
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
