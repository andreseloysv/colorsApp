// Cadena de máscaras sin Vision: de las personas detectadas a la máscara que
// recibe el motor, con capas y pasos. Toda la geometría y la piel se delegan
// en el motor C (ColorEngine); aquí solo se eligen entradas y candidatas.
//
// Por persona (runChain), sobre su máscara BINARIA B (>= 128 -> 255). Si Vision
// juntó a esta persona con otras y se separó (PersonSplit.swift), el primer paso
// es [splitByPose] o [splitByFace]:
//   suelo = max(ceil(minCoverage·W·H), 1)
//   muestra de piel: la propia o, con < 50 muestras y shareSkinModel, la de la
//     persona con más muestras (skinSampleSource); modelo = fitSkinModel(muestra).
//   region == .clothing, opciones ro = regionOptions:
//     con pose: pose' = regionPose(pose) (caderas estimadas en planos medios)
//       sin modelo (se pidió piel y no hay muestra con >= 50 muestras) y ro con brazos:
//         prueba de mangas: T = clothingRegions(pose', ro sin brazos ni piernas, B) (torso),
//         A = clothingRegions(pose', ro) − clothingRegions(pose', ro sin brazos);
//         parecidos = excludeSkin(fitSkinModel(T), Mahalanobis sleeveMatchMahalanobis, maxExcluded 1, A).excluded;
//         si parecidos >= ceil(sleeveMatchFraction·|A|) los brazos se quedan (mangas); si no,
//         ro sin brazos (con manga corta serían piel que nadie quita)
//       R = clothingRegions(pose', ro, B)
//       con modelo M0 (cara): piel(Z) = excludeSkin(M, Mahalanobis maxMahalanobis, maxExcluded 1, Z).excluded
//         brazos A = R − clothingRegions(pose', ro sin brazos) (si ro tiene brazos),
//         piernas P = R − clothingRegions(pose', ro sin piernas) (si ro tiene piernas);
//         desnudo(Z) = piel(Z) >= ceil(bareArmsSkinFraction·|Z|)  (con M0)
//         si desnudo(A) o desnudo(P): aprendizaje, hasta skinLearningIterations pasadas sobre R:
//           C = candidatos de excludeSkin(M, Mahalanobis skinLearningMahalanobis, maxExcluded 1, R);
//           parar si |C| = 0, |C| > maxExcludedFraction·|R| o no añade píxeles;
//           M' = fitSkinModel(muestra ∪ C); parar (sin aceptar) si piel(R) con M' > maxExcludedFraction·|R|;
//           muestra = muestra ∪ C; M = M'
//         brazos desnudos con el modelo final M: si desnudo(A): ro sin brazos, R sin brazos
//       S = clothingRegions(pose', silhouetteOptions(ro), B)            (silueta)
//       requerido = max(ceil(minRegionFraction·|S|), suelo)
//       |S| >= suelo:  |R| >= requerido -> R [poseRegions]; si no -> S [poseRegions] (silueta)
//       |S| <  suelo:  la pose no describe a esta persona -> 3.
//       (CE_ERR_POSE: sin candidatas de pose -> 3.)
//     3. cutHead(B, cutHeadFraction(bbox(B), cara))                        -> [.., headCut]
//   region == .wholePerson: B
//   modelo: F = final; E = excludeSkin(M, skinOptions, F) -> [skinExcluded] si quitó algún píxel, o
//     [skinGuard] (máscara intacta); con < 50 muestras no se aplica (skinNote). Con piel quitada S:
//     crecimiento (histéresis): C = candidatos de excludeSkin(M, Mahalanobis skinGrowMahalanobis,
//     maxExcluded 1, E); G = píxeles de C alcanzables desde S por vecindad de 8 dentro de C en
//     <= skinGrowRadius pasos; si |S| + |G| <= maxExcludedFraction·|F| y |G| <= skinGrowMaxRatio·|S|:
//     E = E − G. Después el halo:
//     fuera los píxeles a Chebyshev <= skinHaloRadius de S ∪ G.
//   respaldo de la persona: S si hay silueta >= suelo, si no B (fallbackSource).
// largestPerson / selectedPerson: la salida de la persona si |salida| >= suelo;
//   si no, el respaldo si llega al suelo [wholePerson]; si no, sin máscara [none].
// allPeople: la unión (máximo por píxel) de las salidas con |salida| >= suelo; si
//   ninguna llega, la unión de los respaldos que lleguen [wholePerson]; si no, [none].
// off: sin máscara [none]. Sin personas: sin máscara [noPeople]. Si la detección descartó
// personas fantasma (`mask(detection:)`/`compute`), los pasos empiezan por [rejectedPhantom].
// Regiones de prenda (computeGarmentRegions, ADR-011): con la máscara ya decidida, para cada
// persona que aporta máscara y cuya región sale de la pose (poseRegions / poseSilhouette, también
// el respaldo con la silueta): mapa = ce_mask_garment_regions(pose', silhouetteOptions(ro), máscara
// de esa persona) con 1 arriba y 2 abajo; si pose' tiene caderas estimadas, 2 -> 1 (no se ve la
// parte de abajo). largestPerson / selectedPerson: el mapa de la persona es
// SubjectMaskResult.garmentRegions y los pasos terminan en [garmentRegions]; allPeople: un mapa
// por persona en sus capas (SubjectMaskResult.garmentRegions nil). Sin pose: nil y sin paso.
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
                     stride: Int, options: SubjectOptions, detectTimings: [String: Double],
                     rejected: [RejectedPerson] = []) throws -> SubjectMaskResult {
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
        guard options.sleeveMatchFraction.isFinite, options.sleeveMatchFraction >= 0, options.sleeveMatchFraction <= 1 else {
            throw SubjectError.invalidOptions("sleeveMatchFraction debe estar en 0...1")
        }
        guard (0...maxLearningIterations).contains(options.skinLearningIterations) else {
            throw SubjectError.invalidOptions("skinLearningIterations debe estar en 0...\(maxLearningIterations)")
        }
        guard (0...maxHaloRadius).contains(options.skinHaloRadius) else {
            throw SubjectError.invalidOptions("skinHaloRadius debe estar en 0...\(maxHaloRadius)")
        }
        guard (0...maxGrowRadius).contains(options.skinGrowRadius) else {
            throw SubjectError.invalidOptions("skinGrowRadius debe estar en 0...\(maxGrowRadius)")
        }
        guard options.skinGrowMahalanobis.isFinite, options.skinGrowMahalanobis >= 0 else {
            throw SubjectError.invalidOptions("skinGrowMahalanobis debe ser finito y >= 0")
        }
        guard options.skinGrowMaxRatio.isFinite, options.skinGrowMaxRatio >= 0, options.skinGrowMaxRatio <= 1 else {
            throw SubjectError.invalidOptions("skinGrowMaxRatio debe estar en 0...1")
        }
        guard options.skinLearningMahalanobis.isFinite, options.skinLearningMahalanobis >= 0,
              options.sleeveMatchMahalanobis.isFinite, options.sleeveMatchMahalanobis >= 0 else {
            throw SubjectError.invalidOptions("skinLearningMahalanobis y sleeveMatchMahalanobis deben ser finitos y >= 0")
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

        func finish(chosen: Int?, mask: [UInt8]?, steps: [MaskFallback], persons: [PersonLayers],
                    garmentRegions: [UInt8]? = nil) -> SubjectMaskResult {
            let coverage = mask.map { MaskOps.coverage($0, width: width, height: height) } ?? 0
            timings["mask"] = clock.elapsedMs
            timings["total"] = (detectTimings["detect"] ?? 0) + clock.elapsedMs
            let layers = SubjectLayers(width: width, height: height, persons: persons, allPeopleOverlay: overlay,
                                       finalMask: mask)
            let allSteps = rejected.isEmpty ? steps : [.rejectedPhantom] + steps
            return SubjectMaskResult(width: width, height: height, people: people, chosenIndex: chosen, mask: mask,
                                     steps: allSteps, timings: timings, maskCoverage: coverage, layers: layers,
                                     rejectedPhantoms: rejected, garmentRegions: garmentRegions)
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
            var garment: (regions: [UInt8], stats: GarmentRegionStats)? = nil
            if options.computeGarmentRegions, let m = mask {
                let tg = clock.elapsedMs
                garment = try garmentRegionMap(decision: chain.decision, region: options.region, mask: m, width: width,
                                               height: height)
                if garment != nil { steps.append(.garmentRegions) }
                timings["garments"] = clock.elapsedMs - tg
            }
            let layer = chain.layers(steps: steps, used: mask != nil && fallback == nil, fallback: fallback,
                                     garment: garment)
            return finish(chosen: index, mask: mask, steps: steps, persons: [layer], garmentRegions: garment?.regions)
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
            // Regiones de prenda por persona: sobre la máscara que cada una aporta a la unión
            // (su salida, o su respaldo si la unión volvió a los respaldos).
            var garments = [(regions: [UInt8], stats: GarmentRegionStats)?](repeating: nil, count: chains.count)
            if options.computeGarmentRegions, mask != nil {
                let tg = clock.elapsedMs
                for (i, c) in chains.enumerated() {
                    let contributed: [UInt8]? = used[i] ? c.final : (fallbacks[i] != nil ? c.fallback : nil)
                    guard let m = contributed else { continue }
                    garments[i] = try garmentRegionMap(decision: c.decision, region: options.region, mask: m,
                                                       width: width, height: height)
                }
                if garments.contains(where: { $0 != nil }) { steps.append(.garmentRegions) }
                timings["garments"] = clock.elapsedMs - tg
            }
            let persons = chains.indices.map { i -> PersonLayers in
                var personSteps = chains[i].steps
                if garments[i] != nil { personSteps.append(.garmentRegions) }
                return chains[i].layers(steps: personSteps, used: used[i], fallback: fallbacks[i], garment: garments[i])
            }
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
    /// Cota de `skinLearningIterations`.
    public static let maxLearningIterations = 8
    /// Cota de `skinHaloRadius`.
    public static let maxHaloRadius = 8
    /// Cota de `skinGrowRadius`.
    public static let maxGrowRadius = 64

    /// Píxeles de brazo parecidos al torso para conservar los brazos sin modelo de piel:
    /// max(1, ceil(sleeveMatchFraction · armPixels)).
    public static func sleeveThreshold(armPixels: Int, options: SubjectOptions) -> Int {
        max(1, Int((options.sleeveMatchFraction * Double(armPixels)).rounded(.up)))
    }

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
        var learnedSamples: [[UInt8]] = []
        var learningPixels: [Int] = []
        var legs: [UInt8]? = nil
        var skinExcludedMask: [UInt8]? = nil
        var haloPixels = 0
        var sleeveTorso: [UInt8]? = nil
        var grownPixels = 0
        var grownMask: [UInt8]? = nil
        var growCandidates: Int? = nil

        func layers(steps: [MaskFallback], used: Bool, fallback: RegionSource?,
                    garment: (regions: [UInt8], stats: GarmentRegionStats)? = nil) -> PersonLayers {
            PersonLayers(personIndex: index, instanceId: person.id, personMask: body, pose: person.pose,
                         regionMask: region, faceSampleMask: sample, skinRemovedMask: removed, finalMask: final,
                         steps: steps, skinModel: model, skinExcludedPixels: excluded, skinNote: note,
                         regionDecision: decision, usedInMask: used, skinSampleSource: sampleSource,
                         silhouetteMask: silhouette, armsMask: arms, fallbackSource: fallback,
                         learnedSampleMasks: learnedSamples, skinLearningPixels: learningPixels,
                         skinExcludedMask: skinExcludedMask, skinHaloPixels: haloPixels, sleeveTorsoMask: sleeveTorso,
                         legsMask: legs, skinGrownPixels: grownPixels, skinGrownMask: grownMask,
                         skinGrowCandidatePixels: growCandidates, garmentRegions: garment?.regions,
                         garmentRegionStats: garment?.stats)
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
        // Persona separada de una instancia que Vision juntó con otras: el paso va
        // primero (PersonSplit.swift, ADR-010).
        if let split = person.splitStep {
            out.steps.append(split)
        }

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
            var ro = options.regionOptions
            let skinProbe = SkinOptions(maxMahalanobis: options.skinOptions.maxMahalanobis, maxExcludedFraction: 1)
            var upperArmsDropped = false
            var poseRegionPixels: Int? = nil, silhouettePixels: Int? = nil
            var regionPose: Pose? = nil
            var hipsEstimated = false
            var chosen: (mask: [UInt8], pixels: Int, source: RegionSource)? = nil
            var cutFraction: Double? = nil
            var required = floor
            var armPixels: Int? = nil, armSkinPixels: Int? = nil
            var legPixels: Int? = nil, legSkinPixels: Int? = nil
            var sleevePixels: Int? = nil, sleeveMatchPixels: Int? = nil
            var sleevesKept = false
            var bareArmsDropped = false
            if let pose = person.pose {
                let planned = SubjectExtractor.regionPose(pose, minConfidence: ro.minConfidence)
                do {
                    func regions(_ o: RegionOptions) throws -> (mask: [UInt8], pixels: Int) {
                        try clothingRegions(pose: planned.pose, options: o, mask: body, width: width, height: height)
                    }
                    func probe(_ model: SkinModel, _ opts: SkinOptions, _ zone: [UInt8]) throws -> Int {
                        let probeClock = Stopwatch()
                        defer { skinMs += probeClock.elapsedMs }
                        return try excludeSkin(rgba: rgba, width: width, height: height, stride: stride, model: model,
                                               options: opts, mask: zone).excluded
                    }
                    var noArms = ro
                    noArms.includeUpperArms = false
                    // Se pidió quitar la piel pero no hay modelo: los brazos se quitan salvo que
                    // sean mangas de la prenda del torso (con manga corta serían piel que nadie quita).
                    if options.adaptiveSkin && !skinAvailable && ro.includeUpperArms {
                        var torsoOptions = noArms
                        torsoOptions.includeLegs = false
                        torsoOptions.includeLowerLegs = false
                        let torso = try regions(torsoOptions)
                        let arms = MaskOps.removed(before: try regions(ro).mask, after: try regions(noArms).mask)
                        let n = MaskOps.nonZero(arms)
                        sleevePixels = n
                        if n > 0 {
                            out.arms = arms
                            out.sleeveTorso = torso.mask
                            if torso.pixels >= minSkinSamples, options.sleeveMatchFraction < 1 {
                                let torsoModel = try fitSkinModel(rgba: rgba, width: width, height: height, stride: stride,
                                                                  sampleMask: torso.mask)
                                let match = try probe(torsoModel, SkinOptions(maxMahalanobis: options.sleeveMatchMahalanobis,
                                                                              maxExcludedFraction: 1), arms)
                                sleeveMatchPixels = match
                                sleevesKept = match >= sleeveThreshold(armPixels: n, options: options)
                            }
                        }
                        if !sleevesKept {
                            ro = noArms
                            upperArmsDropped = true
                        }
                    }
                    var r = try regions(ro)
                    regionPose = planned.pose
                    hipsEstimated = planned.hipsEstimated
                    if let faceModel = out.model {
                        var armsZone: [UInt8]? = nil, r0: (mask: [UInt8], pixels: Int)? = nil
                        var bareArms = false, bareLegs = false
                        if ro.includeUpperArms {
                            let without = try regions(noArms)
                            r0 = without
                            let arms = MaskOps.removed(before: r.mask, after: without.mask)
                            let n = MaskOps.nonZero(arms)
                            armPixels = n
                            armSkinPixels = 0
                            if n > 0 {
                                out.arms = arms
                                armsZone = arms
                                armSkinPixels = try probe(faceModel, skinProbe, arms)
                                bareArms = armSkinPixels! >= bareArmsThreshold(armPixels: n, options: options)
                            }
                        }
                        if ro.includeLegs || ro.includeLowerLegs {
                            var noLegs = ro
                            noLegs.includeLegs = false
                            noLegs.includeLowerLegs = false
                            let legs = MaskOps.removed(before: r.mask, after: try regions(noLegs).mask)
                            let n = MaskOps.nonZero(legs)
                            legPixels = n
                            if n > 0 { out.legs = legs }
                            legSkinPixels = n > 0 ? try probe(faceModel, skinProbe, legs) : 0
                            bareLegs = n > 0 && legSkinPixels! >= bareArmsThreshold(armPixels: n, options: options)
                        }
                        // Piel del cuerpo: con brazos o piernas desnudos, la muestra se amplía con la
                        // piel de la región según el modelo vigente y se reajusta el modelo.
                        if (bareArms || bareLegs), options.skinLearningIterations > 0, var sample = out.sample {
                            let zonePixels = r.pixels
                            let learnOptions = SkinOptions(maxMahalanobis: options.skinLearningMahalanobis,
                                                           maxExcludedFraction: 1)
                            var model = faceModel
                            for _ in 0..<options.skinLearningIterations {
                                let learnClock = Stopwatch()
                                let candidates = try excludeSkin(rgba: rgba, width: width, height: height, stride: stride,
                                                                 model: model, options: learnOptions, mask: r.mask)
                                skinMs += learnClock.elapsedMs
                                guard candidates.excluded > 0,
                                      Double(candidates.excluded) <= options.skinOptions.maxExcludedFraction * Double(zonePixels)
                                else { break }
                                let grown = MaskOps.union([sample, MaskOps.removed(before: r.mask, after: candidates.mask)]) ?? sample
                                let added = samplePixels(grown) - samplePixels(sample)
                                guard added > 0 else { break }
                                let fitClock = Stopwatch()
                                let grownModel = try fitSkinModel(rgba: rgba, width: width, height: height, stride: stride,
                                                                  sampleMask: grown)
                                skinMs += fitClock.elapsedMs
                                // El modelo ampliado no puede disparar la salvaguarda en la región: si
                                // quitaría más de maxExcludedFraction, la pasada no se acepta (aprender
                                // nunca deja más piel que no aprender).
                                guard Double(try probe(grownModel, skinProbe, r.mask))
                                        <= options.skinOptions.maxExcludedFraction * Double(zonePixels) else { break }
                                model = grownModel
                                sample = grown
                                out.learningPixels.append(candidates.excluded)
                                out.learnedSamples.append(grown)
                            }
                            if !out.learnedSamples.isEmpty {
                                out.model = model
                            }
                        }
                        // Brazos desnudos con el modelo final: la piel del brazo que el modelo
                        // reconoce delata la manga corta; la que queda en sombra no la alcanza.
                        if let arms = armsZone, let without = r0, let n = armPixels, let model = out.model {
                            if !out.learnedSamples.isEmpty {
                                armSkinPixels = try probe(model, skinProbe, arms)
                            }
                            if armSkinPixels! >= bareArmsThreshold(armPixels: n, options: options) {
                                bareArmsDropped = true
                                ro = noArms
                                r = without
                            }
                        }
                    }
                    poseRegionPixels = r.pixels
                    let s = try regions(silhouetteOptions(ro))
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
                                              bareArmsDropped: bareArmsDropped, legPixels: legPixels,
                                              legSkinPixels: legSkinPixels, sleevePixels: sleevePixels,
                                              sleeveMatchPixels: sleeveMatchPixels, sleevesKept: sleevesKept)
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
                out.skinExcludedMask = r.mask
                let seeds = MaskOps.removed(before: out.final, after: r.mask)
                var kept = r.mask
                var skin = seeds
                // Piel en sombra conectada con la quitada (histéresis con el mismo modelo).
                if options.skinGrowRadius > 0, options.skinGrowMahalanobis > options.skinOptions.maxMahalanobis {
                    let weak = try excludeSkin(rgba: rgba, width: width, height: height, stride: stride, model: model,
                                               options: SkinOptions(maxMahalanobis: options.skinGrowMahalanobis,
                                                                    maxExcludedFraction: 1), mask: r.mask)
                    out.growCandidates = weak.excluded
                    if weak.excluded > 0 {
                        let candidates = MaskOps.removed(before: r.mask, after: weak.mask)
                        let grown = MaskOps.geodesicGrow(seeds: seeds, allowed: candidates, width: width, height: height,
                                                         radius: options.skinGrowRadius)
                        let n = MaskOps.nonZero(grown)
                        let limit = options.skinOptions.maxExcludedFraction * Double(MaskOps.nonZero(out.final))
                        if n > 0, Double(r.excluded + n) <= limit, Double(n) <= options.skinGrowMaxRatio * Double(r.excluded) {
                            for i in 0..<kept.count where grown[i] != 0 { kept[i] = 0 }
                            skin = MaskOps.union([seeds, grown]) ?? seeds
                            out.grownPixels = n
                            out.grownMask = grown
                        }
                    }
                }
                let halo = MaskOps.removeHalo(kept, around: skin, width: width, height: height, radius: options.skinHaloRadius)
                out.haloPixels = halo.removed
                out.removed = MaskOps.removed(before: out.final, after: halo.mask)
                out.excluded = r.excluded + out.grownPixels + halo.removed
                out.final = halo.mask
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
