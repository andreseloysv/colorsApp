# R8 de release: ofuscación y reducción activas. Los métodos JNI se conservan
# con las consumer-rules de :engine (EngineNative). MediaPipe sí usa reflexión: ver abajo.

# MediaPipe Tasks lee sus mensajes protobuf-lite por reflexión (nombres de campo como
# `platform_`): si R8 los renombra, el detector de personas falla en release y la app cae
# a la foto completa sin avisar. Se conservan MediaPipe y protobuf enteros.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite { <fields>; }
-dontwarn com.google.mediapipe.**
-dontwarn com.google.protobuf.**
# Flogger (logs de MediaPipe) localiza a quien llama recorriendo la pila por nombre de clase:
# ofuscado falla con «no caller found on the stack» al crear el grafo. TaskRunner usa además
# datatransport (sin permiso de red, ver AndroidManifest) y Guava.
-keep class com.google.common.flogger.** { *; }
-keep class com.google.common.** { *; }
-keep class com.google.android.datatransport.** { *; }
-dontwarn com.google.common.**
-dontwarn com.google.android.datatransport.**
