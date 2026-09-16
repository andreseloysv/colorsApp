// Detección con Apple Vision (on-device, sin red): instancias de persona, pose
// 2D y landmarks de cara, asociados por persona y expresados en píxeles del
// raster que ve el motor.
//
//   - VNGeneratePersonInstanceMaskRequest: una sola petición; por cada índice de
//     `allInstances`, generateScaledMaskForImage(forInstances:from:) (máscara a
//     la resolución de la imagen) reescalada al raster con CoreGraphics.
//   - VNDetectHumanBodyPoseRequest: cada observación se asocia a la instancia
//     cuya máscara (>= 128) contiene más muestras de su esqueleto (segmentos
//     entre puntos con confianza >= 0,3; el torso cuenta doble); si varias
//     eligen la misma instancia se queda una (ver associatePoses). Hace falta al
//     menos una muestra del torso dentro.
//   - VNDetectFaceLandmarksRequest: cada cara se asocia a la instancia que
//     contiene (>= 128) más muestras del centro de su rectángulo; si hay varias
//     caras para una persona se queda una (ver associateFaces). La muestra de
//     piel sale de FaceSample (solo caras con ojos y labios); el rectángulo de
//     cualquier cara fija el recorte de cabeza sin pose.
//   - Separación de instancias fusionadas (PersonSplit.swift): ANTES de asociar, las
//     instancias en las que caen dos o más semillas de persona (poses y caras de Vision)
//     se reparten con `ce_mask_split_instance`; cada persona separada lleva su pose, su
//     cara y `splitFrom` = id de la instancia de Vision. Hasta 8 personas. Una semilla de
//     CARA sin pose necesita evidencia corporal (rectángulo de persona de Vision o puntos
//     de pose dentro de su eje): sin eso un póster, una pantalla o un retrato detrás de
//     una persona real creaba una persona fantasma (`SplitOptions.requireBodyForFaceSeeds`).
//   - Evidencia corporal (PersonEvidence.swift): tras asociar poses y caras, si alguna
//     instancia no tiene pose con torso dentro ni cara se piden rectángulos de persona
//     (VNDetectHumanRectanglesRequest, cuerpo entero; solo entonces, para no pagar la
//     petición en fotos con personas claras). Una instancia sin pose, cara ni rectángulo
//     de persona es una «persona fantasma» (Vision las devuelve en imágenes sin nadie y en
//     prendas colgadas) y se descarta (`PeopleDetection.rejectedPhantoms`; paso
//     `.rejectedPhantom` en `compute`).
// Coordenadas: Vision normaliza con origen abajo-izquierda; aquí
// x_px = x · W, y_px = (1 − y) · H.
import CoreGraphics
import CoreVideo
import Foundation
import Vision
import ColorEngine

