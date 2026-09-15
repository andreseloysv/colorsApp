// Muestra de piel de la cara a partir de landmarks: mejillas y frente como
// polígonos convexos, sin ojos, cejas, labios ni pelo. Solo geometría; el
// modelo de piel (media y covarianza en Lab) lo ajusta el motor C.
//
// Marco afín de la cara: P(s, t) = M + s·h + t·w, con M el punto medio de los
// centros de los ojos, h = (ojo B − ojo A)/2 (s = ±1 cae en cada ojo) y
// w = centro de la boca − M (t = 1 cae en la boca). Al ser afín sigue el giro
// (roll), la escala y el escorzo de una cara de medio perfil sin trigonometría.
//
// Proporciones (antropometría media: distancia interpupilar d ≈ 63 mm,
// ojo–boca ≈ 1,1·d, alas de la nariz ≈ 0,55·d de ancho, boca ≈ 0,8·d):
//   - Mejilla (lado σ = ±1): cuadrilátero (0,62σ, 0,28), (1,38σ, 0,28),
//     (1,32σ, 0,72), (0,68σ, 0,72): por debajo del párpado y las ojeras
//     (t ≥ 0,28), fuera de la nariz (|s| ≥ 0,62), por encima del surco
//     nasogeniano y de la comisura al sonreír (t ≤ 0,72) y dentro del
//     contorno (|s| ≤ 1,38). Se recorta además con la envolvente convexa de
//     `faceContour` (en un medio perfil la mejilla lejana sale de la cara).
//   - Frente: franja del marco s ∈ [−0,8, 0,8], t ∈ [c − 0,32, c − 0,08]
//     con c el punto más alto de las cejas (t mínimo; −0,32 si no hay cejas):
//     justo encima de las cejas, lejos del nacimiento del pelo en una frente
//     media (~0,9·d). Se recorta con el rectángulo de la cara de Vision
//     ampliado un 5 % hacia arriba: en las fotos de harness/people ese borde
//     cae a la altura de las cejas o poco más arriba, y ampliarlo más metía
//     flequillo en la muestra (el pelo que quede lo mitiga la salvaguarda).
// Todo se intersecta con la máscara de la persona erosionada 2 px (>= 128 en
// todo el cuadrado 5x5): así el fondo y el pelo del contorno no entran.
import CoreGraphics

/// Landmarks de una cara en píxeles del raster (origen arriba-izquierda).
public struct FaceLandmarkPoints: Equatable, Sendable {
    public var leftEye: [CGPoint]
    public var rightEye: [CGPoint]
    public var leftEyebrow: [CGPoint]
    public var rightEyebrow: [CGPoint]
    public var outerLips: [CGPoint]
    public var faceContour: [CGPoint]
    /// Rectángulo de la cara de Vision en píxeles del raster.
    public var boundingBox: CGRect

    public init(leftEye: [CGPoint], rightEye: [CGPoint], leftEyebrow: [CGPoint] = [], rightEyebrow: [CGPoint] = [],
                outerLips: [CGPoint], faceContour: [CGPoint] = [], boundingBox: CGRect = .null) {
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.leftEyebrow = leftEyebrow
        self.rightEyebrow = rightEyebrow
        self.outerLips = outerLips
        self.faceContour = faceContour
        self.boundingBox = boundingBox
    }

