// Conversion de descriptores a texto localizado (la parte de FeedModel /
// ResultNotice que en Swift hace String(localized:)). Todo sale de
// strings_w3.xml, volcado del catalogo de iOS sin inventar copia.
package com.andreseloy.colorsapp.feature.extract

import android.content.res.Resources
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.engine.GarmentRegion
import com.andreseloy.colorsapp.feature.feed.CropNotice
import com.andreseloy.colorsapp.feature.feed.PaletteTitleKind
import com.andreseloy.colorsapp.feature.feed.PersonLabel
import com.andreseloy.colorsapp.feature.feed.RegionTextKind
import com.andreseloy.colorsapp.subject.MaskStep
import java.util.Locale

/** Locale del idioma de la UI (para numeros y minusculas como en iOS). */
@Composable
fun w3Locale(): Locale =
    androidx.compose.ui.platform.LocalConfiguration.current.locales[0] ?: Locale.ROOT

fun numberLabel(resources: Resources, comboId: Int): String =
    resources.getString(R.string.w3_number_label, W3Format.paddedComboId(comboId))

@Composable
fun numberLabel(comboId: Int): String =
    stringResource(R.string.w3_number_label, W3Format.paddedComboId(comboId))

/** «Nº 067 · 2 colores» (DesignFormat.comboSubtitle). */
@Composable
fun comboSubtitle(comboId: Int, size: Int): String {
    val count = if (size == 1) {
        stringResource(R.string.w3_color_count_one_fmt, size)
    } else {
        stringResource(R.string.w3_colors_count, size)
    }
    return "${numberLabel(comboId)} · $count"
}

/** 0,392 -> «39 %» (DesignFormat.percent, espacio duro del recurso). */
@Composable
fun percentText(weight: Double): String =
    stringResource(R.string.w3_percent_int, W3Format.percentInt(weight))

/** Fraccion de cobertura con 1 decimal: «12,3 %» (SubjectExplanation.percent). */
@Composable
fun percentFractionText(fraction: Double, digits: Int = 1): String {
    val locale = w3Locale()
    return W3Format.percentValue(fraction, digits, locale) + "\u00A0%"
}

/** Etiqueta larga de la region de prenda (GarmentText.regionLabel). */
fun garmentRegionLabel(resources: Resources, region: GarmentRegion): String =
    resources.getString(
        when (region) {
            GarmentRegion.UPPER -> R.string.w3_region_upper
            GarmentRegion.LOWER -> R.string.w3_region_lower
            GarmentRegion.WHOLE -> R.string.w3_region_whole
            GarmentRegion.NONE -> R.string.w3_region_garment
        },
    )

/** Etiqueta corta por codigo de region (GarmentText.shortRegionLabel). */
fun garmentShortLabel(resources: Resources, regionCode: Int): String =
    resources.getString(
        when (regionCode) {
            GarmentRegion.UPPER.code -> R.string.w3_region_upper_short
            GarmentRegion.LOWER.code -> R.string.w3_region_lower_short
            GarmentRegion.WHOLE.code -> R.string.w3_region_whole
            else -> R.string.w3_region_garment
        },
    )

@Composable
fun personLabelText(label: PersonLabel): String = when (label) {
    PersonLabel.WholePhoto -> stringResource(R.string.w3_whole_photo)
    PersonLabel.OnePerson -> stringResource(R.string.w3_one_person)
    is PersonLabel.AllPeople -> stringResource(R.string.w3_all_people_n, label.count)
    is PersonLabel.MainOf -> stringResource(R.string.w3_main_person_of, label.count)
    is PersonLabel.PersonOf ->
        stringResource(R.string.w3_person_i_of_n, label.indexOneBased, label.count)
}

@Composable
fun paletteTitleText(kind: PaletteTitleKind): String = stringResource(
    when (kind) {
        PaletteTitleKind.GARMENTS -> R.string.w3_palette_garments
        PaletteTitleKind.CLOTHING -> R.string.w3_palette_clothing
        PaletteTitleKind.PERSON -> R.string.w3_palette_person
        PaletteTitleKind.PHOTO -> R.string.w3_palette_photo
    },
)