/// Detección completa con avisos y tiempos (visionmask la vuelca en JSON).
public struct PeopleDetection: Sendable {
    public let people: [PersonInstance]
    /// Milisegundos: "vision.instances", "vision.masks", "vision.pose", "vision.face",
    /// "split", "associate", "vision.humans", "evidence", "detect".
    public let timings: [String: Double]
    /// Avisos no fatales (p. ej. la petición de pose falló y se sigue sin pose).
    public let warnings: [String]
    /// Poses de Vision sin persona asociada (píxeles del raster).
    public let unassignedPoses: Int
    /// Caras sin persona asociada.
    public let unassignedFaces: Int
    /// Landmarks de la cara asociada a cada persona (mismo orden que `people`), nil sin cara.
    public let faces: [FaceLandmarkPoints?]
    /// Instancias de Vision descartadas por cubrir menos de `SubjectExtractor.minPersonCoverage`
    /// del raster (fragmentos): no son personas ni reciben poses o caras.
    public let discardedPeople: Int
    /// Poses de Vision sin persona asociada (para dibujarlas en las capas).
    public let orphanPoses: [Pose]
    /// Caras de Vision sin persona asociada.
    public let orphanFaces: [FaceLandmarkPoints]
    /// Instancias sin evidencia corporal (personas fantasma), descartadas: no están en
    /// `people` ni en `faces`. Vacío con `PhantomOptions.enabled == false`.
    public var rejectedPhantoms: [RejectedPerson] = []
    /// Evidencia corporal de cada persona de `people` (mismo orden).
    public var evidence: [PersonEvidence] = []
    /// (Nuevo) Rectángulos de persona de Vision (píxeles del raster, confianza >=
    /// `PhantomOptions.minHumanConfidence`); vacío si no hizo falta pedirlos o si falló la petición.
    public var humanRectangles: [CGRect] = []
    /// (Nuevo) true si se ejecutó `VNDetectHumanRectanglesRequest`.
    public var humanRectanglesRequested = false
    /// (Nuevo) Instancias tal como las devolvió Vision, antes de separar (sin pose ni cara).
    public var visionInstances: [PersonInstance] = []
    /// (Nuevo) Todas las poses de Vision (píxeles del raster).
    public var poses: [Pose] = []
    /// (Nuevo) Todas las caras de Vision (rectángulo y, si los hay, landmarks).
    public var detectedFaces: [FaceLandmarkPoints] = []
    /// (Nuevo) Semillas de persona construidas con poses y caras (las de cara sin evidencia
    /// corporal ya están fuera: ver `faceSeedsWithoutBody`).
    public var seeds: [SubjectSeed] = []
    /// (Nuevo) Id de Vision de la instancia principal de cada semilla (nil: ninguna).
    public var seedInstanceIds: [Int?] = []
    /// (Nuevo) Instancias separadas (vacío si Vision no juntó a nadie).
    public var splits: [InstanceSplit] = []
    /// (Nuevo) Instancias de Vision sin separar unidas a una persona separada.
    public var absorbedInstances: [Int] = []
    /// (Nuevo) Semillas de cara descartadas por no tener evidencia corporal (póster, pantalla,
    /// retrato): no crean persona.
    public var faceSeedsWithoutBody: [SubjectSeed] = []

    /// Detección construida a mano (tests, personas reutilizadas): `faces` y `evidence`
    /// vacíos o con una entrada por persona.
    public init(people: [PersonInstance], timings: [String: Double] = [:], warnings: [String] = [],
                unassignedPoses: Int = 0, unassignedFaces: Int = 0, faces: [FaceLandmarkPoints?] = [],
                discardedPeople: Int = 0, orphanPoses: [Pose] = [], orphanFaces: [FaceLandmarkPoints] = [],
                rejectedPhantoms: [RejectedPerson] = [], evidence: [PersonEvidence] = []) {
        self.people = people
        self.timings = timings
        self.warnings = warnings
        self.unassignedPoses = unassignedPoses
        self.unassignedFaces = unassignedFaces
        self.faces = faces
        self.discardedPeople = discardedPeople
        self.orphanPoses = orphanPoses
        self.orphanFaces = orphanFaces
        self.rejectedPhantoms = rejectedPhantoms
        self.evidence = evidence
    }
}

extension SubjectExtractor {
    /// Detecta personas en `image` (orientada hacia arriba, el mismo contenido que
    /// el raster) y devuelve sus máscaras, poses y muestras de cara en un raster de
    /// `rasterWidth` x `rasterHeight`, ordenadas por cobertura descendente. Lanza
    /// el error de Vision si falla la petición de instancias (p. ej. en el
    /// simulador); los fallos de pose o de caras solo dejan esas partes en nil.
    /// Las instancias sin evidencia corporal (`PhantomOptions.default`) no se devuelven.
    public static func detectPeople(in image: CGImage, rasterWidth: Int, rasterHeight: Int) throws -> [PersonInstance] {
        try detectPeopleDetailed(in: image, rasterWidth: rasterWidth, rasterHeight: rasterHeight).people
    }

    /// `detectPeople` con tiempos, avisos y landmarks (evidencia corporal con `PhantomOptions.default`).
    public static func detectPeopleDetailed(in image: CGImage, rasterWidth: Int, rasterHeight: Int) throws -> PeopleDetection {
        try detectPeopleDetailed(in: image, rasterWidth: rasterWidth, rasterHeight: rasterHeight, phantomOptions: .default)
    }

    /// `detectPeopleDetailed` con umbrales propios de evidencia corporal (`enabled = false`:
    /// toda instancia por encima de `minPersonCoverage` es persona) y separación por defecto.
    public static func detectPeopleDetailed(in image: CGImage, rasterWidth: Int, rasterHeight: Int,
                                            phantomOptions: PhantomOptions) throws -> PeopleDetection {
        try detectPeopleDetailed(in: image, rasterWidth: rasterWidth, rasterHeight: rasterHeight,
                                 phantomOptions: phantomOptions, splitOptions: .default)
    }

