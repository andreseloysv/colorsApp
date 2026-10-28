// Aplicación: crea el AppContainer una vez (ColorsAppApp de iOS).
package com.andreseloy.colorsapp.app

import android.app.Application

class ColorsApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer.bootstrap(this)
    }
}
