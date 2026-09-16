// Separación de instancias fusionadas. VNGeneratePersonInstanceMaskRequest
// junta en una sola instancia a personas que se tocan o se solapan (en
// harness/people/07 varias mujeres; en una selfie apretada, los dos adultos
// hombro con hombro: el fallo que reportó el usuario con una foto suya). Las
// caras y las poses de Vision sí salen por persona: se usan como semillas y la
// geometría (qué píxel es de quién) la decide el motor C
// (`ce_mask_split_instance`) para que la web futura haga lo mismo.
//
// Semillas (píxeles del raster; "presente" = confianza >= 0,3, la de las regiones):
//   - Pose con cuello o dos hombros: eje desde el cuello (o el punto medio de
//     los hombros) hasta la raíz (o el punto medio de las dos caderas); sin
//     caderas, extrapolado hacia abajo (+y) 1,6 · anchura de hombros.
//     half_width = 0,55 · anchura de hombros, como mínimo 0,6 · ancho de su
//     cara si tiene. Anchura de hombros: |LS − RS| o, con un solo hombro,
//     2 · |hombro − cuello|. Sin anchura de hombros vale solo con cara: se
//     extrapola 3,0 · alto de cara y half_width = 1,1 · ancho de cara.
//   - Cara sin pose asociada (todas las de VNDetectFaceLandmarksRequest, con o
//     sin landmarks): eje desde la base del rectángulo (centro del borde
//     inferior) hacia abajo 3,0 · alto de la cara; half_width = 1,1 · ancho.
//   - Cara y pose son la misma persona si el centro de la cara está a menos de
//     0,8 · ancho de cara del cuello o de la nariz: una semilla (la de la pose)
//     con esa cara. Emparejamiento voraz por distancia creciente.
//   - (Nuevo, ADR-010) Una semilla de CARA sin pose solo cuenta si tiene
//     evidencia corporal (`SplitOptions.requireBodyForFaceSeeds`, por defecto
//     activa): un rectángulo de persona de Vision (VNDetectHumanRectanglesRequest)
//     que contenga el centro de la cara y baje al menos `faceSeedBodyBelow` altos
//     de cara por debajo de ella, o `faceSeedMinPoseJoints` puntos utilizables de
//     alguna pose dentro de su eje. Sin eso, una cara de póster, pantalla o
//     retrato pegada a una persona real creaba una PERSONA FANTASMA con la mitad
//     de la ropa de la persona de verdad (medido en harness/people/faces).
// Regla de separación, por instancia de Vision:
//   - Una semilla cuenta para una instancia si el centro de su cara está en la
//     máscara (>= 128) o hay un píxel >= 128 a distancia <= 0,25 · ancho de cara
//     del punto superior del eje (ancho de cara estimado 0,45 · anchura de
//     hombros si la pose no tiene cara) Y, además, al menos la mitad de las 17
//     muestras de su eje que caen en el raster están en la máscara (sin esto, 05
//     se separaba mal porque la barbilla de la chica central cae en la máscara de
//     su vecina). Una semilla puede contar para varias instancias (las máscaras
//     de Vision se pisan).
//   - Una instancia con 2 o más semillas se separa con ce_mask_split_instance
//     (semillas ordenadas por x del punto superior; como mucho 8, las de mayor
//     half_width). Además del eje, cada semilla con cara aporta un segmento de
//     cabeza del centro de la cara al punto superior del eje con half_width
//     0,5 · ancho de cara, mientras quepan en los 8 del motor (primero las caras
//     más anchas): sin él, el eje de una pose empieza en el cuello y la cara de
//     esa persona acababa en la de al lado (la selfie sintética daba una persona
//     con dos caras). Las etiquetas de los segmentos de una semilla son de su
//     persona. Cada semilla con cobertura >= `minSplitCoverage` del raster es una
//     parte de su persona; las menores se reasignan a la semilla conservada
//     vecina (4-vecindad) con más píxeles (sin vecina, a la mayor). Si quedan
//     menos de 2, la instancia no se toca. Cada parte conserva el valor de Vision
//     en sus píxeles (>= 128); el borde suave (< 128) se descarta.
//   - Una PersonInstance nueva por semilla (id nuevo, splitFrom = id de Vision
//     de su parte mayor, pose, cara y rectángulo de cara de la semilla, bbox y
//     cobertura recalculados) con la unión de sus partes. Una instancia sin
//     separar cuyas semillas ya están todas en personas separadas se une a la de
//     más eje dentro.
//   - Las instancias que no se separan asocian pose y cara como antes
//     (`associatePoses` / `associateFacesDetailed`) con las poses y caras que no
//     se usaron.
//   - Personas ordenadas por cobertura; como mucho 8.
// Después de separar, la regla anti-fantasmas (`PersonEvidence`) se aplica a
// TODAS las personas resultantes: una persona separada lleva su pose o su cara,
// así que la evidencia sigue siendo la del contrato de ADR-010.
import CoreGraphics
import ColorEngine

/// Origen de una semilla.
public enum SeedKind: String, Sendable {
    case pose
    case face
}