    /// (Nuevo) `detectPeopleDetailed` con umbrales de evidencia corporal y de separación de
    /// instancias fusionadas (`SplitOptions.enabled = false`: cada instancia de Vision es una
    /// persona, el comportamiento anterior).
    public static func detectPeopleDetailed(in image: CGImage, rasterWidth: Int, rasterHeight: Int,
                                            phantomOptions: PhantomOptions,
                                            splitOptions: SplitOptions) throws -> PeopleDetection {
        let W = rasterWidth, H = rasterHeight
        guard W >= 1, H >= 1, W.multipliedReportingOverflow(by: H).overflow == false else {
            throw SubjectError.invalidDimensions(width: W, height: H)
        }
        let total = Stopwatch()
        var timings: [String: Double] = [:]
        var warnings: [String] = []
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        // 1. Instancias.
        var clock = Stopwatch()
        let instanceRequest = VNGeneratePersonInstanceMaskRequest()
        try handler.perform([instanceRequest])
        timings["vision.instances"] = clock.elapsedMs
        clock = Stopwatch()
        var masks: [(id: Int, mask: [UInt8])] = []
        var discarded = 0
        let minPixels = max(1, Int((minPersonCoverage * Double(W * H)).rounded(.up)))
        if let observation = instanceRequest.results?.first {
            for id in observation.allInstances {
                let buffer = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: id), from: handler)
                let mask = try MaskRaster.rasterizeMask(buffer, width: W, height: H)
                let inside = MaskOps.stats(mask, width: W, height: H).count
                if inside < minPixels {
                    discarded += 1
                    warnings.append("instancia \(id): \(inside) px >= 128 < \(minPixels) (minPersonCoverage): descartada")
                    continue
                }
                masks.append((id, mask))
            }
        }
        timings["vision.masks"] = clock.elapsedMs

        // 2. Pose.
        clock = Stopwatch()
        var poses: [Pose] = []
        if !masks.isEmpty {
            let poseRequest = VNDetectHumanBodyPoseRequest()
            do {
                try handler.perform([poseRequest])
                poses = (poseRequest.results ?? []).map { visionPose($0, width: W, height: H) }
            } catch {
                warnings.append("pose: \(error.localizedDescription)")
            }
        }
        timings["vision.pose"] = clock.elapsedMs

        // 3. Caras.
        clock = Stopwatch()
        var faces: [FaceLandmarkPoints] = []
        if !masks.isEmpty {
            let faceRequest = VNDetectFaceLandmarksRequest()
            do {
                try handler.perform([faceRequest])
                faces = (faceRequest.results ?? []).compactMap { visionFace($0, width: W, height: H) }
            } catch {
                warnings.append("face: \(error.localizedDescription)")
            }
        }
        timings["vision.face"] = clock.elapsedMs

        // 4. Semillas de persona (poses y caras) y separación de instancias fusionadas.
        clock = Stopwatch()
        let instances = masks.map { PersonInstance(id: $0.id, mask: $0.mask, width: W, height: H) }
        let seeds = PersonSplitter.seeds(poses: poses, faces: faces)
        timings["seeds"] = clock.elapsedMs
        // Rectángulos de persona: una semilla de CARA sin pose solo cuenta con evidencia
        // corporal (ADR-010), así que la petición se adelanta aquí si hace falta.
        var humanBoxes: [CGRect] = []
        var humansRequested = false
        let needFaceSeedBody = splitOptions.enabled && splitOptions.requireBodyForFaceSeeds
            && seeds.contains { $0.kind == .face }
        func requestHumans() {
            guard !humansRequested else { return }
            humansRequested = true
            let humanClock = Stopwatch()
            do {
                humanBoxes = try humanRectangles(handler: handler, width: W, height: H,
                                                 minConfidence: phantomOptions.minHumanConfidence)
            } catch {
                warnings.append("human rectangles: \(error.localizedDescription)")
            }
            timings["vision.humans"] = humanClock.elapsedMs
        }
        if phantomOptions.humanRectangles, needFaceSeedBody {
            requestHumans()
        }
        clock = Stopwatch()
        let outcome = try PersonSplitter.apply(instances: instances, poses: poses, faces: faces, seeds: seeds,
                                               width: W, height: H, humanBoxes: humanBoxes, options: splitOptions)
        var people = outcome.people
        let faceByPerson: [Int: FaceLandmarkPoints] = {
            var d: [Int: FaceLandmarkPoints] = [:]
            for (i, p) in people.enumerated() where outcome.faces[i] != nil { d[p.id] = outcome.faces[i] }
            return d
        }()
        for split in outcome.splits {
            warnings.append("instancia \(split.instanceId): \(split.seeds.count) semillas -> personas \(split.personIds.map(String.init).joined(separator: ", ")) (\(split.step.rawValue))")
        }
        for seed in outcome.faceSeedsWithoutBody {
            warnings.append("cara en (\(Int(seed.seed.x0)), \(Int(seed.seed.y0))) sin evidencia corporal (rectángulo de persona o puntos de pose): no crea persona")
        }
        timings["split"] = clock.elapsedMs
        timings["associate"] = clock.elapsedMs
        // 5. Evidencia corporal: rectángulos de persona solo si alguna persona no tiene pose ni
        // cara; fuera las personas fantasma.
        clock = Stopwatch()
        if phantomOptions.enabled, phantomOptions.humanRectangles, !humansRequested,
           people.contains(where: { !bodyEvidence(for: $0, width: W, height: H, options: phantomOptions).isPerson }) {
            requestHumans()
        }
        let screened = rejectPhantoms(people, width: W, height: H, options: phantomOptions, humanBoxes: humanBoxes)
        let boxOf = associateHumanRectangles(phantomOptions.humanRectangles ? humanBoxes : [], masks: people.map(\.mask),
                                             width: W, height: H)
        let evidenceAll = people.indices.map {
            bodyEvidence(for: people[$0], width: W, height: H, options: phantomOptions, humanBox: boxOf[$0].map { humanBoxes[$0] })
        }
        let keptIds = Set(screened.people.map(\.id))
        let keptEvidence = zip(people, evidenceAll).filter { keptIds.contains($0.0.id) }.map(\.1)
        people = screened.people
        for r in screened.rejected {
            warnings.append("instancia \(r.instance.id): sin evidencia corporal (torso \(r.evidence.torsoJointsInside), cara \(r.evidence.hasFace), rectángulo de persona \(r.evidence.humanBox != nil), cobertura \(r.evidence.coverage), alto/ancho \(r.evidence.aspect), relleno \(r.evidence.extent), solidez \(r.evidence.solidity)): fantasma")
        }
        timings["evidence"] = clock.elapsedMs
        timings["detect"] = total.elapsedMs
        // Poses y caras que acabaron en alguna persona (separada o no).
        let usedPoseSet = Set(people.compactMap { p in poses.firstIndex { $0 == p.pose } })
        let usedFaceSet = Set(people.compactMap { p in faceByPerson[p.id].flatMap { f in faces.firstIndex(of: f) } })
        var detection = PeopleDetection(people: people, timings: timings, warnings: warnings,
                                        unassignedPoses: poses.count - usedPoseSet.count,
                                        unassignedFaces: faces.count - usedFaceSet.count,
                                        faces: people.map { faceByPerson[$0.id] }, discardedPeople: discarded,
                                        orphanPoses: poses.indices.filter { !usedPoseSet.contains($0) }.map { poses[$0] },
                                        orphanFaces: faces.indices.filter { !usedFaceSet.contains($0) }.map { faces[$0] })
        detection.rejectedPhantoms = screened.rejected
        detection.evidence = phantomOptions.enabled ? keptEvidence
            : people.map { bodyEvidence(for: $0, width: W, height: H, options: phantomOptions) }
        detection.humanRectangles = humanBoxes
        detection.humanRectanglesRequested = humansRequested
        detection.visionInstances = instances
        detection.poses = poses
        detection.detectedFaces = faces
        detection.seeds = outcome.seeds
        detection.seedInstanceIds = outcome.seedInstance.map { $0.map { instances[$0].id } }
        detection.splits = outcome.splits
        detection.absorbedInstances = outcome.absorbedInstances
        detection.faceSeedsWithoutBody = outcome.faceSeedsWithoutBody
        return detection
    }

    /// (Nuevo) Rectángulos de persona de cuerpo entero de Vision (`VNDetectHumanRectanglesRequest`,
    /// `upperBodyOnly = false`) con confianza >= `minConfidence`, en píxeles de un raster de
    /// `rasterWidth` x `rasterHeight` (origen arriba-izquierda). Lanza el error de Vision.
    public static func detectHumanRectangles(in image: CGImage, rasterWidth: Int, rasterHeight: Int,
                                             minConfidence: Double = PhantomOptions.default.minHumanConfidence) throws -> [CGRect] {
        guard rasterWidth >= 1, rasterHeight >= 1 else {
            throw SubjectError.invalidDimensions(width: rasterWidth, height: rasterHeight)
        }
        return try humanRectangles(handler: VNImageRequestHandler(cgImage: image, options: [:]), width: rasterWidth,
                                   height: rasterHeight, minConfidence: minConfidence)
    }

    static func humanRectangles(handler: VNImageRequestHandler, width: Int, height: Int,
                                minConfidence: Double) throws -> [CGRect] {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        try handler.perform([request])
        return (request.results ?? []).compactMap { o in
            guard Double(o.confidence) >= minConfidence else { return nil }
            return visionRect(o.boundingBox, width: width, height: height)
        }
    }

    /// Detecta y aplica la cadena. Si Vision lanza, devuelve mask nil y steps
    /// [.visionUnavailable] (nunca lanza por Vision). Con `mode == .off` no ejecuta Vision.
    /// Si se descartaron personas fantasma (`options.phantomOptions`), los pasos empiezan
    /// por `.rejectedPhantom` (y siguen con `.noPeople` si no queda nadie: foto completa).
    public static func compute(image: CGImage, rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int,
                               stride: Int, options: SubjectOptions) throws -> SubjectMaskResult {
        if options.mode == .off {
            return try mask(people: [], rgba: rgba, width: width, height: height, stride: stride, options: options)
        }
        let detection: PeopleDetection
        do {
            detection = try detectPeopleDetailed(in: image, rasterWidth: width, rasterHeight: height,
                                                 phantomOptions: options.phantomOptions,
                                                 splitOptions: options.splitOptions)
        } catch let e as SubjectError where e == .invalidDimensions(width: width, height: height) {
            throw e
        } catch {
            let empty = [UInt8](repeating: 0, count: max(0, width) * max(0, height))
            let layers = SubjectLayers(width: width, height: height, persons: [], allPeopleOverlay: empty, finalMask: nil)
            return SubjectMaskResult(width: width, height: height, people: [], chosenIndex: nil, mask: nil,
                                     steps: [.visionUnavailable], timings: [:], maskCoverage: 0, layers: layers)
        }
        return try mask(detection: detection, rgba: rgba, width: width, height: height, stride: stride,
                        options: options)
    }

    /// Aplica la cadena a una detección ya hecha: como `mask(people:)` con `detection.people`,
    /// más el paso `.rejectedPhantom` al principio si la detección descartó personas fantasma
    /// (`SubjectMaskResult.rejectedPhantoms`).
    public static func mask(detection: PeopleDetection, rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int,
                            stride: Int, options: SubjectOptions) throws -> SubjectMaskResult {
        try mask(people: detection.people, rgba: rgba, width: width, height: height, stride: stride,
                 options: options, detectTimings: detection.timings, rejected: detection.rejectedPhantoms)
    }

    // MARK: - Conversión de observaciones

    static let jointNames: [(ColorEngine.Joint, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .nose), (.neck, .neck), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.leftHip, .leftHip), (.rightHip, .rightHip), (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle), (.root, .root),
    ]

    static func visionPose(_ observation: VNHumanBodyPoseObservation, width: Int, height: Int) -> Pose {
        var pose = Pose()
        guard let points = try? observation.recognizedPoints(.all) else { return pose }
        for (joint, name) in jointNames {
            guard let p = points[name], p.confidence > 0 else { continue }
            let x = Double(p.location.x) * Double(width)
            let y = (1 - Double(p.location.y)) * Double(height)
            guard x.isFinite, y.isFinite else { continue }
            pose[joint] = Keypoint(x: x, y: y, confidence: Double(p.confidence))
        }
        return pose
    }

    /// Rectángulo normalizado de Vision (origen abajo-izquierda) en píxeles del raster; nil si no es finito.
    static func visionRect(_ bb: CGRect, width: Int, height: Int) -> CGRect? {
        let box = CGRect(x: bb.minX * CGFloat(width), y: (1 - bb.maxY) * CGFloat(height),
                         width: bb.width * CGFloat(width), height: bb.height * CGFloat(height))
        guard box.minX.isFinite, box.minY.isFinite, box.width.isFinite, box.height.isFinite, box.width > 0,
              box.height > 0 else { return nil }
        return box
    }

    /// Cara en píxeles del raster. Sin landmarks (o sin ojos o labios) conserva
    /// solo el rectángulo: sirve para asociar la cara y fijar el recorte de cabeza,
    /// pero no da muestra de piel (`FaceSample.polygons` devuelve nil).
    static func visionFace(_ face: VNFaceObservation, width: Int, height: Int) -> FaceLandmarkPoints? {
        let size = CGSize(width: width, height: height)
        func pts(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            guard let region, region.pointCount > 0 else { return [] }
            return region.pointsInImage(imageSize: size).map { CGPoint(x: $0.x, y: CGFloat(height) - $0.y) }
        }
        let bb = face.boundingBox
        let box = CGRect(x: bb.minX * CGFloat(width), y: (1 - bb.maxY) * CGFloat(height),
                         width: bb.width * CGFloat(width), height: bb.height * CGFloat(height))
        guard box.minX.isFinite, box.minY.isFinite, box.width.isFinite, box.height.isFinite, box.width > 0,
              box.height > 0 else { return nil }
        guard let lm = face.landmarks else {
            return FaceLandmarkPoints(leftEye: [], rightEye: [], outerLips: [], boundingBox: box)
        }
        let result = FaceLandmarkPoints(leftEye: pts(lm.leftEye), rightEye: pts(lm.rightEye),
                                        leftEyebrow: pts(lm.leftEyebrow), rightEyebrow: pts(lm.rightEyebrow),
                                        outerLips: pts(lm.outerLips), faceContour: pts(lm.faceContour),
                                        boundingBox: box)
        guard !result.leftEye.isEmpty, !result.rightEye.isEmpty, !result.outerLips.isEmpty else {
            return FaceLandmarkPoints(leftEye: [], rightEye: [], outerLips: [], boundingBox: box)
        }
        return result
    }

    // MARK: - Asociación (sin Vision: testeable con datos sintéticos)

    static let torsoJoints: [ColorEngine.Joint] = [.neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .root]
    /// Segmentos del torso del esqueleto (cuentan doble al asociar).
    static let torsoSegments: [(ColorEngine.Joint, ColorEngine.Joint)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftHip), (.rightShoulder, .rightHip), (.leftHip, .rightHip),
        (.neck, .root),
    ]
    /// Resto de segmentos: cabeza, brazos y piernas.
    static let limbSegments: [(ColorEngine.Joint, ColorEngine.Joint)] = [
        (.nose, .neck), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist), (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
    ]
    /// Muestras por segmento del esqueleto al asociar (t = (k + 0,5)/n).
    static let segmentSamples = 8

    /// Puntos de muestra del esqueleto de una pose: `segmentSamples` puntos por
    /// segmento cuyos dos extremos son utilizables (confianza >= `minConfidence`,
    /// la regla del motor), cada punto del torso utilizable que no está en ningún
    /// segmento del torso y cada punto utilizable del resto que no está en ninguno.
    /// `torso` marca las muestras de segmentos o puntos del torso.
    static func skeletonSamples(_ pose: Pose, minConfidence: Double) -> [(x: Double, y: Double, torso: Bool)] {
        var out: [(x: Double, y: Double, torso: Bool)] = []
        var inTorsoSegment = Set<Int>(), inAnySegment = Set<Int>()
        let n = segmentSamples
        for (list, torso) in [(torsoSegments, true), (limbSegments, false)] {
            for (a, b) in list {
                let pa = pose[a], pb = pose[b]
                guard usable(pa, minConfidence: minConfidence), usable(pb, minConfidence: minConfidence) else { continue }
                for j in [a, b] {
                    inAnySegment.insert(j.rawValue)
                    if torso { inTorsoSegment.insert(j.rawValue) }
                }
                for k in 0..<n {
                    let t = (Double(k) + 0.5) / Double(n)
                    out.append((pa.x + t * (pb.x - pa.x), pa.y + t * (pb.y - pa.y), torso))
                }
            }
        }
        // Puntos sueltos: un punto del torso fuera de todo segmento del torso (p. ej.
        // cuello y un hombro sin el otro) cuenta como muestra del torso; el resto,
        // solo si no está en ningún segmento.
        for joint in ColorEngine.Joint.allCases {
            let k = pose[joint]
            guard usable(k, minConfidence: minConfidence) else { continue }
            if torsoJoints.contains(joint) {
                if !inTorsoSegment.contains(joint.rawValue) { out.append((k.x, k.y, true)) }
            } else if !inAnySegment.contains(joint.rawValue) {
                out.append((k.x, k.y, false))
            }
        }
        return out
    }

    /// Para cada máscara, el índice de la pose asociada (o nil).
    ///
    /// Solo cuentan los puntos que el motor usaría (confianza >= `minConfidence`).
    /// Cada pose se muestrea a lo largo de su esqueleto (`skeletonSamples`: 8
    /// puntos por segmento entre puntos utilizables; torso = hombros, caderas y
    /// columna cuello–raíz) y va a la instancia cuya máscara (>= 128) contiene
    /// más muestras, con las del torso contando doble (desempate: más muestras
    /// del torso, luego la máscara anterior). Hace falta al menos una muestra del
    /// torso dentro. Contar puntos sueltos fallaba en los bordes entre personas
    /// abrazadas: el cuello y un hombro caen en la instancia vecina y la pose
    /// se iba a la persona equivocada (harness/people/05).
    /// Si varias poses eligen la misma instancia (Vision fusiona personas cuando
    /// hay más de 4), se queda la de más muestras del torso dentro, luego más
    /// muestras ponderadas, luego el torso más grande (hombros y caderas más
    /// separados: la persona más cercana) y luego la pose anterior.
    public static func associatePoses(_ poses: [Pose], masks: [[UInt8]], width: Int, height: Int,
                                      minConfidence: Double = RegionOptions.default.minConfidence) -> [Int?] {
        struct Claim { let torso: Int; let score: Int; let extent: Double; let pose: Int }
        var claims = [[Claim]](repeating: [], count: masks.count)
        for (pi, pose) in poses.enumerated() {
            let samples = skeletonSamples(pose, minConfidence: minConfidence)
            guard !samples.isEmpty else { continue }
            var best: (mask: Int, torso: Int, score: Int)? = nil
            for (mi, mask) in masks.enumerated() {
                var torso = 0, limb = 0
                for p in samples where MaskOps.value(mask, width: width, height: height, x: p.x, y: p.y) >= MaskOps.insideThreshold {
                    if p.torso { torso += 1 } else { limb += 1 }
                }
                guard torso >= 1 else { continue }
                let score = 2 * torso + limb
                if let b = best, (b.score, b.torso) >= (score, torso) { continue }
                best = (mi, torso, score)
            }
            if let b = best {
                claims[b.mask].append(Claim(torso: b.torso, score: b.score,
                                            extent: torsoExtent(pose, minConfidence: minConfidence), pose: pi))
            }
        }
        return claims.map { list in
            list.min { a, b in
                if a.torso != b.torso { return a.torso > b.torso }
                if a.score != b.score { return a.score > b.score }
                if a.extent != b.extent { return a.extent > b.extent }
                return a.pose < b.pose
            }?.pose
        }
    }

    /// Diagonal del rectángulo de los puntos del torso presentes (0 si hay < 2).
    static func torsoExtent(_ pose: Pose, minConfidence: Double = 0) -> Double {
        let pts = torsoJoints.map { pose[$0] }.filter { $0.confidence > 0 && $0.confidence >= minConfidence }
        guard pts.count >= 2, let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(),
              let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else { return 0 }
        let dx = maxX - minX, dy = maxY - minY
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Lado de la rejilla de muestras de una cara al asociarla (7 x 7 = 49 muestras).
    static let faceGrid = 7
    /// Parte central del rectángulo de la cara que se muestrea (fracción de cada lado).
    static let faceGridSpan = 0.6

    /// Muestras de una cara: rejilla `faceGrid` x `faceGrid` sobre el `faceGridSpan`
    /// central de su rectángulo (sin rectángulo: el punto medio de los ojos).
    /// `below`: la misma rejilla desplazada un alto de cara hacia abajo (cuello y
    /// pecho de la misma persona).
    static func faceSamplePoints(_ face: FaceLandmarkPoints, below: Bool = false) -> [CGPoint] {
        let box = face.boundingBox
        guard !box.isNull, !box.isEmpty else { return below ? [] : [face.center] }
        let n = faceGrid
        let dy = below ? Double(box.height) : 0
        var out: [CGPoint] = []
        for j in 0..<n {
            for i in 0..<n {
                let u = (1 - faceGridSpan) / 2 + faceGridSpan * (Double(i) + 0.5) / Double(n)
                let v = (1 - faceGridSpan) / 2 + faceGridSpan * (Double(j) + 0.5) / Double(n)
                out.append(CGPoint(x: Double(box.minX) + u * Double(box.width),
                                   y: Double(box.minY) + v * Double(box.height) + dy))
            }
        }
        return out
    }

    /// Para cada máscara, el índice de la cara asociada (o nil).
    ///
    /// Cada cara va a la instancia cuya máscara (>= 128) contiene más muestras de
    /// la parte central de su rectángulo (`faceSamplePoints`), si contiene al
    /// menos una cuarta parte (desempate: la máscara anterior). Si ninguna llega
    /// (Vision deja la cara fuera de la instancia, p. ej. piel oscura con gafas de
    /// sol en harness/people/05), se usa la misma rejilla un alto de cara más
    /// abajo (cuello y pecho) con el mismo criterio: asociación indirecta (la cara
    /// solo aporta su rectángulo, sin muestra de piel). Si
    /// varias caras eligen la misma instancia se queda la directa, luego la de
    /// más muestras dentro, luego la que tiene landmarks (muestra de piel), luego
    /// la de mayor rectángulo y luego la cara anterior. Mirar solo el centro
    /// fallaba con caras con huecos en su propia máscara: el centro caía en la
    /// instancia vecina, que ya tenía su cara, y la cara se perdía.
    public static func associateFaces(_ faces: [FaceLandmarkPoints], masks: [[UInt8]], width: Int, height: Int) -> [Int?] {
        associateFacesDetailed(faces, masks: masks, width: width, height: height).map { $0?.face }
    }

    /// `associateFaces` indicando si la asociación fue directa (la cara dentro de la máscara).
    static func associateFacesDetailed(_ faces: [FaceLandmarkPoints], masks: [[UInt8]], width: Int, height: Int)
        -> [(face: Int, direct: Bool)?] {
        struct Key: Comparable {
            let direct: Int, score: Int, landmarks: Int, area: Double, face: Int
            static func < (a: Key, b: Key) -> Bool {
                (a.direct, a.score, a.landmarks, a.area, -a.face) < (b.direct, b.score, b.landmarks, b.area, -b.face)
            }
        }
        func bestMask(_ pts: [CGPoint]) -> (mask: Int, score: Int)? {
            var best = -1, bestScore = 0
            for (mi, mask) in masks.enumerated() {
                var c = 0
                for p in pts where MaskOps.value(mask, width: width, height: height, x: Double(p.x), y: Double(p.y))
                    >= MaskOps.insideThreshold {
                    c += 1
                }
                if c > bestScore {
                    best = mi
                    bestScore = c
                }
            }
            guard best >= 0, 4 * bestScore >= pts.count else { return nil }
            return (best, bestScore)
        }
        var result = [(face: Int, direct: Bool)?](repeating: nil, count: masks.count)
        var bestKey = [Key?](repeating: nil, count: masks.count)
        for (fi, face) in faces.enumerated() {
            var direct = true
            var hit = bestMask(faceSamplePoints(face))
            if hit == nil {
                let below = faceSamplePoints(face, below: true)
                if !below.isEmpty {
                    hit = bestMask(below)
                    direct = false
                }
            }
            guard let hit else { continue }
            let box = face.boundingBox
            let area = box.isNull ? 0 : Double(box.width * box.height)
            let key = Key(direct: direct ? 1 : 0, score: hit.score, landmarks: FaceSample.polygons(face) == nil ? 0 : 1,
                          area: area, face: fi)
            if let k = bestKey[hit.mask], k >= key { continue }
            bestKey[hit.mask] = key
            result[hit.mask] = (fi, direct)
        }
        return result
    }
}
