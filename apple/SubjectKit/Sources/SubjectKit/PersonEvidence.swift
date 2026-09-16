// Evidencia corporal de una instancia de persona: Vision
// (VNGeneratePersonInstanceMaskRequest) devuelve instancias en imágenes sin nadie
// (un PNG liso, bandas de color, texturas, sintéticos de la capa 3). Una instancia
// solo cuenta como persona si tiene evidencia de cuerpo; el resto es una «persona
// fantasma» y se descarta en la detección (paso `MaskFallback.rejectedPhantom`).
// Sin personas aceptadas la foto se analiza completa (docs/DECISIONS.md, ADR-010).
//
// Reglas, en orden (la primera que se cumple decide `PersonEvidence.kind`):
//   1. pose: al menos `minTorsoJoints` puntos del torso de la pose asociada
//      (cuello, hombros, caderas, raíz) con confianza >= `minConfidence` (la regla
//      del motor) dentro de la máscara binaria (>= 128) o a <= `jointRadius` px
//      (Chebyshev) de ella: los hombros caen a menudo en el borde de la silueta.
//   2. face: una cara de Vision asociada a la instancia (dentro de su máscara o,
//      como en harness/people/05, justo encima con el cuello y el pecho dentro). Con
//      `requireBodyForFaceOnly` (nueva, apagada por defecto) esa cara necesita además
//      CUERPO: el rectángulo de persona de la instancia debe ser el de esa cara
//      (`PersonSplitter.rectangleIsBody`) o tiene que haber algún punto del torso dentro;
//      si no, un retrato enmarcado o una pantalla con una cara cuenta como persona.
//   3. humanRectangle: sin pose ni cara, un rectángulo de persona de Vision
//      (VNDetectHumanRectanglesRequest, cuerpo entero, confianza >= `minHumanConfidence`)
//      asociado a la instancia (`associateHumanRectangles`: cada rectángulo va a la
//      instancia con más píxeles dentro) que contiene al menos `minHumanOverlap` de sus
//      píxeles, con esos píxeles cubriendo al menos `minHumanFill` del rectángulo. Es un
//      detector de personas independiente de la segmentación: no se activa con prendas.
//   4. shape: solo con `acceptShapeOnly` (DESACTIVADA por defecto): sin pose, cara ni
//      rectángulo, una silueta plausible: cobertura en [`shapeMinCoverage`,
//      `shapeMaxCoverage`] del raster, relación alto/ancho del bbox en [`shapeMinAspect`,
//      `shapeMaxAspect`], relleno del bbox (extent) <= `shapeMaxExtent`, solidez
//      (píxeles / área de la envolvente convexa) <= `shapeMaxSolidity` y alto del bbox <
//      `shapeMaxHeightSpan` del raster. Se desactivó tras la verificación: los vestidos y
//      monos colgados en percha tienen la misma forma que una persona (alto/ancho 1,3-1,4,
//      relleno 0,43-0,6, solidez 0,58-0,87) y Vision los devuelve como instancias.
//   5. none: fantasma.
// Medido (visionmask, macOS 26): ninguna de las 148 sintéticas sin personas de
// harness/people/nopeople (incluidas 48 prendas en percha, perchero, planas y en puerta),
// de los 20 PNG de sim_media ni de 100 sintéticos de la capa 3 tiene rectángulo de persona;
// las 18 personas de harness/people tienen pose (16) o cara (2).
// Solo geometría de máscaras, puntos y rectángulos (sin color): la web futura aplica las
// mismas reglas a las instancias de su segmentador y a su detector de personas.
import CoreGraphics
import ColorEngine