/// Umbrales de la separación de instancias (`PersonSplitter.apply`).
public struct SplitOptions: Equatable, Sendable {
    /// false: no se separa ninguna instancia (comportamiento anterior a ADR-010bis).
    public var enabled = true
    /// Cobertura mínima (fracción del raster) de una persona separada.
    public var minSplitCoverage = 0.005
    /// Personas como mucho tras separar (el motor admite 8 semillas).
    public var maxPeople = 8
    /// (Nuevo) Una semilla de CARA sin pose necesita evidencia corporal: rectángulo
    /// de persona de Vision o puntos de pose dentro de su eje. Evita la persona
    /// fantasma de un póster, una pantalla o un retrato detrás de una persona real.
    public var requireBodyForFaceSeeds = true
    /// Altos de cara que el rectángulo de persona debe bajar por debajo de la cara
    /// para valer como evidencia corporal de una semilla de cara.
    public var faceSeedBodyBelow = 1.0
    /// El rectángulo debe EMPEZAR a la altura de esa cara (es su cabeza): como mucho
    /// estos altos de cara por encima de su borde superior (pelo, gorro, sombrero).
    /// Sin esta condición, el rectángulo de la persona de verdad valida una cara
    /// estampada en su camiseta o la de una pantalla que sostiene (medido en
    /// harness/people/faces: poster_on_torso daba dos personas).
    public var faceSeedBodyTopAbove = 1.0
    /// ... y como mucho estos altos de cara por debajo (la cara no puede quedar encima
    /// del rectángulo).
    public var faceSeedBodyTopBelow = 0.5
    /// Puntos utilizables de una pose que NO es semilla, por debajo de la cara y dentro
    /// del eje de la semilla, que valen como evidencia corporal alternativa.
    public var faceSeedMinPoseJoints = 2

    public init(enabled: Bool = true, minSplitCoverage: Double = 0.005, maxPeople: Int = 8,
                requireBodyForFaceSeeds: Bool = true, faceSeedBodyBelow: Double = 1.0,
                faceSeedBodyTopAbove: Double = 1.0, faceSeedBodyTopBelow: Double = 0.5,
                faceSeedMinPoseJoints: Int = 2) {
        self.enabled = enabled
        self.minSplitCoverage = minSplitCoverage
        self.maxPeople = maxPeople
        self.requireBodyForFaceSeeds = requireBodyForFaceSeeds
        self.faceSeedBodyBelow = faceSeedBodyBelow
        self.faceSeedBodyTopAbove = faceSeedBodyTopAbove
        self.faceSeedBodyTopBelow = faceSeedBodyTopBelow
        self.faceSeedMinPoseJoints = faceSeedMinPoseJoints
    }

    public static var `default`: SplitOptions { SplitOptions() }
}

/// Semilla de persona con su origen (pose y/o cara).
public struct SubjectSeed: Equatable, Sendable {
    /// Eje y semiancho que recibe el motor.
    public var seed: PersonSeed
    public var kind: SeedKind
    /// Pose de la semilla (solo `.pose`).
    public var pose: Pose?
    /// Cara de la semilla (`.face`, o la cara fusionada con la pose).
    public var face: FaceLandmarkPoints?
    /// Ancho de cara (real o estimado) para dilatar la máscara al asignar la semilla.
    public var faceWidth: Double
    /// Índice en las poses / caras de la detección (nil en semillas construidas a mano).
    public var poseIndex: Int?
    public var faceIndex: Int?
    /// (Nuevo) Evidencia corporal de una semilla de cara: `.none` la descarta.
    /// Siempre `.pose` en las semillas de pose.
    public var bodyEvidence: SeedBodyEvidence = .pose

    public init(seed: PersonSeed, kind: SeedKind, pose: Pose? = nil, face: FaceLandmarkPoints? = nil,
                faceWidth: Double, poseIndex: Int? = nil, faceIndex: Int? = nil,
                bodyEvidence: SeedBodyEvidence = .pose) {
        self.seed = seed
        self.kind = kind
        self.pose = pose
        self.face = face
        self.faceWidth = faceWidth
        self.poseIndex = poseIndex
        self.faceIndex = faceIndex
        self.bodyEvidence = bodyEvidence
    }

    /// Punto superior del eje (cuello o base de la cara).
    public var top: CGPoint { CGPoint(x: seed.x0, y: seed.y0) }
}

/// (Nuevo) Qué acredita que detrás de una semilla hay un cuerpo.
public enum SeedBodyEvidence: String, Sendable {
    /// La semilla viene de una pose (el cuerpo es la propia pose).
    case pose
    /// Rectángulo de persona de Vision que contiene la cara y baja por debajo de ella.
    case humanRectangle
    /// Puntos utilizables de alguna pose dentro del eje de la semilla.
    case poseJoints
    /// Ninguna: cara sin cuerpo (póster, pantalla, retrato). La semilla se descarta.
    case none
}

/// Una instancia de Vision que se separó.
public struct InstanceSplit: Sendable {
    /// `PersonInstance.id` de la instancia de Vision.
    public let instanceId: Int
    /// Máscara de Vision de la instancia (la entrada de ce_mask_split_instance).
    public let mask: [UInt8]
    /// Semillas (personas) de la instancia, ordenadas por x del punto superior.
    public let seeds: [SubjectSeed]
    /// Segmentos pasados al motor: primero el eje de cada semilla (mismo orden) y
    /// después el segmento de cabeza de las semillas con cara.
    public let segments: [PersonSeed]
    /// Semilla (índice en `seeds`) de cada segmento.
    public let segmentOwner: [Int]
    /// Salida de ce_mask_split_instance (0 fondo, k + 1 = segmento k), antes de reasignar etiquetas pequeñas.
    public let labels: [UInt8]
    /// Píxeles de cada semilla (suma de sus segmentos; índice 0 = semilla 0).
    public let labelPixels: [Int]
    /// Para cada semilla, el id de la persona nueva que la contiene (nil si su etiqueta quedó vacía).
    public let personIdBySeed: [Int?]
    /// Ids de las personas nuevas, en orden de etiqueta.
    public let personIds: [Int]
    /// `.splitByPose` si todas las semillas conservadas son de pose, `.splitByFace` si alguna es de cara.
    public let step: MaskFallback

