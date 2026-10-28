// Versión de la política de análisis de un scan: espejo de
// ios/ColorsApp/DB/AnalysisPolicy.swift. La columna
// `scans.engine_policy_version` (migración v4) guarda [CURRENT] en el
// momento del análisis; [needsReanalysis] compara esa versión, la del motor
// y la del diccionario con las actuales. Aquí solo está el criterio, para
// que sea el mismo en todas las pantallas.
package com.andreseloy.colorsapp.data

import com.andreseloy.colorsapp.engine.colorEngineVersion
import com.andreseloy.colorsapp.engine.dictionaryVersion

object AnalysisPolicy {
    /**
     * Versión actual. Se SUBE cuando cambia algo que altera el resultado de
     * un scan sin cambiar la versión del motor: valores por defecto del
     * match, la cadena de máscaras o el camino de paleta.
     *
     * 1 (2026-09-16): match sin hipótesis de iluminante, recorte por defecto
     * persona más grande + solo ropa + piel adaptativa y paleta por prenda
     * con el mapa de regiones de la pose cuando lo hay; sin pose, camino
     * clásico. null en la base de datos = anterior a v4: se re-analiza.
     */
    const val CURRENT: Int = 1

    /**
     * true si [scan] se analizó con una política, un motor o un diccionario
     * distintos de los dados (o antes de que existiera la columna). Los
     * scans manuales (sin foto) no tienen nada que re-analizar.
     *
     * Las versiones se inyectan para poder probar el criterio sin el motor
     * nativo; en la app las pasa quien ya las leyó del motor.
     */
    fun needsReanalysis(
        scan: ScanRecord,
        engineVersion: String,
        dictVersion: String,
        policyVersion: Int = CURRENT,
    ): Boolean {
        if (scan.source == ScanSource.MANUAL) return false
        val version = scan.enginePolicyVersion ?: return true
        return version != policyVersion ||
            scan.engineVersion != engineVersion ||
            scan.dictVersion != dictVersion
    }

    /** Versión de producción: compara contra el motor C de esta build. */
    fun needsReanalysis(scan: ScanRecord): Boolean =
        needsReanalysis(scan, colorEngineVersion, dictionaryVersion)
}

/** Atajo sobre el registro, como `ScanRecord.needsReanalysis` en iOS. */
fun ScanRecord.needsReanalysis(
    engineVersion: String,
    dictVersion: String,
    policyVersion: Int = AnalysisPolicy.CURRENT,
): Boolean = AnalysisPolicy.needsReanalysis(this, engineVersion, dictVersion, policyVersion)