/// Umbrales de la evidencia corporal (`SubjectExtractor.bodyEvidence`).
public struct PhantomOptions: Equatable, Sendable {
    /// false: toda instancia que supere `minPersonCoverage` es persona (comportamiento anterior).
    public var enabled = true
    /// Puntos del torso (cuello, hombros, caderas, raíz) necesarios dentro de la máscara.
    public var minTorsoJoints = 2
    /// Confianza mínima de un punto (la de `RegionOptions.default`).
    public var minConfidence = RegionOptions.default.minConfidence
    /// Tolerancia (px, Chebyshev) alrededor de cada punto para contarlo dentro.
    public var jointRadius = 2
    /// Sin pose ni cara: cobertura mínima y máxima del raster.
    public var shapeMinCoverage = 0.01
    public var shapeMaxCoverage = 0.6
    /// Sin pose ni cara: relación alto/ancho del bbox.
    public var shapeMinAspect = 1.2
    public var shapeMaxAspect = 6.0
    /// Sin pose ni cara: fracción máxima del bbox cubierta por la máscara.
    public var shapeMaxExtent = 0.8
    /// Sin pose ni cara: fracción máxima de la envolvente convexa cubierta por la máscara.
    public var shapeMaxSolidity = 0.88
    /// Sin pose ni cara: el alto del bbox debe ser menor que esta fracción del alto del raster.
    public var shapeMaxHeightSpan = 0.95
    /// (Nuevo) Regla de forma sola (4): false por defecto. Una prenda colgada tiene forma de
    /// persona; sin pose, cara ni rectángulo de persona la instancia es fantasma.
    public var acceptShapeOnly = false
    /// (Nuevo) Pedir rectángulos de persona a Vision (`VNDetectHumanRectanglesRequest`) cuando
    /// alguna instancia no tiene pose ni cara (regla 3). false: sin regla 3.
    public var humanRectangles = true
    /// (Nuevo) Confianza mínima de un rectángulo de persona.
    public var minHumanConfidence = 0.3
    /// (Nuevo) Fracción mínima de los píxeles (>= 128) de la instancia dentro del rectángulo.
    public var minHumanOverlap = 0.5
    /// (Nuevo) Fracción mínima del área del rectángulo cubierta por esos píxeles.
    public var minHumanFill = 0.1
    /// (Nuevo, aditivo; false por defecto) La regla 2 (cara) exige además que la cara tenga
    /// CUERPO: un rectángulo de persona de Vision asociado a la instancia del que esa cara es
    /// la cabeza (`PersonSplitter.rectangleIsBody`) o al menos un punto del torso dentro de la
    /// máscara. Sin esto, un retrato enmarcado o una pantalla con una cara es una persona
    /// (medido en harness/people/faces: poster_alone y screen_alone dan 1 persona con
    /// evidencia `face` y ningún rectángulo de persona; las dos personas reales de
    /// harness/people/05 aceptadas por cara SÍ tienen su rectángulo). Cambia el
    /// comportamiento por defecto de la detección, así que se deja apagada hasta que la
    /// promueva quien mantiene la regla anti-fantasmas (visionmask: `--face-only-body`).
    public var requireBodyForFaceOnly = false

    public init(enabled: Bool = true, minTorsoJoints: Int = 2, minConfidence: Double = RegionOptions.default.minConfidence,
                jointRadius: Int = 2, shapeMinCoverage: Double = 0.01, shapeMaxCoverage: Double = 0.6,
                shapeMinAspect: Double = 1.2, shapeMaxAspect: Double = 6.0, shapeMaxExtent: Double = 0.8,
                shapeMaxSolidity: Double = 0.88, shapeMaxHeightSpan: Double = 0.95, acceptShapeOnly: Bool = false,
                humanRectangles: Bool = true, minHumanConfidence: Double = 0.3, minHumanOverlap: Double = 0.5,
                minHumanFill: Double = 0.1, requireBodyForFaceOnly: Bool = false) {
        self.enabled = enabled
        self.minTorsoJoints = minTorsoJoints
        self.minConfidence = minConfidence
        self.jointRadius = jointRadius
        self.shapeMinCoverage = shapeMinCoverage
        self.shapeMaxCoverage = shapeMaxCoverage
        self.shapeMinAspect = shapeMinAspect
        self.shapeMaxAspect = shapeMaxAspect
        self.shapeMaxExtent = shapeMaxExtent
        self.shapeMaxSolidity = shapeMaxSolidity
        self.shapeMaxHeightSpan = shapeMaxHeightSpan
        self.acceptShapeOnly = acceptShapeOnly
        self.humanRectangles = humanRectangles
        self.minHumanConfidence = minHumanConfidence
        self.minHumanOverlap = minHumanOverlap
        self.minHumanFill = minHumanFill
        self.requireBodyForFaceOnly = requireBodyForFaceOnly
    }

