// Cadena de máscaras sin Vision: de las personas detectadas a la máscara que
// recibe el motor, con capas y pasos. Toda la geometría y la piel se delegan
// en el motor C (ColorEngine); aquí solo se eligen entradas y candidatas.
//
// Por persona (runChain), sobre su máscara BINARIA B (>= 128 -> 255):
//   suelo = max(ceil(minCoverage·W·H), 1)
//   muestra de piel: la propia o, con < 50 muestras y shareSkinModel, la de la
//     persona con más muestras (skinSampleSource); modelo = fitSkinModel(muestra).
//   region == .clothing, opciones ro = regionOptions (sin brazos si se pidió piel
//   y no hay muestra con >= 50 muestras: con manga corta serían piel):
//     con pose: pose' = regionPose(pose) (caderas estimadas en planos medios)
//       R = clothingRegions(pose', ro, B)
//       brazos desnudos (modelo y ro con brazos): A = R − clothingRegions(pose', ro sin brazos, B);
//         piel(A) = excludeSkin(modelo, maxExcluded 1, A).excluded;
//         si piel(A) >= ceil(bareArmsSkinFraction·|A|): ro sin brazos, R sin brazos
//       S = clothingRegions(pose', silhouetteOptions(ro), B)            (silueta)
//       requerido = max(ceil(minRegionFraction·|S|), suelo)
//       |S| >= suelo:  |R| >= requerido -> R [poseRegions]; si no -> S [poseRegions] (silueta)
//       |S| <  suelo:  la pose no describe a esta persona -> 3.
//       (CE_ERR_POSE: sin candidatas de pose -> 3.)
//     3. cutHead(B, cutHeadFraction(bbox(B), cara))                        -> [.., headCut]
//   region == .wholePerson: B
//   modelo: excludeSkin -> [skinExcluded] si quitó algún píxel, o [skinGuard]
//     (máscara intacta); con < 50 muestras no se aplica (skinNote).
//   respaldo de la persona: S si hay silueta >= suelo, si no B (fallbackSource).
// largestPerson / selectedPerson: la salida de la persona si |salida| >= suelo;
//   si no, el respaldo si llega al suelo [wholePerson]; si no, sin máscara [none].
// allPeople: la unión (máximo por píxel) de las salidas con |salida| >= suelo; si
//   ninguna llega, la unión de los respaldos que lleguen [wholePerson]; si no, [none].
// off: sin máscara [none]. Sin personas: sin máscara [noPeople].
// La suficiencia de las regiones se mide frente a la SILUETA de la pose (la
// persona que describe la pose), no frente al raster ni a la instancia de Vision:
// una persona pequeña conserva su región de ropa y un objeto pegado a ella en la
// misma instancia (cochecito, bici, bolso, moto) no la vuelve «insuficiente».
// Con pose nunca se usa la instancia cruda de Vision (CONTEXT §12).
import CoreGraphics
import Darwin
import ColorEngine

public enum SubjectExtractor {
    /// Aplica la cadena a personas ya detectadas (`detectPeople` o construidas a
    /// mano). `rgba`: el raster RGBA/RGBX sRGB de 8 bits que ve el motor
    /// (`width` x `height`, `stride` bytes por fila). Lanza `SubjectError` con
    /// dimensiones, máscaras u opciones inválidas y `ColorEngineError` si el
    /// motor rechaza algo que no es un retorno previsto (CE_ERR_POSE y
    /// CE_ERR_SKIN_SAMPLES sí son retornos previstos y no lanzan).
    public static func mask(people: [PersonInstance], rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int,
                            stride: Int, options: SubjectOptions) throws -> SubjectMaskResult {
        try mask(people: people, rgba: rgba, width: width, height: height, stride: stride, options: options,
                 detectTimings: [:])
    }

