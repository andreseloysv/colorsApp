# R8: conservar el puente JNI (nombres de método = símbolos Java_* en ce_jni.c).
-keep class com.andreseloy.colorsapp.engine.EngineNative {
    native <methods>;
}
