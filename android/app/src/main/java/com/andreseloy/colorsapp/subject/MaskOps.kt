// Port literal de apple/SubjectKit/Sources/SubjectKit/MaskOps.swift:
// operaciones de máscara sin color (recuento, bbox, unión, dilatación,
// crecimiento geodésico, halo, polígonos convexos). Nada de lógica de color:
// eso vive en el motor C. Las máscaras son width*height bytes sin stride,
// 0..255, origen arriba-izquierda; el centro del píxel (i,j) es (i+0.5, j+0.5).
package com.andreseloy.colorsapp.subject

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** Punto en píxeles del raster (CGPoint de SubjectKit). */
data class Pt(val x: Double, val y: Double)

/** Rectángulo en píxeles del raster (CGRect): origen + tamaño. */
data class RectD(val x: Double, val y: Double, val width: Double, val height: Double) {
    val minX: Double get() = x
    val minY: Double get() = y
    val maxX: Double get() = x + width
    val maxY: Double get() = y + height
    val midX: Double get() = x + width / 2
    val midY: Double get() = y + height / 2
    val isEmpty: Boolean get() = width <= 0 || height <= 0
    val isFinite: Boolean
        get() = x.isFinite() && y.isFinite() && width.isFinite() && height.isFinite()

    fun contains(p: Pt): Boolean = p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY

    companion object {
        val ZERO = RectD(0.0, 0.0, 0.0, 0.0)
    }
}

/** Resultado de MaskOps.stats: recuento >=128, cobertura y bbox en píxeles. */
data class MaskStats(val count: Int, val coverage: Double, val bbox: RectD)

object MaskOps {
    /** Umbral de "dentro" para cobertura, bbox y asociaciones. */
    const val INSIDE_THRESHOLD = 128

    fun u(b: Byte): Int = b.toInt() and 0xFF

    /** Cobertura (fracción >= 128) y bbox de los píxeles >= 128. */
    fun stats(mask: ByteArray, width: Int, height: Int): MaskStats {
        if (width < 1 || height < 1 || mask.size < width * height) return MaskStats(0, 0.0, RectD.ZERO)
        var count = 0
        var minX = Int.MAX_VALUE
        var minY = Int.MAX_VALUE
        var maxX = -1
        var maxY = -1
        for (y in 0 until height) {
            val row = y * width
            for (x in 0 until width) {
                if (u(mask[row + x]) >= INSIDE_THRESHOLD) {
                    count++
                    if (x < minX) minX = x
                    if (x > maxX) maxX = x
                    if (y < minY) minY = y
                    if (y > maxY) maxY = y
                }
            }
        }
        if (count == 0) return MaskStats(0, 0.0, RectD.ZERO)
        val bbox = RectD(
            minX.toDouble(), minY.toDouble(),
            (maxX - minX + 1).toDouble(), (maxY - minY + 1).toDouble(),
        )
        return MaskStats(count, count.toDouble() / (width * height), bbox)
    }

    fun coverage(mask: ByteArray, width: Int, height: Int): Double =
        stats(mask, width, height).coverage

    /** Píxeles > 0 (la cuenta que devuelven las funciones de máscara del motor). */
    fun nonZero(mask: ByteArray): Int {
        var n = 0
        for (v in mask) if (v != 0.toByte()) n++
        return n
    }

    /** Máscara binaria: 255 donde mask >= 128, 0 en el resto. */
    fun binarize(mask: ByteArray): ByteArray {
        val out = ByteArray(mask.size)
        for (i in mask.indices) if (u(mask[i]) >= INSIDE_THRESHOLD) out[i] = -1 // 255
        return out
    }

    /** Máximo por píxel; null si no hay máscaras. */
    fun union(masks: List<ByteArray>): ByteArray? {
        var out = masks.firstOrNull()?.copyOf() ?: return null
        for (m in masks.drop(1)) {
            val n = min(out.size, m.size)
            for (i in 0 until n) if (u(m[i]) > u(out[i])) out[i] = m[i]
        }
        return out
    }

    /** 255 donde before > 0 y after == 0. */
    fun removed(before: ByteArray, after: ByteArray): ByteArray {
        val out = ByteArray(before.size)
        val n = min(before.size, after.size)
        for (i in 0 until n) if (before[i] != 0.toByte() && after[i] == 0.toByte()) out[i] = -1
        return out
    }

