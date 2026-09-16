// Parámetros de la región que se derivan de la detección antes de llamar al
// motor: caderas estimadas en planos medios, opciones de la silueta de la pose
// y altura del recorte de cabeza a partir de la cara. Solo preparan ENTRADAS de
// las funciones del motor (puntos de pose, opciones, fracción): la geometría
// de las máscaras sigue en ce_mask_clothing_regions / ce_mask_cut_head, así que
// cada capa se reproduce con `ce regions` / `ce cut-head` (repro.sh de
// visionmask). La web futura debe aplicar estas mismas reglas (ADR-010).
import CoreGraphics
import ColorEngine

extension SubjectExtractor {
    /// Fracción de `cutHead` sin cara (y mínima con cara).
    public static let headCutFraction = 0.18
    /// Fracción máxima de `cutHead` (la del motor).
    public static let maxHeadCutFraction = 0.5
    /// Con cara, el corte cae en su borde inferior + este factor por su alto (cuello).
    public static let headCutNeckFactor = 0.25
    /// Caderas estimadas: distancia de la línea de hombros a la de caderas, en
    /// anchos de hombros. En las poses completas de harness/people la distancia
    /// perpendicular mide 1,32–1,78 anchos de frente (más de perfil): 1,2 queda
    /// del lado corto y no llega al cinturón ni a lo que haya en el regazo.
    public static let estimatedTorsoLength = 1.2
    /// Caderas estimadas: separación relativa a la de los hombros (0,59–0,89 medido).
    public static let estimatedHipWidth = 0.75
    /// Silueta de la pose: ancho total de las cápsulas (anchos de hombros).
    public static let silhouetteLimbWidth = 1.0
    /// Silueta de la pose: margen del torso (anchos de hombros).
    public static let silhouetteTorsoMargin = 0.35
    /// Detección: una instancia con menos de esta fracción del raster (>= 128) se
    /// descarta (fragmentos; con 1024 x 683 son < 350 px).
    public static let minPersonCoverage = 0.0005

    /// Regla de "punto utilizable" del motor (ce_mask_clothing_regions).
    static func usable(_ k: Keypoint, minConfidence: Double) -> Bool {
        k.confidence.isFinite && k.confidence > 0 && k.confidence >= minConfidence && k.x.isFinite && k.y.isFinite
            && abs(k.x) <= 1_048_576 && abs(k.y) <= 1_048_576
    }

    /// Par izquierda/derecha con la simetría del motor (P_falta = 2·medio − P_otro).
    /// Devuelve los dos puntos y la menor confianza usada, o nil.
    static func pair(_ pose: Pose, _ l: Joint, _ r: Joint, _ mid: Joint, minConfidence: Double)
        -> (left: (x: Double, y: Double), right: (x: Double, y: Double), confidence: Double)? {
        let L = pose[l], R = pose[r], M = pose[mid]
        let uL = usable(L, minConfidence: minConfidence), uR = usable(R, minConfidence: minConfidence)
        let uM = usable(M, minConfidence: minConfidence)
        if uL && uR { return ((L.x, L.y), (R.x, R.y), min(L.confidence, R.confidence)) }
        if uL && uM { return ((L.x, L.y), (2 * M.x - L.x, 2 * M.y - L.y), min(L.confidence, M.confidence)) }
        if uR && uM { return ((2 * M.x - R.x, 2 * M.y - R.y), (R.x, R.y), min(R.confidence, M.confidence)) }
        return nil
    }

    /// Pose que se entrega a `clothingRegions`.
    ///
    /// Si el motor puede formar las caderas (las dos, o una más la raíz) la pose
    /// no cambia. Si no, pero sí los hombros (los dos, o uno más el cuello) con
    /// ancho sw = |S_R − S_L| >= 1 px, se ESTIMAN (plano medio: caderas fuera del
    /// encuadre u ocultas):
    ///   - M = (S_L + S_R)/2; n = (−(S_R.y − S_L.y), S_R.x − S_L.x)/sw, normal a la
    ///     línea de hombros, orientada lejos de la nariz si la nariz es utilizable
    ///     y no está sobre esa línea; si no, hacia abajo en la imagen (n.y > 0;
    ///     con n.y == 0, n.x > 0).
    ///   - Raíz R = M + estimatedTorsoLength·sw·n; H_L = R + estimatedHipWidth·(S_L − M),
    ///     H_R = R + estimatedHipWidth·(S_R − M); confianza = la menor de las usadas
    ///     para los hombros.
    ///   - Rodillas y tobillos se borran (sin cápsulas de piernas desde caderas
    ///     inventadas): la región es torso superior + brazos, sin cabeza ni manos.
    /// Devuelve la pose y si se estimaron las caderas.
    public static func regionPose(_ pose: Pose, minConfidence: Double = RegionOptions.default.minConfidence)
        -> (pose: Pose, hipsEstimated: Bool) {
        guard pose.joints.count == Joint.allCases.count else { return (pose, false) }
        if pair(pose, .leftHip, .rightHip, .root, minConfidence: minConfidence) != nil { return (pose, false) }
        guard let s = pair(pose, .leftShoulder, .rightShoulder, .neck, minConfidence: minConfidence) else {
            return (pose, false)
        }
        let dx = s.right.x - s.left.x, dy = s.right.y - s.left.y
        let sw = (dx * dx + dy * dy).squareRoot()
        guard sw.isFinite, sw >= 1 else { return (pose, false) }
        let mx = (s.left.x + s.right.x) / 2, my = (s.left.y + s.right.y) / 2
        var nx = -dy / sw, ny = dx / sw
        var oriented = false
        let nose = pose[.nose]
        if usable(nose, minConfidence: minConfidence) {
            let side = nx * (nose.x - mx) + ny * (nose.y - my)
            if side > 0 {
                nx = -nx
                ny = -ny
                oriented = true
            } else if side < 0 {
                oriented = true
            }
        }
        if !oriented && (ny < 0 || (ny == 0 && nx < 0)) {
            nx = -nx
            ny = -ny
        }
        let d = estimatedTorsoLength * sw
        let rx = mx + d * nx, ry = my + d * ny
        let conf = s.confidence
        var out = pose
        out[.root] = Keypoint(x: rx, y: ry, confidence: conf)
        out[.leftHip] = Keypoint(x: rx + estimatedHipWidth * (s.left.x - mx), y: ry + estimatedHipWidth * (s.left.y - my),
                                 confidence: conf)
        out[.rightHip] = Keypoint(x: rx + estimatedHipWidth * (s.right.x - mx), y: ry + estimatedHipWidth * (s.right.y - my),
                                  confidence: conf)
        for j in [Joint.leftKnee, .rightKnee, .leftAnkle, .rightAnkle] { out[j] = .missing }
        return (out, true)
    }

