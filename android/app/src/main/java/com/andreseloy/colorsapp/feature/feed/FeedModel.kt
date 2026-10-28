// Logica pura del Feed: espejo de ios/ColorsApp/Views/Feed/FeedModel.swift
// (filtros, combinacion del dia, textos de la publicacion) y de FeedItem
// (FeedComponents.swift). Sin vistas ni base de datos y SIN logica de color:
// el nombre de Wada mas cercano viene del motor via PaletteColor. Los textos
// localizables se resuelven en la UI desde estos descriptores (kinds), igual
// que el Swift compone String(localized:) en el modelo.
package com.andreseloy.colorsapp.feature.feed

import com.andreseloy.colorsapp.data.FeedbackVerdict
import com.andreseloy.colorsapp.data.ScanRecord
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.data.WadaDictionary
import com.andreseloy.colorsapp.feature.extract.AnalysisPolicy
import com.andreseloy.colorsapp.feature.extract.PaletteColor
import com.andreseloy.colorsapp.feature.extract.ScanJson
import com.andreseloy.colorsapp.subject.MaskStep
import com.andreseloy.colorsapp.subject.RegionMode
import com.andreseloy.colorsapp.subject.SubjectMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.random.Random

/* ---------------- Filtros ---------------- */

/** Chips del Feed: todo, por tamano de la ganadora, guardadas y por votar. */
enum class FeedFilter {
    ALL, TWO, THREE, FOUR, SAVED, UNVOTED;

    val comboSize: Int?
        get() = when (this) {
            TWO -> 2
            THREE -> 3
            FOUR -> 4
            else -> null
        }

    fun includes(top1Size: Int?, verdict: FeedbackVerdict?, isSaved: Boolean): Boolean =
        when (this) {
            ALL -> true
            TWO, THREE, FOUR -> top1Size == comboSize
            SAVED -> isSaved
            UNVOTED -> verdict == null
        }
}

/* ---------------- Combinacion del dia ---------------- */

object DayPick {
    /** Dias desde 1970-01-01 de la fecha LOCAL (sin horas). */
    fun localDaysSince1970(date: LocalDate): Long = date.toEpochDay()

    /** Combinacion del dia: (diasDesde1970 x 7919) mod count + 1, en fecha local. */
    fun comboId(daysSince1970: Long, count: Int): Int {
        if (count <= 0) return 1
        val c = count.toLong()
        val product = Math.floorMod(daysSince1970, c) * Math.floorMod(7919L, c)
        return (Math.floorMod(product, c)).toInt() + 1
    }

    fun comboId(date: LocalDate, count: Int): Int = comboId(localDaysSince1970(date), count)

    /** Otra combinacion distinta de [current] (aleatoriedad de interfaz, no del motor). */
    fun another(current: Int, count: Int, random: Random = Random.Default): Int {
        if (count <= 1) return 1
        val pick = random.nextInt(1, count)
        return if (pick >= current) pick + 1 else pick
    }
}

/* ---------------- Nombres ---------------- */

object FeedComboName {
    /**
     * Nombre de una combinacion: curado si lo hay; si no, los nombres de Wada
     * de sus dos primeros colores. null = la UI ensena «Nº 067». (Los nombres
     * propuestos de ComboNaming llegan con el diccionario JSON de W1/W4.)
     */
    fun name(comboId: Int, dictionary: WadaDictionary): String? {
        dictionary.curatedName(comboId)?.let { return it }
        val names = dictionary.colorsOf(comboId).take(2).map { it.name }
        return if (names.isEmpty()) null else names.joinToString(" · ")
    }
}

/** Resumen del top-1 para el pie «Se parece a» (ComboMatchSummary de iOS). */
data class ComboMatchSummary(
    val comboId: Int,
    /** null = se ensena el numero («Nº 067»). */
    val name: String?,
    val colors: List<PaletteColor>,
    val ambiguousWithTop2: Boolean,
) {
    val size: Int get() = colors.size
}

/* ---------------- Origen ---------------- */

/** Origen de una publicacion (PostSource de Cards.swift). */
enum class PostSource {
    LIBRARY, CAMERA, PICKED;