    static func mask(people unsorted: [PersonInstance], rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int,
                     stride: Int, options: SubjectOptions, detectTimings: [String: Double]) throws -> SubjectMaskResult {
        let clock = Stopwatch()
        guard width >= 1, height >= 1, width <= Int(Int32.max), height <= Int(Int32.max),
              width.multipliedReportingOverflow(by: height).overflow == false else {
            throw SubjectError.invalidDimensions(width: width, height: height)
        }
        guard options.minCoverage.isFinite, options.minCoverage >= 0, options.minCoverage <= 1 else {
            throw SubjectError.invalidOptions("minCoverage debe estar en 0...1")
        }
        guard options.minRegionFraction.isFinite, options.minRegionFraction >= 0, options.minRegionFraction <= 1 else {
            throw SubjectError.invalidOptions("minRegionFraction debe estar en 0...1")
        }
        guard options.bareArmsSkinFraction.isFinite, options.bareArmsSkinFraction >= 0,
              options.bareArmsSkinFraction <= 1 else {
            throw SubjectError.invalidOptions("bareArmsSkinFraction debe estar en 0...1")
        }
        let count = width * height
        let required = (height - 1) * stride + width * 4
        guard stride >= width * 4 else {
            throw ColorEngineError.engine(code: -4)  // CE_ERR_STRIDE
        }
        guard rgba.count >= required else {
            throw ColorEngineError.bufferTooSmall(required: required, actual: rgba.count)
        }
        for p in unsorted {
            guard p.mask.count == count else {
                throw SubjectError.maskSizeMismatch(personId: p.id, expected: count, actual: p.mask.count)
            }
            if let s = p.faceSampleMask, s.count != count {
                throw SubjectError.maskSizeMismatch(personId: p.id, expected: count, actual: s.count)
            }
        }
        let people = sortPeople(unsorted)
        var timings = detectTimings
        let overlay = MaskOps.instanceOverlay(people, width: width, height: height)

        func finish(chosen: Int?, mask: [UInt8]?, steps: [MaskFallback], persons: [PersonLayers]) -> SubjectMaskResult {
            let coverage = mask.map { MaskOps.coverage($0, width: width, height: height) } ?? 0
            timings["mask"] = clock.elapsedMs
            timings["total"] = (detectTimings["detect"] ?? 0) + clock.elapsedMs
            let layers = SubjectLayers(width: width, height: height, persons: persons, allPeopleOverlay: overlay,
                                       finalMask: mask)
            return SubjectMaskResult(width: width, height: height, people: people, chosenIndex: chosen, mask: mask,
                                     steps: steps, timings: timings, maskCoverage: coverage, layers: layers)
        }

        if options.mode == .off {
            return finish(chosen: nil, mask: nil, steps: [.none], persons: [])
        }
        guard !people.isEmpty else {
            return finish(chosen: nil, mask: nil, steps: [.noPeople], persons: [])
        }

        let floorPixels = self.floorPixels(options: options, width: width, height: height)
        let donors = skinDonors(people)
        var regionMs = 0.0, skinMs = 0.0
        if options.mode != .allPeople {
            var index = 0
            if options.mode == .selectedPerson, let sel = options.selectedIndex, sel >= 0, sel < people.count {
                index = sel
            }
            let person = people[index]
            let chain = try runChain(person: person, index: index, rgba: rgba, width: width, height: height,
                                     stride: stride, options: options, donor: donors[index], people: people,
                                     regionMs: &regionMs, skinMs: &skinMs)
            let t0 = clock.elapsedMs
            var steps = chain.steps
            var mask: [UInt8]? = chain.final
            var fallback: RegionSource? = nil
            if MaskOps.nonZero(chain.final) < floorPixels {
                if MaskOps.nonZero(chain.fallback) >= floorPixels {
                    mask = chain.fallback
                    fallback = chain.fallbackSource
                    steps.append(.wholePerson)
                } else {
                    mask = nil
                    steps.append(.none)
                }
            }
            timings["regions"] = regionMs
            timings["skin"] = skinMs
            timings["coverage"] = clock.elapsedMs - t0
            let layer = chain.layers(steps: steps, used: mask != nil && fallback == nil, fallback: fallback)
            return finish(chosen: index, mask: mask, steps: steps, persons: [layer])
        } else {
            var chains: [ChainOutput] = []
            for (i, p) in people.enumerated() {
                chains.append(try runChain(person: p, index: i, rgba: rgba, width: width, height: height,
                                           stride: stride, options: options, donor: donors[i], people: people,
                                           regionMs: &regionMs, skinMs: &skinMs))
            }
            let t0 = clock.elapsedMs
            var steps: [MaskFallback] = []
            for c in chains {
                for s in c.steps where !steps.contains(s) { steps.append(s) }
            }
            let used = chains.map { MaskOps.nonZero($0.final) >= floorPixels }
            var mask = MaskOps.union(zip(chains, used).filter(\.1).map(\.0.final))
            var fallbacks = [RegionSource?](repeating: nil, count: chains.count)
            if mask == nil {
                var bodies: [[UInt8]] = []
                for (i, c) in chains.enumerated() where MaskOps.nonZero(c.fallback) >= floorPixels {
                    bodies.append(c.fallback)
                    fallbacks[i] = c.fallbackSource
                }
                if let whole = MaskOps.union(bodies) {
                    mask = whole
                    steps.append(.wholePerson)
                } else {
                    steps.append(.none)
                }
            }
            timings["regions"] = regionMs
            timings["skin"] = skinMs
            timings["coverage"] = clock.elapsedMs - t0
            let persons = chains.indices.map { chains[$0].layers(steps: chains[$0].steps, used: used[$0],
                                                                 fallback: fallbacks[$0]) }
            return finish(chosen: nil, mask: mask, steps: steps, persons: persons)
        }
    }

