// Port literal de apple/SubjectKit/Sources/SubjectKit/SubjectChain.swift:
// de las personas detectadas a la máscara que recibe el motor, con capas,
// pasos y tiempos. Toda la geometría de regiones y la piel las decide el
// motor C vía :engine (clothingRegions, cutHead, fitSkinModel, excludeSkin,
// garmentRegions); aquí solo se eligen entradas y candidatas, con las
// mismas constantes y el mismo orden que en iOS (ver la cabecera del Swift:
// suelo, muestra propia o compartida, prueba de mangas sin modelo, piel del
// cuerpo aprendida, brazos desnudos, regiones frente a silueta, exclusión
// con crecimiento en sombra conectado y halo, respaldo y mapa de prendas).
package com.andreseloy.colorsapp.subject

import com.andreseloy.colorsapp.engine.ColorEngine
import com.andreseloy.colorsapp.engine.EngineException
import com.andreseloy.colorsapp.engine.EngineImage
import com.andreseloy.colorsapp.engine.Pose
import com.andreseloy.colorsapp.engine.RegionOptions
import com.andreseloy.colorsapp.engine.SkinModel
import com.andreseloy.colorsapp.engine.SkinOptions
import kotlin.math.ceil
import kotlin.math.max

/** Detección con detalle: fantasmas descartadas y tiempos del detector. */
data class PeopleDetectionResult(
    val people: List<PersonDetection>,
    val rejectedPhantoms: List<PersonDetection> = emptyList(),
    val timingsMs: Map<String, Double> = emptyMap(),
)

/** Detector que además informa de fantasmas y tiempos (detectPeopleDetailed). */
interface DetailedPersonDetector : PersonDetector {
    suspend fun detectDetailed(image: EngineImage): PeopleDetectionResult

    override suspend fun detect(image: EngineImage): List<PersonDetection> =
        detectDetailed(image).people
}

object SubjectChain {
    /** Muestras mínimas de una muestra de cara utilizable (CE_SKIN_MIN_SAMPLES). */
    const val MIN_SKIN_SAMPLES = 50
    const val MAX_LEARNING_ITERATIONS = 8
    const val MAX_HALO_RADIUS = 8
    const val MAX_GROW_RADIUS = 64

    /** Suelo absoluto en píxeles: max(1, ceil(minCoverage · W · H)). */
    fun floorPixels(options: SubjectOptions, width: Int, height: Int): Int =
        max(1, ceil(options.minCoverage * (width * height)).toInt())

    /** Píxeles que deben tener las regiones frente a una silueta dada. */
    fun requiredRegionPixels(silhouettePixels: Int, options: SubjectOptions, width: Int, height: Int): Int =
        max(
            ceil(options.minRegionFraction * silhouettePixels).toInt(),
            floorPixels(options, width, height),
        )

    /** Píxeles de brazo que deben ser piel para quitar los brazos. */
    fun bareArmsThreshold(armPixels: Int, options: SubjectOptions): Int =
        max(1, ceil(options.bareArmsSkinFraction * armPixels).toInt())

    /** Píxeles de brazo parecidos al torso para conservarlos sin modelo. */
    fun sleeveThreshold(armPixels: Int, options: SubjectOptions): Int =
        max(1, ceil(options.sleeveMatchFraction * armPixels).toInt())

    /** Para cada persona, la otra con más muestras de cara (>=50) o null. */
    internal fun skinDonors(people: List<PersonDetection>): List<Int?> {
        val counts = people.map { samplePixels(it.faceSampleMask?.bytes) }
        val ranked = counts.indices.filter { counts[it] >= MIN_SKIN_SAMPLES }
            .sortedWith(compareByDescending<Int> { counts[it] }.thenBy { it })
        return people.indices.map { i -> ranked.firstOrNull { it != i } }
    }

    /** Píxeles >= 128 de una muestra de cara (el criterio de ce_skin_model_fit). */
    fun samplePixels(sample: ByteArray?): Int {
        if (sample == null) return 0
        var n = 0
        for (v in sample) if (MaskOps.u(v) >= 128) n++
        return n
    }