    public init(instanceId: Int, mask: [UInt8], seeds: [SubjectSeed], segments: [PersonSeed], segmentOwner: [Int],
                labels: [UInt8], labelPixels: [Int], personIdBySeed: [Int?], personIds: [Int], step: MaskFallback) {
        self.instanceId = instanceId
        self.mask = mask
        self.seeds = seeds
        self.segments = segments
        self.segmentOwner = segmentOwner
        self.labels = labels
        self.labelPixels = labelPixels
        self.personIdBySeed = personIdBySeed
        self.personIds = personIds
        self.step = step
    }
}

/// Resultado de aplicar la separación a las instancias de Vision.
public struct SplitOutcome: Sendable {
    /// Personas finales (ordenadas por cobertura, como mucho `SplitOptions.maxPeople`).
    public let people: [PersonInstance]
    /// Cara de cada persona (mismo orden que `people`), nil sin cara.
    public let faces: [FaceLandmarkPoints?]
    /// Instancias separadas.
    public let splits: [InstanceSplit]
    /// Semillas que se usaron (marcadas con su `bodyEvidence`), en el orden en que
    /// las recorre `seedInstance`. Vacío con `SplitOptions.enabled == false`.
    public let seeds: [SubjectSeed]
    /// Instancia principal de Vision (índice en `instances`) de cada semilla de
    /// `seeds`, nil si no cuenta para ninguna.
    public let seedInstance: [Int?]
    /// Ids de instancias sin separar unidas a una persona separada (solo contenían semillas ya separadas).
    public let absorbedInstances: [Int]
    /// Poses y caras de la detección que no acabaron en ninguna persona.
    public let unassignedPoses: Int
    public let unassignedFaces: Int
    /// (Nuevo) Semillas de cara descartadas por no tener evidencia corporal.
    public let faceSeedsWithoutBody: [SubjectSeed]

    public init(people: [PersonInstance], faces: [FaceLandmarkPoints?], splits: [InstanceSplit],
                seeds: [SubjectSeed] = [], seedInstance: [Int?], absorbedInstances: [Int], unassignedPoses: Int,
                unassignedFaces: Int, faceSeedsWithoutBody: [SubjectSeed] = []) {
        self.people = people
        self.faces = faces
        self.splits = splits
        self.seeds = seeds
        self.seedInstance = seedInstance
        self.absorbedInstances = absorbedInstances
        self.unassignedPoses = unassignedPoses
        self.unassignedFaces = unassignedFaces
        self.faceSeedsWithoutBody = faceSeedsWithoutBody
    }
}

public enum PersonSplitter {
    public static let poseHalfWidthFactor = 0.55
    public static let poseMinHalfWidthFaceFactor = 0.6
    public static let hipExtrapolationFactor = 1.6
    public static let faceAxisFactor = 3.0
    public static let faceHalfWidthFactor = 1.1
    public static let faceMatchFactor = 0.8
    public static let dilationFaceFactor = 0.25
    /// Ancho de cara estimado por anchura de hombros (articulaciones) cuando la pose no tiene cara.
    public static let faceWidthPerShoulderWidth = 0.45
    /// Cobertura mínima (fracción del raster) de una persona separada (`SplitOptions.minSplitCoverage`).
    public static let minSplitCoverage = SplitOptions.default.minSplitCoverage
    /// Personas como mucho tras separar.
    public static let maxPeople = SplitOptions.default.maxPeople

    // MARK: - Semillas

    /// La semilla cabe en el contrato del motor (coordenadas finitas con |v| <=
    /// CE_POSE_COORD_MAX, 0 < half_width <= CE_POSE_COORD_MAX); las que no, se descartan.
    public static func engineAccepts(_ s: PersonSeed) -> Bool {
        let limit = 1_048_576.0
        return [s.x0, s.y0, s.x1, s.y1].allSatisfy { $0.isFinite && abs($0) <= limit }
            && s.halfWidth > 0 && s.halfWidth <= limit
    }