    /** Dilatación binaria Chebyshev (cuadrado 2r+1), dos pasadas separables. */
    fun dilate(mask: ByteArray, width: Int, height: Int, radius: Int): ByteArray {
        val count = width * height
        if (width < 1 || height < 1 || mask.size < count) return ByteArray(max(0, count))
        var out = ByteArray(count)
        for (i in 0 until count) if (mask[i] != 0.toByte()) out[i] = -1
        val r = max(0, radius)
        if (r == 0) return out
        val tmp = ByteArray(count)
        for (y in 0 until height) {
            val row = y * width
            var inWindow = 0
            for (x in 0 until min(width, r + 1)) if (out[row + x] != 0.toByte()) inWindow++
            for (x in 0 until width) {
                if (inWindow > 0) tmp[row + x] = -1
                val add = x + r + 1
                val drop = x - r
                if (add < width && out[row + add] != 0.toByte()) inWindow++
                if (drop >= 0 && out[row + drop] != 0.toByte()) inWindow--
            }
        }
        val result = ByteArray(count)
        for (x in 0 until width) {
            var inWindow = 0
            for (y in 0 until min(height, r + 1)) if (tmp[y * width + x] != 0.toByte()) inWindow++
            for (y in 0 until height) {
                if (inWindow > 0) result[y * width + x] = -1
                val add = y + r + 1
                val drop = y - r
                if (add < height && tmp[add * width + x] != 0.toByte()) inWindow++
                if (drop >= 0 && tmp[drop * width + x] != 0.toByte()) inWindow--
            }
        }
        return result
    }

    /** Píxeles de allowed alcanzables desde seeds en <= radius pasos (8-vecindad). */
    fun geodesicGrow(seeds: ByteArray, allowed: ByteArray, width: Int, height: Int, radius: Int): ByteArray {
        val count = width * height
        if (width < 1 || height < 1 || seeds.size < count || allowed.size < count) {
            return ByteArray(max(0, count))
        }
        val out = ByteArray(count)
        if (radius <= 0) return out
        val visited = BooleanArray(count)
        var frontier = ArrayList<Int>()
        for (i in 0 until count) if (seeds[i] != 0.toByte()) {
            visited[i] = true
            frontier.add(i)
        }
        var step = 0
        while (frontier.isNotEmpty() && step < radius) {
            val next = ArrayList<Int>()
            for (i in frontier) {
                val x = i % width
                val y = i / width
                for (dy in -1..1) {
                    val yy = y + dy
                    if (yy < 0 || yy >= height) continue
                    for (dx in -1..1) {
                        if (dx == 0 && dy == 0) continue
                        val xx = x + dx
                        if (xx < 0 || xx >= width) continue
                        val j = yy * width + xx
                        if (!visited[j] && allowed[j] != 0.toByte()) {
                            visited[j] = true
                            out[j] = -1
                            next.add(j)
                        }
                    }
                }
            }
            frontier = next
            step++
        }
        return out
    }

    /** Halo: pone a 0 los píxeles de mask a Chebyshev <= radius de around. */
    fun removeHalo(mask: ByteArray, around: ByteArray, width: Int, height: Int, radius: Int): Pair<ByteArray, Int> {
        if (radius <= 0 || nonZero(around) == 0) return mask to 0
        val grown = dilate(around, width, height, radius)
        val out = mask.copyOf()
        var removed = 0
        val n = min(out.size, grown.size)
        for (i in 0 until n) if (grown[i] != 0.toByte() && out[i] != 0.toByte()) {
            out[i] = 0
            removed++
        }
        return out to removed
    }

    /** Mapa de instancias: id (1..255) de la persona con mayor valor >=128. */
    fun instanceOverlay(people: List<PersonDetection>, width: Int, height: Int): ByteArray {
        val count = width * height
        val out = ByteArray(count)
        val best = IntArray(count)
        for (p in people) {
            val m = p.instanceMask.bytes
            if (m.size < count) continue
            val label = max(1, min(255, p.id))
            for (i in 0 until count) {
                val v = u(m[i])
                if (v >= INSIDE_THRESHOLD && v > best[i]) {
                    best[i] = v
                    out[i] = label.toByte()
                }
            }
        }
        return out
    }

    /** Valor de la máscara en el píxel que contiene (x, y); 0 fuera del raster. */
    fun value(mask: ByteArray, width: Int, height: Int, x: Double, y: Double): Int {
        if (!x.isFinite() || !y.isFinite() || x < 0 || y < 0) return 0
        val ix = floor(x).toInt()
        val iy = floor(y).toInt()
        if (ix >= width || iy >= height || mask.size < width * height) return 0
        return u(mask[iy * width + ix])
    }

