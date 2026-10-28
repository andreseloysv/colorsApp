# Rendimiento y tamaño en Android (carril W6)

Medido en el teléfono del dueño: Samsung Galaxy A14 (SM-A145R, Android 15,
Exynos 1330: 2×A78 + 6×A55, Mali-G68 MP2), con el test instrumentado
`SubjectPeopleDeviceTest#peoplePhotosVsIosReference` (las 9 fotos de
`harness/people`, misma cadena que la app: detector + SubjectChain +
motor). Sin `connectedAndroidTest`: APKs instalados a mano y
`am instrument`, para no desinstalar la app del teléfono.

**Advertencia de método (térmica):** tras varias pasadas seguidas el A14
baja frecuencias y los tiempos absolutos suben hasta ~1,5× (lo delata
YuNet, de código intacto entre variantes: 170 ms en frío, 220–450 ms en
caliente). Por eso la comparación que manda es el **A/B alternado en las
mismas condiciones** (baseline compilado del HEAD previo a W6 contra el
build optimizado, dos pasadas de cada uno con 120 s de enfriamiento
entre ellas). Los absolutos «en frío» se dan aparte, de la primera
pasada del día con cada variante.

## Puertas de no regresión (todas cumplidas)

Mismo top-3 que el baseline en las 9 fotos, mismo conteo de personas y
ΔIoU por persona **0,000** frente a la referencia de iOS (las
optimizaciones no cambian ningún píxel de decisión: se limitan a no
ejecutar modelos cuya salida no puede cambiar el resultado y a
reutilizar tareas). Lo verifican el test de cadena (en A/B y en frío) y
el nuevo `YuNetParityDeviceTest`.

## Foto única: antes / después

En frío solo hay absolutos comparables del baseline (primera pasada
del día: 4,74–9,46 s, mediana 6,97 s; coincide con el 4,9–9,3 s del
informe W2). Del optimizado hay una pasada en frío de la variante
intermedia (perezosos + tareas calientes, aún con YuNet-ORT): mediana
4,32 s (1,78–6,91 s). La variante final suma el sobrecoste medido de
YuNet-TFLite (+0,28 s/foto, ver «Tamaño»), así que su absoluto en frío
estimado es ≈4,6 s de mediana (≈2,1 s la foto simple 08). Etiquetado
como estimación: tras un día de pasadas el teléfono no volvió al estado
térmico de la mañana (sensor SoC en 55 °C con batería a 29 °C) y las
pasadas «en frío» tardías reproducen los valores del A/B en caliente.
La comparación que manda es el A/B siguiente.

A/B alternado (mediana de 2 pasadas por variante, teléfono caliente;
ratios = optimizado/baseline):

| Foto | Personas | Baseline | Optimizado | Ratio |
|---|---:|---:|---:|---:|
| 01 single black outfit | 1 | 10,61 s | 6,87 s | 0,65 |
| 02 single dress umbrella | 1 | 10,29 s | 6,51 s | 0,63 |
| 03 couple denim street | 3 | 11,21 s | 9,43 s | 0,84 |
| 04 two women backlit | 2 | 8,45 s | 7,40 s | 0,88 |
| 05 three friends closeup | 2 | 11,38 s | 6,70 s | 0,59 |
| 06 group courier street | 5 | 12,12 s | 10,20 s | 0,84 |
| 07 group mural white outfits | 7 | 14,56 s | 11,63 s | 0,80 |
| 08 artist colorful mural | 1 | 7,60 s | 3,06 s | 0,40 |
| synthetic tight selfie | 2 | 9,64 s | 8,87 s | 0,92 |
| **Mediana** | | **10,61 s** | **7,40 s** | **0,70** |

Por fases (mediana de las fotos 2–9, mismo A/B):