    static func usable(_ k: Keypoint, _ minConfidence: Double) -> CGPoint? {
        guard k.confidence.isFinite, k.confidence > 0, k.confidence >= minConfidence, k.x.isFinite, k.y.isFinite,
              abs(k.x) <= 1_048_576, abs(k.y) <= 1_048_576 else { return nil }
        return CGPoint(x: k.x, y: k.y)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x) - Double(b.x), dy = Double(a.y) - Double(b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Rectángulo utilizable de una cara (nil si es nulo, vacío o no finito).
    static func box(_ face: FaceLandmarkPoints) -> CGRect? {
        let b = face.boundingBox
        guard !b.isNull, !b.isEmpty, b.minX.isFinite, b.minY.isFinite, b.width.isFinite, b.height.isFinite,
              b.width > 0, b.height > 0 else { return nil }
        return b
    }

    /// Geometría de la pose: punto superior, anchura de hombros y punto inferior (si hay caderas).
    static func poseAxis(_ pose: Pose, minConfidence: Double) -> (top: CGPoint, shoulderWidth: Double?, bottom: CGPoint?)? {
        let neck = usable(pose[.neck], minConfidence)
        let ls = usable(pose[.leftShoulder], minConfidence), rs = usable(pose[.rightShoulder], minConfidence)
        let top: CGPoint
        if let neck {
            top = neck
        } else if let ls, let rs {
            top = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
        } else {
            return nil
        }
        var sw: Double? = nil
        if let ls, let rs {
            sw = distance(ls, rs)
        } else if let neck, let s = ls ?? rs {
            sw = 2 * distance(s, neck)
        }
        if let w = sw, !(w >= 1) { sw = nil }
        var bottom: CGPoint? = nil
        if let root = usable(pose[.root], minConfidence) {
            bottom = root
        } else if let lh = usable(pose[.leftHip], minConfidence), let rh = usable(pose[.rightHip], minConfidence) {
            bottom = CGPoint(x: (lh.x + rh.x) / 2, y: (lh.y + rh.y) / 2)
        }
        return (top, sw, bottom)
    }

    /// Semillas de poses y caras según las reglas de la cabecera. Orden: poses
    /// (en el orden de Vision) y luego caras sin pose. Sin evidencia corporal:
    /// las semillas de cara se marcan (`bodyEvidence`) pero no se filtran aquí.
    public static func seeds(poses: [Pose], faces: [FaceLandmarkPoints],
                             minConfidence: Double = RegionOptions.default.minConfidence) -> [SubjectSeed] {
        let axes = poses.map { poseAxis($0, minConfidence: minConfidence) }
        // Emparejamiento cara-pose (voraz por distancia).
        var pairs: [(d: Double, pose: Int, face: Int)] = []
        for (fi, face) in faces.enumerated() {
            guard let fb = box(face) else { continue }
            let fw = Double(fb.width)
            for (pi, axis) in axes.enumerated() where axis != nil {
                var d = Double.infinity
                if let neck = usable(poses[pi][.neck], minConfidence) { d = min(d, distance(face.center, neck)) }
                if let nose = usable(poses[pi][.nose], minConfidence) { d = min(d, distance(face.center, nose)) }
                if d < faceMatchFactor * fw { pairs.append((d, pi, fi)) }
            }
        }
        pairs.sort { ($0.d, $0.pose, $0.face) < ($1.d, $1.pose, $1.face) }
        var faceOfPose = [Int?](repeating: nil, count: poses.count)
        var poseOfFace = [Int?](repeating: nil, count: faces.count)
        for p in pairs where faceOfPose[p.pose] == nil && poseOfFace[p.face] == nil {
            faceOfPose[p.pose] = p.face
            poseOfFace[p.face] = p.pose
        }
        var out: [SubjectSeed] = []
        var usedFace = [Bool](repeating: false, count: faces.count)
        for (pi, axis) in axes.enumerated() {
            guard let axis else { continue }
            let face = faceOfPose[pi].map { faces[$0] }
            let fbox = face.flatMap { box($0) }
            let fw = fbox.map { Double($0.width) }
            let fh = fbox.map { Double($0.height) }
            var bottom: CGPoint
            var hw: Double
            var faceWidth: Double
            if let sw = axis.shoulderWidth {
                bottom = axis.bottom ?? CGPoint(x: axis.top.x, y: axis.top.y + hipExtrapolationFactor * sw)
                hw = poseHalfWidthFactor * sw
                if let fw { hw = max(hw, poseMinHalfWidthFaceFactor * fw) }
                faceWidth = fw ?? faceWidthPerShoulderWidth * sw
            } else if let fw, let fh {
                bottom = axis.bottom ?? CGPoint(x: axis.top.x, y: axis.top.y + faceAxisFactor * fh)
                hw = faceHalfWidthFactor * fw
                faceWidth = fw
            } else {
                continue
            }
            let seed = PersonSeed(x0: Double(axis.top.x), y0: Double(axis.top.y), x1: Double(bottom.x),
                                  y1: Double(bottom.y), halfWidth: hw)
            guard engineAccepts(seed) else { continue }
            if let f = faceOfPose[pi] { usedFace[f] = true }
            out.append(SubjectSeed(seed: seed, kind: .pose, pose: poses[pi], face: face, faceWidth: faceWidth,
                                   poseIndex: pi, faceIndex: faceOfPose[pi], bodyEvidence: .pose))
        }
        for (fi, face) in faces.enumerated() where !usedFace[fi] {
            guard let b = box(face) else { continue }
            let fw = Double(b.width), fh = Double(b.height)
            guard Double(b.midX).isFinite, Double(b.maxY).isFinite else { continue }
            let x = Double(b.midX), y = Double(b.maxY)
            let seed = PersonSeed(x0: x, y0: y, x1: x, y1: y + faceAxisFactor * fh, halfWidth: faceHalfWidthFactor * fw)
            guard engineAccepts(seed) else { continue }
            out.append(SubjectSeed(seed: seed, kind: .face, face: face, faceWidth: fw, faceIndex: fi,
                                   bodyEvidence: .none))
        }
        return out
    }

    // MARK: - Evidencia corporal de las semillas de cara (ADR-010)

    /// Evidencia corporal de una semilla de cara: `.humanRectangle` si algún
    /// rectángulo de persona de Vision es EL CUERPO DE ESA CARA (contiene su centro,
    /// empieza a su altura — entre `faceSeedBodyTopAbove` altos de cara por encima y
    /// `faceSeedBodyTopBelow` por debajo de su borde superior — y baja al menos
    /// `faceSeedBodyBelow` altos de cara por debajo de ella); `.poseJoints` si al menos
    /// `options.faceSeedMinPoseJoints` puntos utilizables de una pose que NO es semilla
    /// (`otherPoses`) caen por debajo de la cara y dentro del eje de la semilla
    /// (distancia <= half_width); `.none` si no hay ninguna de las dos. Las semillas de
    /// pose devuelven `.pose`.
    public static func bodyEvidence(for seed: SubjectSeed, humanBoxes: [CGRect], poses otherPoses: [Pose],
                                    options: SplitOptions = .default,
                                    minConfidence: Double = RegionOptions.default.minConfidence) -> SeedBodyEvidence {
        if seed.kind == .pose { return .pose }
        guard let face = seed.face, let b = box(face) else { return .none }
        if humanBoxes.contains(where: { rectangleIsBody(of: b, rect: $0, options: options) }) {
            return .humanRectangle
        }
        // Puntos de una pose sin semilla dentro del eje del cuerpo (por debajo de la barbilla).
        for pose in otherPoses {
            var joints = 0
            for joint in ColorEngine.Joint.allCases {
                guard let p = usable(pose[joint], minConfidence) else { continue }
                guard Double(p.y) >= Double(b.maxY) else { continue }
                if distanceToAxis(seed.seed, x: Double(p.x), y: Double(p.y)) <= seed.seed.halfWidth { joints += 1 }
            }
            if joints >= max(1, options.faceSeedMinPoseJoints) { return .poseJoints }
        }
        return .none
    }

    /// true si `rect` (rectángulo de persona de Vision) es EL CUERPO de la cara `face`:
    /// contiene su centro, empieza a su altura (entre `faceSeedBodyTopAbove` altos de cara
    /// por encima y `faceSeedBodyTopBelow` por debajo de su borde superior) y baja al menos
    /// `faceSeedBodyBelow` altos de cara por debajo de ella. La misma prueba vale para una
    /// semilla de cara y para una instancia cuya única evidencia es una cara
    /// (`PhantomOptions.requireBodyForFaceOnly`).
    public static func rectangleIsBody(of face: CGRect, rect r: CGRect, options: SplitOptions = .default) -> Bool {
        guard !face.isNull, !face.isEmpty, !r.isNull, r.width.isFinite, r.height.isFinite, r.minX.isFinite,
              r.minY.isFinite else { return false }
        let h = Double(face.height)
        guard h > 0 else { return false }
        return r.contains(CGPoint(x: face.midX, y: face.midY))
            && Double(r.maxY) >= Double(face.maxY) + options.faceSeedBodyBelow * h
            && Double(r.minY) >= Double(face.minY) - options.faceSeedBodyTopAbove * h
            && Double(r.minY) <= Double(face.minY) + options.faceSeedBodyTopBelow * h
    }

    /// Distancia del punto al eje de la semilla (proyección acotada), la misma
    /// geometría que `ce_mask_split_instance`.
    static func distanceToAxis(_ s: PersonSeed, x: Double, y: Double) -> Double {
        let dx = s.x1 - s.x0, dy = s.y1 - s.y0, dd = dx * dx + dy * dy
        let qx = x - s.x0, qy = y - s.y0
        var t = 0.0
        if dd > 0 {
            t = (qx * dx + qy * dy) / dd
            t = min(1, max(0, t))
        }
        let ex = qx - t * dx, ey = qy - t * dy
        return (ex * ex + ey * ey).squareRoot()
    }

    /// Marca la evidencia corporal de cada semilla (`bodyEvidence`) y, con
    /// `options.requireBodyForFaceSeeds`, devuelve aparte las de cara sin cuerpo.
    public static func screenFaceSeeds(_ seeds: [SubjectSeed], humanBoxes: [CGRect], poses: [Pose],
                                       options: SplitOptions = .default,
                                       minConfidence: Double = RegionOptions.default.minConfidence)
        -> (kept: [SubjectSeed], rejected: [SubjectSeed]) {
        var kept: [SubjectSeed] = [], rejected: [SubjectSeed] = []
        // Una pose que ya es semilla es el cuerpo de SU cara, no el de otra.
        let seedPoses = Set(seeds.compactMap { $0.kind == .pose ? $0.poseIndex : nil })
        let others = poses.indices.filter { !seedPoses.contains($0) }.map { poses[$0] }
        for var s in seeds {
            s.bodyEvidence = bodyEvidence(for: s, humanBoxes: humanBoxes, poses: others, options: options,
                                          minConfidence: minConfidence)
            if options.requireBodyForFaceSeeds && s.kind == .face && s.bodyEvidence == .none {
                rejected.append(s)
            } else {
                kept.append(s)
            }
        }
        return (kept, rejected)
    }

    /// Semiancho del segmento de cabeza en anchos de cara.
    public static let headHalfWidthFactor = 0.5

    /// Segmento de cabeza de una semilla con cara: del centro de la cara al punto
    /// superior del eje (cuello o barbilla), half_width = 0,5 · ancho de cara. Sin
    /// él la cabeza queda lejos del eje de su pose (que empieza en el cuello) y la
    /// cara acababa en la persona de al lado. nil sin cara.
    public static func headSegment(_ s: SubjectSeed) -> PersonSeed? {
        guard let f = s.face, let b = box(f) else { return nil }
        let fw = Double(b.width)
        let cx = Double(b.midX), cy = Double(b.midY)
        let head = PersonSeed(x0: cx, y0: cy, x1: s.seed.x0, y1: s.seed.y0, halfWidth: headHalfWidthFactor * fw)
        return engineAccepts(head) ? head : nil
    }

    // MARK: - Semillas de cada instancia

    /// Muestras del eje para medir qué parte cae dentro de una instancia.
    public static let axisSamples = 17
    /// Fracción mínima del eje dentro de la instancia para que la semilla cuente.
    public static let minAxisInside = 0.5

    /// Relación de una semilla con una instancia.
    public struct Membership: Equatable, Sendable {
        /// El centro de la cara está dentro de la máscara (>= 128).
        public var faceInside: Bool
        /// El punto superior del eje está dentro de la máscara (>= 128).
        public var topInside: Bool
        /// Distancia del punto superior al centro del píxel >= 128 más cercano
        /// (0 si está dentro; infinito si no hay ninguno a <= 0,25 · ancho de cara).
        public var topDistance: Double
        /// Fracción de las `axisSamples` muestras del eje (dentro del raster) con máscara >= 128.
        public var axisInside: Double
        /// Regla del contrato: cara dentro o punto superior en la máscara dilatada.
        public var touches: Bool { faceInside || topDistance.isFinite }
        /// La semilla cuenta para la instancia: `touches` y al menos `minAxisInside` del eje dentro.
        public var counts: Bool { touches && axisInside >= PersonSplitter.minAxisInside }
    }

    public static func membership(_ s: SubjectSeed, mask: [UInt8], width: Int, height: Int) -> Membership {
        guard width >= 1, height >= 1, mask.count >= width * height else {
            return Membership(faceInside: false, topInside: false, topDistance: .infinity, axisInside: 0)
        }
        func inside(_ x: Double, _ y: Double) -> Bool {
            MaskOps.value(mask, width: width, height: height, x: x, y: y) >= MaskOps.insideThreshold
        }
        var faceIn = false
        if let f = s.face {
            faceIn = inside(Double(f.center.x), Double(f.center.y))
        }
        let tx = s.seed.x0, ty = s.seed.y0
        let topIn = inside(tx, ty)
        var dist = topIn ? 0 : Double.infinity
        let r = max(0, dilationFaceFactor * s.faceWidth)
        if !topIn, tx.isFinite, ty.isFinite, r.isFinite, abs(tx) < 1e7, abs(ty) < 1e7, r < 1e7 {
            let x0 = max(0, Int((tx - r - 1).rounded(.down))), x1 = min(width - 1, Int((tx + r + 1).rounded(.up)))
            let y0 = max(0, Int((ty - r - 1).rounded(.down))), y1 = min(height - 1, Int((ty + r + 1).rounded(.up)))
            if x0 <= x1, y0 <= y1 {
                for y in y0...y1 {
                    for x in x0...x1 where mask[y * width + x] >= MaskOps.insideThreshold {
                        let dx = Double(x) + 0.5 - tx, dy = Double(y) + 0.5 - ty
                        let d = (dx * dx + dy * dy).squareRoot()
                        if d <= r && d < dist { dist = d }
                    }
                }
            }
        }
        var total = 0, hits = 0
        for i in 0..<axisSamples {
            let t = Double(i) / Double(axisSamples - 1)
            let x = s.seed.x0 + t * (s.seed.x1 - s.seed.x0), y = s.seed.y0 + t * (s.seed.y1 - s.seed.y0)
            guard x.isFinite, y.isFinite, x >= 0, y >= 0, x < Double(width), y < Double(height) else { continue }
            total += 1
            if inside(x, y) { hits += 1 }
        }
        return Membership(faceInside: faceIn, topInside: topIn, topDistance: dist,
                          axisInside: total > 0 ? Double(hits) / Double(total) : 0)
    }

    /// `counted[s][i]`: la semilla s cuenta para la instancia i.
    public static func countedSeeds(_ seeds: [SubjectSeed], masks: [[UInt8]], width: Int,
                                    height: Int) -> [[Membership]] {
        seeds.map { s in masks.map { membership(s, mask: $0, width: width, height: height) } }
    }

    /// Instancia principal de cada semilla (la que cuenta con más eje dentro;
    /// desempate: cara dentro, punto superior dentro, menor distancia, anterior), o nil.
    static func primaryInstance(_ ms: [Membership]) -> Int? {
        var best: Int? = nil
        for (i, m) in ms.enumerated() where m.counts {
            if let b = best {
                let bm = ms[b]
                let bk = (bm.axisInside, bm.faceInside ? 1 : 0, bm.topInside ? 1 : 0, -bm.topDistance)
                let mk = (m.axisInside, m.faceInside ? 1 : 0, m.topInside ? 1 : 0, -m.topDistance)
                if !(mk > bk) { continue }
            }
            best = i
        }
        return best
    }

    // MARK: - Separación

    /// Separa las instancias de Vision (`instances`: máscaras con sus ids; pose y
    /// cara se ignoran) con las semillas y asocia poses y caras al resto. `poses`
    /// y `faces` son todas las observaciones (las semillas guardan sus índices;
    /// en semillas construidas a mano pueden ir vacías). `humanBoxes`: rectángulos
    /// de persona de Vision para la evidencia corporal de las semillas de cara.
    /// Lanza los errores del motor.
    public static func apply(instances: [PersonInstance], poses: [Pose], faces: [FaceLandmarkPoints],
                             seeds allSeeds: [SubjectSeed], width: Int, height: Int,
                             humanBoxes: [CGRect] = [], options: SplitOptions = .default) throws -> SplitOutcome {
        let count = width * height
        let screened = screenFaceSeeds(allSeeds, humanBoxes: humanBoxes, poses: poses, options: options)
        let seeds = options.enabled ? screened.kept : []
        let masks = instances.map(\.mask)
        let member = countedSeeds(seeds, masks: masks, width: width, height: height)
        let seedInstance = member.map(primaryInstance)
        let minPixels = Int((max(0, options.minSplitCoverage) * Double(count)).rounded(.up))
        let maxSeeds = min(splitMaxSeeds, max(1, options.maxPeople))

        // 1. Separación de cada instancia con 2 o más semillas.
        struct Part { let instance: Int; let seed: Int; let mask: [UInt8]; let pixels: Int }
        var parts: [Part] = []
        struct PendingSplit {
            let instance: Int; let seeds: [Int]; let segments: [PersonSeed]; let owner: [Int]
            let labels: [UInt8]; let pixels: [Int]; let kept: [Int]
        }
        var pending: [PendingSplit] = []
        for (ii, inst) in instances.enumerated() {
            var mine = seeds.indices.filter { member[$0][ii].counts }
            guard mine.count >= 2 else { continue }
            if mine.count > maxSeeds {
                mine = Array(mine.sorted { (seeds[$0].seed.halfWidth, -$0) > (seeds[$1].seed.halfWidth, -$1) }
                    .prefix(maxSeeds))
            }
            mine.sort { (seeds[$0].seed.x0, seeds[$0].seed.y0, $0) < (seeds[$1].seed.x0, seeds[$1].seed.y0, $1) }
            let n = mine.count
            var segments = mine.map { seeds[$0].seed }
            var owner = Array(0..<n)
            // Cabezas: de las semillas con cara, de mayor a menor ancho de cara mientras quepan.
            let withFace = (0..<n).filter { headSegment(seeds[mine[$0]]) != nil }
                .sorted { faceWidthKey(seeds[mine[$0]], $0) > faceWidthKey(seeds[mine[$1]], $1) }
            for j in withFace.prefix(splitMaxSeeds - n).sorted() {
                segments.append(headSegment(seeds[mine[j]])!)
                owner.append(j)
            }
            let r = try splitInstance(mask: inst.mask, width: width, height: height, seeds: segments)
            // Etiqueta de semilla (1...n) por píxel.
            var ownerOfLabel = [UInt8](repeating: 0, count: segments.count + 1)
            for (k, o) in owner.enumerated() { ownerOfLabel[k + 1] = UInt8(o + 1) }
            var lab = [UInt8](repeating: 0, count: count)
            var pixels = [Int](repeating: 0, count: n + 1)
            r.labels.withUnsafeBufferPointer { raw in
                for i in 0..<count {
                    let o = ownerOfLabel[Int(raw[i])]
                    lab[i] = o
                    pixels[Int(o)] += 1
                }
            }
            let kept = (1...n).filter { pixels[$0] >= minPixels }
            guard kept.count >= 2 else { continue }
            // Semillas pequeñas (con píxeles) -> vecina conservada (4-vecindad) con más píxeles.
            var target = [Int](0...n)
            let small = (1...n).filter { pixels[$0] > 0 && pixels[$0] < minPixels }
            if !small.isEmpty {
                var touches = [[Bool]](repeating: [Bool](repeating: false, count: n + 1), count: n + 1)
                lab.withUnsafeBufferPointer { lb in
                    for y in 0..<height {
                        for x in 0..<width {
                            let a = Int(lb[y * width + x])
                            guard a != 0 else { continue }
                            if x + 1 < width {
                                let b = Int(lb[y * width + x + 1])
                                if b != 0 && b != a { touches[a][b] = true; touches[b][a] = true }
                            }
                            if y + 1 < height {
                                let b = Int(lb[(y + 1) * width + x])
                                if b != 0 && b != a { touches[a][b] = true; touches[b][a] = true }
                            }
                        }
                    }
                }
                let largest = kept.max { (pixels[$0], -$0) < (pixels[$1], -$1) }!
                for sm in small {
                    let neighbors = kept.filter { touches[sm][$0] }
                    target[sm] = neighbors.max { (pixels[$0], -$0) < (pixels[$1], -$1) } ?? largest
                }
            }
            for k in kept {
                var m = [UInt8](repeating: 0, count: count)
                var np = 0
                lab.withUnsafeBufferPointer { lb in
                    inst.mask.withUnsafeBufferPointer { src in
                        for i in 0..<count where lb[i] != 0 && target[Int(lb[i])] == k {
                            m[i] = src[i]
                            np += 1
                        }
                    }
                }
                parts.append(Part(instance: ii, seed: mine[k - 1], mask: m, pixels: np))
            }
            var finalTarget = [Int](repeating: 0, count: n)
            for j in 1...n where pixels[j] > 0 { finalTarget[j - 1] = target[j] }
            pending.append(PendingSplit(instance: ii, seeds: mine, segments: segments, owner: owner, labels: r.labels,
                                        pixels: Array(pixels.dropFirst()), kept: finalTarget))
        }
        let splitInstanceIndices = Set(pending.map(\.instance))

        // 2. Una persona por semilla: une (máximo por píxel) sus partes de varias
        //    instancias (las máscaras de Vision se pisan) y, si una instancia sin
        //    separar solo contiene semillas ya separadas en otra, la une a la de
        //    más eje dentro (Vision dio dos instancias de la misma persona).
        var seedOrder: [Int] = []
        for p in parts where !seedOrder.contains(p.seed) { seedOrder.append(p.seed) }
        var mergedMask: [Int: [UInt8]] = [:]
        var mergedFrom: [Int: (instance: Int, pixels: Int)] = [:]
        for p in parts {
            if var m = mergedMask[p.seed] {
                for i in 0..<count where p.mask[i] > m[i] { m[i] = p.mask[i] }
                mergedMask[p.seed] = m
            } else {
                mergedMask[p.seed] = p.mask
            }
            if let f = mergedFrom[p.seed], f.pixels >= p.pixels { continue }
            mergedFrom[p.seed] = (p.instance, p.pixels)
        }
        var absorbed = Set<Int>()
        for (ii, inst) in instances.enumerated() where !splitInstanceIndices.contains(ii) {
            let mine = seeds.indices.filter { member[$0][ii].counts }
            guard !mine.isEmpty, mine.allSatisfy({ mergedMask[$0] != nil }) else { continue }
            let host = mine.max { (member[$0][ii].axisInside, -$0) < (member[$1][ii].axisInside, -$1) }!
            var m = mergedMask[host]!
            for i in 0..<count where inst.mask[i] >= MaskOps.insideThreshold && inst.mask[i] > m[i] { m[i] = inst.mask[i] }
            mergedMask[host] = m
            absorbed.insert(ii)
        }
        var nextId = (instances.map(\.id).max() ?? 0) + 1
        var idBySeed: [Int: Int] = [:]
        var usedPoses = Set<Int>(), usedFaces = Set<Int>()
        var all: [(person: PersonInstance, face: FaceLandmarkPoints?)] = []
        for si in seedOrder {
            let s = seeds[si]
            let m = mergedMask[si]!
            let id = nextId
            nextId += 1
            idBySeed[si] = id
            let sample = s.face.flatMap { FaceSample.mask($0, width: width, height: height, personMask: m) }
            all.append((PersonInstance(id: id, mask: m, width: width, height: height, pose: s.pose,
                                       faceSampleMask: sample, faceBox: s.face.flatMap { box($0) },
                                       splitFrom: instances[mergedFrom[si]!.instance].id), s.face))
            if let p = s.poseIndex { usedPoses.insert(p) }
            if let f = s.faceIndex { usedFaces.insert(f) }
        }
        let splits = pending.map { ps -> InstanceSplit in
            let ids = ps.seeds.indices.map { j -> Int? in
                ps.kept[j] == 0 ? nil : idBySeed[ps.seeds[ps.kept[j] - 1]]
            }
            var personIds: [Int] = []
            for id in ids.compactMap({ $0 }) where !personIds.contains(id) { personIds.append(id) }
            let anyFace = ps.seeds.indices.contains { j in ps.kept[j] == j + 1 && seeds[ps.seeds[j]].kind == .face }
            return InstanceSplit(instanceId: instances[ps.instance].id, mask: instances[ps.instance].mask,
                                 seeds: ps.seeds.map { seeds[$0] }, segments: ps.segments, segmentOwner: ps.owner,
                                 labels: ps.labels, labelPixels: ps.pixels,
                                 personIdBySeed: ids, personIds: personIds, step: anyFace ? .splitByFace : .splitByPose)
        }

        // 3. Instancias sin separar: asociación de siempre con las poses y caras libres.
        let rest = instances.indices.filter { !splitInstanceIndices.contains($0) && !absorbed.contains($0) }
        let freePoses = poses.indices.filter { !usedPoses.contains($0) }
        let freeFaces = faces.indices.filter { !usedFaces.contains($0) }
        let restMasks = rest.map { instances[$0].mask }
        let poseOf = SubjectExtractor.associatePoses(freePoses.map { poses[$0] }, masks: restMasks, width: width,
                                                     height: height)
        let faceLinks = SubjectExtractor.associateFacesDetailed(freeFaces.map { faces[$0] }, masks: restMasks,
                                                                width: width, height: height)
        for (k, ii) in rest.enumerated() {
            let inst = instances[ii]
            let pose = poseOf[k].map { poses[freePoses[$0]] }
            var face: FaceLandmarkPoints? = nil
            var sample: [UInt8]? = nil
            if let link = faceLinks[k] {
                let fi = freeFaces[link.face]
                face = faces[fi]
                // Solo la cara DIRECTA (dentro de su instancia) da muestra de piel:
                // recortar una cara de arriba con la máscara blanda metía pelo y fondo.
                if link.direct {
                    sample = FaceSample.mask(faces[fi], width: width, height: height, personMask: inst.mask)
                }
                usedFaces.insert(fi)
            }
            if let p = poseOf[k] { usedPoses.insert(freePoses[p]) }
            all.append((PersonInstance(id: inst.id, mask: inst.mask, coverage: inst.coverage, bbox: inst.bbox,
                                       pose: pose, faceSampleMask: sample, faceBox: face.flatMap { box($0) }), face))
        }
        let order = SubjectExtractor.sortPeople(all.map(\.person))
        var faceById: [Int: FaceLandmarkPoints] = [:]
        for e in all { if let f = e.face { faceById[e.person.id] = f } }
        let people = Array(order.prefix(max(1, options.maxPeople)))
        return SplitOutcome(people: people, faces: people.map { faceById[$0.id] }, splits: splits, seeds: seeds,
                            seedInstance: seedInstance, absorbedInstances: absorbed.sorted().map { instances[$0].id },
                            unassignedPoses: poses.count - usedPoses.count,
                            unassignedFaces: faces.count - usedFaces.count,
                            faceSeedsWithoutBody: options.enabled ? screened.rejected : [])
    }

    /// Clave de orden de las cabezas: ancho de cara y, a igualdad, el índice menor.
    static func faceWidthKey(_ s: SubjectSeed, _ index: Int) -> (Double, Int) {
        ((s.face.flatMap { box($0) }.map { Double($0.width) }) ?? 0, -index)
    }
}