    /// Suelo absoluto en píxeles: max(1, ceil(minCoverage · width · height)).
    public static func floorPixels(options: SubjectOptions, width: Int, height: Int) -> Int {
        max(1, Int((options.minCoverage * Double(width * height)).rounded(.up)))
    }

    /// Píxeles que deben tener las regiones de la pose de una persona cuya silueta
    /// de la pose mide `silhouettePixels`: max(ceil(minRegionFraction · silhouettePixels), suelo).
    public static func requiredRegionPixels(silhouettePixels: Int, options: SubjectOptions, width: Int,
                                            height: Int) -> Int {
        max(Int((options.minRegionFraction * Double(silhouettePixels)).rounded(.up)),
            floorPixels(options: options, width: width, height: height))
    }

    /// Píxeles de brazo que deben ser piel para quitar los brazos:
    /// max(1, ceil(bareArmsSkinFraction · armPixels)).
    public static func bareArmsThreshold(armPixels: Int, options: SubjectOptions) -> Int {
        max(1, Int((options.bareArmsSkinFraction * Double(armPixels)).rounded(.up)))
    }

    /// Muestras mínimas de una muestra de cara utilizable (CE_SKIN_MIN_SAMPLES).
    public static let minSkinSamples = 50

    /// Para cada persona, la otra persona con más muestras de cara (>= 128) si
    /// llega a `minSkinSamples` (desempate: índice menor); nil si no hay.
    static func skinDonors(_ people: [PersonInstance]) -> [Int?] {
        let counts = people.map { samplePixels($0.faceSampleMask) }
        let ranked = counts.indices.filter { counts[$0] >= minSkinSamples }
            .sorted { counts[$0] != counts[$1] ? counts[$0] > counts[$1] : $0 < $1 }
        return people.indices.map { i in ranked.first { $0 != i } }
    }

    /// Orden estable: cobertura descendente, desempate por id ascendente.
    static func sortPeople(_ people: [PersonInstance]) -> [PersonInstance] {
        people.enumerated().sorted { a, b in
            if a.element.coverage != b.element.coverage { return a.element.coverage > b.element.coverage }
            if a.element.id != b.element.id { return a.element.id < b.element.id }
            return a.offset < b.offset
        }.map(\.element)
    }

    struct ChainOutput {
        let person: PersonInstance
        let index: Int
        /// Máscara binaria de la persona.
        let body: [UInt8]
        var region: [UInt8]?
        var silhouette: [UInt8]?
        var arms: [UInt8]?
        var sample: [UInt8]?
        var removed: [UInt8]?
        var final: [UInt8]
        var steps: [MaskFallback]
        var model: SkinModel?
        var excluded: Int
        var note: String?
        var decision: RegionDecision?
        var sampleSource: Int?
        /// Máscara de respaldo si la final no llega al suelo: silueta (con pose) o persona binaria.
        var fallback: [UInt8]
        var fallbackSource: RegionSource