| Fase | Baseline | Optimizado | Por qué |
|---|---:|---:|---|
| `vision.pose` | 1.858 ms | 660 ms | tarea caliente reutilizada (crear la tarea costaba ~0,5–1,2 s por foto) |
| `vision.face` (YuNet) | 222 ms | 454 ms | TFLite en vez de ORT (ver «Tamaño»): +230 ms a cambio de −15 MB |
| `vision.humanRectangles` | 1.691 ms | 1.231 ms | caliente + solo cuando una semilla/rescate/fantasma lo necesita (mediana mezclada con los «skip») |
| `vision.multiclass` | 1.833 ms | 586 ms | caliente + solo para rescate/respaldo de piel (antes: siempre) |
| `vision.masks` (MagicTouch) | 2.519 ms | 2.491 ms | sin cambio medible: es inferencia pura por persona |
| `detect` total | 9.757 ms | 7.602 ms | |

Frecuencia real de los modelos «de respaldo» en las 9 fotos: EfficientDet
corre en 6/9 (semillas de cara sin evidencia por articulaciones) y el
multiclass en 4/9 (respaldo de piel; solo *aporta* muestra en 2/9,
`skinBackupUsed`). En las fotos donde se saltan (01, 02, 08) el ahorro
es el mayor (ratio 0,40–0,65).

### ¿Se llega a ≤ 2,5 s por foto? No con este hardware y estos modelos.

Ni en frío: solo la foto simple 08 (1 persona, sin EfficientDet ni
multiclass) baja a ≈2,1 s estimados; un grupo de 5–7 personas paga
5–7 inferencias MagicTouch (~0,55–0,9 s cada una) más pose y cadena y
se queda en ≈6–7 s estimados en frío. El suelo medido por foto con
1 persona, descomponiendo la pasada en frío, es aproximadamente:
pose ≥0,24 s + caras 0,45 s + 1 máscara ≥0,55 s + cadena/motor
(regiones+piel+match en C) 0,5–1,3 s. Bajar de ahí exige cambiar de
modelos (pose lite, segmentador de instancias en una pasada) o de
runtime (LiteRT a pelo con delegado GPU propio), decisiones de producto
que cambian resultados y quedan para el dueño (ver «Descartado»).

Desglose del calentamiento (primera foto tras arrancar el proceso): la
pose paga la carga del `.task` y la compilación de grafos una sola vez
(ya incluido en la foto 01 de cada pasada; en el baseline se pagaba en
**cada** foto porque cada tarea se creaba y cerraba por foto).

## Escaneo día 0 (200 fotos)

`ScanPerfDeviceTest#day0Scan200Photos`: inserta 200 JPEG variados en un
álbum propio de MediaStore (`Pictures/ChromaSolW6Test`; 30 con personas
de `harness/people` y 170 escenas sintéticas sin personas), los escanea
por el camino real de miniaturas de 256 px (`loadThumbnail` +
`MediaStoreScanRunner.scanBitmaps`, 3 en paralelo, un `ce_ctx` por
tarea, cancelable como en iOS) y **borra las 200 URIs al final** (también
si el test falla). No enumera el carrete del dueño.

Medido en caliente, baseline y optimizado seguidos (mismo test
compilado contra cada variante; conteos de pasos idénticos en ambos,
0 fallos):

| Grupo | Baseline | Optimizado |
|---|---:|---:|
| 30 con personas | 8,18 s/foto (243 s) | 5,32 s/foto (157 s) |
| 170 sin personas | 4,96 s/foto (831 s) | 0,70 s/foto (107 s) |
| **200 mezcladas (15 % personas)** | **5,44 s/foto (18,1 min)** | **1,39 s/foto (4,6 min)** |

