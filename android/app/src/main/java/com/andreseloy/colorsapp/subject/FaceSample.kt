// Port literal de apple/SubjectKit/Sources/SubjectKit/FaceSample.swift:
// muestra de piel de la cara (mejillas y frente) como polígonos convexos en
// el marco afín P(s,t) = M + s·h + t·w (M = media de ojos, h = (ojoB-ojoA)/2,
// w = boca - M). Solo geometría; el modelo de piel lo ajusta el motor C.
// En Android los puntos vienen de YuNet (2 ojos, nariz, 2 comisuras): la
// boca es la media de comisuras; sin cejas se usa c=-0,32 y sin contorno no
// hay recorte por envolvente (el respaldo está medido en el §5.4 del informe).
package com.andreseloy.colorsapp.subject

import kotlin.math.abs
import kotlin.math.sqrt

/** Landmarks de una cara en píxeles del raster (origen arriba-izquierda). */
data class FaceLandmarkPoints(
    val leftEye: List<Pt>,
    val rightEye: List<Pt>,
    val leftEyebrow: List<Pt> = emptyList(),
    val rightEyebrow: List<Pt> = emptyList(),
    val outerLips: List<Pt>,
    val faceContour: List<Pt> = emptyList(),
    val boundingBox: RectD? = null,
) {
    /** Centro para asociar la cara: centro de la caja o media de los ojos. */
    val center: Pt
        get() {
            val box = boundingBox
            if (box != null && !box.isEmpty) return Pt(box.midX, box.midY)
            val a = FaceSample.centroid(leftEye) ?: Pt(0.0, 0.0)
            val b = FaceSample.centroid(rightEye) ?: Pt(0.0, 0.0)
            return Pt((a.x + b.x) / 2, (a.y + b.y) / 2)
        }
}

/** Polígonos de muestra de piel. */
object FaceSample {
    // Cuadrilátero de la mejilla en coordenadas (s, t) para el lado +1.
    private val CHEEK = listOf(
        0.62 to 0.28, 1.38 to 0.28, 1.32 to 0.72, 0.68 to 0.72,
    )
    private const val FOREHEAD_HALF_WIDTH = 0.8
    private const val FOREHEAD_NEAR = 0.08
    private const val FOREHEAD_FAR = 0.32
    private const val DEFAULT_BROW_TOP = -0.32

    /** Margen sobre el borde superior de la caja de cara (fracción de su alto). */
    private const val FOREHEAD_BOX_MARGIN = 0.05

    /** Erosión (px) de la máscara de persona al recortar la muestra. */
    private const val PERSON_CLIP_EROSION = 2

    fun centroid(pts: List<Pt>): Pt? {
        val valid = pts.filter { it.x.isFinite() && it.y.isFinite() }
        if (valid.isEmpty()) return null
        var sx = 0.0
        var sy = 0.0
        for (p in valid) {
            sx += p.x
            sy += p.y
        }
        return Pt(sx / valid.size, sy / valid.size)
    }

    /**
     * Polígonos (mejilla A, mejilla B, frente) en píxeles del raster; null si
     * faltan ojos o labios o el marco es degenerado (< 1 px o casi colineal).
     */
    fun polygons(lm: FaceLandmarkPoints): List<List<Pt>>? {
        val ea = centroid(lm.leftEye) ?: return null
        val eb = centroid(lm.rightEye) ?: return null
        val mouth = centroid(lm.outerLips) ?: return null
        val mx = (ea.x + eb.x) / 2
        val my = (ea.y + eb.y) / 2
        val hx = (eb.x - ea.x) / 2
        val hy = (eb.y - ea.y) / 2
        val wx = mouth.x - mx
        val wy = mouth.y - my
        val hn = sqrt(hx * hx + hy * hy)
        val wn = sqrt(wx * wx + wy * wy)
        val det = hx * wy - hy * wx
        if (hn < 0.5 || wn < 1 || abs(det) < 0.2 * hn * wn) return null
        fun point(s: Double, t: Double): Pt = Pt(mx + s * hx + t * wx, my + s * hy + t * wy)
        fun tCoord(p: Pt): Double = (hx * (p.y - my) - hy * (p.x - mx)) / det
        val hull = MaskOps.convexHull(lm.faceContour)
        val result = ArrayList<List<Pt>>()
        for (sigma in listOf(-1.0, 1.0)) {
            var poly = CHEEK.map { point(sigma * it.first, it.second) }
            if (hull.size >= 3) poly = MaskOps.intersectConvex(poly, hull)
            result.add(poly)
        }
        val brows = (lm.leftEyebrow + lm.rightEyebrow).filter { it.x.isFinite() && it.y.isFinite() }
        val browTop = if (brows.isEmpty()) DEFAULT_BROW_TOP else brows.minOf { tCoord(it) }
        val near = browTop - FOREHEAD_NEAR
        val far = browTop - FOREHEAD_FAR
        var forehead = listOf(
            point(-FOREHEAD_HALF_WIDTH, near), point(FOREHEAD_HALF_WIDTH, near),
            point(FOREHEAD_HALF_WIDTH, far), point(-FOREHEAD_HALF_WIDTH, far),
        )
        val box = lm.boundingBox
        if (box != null && !box.isEmpty) {
            val top = box.minY - FOREHEAD_BOX_MARGIN * box.height
            val rect = listOf(
                Pt(box.minX, top), Pt(box.maxX, top), Pt(box.maxX, box.maxY), Pt(box.minX, box.maxY),
            )
            forehead = MaskOps.intersectConvex(forehead, rect)
        }
        result.add(forehead)
        return result
    }

    /** Máscara de muestra (255 dentro de mejillas/frente y de la persona). */
    fun mask(lm: FaceLandmarkPoints, width: Int, height: Int, personMask: ByteArray?): ByteArray? {
        val polys = polygons(lm) ?: return null
        return MaskOps.fillConvexPolygons(
            polys, width, height,
            clip = personMask, clipErosion = if (personMask == null) 0 else PERSON_CLIP_EROSION,
        )
    }
}
