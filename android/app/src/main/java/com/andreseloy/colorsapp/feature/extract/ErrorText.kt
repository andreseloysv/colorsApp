// Mensajes de error de la UI: espejo de ios/ColorsApp/Views/Feed/ErrorText.swift
// para los errores que existen en Android (motor, escaneo, imagen ilegible).
package com.andreseloy.colorsapp.feature.extract

import android.content.res.Resources
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.engine.EngineException
import com.andreseloy.colorsapp.scan.ScanException

object ErrorText {
    fun describe(resources: Resources, error: Throwable): String = when (error) {
        is EngineException.Engine ->
            resources.getString(R.string.w3_error_engine, error.code)

        is EngineException.BufferTooSmall ->
            resources.getString(R.string.w3_error_buffer, error.actual, error.required)

        is EngineException.MaskTooSmall ->
            resources.getString(R.string.w3_error_mask, error.actual, error.required)

        is ScanException.NotImplemented ->
            resources.getString(R.string.w3_error_scan_not_implemented)

        is ScanException.Cancelled ->
            resources.getString(R.string.w3_error_scan_cancelled)

        is UnreadableImageException ->
            resources.getString(R.string.w3_error_unreadable)

        else -> error.localizedMessage ?: resources.getString(R.string.w3_error_unreadable)
    }
}

/** La foto elegida no se ha podido decodificar (ImageLoadingError de iOS). */
class UnreadableImageException : Exception("unreadable")