    private fun validateOptions(options: SubjectOptions) {
        fun in01(name: String, v: Double) {
            require(v.isFinite() && v in 0.0..1.0) { "$name debe estar en 0...1" }
        }
        in01("minCoverage", options.minCoverage)
        in01("minRegionFraction", options.minRegionFraction)
        in01("bareArmsSkinFraction", options.bareArmsSkinFraction)
        in01("sleeveMatchFraction", options.sleeveMatchFraction)
        in01("skinGrowMaxRatio", options.skinGrowMaxRatio)
        require(options.skinLearningIterations in 0..MAX_LEARNING_ITERATIONS) {
            "skinLearningIterations debe estar en 0...$MAX_LEARNING_ITERATIONS"
        }
        require(options.skinHaloRadius in 0..MAX_HALO_RADIUS) { "skinHaloRadius debe estar en 0...$MAX_HALO_RADIUS" }
        require(options.skinGrowRadius in 0..MAX_GROW_RADIUS) { "skinGrowRadius debe estar en 0...$MAX_GROW_RADIUS" }
        require(options.skinGrowMahalanobis.isFinite() && options.skinGrowMahalanobis >= 0) {
            "skinGrowMahalanobis debe ser finito y >= 0"
        }
        require(
            options.skinLearningMahalanobis.isFinite() && options.skinLearningMahalanobis >= 0 &&
                options.sleeveMatchMahalanobis.isFinite() && options.sleeveMatchMahalanobis >= 0,
        ) { "skinLearningMahalanobis y sleeveMatchMahalanobis deben ser finitos y >= 0" }
    }