    public static var `default`: PhantomOptions { PhantomOptions() }
}

/// Evidencia corporal de una instancia y las medidas que la deciden.
public struct PersonEvidence: Equatable, Sendable {
    /// Qué regla la acepta (`none` = fantasma).
    /// `humanRectangle` es un caso nuevo (aditivo): los `switch` exhaustivos deben añadirlo.
    public enum Kind: String, Sendable {
        case pose, face, shape, none, humanRectangle
    }

    public let kind: Kind
    /// Puntos del torso utilizables dentro de la máscara (con la tolerancia).
    public let torsoJointsInside: Int
    /// Hay una cara de Vision asociada (`PersonInstance.faceBox`).
    public let hasFace: Bool
    /// Fracción del raster con máscara >= 128.
    public let coverage: Double
    /// Alto / ancho del bbox (0 con máscara vacía).
    public let aspect: Double
    /// Píxeles / área del bbox (0 con máscara vacía).
    public let extent: Double
    /// Píxeles / área de la envolvente convexa de los píxeles (como cuadrados de lado 1; 0 con máscara vacía).
    public let solidity: Double
    /// Alto del bbox / alto del raster (0 con máscara vacía).
    public let heightSpan: Double
    /// (Nuevo) Rectángulo de persona de Vision asociado (píxeles del raster); nil sin rectángulo.
    public let humanBox: CGRect?
    /// (Nuevo) Fracción de los píxeles de la instancia dentro de `humanBox` (0 sin rectángulo).
    public let humanOverlap: Double
    /// (Nuevo) Fracción del área de `humanBox` cubierta por la instancia (0 sin rectángulo).
    public let humanFill: Double
    /// (Nuevo) true si la regla de forma (4) aceptaría la silueta, esté o no activada.
    public let plausibleShape: Bool

    public init(kind: Kind, torsoJointsInside: Int, hasFace: Bool, coverage: Double, aspect: Double, extent: Double,
                solidity: Double, heightSpan: Double = 0, humanBox: CGRect? = nil, humanOverlap: Double = 0,
                humanFill: Double = 0, plausibleShape: Bool = false) {
        self.kind = kind
        self.torsoJointsInside = torsoJointsInside
        self.hasFace = hasFace
        self.coverage = coverage
        self.aspect = aspect
        self.extent = extent
        self.solidity = solidity
        self.heightSpan = heightSpan
        self.humanBox = humanBox
        self.humanOverlap = humanOverlap
        self.humanFill = humanFill
        self.plausibleShape = plausibleShape
    }

    public var isPerson: Bool { kind != .none }
}

/// Instancia de Vision descartada por no tener evidencia corporal.
public struct RejectedPerson: Sendable {
    public let instance: PersonInstance
    public let evidence: PersonEvidence

    public init(instance: PersonInstance, evidence: PersonEvidence) {
        self.instance = instance
        self.evidence = evidence
    }
}

extension SubjectExtractor {
    /// Puntos del torso que cuentan como evidencia de pose.
    public static let evidenceTorsoJoints: [Joint] = [.neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .root]

    /// Evidencia corporal de `person` en un raster `width` x `height` (ver cabecera), sin
    /// rectángulo de persona (reglas 1, 2 y, con `acceptShapeOnly`, 4).
    public static func bodyEvidence(for person: PersonInstance, width: Int, height: Int,
                                    options: PhantomOptions = .default) -> PersonEvidence {
        bodyEvidence(for: person, width: width, height: height, options: options, humanBox: nil)
    }