Miniaturas incluidas (≈67–70 ms/foto en ambos). El baseline pagaba la
creación de las 4 tareas MediaPipe en **cada** foto aunque no hubiera
nadie (4,96 s por una escena vacía); el optimizado sale tras pose+caras
sin hallazgos (0,70 s). ¿≤1 s/foto? En fotos sin personas sí (0,70 s en
caliente); mezclado con 15 % de fotos con personas queda 1,39 s/foto
porque una foto con personas a 256 px cuesta casi lo mismo que a 1024
(los modelos trabajan a su resolución interna y la cadena es la misma
que en foto única, como en iOS). Bajar de ahí exigiría un camino de
escaneo distinto del de foto única (p. ej., sin MagicTouch en el
escaneo), que cambiaría los `scans` guardados frente al análisis
completo: no hecho sin el dueño. El calentamiento (primera foto del
proceso) baja de 8,5 s a 6,2 s y se paga una vez por escaneo.

## Tamaño

Descarga por ABI según Play (`bundletool get-size total`, device-spec
arm64-v8a/es/420 dpi/API 35) y APK de depuración completo:

| Artefacto | Antes | Después |
|---|---:|---:|
| AAB `get-size total` (arm64) | 54.292.501 B (51,8 MiB) | 49.143.854 B (46,9 MiB) |
| Split arm64 (fichero .apk) | 28 MiB | 14 MiB |
| AAB completo (2 ABIs) | 67 MiB | 57 MiB |
| APK debug (2 ABIs) | 117 MiB | 87 MiB |

Qué cambió: **fuera ONNX Runtime**. `libonnxruntime.so` +
`libonnxruntime4j_jni.so` costaban 18,5 MB sin comprimir por ABI para
correr un modelo de 232 KB. YuNet se convirtió a TFLite float32 desde
el ONNX fijado por sha256 (`android/tools/convert_yunet.py`, onnx2tf
2.6.9; el `.tflite` de 236.564 B va versionado en
`assets/models/` porque no tiene URL oficial) y corre con el intérprete
TFLite (`libtensorflowlite_jni.so` arm64: 3,55 MB). Paridad validada en
el Mac contra ORT sobre las 9 fotos: tensores con |Δ|máx 1,3e-5, mismas
caras y cajas a 0,00 px; en el dispositivo, ΔIoU final 0,000. Precio:
la inferencia de caras sube de ~170 a ~450 ms (probado: 8 hilos igual;
NNAPI 240 ms pero compila 9,6 s en el primer uso de cada proceso).

Lo que queda dentro (split base, sin comprimir): modelos de sujeto
44,1 MB (selfie_multiclass 16,4 + efficientdet_lite2 12,1 + pose_full
9,4 + magic_touch 6,2), `libmediapipe_tasks_jni.so` 10,5 MB, dex 3,1 MB,
motor C 0,5 MB, tipografías 1,1 MB.

### datatransport: no se puede quitar limpio con MediaPipe Tasks

Las clases `com.google.android.datatransport` (api+runtime+cct ≈ 284 KB
de `classes.jar` antes de R8; coste de tamaño despreciable, el problema
es de ficha de privacidad) las arrastra tasks-vision y W2 ya comprobó
en el AVD que excluir el grupo o solo el backend CCT rompe `TaskRunner`
con `NoClassDefFoundError` al crear cualquier tarea
(`TasksStatsProtoLogger → RemoteLoggingClient → CctDestination`).
Siguen neutralizadas como dejó W2: el manifiesto elimina
INTERNET/ACCESS_NETWORK_STATE en la fusión y `make android-lint`
verifica el APK release sin permisos de red. Quitarlas del todo exige
dejar MediaPipe Tasks y hablar con LiteRT directamente (grafos,
pre/post-procesado y asociaciones de los 4 modelos a mano; también
quitaría de golpe la fragilidad de timestamps de Tasks). Es un
cambio de arquitectura de días, con riesgo de paridad en cada modelo:
**no hecho; decisión para el dueño.**

Oportunidades no ejecutadas (cambian modelos fijados por el informe B;
requieren decisión del dueño): selfie_multiclass en float16 oficial
(~−8 MB, toca el respaldo de piel), pose_landmarker_lite (~−3,7 MB,
toca los landmarks de todas las fotos).

## Descartado con números