    companion object {
        fun of(source: ScanSource): PostSource = when (source) {
            ScanSource.LIBRARY -> LIBRARY
            ScanSource.CAMERA -> CAMERA
            ScanSource.PICKER, ScanSource.MANUAL -> PICKED
        }
    }
}

/* ---------------- Textos de la publicacion (descriptores) ---------------- */

sealed interface PersonLabel {
    data object WholePhoto : PersonLabel
    data object OnePerson : PersonLabel
    data class AllPeople(val count: Int) : PersonLabel
    data class MainOf(val count: Int) : PersonLabel
    data class PersonOf(val indexOneBased: Int, val count: Int) : PersonLabel
}

enum class PaletteTitleKind { GARMENTS, CLOTHING, PERSON, PHOTO }

enum class RegionTextKind { CLOTHING, WHOLE_PERSON, PERSON }

/**
 * Aviso corto del recorte sobre la foto (FeedPostText.cropNotice): la UI lo
 * convierte en texto con los recursos, componiendo igual que el Swift.
 */
sealed interface CropNotice {
    val isFallback: Boolean

    data class WholePhoto(override val isFallback: Boolean) : CropNotice
    data object WholePersonFallback : CropNotice {
        override val isFallback: Boolean = true
    }

    data class Region(
        val kind: RegionTextKind,
        /** N si es «Todas las personas (N) · …»; null en caso contrario. */
        val allPeopleCount: Int?,
        val skinExcluded: Boolean,
        override val isFallback: Boolean,
    ) : CropNotice
}

object FeedPostText {

    /** Persona analizada; null en scans anteriores al recorte de sujeto. */
    fun person(scan: ScanRecord): PersonLabel? {
        val raw = scan.subjectMode ?: return null
        val mode = SubjectMode.fromRaw(raw)
        val steps = ScanJson.decodeSteps(scan.maskStepsJson)
        val n = scan.peopleCount ?: 0
        if (mode == SubjectMode.OFF ||
            MaskStep.VISION_UNAVAILABLE in steps || MaskStep.NO_PEOPLE in steps || n == 0
        ) {
            return PersonLabel.WholePhoto
        }
        if (mode == SubjectMode.ALL_PEOPLE) {
            return if (n == 1) PersonLabel.OnePerson else PersonLabel.AllPeople(n)
        }
        if (n == 1) return PersonLabel.OnePerson
        val index = scan.personIndex ?: 0
        return if (index == 0) PersonLabel.MainOf(n) else PersonLabel.PersonOf(index + 1, n)
    }

    /** Aviso del recorte; null en scans anteriores a v2. */
    fun cropNotice(scan: ScanRecord): CropNotice? {
        val raw = scan.subjectMode ?: return null
        val mode = SubjectMode.fromRaw(raw)
        val region = RegionMode.entries.firstOrNull { it.raw == scan.regionMode }
        val steps = ScanJson.decodeSteps(scan.maskStepsJson)
        if (mode == SubjectMode.OFF) return CropNotice.WholePhoto(isFallback = false)
        if (MaskStep.VISION_UNAVAILABLE in steps || MaskStep.NO_PEOPLE in steps ||
            MaskStep.NONE in steps || (scan.maskCoverage ?: 0.0) <= 0.0
        ) {
            return CropNotice.WholePhoto(isFallback = true)
        }
        if (MaskStep.WHOLE_PERSON in steps) return CropNotice.WholePersonFallback
        val kind = when (region) {
            RegionMode.CLOTHING -> RegionTextKind.CLOTHING
            RegionMode.WHOLE_PERSON -> RegionTextKind.WHOLE_PERSON
            else -> RegionTextKind.PERSON
        }
        val allCount = scan.peopleCount?.takeIf { mode == SubjectMode.ALL_PEOPLE && it >= 2 }
        return CropNotice.Region(
            kind = kind,
            allPeopleCount = allCount,
            skinExcluded = MaskStep.SKIN_EXCLUDED in steps,
            isFallback = MaskStep.SKIN_GUARD in steps,
        )
    }