/** Texto del aviso corto del recorte (FeedPostText.cropNotice). */
@Composable
fun cropNoticeText(notice: CropNotice): String {
    val locale = w3Locale()
    return when (notice) {
        is CropNotice.WholePhoto -> stringResource(R.string.w3_whole_photo)
        CropNotice.WholePersonFallback -> stringResource(R.string.w3_whole_person)
        is CropNotice.Region -> {
            var text = stringResource(
                when (notice.kind) {
                    RegionTextKind.CLOTHING -> R.string.w3_clothing_only
                    RegionTextKind.WHOLE_PERSON -> R.string.w3_whole_person
                    RegionTextKind.PERSON -> R.string.w3_person
                },
            )
            if (notice.allPeopleCount != null) {
                text = stringResource(
                    R.string.w3_all_people_with, notice.allPeopleCount,
                    text.lowercase(locale),
                )
            }
            if (notice.skinExcluded) {
                text = stringResource(R.string.w3_with_skin_excluded, text)
            }
            text
        }
    }
}

/** Texto del aviso de Resultado (SubjectExplanation.notice). */
@Composable
fun maskNoticeText(notice: MaskNotice): String = when (notice) {
    is MaskNotice.Whole -> stringResource(
        when (notice.fixed) {
            MaskNotice.Fixed.VISION_UNAVAILABLE -> R.string.w3_notice_vision_unavailable
            MaskNotice.Fixed.CROP_OFF -> R.string.w3_notice_crop_off
            MaskNotice.Fixed.NO_PERSON -> R.string.w3_notice_no_person
            MaskNotice.Fixed.PERSON -> R.string.w3_person
        },
    )
    is MaskNotice.Parts -> ResultNotice.capitalizedFirst(
        notice.parts.map { noticePartText(it) }.joinToString(" · "),
    )
}

@Composable
private fun noticePartText(part: NoticePart): String = when (part) {
    NoticePart.OnePerson -> stringResource(R.string.w3_one_person)
    is NoticePart.AllPeople -> stringResource(R.string.w3_all_people_n, part.count)
    is NoticePart.MainOf -> stringResource(R.string.w3_main_person_of, part.count)
    is NoticePart.PersonOf ->
        stringResource(R.string.w3_person_i_of_n, part.indexOneBased, part.count)
    NoticePart.SplitByPose -> stringResource(R.string.w3_notice_split_pose)
    NoticePart.SplitByFace -> stringResource(R.string.w3_notice_split_face)
    NoticePart.ClothingOnly -> stringResource(R.string.w3_region_clothing_lower)
    NoticePart.WholePersonRegion -> stringResource(R.string.w3_region_person_lower)
    NoticePart.HeadCutNoPose -> stringResource(R.string.w3_notice_head_cut_no_pose)
    NoticePart.SkinGuard -> stringResource(R.string.w3_notice_skin_guard)
    NoticePart.SkinExcluded -> stringResource(R.string.w3_notice_skin_excluded)
    NoticePart.TooSmallWholePerson -> stringResource(R.string.w3_notice_small_person)
    NoticePart.PersonTooSmall -> stringResource(R.string.w3_notice_person_too_small)
    NoticePart.GarmentRegions -> stringResource(R.string.w3_notice_garment_regions)
}

/** Nombre de un paso de la cadena (SubjectExplanation.stepTitles, subconjunto). */
@Composable
fun stepTitleText(step: MaskStep): String = stringResource(
    when (step) {
        MaskStep.NONE -> R.string.w3_step_none
        MaskStep.NO_PEOPLE -> R.string.w3_step_no_people
        MaskStep.POSE_REGIONS -> R.string.w3_step_pose_regions
        MaskStep.HEAD_CUT -> R.string.w3_step_head_cut
        MaskStep.WHOLE_PERSON -> R.string.w3_step_whole_person
        MaskStep.SKIN_EXCLUDED -> R.string.w3_step_skin_excluded
        MaskStep.SKIN_GUARD -> R.string.w3_step_skin_guard
        MaskStep.VISION_UNAVAILABLE -> R.string.w3_step_vision_unavailable
        MaskStep.REJECTED_PHANTOM -> R.string.w3_step_none
        MaskStep.GARMENT_REGIONS -> R.string.w3_step_garment_regions
        MaskStep.SPLIT_BY_POSE -> R.string.w3_step_split_pose
        MaskStep.SPLIT_BY_FACE -> R.string.w3_step_split_face
    },
)

/** Etiqueta accesible de un color: «Color 1 de 5, Black, #222524, 39 por ciento». */
@Composable
fun colorAccessibilityLabel(color: PaletteColor, position: Int, total: Int): String {
    val parts = mutableListOf(stringResource(R.string.w3_color_i_of_n, position + 1, total))
    color.name?.let { parts += it }
    parts += color.hex
    color.weight?.let {
        parts += stringResource(R.string.w3_percent_words, W3Format.percentInt(it))
    }
    return parts.joinToString(", ")
}