    /// Evidencia corporal con el rectángulo de persona asociado a esta instancia
    /// (`associateHumanRectangles`; nil = sin rectángulo).
    public static func bodyEvidence(for person: PersonInstance, width: Int, height: Int, options: PhantomOptions,
                                    humanBox: CGRect?) -> PersonEvidence {
        let stats = MaskOps.stats(person.mask, width: width, height: height)
        var joints = 0
        if let pose = person.pose {
            let r = max(0, options.jointRadius)
            for j in evidenceTorsoJoints {
                let k = pose[j]
                guard usable(k, minConfidence: options.minConfidence) else { continue }
                if nearMask(person.mask, width: width, height: height, x: k.x, y: k.y, radius: r) { joints += 1 }
            }
        }
        let hasFace = person.faceBox != nil
        var aspect = 0.0, extent = 0.0, solidity = 0.0, span = 0.0
        if stats.count > 0 {
            let w = Double(stats.bbox.width), h = Double(stats.bbox.height)
            aspect = h / w
            span = h / Double(height)
            extent = Double(stats.count) / (w * h)
            let hull = hullArea(person.mask, width: width, height: height)
            solidity = hull > 0 ? min(1, Double(stats.count) / hull) : 1
        }
        let shape = stats.count > 0 && stats.coverage >= options.shapeMinCoverage && stats.coverage <= options.shapeMaxCoverage
            && aspect >= options.shapeMinAspect && aspect <= options.shapeMaxAspect
            && extent <= options.shapeMaxExtent && solidity <= options.shapeMaxSolidity && span < options.shapeMaxHeightSpan
        var overlap = 0.0, fill = 0.0
        if let box = humanBox, stats.count > 0 {
            let inside = pixelsInside(person.mask, width: width, height: height, box: box)
            overlap = Double(inside) / Double(stats.count)
            let area = Double(box.width * box.height)
            fill = area > 0 ? Double(inside) / area : 0
        }
        let human = humanBox != nil && options.humanRectangles && overlap >= options.minHumanOverlap
            && fill >= options.minHumanFill
        // (Nuevo) Cara con cuerpo: el rectángulo de persona de esta instancia empieza a la
        // altura de la cara y baja por debajo de ella, o hay algún punto del torso dentro.
        let faceHasBody = !options.requireBodyForFaceOnly || joints >= 1
            || (person.faceBox.map { f in humanBox.map { PersonSplitter.rectangleIsBody(of: f, rect: $0) } ?? false } ?? false)
        let kind: PersonEvidence.Kind
        if joints >= max(1, options.minTorsoJoints) {
            kind = .pose
        } else if hasFace, faceHasBody {
            kind = .face
        } else if human {
            kind = .humanRectangle
        } else if options.acceptShapeOnly && shape {
            kind = .shape
        } else {
            kind = .none
        }
        return PersonEvidence(kind: kind, torsoJointsInside: joints, hasFace: hasFace, coverage: stats.coverage,
                              aspect: aspect, extent: extent, solidity: solidity, heightSpan: span,
                              humanBox: humanBox, humanOverlap: overlap, humanFill: fill, plausibleShape: shape)
    }

    /// Separa las personas con evidencia corporal de las fantasma (orden conservado), sin
    /// rectángulos de persona. Con `options.enabled == false` las acepta todas.
    public static func rejectPhantoms(_ people: [PersonInstance], width: Int, height: Int,
                                      options: PhantomOptions = .default)
        -> (people: [PersonInstance], rejected: [RejectedPerson]) {
        rejectPhantoms(people, width: width, height: height, options: options, humanBoxes: [])
    }

    /// `rejectPhantoms` con los rectángulos de persona de Vision (píxeles del raster, ya
    /// filtrados por confianza): cada uno se asocia a una instancia (`associateHumanRectangles`).
    public static func rejectPhantoms(_ people: [PersonInstance], width: Int, height: Int, options: PhantomOptions,
                                      humanBoxes: [CGRect]) -> (people: [PersonInstance], rejected: [RejectedPerson]) {
        guard options.enabled else { return (people, []) }
        let boxOf = associateHumanRectangles(options.humanRectangles ? humanBoxes : [], masks: people.map(\.mask),
                                             width: width, height: height)
        var kept: [PersonInstance] = []
        var rejected: [RejectedPerson] = []
        for (i, p) in people.enumerated() {
            let e = bodyEvidence(for: p, width: width, height: height, options: options,
                                 humanBox: boxOf[i].map { humanBoxes[$0] })
            if e.isPerson {
                kept.append(p)
            } else {
                rejected.append(RejectedPerson(instance: p, evidence: e))
            }
        }
        return (kept, rejected)
    }

