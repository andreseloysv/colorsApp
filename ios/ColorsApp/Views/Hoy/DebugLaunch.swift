// Argumento de lanzamiento de depuración (solo DEBUG): `-uiScreen result-demo`
// abre Resultado con el análisis de una imagen sintética de la combinación 12;
// `-uiScreen explorar-<id>` abre el detalle de esa combinación y
// `-uiScreen ajustes` la pantalla de Ajustes (empujada, sin cambiar de pestaña). Lo consume
// HoyView (primera pestaña) empujando la ruta en su NavigationStack, así el
// verificador captura la pantalla sin navegar:
//   xcrun simctl launch <udid> com.andreseloy.colorsapp -uiScreen result-demo
import Foundation
import CoreGraphics

enum DebugLaunch {
    enum Screen: Equatable, Sendable {
        case resultDemo
        case explorar(Int)
        case ajustes
    }

    static let argument = "-uiScreen"
    static let demoComboId = 12

    static func screen(from arguments: [String]) -> Screen? {
        guard let i = arguments.firstIndex(of: argument), i + 1 < arguments.count else { return nil }
        let value = arguments[i + 1]
        if value == "result-demo" { return .resultDemo }
        if value == "ajustes" { return .ajustes }
        if value.hasPrefix("explorar-"), let id = Int(value.dropFirst("explorar-".count)) { return .explorar(id) }
        return nil
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
