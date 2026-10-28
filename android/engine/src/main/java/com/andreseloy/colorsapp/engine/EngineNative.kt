// Declaraciones JNI del motor de color. Los símbolos Java_* viven en
// src/main/cpp/ce_jni.c; no renombrar sin tocar el C y consumer-rules.pro.
// Las opciones viajan como DoubleArray en el orden documentado en ce_jni.c.
package com.andreseloy.colorsapp.engine

internal object EngineNative {
    init {
        System.loadLibrary("colorengine")
    }

    external fun nativeVersion(): String
    external fun nativeDictVersion(): String
    external fun nativeDictNumColors(): Int
    external fun nativeDictNumCombos(): Int
    external fun nativeContextSize(): Long
    external fun nativeCreateContext(): Long
    external fun nativeDestroyContext(handle: Long)
    external fun nativeDefaults(): DoubleArray

    external fun nativeSrgb8ToLab(r: Int, g: Int, b: Int): DoubleArray
    external fun nativeLabToSrgb8(l: Double, a: Double, b: Double): IntArray
    external fun nativeDe2000(
        l1: Double, a1: Double, b1: Double,
        l2: Double, a2: Double, b2: Double,
    ): Double

    external fun nativeDe2000K(
        l1: Double, a1: Double, b1: Double,
        l2: Double, a2: Double, b2: Double,
        kL: Double, kC: Double, kH: Double,
    ): Double

    external fun nativeDe76(
        l1: Double, a1: Double, b1: Double,
        l2: Double, a2: Double, b2: Double,
    ): Double

    external fun nativeDictColorRgb(index: Int): IntArray
    external fun nativeDictColorName(index: Int): String?
    external fun nativeDictColorLab(index: Int): DoubleArray
    external fun nativeDictCombo(id: Int): IntArray
    external fun nativeNearestColor(l: Double, a: Double, b: Double): DoubleArray
    external fun nativeReducedDims(w: Int, h: Int, maxSide: Int): IntArray

    external fun nativeExtractPalette(
        handle: Long, pixels: ByteArray, w: Int, h: Int, stride: Int, fmt: Int,
        mask: ByteArray?, paletteOpts: DoubleArray?, outLabW: DoubleArray, outRgb: IntArray,
    ): Int

    external fun nativeMatch(
        handle: Long, swLabW: DoubleArray, nSw: Int, matchOpts: DoubleArray?,
        topK: Int, outIds: IntArray, outScores: DoubleArray, outMeta: IntArray,
    ): Int

    external fun nativeAnalyze(
        handle: Long, pixels: ByteArray, w: Int, h: Int, stride: Int, fmt: Int,
        mask: ByteArray?, paletteOpts: DoubleArray?, matchOpts: DoubleArray?,
        outLabW: DoubleArray, outRgb: IntArray, outIds: IntArray, outScores: DoubleArray,
        outMeta: IntArray, outHash: LongArray,
    ): Int

    external fun nativeExtractGarments(
        handle: Long, pixels: ByteArray, w: Int, h: Int, stride: Int, fmt: Int,
        mask: ByteArray?, regionMap: ByteArray?, nRegions: Int,
        paletteOpts: DoubleArray?, garmentOpts: DoubleArray?,
        outLabW: DoubleArray, outRgb: IntArray, outShare: DoubleArray, outInts: IntArray,
    ): Int

    external fun nativeAnalyzeGarments(
        handle: Long, pixels: ByteArray, w: Int, h: Int, stride: Int, fmt: Int,
        mask: ByteArray?, regionMap: ByteArray?, nRegions: Int,
        paletteOpts: DoubleArray?, garmentOpts: DoubleArray?, matchOpts: DoubleArray?,
        outLabW: DoubleArray, outRgb: IntArray, outShare: DoubleArray, outInts: IntArray,
        outIds: IntArray, outScores: DoubleArray, outMeta: IntArray, outHash: LongArray,
    ): Int

    external fun nativeExplain(
        handle: Long, swLabW: DoubleArray, nSw: Int, matchOpts: DoubleArray?, comboId: Int,
        outMain: DoubleArray, outInts: IntArray,
        outPsIdx: IntArray, outPsDe: DoubleArray,
        outPcIdx: IntArray, outPcSw: IntArray, outPcDe: DoubleArray,
    ): Int

    external fun nativePaletteDebugInfo(
        handle: Long, outInts: IntArray, outDbls: DoubleArray,
        outClLabW: DoubleArray, outClRgb: IntArray, outClInts: IntArray,
    ): Int

    external fun nativeDebugMap(handle: Long, kind: Int, out: ByteArray): Int

    external fun nativeClothingRegions(
        pose: DoubleArray, regionOpts: DoubleArray?, mask: ByteArray, w: Int, h: Int,
    ): Int

    external fun nativeGarmentRegions(
        pose: DoubleArray, regionOpts: DoubleArray?, personMask: ByteArray, w: Int, h: Int,
        regionsOut: ByteArray,
    ): Int

    external fun nativeCutHead(mask: ByteArray, w: Int, h: Int, fraction: Double): Int

    external fun nativeSkinFit(
        pixels: ByteArray, w: Int, h: Int, stride: Int, fmt: Int, sampleMask: ByteArray,
        outModel: DoubleArray, outN: IntArray,
    ): Int

    external fun nativeExcludeSkin(
        pixels: ByteArray, w: Int, h: Int, stride: Int, fmt: Int, model: DoubleArray,
        modelN: Int, skinOpts: DoubleArray?, mask: ByteArray,
    ): Int

    external fun nativeSplitInstance(
        mask: ByteArray, w: Int, h: Int, seeds: DoubleArray, nSeeds: Int, labelsOut: ByteArray,
    ): Int

    external fun nativeSwatchHash(swLabW: DoubleArray, nSw: Int): Long
    external fun nativeGarmentHash(
        swLabW: DoubleArray, share: DoubleArray, ints: IntArray, nSw: Int,
    ): Long

    external fun nativeResultHash(
        swLabW: DoubleArray, nSw: Int, hitIds: IntArray, hitScores: DoubleArray,
        nHits: Int, ambiguous: Int,
    ): Long
}