        func layers(steps: [MaskFallback], used: Bool, fallback: RegionSource?) -> PersonLayers {
            PersonLayers(personIndex: index, instanceId: person.id, personMask: body, pose: person.pose,
                         regionMask: region, faceSampleMask: sample, skinRemovedMask: removed, finalMask: final,
                         steps: steps, skinModel: model, skinExcludedPixels: excluded, skinNote: note,
                         regionDecision: decision, usedInMask: used, skinSampleSource: sampleSource,
                         silhouetteMask: silhouette, armsMask: arms, fallbackSource: fallback)
        }
    }

    /// Píxeles >= 128 de una muestra de cara (el criterio de ce_skin_model_fit).
    static func samplePixels(_ sample: [UInt8]?) -> Int {
        guard let sample else { return 0 }
        return sample.withUnsafeBufferPointer { b in
            var n = 0
            for i in 0..<b.count where b[i] >= 128 { n += 1 }
            return n
        }
    }

    /// Región (pose, silueta o corte de cabeza) y piel de una persona.
    static func runChain(person: PersonInstance, index: Int, rgba: UnsafeBufferPointer<UInt8>, width: Int,
                         height: Int, stride: Int, options: SubjectOptions, donor: Int? = nil,
                         people: [PersonInstance] = [], regionMs: inout Double,
                         skinMs: inout Double) throws -> ChainOutput {
        let body = MaskOps.binarize(person.mask)
        let bodyStats = MaskOps.stats(body, width: width, height: height)
        let floor = floorPixels(options: options, width: width, height: height)
        var out = ChainOutput(person: person, index: index, body: body, region: nil, sample: nil, removed: nil,
                              final: body, steps: [], model: nil, excluded: 0, note: nil, decision: nil,
                              fallback: body, fallbackSource: .wholePerson)

        // Muestra de piel: la propia o, sin muestra utilizable, la de otra persona.
        var skinSample = person.faceSampleMask
        var skinSource: Int? = skinSample == nil ? nil : index
        var skinPixels = samplePixels(skinSample)
        if options.adaptiveSkin, options.shareSkinModel, skinPixels < minSkinSamples, let d = donor, d < people.count,
           let donorSample = people[d].faceSampleMask {
            skinSample = donorSample
            skinSource = d
            skinPixels = samplePixels(donorSample)
        }
        let skinAvailable = options.adaptiveSkin && skinPixels >= minSkinSamples
        if options.adaptiveSkin, let sample = skinSample {
            let clock = Stopwatch()
            out.sample = sample
            out.sampleSource = skinSource
            do {
                out.model = try fitSkinModel(rgba: rgba, width: width, height: height, stride: stride,
                                             sampleMask: sample)
            } catch let e as ColorEngineError where e == .tooFewSkinSamples {
                out.note = "tooFewSkinSamples"
            }
            skinMs += clock.elapsedMs
        }

        if options.region == .clothing {
            let clock = Stopwatch()
            // Se pidió quitar la piel pero no hay modelo: los brazos (a menudo desnudos
            // con manga corta) quedan fuera; las piernas se mantienen (pantalón).
            var ro = options.regionOptions
            let upperArmsDropped = options.adaptiveSkin && !skinAvailable && ro.includeUpperArms
            if upperArmsDropped { ro.includeUpperArms = false }
            var poseRegionPixels: Int? = nil, silhouettePixels: Int? = nil
            var regionPose: Pose? = nil
            var hipsEstimated = false
            var chosen: (mask: [UInt8], pixels: Int, source: RegionSource)? = nil
            var cutFraction: Double? = nil
            var required = floor
            var armPixels: Int? = nil, armSkinPixels: Int? = nil
            var bareArmsDropped = false
            if let pose = person.pose {
                let planned = SubjectExtractor.regionPose(pose, minConfidence: ro.minConfidence)
                do {
                    var r = try clothingRegions(pose: planned.pose, options: ro, mask: body, width: width, height: height)
                    regionPose = planned.pose
                    hipsEstimated = planned.hipsEstimated
                    if ro.includeUpperArms, let model = out.model {
                        // Brazos desnudos: la piel del brazo que el modelo reconoce en luz
                        // directa delata la manga corta; la que queda en sombra no la alcanza.
                        var noArms = ro
                        noArms.includeUpperArms = false
                        let r0 = try clothingRegions(pose: planned.pose, options: noArms, mask: body, width: width,
                                                     height: height)
                        let arms = MaskOps.removed(before: r.mask, after: r0.mask)
                        let n = MaskOps.nonZero(arms)
                        armPixels = n
                        if n > 0 {
                            out.arms = arms
                            let probeClock = Stopwatch()
                            let probe = try excludeSkin(rgba: rgba, width: width, height: height, stride: stride,
                                                        model: model,
                                                        options: SkinOptions(maxMahalanobis: options.skinOptions.maxMahalanobis,
                                                                             maxExcludedFraction: 1),
                                                        mask: arms)
                            skinMs += probeClock.elapsedMs
                            armSkinPixels = probe.excluded
                            if probe.excluded >= bareArmsThreshold(armPixels: n, options: options) {
                                bareArmsDropped = true
                                ro = noArms
                                r = r0
                            }
                        } else {
                            armSkinPixels = 0
                        }
                    }
                    poseRegionPixels = r.pixels
                    let s = try clothingRegions(pose: planned.pose, options: silhouetteOptions(ro), mask: body,
                                                width: width, height: height)
                    silhouettePixels = s.pixels
                    out.silhouette = s.mask
                    out.steps.append(.poseRegions)
                    if s.pixels >= floor {
                        out.fallback = s.mask
                        out.fallbackSource = .poseSilhouette
                        required = requiredRegionPixels(silhouettePixels: s.pixels, options: options, width: width,
                                                        height: height)
                        chosen = r.pixels >= required ? (r.mask, r.pixels, .poseRegions) : (s.mask, s.pixels, .poseSilhouette)
                    }
                } catch let e as ColorEngineError where e == .poseMissing {
                    chosen = nil
                }
            }
            if chosen == nil {
                let fraction = cutHeadFraction(bodyBox: bodyStats.bbox, faceBox: person.faceBox)
                let r = cutHead(mask: body, width: width, height: height, fraction: fraction)
                guard r.pixels >= 0 else { throw ColorEngineError.engine(code: Int32(r.pixels)) }
                chosen = (r.mask, r.pixels, .headCut)
                cutFraction = fraction
                out.steps.append(.headCut)
            }
            if let chosen {
                out.final = chosen.mask
                out.region = chosen.mask
                out.decision = RegionDecision(source: chosen.source, bodyPixels: bodyStats.count, requiredPixels: required,
                                              poseRegionPixels: poseRegionPixels, silhouettePixels: silhouettePixels,
                                              regionPixels: chosen.pixels, regionPose: regionPose,
                                              hipsEstimated: hipsEstimated, headCutFraction: cutFraction,
                                              regionOptions: regionPose == nil ? nil : ro,
                                              upperArmsDropped: upperArmsDropped && regionPose != nil,
                                              armPixels: armPixels, armSkinPixels: armSkinPixels,
                                              bareArmsDropped: bareArmsDropped)
            }
            regionMs += clock.elapsedMs
        } else {
            out.decision = RegionDecision(source: .wholePerson, bodyPixels: bodyStats.count, requiredPixels: floor,
                                          poseRegionPixels: nil, silhouettePixels: nil, regionPixels: bodyStats.count,
                                          regionPose: nil, hipsEstimated: false, headCutFraction: nil)
        }
        if let model = out.model {
            let clock = Stopwatch()
            let r = try excludeSkin(rgba: rgba, width: width, height: height, stride: stride, model: model,
                                    options: options.skinOptions, mask: out.final)
            if r.guardTriggered {
                out.steps.append(.skinGuard)
            } else if r.excluded > 0 {
                out.removed = MaskOps.removed(before: out.final, after: r.mask)
                out.excluded = r.excluded
                out.final = r.mask
                out.steps.append(.skinExcluded)
            }
            // Con 0 píxeles de piel en la región no hay paso (la máscara no cambió);
            // el modelo queda en la capa.
            skinMs += clock.elapsedMs
        }
        return out
    }
}

/// Cronómetro monotónico en milisegundos.
struct Stopwatch {
    private let start = DispatchTimeNanos.now()
    var elapsedMs: Double { Double(DispatchTimeNanos.now() - start) / 1_000_000 }
}

enum DispatchTimeNanos {
    static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
}