    /// Opciones de la silueta de la pose: las de la región con los brazos enteros
    /// (antebrazos incluidos) si la región incluye brazos, piernas enteras,
    /// cápsulas de al menos `silhouetteLimbWidth` y margen del torso de al menos
    /// `silhouetteTorsoMargin` (misma confianza mínima). Sigue sin cabeza ni manos.
    public static func silhouetteOptions(_ o: RegionOptions) -> RegionOptions {
        RegionOptions(minConfidence: o.minConfidence, torsoMargin: max(o.torsoMargin, silhouetteTorsoMargin),
                      limbWidth: max(o.limbWidth, silhouetteLimbWidth), includeUpperArms: o.includeUpperArms,
                      includeForearms: o.includeUpperArms, includeLegs: true, includeLowerLegs: true)
    }

    /// Opciones de `ce_mask_garment_regions` para el mapa de regiones de prenda: las de la silueta
    /// de la pose (`silhouetteOptions`) de las opciones finales de la región. La máscara que recibe
    /// el motor con pose es un subconjunto de esa silueta (regiones de la pose o la silueta, menos
    /// la piel), así que todos sus píxeles quedan etiquetados; es la configuración con la que se
    /// calibró la paleta por prenda (`--torso-margin 0.35 --limb-width 1.0 --forearms 1`,
    /// engine/BENCHLOG.md, ADR-011).
    public static func garmentRegionOptions(_ o: RegionOptions) -> RegionOptions {
        silhouetteOptions(o)
    }

    /// Mapa de regiones de prenda de una persona (ver `SubjectOptions.computeGarmentRegions`):
    /// `ce_mask_garment_regions(decision.regionPose, garmentRegionOptions(decision.regionOptions), mask)`
    /// si la región es de ropa y sale de la pose (`.poseRegions` o `.poseSilhouette`); con caderas
    /// estimadas (`decision.hipsEstimated`) los 2 pasan a 1. nil si no hay pose utilizable para
    /// esta persona (recorte de cabeza, persona completa, sin decisión) o si el motor devuelve
    /// CE_ERR_POSE. `mask` es la máscara que recibe el motor para esta persona (width * height).
    /// Lanza los demás errores del motor.
    public static func garmentRegionMap(decision: RegionDecision?, region: RegionMode, mask: [UInt8], width: Int,
                                        height: Int) throws -> (regions: [UInt8], stats: GarmentRegionStats)? {
        guard region == .clothing, let d = decision, d.source == .poseRegions || d.source == .poseSilhouette,
              let pose = d.regionPose, let ro = d.regionOptions else { return nil }
        let options = garmentRegionOptions(ro)
        var map: [UInt8]
        do {
            // Cualificado: `garmentRegions` es también el nombre de propiedades de SubjectKit.
            map = try ColorEngine.garmentRegions(pose: pose, options: options, personMask: mask, width: width,
                                                 height: height).regions
        } catch let e as ColorEngineError where e == .poseMissing {
            return nil
        }
        var upper = 0, lower = 0, merged = 0
        map.withUnsafeMutableBufferPointer { b in
            for i in 0..<b.count {
                switch b[i] {
                case 1: upper += 1
                case 2:
                    if d.hipsEstimated {
                        b[i] = 1
                        upper += 1
                        merged += 1
                    } else {
                        lower += 1
                    }
                default: break
                }
            }
        }
        let stats = GarmentRegionStats(upperPixels: upper, lowerPixels: lower, maskPixels: MaskOps.nonZero(mask),
                                       lowerMergedIntoUpper: d.hipsEstimated, mergedLowerPixels: merged,
                                       options: options, pose: pose)
        return (map, stats)
    }

    /// Fracción de `cutHead` para una persona: sin cara, `headCutFraction`; con
    /// cara, la franja hasta su borde inferior + `headCutNeckFactor`·alto de la cara,
    /// medida sobre el bbox de la persona binaria (y0, H) y acotada a
    /// [`headCutFraction`, `maxHeadCutFraction`]. En un plano medio la cabeza ocupa
    /// bastante más del 18 % del alto.
    public static func cutHeadFraction(bodyBox: CGRect, faceBox: CGRect?) -> Double {
        guard let f = faceBox, !f.isNull, !f.isEmpty, !bodyBox.isNull, bodyBox.height > 0,
              f.maxY.isFinite, f.height.isFinite else { return headCutFraction }
        let chin = Double(f.maxY) + headCutNeckFactor * Double(f.height)
        let fraction = (chin - Double(bodyBox.minY)) / Double(bodyBox.height)
        guard fraction.isFinite else { return headCutFraction }
        return min(maxHeadCutFraction, max(headCutFraction, fraction))
    }
}