    /// Centro para asociar la cara a una persona: centro del rectángulo de Vision
    /// o, sin él, punto medio entre los ojos.
    public var center: CGPoint {
        if !boundingBox.isNull, !boundingBox.isEmpty {
            return CGPoint(x: boundingBox.midX, y: boundingBox.midY)
        }
        let a = FaceSample.centroid(leftEye) ?? .zero, b = FaceSample.centroid(rightEye) ?? .zero
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

/// Polígonos de muestra de piel.
public enum FaceSample {
    /// Cuadrilátero de la mejilla en coordenadas (s, t) para el lado +1.
    static let cheek: [(s: Double, t: Double)] = [(0.62, 0.28), (1.38, 0.28), (1.32, 0.72), (0.68, 0.72)]
    static let foreheadHalfWidth = 0.8
    static let foreheadNear = 0.08
    static let foreheadFar = 0.32
    static let defaultBrowTop = -0.32
    /// Margen sobre el borde superior del rectángulo de la cara (fracción de su alto).
    static let foreheadBoxMargin = 0.05
    /// Erosión (px) de la máscara de persona al recortar la muestra: aleja la
    /// muestra del borde (fondo y pelo del contorno).
    static let personClipErosion = 2

    static func centroid(_ pts: [CGPoint]) -> CGPoint? {
        let valid = pts.filter { $0.x.isFinite && $0.y.isFinite }
        guard !valid.isEmpty else { return nil }
        var sx = 0.0, sy = 0.0
        for p in valid {
            sx += Double(p.x)
            sy += Double(p.y)
        }
        return CGPoint(x: sx / Double(valid.count), y: sy / Double(valid.count))
    }

    /// Polígonos (mejilla A, mejilla B, frente) en píxeles del raster; nil si
    /// faltan ojos o labios o el marco es degenerado (< 1 px o casi colineal).
    public static func polygons(_ lm: FaceLandmarkPoints) -> [[CGPoint]]? {
        guard let ea = centroid(lm.leftEye), let eb = centroid(lm.rightEye), let mouth = centroid(lm.outerLips) else {
            return nil
        }
        let mx = (Double(ea.x) + Double(eb.x)) / 2, my = (Double(ea.y) + Double(eb.y)) / 2
        let hx = (Double(eb.x) - Double(ea.x)) / 2, hy = (Double(eb.y) - Double(ea.y)) / 2
        let wx = Double(mouth.x) - mx, wy = Double(mouth.y) - my
        let hn = (hx * hx + hy * hy).squareRoot(), wn = (wx * wx + wy * wy).squareRoot()
        let det = hx * wy - hy * wx
        guard hn >= 0.5, wn >= 1, abs(det) >= 0.2 * hn * wn else { return nil }
        func point(_ s: Double, _ t: Double) -> CGPoint {
            CGPoint(x: mx + s * hx + t * wx, y: my + s * hy + t * wy)
        }
        func tCoord(_ p: CGPoint) -> Double {
            // Inversa de [h w]: t = (hx·(py − my) − hy·(px − mx)) / det.
            (hx * (Double(p.y) - my) - hy * (Double(p.x) - mx)) / det
        }
        let hull = MaskOps.convexHull(lm.faceContour)
        var result: [[CGPoint]] = []
        for sigma in [-1.0, 1.0] {
            var poly = cheek.map { point(sigma * $0.s, $0.t) }
            if hull.count >= 3 {
                poly = MaskOps.intersectConvex(poly, hull)
            }
            result.append(poly)
        }
        let brows = (lm.leftEyebrow + lm.rightEyebrow).filter { $0.x.isFinite && $0.y.isFinite }
        let browTop = brows.isEmpty ? defaultBrowTop : brows.map(tCoord).min() ?? defaultBrowTop
        let near = browTop - foreheadNear, far = browTop - foreheadFar
        var forehead = [point(-foreheadHalfWidth, near), point(foreheadHalfWidth, near),
                        point(foreheadHalfWidth, far), point(-foreheadHalfWidth, far)]
        if !lm.boundingBox.isNull, !lm.boundingBox.isEmpty {
            let box = lm.boundingBox
            let top = box.minY - foreheadBoxMargin * box.height
            let rect = [CGPoint(x: box.minX, y: top), CGPoint(x: box.maxX, y: top),
                        CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
            forehead = MaskOps.intersectConvex(forehead, rect)
        }
        result.append(forehead)
        return result
    }

    /// Máscara de muestra (255 dentro de mejillas o frente y de la persona); nil
    /// si no hay polígonos.
    public static func mask(_ lm: FaceLandmarkPoints, width: Int, height: Int, personMask: [UInt8]?) -> [UInt8]? {
        guard let polys = polygons(lm) else { return nil }
        return MaskOps.fillConvexPolygons(polys, width: width, height: height, clip: personMask,
                                          clipErosion: personMask == nil ? 0 : personClipErosion)
    }
}
