// Escena sintética con personas (atajos -uiScreen layers-demo / result-demo-* y
// tests del inspector de capas): fondo con distractores, una figura de frente con camiseta
// Green Blue y pantalón Isabella Color (combinación Nº 012 de Wada), escote y
// cuello de piel, antebrazos y manos de piel, pelo y zapatos oscuros; su máscara
// de persona, una pose de 15 puntos y la zona de muestra de piel de la cara.
// Todo con aritmética entera por píxel y un ruido LCG determinista (±5 por
// canal): los mismos bytes en cualquier plataforma, sin Vision ni CoreGraphics.
// Así la cadena real (regiones de la pose, piel adaptativa) y el motor corren
// sobre algo que se parece a una foto, también en el simulador donde Vision no
// está disponible.
import Foundation
import CoreGraphics
import ColorEngine
import SubjectKit

struct SyntheticPersonScene: Sendable {
    static let width = 300
    static let height = 400

    let width: Int
    let height: Int
    /// width * height * 3 bytes sRGB.
    let rgb: [UInt8]
    /// Máscara de persona (0/255) de cada figura.
    let personMasks: [[UInt8]]
    /// Muestra de piel de la cara de cada figura (mejillas y frente, sin ojos ni boca).
    let faceSamples: [[UInt8]]
    let poses: [Pose]

    /// Máscara de la primera figura.
    var personMask: [UInt8] { personMasks[0] }
    var faceSample: [UInt8] { faceSamples[0] }
    var pose: Pose { poses[0] }

    var ppm: PPMImage { PPMImage(width: width, height: height, rgb: rgb) }
    var image: CGImage? { ppm.makeCGImage() }

    /// La primera figura tal como la entregaría la detección (id de instancia 1).
    var person: PersonInstance { people[0] }

    /// Todas las figuras como personas detectadas (ids 1...n).
    var people: [PersonInstance] {
        personMasks.indices.map { i in
            PersonInstance(id: i + 1, mask: personMasks[i], width: width, height: height, pose: poses[i],
                           faceSampleMask: faceSamples[i])
        }
    }

    typealias RGB = (r: Int, g: Int, b: Int)

    /// Una figura: desplazamiento horizontal y colores de la ropa.
    struct Figure: Sendable {
        let dx: Int
        let shirt: RGB
        let trousers: RGB
    }

    // Colores (sRGB8). Camiseta y pantalón: colores 12 de Wada (Green Blue, Isabella Color).
    static let shirt = (r: 9, g: 145, b: 151)
    static let trousers = (r: 197, g: 165, b: 110)
    static let skin = (r: 201, g: 139, b: 102)
    static let hair = (r: 59, g: 42, b: 32)
    static let shoes = (r: 38, g: 38, b: 40)
    static let wall = (r: 217, g: 211, b: 199)
    static let floor = (r: 139, g: 76, b: 61)
    static let sign = (r: 227, g: 190, b: 42)
    static let plant = (r: 79, g: 123, b: 58)
    static let eye = (r: 30, g: 24, b: 22)
    static let mouth = (r: 150, g: 70, b: 70)
    /// Segunda figura de `makeTwo` (camisa Grenadine Red y pantalón azul marino oscuro).
    static let shirt2 = (r: 229, g: 77, b: 66)
    static let trousers2 = (r: 44, g: 57, b: 84)

    /// Una persona en 300 × 400 px (fixtures de LayersInspectorTests: no cambiar sin regenerarlas).
    static func make() -> SyntheticPersonScene {
        make(width: width, figures: [Figure(dx: 0, shirt: shirt, trousers: trousers)])
    }

    /// Dos personas del mismo tamaño, sin solaparse, en 500 × 400 px (atajos -uiScreen
    /// result-demo-people*: fila "Personas"). Misma cobertura: la primera es la de id 1.
    static func makeTwo() -> SyntheticPersonScene {
        make(width: 500, figures: [Figure(dx: 0, shirt: shirt, trousers: trousers),
                                   Figure(dx: 200, shirt: shirt2, trousers: trousers2)])
    }