    fun paletteTitleKind(scan: ScanRecord, hasGarments: Boolean): PaletteTitleKind {
        if (hasGarments) return PaletteTitleKind.GARMENTS
        val raw = scan.subjectMode
        if (raw == null || SubjectMode.fromRaw(raw) == SubjectMode.OFF ||
            (scan.maskCoverage ?: 0.0) <= 0.0
        ) {
            return PaletteTitleKind.PHOTO
        }
        val steps = ScanJson.decodeSteps(scan.maskStepsJson)
        if (MaskStep.WHOLE_PERSON in steps || scan.regionMode == RegionMode.WHOLE_PERSON.raw) {
            return PaletteTitleKind.PERSON
        }
        return PaletteTitleKind.CLOTHING
    }

    fun isOutdated(scan: ScanRecord, engineVersion: String, dictVersion: String): Boolean =
        AnalysisPolicy.needsReanalysis(scan, engineVersion, dictVersion)

    /**
     * Fecha de la cabecera: «14 sept, 10:45» este ano y «14 sept 2025, 10:45»
     * en anos anteriores, en el idioma del sistema (FeedPostText.date).
     */
    fun dateText(epochMs: Long, locale: Locale, zone: ZoneId, nowMs: Long): String {
        val date = Instant.ofEpochMilli(epochMs).atZone(zone)
        val now = Instant.ofEpochMilli(nowMs).atZone(zone)
        val pattern = if (date.year == now.year) "d MMM, HH:mm" else "d MMM yyyy, HH:mm"
        return DateTimeFormatter.ofPattern(pattern, locale).withZone(zone).format(date)
    }
}

/* ---------------- Publicacion ---------------- */

/** Lo que pinta una publicacion, calculado una vez por version del scan (rev). */
data class FeedItemData(
    val scan: ScanRecord,
    val palette: List<PaletteColor>,
    val match: ComboMatchSummary?,
    val top1Size: Int?,
    val person: PersonLabel?,
    val notice: CropNotice?,
    val paletteTitle: PaletteTitleKind,
    val isOutdated: Boolean,
) {
    val id: String get() = scan.id
}

object FeedItemBuilder {
    /**
     * @param garmentShortLabel etiqueta corta localizada de una region de
     * prenda (GarmentText.shortRegionLabel), resuelta por la UI.
     */
    fun build(
        scan: ScanRecord,
        dictionary: WadaDictionary,
        garmentShortLabel: (regionCode: Int) -> String,
        engineVersion: String,
        dictVersion: String,
    ): FeedItemData {
        val garments = ScanJson.decodeGarments(scan.garmentsJson)
        val palette: List<PaletteColor> = if (garments.isNotEmpty()) {
            garments.mapIndexedNotNull { i, e ->
                PaletteColor.fromHex(i, e.hex, name = garmentShortLabel(e.region), weight = e.weight)
            }
        } else {
            ScanJson.decodePalette(scan.paletteJson).mapIndexedNotNull { i, e ->
                PaletteColor.fromHex(i, e.hex, weight = e.weight)?.namedByNearestWada(dictionary)
            }
        }
        val match = scan.top1?.takeIf { dictionary.combo(it) != null }?.let { top1 ->
            ComboMatchSummary(
                comboId = top1,
                name = FeedComboName.name(top1, dictionary),
                colors = PaletteColor.combo(top1, dictionary),
                ambiguousWithTop2 = scan.ambiguous && scan.top2 != null,
            )
        }
        return FeedItemData(
            scan = scan,
            palette = palette,
            match = match,
            top1Size = scan.top1?.let { dictionary.combo(it)?.size },
            person = FeedPostText.person(scan),
            notice = FeedPostText.cropNotice(scan),
            paletteTitle = FeedPostText.paletteTitleKind(scan, garments.isNotEmpty()),
            isOutdated = FeedPostText.isOutdated(scan, engineVersion, dictVersion),
        )
    }
}

/* ---------------- Onboarding del escaneo ---------------- */

object FeedOnboarding {
    /** Presentar la hoja: solo si el escaneo inicial no se ha hecho ni saltado. */
    fun shouldPresent(initialScanDone: Boolean, skipped: Boolean): Boolean =
        !initialScanDone && !skipped
}