    /**
     * Aplica la cadena a personas ya detectadas sobre el raster [image].
     * [detectTimingsMs] trae los tiempos del detector (clave "detect").
     */
    fun mask(
        unsorted: List<PersonDetection>,
        image: EngineImage,
        options: SubjectOptions,
        detectTimingsMs: Map<String, Double> = emptyMap(),
        rejected: List<PersonDetection> = emptyList(),
    ): SubjectMaskResult {
        val startNs = System.nanoTime()
        fun elapsed(): Double = (System.nanoTime() - startNs) / 1_000_000.0
        val width = image.width
        val height = image.height
        require(width >= 1 && height >= 1) { "dimensiones inválidas ${width}x$height" }
        validateOptions(options)
        val count = width * height
        for (p in unsorted) {
            require(p.instanceMask.bytes.size >= count) {
                "máscara de la persona ${p.id}: ${p.instanceMask.bytes.size} != $count"
            }
            p.faceSampleMask?.let {
                require(it.bytes.size >= count) { "muestra de la persona ${p.id} no mide W*H" }
            }
        }
        val people = PersonSplitter.sortPeople(unsorted, width, height)
        val timings = LinkedHashMap(detectTimingsMs)
        val overlay = MaskOps.instanceOverlay(people, width, height)

        fun finish(
            chosen: Int?, maskBytes: ByteArray?, steps: List<MaskStep>,
            persons: List<PersonLayers>, garmentBytes: ByteArray?,
            peopleResults: List<PersonInstanceResult>,
        ): SubjectMaskResult {
            timings["mask"] = elapsed()
            timings["total"] = (detectTimingsMs["detect"] ?: 0.0) + elapsed()
            val layers = SubjectLayers(
                width, height, persons,
                MaskBuffer(width, height, overlay),
                maskBytes?.let { MaskBuffer(width, height, it) },
            )
            val allSteps = if (rejected.isEmpty()) steps else listOf(MaskStep.REJECTED_PHANTOM) + steps
            return SubjectMaskResult(
                width = width, height = height,
                people = peopleResults,
                chosenIndex = chosen,
                mask = maskBytes?.let { MaskBuffer(width, height, it) },
                garmentRegions = garmentBytes?.let { MaskBuffer(width, height, it) },
                steps = allSteps,
                timingsMs = timings,
                layers = layers,
                rejectedPhantoms = rejected.map { it.asResult(width, height) },
            )
        }

        fun baseResults(): MutableList<PersonInstanceResult> =
            people.map { it.asResult(width, height) }.toMutableList()

        if (options.mode == SubjectMode.OFF) {
            return finish(null, null, listOf(MaskStep.NONE), emptyList(), null, baseResults())
        }
        if (people.isEmpty()) {
            return finish(null, null, listOf(MaskStep.NO_PEOPLE), emptyList(), null, baseResults())
        }

        val floor = floorPixels(options, width, height)
        val donors = skinDonors(people)
        var regionMs = 0.0
        var skinMs = 0.0
        if (options.mode != SubjectMode.ALL_PEOPLE) {
            var index = 0
            val sel = options.selectedIndex
            if (options.mode == SubjectMode.SELECTED_PERSON && sel != null && sel in people.indices) {
                index = sel
            }
            val chain = runChain(people[index], index, image, options, donors[index], people)
            regionMs += chain.regionMs
            skinMs += chain.skinMs
            val t0 = elapsed()
            val steps = chain.steps.toMutableList()
            var maskBytes: ByteArray? = chain.finalMask
            var fallback: RegionSource? = null
            if (MaskOps.nonZero(chain.finalMask) < floor) {
                if (MaskOps.nonZero(chain.fallback) >= floor) {
                    maskBytes = chain.fallback
                    fallback = chain.fallbackSource
                    steps.add(MaskStep.WHOLE_PERSON)
                } else {
                    maskBytes = null
                    steps.add(MaskStep.NONE)
                }
            }
            timings["regions"] = regionMs
            timings["skin"] = skinMs
            timings["coverage"] = elapsed() - t0
            var garment: Pair<ByteArray, GarmentRegionStats>? = null
            if (options.computeGarmentRegions && maskBytes != null) {
                val tg = elapsed()
                garment = RegionPlanning.garmentRegionMap(chain.decision, options.region, maskBytes, width, height)
                if (garment != null) steps.add(MaskStep.GARMENT_REGIONS)
                timings["garments"] = elapsed() - tg
            }
            val layer = chain.toLayers(steps, used = maskBytes != null && fallback == null, fallback, garment)
            val results = baseResults()
            results[index] = people[index].asResult(
                width, height, finalMask = chain.finalMask,
                garment = garment?.first, steps = steps,
            )
            return finish(index, maskBytes, steps, listOf(layer), garment?.first, results)
        } else {
            val chains = people.mapIndexed { i, p ->
                runChain(p, i, image, options, donors[i], people).also {
                    regionMs += it.regionMs
                    skinMs += it.skinMs
                }
            }
            val t0 = elapsed()
            val steps = ArrayList<MaskStep>()
            for (c in chains) for (s in c.steps) if (s !in steps) steps.add(s)
            val used = chains.map { MaskOps.nonZero(it.finalMask) >= floor }
            var maskBytes = MaskOps.union(chains.zip(used).filter { it.second }.map { it.first.finalMask })
            val fallbacks = MutableList<RegionSource?>(chains.size) { null }
            if (maskBytes == null) {
                val bodies = ArrayList<ByteArray>()
                for ((i, c) in chains.withIndex()) {
                    if (MaskOps.nonZero(c.fallback) >= floor) {
                        bodies.add(c.fallback)
                        fallbacks[i] = c.fallbackSource
                    }
                }
                val whole = MaskOps.union(bodies)
                if (whole != null) {
                    maskBytes = whole
                    steps.add(MaskStep.WHOLE_PERSON)
                } else {
                    steps.add(MaskStep.NONE)
                }
            }
            timings["regions"] = regionMs
            timings["skin"] = skinMs
            timings["coverage"] = elapsed() - t0
            val garments = MutableList<Pair<ByteArray, GarmentRegionStats>?>(chains.size) { null }
            if (options.computeGarmentRegions && maskBytes != null) {
                val tg = elapsed()
                for ((i, c) in chains.withIndex()) {
                    val contributed: ByteArray? =
                        if (used[i]) c.finalMask else if (fallbacks[i] != null) c.fallback else null
                    if (contributed == null) continue
                    garments[i] = RegionPlanning.garmentRegionMap(c.decision, options.region, contributed, width, height)
                }
                if (garments.any { it != null }) steps.add(MaskStep.GARMENT_REGIONS)
                timings["garments"] = elapsed() - tg
            }
            val results = baseResults()
            val persons = chains.indices.map { i ->
                val personSteps = chains[i].steps.toMutableList()
                if (garments[i] != null) personSteps.add(MaskStep.GARMENT_REGIONS)
                results[i] = people[i].asResult(
                    width, height, finalMask = chains[i].finalMask,
                    garment = garments[i]?.first, steps = personSteps,
                )
                chains[i].toLayers(personSteps, used[i], fallbacks[i], garments[i])
            }
            return finish(null, maskBytes, steps, persons, null, results)
        }
    }

