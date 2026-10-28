// Mapeo BlazePose (33 landmarks de MediaPipe) -> ce_pose (15 puntos), el
// del §5.1 del informe del carril B (proto.py: to_ce_pose), medido contra
// Vision. Índices BlazePose: 0 nariz, 11/12 hombros, 13/14 codos, 15/16
// muñecas, 23/24 caderas, 25/26 rodillas, 27/28 tobillos ("izquierda" = la
// de la persona, igual que Vision). cuello = media de hombros y raíz =
// media de caderas, con la confianza menor de la pareja. La confianza es la
// `visibility` tal cual (lo que el prototipo midió; el motor solo exige un
// escalar comparable con 0,3). Sin volteo de y: MediaPipe ya normaliza con
// origen arriba-izquierda.
package com.andreseloy.colorsapp.subject

import com.andreseloy.colorsapp.engine.Joint
import com.andreseloy.colorsapp.engine.Keypoint
import com.andreseloy.colorsapp.engine.Pose
import kotlin.math.min

/** Landmark normalizado de BlazePose (x, y en [0,1] nominal; puede salirse). */
data class BlazeLandmark(val x: Double, val y: Double, val visibility: Double, val presence: Double = 1.0)

object BlazePoseMapping {
    /** Nº de landmarks que devuelve Pose Landmarker. */
    const val LANDMARK_COUNT = 33

    private fun kp(lm: BlazeLandmark, width: Int, height: Int): Keypoint =
        Keypoint(lm.x * width, lm.y * height, lm.visibility)

    private fun mid(a: BlazeLandmark, b: BlazeLandmark, width: Int, height: Int): Keypoint =
        Keypoint(
            (a.x + b.x) / 2 * width, (a.y + b.y) / 2 * height,
            min(a.visibility, b.visibility),
        )

    /** Pose del motor en píxeles del raster desde los 33 landmarks. */
    fun toCePose(landmarks: List<BlazeLandmark>, width: Int, height: Int): Pose {
        require(landmarks.size >= 29) { "BlazePose: ${landmarks.size} landmarks" }
        val joints = MutableList(Joint.entries.size) { Keypoint.MISSING }
        fun set(joint: Joint, index: Int) {
            joints[joint.ordinal] = kp(landmarks[index], width, height)
        }
        set(Joint.NOSE, 0)
        set(Joint.LEFT_SHOULDER, 11)
        set(Joint.RIGHT_SHOULDER, 12)
        set(Joint.LEFT_ELBOW, 13)
        set(Joint.RIGHT_ELBOW, 14)
        set(Joint.LEFT_WRIST, 15)
        set(Joint.RIGHT_WRIST, 16)
        set(Joint.LEFT_HIP, 23)
        set(Joint.RIGHT_HIP, 24)
        set(Joint.LEFT_KNEE, 25)
        set(Joint.RIGHT_KNEE, 26)
        set(Joint.LEFT_ANKLE, 27)
        set(Joint.RIGHT_ANKLE, 28)
        joints[Joint.NECK.ordinal] = mid(landmarks[11], landmarks[12], width, height)
        joints[Joint.ROOT.ordinal] = mid(landmarks[23], landmarks[24], width, height)
        return Pose(joints)
    }
}