    /** Rasteriza polígonos convexos en el centro de cada píxel, con clip opcional. */
    fun fillConvexPolygons(
        polygons: List<List<Pt>>, width: Int, height: Int,
        clip: ByteArray? = null, clipErosion: Int = 0,
    ): ByteArray {
        val out = ByteArray(width * height)
        for (poly in polygons) {
            if (poly.size < 3) continue
            var minXf = Double.POSITIVE_INFINITY
            var maxXf = Double.NEGATIVE_INFINITY
            var minYf = Double.POSITIVE_INFINITY
            var maxYf = Double.NEGATIVE_INFINITY
            var finite = true
            for (p in poly) {
                if (!p.x.isFinite() || !p.y.isFinite()) { finite = false; break }
                if (p.x < minXf) minXf = p.x
                if (p.x > maxXf) maxXf = p.x
                if (p.y < minYf) minYf = p.y
                if (p.y > maxYf) maxYf = p.y
            }
            if (!finite) continue
            val x0 = max(0, floor(minXf - 0.5).toInt())
            val x1 = min(width - 1, kotlin.math.ceil(maxXf - 0.5).toInt())
            val y0 = max(0, floor(minYf - 0.5).toInt())
            val y1 = min(height - 1, kotlin.math.ceil(maxYf - 0.5).toInt())
            if (x0 > x1 || y0 > y1) continue
            for (y in y0..y1) {
                for (x in x0..x1) {
                    val i = y * width + x
                    if (out[i] != 0.toByte()) continue
                    if (clip != null && !insideEroded(clip, width, height, x, y, clipErosion)) continue
                    if (pointInConvexPolygon(Pt(x + 0.5, y + 0.5), poly)) out[i] = -1
                }
            }
        }
        return out
    }

    /** true si el cuadrado (2r+1)² centrado en (x,y) está todo >=128 y dentro. */
    fun insideEroded(mask: ByteArray, width: Int, height: Int, x: Int, y: Int, radius: Int): Boolean {
        if (mask.size < width * height) return false
        val r = max(0, radius)
        if (x - r < 0 || y - r < 0 || x + r >= width || y + r >= height) return false
        for (yy in (y - r)..(y + r)) {
            for (xx in (x - r)..(x + r)) {
                if (u(mask[yy * width + xx]) < INSIDE_THRESHOLD) return false
            }
        }
        return true
    }

    /** true si p está dentro o sobre el borde de un polígono convexo. */
    fun pointInConvexPolygon(p: Pt, poly: List<Pt>): Boolean {
        if (poly.size < 3) return false
        var sign = 0
        for (i in poly.indices) {
            val a = poly[i]
            val b = poly[(i + 1) % poly.size]
            val cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if (cross > 0) {
                if (sign < 0) return false
                sign = 1
            } else if (cross < 0) {
                if (sign > 0) return false
                sign = -1
            }
        }
        return true
    }

    /** Envolvente convexa (monotone chain), sin puntos colineales. */
    fun convexHull(points: List<Pt>): List<Pt> {
        val pts = points.filter { it.x.isFinite() && it.y.isFinite() }
            .sortedWith(compareBy({ it.x }, { it.y }))
        if (pts.size < 3) return pts
        fun cross(o: Pt, a: Pt, b: Pt): Double =
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        val lower = ArrayList<Pt>()
        for (p in pts) {
            while (lower.size >= 2 && cross(lower[lower.size - 2], lower[lower.size - 1], p) <= 0) {
                lower.removeAt(lower.size - 1)
            }
            lower.add(p)
        }
        val upper = ArrayList<Pt>()
        for (p in pts.reversed()) {
            while (upper.size >= 2 && cross(upper[upper.size - 2], upper[upper.size - 1], p) <= 0) {
                upper.removeAt(upper.size - 1)
            }
            upper.add(p)
        }
        return lower.dropLast(1) + upper.dropLast(1)
    }

    /** Intersección de dos polígonos convexos (Sutherland–Hodgman). */
    fun intersectConvex(subject: List<Pt>, clipper: List<Pt>): List<Pt> {
        if (subject.size < 3 || clipper.size < 3) return emptyList()
        var area = 0.0
        for (i in clipper.indices) {
            val a = clipper[i]
            val b = clipper[(i + 1) % clipper.size]
            area += a.x * b.y - b.x * a.y
        }
        val orient = if (area >= 0) 1.0 else -1.0
        var output = subject
        for (i in clipper.indices) {
            if (output.isEmpty()) break
            val a = clipper[i]
            val b = clipper[(i + 1) % clipper.size]
            fun inside(p: Pt): Boolean =
                orient * ((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)) >= 0
            fun intersection(p: Pt, q: Pt): Pt {
                val d1 = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
                val d2 = (b.x - a.x) * (q.y - a.y) - (b.y - a.y) * (q.x - a.x)
                val t = d1 / (d1 - d2)
                return Pt(p.x + t * (q.x - p.x), p.y + t * (q.y - p.y))
            }
            val input = output
            val next = ArrayList<Pt>()
            for (j in input.indices) {
                val cur = input[j]
                val prev = input[(j + input.size - 1) % input.size]
                if (inside(cur)) {
                    if (!inside(prev)) next.add(intersection(prev, cur))
                    next.add(cur)
                } else if (inside(prev)) {
                    next.add(intersection(prev, cur))
                }
            }
            output = next
        }
        return if (output.size >= 3) output else emptyList()
    }
}