- **Delegado GPU de MediaPipe**: en el A14 (Mali, tasks 0.10.35)
  InteractiveSegmenter muere con abort nativo al convertir el resultado
  y EfficientDet en `tensors_to_detections` (check 1 vs 90 clases),
  sin excepción Java que capturar → sin respaldo posible. El mecanismo
  queda tras el flag `preferGpu=false` con lista negra por modelo.
- **Detección a 640 px** (raster del motor intacto a 1024): sin
  ganancia clara de tiempo y rompiendo puertas (07: 7→6 personas y otro
  top-3; 08: cambia el orden del top-3; ΔIoU hasta −0,216). Mecanismo
  presente pero desactivado (`detectMaxSide=0`).
- **YuNet en paralelo con la pose**: medido peor (2 núcleos grandes;
  MediaPipe/XNNPACK ya satura la CPU). Vuelto a serie.
- **MPImage compartida entre puntos interactivos**: sin ganancia
  medible (la copia cara ocurre dentro del grafo). Vuelto al original.

## Otros cambios del carril

- Informe W2: los `String.format` del test van con `Locale.US`
  (salían comas decimales y el JSON era inválido);
  `docs/research/w2-report-galaxy-a14.json` regenerado válido.
- IDs de scan: `PhotoAnalyzer.makeScanRecord` usa el UUIDv7 de W1
  (`UuidV7.string(nowMs)`) en vez de `UUID.randomUUID()` (v4). Queda
  una segunda implementación v7 local en
  `feature/extract/ScanAnalyzer.newScanId` (paquete de W5): mismo
  formato, sin el contador monotónico de W1; conviene unificarla.
- Robustez de la pose caliente: el fallo de máscara float / *timestamp
  mismatch* al reutilizar la tarea se reintenta una vez con tarea
  fresca; si también muere, el tamaño de raster queda memorizado como
  «sin máscaras de pose» (la instancia sale de MagicTouch, como ya
  pasaba en el baseline con 02/03/05).

## Cómo repetir las mediciones

```sh
# Foto única (9 de harness/people) y paridad YuNet, en el A14:
cd android
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=~/Library/Android/sdk ./gradlew --console=plain \
  -Dorg.gradle.jvmargs=-Xmx3g -Dorg.gradle.workers.max=3 \
  :app:assembleDebug :app:assembleDebugAndroidTest
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB -s R8YW50R482L install -r app/build/outputs/apk/debug/app-debug.apk
$ADB -s R8YW50R482L install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
$ADB -s R8YW50R482L shell am instrument -w \
  -e class com.andreseloy.colorsapp.subject.SubjectPeopleDeviceTest#peoplePhotosVsIosReference \
  com.andreseloy.colorsapp.test/androidx.test.runner.AndroidJUnitRunner
$ADB -s R8YW50R482L pull /sdcard/Android/data/com.andreseloy.colorsapp/files/w2/w2-report.json .
$ADB -s R8YW50R482L shell am instrument -w \
  -e class com.andreseloy.colorsapp.subject.YuNetParityDeviceTest \
  com.andreseloy.colorsapp.test/androidx.test.runner.AndroidJUnitRunner
# Escaneo 200 (se autoborra de MediaStore):
$ADB -s R8YW50R482L shell am instrument -w \
  -e class com.andreseloy.colorsapp.scan.ScanPerfDeviceTest \
  com.andreseloy.colorsapp.test/androidx.test.runner.AndroidJUnitRunner
$ADB -s R8YW50R482L pull /sdcard/Android/data/com.andreseloy.colorsapp/files/w6/scan200.json .
# Tamaño:
make android-bundle   # desde la raíz
bundletool build-apks --bundle=android/app/build/outputs/bundle/release/app-release.aab \
  --output=build-android/size/final.apks --device-spec=build-android/size/arm64.json
bundletool get-size total --apks=build-android/size/final.apks \
  --device-spec=build-android/size/arm64.json
# con {"supportedAbis":["arm64-v8a"],"supportedLocales":["es"],"screenDensity":420,"sdkVersion":35}
```