    static func make(width w: Int, figures: [Figure]) -> SyntheticPersonScene {
        let h = height
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        var persons = [[UInt8]](repeating: [UInt8](repeating: 0, count: w * h), count: figures.count)
        var samples = persons

        // Puntos de la pose (píxeles; la izquierda de la persona queda a la derecha de la imagen).
        let nose = (150, 80), neck = (150, 112)
        let ls = (195, 122), rs = (105, 122)
        let le = (222, 180), re = (78, 180)
        let lw = (232, 236), rw = (68, 236)
        let lh = (178, 238), rh = (122, 238)
        let lk = (172, 305), rk = (128, 305)
        let la = (170, 368), ra = (130, 368)
        let root = (150, 238)

        func d2(_ x: Int, _ y: Int, _ p: (Int, Int)) -> Int { (x - p.0) * (x - p.0) + (y - p.1) * (y - p.1) }
        /// (x, y) dentro de la cápsula a-b de radio r (centro del píxel).
        func capsule(_ x: Int, _ y: Int, _ a: (Int, Int), _ b: (Int, Int), _ r: Int) -> Bool {
            let px = Double(x) + 0.5, py = Double(y) + 0.5
            let ax = Double(a.0), ay = Double(a.1), bx = Double(b.0), by = Double(b.1)
            let vx = bx - ax, vy = by - ay
            let len2 = vx * vx + vy * vy
            var t = len2 > 0 ? ((px - ax) * vx + (py - ay) * vy) / len2 : 0
            t = max(0, min(1, t))
            let dx = px - (ax + t * vx), dy = py - (ay + t * vy)
            return dx * dx + dy * dy <= Double(r * r)
        }

        var state: UInt32 = 0x1234_5678
        func noise() -> Int {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Int(state >> 24) % 11 - 5
        }

        for y in 0..<h {
            for gx in 0..<w {
                // Fondo.
                var c = y < 320 ? wall : floor
                if gx >= 222, gx < 290, y >= 28, y < 92 { c = sign }
                if d2(gx, y, (36, 292)) <= 30 * 30 || d2(gx, y, (58, 262)) <= 20 * 20 { c = plant }
                var owner = -1
                var isSample = false
                for (fi, figure) in figures.enumerated() {
                    let x = gx - figure.dx
                    guard x >= 0 else { continue }
                    var inPerson = false
                    var sample = false
                    var fc = c
                    // Piernas y pelvis (pantalón), zapatos.
                    if capsule(x, y, lh, lk, 19) || capsule(x, y, lk, la, 16) || capsule(x, y, rh, rk, 19)
                        || capsule(x, y, rk, ra, 16) || (x >= 110 && x < 190 && y >= 228 && y < 256) {
                        fc = figure.trousers
                        inPerson = true
                    }
                    if d2(x, y, (la.0 + 4, la.1 + 10)) <= 13 * 13 || d2(x, y, (ra.0 - 4, ra.1 + 10)) <= 13 * 13 {
                        fc = shoes
                        inPerson = true
                    }
                    // Antebrazos y manos (piel), mangas (camiseta).
                    if capsule(x, y, le, lw, 11) || capsule(x, y, re, rw, 11)
                        || d2(x, y, (lw.0 + 3, lw.1 + 12)) <= 11 * 11 || d2(x, y, (rw.0 - 3, rw.1 + 12)) <= 11 * 11 {
                        fc = skin
                        inPerson = true
                    }
                    if capsule(x, y, ls, le, 15) || capsule(x, y, rs, re, 15) {
                        fc = figure.shirt
                        inPerson = true
                    }
                    // Torso (camiseta) con escote en V de piel.
                    if x >= 100, x < 200, y >= 116, y < 244 {
                        fc = figure.shirt
                        inPerson = true
                        let vTop = 116, vBottom = 156
                        if y < vBottom {
                            let half = (vBottom - y) * 16 / (vBottom - vTop)
                            if abs(x - 150) < half { fc = skin }
                        }
                    }
                    // Cuello, cabeza, pelo, ojos, boca.
                    if x >= 139, x < 161, y >= 96, y < 120 {
                        fc = skin
                        inPerson = true
                    }
                    if d2(x, y, nose) <= 27 * 27 {
                        fc = skin
                        inPerson = true
                        if d2(x, y, (150, 84)) <= 15 * 15 { sample = true }
                    }
                    if d2(x, y, (150, 68)) <= 28 * 28 && y < 64 {
                        fc = hair
                        inPerson = true
                        sample = false
                    }
                    if d2(x, y, (140, 76)) <= 3 * 3 || d2(x, y, (160, 76)) <= 3 * 3 {
                        fc = eye
                        sample = false
                    }
                    if x >= 143, x < 157, y >= 92, y < 96 {
                        fc = mouth
                        sample = false
                    }
                    c = fc
                    if inPerson {
                        owner = fi
                        isSample = sample
                    }
                }
                let o = (y * w + gx) * 3
                rgb[o] = UInt8(max(0, min(255, c.r + noise())))
                rgb[o + 1] = UInt8(max(0, min(255, c.g + noise())))
                rgb[o + 2] = UInt8(max(0, min(255, c.b + noise())))
                if owner >= 0 {
                    persons[owner][y * w + gx] = 255
                    if isSample { samples[owner][y * w + gx] = 255 }
                }
            }
        }

        let points: [(Joint, (Int, Int))] = [
            (.nose, nose), (.neck, neck), (.leftShoulder, ls), (.rightShoulder, rs), (.leftElbow, le),
            (.rightElbow, re), (.leftWrist, lw), (.rightWrist, rw), (.leftHip, lh), (.rightHip, rh),
            (.leftKnee, lk), (.rightKnee, rk), (.leftAnkle, la), (.rightAnkle, ra), (.root, root),
        ]
        let poses: [Pose] = figures.map { figure in
            var pose = Pose()
            for (joint, p) in points {
                pose[joint] = Keypoint(x: Double(p.0 + figure.dx), y: Double(p.1), confidence: 0.9)
            }
            return pose
        }
        return SyntheticPersonScene(width: w, height: h, rgb: rgb, personMasks: persons, faceSamples: samples, poses: poses)
    }
}