    private fun PersonDetection.asResult(
        width: Int, height: Int,
        finalMask: ByteArray? = null,
        garment: ByteArray? = null,
        steps: List<MaskStep> = emptyList(),
    ): PersonInstanceResult = PersonInstanceResult(
        id = id,
        coverage = MaskOps.coverage(instanceMask.bytes, width, height),
        finalMask = finalMask?.let { MaskBuffer(width, height, it) },
        garmentRegions = garment?.let { MaskBuffer(width, height, it) },
        instanceMask = instanceMask,
        pose = pose,
        splitFrom = splitFrom,
        steps = steps,
    )

    /** Salida interna de la cadena de una persona (ChainOutput del Swift). */
    internal class ChainOutput(
        val person: PersonDetection,
        val index: Int,
        val body: ByteArray,
        var finalMask: ByteArray,
        var fallback: ByteArray,
        var fallbackSource: RegionSource,
    ) {
        var region: ByteArray? = null
        var silhouette: ByteArray? = null
        var arms: ByteArray? = null
        var sample: ByteArray? = null
        var removed: ByteArray? = null
        val steps = ArrayList<MaskStep>()
        var model: SkinModel? = null
        var excluded: Int = 0
        var note: String? = null
        var decision: RegionDecision? = null
        var sampleSource: Int? = null
        var learnedSamples: List<ByteArray> = emptyList()
        var learningPixels: List<Int> = emptyList()
        var legs: ByteArray? = null
        var skinExcludedMask: ByteArray? = null
        var haloPixels: Int = 0
        var sleeveTorso: ByteArray? = null
        var grownPixels: Int = 0
        var grownMask: ByteArray? = null
        var growCandidates: Int? = null
        var regionMs: Double = 0.0
        var skinMs: Double = 0.0

        fun toLayers(
            steps: List<MaskStep>, used: Boolean, fallback: RegionSource?,
            garment: Pair<ByteArray, GarmentRegionStats>?,
        ): PersonLayers {
            val w = person.instanceMask.width
            val h = person.instanceMask.height
            fun mb(b: ByteArray?) = b?.let { MaskBuffer(w, h, it) }
            return PersonLayers(
                personIndex = index, instanceId = person.id,
                personMask = MaskBuffer(w, h, body), pose = person.pose,
                regionMask = mb(region), faceSampleMask = mb(sample),
                skinRemovedMask = mb(removed), finalMask = MaskBuffer(w, h, finalMask),
                steps = steps, skinModel = model, skinExcludedPixels = excluded,
                skinNote = note, regionDecision = decision, usedInMask = used,
                skinSampleSource = sampleSource, silhouetteMask = mb(silhouette),
                armsMask = mb(arms), fallbackSource = fallback,
                learnedSampleMasks = learnedSamples.map { MaskBuffer(w, h, it) },
                skinLearningPixels = learningPixels, skinExcludedMask = mb(skinExcludedMask),
                skinHaloPixels = haloPixels, sleeveTorsoMask = mb(sleeveTorso),
                legsMask = mb(legs), skinGrownPixels = grownPixels,
                skinGrownMask = mb(grownMask), skinGrowCandidatePixels = growCandidates,
                garmentRegions = mb(garment?.first), garmentRegionStats = garment?.second,
            )
        }
    }