    /// Para cada máscara, el índice del rectángulo de persona asociado (o nil): cada rectángulo
    /// va a la máscara con más píxeles (>= 128) dentro de él (desempate: la máscara anterior);
    /// si varios eligen la misma máscara se queda el de más píxeles dentro (desempate: el
    /// anterior). Un rectángulo sin píxeles dentro no se asocia.
    public static func associateHumanRectangles(_ boxes: [CGRect], masks: [[UInt8]], width: Int, height: Int) -> [Int?] {
        var result = [Int?](repeating: nil, count: masks.count)
        var best = [Int](repeating: 0, count: masks.count)
        for (bi, box) in boxes.enumerated() {
            var target = -1, count = 0
            for (mi, mask) in masks.enumerated() {
                let c = pixelsInside(mask, width: width, height: height, box: box)
                if c > count {
                    target = mi
                    count = c
                }
            }
            guard target >= 0 else { continue }
            if result[target] == nil || count > best[target] {
                result[target] = bi
                best[target] = count
            }
        }
        return result
    }

    /// Píxeles >= 128 cuyo centro (x + 0,5, y + 0,5) cae dentro de `box` (bordes incluidos).
    static func pixelsInside(_ mask: [UInt8], width: Int, height: Int, box: CGRect) -> Int {
        guard mask.count >= width * height, !box.isNull, box.width.isFinite, box.height.isFinite,
              box.minX.isFinite, box.minY.isFinite else { return 0 }
        let x0 = max(0, Int((Double(box.minX) - 0.5).rounded(.up))), x1 = min(width - 1, Int((Double(box.maxX) - 0.5).rounded(.down)))
        let y0 = max(0, Int((Double(box.minY) - 0.5).rounded(.up))), y1 = min(height - 1, Int((Double(box.maxY) - 0.5).rounded(.down)))
        guard x0 <= x1, y0 <= y1 else { return 0 }
        var n = 0
        mask.withUnsafeBufferPointer { m in
            for y in y0...y1 {
                let row = y * width
                for x in x0...x1 where m[row + x] >= MaskOps.insideThreshold { n += 1 }
            }
        }
        return n
    }

    /// true si algún píxel >= 128 cae a distancia de Chebyshev <= radius del píxel que contiene (x, y).
    static func nearMask(_ mask: [UInt8], width: Int, height: Int, x: Double, y: Double, radius: Int) -> Bool {
        guard x.isFinite, y.isFinite, abs(x) <= 1_048_576, abs(y) <= 1_048_576, mask.count >= width * height else {
            return false
        }
        let ix = Int(x.rounded(.down)), iy = Int(y.rounded(.down))
        for yy in (iy - radius)...(iy + radius) where yy >= 0 && yy < height {
            let row = yy * width
            for xx in (ix - radius)...(ix + radius) where xx >= 0 && xx < width {
                if mask[row + xx] >= MaskOps.insideThreshold { return true }
            }
        }
        return false
    }

    /// Área de la envolvente convexa de los píxeles >= 128 (esquinas de cada tramo por fila: los
    /// píxeles como cuadrados de lado 1). 0 con máscara vacía.
    static func hullArea(_ mask: [UInt8], width: Int, height: Int) -> Double {
        guard mask.count >= width * height else { return 0 }
        var pts: [CGPoint] = []
        mask.withUnsafeBufferPointer { m in
            for y in 0..<height {
                let row = y * width
                var first = -1, last = -1
                for x in 0..<width where m[row + x] >= MaskOps.insideThreshold {
                    if first < 0 { first = x }
                    last = x
                }
                if first >= 0 {
                    pts.append(CGPoint(x: first, y: y))
                    pts.append(CGPoint(x: last + 1, y: y))
                    pts.append(CGPoint(x: first, y: y + 1))
                    pts.append(CGPoint(x: last + 1, y: y + 1))
                }
            }
        }
        let hull = MaskOps.convexHull(pts)
        guard hull.count >= 3 else { return 0 }
        var area = 0.0
        for i in 0..<hull.count {
            let a = hull[i], b = hull[(i + 1) % hull.count]
            area += Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
        }
        return abs(area) / 2
    }
}
