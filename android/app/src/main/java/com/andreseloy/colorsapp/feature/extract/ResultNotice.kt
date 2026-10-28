// Aviso del recorte de sujeto y nombres de los pasos: espejo de
// SubjectExplanation.notice / stepTitles (Views/Capas/SubjectExplanation.swift)
// con los datos que el contrato Android de subject/ expone hoy
// (SubjectMaskResult: people, chosenIndex, mask, steps). Lo que en iOS sale
// de PersonLayers (decision de region por persona, donante de piel, brazos
// fuera, fantasmas) no existe aun en el contrato: cuando W2 lo exponga se
// anaden esas partes aqui sin tocar la UI. La UI resuelve los textos.
package com.andreseloy.colorsapp.feature.extract

import com.andreseloy.colorsapp.subject.MaskStep
import com.andreseloy.colorsapp.subject.RegionMode
import com.andreseloy.colorsapp.subject.SubjectMaskResult
import com.andreseloy.colorsapp.subject.SubjectMode
import com.andreseloy.colorsapp.subject.SubjectOptions

/** Una parte del aviso («Solo ropa · piel excluida» se compone de partes). */
sealed interface NoticePart {
    data object OnePerson : NoticePart
    data class AllPeople(val count: Int) : NoticePart
    data class MainOf(val count: Int) : NoticePart
    data class PersonOf(val indexOneBased: Int, val count: Int) : NoticePart
    data object SplitByPose : NoticePart
    data object SplitByFace : NoticePart
    data object ClothingOnly : NoticePart
    data object WholePersonRegion : NoticePart
    data object HeadCutNoPose : NoticePart
    data object SkinGuard : NoticePart
    data object SkinExcluded : NoticePart
    data object TooSmallWholePerson : NoticePart
    data object PersonTooSmall : NoticePart
    data object GarmentRegions : NoticePart
}

/** Aviso completo: o un texto cerrado o una composicion de partes. */
sealed interface MaskNotice {
    val isFallback: Boolean

    enum class Fixed { VISION_UNAVAILABLE, CROP_OFF, NO_PERSON, PERSON }

    data class Whole(val fixed: Fixed, override val isFallback: Boolean) : MaskNotice
    data class Parts(val parts: List<NoticePart>, override val isFallback: Boolean) : MaskNotice
}

object ResultNotice {

    fun notice(options: SubjectOptions, result: SubjectMaskResult): MaskNotice {
        val steps = result.steps
        if (MaskStep.VISION_UNAVAILABLE in steps) {
            return MaskNotice.Whole(MaskNotice.Fixed.VISION_UNAVAILABLE, isFallback = true)
        }
        if (options.mode == SubjectMode.OFF) {
            return MaskNotice.Whole(MaskNotice.Fixed.CROP_OFF, isFallback = false)
        }
        if (result.people.isEmpty() || MaskStep.NO_PEOPLE in steps) {
            return MaskNotice.Whole(MaskNotice.Fixed.NO_PERSON, isFallback = true)
        }
        val parts = mutableListOf<NoticePart>()
        var fallback = false
        val n = result.people.size
        if (options.mode == SubjectMode.ALL_PEOPLE) {
            parts += if (n == 1) NoticePart.OnePerson else NoticePart.AllPeople(n)
        } else if (n >= 2) {
            val index = result.chosenIndex ?: 0
            parts += if (index == 0) NoticePart.MainOf(n) else NoticePart.PersonOf(index + 1, n)
        }
        if (MaskStep.SPLIT_BY_POSE in steps || MaskStep.SPLIT_BY_FACE in steps) {
            parts += if (MaskStep.SPLIT_BY_POSE in steps) {
                NoticePart.SplitByPose
            } else {
                NoticePart.SplitByFace
            }
        }
        // Region: sin la decision por persona del contrato se deduce de los pasos.
        when {
            options.region == RegionMode.WHOLE_PERSON -> parts += NoticePart.WholePersonRegion
            MaskStep.POSE_REGIONS in steps -> parts += NoticePart.ClothingOnly
            MaskStep.HEAD_CUT in steps -> parts += NoticePart.HeadCutNoPose
            MaskStep.WHOLE_PERSON in steps -> parts += NoticePart.WholePersonRegion
        }
        if (MaskStep.SKIN_GUARD in steps) {
            parts += NoticePart.SkinGuard
            fallback = true
        } else if (MaskStep.SKIN_EXCLUDED in steps) {
            parts += NoticePart.SkinExcluded
        }
        if (MaskStep.WHOLE_PERSON in steps && options.region != RegionMode.WHOLE_PERSON) {
            parts += NoticePart.TooSmallWholePerson
            fallback = true
        }
        if (MaskStep.NONE in steps) {
            parts += NoticePart.PersonTooSmall
            fallback = true
        }
        if (MaskStep.GARMENT_REGIONS in steps) {
            parts += NoticePart.GarmentRegions
        }
        if (parts.isEmpty()) {
            return MaskNotice.Whole(MaskNotice.Fixed.PERSON, isFallback = fallback)
        }
        return MaskNotice.Parts(parts, isFallback = fallback)
    }

    /** Titulos de los pasos tal como ocurrieron (REJECTED_PHANTOM sin conteo: se omite). */
    fun stepKinds(result: SubjectMaskResult): List<MaskStep> =
        result.steps.filter { it != MaskStep.REJECTED_PHANTOM }

    /** Primera letra en mayuscula (MaskStepsText.capitalizedFirst). */
    fun capitalizedFirst(text: String): String =
        text.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
}