    /** Región (pose, silueta o corte de cabeza) y piel de una persona. */
    internal fun runChain(
        person: PersonDetection, index: Int, image: EngineImage,
        options: SubjectOptions, donor: Int?, people: List<PersonDetection>,
    ): ChainOutput {
        val width = image.width
        val height = image.height
        val body = MaskOps.binarize(person.instanceMask.bytes)
        val bodyStats = MaskOps.stats(body, width, height)
        val floor = floorPixels(options, width, height)
        val out = ChainOutput(person, index, body, body, body, RegionSource.WHOLE_PERSON)
        person.splitStep?.let { out.steps.add(it) }

        fun nowMs(): Double = System.nanoTime() / 1_000_000.0

        // Muestra de piel: la propia o, sin muestra utilizable, la de otra persona.
        var skinSample: ByteArray? = person.faceSampleMask?.bytes
        var skinSource: Int? = if (skinSample == null) null else index
        var skinPixels = samplePixels(skinSample)
        if (options.adaptiveSkin && options.shareSkinModel && skinPixels < MIN_SKIN_SAMPLES &&
            donor != null && donor in people.indices
        ) {
            val donorSample = people[donor].faceSampleMask?.bytes
            if (donorSample != null) {
                skinSample = donorSample
                skinSource = donor
                skinPixels = samplePixels(donorSample)
            }
        }
        val skinAvailable = options.adaptiveSkin && skinPixels >= MIN_SKIN_SAMPLES
        if (options.adaptiveSkin && skinSample != null) {
            val t0 = nowMs()
            out.sample = skinSample
            out.sampleSource = skinSource
            try {
                out.model = ColorEngine.fitSkinModel(image, skinSample)
            } catch (e: EngineException.Engine) {
                if (e.code == EngineException.Engine.ERR_SKIN_SAMPLES) out.note = "tooFewSkinSamples" else throw e
            }
            out.skinMs += nowMs() - t0
        }

        fun regions(pose: Pose, o: RegionOptions, mask: ByteArray): Pair<ByteArray, Int> {
            val m = mask.copyOf()
            val n = ColorEngine.clothingRegions(pose, m, width, height, o)
            return m to n
        }

        fun exclude(mask: ByteArray, model: SkinModel, opts: SkinOptions): Triple<ByteArray, Int, Boolean> {
            val m = mask.copyOf()
            val (excluded, guard) = ColorEngine.excludeSkin(image, model, m, opts)
            return Triple(m, excluded, guard)
        }

        if (options.region == RegionMode.CLOTHING) {
            val regionStart = nowMs()
            var ro = options.regionOptions ?: RegionOptions.DEFAULT
            val skinProbe = SkinOptions(options.skinOptions.maxMahalanobis, 1.0)
            var upperArmsDropped = false
            var poseRegionPixels: Int? = null
            var silhouettePixels: Int? = null
            var regionPose: Pose? = null
            var hipsEstimated = false
            var chosen: Triple<ByteArray, Int, RegionSource>? = null
            var cutFraction: Double? = null
            var required = floor
            var armPixels: Int? = null
            var armSkinPixels: Int? = null
            var legPixels: Int? = null
            var legSkinPixels: Int? = null
            var sleevePixels: Int? = null
            var sleeveMatchPixels: Int? = null
            var sleevesKept = false
            var bareArmsDropped = false
            val pose = person.pose
            if (pose != null) {
                val planned = RegionPlanning.regionPose(pose, ro.minConfidence)
                try {
                    fun probe(model: SkinModel, opts: SkinOptions, zone: ByteArray): Int {
                        val t0 = nowMs()
                        val r = exclude(zone, model, opts).second
                        out.skinMs += nowMs() - t0
                        return r
                    }
                    val noArms = ro.copy(includeUpperArms = false)
                    // Sin modelo de piel: brazos fuera salvo mangas del torso.
                    if (options.adaptiveSkin && !skinAvailable && ro.includeUpperArms) {
                        val torsoOptions = noArms.copy(includeLegs = false, includeLowerLegs = false)
                        val torso = regions(planned.first, torsoOptions, body)
                        val arms = MaskOps.removed(
                            regions(planned.first, ro, body).first,
                            regions(planned.first, noArms, body).first,
                        )
                        val n = MaskOps.nonZero(arms)
                        sleevePixels = n
                        if (n > 0) {
                            out.arms = arms
                            out.sleeveTorso = torso.first
                            if (torso.second >= MIN_SKIN_SAMPLES && options.sleeveMatchFraction < 1) {
                                val torsoModel = ColorEngine.fitSkinModel(image, torso.first)
                                val match = probe(
                                    torsoModel,
                                    SkinOptions(options.sleeveMatchMahalanobis, 1.0), arms,
                                )
                                sleeveMatchPixels = match
                                sleevesKept = match >= sleeveThreshold(n, options)
                            }
                        }
                        if (!sleevesKept) {
                            ro = noArms
                            upperArmsDropped = true
                        }
                    }
                    var r = regions(planned.first, ro, body)
                    regionPose = planned.first
                    hipsEstimated = planned.second
                    val faceModel = out.model
                    if (faceModel != null) {
                        var armsZone: ByteArray? = null
                        var r0: Pair<ByteArray, Int>? = null
                        var bareArms = false
                        var bareLegs = false
                        if (ro.includeUpperArms) {
                            val without = regions(planned.first, noArms, body)
                            r0 = without
                            val arms = MaskOps.removed(r.first, without.first)
                            val n = MaskOps.nonZero(arms)
                            armPixels = n
                            armSkinPixels = 0
                            if (n > 0) {
                                out.arms = arms
                                armsZone = arms
                                armSkinPixels = probe(faceModel, skinProbe, arms)
                                bareArms = (armSkinPixels ?: 0) >= bareArmsThreshold(n, options)
                            }
                        }
                        if (ro.includeLegs || ro.includeLowerLegs) {
                            val noLegs = ro.copy(includeLegs = false, includeLowerLegs = false)
                            val legs = MaskOps.removed(r.first, regions(planned.first, noLegs, body).first)
                            val n = MaskOps.nonZero(legs)
                            legPixels = n
                            if (n > 0) out.legs = legs
                            legSkinPixels = if (n > 0) probe(faceModel, skinProbe, legs) else 0
                            bareLegs = n > 0 && (legSkinPixels ?: 0) >= bareArmsThreshold(n, options)
                        }
                        // Piel del cuerpo aprendida (hasta N pasadas sobre R).
                        val initialSample = out.sample
                        if ((bareArms || bareLegs) && options.skinLearningIterations > 0 && initialSample != null) {
                            var sample: ByteArray = initialSample
                            val zonePixels = r.second
                            val learnOptions = SkinOptions(options.skinLearningMahalanobis, 1.0)
                            var model: SkinModel = faceModel
                            val learned = ArrayList<ByteArray>()
                            val learnedPx = ArrayList<Int>()
                            for (pass in 0 until options.skinLearningIterations) {
                                val t0 = nowMs()
                                val candidates = exclude(r.first, model, learnOptions)
                                out.skinMs += nowMs() - t0
                                if (candidates.second <= 0) break
                                if (candidates.second > options.skinOptions.maxExcludedFraction * zonePixels) break
                                val grown = MaskOps.union(
                                    listOf(sample, MaskOps.removed(r.first, candidates.first)),
                                ) ?: sample
                                val added = samplePixels(grown) - samplePixels(sample)
                                if (added <= 0) break
                                val t1 = nowMs()
                                val grownModel = ColorEngine.fitSkinModel(image, grown)
                                out.skinMs += nowMs() - t1
                                if (probe(grownModel, skinProbe, r.first) >
                                    options.skinOptions.maxExcludedFraction * zonePixels
                                ) break
                                model = grownModel
                                sample = grown
                                learnedPx.add(candidates.second)
                                learned.add(grown)
                            }
                            if (learned.isNotEmpty()) {
                                out.model = model
                                out.learnedSamples = learned
                                out.learningPixels = learnedPx
                            }
                        }
                        // Brazos desnudos con el modelo final.
                        val armsFinal = armsZone
                        val without = r0
                        val nArms = armPixels
                        val modelFinal = out.model
                        if (armsFinal != null && without != null && nArms != null && modelFinal != null) {
                            if (out.learnedSamples.isNotEmpty()) {
                                armSkinPixels = probe(modelFinal, skinProbe, armsFinal)
                            }
                            if ((armSkinPixels ?: 0) >= bareArmsThreshold(nArms, options)) {
                                bareArmsDropped = true
                                // Swift: ro = noArms ANTES de la silueta.
                                // (El source lo ajusta sobre la variable ro viva.)
                                r = without
                                // La silueta se calcula con las opciones ya sin brazos.
                                // Se refleja asignando ro aquí (ver más abajo).
                                ro = noArms
                            }
                        }
                    }
                    poseRegionPixels = r.second
                    val s = regions(planned.first, RegionPlanning.silhouetteOptions(ro), body)
                    silhouettePixels = s.second
                    out.silhouette = s.first
                    out.steps.add(MaskStep.POSE_REGIONS)
                    if (s.second >= floor) {
                        out.fallback = s.first
                        out.fallbackSource = RegionSource.POSE_SILHOUETTE
                        required = requiredRegionPixels(s.second, options, width, height)
                        chosen = if (r.second >= required) {
                            Triple(r.first, r.second, RegionSource.POSE_REGIONS)
                        } else {
                            Triple(s.first, s.second, RegionSource.POSE_SILHOUETTE)
                        }
                    }
                } catch (e: EngineException.Engine) {
                    if (e.code != EngineException.Engine.ERR_POSE) throw e
                    chosen = null
                }
            }
            if (chosen == null) {
                val fraction = RegionPlanning.cutHeadFraction(bodyStats.bbox, person.faceBox)
                val m = body.copyOf()
                val pixels = ColorEngine.cutHead(m, width, height, fraction)
                chosen = Triple(m, pixels, RegionSource.HEAD_CUT)
                cutFraction = fraction
                out.steps.add(MaskStep.HEAD_CUT)
            }
            val ch = chosen
            if (ch != null) {
                out.finalMask = ch.first
                out.region = ch.first
                out.decision = RegionDecision(
                    source = ch.third, bodyPixels = bodyStats.count, requiredPixels = required,
                    poseRegionPixels = poseRegionPixels, silhouettePixels = silhouettePixels,
                    regionPixels = ch.second, regionPose = regionPose,
                    hipsEstimated = hipsEstimated, headCutFraction = cutFraction,
                    regionOptions = if (regionPose == null) null else ro,
                    upperArmsDropped = upperArmsDropped && regionPose != null,
                    armPixels = armPixels, armSkinPixels = armSkinPixels,
                    bareArmsDropped = bareArmsDropped, legPixels = legPixels,
                    legSkinPixels = legSkinPixels, sleevePixels = sleevePixels,
                    sleeveMatchPixels = sleeveMatchPixels, sleevesKept = sleevesKept,
                )
            }
            out.regionMs += nowMs() - regionStart
        } else {
            out.decision = RegionDecision(
                source = RegionSource.WHOLE_PERSON, bodyPixels = bodyStats.count,
                requiredPixels = floor, poseRegionPixels = null, silhouettePixels = null,
                regionPixels = bodyStats.count, regionPose = null,
                hipsEstimated = false, headCutFraction = null,
            )
        }
        val model = out.model
        if (model != null) {
            val t0 = nowMs()
            val r = exclude(out.finalMask, model, options.skinOptions)
            if (r.third) {
                out.steps.add(MaskStep.SKIN_GUARD)
            } else if (r.second > 0) {
                out.skinExcludedMask = r.first
                val seeds = MaskOps.removed(out.finalMask, r.first)
                var kept = r.first
                var skin = seeds
                // Piel en sombra conectada con la quitada (histéresis).
                if (options.skinGrowRadius > 0 &&
                    options.skinGrowMahalanobis > options.skinOptions.maxMahalanobis
                ) {
                    val weak = exclude(r.first, model, SkinOptions(options.skinGrowMahalanobis, 1.0))
                    out.growCandidates = weak.second
                    if (weak.second > 0) {
                        val candidates = MaskOps.removed(r.first, weak.first)
                        val grown = MaskOps.geodesicGrow(seeds, candidates, width, height, options.skinGrowRadius)
                        val n = MaskOps.nonZero(grown)
                        val limit = options.skinOptions.maxExcludedFraction * MaskOps.nonZero(out.finalMask)
                        if (n > 0 && (r.second + n).toDouble() <= limit && n.toDouble() <= options.skinGrowMaxRatio * r.second) {
                            val keptCopy = kept.copyOf()
                            for (i in keptCopy.indices) if (grown[i] != 0.toByte()) keptCopy[i] = 0
                            kept = keptCopy
                            skin = MaskOps.union(listOf(seeds, grown)) ?: seeds
                            out.grownPixels = n
                            out.grownMask = grown
                        }
                    }
                }
                val halo = MaskOps.removeHalo(kept, skin, width, height, options.skinHaloRadius)
                out.haloPixels = halo.second
                out.removed = MaskOps.removed(out.finalMask, halo.first)
                out.excluded = r.second + out.grownPixels + halo.second
                out.finalMask = halo.first
                out.steps.add(MaskStep.SKIN_EXCLUDED)
            }
            out.skinMs += nowMs() - t0
        }
        return out
    }
}

/**
 * Segmentador completo: detector de plataforma + cadena (SubjectChain).
 * Si el detector falla (modelo ausente, error de MediaPipe), el resultado
 * es "detector no disponible" ([MaskStep.VISION_UNAVAILABLE]) y foto entera,
 * nunca un crash: la misma semántica que visionUnavailable en iOS.
 */
class SubjectChainSegmenter(
    private val detector: PersonDetector,
) : SubjectSegmenter {
    override suspend fun compute(image: EngineImage, options: SubjectOptions): SubjectMaskResult {
        if (options.mode == SubjectMode.OFF) {
            return SubjectMaskResult(
                width = image.width, height = image.height,
                people = emptyList(), chosenIndex = null, mask = null,
                steps = listOf(MaskStep.NONE),
            )
        }
        val detection: PeopleDetectionResult = try {
            val t0 = System.nanoTime()
            val detailed = (detector as? DetailedPersonDetector)?.detectDetailed(image)
                ?: PeopleDetectionResult(detector.detect(image))
            val ms = (System.nanoTime() - t0) / 1_000_000.0
            detailed.copy(timingsMs = detailed.timingsMs + ("detect" to (detailed.timingsMs["detect"] ?: ms)))
        } catch (e: Exception) {
            // El fallo queda en el registro (diagnósticos), nunca como crash.
            android.util.Log.w("SubjectChainSegmenter", "detector no disponible: $e", e)
            return SubjectMaskResult(
                width = image.width, height = image.height,
                people = emptyList(), chosenIndex = null, mask = null,
                steps = listOf(MaskStep.VISION_UNAVAILABLE),
            )
        }
        return SubjectChain.mask(
            detection.people, image, options,
            detectTimingsMs = detection.timingsMs,
            rejected = detection.rejectedPhantoms,
        )
    }

    /** Cadena sobre personas ya detectadas (cambiar de persona sin re-detectar). */
    fun compute(image: EngineImage, people: List<PersonDetection>, options: SubjectOptions): SubjectMaskResult =
        SubjectChain.mask(people, image, options)
}
